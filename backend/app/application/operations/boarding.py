"""Conductor operations: QR boarding validation and the trip manifest."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.domain.enums import BookingStatus, TripStatus
from app.infrastructure.models import BoardingScan
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Trip
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)


def occupies_leg(leg_sequence: int):
    """SQL predicate: this booking occupies a seat on the given leg.

    A passenger boarding at stop 1 and alighting at stop 2 is NOT aboard
    on leg 2. Getting this wrong is the subtle bug that would make every
    YOLOv8 variance look like theft -- the manifest would count people who
    already got off.

    Leg k spans stop k -> k+1, so a booking occupies it when
    boarding <= k and alighting > k.
    """
    return and_(
        BookingRow.boarding_stop_sequence <= leg_sequence,
        BookingRow.alighting_stop_sequence > leg_sequence,
    )


ABOARD = [
    BookingStatus.CONFIRMED.value,
    BookingStatus.CHECKED_IN.value,
    BookingStatus.BOARDED.value,
]


@dataclass(frozen=True)
class ScanResult:
    scan_id: str
    result: str
    accepted: bool
    booking_id: str | None
    ticket_number: str | None
    passenger_name: str | None
    seat_number: int | None
    boarding_stop: int | None
    alighting_stop: int | None
    message: str


class ScanTicketUseCase:
    """Validate a QR payload at the van door and mark the passenger boarded.

    Never raises for an invalid ticket. A conductor scanning in a queue
    needs a fast verdict on screen, not an exception -- so every outcome
    returns a `result` code that the app renders as green or red. The
    outcome is recorded in `boarding_scans` either way, which is what
    makes the boarding record auditable.
    """

    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(
        self,
        *,
        qr_payload: str,
        trip_id: str,
        stop_sequence: int,
        scanned_by_user_id: str,
        client_recorded_at: datetime | None = None,
    ) -> ScanResult:
        now = datetime.now(timezone.utc)

        result = await self.session.execute(
            select(BookingRow).where(BookingRow.qr_payload == qr_payload)
        )
        booking = result.scalar_one_or_none()

        async def record(code: str, message: str, accepted: bool) -> ScanResult:
            scan_id = str(uuid.uuid4())
            if booking is not None:
                self.session.add(
                    BoardingScan(
                        scan_id=scan_id,
                        booking_id=booking.booking_id,
                        scanned_by_user_id=scanned_by_user_id,
                        stop_sequence=stop_sequence,
                        result=code,
                        scanned_at=now,
                        client_recorded_at=client_recorded_at,
                        synced_at=now,
                    )
                )
            await self.session.commit()
            log.info("Scan %s -> %s", qr_payload[:16], code)
            return ScanResult(
                scan_id=scan_id,
                result=code,
                accepted=accepted,
                booking_id=booking.booking_id if booking else None,
                ticket_number=booking.ticket_number if booking else None,
                passenger_name=None,
                seat_number=booking.seat_number if booking else None,
                boarding_stop=booking.boarding_stop_sequence if booking else None,
                alighting_stop=booking.alighting_stop_sequence if booking else None,
                message=message,
            )

        if booking is None:
            return await record("wrong_trip", "Ticket not recognised.", False)
        if booking.trip_id != trip_id:
            return await record("wrong_trip", "This ticket is for another trip.", False)
        if booking.status == BookingStatus.CANCELLED.value:
            return await record("cancelled", "This booking was cancelled.", False)
        if booking.status == BookingStatus.RESCHEDULED.value:
            return await record(
                "wrong_trip", "This ticket was moved to another trip.", False
            )
        if booking.status == BookingStatus.PENDING.value:
            return await record("unpaid", "This booking has not been paid.", False)
        if booking.status == BookingStatus.BOARDED.value:
            return await record("already_boarded", "Already scanned aboard.", False)
        if booking.boarding_stop_sequence != stop_sequence:
            return await record(
                "wrong_stop",
                f"This passenger boards at stop {booking.boarding_stop_sequence}.",
                False,
            )

        booking.status = BookingStatus.BOARDED.value
        booking.updated_at = now
        return await record(
            "valid",
            f"Valid - stops {booking.boarding_stop_sequence} to "
            f"{booking.alighting_stop_sequence}.",
            True,
        )


class ManifestUseCase:
    """Who is aboard, and what the operator should see."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def for_trip(self, trip_id: str) -> dict:
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        result = await self.session.execute(
            select(BookingRow)
            .where(
                BookingRow.trip_id == trip_id,
                BookingRow.status.notin_(
                    [
                        BookingStatus.CANCELLED.value,
                        BookingStatus.RESCHEDULED.value,
                    ]
                ),
            )
            .order_by(BookingRow.boarding_stop_sequence, BookingRow.booked_at)
        )
        bookings = list(result.scalars().all())

        return {
            "trip_id": trip_id,
            "trip_label": trip.trip_label,
            "departure_datetime": trip.departure_datetime,
            "status": trip.status,
            "seat_capacity": trip.seat_capacity,
            "total_bookings": len(bookings),
            "boarded": sum(b.status == BookingStatus.BOARDED.value for b in bookings),
            "checked_in": sum(
                b.status == BookingStatus.CHECKED_IN.value for b in bookings
            ),
            "awaiting": sum(b.status == BookingStatus.CONFIRMED.value for b in bookings),
            "unpaid": sum(b.status == BookingStatus.PENDING.value for b in bookings),
            "passengers": [
                {
                    "booking_id": b.booking_id,
                    "ticket_number": b.ticket_number,
                    "boarding_stop": b.boarding_stop_sequence,
                    "alighting_stop": b.alighting_stop_sequence,
                    "booking_type": b.booking_type,
                    "status": b.status,
                    "fare_amount": b.fare_amount,
                    "fare_is_manual": b.fare_is_manual,
                    "is_roadside_pickup": b.is_roadside_pickup,
                    "pickup_landmark": b.pickup_landmark,
                    # Walk-ins may legitimately be anonymous.
                    "name": b.walkin_name,
                }
                for b in bookings
            ],
        }

    async def booked_count_on_leg(self, trip_id: str, leg_sequence: int) -> int:
        """Manifest headcount for one leg -- the YOLOv8 comparison baseline."""
        result = await self.session.execute(
            select(func.count())
            .select_from(BookingRow)
            .where(
                BookingRow.trip_id == trip_id,
                BookingRow.status.in_(ABOARD),
                occupies_leg(leg_sequence),
            )
        )
        return int(result.scalar_one())


