"""Dispatcher operations: QR boarding validation and the trip manifest."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.audit import auto_trigger
from app.application.finance.statement import Statements
from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import AuditTrigger, BookingStatus, DepartureSource, Role, TripStatus
from app.infrastructure.models import BoardingScan
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import PassengerEvent, Trip
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

    Never raises for an invalid ticket. A Dispatcher scanning in a queue
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
        now = app_tz.now()

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

    More people aboard than listed (an unlisted boarding still pending,
    brief 2.4) stops a person's Depart until the Dispatcher fixes the
    list or types a reason. The van leaving anyway is not stopped: GPS
    departs it and 'Departed With More Than Listed' goes to the Terminal
    Manager.
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

        unlisted = (await self.session.execute(
            select(func.count()).select_from(PassengerEvent).where(
                PassengerEvent.trip_id == trip_id,
                PassengerEvent.resolution_status == "pending",
            )
        )).scalar_one()
        if unlisted and source is not DepartureSource.GPS:
            raise ConflictError(
                f"{unlisted} {'person is' if unlisted == 1 else 'people are'} aboard but not "
                "on the passenger list. Add them to the list, or type a reason, before Depart."
            )

        now = app_tz.now()
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
        if unlisted:
            await notifications.notify_trip(
                trip=trip, type="departed_more_than_listed",
                title="Departed with more aboard than listed",
                message=(f"{trip_label(trip)} left with {unlisted} more aboard than its "
                         "passenger list, and the Dispatcher neither fixed the list nor gave a "
                         "reason. No fare is priced from the camera's count."),
                roles=(Role.TERMINAL_MANAGER,),
            )
        await self.session.commit()

        log.info("Trip %s departed; %d no-shows recorded.", trip_id, len(no_shows))

        # 2.3.5's door-closure trigger. Boarding is shut, the no-shows are
        # released, so the manifest for leg 1 is final and this is the
        # moment a cabin count means something. Detached: the crew is not
        # made to wait at the door for a camera, and a camera that is down
        # must not turn a completed departure into an error.
        auto_trigger.schedule(
            trip_id=trip_id,
            leg_sequence=1,  # departing stop 1 puts the van on leg 1
            trigger=AuditTrigger.DOOR_CLOSE,
        )

        return {
            "trip_id": trip_id,
            "status": TripStatus.DEPARTED.value,
            "departed_at": now.isoformat(),
            "departure_source": source.value,
            "no_shows": len(no_shows),
        }
