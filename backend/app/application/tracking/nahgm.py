"""NAHGM — Node-Aligned Haversine Geofenced Monitoring.

Answers two questions from a stream of GPS positions:

    where on the route is this van?      (node-aligned map matching)
    when will it reach the next stops?   (node-based ETA)

**Map matching.** A raw coordinate says nothing about route progress. The
module computes haversine distance from the reported position to every
terminal node in the route's ordered sequence and greedily selects the
nearest. That node establishes where the van sits along the sequence,
which is what turns a latitude/longitude pair into "just left Digos."

**ETA.** Remaining distance is the sum of node-to-node haversine hops
from the current position onward. Speed comes from recent pings when
available, falling back to the route's own planned schedule -- the
`offset_minutes` on each stop already encodes how long the cooperative
expects each section to take, which is a better default than a guessed
constant.

The honest framing for the manuscript: haversine distance and
nearest-node selection are textbook. What is being claimed is their
application to fixed-route cooperative operations, not the mathematics.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.audit import auto_trigger
from app.application.operations.check_in import haversine_m
from app.core.exceptions import ConflictError, NotFoundError
from app.core.timezone import APP_TZ, localize
from app.domain.enums import AuditTrigger, TripStatus
from app.infrastructure.models import (
    RouteStop,
    Terminal,
    Trip,
    TripLocationPing,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

# Below this, a van is treated as stopped rather than crawling -- GPS
# jitter on a parked vehicle otherwise produces a nonsensical ETA.
MIN_MOVING_KPH = 5.0
# How many recent pings feed the rolling speed estimate.
SPEED_WINDOW = 5


@dataclass(frozen=True)
class StopEta:
    stop_sequence: int
    terminal_id: str
    terminal_name: str
    distance_m: float
    eta: datetime | None
    minutes_away: int | None


@dataclass(frozen=True)
class VanPosition:
    trip_id: str
    van_id: str | None
    plate_number: str | None
    latitude: float
    longitude: float
    speed_kph: float | None
    heading_deg: float | None
    nearest_stop_sequence: int | None
    nearest_stop_name: str | None
    distance_to_stop_m: float | None
    recorded_at: datetime
    is_stale: bool
    seconds_since_report: int
    etas: list[StopEta]


class TrackingService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.policies = PolicyRepository(session)

    # ------------------------------------------------------------------
    async def record_ping(
        self,
        *,
        trip_id: str,
        latitude: float,
        longitude: float,
        accuracy_m: float | None = None,
        speed_kph: float | None = None,
        heading_deg: float | None = None,
        recorded_at: datetime | None = None,
    ) -> dict:
        """Store one position report and map-match it to the route."""
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")
        if trip.status in (TripStatus.CANCELLED.value, TripStatus.COMPLETED.value):
            raise ConflictError(f"Trip is {trip.status}; tracking is closed.")

        stops = await self._route_stops(trip.route_id)
        nearest_seq, nearest_dist = self._match_to_node(latitude, longitude, stops)

        # Read before the insert: the node-departure trigger below is a
        # transition between two consecutive reports, so it needs the one
        # that came before this.
        previous = await self._latest_ping(trip_id)

        when = recorded_at or datetime.now(APP_TZ)
        if when.tzinfo is not None:
            when = when.astimezone(APP_TZ).replace(tzinfo=None)

        self.session.add(
            TripLocationPing(
                trip_id=trip_id,
                van_id=trip.van_id,
                latitude=Decimal(str(round(latitude, 6))),
                longitude=Decimal(str(round(longitude, 6))),
                accuracy_m=(
                    Decimal(str(round(accuracy_m, 2))) if accuracy_m is not None else None
                ),
                speed_kph=(
                    Decimal(str(round(speed_kph, 2))) if speed_kph is not None else None
                ),
                heading_deg=(
                    Decimal(str(round(heading_deg, 2)))
                    if heading_deg is not None
                    else None
                ),
                nearest_stop_sequence=nearest_seq,
                distance_to_stop_m=(
                    Decimal(str(round(nearest_dist, 2)))
                    if nearest_dist is not None
                    else None
                ),
                recorded_at=when,
                received_at=datetime.now(APP_TZ).replace(tzinfo=None),
            )
        )
        await self.session.commit()

        # 2.3.5's GPS-node trigger. The van has pulled out of a terminal's
        # geofence, so the cabin for the leg it just entered is settled and
        # a headcount there is comparable with the manifest. Detached: a
        # position report must never be rejected because a camera is down,
        # or the track would grow holes wherever the AI node hiccuped.
        leg = await self._leg_just_entered(previous, nearest_seq, nearest_dist, stops)
        if leg is not None:
            auto_trigger.schedule(
                trip_id=trip_id, leg_sequence=leg, trigger=AuditTrigger.GPS_NODE
            )

        return {
            "trip_id": trip_id,
            "nearest_stop_sequence": nearest_seq,
            "distance_to_stop_m": round(nearest_dist, 2) if nearest_dist else None,
            "recorded_at": when.isoformat(),
        }

    # ------------------------------------------------------------------
    async def current_position(self, *, trip_id: str) -> VanPosition:
        """Latest known position, with ETAs for the stops still ahead."""
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        result = await self.session.execute(
            select(TripLocationPing)
            .where(TripLocationPing.trip_id == trip_id)
            .order_by(TripLocationPing.recorded_at.desc())
            .limit(SPEED_WINDOW)
        )
        pings = list(result.scalars().all())
        if not pings:
            raise NotFoundError("No position has been reported for this trip yet.")

        latest = pings[0]
        recorded = localize(latest.recorded_at)
        age = int((datetime.now(APP_TZ) - recorded).total_seconds())

        stale_after = await self.policies.get_int("tracking_stale_after_seconds")
        stops = await self._route_stops(trip.route_id)
        speed = self._estimate_speed(pings, trip, stops)

        etas = await self._compute_etas(
            latitude=float(latest.latitude),
            longitude=float(latest.longitude),
            from_sequence=latest.nearest_stop_sequence or 1,
            stops=stops,
            speed_kph=speed,
            now=recorded,
        )

        nearest_name = next(
            (
                t.terminal_name
                for rs, t in stops
                if rs.stop_sequence == latest.nearest_stop_sequence
            ),
            None,
        )

        return VanPosition(
            trip_id=trip_id,
            van_id=latest.van_id,
            plate_number=trip.van.plate_number if trip.van else None,
            latitude=float(latest.latitude),
            longitude=float(latest.longitude),
            speed_kph=float(latest.speed_kph) if latest.speed_kph else speed,
            heading_deg=float(latest.heading_deg) if latest.heading_deg else None,
            nearest_stop_sequence=latest.nearest_stop_sequence,
            nearest_stop_name=nearest_name,
            distance_to_stop_m=(
                float(latest.distance_to_stop_m) if latest.distance_to_stop_m else None
            ),
            recorded_at=recorded,
            # A stale position shown as current is worse than none at all:
            # a passenger would walk to a terminal on the strength of a van
            # that stopped reporting twenty minutes ago.
            is_stale=age > stale_after,
            seconds_since_report=age,
            etas=etas,
        )

    async def track_history(self, *, trip_id: str, limit: int = 500) -> list[dict]:
        """Breadcrumb trail, oldest first -- draws the route travelled."""
        result = await self.session.execute(
            select(TripLocationPing)
            .where(TripLocationPing.trip_id == trip_id)
            .order_by(TripLocationPing.recorded_at.desc())
            .limit(limit)
        )
        pings = list(result.scalars().all())[::-1]
        return [
            {
                "latitude": float(p.latitude),
                "longitude": float(p.longitude),
                "speed_kph": float(p.speed_kph) if p.speed_kph else None,
                "nearest_stop_sequence": p.nearest_stop_sequence,
                "recorded_at": localize(p.recorded_at).isoformat(),
            }
            for p in pings
        ]

    async def active_fleet(self) -> list[dict]:
        """Every van currently reporting -- the console's fleet map."""
        result = await self.session.execute(
            select(Trip).where(
                Trip.status.in_([TripStatus.BOARDING.value, TripStatus.DEPARTED.value])
            )
        )
        out: list[dict] = []
        for trip in result.scalars():
            try:
                pos = await self.current_position(trip_id=trip.trip_id)
            except NotFoundError:
                continue
            out.append(
                {
                    "trip_id": pos.trip_id,
                    "plate_number": pos.plate_number,
                    "trip_label": trip.trip_label,
                    "latitude": pos.latitude,
                    "longitude": pos.longitude,
                    "nearest_stop_name": pos.nearest_stop_name,
                    "speed_kph": pos.speed_kph,
                    "is_stale": pos.is_stale,
                    "next_eta": pos.etas[0].eta.isoformat() if pos.etas else None,
                }
            )
        return out

    # ------------------------------------------------------------------
    async def _latest_ping(self, trip_id: str) -> TripLocationPing | None:
        result = await self.session.execute(
            select(TripLocationPing)
            .where(TripLocationPing.trip_id == trip_id)
            .order_by(TripLocationPing.recorded_at.desc())
            .limit(1)
        )
        return result.scalars().first()

    async def _leg_just_entered(
        self,
        previous: TripLocationPing | None,
        nearest_seq: int | None,
        nearest_dist: float | None,
        stops: list[tuple[RouteStop, Terminal]],
    ) -> int | None:
        """The leg the van has just pulled onto, or None if nothing changed.

        A node departure is a transition, not a state: the previous report
        sat inside a terminal's geofence and this one does not. Everything
        else -- still parked at the node, already out on the road, the
        first report of the trip -- is not an event, which is what keeps a
        10-second ping interval from firing ten audits a minute.

        Leg k runs from stop k to stop k+1, so leaving stop k puts the van
        on leg k and that is the leg whose manifest the count belongs to.

        The radius is the terminal's own check-in geofence. "Is the vehicle
        still at this terminal" and "is this passenger at this terminal"
        are the same question about the same compound; a second radius for
        it would only drift away from the first.
        """
        if previous is None or previous.nearest_stop_sequence is None:
            return None
        if previous.distance_to_stop_m is None:
            return None

        was_at = previous.nearest_stop_sequence
        radius = await self._node_radius(was_at, stops)
        if float(previous.distance_to_stop_m) > radius:
            return None  # already between nodes when it last reported

        still_inside = (
            nearest_seq == was_at
            and nearest_dist is not None
            and nearest_dist <= radius
        )
        if still_inside:
            return None

        # The final stop closes the route. Leaving its fence is the van
        # going home, not starting a section, and there is no leg N to
        # count passengers on.
        if was_at >= max(rs.stop_sequence for rs, _ in stops):
            return None

        return was_at

    async def _node_radius(
        self, stop_sequence: int, stops: list[tuple[RouteStop, Terminal]]
    ) -> float:
        terminal = next(
            (t for rs, t in stops if rs.stop_sequence == stop_sequence), None
        )
        if terminal is not None and terminal.geofence_radius_m:
            return float(terminal.geofence_radius_m)
        return float(await self.policies.get_int("default_geofence_radius_m"))

    async def _route_stops(self, route_id: str) -> list[tuple[RouteStop, Terminal]]:
        result = await self.session.execute(
            select(RouteStop, Terminal)
            .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
            .where(RouteStop.route_id == route_id)
            .order_by(RouteStop.stop_sequence)
        )
        return list(result.all())

    @staticmethod
    def _match_to_node(
        lat: float, lng: float, stops: list[tuple[RouteStop, Terminal]]
    ) -> tuple[int | None, float | None]:
        """Greedy nearest-node selection -- the map-matching step."""
        best_seq, best_dist = None, None
        for rs, terminal in stops:
            d = haversine_m(lat, lng, float(terminal.latitude), float(terminal.longitude))
            if best_dist is None or d < best_dist:
                best_seq, best_dist = rs.stop_sequence, d
        return best_seq, best_dist

    @staticmethod
    def _estimate_speed(
        pings: list[TripLocationPing],
        trip: Trip,
        stops: list[tuple[RouteStop, Terminal]],
    ) -> float:
        """Rolling speed, falling back to the route's planned pace.

        Reported speed is preferred. Where the receiver does not supply it,
        the schedule itself is a better default than a guessed constant --
        offset_minutes already encodes how long the cooperative expects
        each section to take.
        """
        reported = [float(p.speed_kph) for p in pings if p.speed_kph is not None]
        if reported:
            avg = sum(reported) / len(reported)
            if avg >= MIN_MOVING_KPH:
                return round(avg, 1)

        if len(stops) >= 2:
            total_minutes = max(rs.offset_minutes for rs, _ in stops)
            total_m = 0.0
            for (_, a), (_, b) in zip(stops, stops[1:]):
                total_m += haversine_m(
                    float(a.latitude), float(a.longitude),
                    float(b.latitude), float(b.longitude),
                )
            if total_minutes > 0 and total_m > 0:
                return round((total_m / 1000) / (total_minutes / 60), 1)

        return 40.0  # last resort

    async def _compute_etas(
        self,
        *,
        latitude: float,
        longitude: float,
        from_sequence: int,
        stops: list[tuple[RouteStop, Terminal]],
        speed_kph: float,
        now: datetime,
    ) -> list[StopEta]:
        """Cumulative node-to-node distance ahead, converted to arrival times."""
        ahead = [(rs, t) for rs, t in stops if rs.stop_sequence > from_sequence]
        if not ahead:
            return []

        etas: list[StopEta] = []
        cursor_lat, cursor_lng = latitude, longitude
        cumulative_m = 0.0

        for rs, terminal in ahead:
            leg_m = haversine_m(
                cursor_lat, cursor_lng,
                float(terminal.latitude), float(terminal.longitude),
            )
            cumulative_m += leg_m
            cursor_lat, cursor_lng = float(terminal.latitude), float(terminal.longitude)

            if speed_kph >= MIN_MOVING_KPH:
                minutes = (cumulative_m / 1000) / speed_kph * 60
                eta = now + timedelta(minutes=minutes)
                minutes_away = int(round(minutes))
            else:
                # Stationary: an ETA computed from a near-zero speed would
                # be absurd, so report distance and leave arrival unknown.
                eta, minutes_away = None, None

            etas.append(
                StopEta(
                    stop_sequence=rs.stop_sequence,
                    terminal_id=terminal.terminal_id,
                    terminal_name=terminal.terminal_name,
                    distance_m=round(cumulative_m, 1),
                    eta=eta,
                    minutes_away=minutes_away,
                )
            )
        return etas