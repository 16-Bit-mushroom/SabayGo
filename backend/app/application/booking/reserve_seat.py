"""Reserve-space use case.

Orchestration only: it holds the transaction boundary and calls domain and
repositories. No SQL here, no business rules here -- rules live in the
Booking entity, SQL lives in the repository.

Vocabulary note: what the database calls `seat_number` is a capacity slot,
not a physical chair. UV Express does not assign seats -- passengers sit
wherever there is room. The number exists so the system can guarantee no
section of road is oversold; it is never shown to a passenger.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, NotFoundError, PolicyViolationError
from app.core.timezone import APP_TZ
from app.domain.entities.booking import Booking as BookingEntity
from app.domain.enums import BookingStatus, BookingType, TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import FareMatrix, Trip
from app.infrastructure.models import Payment as PaymentRow
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)

# App bookings close the moment a van starts loading.
APP_BOOKABLE = {TripStatus.SCHEDULED.value}

# Cash passengers are recorded whenever there is room. A conductor logs
# walk-ins while the van is loading, and a driver picks up roadside
# passengers after departure. Blocking either would make the honest path
# impossible and leave undocumented boarding as the only option -- which
# is precisely what the YOLOv8 check exists to detect.
CASH_BOOKABLE = {
    TripStatus.SCHEDULED.value,
    TripStatus.BOARDING.value,
    TripStatus.DEPARTED.value,
}

CASH_TYPES = {BookingType.WALK_IN, BookingType.DRIVER_ISSUED}


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
    # Roadside pickup: boarded between terminals, recorded from the
    # section they are travelling on.
    is_roadside_pickup: bool = False
    pickup_landmark: str | None = None
    # Conductor-set fare. Required for roadside, optional otherwise.
    fare_override: Decimal | None = None
    fare_note: str | None = None


@dataclass(frozen=True)
class ReserveSeatResult:
    booking_id: str
    ticket_number: str
    fare_amount: Decimal
    fare_is_manual: bool
    status: BookingStatus
    qr_payload: str | None
    boarding_stop: int
    alighting_stop: int
    is_roadside_pickup: bool


class ReserveSeatUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)
        self.policies = PolicyRepository(session)

    async def execute(self, cmd: ReserveSeatCommand) -> ReserveSeatResult:
        segment = Segment(cmd.boarding_stop, cmd.alighting_stop)
        is_cash = cmd.booking_type in CASH_TYPES

        trip = await self.session.get(Trip, cmd.trip_id)
        if trip is None:
            raise NotFoundError(f"Trip {cmd.trip_id} not found.")

        allowed = CASH_BOOKABLE if is_cash else APP_BOOKABLE
        if trip.status not in allowed:
            raise ConflictError(
                f"Trip is {trip.status}; "
                + ("this trip is finished." if is_cash else "app bookings are closed.")
            )

        # A departed trip is by definition past its departure time, so the
        # future-departure guard applies to app bookings only.
        if not is_cash:
            departure = trip.departure_datetime
            if departure.tzinfo is None:
                departure = departure.replace(tzinfo=APP_TZ)
            if departure <= datetime.now(APP_TZ):
                raise ConflictError("This trip has already departed.")
            await self._assert_within_booking_window(trip)

        if cmd.is_roadside_pickup and not is_cash:
            raise ConflictError(
                "A roadside pickup is recorded by the crew, not booked in the app."
            )

        fare, fare_is_manual = await self._resolve_fare(trip, segment, cmd, is_cash)

        # ---- the locked section -------------------------------------
        hold_ttl = await self.policies.get_int("seat_hold_ttl_seconds")
        slot = await self.seats.allocate_seat(
            trip_id=cmd.trip_id, segment=segment, hold_ttl_seconds=hold_ttl
        )

        # The advance limit is checked INSIDE the lock. Outside it,
        # concurrent requests all read the same stale count and every one
        # passes -- a bug the concurrency experiment caught at 14 bookings
        # against a cap of 10. Skipped entirely when the cap equals
        # capacity, which is now the default: all spaces open, first come
        # first served.
        if not is_cash and trip.advance_booking_seat_cap < trip.seat_capacity:
            await self._assert_advance_cap(trip)

        booking = BookingEntity.create(
            trip_id=cmd.trip_id,
            segment=segment,
            seat_number=slot,
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
                is_roadside_pickup=cmd.is_roadside_pickup,
                pickup_landmark=cmd.pickup_landmark,
                boarding_stop_sequence=segment.boarding_stop,
                alighting_stop_sequence=segment.alighting_stop,
                seat_number=slot,
                fare_amount=fare,
                fare_is_manual=fare_is_manual,
                fare_note=cmd.fare_note,
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
            seat_number=slot,
            segment=segment,
            booking_id=booking.booking_id,
        )

        # Cash is in hand -- no payment round trip, so the space goes
        # straight to taken rather than sitting on a hold that could lapse
        # while the passenger is already aboard.
        if is_cash:
            await self.seats.confirm(booking_id=booking.booking_id)
            # Record the fare as collected but NOT settled. Cash in a
            # conductor's pocket is a different state from money
            # missing, and the revenue view separates the two. It
            # settles when the crew remits at the end of the trip.
            self.session.add(
                PaymentRow(
                    payment_id=str(uuid.uuid4()),
                    booking_id=booking.booking_id,
                    provider="cash",
                    method="cash",
                    amount=fare,
                    status="pending",
                    created_at=now,
                )
            )

        await self.session.commit()
        # ---- lock released -------------------------------------------

        log.info(
            "Reserved space on trip %s, stops %s..%s%s (booking %s, P%s%s)",
            cmd.trip_id, segment.boarding_stop, segment.alighting_stop,
            " roadside" if cmd.is_roadside_pickup else "",
            booking.booking_id, fare, " manual" if fare_is_manual else "",
        )
        return ReserveSeatResult(
            booking_id=booking.booking_id,
            ticket_number=booking.ticket_number,
            fare_amount=fare,
            fare_is_manual=fare_is_manual,
            status=booking.status,
            qr_payload=booking.qr_payload,
            boarding_stop=segment.boarding_stop,
            alighting_stop=segment.alighting_stop,
            is_roadside_pickup=cmd.is_roadside_pickup,
        )

    # ------------------------------------------------------------------
    async def _resolve_fare(
        self, trip: Trip, segment: Segment, cmd: ReserveSeatCommand, is_cash: bool
    ) -> tuple[Decimal, bool]:
        """Decide the fare, and whether it was set by hand.

        A roadside passenger has not travelled a fare-table distance: they
        boarded partway along a section, so neither the previous nor the
        next terminal's price is right. The conductor judges it, and the
        system records that it was manual so the office can see how often
        and by how much fares are being set by hand.
        """
        if cmd.fare_override is not None:
            if not is_cash:
                raise ConflictError("App bookings use the approved fare table.")
            if cmd.fare_override < 0:
                raise ConflictError("A fare cannot be negative.")
            return cmd.fare_override, True

        if cmd.is_roadside_pickup:
            raise ConflictError(
                "A roadside pickup needs a fare entered by the conductor."
            )

        result = await self.session.execute(
            select(FareMatrix)
            .where(
                FareMatrix.route_id == trip.route_id,
                FareMatrix.from_stop_sequence == segment.boarding_stop,
                FareMatrix.to_stop_sequence == segment.alighting_stop,
            )
            .order_by(FareMatrix.effective_from.desc())
            .limit(1)
        )
        fare = result.scalar_one_or_none()
        if fare is None:
            raise NotFoundError(
                f"No approved fare for stops {segment.boarding_stop}"
                f"->{segment.alighting_stop} on this route."
            )
        return fare.fare_amount, False

    async def _assert_within_booking_window(self, trip: Trip) -> None:
        """Passengers cannot book arbitrarily far ahead."""
        days = await self.policies.get_int("advance_booking_open_days")
        delta = (trip.service_date - datetime.now(APP_TZ).date()).days
        if delta > days:
            raise PolicyViolationError(
                f"Bookings open {days} day(s) ahead; this trip is {delta} days away."
            )

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
                "spaces on this trip."
            )
