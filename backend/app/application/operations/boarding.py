"""Dispatcher operations: the trip manifest and Depart.

The QR scan at the van door went with brief rev 721: there is no
ticket to scan. A seat is on the passenger list when the Dispatcher
marks it Paid (`application/booking/cash.py`), and who actually
stepped aboard is the camera's count, matched to the list as a
count and not an identity (`application/edge/checking.py`).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.booking.home_pickup import HomePickups
from app.application.edge.checking import ListCheck
from app.application.finance.statement import Statements
from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import BookingStatus, DepartureSource, Role, TripStatus
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


class ManifestUseCase:
    """Who is aboard, and what the Terminal Manager should see."""

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
                BookingRow.status != BookingStatus.CANCELLED.value,
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
            # Reserved but the Dispatcher has not taken the cash yet, so
            # the seat is not on the passenger list (brief 2.1).
            "unpaid": sum(b.payment_status == "unpaid" for b in bookings),
            "passengers": [
                {
                    "booking_id": b.booking_id,
                    "booking_code": b.booking_code,
                    "boarding_stop": b.boarding_stop_sequence,
                    "alighting_stop": b.alighting_stop_sequence,
                    "booking_type": b.booking_type,
                    "status": b.status,
                    "payment_status": b.payment_status,
                    "paid_at": b.paid_at,
                    "fare_amount": b.fare_amount,
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
    """Close boarding: mark the trip departed and no-show anyone unscanned.

    Brief 4.2 rules 7-8: the Dispatcher taps Depart ('dispatcher'), or
    the Cashier or the Terminal Manager ('staff'), or the van's GPS
    leaves the terminal with a boarding counted ('gps'), whichever is
    first. Only a started
    trip departs; the row lock keeps the two from both releasing the
    no-shows.

    The passenger list locks here if the Cashier's payment did not lock
    it first, and its fare lines are final (`finance.statement`). A trip
    whose share was not recorded is 'left_unpaid' and the Terminal
    Manager and the Cashier are told; the share stays owed on the van's
    statement, which refuses its next assignment (brief 2.1).

    More people aboard than listed (brief 2.4, `edge.checking`) stops a
    person's Depart until the Dispatcher fixes the list or types a
    reason. The van leaving anyway is not stopped: GPS departs it and
    'Departed With More Than Listed' goes to the Terminal Manager.
    """

    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(
        self, *, trip_id: str, source: DepartureSource = DepartureSource.STAFF
    ) -> dict:
        trip = (await self.session.execute(
            select(Trip).where(Trip.trip_id == trip_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if trip is None:
            raise NotFoundError("Trip not found.")
        if trip.status != TripStatus.BOARDING.value:
            raise ConflictError(
                "Start the trip before it departs."
                if trip.status == TripStatus.SCHEDULED.value
                else f"This trip is already {trip.status}."
            )

        check = await ListCheck(self.session).recheck(trip)
        if check.excess and source is not DepartureSource.GPS:
            await self.session.commit()   # the matching stays for the Dispatcher's screen
            raise ConflictError(
                f"{check.aboard} aboard and {check.listed} listed: "
                f"{check.excess} more {'person' if check.excess == 1 else 'people'} aboard than "
                "on the passenger list. Add them to the list, or type a reason, before Depart."
            )

        now = app_tz.now()
        # An activated home pickup's seat boards after the van leaves.
        boards_later = await HomePickups(self.session).at_departure(trip)
        result = await self.session.execute(
            select(BookingRow).where(
                BookingRow.trip_id == trip_id,
                BookingRow.status.in_(
                    [BookingStatus.CONFIRMED.value, BookingStatus.CHECKED_IN.value]
                ),
                BookingRow.booking_id.notin_(boards_later),
            )
        )
        no_shows = list(result.scalars().all())
        seats = SeatRepository(self.session)

        for booking in no_shows:
            booking.status = BookingStatus.NO_SHOW.value
            booking.updated_at = now
            # The seat still counts in A2Z's share: it was paid (brief
            # 2.1). The space is released because it is empty; nobody
            # boards after departure (rev 603), so it is never resold.
            await seats.release(booking_id=booking.booking_id)

        trip.status = TripStatus.DEPARTED.value
        trip.departed_at = now
        trip.departure_source = source.value
        trip.updated_at = now
        await self.session.flush()

        unpaid = await Statements(self.session).lock_at_departure(trip)
        notifications = NotificationService(self.session)
        if unpaid:
            await notifications.notify_trip(
                trip=trip, type="left_unpaid", title="Left unpaid",
                message=(f"{trip_label(trip)} departed with ₱{unpaid:,.2f} of A2Z's share "
                         "not recorded. It stays owed; the van's next assignment is refused "
                         "until it is paid or the Terminal Manager overrides."),
                roles=(Role.TERMINAL_MANAGER, Role.CASHIER),
            )
        await ListCheck(self.session).alert_if_left_with_more(trip, check)
        await self.session.commit()

        log.info("Trip %s departed; %d no-shows recorded.", trip_id, len(no_shows))

        return {
            "trip_id": trip_id,
            "status": TripStatus.DEPARTED.value,
            "departed_at": now.isoformat(),
            "departure_source": source.value,
            "no_shows": len(no_shows),
        }
