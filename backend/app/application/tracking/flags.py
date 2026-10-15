"""A trip's driving flags, kept in step with its GPS readings.

Rev 603, change brief 6.3-6.4 (Table 30). The rules are the pure
`tracking/driving.py`; this module feeds it a trip's readings, its
route's stops and stretches, its declared home-pickup waits and A2Z's
thresholds, and stores what it finds in `driving_events`.

Run after each batch of readings of a trip on the road (departed) or
done (completed), so a phone uploading late, after the trip completed,
still has its readings counted. The readings are taken from the
departure on, with the one just before it, so the first stretch is
timed from the starting terminal's zone. A rental has no route: no flags.

Each run recomputes from every reading and reconciles by kind and start:
  - a new flag is stored with its general place (`TrackingService.geotag`)
    and, unless it is an en-route stop (recorded, not flagged), alerts the
    Terminal Manager and the trip's Dispatcher, once;
  - a flag found again is updated (a stop or a run that went on);
  - a stored flag no longer found (late readings changed the picture) is
    deleted while nobody has looked at it: open and not disputed.
Overspeed and slow stretches need the route's stretches (speed limits,
expected times); until the Terminal Manager sets them only stops are
flagged. Each flag ties to a person only through the operator name,
licence and plate copied onto the trip at the start.

The Terminal Manager reviews an open flag (`review`): 'reviewed' (it
stands, looked at) or 'dismissed' (with a note), each with who and when.
A flag the operator disputes is reviewed by the dispute's decision
instead (`finance/disputes.py`); an en-route stop is recorded, not
flagged, so there is nothing to review.
"""

from __future__ import annotations

