"""The Dispatcher's cash desk at the terminal (brief rev 721, 2.1).

A2Z handles only cash. A passenger reserves a seat in the app and gets a
booking code; at the terminal the passenger hands the fare to the
Dispatcher, who finds the reservation **by name or booking code** and
**marks it Paid**. That mark is what puts the seat on the passenger list,
what counts it into Booked income, and what stops the cutoff job
releasing it (section 4.2 rule 15). A check-in does not: the app cannot
verify that money changed hands.

Cancellation has two doors, because the cash is outside the system once
it is in a pocket:

  * the **passenger** cancels in the app, and only while the seat is
    unpaid -- nothing has to be handed back;
  * the **Dispatcher** cancels a seat the passenger asked about in the
    chat, returning any cash already taken, or clears an unpaid
    reservation whose passenger never came.

Both close when the trip's list locks -- the Cashier records the payment,
or the van departs, whichever comes first. After that there is no
cancellation, no refund and no credit, so nothing here has to compute one.

These run on the Dispatcher's own phone, which works offline: the marks
and cancellations are queued on the device and replayed when the
connection returns. Each one is therefore written to be safe to repeat.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.booking.home_pickup import HomePickups
from app.application.notifications.service import NotificationService
from app.core.exceptions import ConflictError, NotFoundError, PolicyViolationError
from app.core.timezone import APP_TZ
from app.domain.enums import (
    BookingStatus,
    BookingType,
    CancelReason,
    PaymentStatus,
    TripStatus,
)
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import PassengerProfile, Trip, User
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)

# The list is still open while the van is loading. 'en_route' and beyond
# are past the lock.
OPEN_FOR_CASH = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)

# A reservation a Dispatcher can still act on.
STANDING = (BookingStatus.CONFIRMED.value, BookingStatus.CHECKED_IN.value)


@dataclass(frozen=True)
class SeatOnList:
    booking_id: str
    booking_code: str
    passenger_name: str | None
    contact_number: str | None
    alighting_stop: int
    fare_amount: object
    booking_type: str
    status: str
    payment_status: str
    is_home_pickup_seat: bool
    paid_at: datetime | None


class CashDesk:
    def __init__(self, session: AsyncSession):
        self.session = session
        # Set by mark_paid when the seat belonged to a home pickup, so
        # the Dispatcher's screen can say whether it is now activated.
        self.pickup_note: str | None = None

    # ---------------------------------------------------------- search
    async def find(self, *, trip_id: str, query: str | None = None) -> list[SeatOnList]:
        """The trip's reservations, narrowed by name or booking code.

        One search box, because at the van door the Dispatcher has
        whatever the passenger says -- a name or the code on their
        screen -- and should not have to choose which kind it is first.
        """
        stmt = (
            select(BookingRow, PassengerProfile, User)
            .join(
                PassengerProfile,
                PassengerProfile.user_id == BookingRow.passenger_user_id,
                isouter=True,
            )
            .join(User, User.user_id == BookingRow.passenger_user_id, isouter=True)
            .where(
                BookingRow.trip_id == trip_id,
                BookingRow.status.notin_(
                    [BookingStatus.CANCELLED.value, BookingStatus.NO_SHOW.value]
                ),
            )
            .order_by(BookingRow.payment_status, BookingRow.booked_at)
        )
        if query:
            term = f"%{query.strip()}%"
            stmt = stmt.where(
                or_(
                    BookingRow.booking_code.like(term),
                    BookingRow.walkin_name.like(term),
                    func.concat(
                        PassengerProfile.first_name, " ", PassengerProfile.last_name
                    ).like(term),
                )
            )
        rows = (await self.session.execute(stmt)).all()
        return [
            SeatOnList(
                booking_id=b.booking_id,
                booking_code=b.booking_code,
                passenger_name=(
                    f"{pp.first_name} {pp.last_name}" if pp else b.walkin_name
                ),
                contact_number=(u.phone_number if u else b.walkin_phone),
                alighting_stop=b.alighting_stop_sequence,
                fare_amount=b.fare_amount,
                booking_type=b.booking_type,
                status=b.status,
                payment_status=b.payment_status,
                is_home_pickup_seat=bool(b.is_home_pickup_seat),
                paid_at=b.paid_at,
            )
            for b, pp, u in rows
        ]

    # ------------------------------------------------------ mark as paid
    async def mark_paid(
        self, *, booking_id: str, by: User, at: datetime | None = None
    ) -> BookingRow:
        """The passenger handed over the cash.

        `at` is the time the Dispatcher's device recorded, so a mark made
        offline keeps the moment it happened rather than the moment it
        synced -- the order of `paid_at` is what the door-event check
        consumes seats in.
        """
        booking = await self.booking(booking_id)
        trip = await self._open_trip(booking)

        if booking.payment_status == PaymentStatus.PAID.value:
            # A replayed offline mark. Nothing to do and nothing wrong.
            return booking
        if booking.status not in STANDING:
            raise ConflictError(
                f"This seat is {booking.status} and cannot be marked paid."
            )

        booking.payment_status = PaymentStatus.PAID.value
        booking.paid_at = _naive(at or datetime.now(APP_TZ))
        booking.paid_by = by.user_id
        booking.updated_at = _naive(datetime.now(APP_TZ))
        await self.session.flush()

        # A home pickup is activated by the cash for its seats, not by a
        # scan or a screenshot (brief 2.6).
        self.pickup_note = await HomePickups(self.session).on_seat_paid(
            booking, by=by.user_id
        )
        await self.session.flush()

        log.info(
            "Seat %s on trip %s marked paid by %s",
            booking.booking_code, trip.trip_id, by.user_id,
        )
        return booking

    # ---------------------------------------------------- cancellation
    async def cancel_by_passenger(self, *, booking_id: str, user: User) -> BookingRow:
        """In the app, and only while the seat is unpaid (brief 2.1)."""
        booking = await self.booking(booking_id)
        if booking.passenger_user_id != user.user_id:
            raise NotFoundError("Booking not found.")
        if booking.payment_status == PaymentStatus.PAID.value:
            raise PolicyViolationError(
                "This seat is paid. Message the Dispatcher to cancel it, so "
                "the cash can be handed back to you."
            )
        # The app is online when it asks, so a second cancel is a real
        # mistake and should say so.
        return await self._cancel(
            booking, CancelReason.PASSENGER, by=None, tolerate_replay=False
        )

    async def cancel_by_dispatcher(
        self, *, booking_id: str, reason: CancelReason, by: User
    ) -> BookingRow:
        """At the passenger's request, or for a reservation nobody came for."""
        if reason not in (
            CancelReason.PASSENGER_ASKED_DISPATCHER,
            CancelReason.FORGOT_TO_CANCEL,
        ):
            raise ConflictError(f"A Dispatcher cannot cancel a seat as {reason.value}.")
        booking = await self.booking(booking_id)
        if (
            reason is CancelReason.FORGOT_TO_CANCEL
            and booking.payment_status == PaymentStatus.PAID.value
        ):
            raise ConflictError(
                "This seat is paid, so it was not forgotten. Cancel it at the "
                "passenger's request instead, and hand the cash back."
            )
        return await self._cancel(booking, reason, by=by, tolerate_replay=True)

    # ------------------------------------------------------------------
    async def _cancel(
        self,
        booking: BookingRow,
        reason: CancelReason,
        *,
        by: User | None,
        tolerate_replay: bool,
    ) -> BookingRow:
        if booking.status == BookingStatus.CANCELLED.value:
            # The Dispatcher's device may replay a cancellation it queued
            # offline; the passenger's app, which is online when it asks,
            # may not.
            if tolerate_replay:
                return booking
            raise ConflictError("This booking is already cancelled.")
        if booking.status not in STANDING:
            raise ConflictError(f"A {booking.status} seat cannot be cancelled.")

        trip = await self._open_trip(booking)
        if trip.list_locked_at is not None:
            raise PolicyViolationError(
                "The passenger list for this trip is locked. There is no "
                "cancellation, refund or credit after that."
            )

        now = _naive(datetime.now(APP_TZ))
        booking.status = BookingStatus.CANCELLED.value
        booking.cancelled_at = now
        booking.cancelled_by = by.user_id if by else None
        booking.cancel_reason = reason.value
        booking.updated_at = now
        # The seat goes back into the 14 straight away, so a walk-up can
        # take it (brief 2.3).
        await SeatRepository(self.session).release(booking_id=booking.booking_id)
        # Neither seat of a home pickup stands alone: cancelling the
        # relative's seat cancels the pickup and the passenger's with it,
        # because the van is never sent to a house without the relative
        # aboard (brief 2.6).
        await HomePickups(self.session).on_cancelled(booking)
        await self.session.flush()

        if booking.passenger_user_id and by is not None:
            await NotificationService(self.session).notify_passenger(
                user_id=booking.passenger_user_id,
                title="Reservation cancelled",
                message=(
                    f"The Dispatcher cancelled seat {booking.booking_code}. "
                    "Any cash you had already paid is returned to you at the "
                    "terminal."
                ),
                entity=("booking", booking.booking_id),
            )

        log.info(
            "Seat %s cancelled (%s) by %s",
            booking.booking_code, reason.value, by.user_id if by else "passenger",
        )
        return booking

    async def booking(self, booking_id: str) -> BookingRow:
        booking = await self.session.get(BookingRow, booking_id)
        if booking is None:
            raise NotFoundError("Booking not found.")
        return booking

    async def _open_trip(self, booking: BookingRow) -> Trip:
        trip = await self.session.get(Trip, booking.trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")
        if trip.status not in OPEN_FOR_CASH:
            raise ConflictError(
                f"This trip is {trip.status}: its passenger list is closed."
            )
        return trip


def _naive(value: datetime) -> datetime:
    """MySQL stores naive local time (app.core.timezone)."""
    return value.replace(tzinfo=None) if value.tzinfo else value
