"""Booking entity.

Note the create() / reconstitute() split. Sprint 1's entities validated in
__post_init__ unconditionally, which is correct when a user creates
something and wrong when the repository loads history: a completed
booking from last week would fail a "departure must be in the future"
check and make the revenue dashboard unloadable.

    create()        -- new booking, enforces creation invariants
    reconstitute()  -- rebuild from a database row, trusts stored state

State transitions are guarded in both cases.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from app.core.exceptions import ConflictError, PolicyViolationError
from app.domain.enums import BookingStatus, BookingType
from app.domain.value_objects import Segment

_ACTIVE = {
    BookingStatus.PENDING,
    BookingStatus.CONFIRMED,
    BookingStatus.CHECKED_IN,
}
_TERMINAL = {
    BookingStatus.COMPLETED,
    BookingStatus.CANCELLED,
    BookingStatus.NO_SHOW,
    BookingStatus.RESCHEDULED,
}


@dataclass
class Booking:
    booking_id: str
    ticket_number: str
    trip_id: str
    segment: Segment
    seat_number: int
    fare_amount: Decimal
    booking_type: BookingType
    status: BookingStatus

    passenger_user_id: str | None = None
    walkin_name: str | None = None
    walkin_phone: str | None = None
    walkin_wants_receipt: bool = False

    qr_payload: str | None = None
    rescheduled_from_booking_id: str | None = None
    reschedule_count: int = 0
    booked_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    # -- construction ---------------------------------------------------
    @classmethod
    def create(
        cls,
        *,
        trip_id: str,
        segment: Segment,
        seat_number: int,
        fare_amount: Decimal,
        booking_type: BookingType,
        passenger_user_id: str | None = None,
        walkin_name: str | None = None,
        walkin_phone: str | None = None,
        walkin_wants_receipt: bool = False,
    ) -> Booking:
        # Consultation: walk-in passenger details are OPTIONAL -- provided
        # only if the passenger wants a receipt. App bookings still need an
        # account, since that is who the e-ticket belongs to.
        if booking_type is BookingType.APP and not passenger_user_id:
            raise ConflictError("An app booking requires an authenticated passenger.")
        if fare_amount < 0:
            raise ConflictError("Fare cannot be negative.")

        booking_id = str(uuid.uuid4())
        return cls(
            booking_id=booking_id,
            ticket_number=cls._generate_ticket_number(),
            trip_id=trip_id,
            segment=segment,
            seat_number=seat_number,
            fare_amount=fare_amount,
            booking_type=booking_type,
            status=(
                BookingStatus.PENDING
                if booking_type is BookingType.APP
                else BookingStatus.CONFIRMED  # walk-ins pay cash on the spot
            ),
            passenger_user_id=passenger_user_id,
            walkin_name=walkin_name,
            walkin_phone=walkin_phone,
            walkin_wants_receipt=walkin_wants_receipt,
            qr_payload=f"SBG-{booking_id}",
        )

    @classmethod
    def reconstitute(cls, **row) -> Booking:
        """Rebuild from persistence without re-running creation invariants."""
        return cls(**row)

    @staticmethod
    def _generate_ticket_number() -> str:
        stamp = datetime.now(timezone.utc).strftime("%y%m%d")
        return f"SBG-{stamp}-{uuid.uuid4().hex[:6].upper()}"

    # -- transitions ----------------------------------------------------
    def confirm_payment(self) -> None:
        if self.status is not BookingStatus.PENDING:
            raise ConflictError(f"Cannot confirm a booking that is {self.status.value}.")
        self.status = BookingStatus.CONFIRMED

    def check_in(self) -> None:
        if self.status is not BookingStatus.CONFIRMED:
            raise ConflictError(
                f"Only confirmed bookings can check in; this one is {self.status.value}."
            )
        self.status = BookingStatus.CHECKED_IN

    def board(self) -> None:
        if self.status not in (BookingStatus.CONFIRMED, BookingStatus.CHECKED_IN):
            raise ConflictError(f"Cannot board a booking that is {self.status.value}.")
        self.status = BookingStatus.BOARDED

    def mark_no_show(self) -> None:
        if self.status in _TERMINAL or self.status is BookingStatus.BOARDED:
            raise ConflictError(f"Cannot mark {self.status.value} booking as no-show.")
        self.status = BookingStatus.NO_SHOW

    def cancel(self) -> None:
        if self.status in _TERMINAL:
            raise ConflictError(f"Booking is already {self.status.value}.")
        if self.status is BookingStatus.BOARDED:
            raise ConflictError("Cannot cancel a booking after boarding.")
        self.status = BookingStatus.CANCELLED

    # -- policy ---------------------------------------------------------
    def assert_can_reschedule(
        self,
        *,
        departure: datetime,
        cutoff_hours: int,
        max_reschedules: int,
        now: datetime | None = None,
    ) -> None:
        """Consultation policy: no refunds, reschedule allowed inside a window.

        Both limits come from cooperative_policies, snapshotted onto the
        trip at generation time -- so a later policy change never alters
        the terms a passenger already bought under.
        """
        now = now or datetime.now(timezone.utc)
        if departure.tzinfo is None:
            departure = departure.replace(tzinfo=timezone.utc)

        if self.status not in _ACTIVE:
            raise ConflictError(f"A {self.status.value} booking cannot be rescheduled.")
        if self.reschedule_count >= max_reschedules:
            raise PolicyViolationError(
                f"This booking has already been rescheduled {self.reschedule_count} "
                f"time(s); the cooperative allows {max_reschedules}."
            )
        if now > departure - timedelta(hours=cutoff_hours):
            raise PolicyViolationError(
                f"Reschedule closes {cutoff_hours} hour(s) before departure."
            )

    def mark_rescheduled(self) -> None:
        self.status = BookingStatus.RESCHEDULED