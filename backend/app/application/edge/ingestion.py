"""What the edge phone uploads (brief step 5): status reports, door
events, a blurred still per event, and GPS readings.

The phone works offline and sends what it stored when the connection
returns, so every upload is a batch and every batch is idempotent:
a report is keyed by (phone, recorded_at), an event by the event_id the
phone generated. Sending the same batch twice changes nothing.

Times are the phone's clock, which it keeps in step with the server's
(GET /edge/session). A batch dated in the future by more than
`CLOCK_TOLERANCE` is refused whole: the 2-minute matching window (brief
6.1) cannot work with a clock that far off, so the phone must resync,
not have its readings silently shifted.
"""

from __future__ import annotations

import hashlib
import logging
import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from pathlib import Path

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.edge.evidence import PhoneEvidence
from app.application.edge.ledger import (
    STARTED, TRIP_REACH, alerted_while_held, trip_for, van_at,
)
from app.application.notifications.service import NotificationService
from app.application.operations.boarding import DepartTripUseCase
from app.application.operations.non_passenger import NonPassengerMoves
from app.application.operations.trip_lifecycle import TripLifecycle
from app.application.tracking.nahgm import TrackingService
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, InvalidInputError, NotFoundError
from app.core.images import sniff_image_ext
from app.domain.enums import DepartureSource, Role, TripStatus
from app.infrastructure.models import (
    DeviceCheckout,
    DeviceHeartbeat,
    EdgeDevice,
    HeldDoorEvent,
    PassengerEvent,
    Terminal,
    Trip,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

CLOCK_TOLERANCE = timedelta(minutes=2)
MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024
# Outside the public /media mount: a passenger's picture, even blurred,
# is evidence for the office, not a link anyone can open.
SNAPSHOT_DIR = Path(__file__).resolve().parents[3] / "storage" / "snapshots"


def _naive(value: datetime) -> datetime:
    """Manila wall time, as the DATETIME columns hold it."""
    if value.tzinfo is not None:
        value = value.astimezone(app_tz.APP_TZ).replace(tzinfo=None)
    return value


def _metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    rlat1, rlat2 = math.radians(lat1), math.radians(lat2)
    a = (math.sin((rlat2 - rlat1) / 2) ** 2
         + math.cos(rlat1) * math.cos(rlat2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 2 * 6_371_000.0 * math.asin(math.sqrt(a))


@dataclass
class Report:
    recorded_at: datetime
    camera_ok: bool
    gps_ok: bool
    lens_blocked: bool = False
    battery_pct: int | None = None
    battery_temp_c: float | None = None
    charging: bool | None = None
    detection_rate_hz: float | None = None


@dataclass
class DoorEvent:
    event_id: str
    event_type: str  # board | alight
    event_at: datetime
    latitude: float | None = None
    longitude: float | None = None
    occupancy_after: int | None = None
    track_id: int | None = None


@dataclass
class Fix:
    recorded_at: datetime
    latitude: float
    longitude: float
    accuracy_m: float | None = None
    speed_kph: float | None = None
    heading_deg: float | None = None


class EdgeIngestion:
    def __init__(self, session: AsyncSession, device: EdgeDevice):
        self.session = session
        self.device = device

    def _check_clock(self, times: list[datetime]) -> None:
        if times and max(times) > app_tz.now().replace(tzinfo=None) + CLOCK_TOLERANCE:
            raise InvalidInputError(
                "This upload is dated in the future: the phone's clock is off. "
                "Resynchronise with GET /edge/session and send it again."
            )

    # ---------------------------------------------------------- reports
    async def heartbeats(self, reports: list[Report]) -> dict:
        for r in reports:
            r.recorded_at = _naive(r.recorded_at)
        self._check_clock([r.recorded_at for r in reports])
        reports = sorted(reports, key=lambda r: r.recorded_at)

        known = set((await self.session.execute(
            select(DeviceHeartbeat.recorded_at).where(
                DeviceHeartbeat.device_id == self.device.device_id,
                DeviceHeartbeat.recorded_at.in_([r.recorded_at for r in reports]),
            )
        )).scalars().all()) if reports else set()
        now = app_tz.now().replace(tzinfo=None)
        stored = 0
        for r in reports:
            if r.recorded_at in known:
                continue
            known.add(r.recorded_at)
            self.session.add(DeviceHeartbeat(
                device_id=self.device.device_id, recorded_at=r.recorded_at, received_at=now,
                battery_pct=r.battery_pct,
                battery_temp_c=None if r.battery_temp_c is None else Decimal(str(r.battery_temp_c)),
                charging=r.charging, camera_ok=r.camera_ok, gps_ok=r.gps_ok,
                lens_blocked=r.lens_blocked,
                detection_rate_hz=(None if r.detection_rate_hz is None
                                   else Decimal(str(r.detection_rate_hz))),
            ))
            stored += 1

        # The pool's view of the phone: its newest report.
        newest = reports[-1] if reports else None
        if newest and (self.device.last_heartbeat_at is None
                       or newest.recorded_at > self.device.last_heartbeat_at):
            self.device.last_heartbeat_at = newest.recorded_at
            self.device.battery_pct = newest.battery_pct
            self.device.battery_temp_c = (None if newest.battery_temp_c is None
                                          else Decimal(str(newest.battery_temp_c)))
            self.device.camera_ok = newest.camera_ok
            self.device.gps_ok = newest.gps_ok
        await self.session.flush()

        # Judge every trip these reports fall in (brief 4.4).
        if reports:
            evidence = PhoneEvidence(self.session)
            for trip in await self._trips_during(reports[0].recorded_at, reports[-1].recorded_at):
                await evidence.review_coverage(trip)
        await self.session.commit()
        return {"stored": stored, "duplicates": len(reports) - stored}

    async def _trips_during(self, first: datetime, last: datetime) -> list[Trip]:
        vans = (await self.session.execute(
            select(DeviceCheckout.van_id).where(
                DeviceCheckout.device_id == self.device.device_id,
                DeviceCheckout.checked_out_at <= last,
                or_(DeviceCheckout.returned_at.is_(None), DeviceCheckout.returned_at >= first),
            )
        )).scalars().all()
        if not vans:
            return []
        gap = timedelta(seconds=await PolicyRepository(self.session).get_int("heartbeat_gap_seconds"))
        return list((await self.session.execute(
            select(Trip).where(
                Trip.van_id.in_(vans),
                Trip.status.in_(STARTED),
                Trip.started_at <= last,
                or_(Trip.completed_at.is_(None), Trip.completed_at >= first - gap),
            )
        )).scalars().all())

    # ----------------------------------------------------------- events
    async def events(self, events: list[DoorEvent]) -> dict:
        for e in events:
            e.event_at = _naive(e.event_at)
        self._check_clock([e.event_at for e in events])
        counts = {"stored": 0, "held": 0, "duplicates": 0, "ignored": 0}
        held_vans: set[str] = set()
        seen: set[str] = set()
        now = app_tz.now().replace(tzinfo=None)
        for e in sorted(events, key=lambda e: e.event_at):
            if (e.event_id in seen
                    or await self.session.get(PassengerEvent, e.event_id) is not None
                    or await self.session.get(HeldDoorEvent, e.event_id) is not None):
                counts["duplicates"] += 1
                continue
            seen.add(e.event_id)
            van_id = await van_at(self.session, self.device.device_id, e.event_at)
            if van_id is None:
                # Counted in the office, or after the return: no van, no trip.
                counts["ignored"] += 1
                continue
            fields = dict(
                event_id=e.event_id, device_id=self.device.device_id,
                event_type=e.event_type, event_at=e.event_at,
                latitude=None if e.latitude is None else Decimal(str(round(e.latitude, 6))),
                longitude=None if e.longitude is None else Decimal(str(round(e.longitude, 6))),
                occupancy_after=e.occupancy_after, track_id=e.track_id,
            )
            trip = await trip_for(self.session, van_id, e.event_at)
            if trip is not None:
                self.session.add(PassengerEvent(**fields, trip_id=trip.trip_id,
                                                created_at=now))
                counts["stored"] += 1
            else:
                self.session.add(HeldDoorEvent(**fields, van_id=van_id, received_at=now))
                counts["held"] += 1
                held_vans.add(van_id)
            await self.session.flush()

        for van_id in held_vans:
            await self._alert_held(van_id)
        await self.session.commit()
        return counts

    async def _alert_held(self, van_id: str) -> None:
        """'Trip Not Started' (rule 12), once while the van's events wait."""
        if await alerted_while_held(self.session, van_id, "Trip not started"):
            return
        van = await self.session.get(Van, van_id)
        await NotificationService(self.session).notify_staff(
            type="trip_not_started", title="Trip not started",
            message=(f"The phone in {van.plate_number} is counting passengers, but no trip "
                     "of that van is open or about to start. Its door events are held "
                     "until one is started: assign and start the van's trip."),
            roles=(Role.TERMINAL_MANAGER,), entity=("van", van_id),
        )

    # --------------------------------------------------------- snapshots
    async def snapshot(self, event_id: str, data: bytes) -> dict:
        """The blurred still of one event. Evidence is never replaced: the
        same bytes again are accepted, different bytes are refused."""
        row = await self.session.get(PassengerEvent, event_id) \
            or await self.session.get(HeldDoorEvent, event_id)
        if row is None or row.device_id != self.device.device_id:
            raise NotFoundError("No event with that id from this phone.")
        if len(data) > MAX_SNAPSHOT_BYTES:
            raise InvalidInputError("The snapshot is larger than 2 MB.")
        ext = sniff_image_ext(data)
        if ext is None:
            raise InvalidInputError("The snapshot must be a JPEG, PNG or WebP image.")
        digest = hashlib.sha256(data).hexdigest()
        if row.snapshot_hash is not None:
            if row.snapshot_hash != digest:
                raise ConflictError("This event already has a different snapshot.")
            return {"event_id": event_id, "snapshot_hash": digest, "duplicate": True}

        SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
        name = f"{event_id}.{ext}"
        (SNAPSHOT_DIR / name).write_bytes(data)
        row.snapshot_url = f"snapshots/{name}"
        row.snapshot_hash = digest
        await self.session.commit()
        return {"event_id": event_id, "snapshot_hash": digest, "duplicate": False}

    # -------------------------------------------------------------- GPS
    async def fixes(self, fixes: list[Fix]) -> dict:
        """Each reading goes on the trip of the van at its time, through
        the same NAHGM path as before. A reading of a van with no trip is
        held against the van (025); when its phone has held boardings and
        the van has left that terminal's zone, it gets its trip (rule 9)."""
        for f in fixes:
            f.recorded_at = _naive(f.recorded_at)
        self._check_clock([f.recorded_at for f in fixes])
        tracking = TrackingService(self.session)
        counts = {"recorded": 0, "held": 0, "ignored": 0}
        for f in sorted(fixes, key=lambda f: f.recorded_at):
            van_id = await van_at(self.session, self.device.device_id, f.recorded_at)
            if van_id is None:
                counts["ignored"] += 1
                continue
            trip = await trip_for(self.session, van_id, f.recorded_at)
            if trip is None:
                await tracking.hold_reading(
                    van_id=van_id, latitude=f.latitude, longitude=f.longitude,
                    accuracy_m=f.accuracy_m, speed_kph=f.speed_kph,
                    heading_deg=f.heading_deg, recorded_at=f.recorded_at,
                )
                counts["held"] += 1
                await self._detect_departure(van_id, f, tracking)
                continue
            if trip.status in (TripStatus.COMPLETED.value, TripStatus.CANCELLED.value):
                counts["ignored"] += 1
                continue
            await tracking.record_ping(
                trip_id=trip.trip_id, latitude=f.latitude, longitude=f.longitude,
                accuracy_m=f.accuracy_m, speed_kph=f.speed_kph,
                heading_deg=f.heading_deg, recorded_at=f.recorded_at,
            )
            counts["recorded"] += 1
        return counts

    async def _detect_departure(self, van_id: str, fix: Fix,
                                tracking: TrackingService) -> Trip | None:
        """Boardings held at a terminal, then the van's held readings
        outside its zone (the departure rule): the van has left with
        passengers and no trip. An open 'Not a passenger trip' move holds
        it off."""
        if await NonPassengerMoves(self.session).open_for(van_id) is not None:
            return None
        boards = (await self.session.execute(
            select(HeldDoorEvent).where(
                HeldDoorEvent.van_id == van_id,
                HeldDoorEvent.event_type == "board",
                HeldDoorEvent.event_at <= fix.recorded_at,
                HeldDoorEvent.event_at >= fix.recorded_at - TRIP_REACH,
            ).order_by(HeldDoorEvent.event_at)
        )).scalars().all()
        located = [b for b in boards if b.latitude is not None and b.longitude is not None]
        if not located:
            return None
        last = located[-1]
        origin = await self._terminal_at(float(last.latitude), float(last.longitude))
        if origin is None:
            return None
        terminal, _ = origin
        if not await tracking.left_zone(terminal, van_id=van_id):
            return None  # still at the terminal, or not N readings out yet

        dispatcher_id = (await self.session.execute(
            select(DeviceCheckout.dispatcher_id).where(
                DeviceCheckout.device_id == self.device.device_id,
                DeviceCheckout.van_id == van_id,
                DeviceCheckout.checked_out_at <= fix.recorded_at,
            ).order_by(DeviceCheckout.checked_out_at.desc()).limit(1)
        )).scalar_one()
        trip = await TripLifecycle(self.session).detected_start(
            van=await self.session.get(Van, van_id),
            origin_terminal_id=terminal.terminal_id,
            at=fix.recorded_at,
            dispatcher_id=dispatcher_id,
        )
        if trip is not None and trip.status == TripStatus.BOARDING.value:
            await DepartTripUseCase(self.session).execute(
                trip_id=trip.trip_id, source=DepartureSource.GPS
            )
        return trip

    async def _terminal_at(self, lat: float, lon: float) -> tuple[Terminal, float] | None:
        """The terminal whose zone this point is in, nearest first."""
        default = float(await PolicyRepository(self.session).get_int("default_geofence_radius_m"))
        best = None
        for t in (await self.session.execute(
            select(Terminal).where(Terminal.is_active.is_(True))
        )).scalars():
            radius = float(t.geofence_radius_m or default)
            d = _metres(lat, lon, float(t.latitude), float(t.longitude))
            if d <= radius and (best is None or d < best[0]):
                best = (d, t, radius)
        return None if best is None else (best[1], best[2])
