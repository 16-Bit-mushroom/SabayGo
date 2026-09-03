"""Reschedule and cancel.

Cooperative policy from the consultation: NO REFUNDS, but a booking may be
moved to another trip within a cutoff window.

Design decision -- a reschedule keeps the SAME SEGMENT and only changes the
trip. Allowing the segment to change too would mean handling fare
differences, which under a no-refund policy has no sensible answer when the
new segment is cheaper. Keeping the segment fixed sidesteps that entirely
and matches how a passenger actually thinks about it: same journey,
different departure.

The old booking is not deleted. It becomes 'rescheduled' and the new one
points back at it via rescheduled_from_booking_id, so the audit trail
survives and reschedule_count can be enforced across the chain.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timezone import APP_TZ
from app.core.exceptions import ConflictError, NotFoundError, PolicyViolationError
from app.domain.entities.booking import Booking as BookingEntity
from app.domain.enums import BookingStatus, BookingType, PaymentStatus, TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Payment as PaymentRow
from app.infrastructure.models import Trip
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class RescheduleResult:
    old_booking_id: str
    new_booking_id: str
    new_ticket_number: str
    new_trip_id: str
    seat_number: int
    reschedule_count: int
    qr_payload: str | None


class RescheduleBookingUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)
        self.policies = PolicyRepository(session)

    async def execute(
        self, *, booking_id: str, new_trip_id: str, passenger_user_id: str
    ) -> RescheduleResult:
        row = await self.session.get(BookingRow, booking_id)
        if row is None or row.passenger_user_id != passenger_user_id:
            raise NotFoundError("Booking not found.")

        old_trip = await self.session.get(Trip, row.trip_id)
        if old_trip is None:
            raise NotFoundError("Original trip not found.")

        segment = Segment(row.boarding_stop_sequence, row.alighting_stop_sequence)

        # Rebuild the entity from persistence WITHOUT re-running creation
        # invariants -- this is exactly what reconstitute() exists for.
        entity = BookingEntity.reconstitute(
            booking_id=row.booking_id,
            ticket_number=row.ticket_number,
            trip_id=row.trip_id,
            segment=segment,
            seat_number=row.seat_number,
            fare_amount=row.fare_amount,
            booking_type=BookingType(row.booking_type),
            status=BookingStatus(row.status),
            passenger_user_id=row.passenger_user_id,
            qr_payload=row.qr_payload,
            reschedule_count=row.reschedule_count,
            booked_at=row.booked_at,
        )

        max_reschedules = await self.policies.get_int("max_reschedules_per_booking")

        # Cutoff comes from the trip snapshot, not the live policy row: the
        # passenger bought under the terms in force at booking time, and a
        # later policy change must not retroactively shorten their window.
        entity.assert_can_reschedule(
            departure=old_trip.departure_datetime,
            cutoff_hours=old_trip.reschedule_cutoff_hours,
            max_reschedules=max_reschedules,
        )

        new_trip = await self.session.get(Trip, new_trip_id)
        if new_trip is None:
            raise NotFoundError("Target trip not found.")
        if new_trip.trip_id == old_trip.trip_id:
            raise ConflictError("That is the same trip.")
        if new_trip.route_id != old_trip.route_id:
            raise PolicyViolationError(
                "A booking can only be moved to another trip on the same route."
            )
        if new_trip.status != TripStatus.SCHEDULED.value:
            raise ConflictError(f"Target trip is {new_trip.status}.")

        departure = new_trip.departure_datetime
        if departure.tzinfo is None:
            departure = departure.replace(tzinfo=APP_TZ)
        if departure <= datetime.now(APP_TZ):
            raise ConflictError("Target trip has already departed.")

        # Claim the new seat BEFORE releasing the old one. If allocation
        # fails the transaction rolls back and the passenger keeps their
        # original seat -- releasing first would risk stranding them with
        # neither.
        hold_ttl = await self.policies.get_int("seat_hold_ttl_seconds")
        new_seat = await self.seats.allocate_seat(
            trip_id=new_trip_id, segment=segment, hold_ttl_seconds=hold_ttl
        )

        now = datetime.now(APP_TZ)
        new_id = str(uuid.uuid4())
        new_ticket = BookingEntity._generate_ticket_number()
        was_paid = row.status in (
            BookingStatus.CONFIRMED.value,
            BookingStatus.CHECKED_IN.value,
        )

        self.session.add(
            BookingRow(
                booking_id=new_id,
                ticket_number=new_ticket,
                trip_id=new_trip_id,
                passenger_user_id=row.passenger_user_id,
                booking_type=row.booking_type,
                boarding_stop_sequence=segment.boarding_stop,
                alighting_stop_sequence=segment.alighting_stop,
                seat_number=new_seat,
                # No refund and no top-up: the fare already paid carries over.
                fare_amount=row.fare_amount,
                status=(
                    BookingStatus.CONFIRMED.value
                    if was_paid
                    else BookingStatus.PENDING.value
                ),
                qr_payload=f"SBG-{new_id}",
                rescheduled_from_booking_id=row.booking_id,
                reschedule_count=row.reschedule_count + 1,
                booked_at=now,
                created_at=now,
                updated_at=now,
            )
        )
        await self.session.flush()

        await self.seats.bind_to_booking(
            trip_id=new_trip_id, seat_number=new_seat,
            segment=segment, booking_id=new_id,
        )

        if was_paid:
            # Payment already settled -- the new seat is confirmed outright
            # and the payment record follows the booking forward.
            await self.seats.confirm(booking_id=new_id)
            payments = await self.session.execute(
                select(PaymentRow).where(
                    PaymentRow.booking_id == row.booking_id,
                    PaymentRow.status == PaymentStatus.PAID.value,
                )
            )
            for payment in payments.scalars():
                payment.booking_id = new_id

        await self.seats.release(booking_id=row.booking_id)
        row.status = BookingStatus.RESCHEDULED.value
        row.updated_at = now

        await self.session.commit()
        log.info(
            "Rescheduled %s -> %s (trip %s -> %s, seat %s)",
            row.booking_id, new_id, old_trip.trip_id, new_trip_id, new_seat,
        )

        return RescheduleResult(
            old_booking_id=row.booking_id,
            new_booking_id=new_id,
            new_ticket_number=new_ticket,
            new_trip_id=new_trip_id,
            seat_number=new_seat,
            reschedule_count=row.reschedule_count + 1,
            qr_payload=f"SBG-{new_id}",
        )


class CancelBookingUseCase:
    """Cancel a booking. No refund is issued -- cooperative policy."""

    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)

    async def execute(
        self, *, booking_id: str, passenger_user_id: str | None = None
    ) -> dict[str, str]:
        row = await self.session.get(BookingRow, booking_id)
        if row is None:
            raise NotFoundError("Booking not found.")
        if passenger_user_id and row.passenger_user_id != passenger_user_id:
            raise NotFoundError("Booking not found.")

        segment = Segment(row.boarding_stop_sequence, row.alighting_stop_sequence)
        entity = BookingEntity.reconstitute(
            booking_id=row.booking_id,
            ticket_number=row.ticket_number,
            trip_id=row.trip_id,
            segment=segment,
            seat_number=row.seat_number,
            fare_amount=row.fare_amount,
            booking_type=BookingType(row.booking_type),
            status=BookingStatus(row.status),
            passenger_user_id=row.passenger_user_id,
            reschedule_count=row.reschedule_count,
            booked_at=row.booked_at,
        )
        # Cooperative policy may close cancellation some hours before
        # departure. 0 means it stays open until the van leaves, which
        # was the previous behaviour.
        cutoff = await PolicyRepository(self.session).get_int(
            "cancel_cutoff_hours"
        )
        if cutoff > 0:
            trip = await self.session.get(Trip, row.trip_id)
            if trip is not None:
                departure = trip.departure_datetime
                if departure.tzinfo is None:
                    departure = departure.replace(tzinfo=APP_TZ)
                if datetime.now(APP_TZ) > departure - timedelta(hours=cutoff):
                    raise PolicyViolationError(
                        f"Cancellation closes {cutoff} hour(s) before "
                        "departure."
                    )

        entity.cancel()  # raises if already terminal or boarded

        now = datetime.now(APP_TZ)
        row.status = BookingStatus.CANCELLED.value
        row.cancelled_at = now
        row.updated_at = now

        # Return the seat-legs to the pool so someone else can book them.
        await self.seats.release(booking_id=booking_id)
        await self.session.commit()

        log.info("Cancelled booking %s (seat %s released)", booking_id, row.seat_number)
        return {
            "booking_id": booking_id,
            "status": BookingStatus.CANCELLED.value,
            "refund": "none",
            "note": "Cooperative policy: cancellations are not refunded.",
        }
