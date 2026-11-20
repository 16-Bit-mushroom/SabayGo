"""The Van Status Board (rev 603, change brief 8 and 9): where each van
is, from the trip status and GPS readings already stored, with no extra
data entry. For the Terminal Manager and the Cashier.

Each van is in one state, first match wins:
  travelling      its trip has departed and not yet arrived: with the
                  Dispatcher, operator, route, the number aboard (the door
                  count, as the capacity check counts it; none without a
                  phone) and the last GPS position;
  out_of_service  the van is in maintenance or inactive;
  on_site         a trip of today, scheduled or boarding, is assigned to it
                  (the earliest is shown);
  not_on_trip     neither.
A trip under way (boarding or departed) also carries what watches it, so
the office sees it live (10 Nov, the Overview's live van monitor):
  camera          the door phone checked out with the van: 'live' (it
                  reported within `heartbeat_gap_seconds`, camera working,
                  lens clear), 'lens_blocked', 'silent' (no report within
                  the gap, or never), or 'no_phone' -- the same tests the
                  Unaudited rule uses (`edge/evidence.py`);
  aboard          the door count against `seat_capacity`; none without a
                  phone, and zero only when a live camera has seen nobody
                  board -- never an invented count;
  open_flags      the trip's driving flags still open for review (en-route
                  stops are recorded, not flagged, so they are left out).
Every van also carries what it still owes of the terminal fees on its
open statements (the amount that blocks its next assignment), so the Cashier
sees which vans are out and which still owe for their last trip.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.edge.capacity import aboard_after
from app.application.finance.statement import Statements
from app.application.identity.naming import display_name
from app.application.notifications.service import trip_label
from app.application.tracking.nahgm import TrackingService
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError
from app.domain.enums import TripStatus
from app.infrastructure.models import (
    DeviceCheckout,
    DeviceHeartbeat,
    DrivingEvent,
    EdgeDevice,
    Operator,
    PassengerEvent,
    Trip,
    User,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

ON_SITE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)
UNDER_WAY = (TripStatus.BOARDING.value, TripStatus.DEPARTED.value)


@dataclass
class VanState:
    van_id: str
    plate_number: str
    operator_name: str
    operator_licence: str
    operational_status: str
    state: str
    owes: Decimal
    trip_id: str | None = None
    trip_label: str | None = None
    route_name: str | None = None
    trip_status: str | None = None
    departure_datetime: datetime | None = None
    dispatcher_name: str | None = None
    aboard: int | None = None
    latitude: float | None = None
    longitude: float | None = None
    position_at: datetime | None = None
    position_stale: bool | None = None
    nearest_stop_name: str | None = None
    seat_capacity: int = 14
    camera: str | None = None
    camera_seen_at: datetime | None = None
    open_flags: int | None = None


async def door_camera(session: AsyncSession, van_id: str | None) -> tuple[str, datetime | None]:
    """The van's door phone and when it last reported: 'live' (reported
    within `heartbeat_gap_seconds`, camera working, lens clear),
    'lens_blocked', 'silent' (no report within the gap, or never) or
    'no_phone' -- the tests the Unaudited rule uses (`edge/evidence.py`).
    The office's van board and the Dispatcher's door check (16 Nov) both
    read it, so a count is never shown for a camera that is not there."""
    if van_id is None:
        return "no_phone", None
    checkout = await session.scalar(
        select(DeviceCheckout).where(DeviceCheckout.van_id == van_id,
                                     DeviceCheckout.returned_at.is_(None)))
    if checkout is None:
        return "no_phone", None
    device = await session.get(EdgeDevice, checkout.device_id)
    last = await session.scalar(
        select(DeviceHeartbeat).where(DeviceHeartbeat.device_id == checkout.device_id)
        .order_by(DeviceHeartbeat.recorded_at.desc()).limit(1))
    seen = device.last_heartbeat_at if device else None
    gap = timedelta(seconds=await PolicyRepository(session).get_int("heartbeat_gap_seconds"))
    now = app_tz.now().replace(tzinfo=None)
    if seen is None or now - seen > gap:
        return "silent", seen
    if last is not None and (last.lens_blocked or not last.camera_ok):
        return "lens_blocked", seen
    return "live", seen


class VanBoard:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def now(self) -> list[VanState]:
        vans = (await self.session.execute(
            select(Van, Operator).join(Operator, Operator.operator_id == Van.operator_id)
            .order_by(Van.plate_number)
        )).all()
        out_now = {t.van_id: t for t in (await self.session.execute(
            select(Trip).where(Trip.status == TripStatus.DEPARTED.value, Trip.van_id.is_not(None))
            .order_by(Trip.departed_at)
        )).scalars()}
        today: dict[str, Trip] = {}
        for t in (await self.session.execute(
            select(Trip).where(Trip.service_date == app_tz.now().date(),
                               Trip.status.in_(ON_SITE), Trip.van_id.is_not(None))
            .order_by(Trip.departure_datetime.desc())
        )).scalars():
            today[t.van_id] = t
        shown = [t for t in out_now.values()] + [t for t in today.values()]
        names = {u.user_id: display_name(u) for u in (await self.session.execute(
            select(User).where(User.user_id.in_({t.dispatcher_id for t in shown} - {None}))
        )).scalars()} if shown else {}

        statements = Statements(self.session)
        board = []
        for van, operator in vans:
            row = VanState(
                seat_capacity=van.seat_capacity,
                van_id=van.van_id, plate_number=van.plate_number,
                operator_name=operator.full_name, operator_licence=operator.license_number,
                operational_status=van.operational_status, state="not_on_trip",
                owes=await statements.van_balance(van.van_id),
            )
            trip = out_now.get(van.van_id)
            if trip is not None:
                row.state = "travelling"
                await self._travelling(row, trip)
            elif van.operational_status != "active":
                row.state = "out_of_service"
            elif (trip := today.get(van.van_id)) is not None:
                row.state = "on_site"
            if trip is not None:
                row.trip_id, row.trip_label = trip.trip_id, trip_label(trip)
                row.route_name = trip.route.route_name if trip.route else "Van rental"
                row.trip_status, row.departure_datetime = trip.status, trip.departure_datetime
                row.dispatcher_name = names.get(trip.dispatcher_id)
                if trip.status in UNDER_WAY:
                    await self._watch(row, trip)
            board.append(row)
        return board

    async def _watch(self, row: VanState, trip: Trip) -> None:
        """The door camera, the count it keeps and the open driving flags of
        a trip under way."""
        row.camera, row.camera_seen_at = await door_camera(self.session, row.van_id)
        events = list((await self.session.execute(
            select(PassengerEvent).where(PassengerEvent.trip_id == trip.trip_id)
            .order_by(PassengerEvent.event_at)
        )).scalars().all())
        if events:
            row.aboard = aboard_after(events, crew=1 if trip.crew_aboard else 0)[-1][1]
        elif row.camera == "live":
            # A camera watching the door that has seen nobody board: a real 0.
            row.aboard = 0
        row.open_flags = await self.session.scalar(
            select(func.count()).select_from(DrivingEvent)
            .where(DrivingEvent.trip_id == trip.trip_id, DrivingEvent.review_status == "open",
                   DrivingEvent.flag_type != "en_route_stop"))

    async def _travelling(self, row: VanState, trip: Trip) -> None:
        try:
            pos = await TrackingService(self.session).current_position(trip_id=trip.trip_id)
        except NotFoundError:
            return
        row.latitude, row.longitude = pos.latitude, pos.longitude
        row.position_at, row.position_stale = pos.recorded_at, pos.is_stale
        row.nearest_stop_name = pos.nearest_stop_name
