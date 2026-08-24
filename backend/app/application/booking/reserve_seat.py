"""Reserve-seat use case.

Orchestration only: it holds the transaction boundary and calls domain and
repositories. No SQL here, no business rules here -- rules live in the
Booking entity, SQL lives in the repository.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timezone import APP_TZ
from app.core.exceptions import ConflictError, NotFoundError, PolicyViolationError
from app.domain.entities.booking import Booking as BookingEntity
from app.domain.enums import BookingStatus, BookingType, TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import FareMatrix, Trip
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class ReserveSeatCommand:
    trip_id: str
    boarding_stop: int
    alighting_stop: int
    booking_type: BookingType = BookingType.APP
    passenger_user_id: str | None = None
    walkin_name: str | None = None
    walkin_phone: str | None = None
    walkin_wants_receipt: bool = False


@dataclass(frozen=True)
class ReserveSeatResult:
    booking_id: str
    ticket_number: str
    seat_number: int
    fare_amount: Decimal
    status: BookingStatus
    qr_payload: str | None


class ReserveSeatUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)
        self.policies = PolicyRepository(session)

    async def execute(self, cmd: ReserveSeatCommand) -> ReserveSeatResult:
        segment = Segment(cmd.boarding_stop, cmd.alighting_stop)

        trip = await self.session.get(Trip, cmd.trip_id)
        if trip is None:
            raise NotFoundError(f"Trip {cmd.trip_id} not found.")
        if trip.status != TripStatus.SCHEDULED.value:
            raise ConflictError(f"Trip is {trip.status}; bookings are closed.")

        departure = trip.departure_datetime
        if departure.tzinfo is None:
            departure = departure.replace(tzinfo=APP_TZ)
        if departure <= datetime.now(APP_TZ):
            raise ConflictError("This trip has already departed.")

        fare = await self._lookup_fare(trip.route_id, segment)

        

        # ---- the locked section -------------------------------------
        hold_ttl = await self.policies.get_int("seat_hold_ttl_seconds")
        seat_number = await self.seats.allocate_seat(
            trip_id=cmd.trip_id, segment=segment, hold_ttl_seconds=hold_ttl
        )

        # Cap check MUST run inside the lock. Before allocate_seat() this was
        # an unlocked COUNT: concurrent requests all read the same stale
        # value, all passed, and the cap was exceeded. Holding the seat lock
        # serialises competing transactions on this span, so the COUNT is now
        # consistent. On violation the rollback releases the seat.
        if cmd.booking_type is BookingType.APP:
            await self._assert_advance_cap(trip)

        booking = BookingEntity.create(
            trip_id=cmd.trip_id,
            segment=segment,
            seat_number=seat_number,
            fare_amount=fare,
            booking_type=cmd.booking_type,
            passenger_user_id=cmd.passenger_user_id,
            walkin_name=cmd.walkin_name,
            walkin_phone=cmd.walkin_phone,
            walkin_wants_receipt=cmd.walkin_wants_receipt,
        )

        now = datetime.now(APP_TZ)
        self.session.add(
            BookingRow(
                booking_id=booking.booking_id,
                ticket_number=booking.ticket_number,
                trip_id=booking.trip_id,
                passenger_user_id=booking.passenger_user_id,
                walkin_name=booking.walkin_name,
                walkin_phone=booking.walkin_phone,
                walkin_wants_receipt=booking.walkin_wants_receipt,
                booking_type=booking.booking_type.value,
                boarding_stop_sequence=segment.boarding_stop,
                alighting_stop_sequence=segment.alighting_stop,
                seat_number=booking.seat_number,
                fare_amount=booking.fare_amount,
                status=booking.status.value,
                qr_payload=booking.qr_payload,
                reschedule_count=0,
                booked_at=now,
                created_at=now,
                updated_at=now,
            )
        )
        await self.session.flush()

        await self.seats.bind_to_booking(
            trip_id=cmd.trip_id,
            seat_number=seat_number,
            segment=segment,
            booking_id=booking.booking_id,
        )

        # Walk-ins pay cash on the spot -- no PayMongo round trip, so the
        # seat goes straight to booked rather than sitting on a hold.
        if booking.booking_type is not BookingType.APP:
            await self.seats.confirm(booking_id=booking.booking_id)

        await self.session.commit()
        # ---- lock released -------------------------------------------

        log.info(
            "Reserved seat %s on trip %s for %s..%s (booking %s)",
            seat_number, cmd.trip_id, segment.boarding_stop,
            segment.alighting_stop, booking.booking_id,
        )
        return ReserveSeatResult(
            booking_id=booking.booking_id,
            ticket_number=booking.ticket_number,
            seat_number=seat_number,
            fare_amount=fare,
            status=booking.status,
            qr_payload=booking.qr_payload,
        )

    # ------------------------------------------------------------------
    async def _lookup_fare(self, route_id: str, segment: Segment) -> Decimal:
        result = await self.session.execute(
            select(FareMatrix)
            .where(
                FareMatrix.route_id == route_id,
                FareMatrix.from_stop_sequence == segment.boarding_stop,
                FareMatrix.to_stop_sequence == segment.alighting_stop,
            )
            .order_by(FareMatrix.effective_from.desc())
            .limit(1)
        )
        fare = result.scalar_one_or_none()
        if fare is None:
            raise NotFoundError(
                f"No fare configured for stops {segment.boarding_stop}"
                f"->{segment.alighting_stop} on this route."
            )
        return fare.fare_amount

    async def _assert_advance_cap(self, trip: Trip) -> None:
        result = await self.session.execute(
            select(func.count())
            .select_from(BookingRow)
            .where(
                BookingRow.trip_id == trip.trip_id,
                BookingRow.booking_type == BookingType.APP.value,
                BookingRow.status.notin_(
                    [BookingStatus.CANCELLED.value, BookingStatus.RESCHEDULED.value]
                ),
            )
        )
        if int(result.scalar_one()) >= trip.advance_booking_seat_cap:
            raise PolicyViolationError(
                f"Advance booking is limited to {trip.advance_booking_seat_cap} "
                "seats on this trip. Remaining seats are held for walk-in "
                "passengers at the terminal."
            )