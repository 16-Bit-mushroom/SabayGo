"""Release of unpaid reservations at the cutoff (brief 2.1, 4.2 rule 15).

A reservation made in the app is CONFIRMED and UNPAID: it holds one of
the 14 seats, but it is not on the passenger list and adds nothing to
what the van owes. Only the Dispatcher's Mark as Paid changes that. So a
reservation nobody pays for would otherwise keep a seat out of the 14
until the van left, and a walk-up standing at the terminal would be
turned away for a passenger who never came.

This job releases it `unpaid_cutoff_min` minutes before departure
(default 30, the same as the start window, so the list is settled when
Start opens): status Cancelled, `cancel_reason = 'auto_release'`,
`cancelled_by` NULL -- no person decided it -- and the passenger is told.

Two things it deliberately does not do:

  * **A check-in does not save the seat** (brief item 12c, test T61).
    Tapping "I'm here" says where a phone is, not that money changed
    hands, and the whole point of the cash rule is that only the
    Dispatcher can attest to the cash.
  * **It never touches a paid seat.** Once the Dispatcher has the fare,
    the seat is on the list and stays there, no-show or not.

Before the cutoff each passenger gets one reminder to pay at the
terminal. It is sent one cutoff-length before the cutoff -- 30 minutes
earlier when the cutoff is 30 -- so the passenger has as long to act as
the rule allows, and so A2Z has one number to set rather than two.

The restore path for a Paid mark that syncs *after* a release is the
other half of this rule, and lives with the mark that causes it:
`cash.py`, `CashDesk._restore_released` (tests T62 and T63).
"""

from __future__ import annotations

import logging
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.booking.cash import STANDING, cancel_seat
from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.domain.enums import BookingStatus, CancelReason, PaymentStatus, TripStatus
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Notification, Trip
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

# The trip has not left the terminal, so its seats are still worth
# freeing. Past 'boarding' the van is gone and the list is history.
BEFORE_DEPARTURE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)

REMINDER_TYPE = "departure_reminder"


class UnpaidRelease:
    """One sweep: remind whoever is close to the cutoff, release the rest."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def run(self) -> tuple[int, int]:
        """Returns (reminders sent, seats released). Does not commit."""
        cutoff = await PolicyRepository(self.session).get_int("unpaid_cutoff_min")
        now = app_tz.now().replace(tzinfo=None)
        # One query for both halves: everything unpaid whose departure is
        # inside twice the cutoff, split on the cutoff itself.
        horizon = now + timedelta(minutes=cutoff * 2)
        rows = (await self.session.execute(
            select(BookingRow, Trip)
            .join(Trip, Trip.trip_id == BookingRow.trip_id)
            .where(
                BookingRow.status.in_(STANDING),
                # Not filtered by booking type: a walk-up hands over the
                # cash as it is listed, so an unpaid seat of any kind is
                # a seat nobody has paid for.
                BookingRow.payment_status == PaymentStatus.UNPAID.value,
                Trip.status.in_(BEFORE_DEPARTURE),
                Trip.departure_datetime <= horizon,
            )
            .order_by(Trip.departure_datetime, BookingRow.booked_at)
        )).all()
        if not rows:
            return 0, 0

        due = now + timedelta(minutes=cutoff)
        reminded = await self._remind(
            [(b, t) for b, t in rows if t.departure_datetime > due]
        )
        released = 0
        for booking, trip in rows:
            if trip.departure_datetime > due:
                continue
            # Both seats of a home pickup are in this list, and cancelling
            # the relative's already cancelled the other.
            if booking.status == BookingStatus.CANCELLED.value:
                continue
            await self._release(booking, trip)
            released += 1
        return reminded, released

    # ------------------------------------------------------------------
    async def _release(self, booking: BookingRow, trip: Trip) -> None:
        await cancel_seat(self.session, booking, CancelReason.AUTO_RELEASE, by=None)
        if booking.passenger_user_id:
            await NotificationService(self.session).notify_passenger(
                user_id=booking.passenger_user_id,
                title="Reservation released",
                message=(
                    f"Seat {booking.booking_code} on {trip_label(trip)} was "
                    "not paid before the cutoff, so it has been released. "
                    "You can reserve again if a seat is free."
                ),
                entity=("booking", booking.booking_id),
            )
        log.info(
            "Released unpaid seat %s on trip %s",
            booking.booking_code, trip.trip_id,
        )

    async def _remind(self, pending: list[tuple[BookingRow, Trip]]) -> int:
        """One reminder for each reservation, however many times we sweep.

        Already-sent reminders are read back from `notifications` rather
        than marked on the booking: the notification row *is* the record
        that the passenger was told, and a second column saying the same
        thing could disagree with it.
        """
        pending = [(b, t) for b, t in pending if b.passenger_user_id]
        if not pending:
            return 0
        already = set((await self.session.scalars(
            select(Notification.related_entity_id).where(
                Notification.type == REMINDER_TYPE,
                Notification.related_entity_type == "booking",
                Notification.related_entity_id.in_([b.booking_id for b, _ in pending]),
            )
        )).all())
        notifications = NotificationService(self.session)
        sent = 0
        for booking, trip in pending:
            if booking.booking_id in already:
                continue
            await notifications.notify_passenger(
                user_id=booking.passenger_user_id,
                title="Pay at the terminal",
                message=(
                    f"Pay P{booking.fare_amount:,.2f} in cash to the "
                    f"Dispatcher at the terminal for seat "
                    f"{booking.booking_code} on {trip_label(trip)}. An "
                    "unpaid reservation is released before departure."
                ),
                entity=("booking", booking.booking_id),
                type=REMINDER_TYPE,
            )
            sent += 1
        return sent


async def release_unpaid_reservations(session_factory) -> None:
    """A `PeriodicJob` tick (`main.py`)."""
    async with session_factory() as session:
        reminded, released = await UnpaidRelease(session).run()
        if reminded or released:
            await session.commit()
            log.info(
                "Unpaid sweep: %d reminder(s), %d seat(s) released.",
                reminded, released,
            )