import logging
import uuid
from decimal import Decimal

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.notifications.service import NotificationService, trip_label
from app.application.tracking import driving
from app.application.tracking.nahgm import TrackingService
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, InvalidInputError, NotFoundError
from app.domain.enums import Role, TripStatus
from app.infrastructure.models import (
    AssistedPickup,
    Dispute,
    DrivingEvent,
    RouteStretch,
    Trip,
    TripLocationPing,
    User,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

ON_THE_ROAD = (TripStatus.DEPARTED.value, TripStatus.COMPLETED.value)
WORDS = {
    "overspeed": "Overspeed",
    "unscheduled_stop": "Unscheduled stop",
    "slow_stretch": "Slow stretch",
}


def _dec(value: float | None, places: str = "0.01") -> Decimal | None:
    return None if value is None else Decimal(str(value)).quantize(Decimal(places))


class DrivingFlags:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.tracking = TrackingService(session)

    async def review(self, trip_id: str) -> list[DrivingEvent]:
        """Recompute the trip's flags and store them. Commits. Returns the
        flags that are new."""
        trip = await self.session.get(Trip, trip_id)
        if trip is None or trip.route_id is None or trip.status not in ON_THE_ROAD \
                or trip.departed_at is None:
            return []
        found = driving.flags(
            await self._readings(trip), await self._stops(trip.route_id),
            await self._stretches(trip.route_id), await self._waits(trip),
            await self._rules(),
        )
        stored = {(e.flag_type, e.start_at): e for e in (await self.session.execute(
            select(DrivingEvent).where(DrivingEvent.trip_id == trip_id)
        )).scalars()}

        new: list[tuple[DrivingEvent, str | None]] = []
        for flag in found:
            row = stored.pop((flag.kind, flag.start), None)
            if row is None:
                row = DrivingEvent(driving_event_id=str(uuid.uuid4()), trip_id=trip_id,
                                   flag_type=flag.kind, start_at=flag.start,
                                   created_at=app_tz.now().replace(tzinfo=None))
                place = await self.tracking.geotag(trip, flag.start, latitude=flag.lat,
                                                   longitude=flag.lon)
                row.distance_from_start_m = _dec(place.distance_from_start_m if place else None)
                self.session.add(row)
                new.append((row, place.general if place else None))
            row.end_at = flag.end
            row.stretch_no = flag.stretch_no
            row.max_speed_kmh = _dec(flag.max_speed_kmh, "0.1")
            row.limit_kmh = _dec(flag.limit_kmh, "0.1")
            row.time_ratio = _dec(flag.time_ratio)
            row.nearest_stop_dist_m = _dec(flag.nearest_stop_dist_m)
            row.duration_s = flag.duration_s
        for row in stored.values():
            if row.review_status == "open" and not await self.session.scalar(
                    select(exists().where(Dispute.driving_event_id == row.driving_event_id))):
                await self.session.delete(row)

        notifications = NotificationService(self.session)
        for row, where in new:
            if row.flag_type in WORDS:
                await notifications.notify_trip(
                    trip=trip, type="driving_flag", title="Driving flag",
                    message=self._message(trip, row, where), roles=(Role.TERMINAL_MANAGER,),
                    dispatcher=True,
                )
        await self.session.commit()
        if new:
            log.info("Trip %s: %d new driving flags.", trip_id, len(new))
        return [row for row, _ in new]

    async def mark(self, driving_event_id: str, *, by: User, status: str,
                   note: str | None) -> DrivingEvent:
        """The Terminal Manager's review of an open flag. Commits."""
        flag = await self.session.get(DrivingEvent, driving_event_id, with_for_update=True)
        if flag is None:
            raise NotFoundError("Driving flag not found.")
        if flag.flag_type not in WORDS:
            raise ConflictError("An en-route stop is recorded, not flagged: there is "
                                "nothing to review.")
        if flag.review_status != "open":
            raise ConflictError(f"This flag was already {flag.review_status}.")
        if await self.session.scalar(select(exists().where(
                Dispute.driving_event_id == driving_event_id, Dispute.status == "open"))):
            raise ConflictError("The operator disputes this flag: deciding the dispute "
                                "reviews it.")
        if status == "dismissed" and not note:
            raise InvalidInputError("Say why the flag is dismissed.")
        flag.review_status = status
        flag.reviewed_by, flag.reviewed_at = by.user_id, app_tz.now().replace(tzinfo=None)
        flag.review_note = note
        await self.session.commit()
        log.info("Driving flag %s %s by %s.", driving_event_id, status, by.user_id)
        return flag

    # ------------------------------------------------------------ inputs
    async def _readings(self, trip: Trip) -> list[driving.Reading]:
        rows = (await self.session.execute(
            select(TripLocationPing).where(TripLocationPing.trip_id == trip.trip_id)
            .order_by(TripLocationPing.recorded_at)
        )).scalars().all()
        start = next((i for i, p in enumerate(rows) if p.recorded_at >= trip.departed_at),
                     len(rows))
        return [driving.Reading(p.recorded_at, float(p.latitude), float(p.longitude),
                                None if p.speed_kph is None else float(p.speed_kph))
                for p in rows[max(0, start - 1):]]

    async def _stops(self, route_id: str) -> list[driving.Stop]:
        stops = await self.tracking._route_stops(route_id)
        zones = await self.tracking.stop_zones(stops)
        return [driving.Stop(rs.stop_sequence, float(t.latitude), float(t.longitude),
                             zones[rs.stop_sequence]) for rs, t in stops]

    async def _stretches(self, route_id: str) -> list[driving.Stretch]:
        return [driving.Stretch(s.stretch_no, float(s.speed_limit_kmh), s.expected_time_s)
                for s in (await self.session.execute(
                    select(RouteStretch).where(RouteStretch.route_id == route_id)
                )).scalars()]

    async def _waits(self, trip: Trip) -> list[driving.Wait]:
        return [driving.Wait(p.arrived_at, p.left_at) for p in (await self.session.execute(
            select(AssistedPickup).where(AssistedPickup.trip_id == trip.trip_id,
                                         AssistedPickup.arrived_at.is_not(None))
        )).scalars()]

    async def _rules(self) -> driving.Rules:
        policies = PolicyRepository(self.session)
        return driving.Rules(
            overspeed_s=await policies.get_int("overspeed_seconds"),
            stop_s=await policies.get_int("stop_seconds"),
            slow_ratio=1 + float(await policies.get_decimal("slow_tolerance_pct")) / 100,
            standstill_kmh=float(await policies.get_decimal("standstill_kmh")),
            gap_s=await policies.get_int("heartbeat_gap_seconds"),
            pickup_wait_s=await policies.get_int("home_pickup_wait_minutes") * 60,
        )

    @staticmethod
    def _message(trip: Trip, row: DrivingEvent, where: str | None) -> str:
        if row.flag_type == "overspeed":
            what = f"{row.max_speed_kmh} km/h against {row.limit_kmh}"
        elif row.flag_type == "unscheduled_stop":
            minutes, seconds = divmod(row.duration_s or 0, 60)
            what = (f"stopped {minutes} min {seconds} s, "
                    f"{row.nearest_stop_dist_m:,.0f} m from the nearest stop")
        else:
            what = f"stretch {row.stretch_no} took {row.time_ratio} times its expected time"
        return (f"{WORDS[row.flag_type]} on {trip_label(trip)}{f' {where}' if where else ''} "
                f"at {row.start_at:%H:%M}: {what}. For review, not proof of misconduct.")