class DepartTripUseCase:
    """Close boarding: mark the trip departed and no-show anyone unscanned."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(self, *, trip_id: str) -> dict:
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        now = datetime.now(timezone.utc)
        result = await self.session.execute(
            select(BookingRow).where(
                BookingRow.trip_id == trip_id,
                BookingRow.status.in_(
                    [BookingStatus.CONFIRMED.value, BookingStatus.CHECKED_IN.value]
                ),
            )
        )
        no_shows = list(result.scalars().all())
        seats = SeatRepository(self.session)

        for booking in no_shows:
            booking.status = BookingStatus.NO_SHOW.value
            booking.updated_at = now
            # Release the space so it can be resold further down the route.
            # The passenger paid and did not travel -- under a no-refund
            # policy that is their loss -- but the space is physically
            # empty and someone waiting at the next terminal can use it.
            # Leaving it reserved would also make the camera check report
            # fewer bodies than tickets for the rest of the trip.
            await seats.release(booking_id=booking.booking_id)

        trip.status = TripStatus.DEPARTED.value
        trip.departed_at = now
        trip.updated_at = now
        await self.session.commit()

        log.info("Trip %s departed; %d no-shows recorded.", trip_id, len(no_shows))
        return {
            "trip_id": trip_id,
            "status": TripStatus.DEPARTED.value,
            "departed_at": now.isoformat(),
            "no_shows": len(no_shows),
        }
