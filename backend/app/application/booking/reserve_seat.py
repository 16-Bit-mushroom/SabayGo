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

# The Dispatcher lists cash passengers at the starting terminal, on the
# scheduled trip once assigned and while it boards (brief 2.4, rev 603):
# the list is complete before the van leaves. A pickup after departure is
# neither listed nor priced; the camera only holds the van to 14.
CASH_BOOKABLE = {
    TripStatus.SCHEDULED.value,
    TripStatus.BOARDING.value,
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
    # Who recorded a cash walk-in (the paper's LogBookEntries.LoggedBy).
    logged_by: str | None = None
    # Set by the mobile client when a walk-in was queued offline, so a
    # retried sync can be recognised as a replay. The duplicate check
    # itself lives at the API boundary (bookings.py); this only persists
    # the id onto the row it created.
    client_request_id: str | None = None
    # Home pickup (brief 2.6): the relative's booking of the passenger's
    # seat. The pickup itself is `booking/home_pickup.py`.
    booked_for_other: bool = False
    is_home_pickup_seat: bool = False


@dataclass(frozen=True)
class ReserveSeatResult:
    booking_id: str
    ticket_number: str
    fare_amount: Decimal
    status: BookingStatus
    qr_payload: str | None
    boarding_stop: int
    alighting_stop: int


class ReserveSeatUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)
        self.policies = PolicyRepository(session)

    async def execute(self, cmd: ReserveSeatCommand) -> ReserveSeatResult:
        result = await self.reserve(cmd)
        await self.session.commit()
        # ---- lock released -------------------------------------------

        log.info(
            "Reserved space on trip %s, stops %s..%s (booking %s, P%s)",
            cmd.trip_id, result.boarding_stop, result.alighting_stop,
            result.booking_id, result.fare_amount,
        )
        return result

    async def reserve(self, cmd: ReserveSeatCommand) -> ReserveSeatResult:
        """Everything but the commit. The caller holds the transaction, and
        the seat lock with it, until it commits: a home pickup reserves
        both of its seats in one."""
        segment = Segment.from_starting_terminal(cmd.boarding_stop, cmd.alighting_stop)
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

        fare = await self._resolve_fare(trip, segment)

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
                logged_by=cmd.logged_by if is_cash else None,
                client_request_id=cmd.client_request_id,
                booked_for_other=cmd.booked_for_other,
                is_home_pickup_seat=cmd.is_home_pickup_seat,
                boarding_stop_sequence=segment.boarding_stop,
                alighting_stop_sequence=segment.alighting_stop,
                seat_number=slot,
                fare_amount=fare,
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
            # Dispatcher's pocket is a different state from money
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

        return ReserveSeatResult(
            booking_id=booking.booking_id,
            ticket_number=booking.ticket_number,
            fare_amount=fare,
            status=booking.status,
            qr_payload=booking.qr_payload,
            boarding_stop=segment.boarding_stop,
            alighting_stop=segment.alighting_stop,
        )

    # ------------------------------------------------------------------
    async def _resolve_fare(self, trip: Trip, segment: Segment) -> Decimal:
        """The approved terminal-to-terminal fare, cash or app alike.

        Nobody sets a fare by hand: a declared cash fare the Dispatcher
        could price would let the declared income be whatever they said.
        """
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
        return fare.fare_amount

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
