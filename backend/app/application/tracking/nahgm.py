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

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.operations.non_passenger import NonPassengerMoves
from app.application.operations.trip_lifecycle import TripLifecycle
from app.application.tracking.geometry import haversine_m, snap_to_route
from app.core.exceptions import ConflictError, NotFoundError
from app.core.timezone import APP_TZ, localize
from app.domain.enums import TripStatus
from app.infrastructure.models import (
    RouteStop,
    RouteStretch,
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


@dataclass(frozen=True)
class Geotag:
    """Where the van was at a moment, on its route (brief 6.3): for each
    capacity alert, driving flag and departure."""
    latitude: float
    longitude: float
    distance_from_start_m: float | None = None
    stretch_no: int | None = None            # leg k: stop k -> stop k+1
    nearest_stop_sequence: int | None = None
    nearest_stop_dist_m: float | None = None
    # Shown generally: "at Toril" inside a stop zone, else "between Toril
    # and Sta. Cruz", so repeats at one place show.
    general: str | None = None


def _reading(
    *, trip_id: str | None, van_id: str | None, latitude: float, longitude: float,
    accuracy_m: float | None, speed_kph: float | None, heading_deg: float | None,
    recorded_at: datetime, nearest_seq: int | None = None, nearest_dist: float | None = None,
) -> TripLocationPing:
    def dec(value: float | None) -> Decimal | None:
        return None if value is None else Decimal(str(round(value, 2)))

    return TripLocationPing(
        trip_id=trip_id, van_id=van_id,
        latitude=Decimal(str(round(latitude, 6))),
        longitude=Decimal(str(round(longitude, 6))),
        accuracy_m=dec(accuracy_m), speed_kph=dec(speed_kph), heading_deg=dec(heading_deg),
        nearest_stop_sequence=nearest_seq, distance_to_stop_m=dec(nearest_dist),
        recorded_at=recorded_at,
        received_at=datetime.now(APP_TZ).replace(tzinfo=None),
    )


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

        when = recorded_at or datetime.now(APP_TZ)
        if when.tzinfo is not None:
            when = when.astimezone(APP_TZ).replace(tzinfo=None)

        self.session.add(_reading(
            trip_id=trip_id, van_id=trip.van_id, latitude=latitude, longitude=longitude,
            accuracy_m=accuracy_m, speed_kph=speed_kph, heading_deg=heading_deg,
            recorded_at=when, nearest_seq=nearest_seq, nearest_dist=nearest_dist,
        ))
        await self.session.commit()

        if trip.van_id is not None:
            await NonPassengerMoves(self.session).on_reading(trip.van_id, latitude, longitude, when)
            await self.session.commit()

        # Leaving the terminal zone departs the trip, or starts it first
        # if nobody did (brief 4.2 rules 8 and 9). The report is already
        # stored; a failure here is logged, never returned to the unit,
        # which would only resend a ping the track already has.
        if trip.status in (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value) and stops \
                and await self.left_zone(stops[0][1], trip_id=trip_id):
            try:
                await TripLifecycle(self.session).van_left_origin(trip_id)
            except Exception:
                await self.session.rollback()
                log.exception("Departure detection failed for trip %s.", trip_id)

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
    async def _node_radius(
        self, stop_sequence: int, stops: list[tuple[RouteStop, Terminal]]
    ) -> float:
        return (await self.stop_zones(stops))[stop_sequence]

    async def stop_zones(self, stops: list[tuple[RouteStop, Terminal]]) -> dict[int, float]:
        """Each stop's zone radius (brief 6.3): the route's stop zone once
        its stretches are set, else the terminal's geofence, else the
        default geofence."""
        if not stops:
            return {}
        route_zone = await self.session.scalar(
            select(func.max(RouteStretch.stop_zone_radius_m))
            .where(RouteStretch.route_id == stops[0][0].route_id))
        default: float | None = None
        zones: dict[int, float] = {}
        for rs, t in stops:
            if route_zone:
                zones[rs.stop_sequence] = float(route_zone)
            elif t.geofence_radius_m:
                zones[rs.stop_sequence] = float(t.geofence_radius_m)
            else:
                default = default or float(await self.policies.get_int("default_geofence_radius_m"))
                zones[rs.stop_sequence] = default
        return zones

    async def hold_reading(
        self, *, van_id: str, latitude: float, longitude: float,
        accuracy_m: float | None, speed_kph: float | None, heading_deg: float | None,
        recorded_at: datetime,
    ) -> None:
        """A reading from a van with no trip at its time: kept against the
        van (025) so a departure can still be counted, and moved to the
        trip that claims it (`edge.ledger.release_held`)."""
        self.session.add(_reading(
            trip_id=None, van_id=van_id, latitude=latitude, longitude=longitude,
            accuracy_m=accuracy_m, speed_kph=speed_kph, heading_deg=heading_deg,
            recorded_at=recorded_at,
        ))
        await self.session.flush()
        await NonPassengerMoves(self.session).on_reading(van_id, latitude, longitude, recorded_at)
        await self.session.commit()

    async def file_late_reading(
        self, trip: Trip, *, latitude: float, longitude: float, accuracy_m: float | None,
        speed_kph: float | None, heading_deg: float | None, recorded_at: datetime,
    ) -> None:
        """A reading from during a trip that has since completed: a phone
        offline on the road uploads it after the alightings ended the
        trip. History only: nothing live (departure, capacity) runs on it,
        but the trip's driving flags count it."""
        stops = await self._route_stops(trip.route_id) if trip.route_id else []
        nearest_seq, nearest_dist = self._match_to_node(latitude, longitude, stops)
        self.session.add(_reading(
            trip_id=trip.trip_id, van_id=trip.van_id, latitude=latitude, longitude=longitude,
            accuracy_m=accuracy_m, speed_kph=speed_kph, heading_deg=heading_deg,
            recorded_at=recorded_at, nearest_seq=nearest_seq, nearest_dist=nearest_dist,
        ))
        await self.session.commit()

    async def left_zone(
        self, terminal: Terminal, *, trip_id: str | None = None, van_id: str | None = None,
    ) -> bool:
        """The departure rule (brief 4.2 rule 8): the last N readings -- of
        the trip, or the van's held ones -- all outside the terminal zone,
        and moving. A reading with no speed counts by position alone. A
        single stray reading departs nothing. While the zone radius or N
        is unset (a site survey sets them), there is no GPS departure."""
        radius = await self.policies.get_optional_int("depart_zone_radius_m")
        readings = await self.policies.get_optional_int("depart_readings")
        if radius is None or readings is None:
            return False
        query = select(TripLocationPing)
        query = (query.where(TripLocationPing.trip_id == trip_id) if trip_id is not None
                 else query.where(TripLocationPing.van_id == van_id,
                                  TripLocationPing.trip_id.is_(None)))
        last = (await self.session.execute(
            query.order_by(TripLocationPing.recorded_at.desc()).limit(readings)
        )).scalars().all()
        centre = (float(terminal.latitude), float(terminal.longitude))
        return len(last) == readings and all(
            haversine_m(float(p.latitude), float(p.longitude), *centre) > radius
            and (p.speed_kph is None or float(p.speed_kph) >= MIN_MOVING_KPH)
            for p in last
        )

    # ----------------------------------------------------------- geotag
    async def geotag(
        self, trip: Trip, at: datetime, *, latitude: float | None = None,
        longitude: float | None = None,
    ) -> Geotag | None:
        """The van's place at `at`: the event's own fix, else interpolated
        between the trip's readings on either side of it; snapped to the
        nearest stretch of the route, drawn straight stop to stop as the
        maps draw it. None with no position at all. A rental has no route,
        so no stretch."""
        if latitude is None or longitude is None:
            point = await self._position_at(trip.trip_id, at)
            if point is None:
                return None
            latitude, longitude = point
        if trip.route_id is None:
            return Geotag(latitude, longitude)
        stops = await self._route_stops(trip.route_id)
        if len(stops) < 2:
            return Geotag(latitude, longitude)

        snap = snap_to_route(latitude, longitude, [
            (rs.stop_sequence, float(t.latitude), float(t.longitude)) for rs, t in stops
        ])
        stretch, from_start = snap.stretch, snap.from_start_m

        nearest, near_m = self._match_to_node(latitude, longitude, stops)
        return Geotag(latitude, longitude, round(from_start, 2), stretch, nearest,
                      round(near_m, 2), await self._general(stops, stretch, nearest, near_m))

    async def place(
        self, route_id: str | None, stretch_no: int | None,
        nearest_stop: int | None = None, nearest_m: float | None = None,
    ) -> str | None:
        """A stored geotag in words, as `geotag` gave it: "at Toril" inside
        the stop's zone, else "between Toril and Sta. Cruz"."""
        if route_id is None or stretch_no is None:
            return None
        stops = await self._route_stops(route_id)
        if stretch_no + 1 > len(stops):
            return None
        return await self._general(stops, stretch_no, nearest_stop, nearest_m)

    async def _general(
        self, stops: list[tuple[RouteStop, Terminal]], stretch: int,
        nearest: int | None, near_m: float | None,
    ) -> str:
        names = {rs.stop_sequence: t.terminal_name for rs, t in stops}
        if nearest is not None and near_m is not None \
                and near_m <= await self._node_radius(nearest, stops):
            return f"at {names[nearest]}"
        return f"between {names[stretch]} and {names[stretch + 1]}"

    async def _position_at(self, trip_id: str, at: datetime) -> tuple[float, float] | None:
        """Linear between the readings either side of `at`; the nearer one
        alone when only one side exists."""
        before = (await self.session.execute(
            select(TripLocationPing).where(TripLocationPing.trip_id == trip_id,
                                           TripLocationPing.recorded_at <= at)
            .order_by(TripLocationPing.recorded_at.desc()).limit(1)
        )).scalar_one_or_none()
        after = (await self.session.execute(
            select(TripLocationPing).where(TripLocationPing.trip_id == trip_id,
                                           TripLocationPing.recorded_at > at)
            .order_by(TripLocationPing.recorded_at).limit(1)
        )).scalar_one_or_none()
        if before is None and after is None:
            return None
        if before is None or after is None:
            p = before or after
            return float(p.latitude), float(p.longitude)
        span = (after.recorded_at - before.recorded_at).total_seconds()
        f = (at - before.recorded_at).total_seconds() / span if span else 0.0
        return (float(before.latitude) + f * (float(after.latitude) - float(before.latitude)),
                float(before.longitude) + f * (float(after.longitude) - float(before.longitude)))

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

