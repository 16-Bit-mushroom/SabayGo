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
Every van also carries what it still owes of A2Z's share on its open
statements (the amount that blocks its next assignment), so the Cashier
sees which vans are out and which still owe for their last trip.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.edge.capacity import aboard_after
from app.application.finance.statement import Statements
from app.application.identity.naming import display_name
from app.application.notifications.service import trip_label
from app.application.tracking.nahgm import TrackingService
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError
from app.domain.enums import TripStatus
from app.infrastructure.models import Operator, PassengerEvent, Trip, User, Van

ON_SITE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)


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
            board.append(row)
        return board

    async def _travelling(self, row: VanState, trip: Trip) -> None:
        events = list((await self.session.execute(
            select(PassengerEvent).where(PassengerEvent.trip_id == trip.trip_id)
            .order_by(PassengerEvent.event_at)
        )).scalars().all())
        if events:
            row.aboard = aboard_after(events, crew=1 if trip.crew_aboard else 0)[-1][1]
        try:
            pos = await TrackingService(self.session).current_position(trip_id=trip.trip_id)
        except NotFoundError:
            return
        row.latitude, row.longitude = pos.latitude, pos.longitude
        row.position_at, row.position_stale = pos.recorded_at, pos.is_stale
        row.nearest_stop_name = pos.nearest_stop_name
