"""Special trips: a whole van rented from a chosen pickup (rev 603,
change brief 2.5, Table 34).

A van runs outside the timetable only as a special trip: there is no
separate path for an independent van. A request comes two ways:

  app       a passenger asks for a date and time, a pickup, a destination
            and a passenger count (at most 14). The office is alerted.
  counter   the Terminal Manager or the Cashier enters a walk-in
            customer's request (name and contact, no account). It is
            approved as it is entered: the fee is agreed on the spot.

Approving agrees the rental fee with a note on what it is based on
([INTERPRETED] by pickup and destination; there is no fare table) and
creates the trip: no route, no stops, `is_special_trip`. The van and the
Dispatcher are assigned through the trip's own assignment, at the van's
turn, and changed the same way when an operator declines a far trip
(T52). Rejecting needs a reason, which the passenger is told.

Payment comes first. The fee is paid before the van leaves -- in cash at
the terminal, which the trip's Dispatcher logs here (declared, D), or
through the gateway (verified, V) -- and then the trip's Start waits for
it (`TripLifecycle.start`). A paid fee is one fare line on the van's
statement (`finance.statement`), so its 15 % is handed to the Cashier
before Start under the same block as any trip. GPS auto-start is never
blocked.

A request is closed with its trip: voided -> cancelled, arrived ->
completed. A passenger may withdraw a request only before it is
approved; after that the Terminal Manager voids the trip. No refunds.

[OPEN] Whether the Cashier may agree a fee (separation of duties), and
whether a van that declines keeps its queue place; both are A2Z's to say.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.finance.statement import Statements
from app.application.identity.naming import display_name
from app.application.notifications.service import NotificationService
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import Role, TripStatus
from app.infrastructure.models import SpecialTripRequest, Trip, User
from app.infrastructure.repositories.policy_repository import PolicyRepository

ENTITY = "special_trip_request"


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


@dataclass(frozen=True)
class Place:
    address: str
    latitude: Decimal | None = None
    longitude: Decimal | None = None


async def rental_of(session: AsyncSession, trip_id: str) -> SpecialTripRequest | None:
    """The request a special trip was created for, if it was one."""
    return (await session.execute(
        select(SpecialTripRequest).where(SpecialTripRequest.trip_id == trip_id)
    )).scalar_one_or_none()


async def close_rental(session: AsyncSession, trip: Trip) -> None:
    """Follow the trip: voided -> cancelled, completed -> completed."""
    if not trip.is_special_trip:
        return
    request = await rental_of(session, trip.trip_id)
    if request is None:
        return
    status = {TripStatus.CANCELLED.value: "cancelled",
              TripStatus.COMPLETED.value: "completed"}.get(trip.status)
    if status is not None and request.status == "approved":
        request.status = status
        request.updated_at = _now()


class SpecialTrips:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.notifications = NotificationService(session)

    # ----------------------------------------------------------- request
    async def request(
        self, *, by: User, pickup_at: datetime, pickup: Place, destination: Place,
        passenger_count: int,
    ) -> SpecialTripRequest:
        """A passenger asks in the app; the office is alerted."""
        request = self._new(pickup_at=pickup_at, pickup=pickup, destination=destination,
                            passenger_count=passenger_count)
        request.passenger_user_id = by.user_id
        self.session.add(request)
        await self.notifications.notify_staff(
            type="special_trip_request", title="Special trip request",
            message=(f"{display_name(by)} asks for a van for {passenger_count} on "
                     f"{pickup_at:%d %b %H:%M}, from {pickup.address} to {destination.address}. "
                     "Agree the fee and approve it, or reject it with a reason."),
            roles=(Role.TERMINAL_MANAGER, Role.CASHIER), entity=(ENTITY, request.request_id),
        )
        await self.session.commit()
        return request

    async def walk_in(
        self, *, by: User, customer_name: str, customer_contact: str, pickup_at: datetime,
        pickup: Place, destination: Place, passenger_count: int, fee: Decimal, fee_note: str,
    ) -> SpecialTripRequest:
        """The office enters a counter customer's request and agrees the
        fee as it does (T49): approved at once, with its trip."""
        request = self._new(pickup_at=pickup_at, pickup=pickup, destination=destination,
                            passenger_count=passenger_count)
        request.customer_name = customer_name
        request.customer_contact = customer_contact
        request.entered_by = by.user_id
        self.session.add(request)
        await self.session.flush()
        await self._approve(request, by=by, fee=fee, fee_note=fee_note)
        await self.session.commit()
        return request

    def _new(self, *, pickup_at: datetime, pickup: Place, destination: Place,
             passenger_count: int) -> SpecialTripRequest:
        now = _now()
        if pickup_at <= now:
            raise ConflictError("The pickup time has passed. Choose a time ahead.")
        return SpecialTripRequest(
            request_id=str(uuid.uuid4()),
            pickup_at=pickup_at, pickup_address=pickup.address,
            pickup_latitude=pickup.latitude, pickup_longitude=pickup.longitude,
            destination_address=destination.address,
            destination_latitude=destination.latitude,
            destination_longitude=destination.longitude,
            passenger_count=passenger_count, payment_status="unpaid", status="requested",
            created_at=now, updated_at=now,
        )

    # ------------------------------------------------------------ review
    async def approve(self, request_id: str, *, by: User, fee: Decimal,
                      fee_note: str) -> SpecialTripRequest:
        request = await self._locked(request_id)
        if request.status != "requested":
            raise ConflictError(f"This request is already {request.status}.")
        if request.pickup_at <= _now():
            raise ConflictError("Its pickup time has passed: reject it, or ask the "
                                "passenger for a new request.")
        trip = await self._approve(request, by=by, fee=fee, fee_note=fee_note)
        await self.notifications.notify_passenger(
            user_id=request.passenger_user_id, title="Special trip approved",
            message=(f"Your van on {request.pickup_at:%d %b %H:%M} is approved. The fee is "
                     f"₱{fee:,.2f} ({fee_note}). Pay it before the van leaves; a van and a "
                     "Dispatcher are assigned at the van's turn."),
            entity=("trip", trip.trip_id),
        )
        await self.session.commit()
        return request

    async def _approve(self, request: SpecialTripRequest, *, by: User, fee: Decimal,
                       fee_note: str) -> Trip:
        """Agree the fee and create the trip: no route, no stops."""
        policies = PolicyRepository(self.session)
        now = _now()
        who = request.customer_name or display_name(
            await self.session.get(User, request.passenger_user_id))
        trip = Trip(
            trip_id=str(uuid.uuid4()),
            template_id=None,
            route_id=None,
            service_date=request.pickup_at.date(),
            departure_datetime=request.pickup_at,
            trip_label=f"Rental · {who}"[:64],
            is_special_trip=True,
            seat_capacity=await policies.get_int("default_seat_capacity"),
            # Nobody books a seat on a rented van: the renter has it all.
            advance_booking_seat_cap=0,
            reschedule_cutoff_hours=await policies.get_int("reschedule_cutoff_hours"),
            status=TripStatus.SCHEDULED.value,
            created_at=now,
            updated_at=now,
        )
        self.session.add(trip)
        await self.session.flush()
        request.rental_fee = fee
        request.fee_note = fee_note
        request.trip_id = trip.trip_id
        request.status = "approved"
        request.reviewed_by = by.user_id
        request.reviewed_at = now
        request.updated_at = now
        return trip

    async def reject(self, request_id: str, *, by: User, reason: str) -> SpecialTripRequest:
        request = await self._locked(request_id)
        if request.status != "requested":
            raise ConflictError(f"This request is already {request.status}.")
        now = _now()
        request.status = "rejected"
        request.reviewed_by = by.user_id
        request.reviewed_at = now
        request.updated_at = now
        await self.notifications.notify_passenger(
            user_id=request.passenger_user_id, title="Special trip not approved",
            message=f"Your van on {request.pickup_at:%d %b %H:%M} was not approved: {reason}",
            entity=(ENTITY, request.request_id),
        )
        await self.session.commit()
        return request

    async def withdraw(self, request_id: str, *, by: User) -> SpecialTripRequest:
        """The passenger takes back a request nobody has approved yet."""
        request = await self._locked(request_id)
        if request.passenger_user_id != by.user_id:
            raise NotFoundError("Request not found.")
        if request.status != "requested":
            raise ConflictError(
                f"This request is {request.status}. Once approved, ask the terminal "
                "office to cancel the trip; the fee is not refunded."
            )
        request.status = "cancelled"
        request.updated_at = _now()
        await self.session.commit()
        return request

    # ------------------------------------------------------------ the fee
    async def log_cash(self, request_id: str, *, by: User) -> SpecialTripRequest:
        """The trip's Dispatcher received the agreed fee in cash at the
        terminal: declared income (T51). Its share joins the statement."""
        request = await self._locked(request_id)
        if request.status != "approved":
            raise ConflictError(f"This request is {request.status}.")
        if request.payment_status == "paid":
            raise ConflictError("The fee is already paid.")
        trip = await self.session.get(Trip, request.trip_id)
        if by.role == Role.DISPATCHER.value and trip.dispatcher_id != by.user_id:
            raise NotFoundError("Request not found.")
        if trip.status not in (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value):
            raise ConflictError(f"This trip is {trip.status}.")
        request.payment_status = "paid"
        request.payment_reference = None
        request.updated_at = _now()
        await self.session.flush()
        await Statements(self.session).sync(trip)
        await self.session.commit()
        return request

    # ------------------------------------------------------------ helpers
    async def _locked(self, request_id: str) -> SpecialTripRequest:
        request = (await self.session.execute(
            select(SpecialTripRequest).where(SpecialTripRequest.request_id == request_id)
            .with_for_update()
        )).scalar_one_or_none()
        if request is None:
            raise NotFoundError("Request not found.")
        return request
