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

import secrets
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal

from app.core.timezone import APP_TZ
from app.core.exceptions import ConflictError, PolicyViolationError
from app.domain.enums import BookingStatus, BookingType, PaymentStatus
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
}

# The unambiguous half of the alphabet: no I, O, 0 or 1, because the
# passenger reads the code out loud and the Dispatcher types it.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LENGTH = 6


@dataclass
class Booking:
    booking_id: str
    booking_code: str
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

    payment_status: PaymentStatus = PaymentStatus.UNPAID
    booked_at: datetime = field(default_factory=lambda: datetime.now(APP_TZ))

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
            booking_code=cls.generate_code(),
            trip_id=trip_id,
            segment=segment,
            seat_number=seat_number,
            fare_amount=fare_amount,
            booking_type=booking_type,
            # A reservation is confirmed the moment it is made: there is
            # no payment round trip left to wait for. It is still UNPAID,
            # which is what keeps it off the passenger list and exposes
            # it to the cutoff release.
            #
            # A walk-up pays the Dispatcher as it is listed and is aboard
            # already. 'confirmed' would read as "not yet boarded" on the
            # manifest, and departure would make the passenger a no-show
            # and release a space someone is sitting in.
            status=(
                BookingStatus.CONFIRMED
                if booking_type is BookingType.APP
                else BookingStatus.BOARDED
            ),
            payment_status=(
                PaymentStatus.UNPAID
                if booking_type is BookingType.APP
                else PaymentStatus.PAID
            ),
            passenger_user_id=passenger_user_id,
            walkin_name=walkin_name,
            walkin_phone=walkin_phone,
            walkin_wants_receipt=walkin_wants_receipt,
        )

    @classmethod
    def reconstitute(cls, **row) -> Booking:
        """Rebuild from persistence without re-running creation invariants."""
        return cls(**row)

    @staticmethod
    def generate_code() -> str:
        """A short code the passenger gives the Dispatcher (brief 2.1).

        Short because it is spoken across a counter, not scanned: the
        brief's example is SG-4821. Four digits would be 10,000 codes and
        the column is UNIQUE, so collisions would surface as errors at
        the busiest moment; six characters of a 32-letter alphabet is
        about a billion. The caller retries on the unique constraint.
        """
        body = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(_CODE_LENGTH))
        return f"SG-{body}"

    # -- transitions ----------------------------------------------------
    def mark_paid(self) -> None:
        """The Dispatcher took the cash at the terminal (brief 2.1).

        This, and only this, puts the seat on the passenger list and
        stops the cutoff job releasing it. A check-in does not.
        """
        if self.payment_status is PaymentStatus.PAID:
            raise ConflictError("This seat is already marked paid.")
        if self.status in _TERMINAL:
            raise ConflictError(f"Cannot take cash for a {self.status.value} booking.")
        self.payment_status = PaymentStatus.PAID

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

    def assert_passenger_may_cancel(self) -> None:
        """A passenger cancels only an unpaid reservation (brief 2.1).

        Once the cash is in the Dispatcher's hand the money is outside
        the system, so returning it has to be a person's act: the
        passenger asks in the chat and the Dispatcher cancels.
        """
        if self.payment_status is PaymentStatus.PAID:
            raise PolicyViolationError(
                "This seat is paid. Ask the Dispatcher to cancel it so the "
                "cash can be returned to you."
            )
