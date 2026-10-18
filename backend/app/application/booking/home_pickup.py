"""Home pickup of a disabled or elderly passenger (rev 603, change brief
2.6, Table 41): the one exception to "board at the starting terminal".

Booking. A relative books in the app ('Book for someone else'): their own
seat and the passenger's, both from stop 1 to one drop-off, in one
transaction, with the passenger's name and contact and a pin with a
note. Both bookings are the relative's, so they pay each one through the
gateway (`POST /payments/checkout`); the passenger's seat is the one
marked `booked_for_other` and `is_home_pickup_seat`. The relative rides
from the terminal, so the van is never sent alone to a house.

The pin. Accepted automatically when it lies within
`home_pickup_max_route_m` of the part of the route the pair rides (stop 1
to the drop-off), drawn straight stop to stop as NAHGM measures it
(`tracking.geometry`); the distance is stored (T30). While the setting is
unset no home pickup is offered.

Paying when the gateway is down (T31 b). The relative sends a screenshot
of the payment in the trip chat (their thread with the trip's Dispatcher,
so a Dispatcher must be assigned); it becomes the pickup's proof, and a
later screenshot replaces one not yet confirmed. A screenshot takes longer
than a gateway checkout, so the unpaid seats it covers are held until
departure instead of the usual ten minutes, and a hold that lapsed is
taken again if a space is free. The trip's Dispatcher confirms it: every
seat of the pair still unpaid is confirmed, counts as verified income (V)
like any app seat, and the Terminal Manager is told ('Home Pickup Proof').
Besides the verified webhook, this is the one way an app seat is
confirmed, and it is a person's act recorded with who and when.

Activation, at the terminal before departure (T32): a valid scan of the
relative's ticket ('qr_scan'), or the trip's Dispatcher by hand
('dispatcher_entry', with who), e.g. when the relative paid at the
counter. Either needs the passenger's seat paid. The passenger's own
ticket is refused at the door: they board at the pin.

On the trip, after departure: the Dispatcher marks the van at the pin
(`arrived_at`), then closes the stop with the passenger boarded or a
no-show (`left_at`, `closed_by`). Closing inside
`home_pickup_wait_minutes` is an early end (`closed_early`). The wait
between the two comes off the stretch time (brief 6.3). The seat is owed
either way: a no-show is a paid seat (2.1).

Departure keeps an activated pickup's seat on the list, because it
boards after the van leaves. A pickup not activated by then is a no-show
(the relative did not come, so the van does not go) and its seat is
released with the other no-shows. Cancelling the relative's seat cancels
the passenger's and the pickup; cancelling the passenger's seat cancels
only the pickup, and the relative may still ride. Neither seat is moved
to another trip: the pair and the pin belong to one.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.booking.reserve_seat import (
    ReserveSeatCommand,
    ReserveSeatResult,
    ReserveSeatUseCase,
)
from app.application.identity.naming import display_name
from app.application.messaging.service import MessagingService
from app.application.notifications.service import NotificationService, trip_label
from app.application.operations.guards import assert_assigned_to_trip
from app.application.tracking.geometry import snap_to_route
from app.core import timezone as app_tz
from app.core.exceptions import (
    ConflictError,
    NoSeatAvailableError,
    NotFoundError,
    PolicyViolationError,
)
from app.domain.enums import BookingStatus, BookingType, Role, TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import (
    AssistedPickup,
    Message,
    RouteStop,
    Terminal,
    Trip,
    User,
)
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)

PAID = {BookingStatus.CONFIRMED.value, BookingStatus.CHECKED_IN.value}
# Still to happen: the stop at the pin has not been closed or cancelled.
OPEN = ("requested", "activated", "arrived")
BEFORE_DEPARTURE = {TripStatus.SCHEDULED.value, TripStatus.BOARDING.value}


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


@dataclass(frozen=True)
class Pin:
    latitude: Decimal
    longitude: Decimal
    note: str | None = None


@dataclass(frozen=True)
class HomePickupBooked:
    pickup: AssistedPickup
    relative: ReserveSeatResult
    passenger: ReserveSeatResult


async def pickup_of(session: AsyncSession, booking_id: str) -> AssistedPickup | None:
    """The pickup a booking is either seat of, if any."""
    return (await session.execute(
        select(AssistedPickup).where(or_(AssistedPickup.booking_id == booking_id,
                                         AssistedPickup.relative_booking_id == booking_id))
    )).scalar_one_or_none()


class HomePickups:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ----------------------------------------------------------- booking
    async def book(self, *, relative: User, trip_id: str, alighting_stop: int,
                   beneficiary_name: str, beneficiary_contact: str,
                   pin: Pin) -> HomePickupBooked:
        """Both seats and the pickup, or nothing (T30)."""
        reach = await PolicyRepository(self.session).get_optional_int("home_pickup_max_route_m")
        if reach is None:
            raise PolicyViolationError(
                "Home pickup is not offered yet: the Terminal Manager has not set how far "
                "from the route a pin may be.")
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError(f"Trip {trip_id} not found.")
        if trip.route_id is None:
            raise ConflictError("This trip is a rental: it has no route to pick up from.")

        distance = await self._distance_from_route(trip, alighting_stop, pin)
        if distance > reach:
            raise PolicyViolationError(
                f"The pin is {distance:,} m from the route; a home pickup reaches "
                f"{reach:,} m. Choose a place nearer the road the van takes.")

        reserve = ReserveSeatUseCase(self.session)
        seat = dict(trip_id=trip_id, boarding_stop=1, alighting_stop=alighting_stop,
                    booking_type=BookingType.APP, passenger_user_id=relative.user_id)
        own = await reserve.reserve(ReserveSeatCommand(**seat))
        theirs = await reserve.reserve(ReserveSeatCommand(
            **seat, booked_for_other=True, is_home_pickup_seat=True))

        now = _now()
        pickup = AssistedPickup(
            pickup_id=str(uuid.uuid4()), booking_id=theirs.booking_id,
            relative_booking_id=own.booking_id, trip_id=trip_id,
            pickup_latitude=pin.latitude, pickup_longitude=pin.longitude,
            pickup_note=pin.note, route_distance_m=distance,
            beneficiary_name=beneficiary_name, beneficiary_contact=beneficiary_contact,
            status="requested", closed_early=False, created_at=now, updated_at=now,
        )
        self.session.add(pickup)
        await self.session.commit()
        log.info("Home pickup %s on trip %s, %d m from the route",
                 pickup.pickup_id, trip_id, distance)
        return HomePickupBooked(pickup, own, theirs)

    async def _distance_from_route(self, trip: Trip, alighting_stop: int, pin: Pin) -> int:
        stops = (await self.session.execute(
            select(RouteStop.stop_sequence, Terminal.latitude, Terminal.longitude)
            .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
            .where(RouteStop.route_id == trip.route_id,
                   RouteStop.stop_sequence <= alighting_stop)
            .order_by(RouteStop.stop_sequence)
        )).all()
        snap = snap_to_route(float(pin.latitude), float(pin.longitude),
                             [(seq, float(lat), float(lon)) for seq, lat, lon in stops])
        if snap is None or stops[-1][0] != alighting_stop:
            raise NotFoundError(f"This route has no stop {alighting_stop}.")
        return round(snap.offset_m)

    # ------------------------------------------------- screenshot proof
    async def send_proof(self, pickup_id: str, *, by: User, image: bytes) -> AssistedPickup:
        """The relative's payment screenshot, into the trip chat (T31 b)."""
        pickup = await self.session.get(AssistedPickup, pickup_id)
        own = pickup and await self.session.get(BookingRow, pickup.relative_booking_id)
        if own is None or own.passenger_user_id != by.user_id:
            raise NotFoundError("Home pickup not found.")
        trip = await self.session.get(Trip, pickup.trip_id)
        if trip.dispatcher_id is None:
            raise ConflictError(
                "No Dispatcher is assigned to this trip yet: send the screenshot once one is.")
        chat = MessagingService(self.session)
        # Their thread with the trip's Dispatcher; opening it commits.
        conv = await chat.start_conversation(by, peer_user_id=trip.dispatcher_id,
                                             trip_id=trip.trip_id)

        pickup, trip = await self._locked(pickup_id)
        if trip.status not in BEFORE_DEPARTURE:
            raise ConflictError(f"This trip is {trip.status}: seats are paid before departure.")
        if pickup.status not in ("requested", "activated"):
            raise ConflictError(f"This home pickup is {pickup.status}.")
        unpaid = await self._unpaid(pickup)
        if not unpaid:
            raise ConflictError("Both seats are paid: no screenshot is needed.")

        await self._hold_until_departure(trip, unpaid)
        msg = await chat.add_image(
            conv, by, image, f"Payment screenshot for the home pickup of {pickup.beneficiary_name}.")
        await self.session.flush()
        pickup.proof_message_id = msg.message_id
        pickup.updated_at = _now()
        await self.session.commit()
        return pickup

    async def _hold_until_departure(self, trip: Trip, seats_: list[BookingRow]) -> None:
        """Hold each seat until the van leaves, taking it again (perhaps on
        another internal slot) if its hold lapsed while the relative paid."""
        seats = SeatRepository(self.session)
        ttl = max(await PolicyRepository(self.session).get_int("seat_hold_ttl_seconds"),
                  int((trip.departure_datetime - _now()).total_seconds()))
        for booking in seats_:
            segment = Segment(booking.boarding_stop_sequence, booking.alighting_stop_sequence)
            await seats.release(booking_id=booking.booking_id)
            try:
                slot = await seats.allocate_seat(trip_id=trip.trip_id, segment=segment,
                                                 hold_ttl_seconds=ttl)
            except NoSeatAvailableError:
                raise ConflictError(
                    "A seat of this home pickup was released while unpaid, and the van is "
                    "now full.") from None
            await seats.bind_to_booking(trip_id=trip.trip_id, seat_number=slot,
                                        segment=segment, booking_id=booking.booking_id)
            booking.seat_number = slot

    async def proof(self, pickup_id: str, *, by: User) -> Message:
        """The screenshot: for the relative, the trip's Dispatcher and the
        Terminal Manager."""
        pickup = await self.session.get(AssistedPickup, pickup_id)
        if pickup is None:
            raise NotFoundError("Home pickup not found.")
        own = await self.session.get(BookingRow, pickup.relative_booking_id)
        if own.passenger_user_id != by.user_id:
            if by.role == Role.PASSENGER.value:
                raise NotFoundError("Home pickup not found.")
            await assert_assigned_to_trip(self.session, trip_id=pickup.trip_id, user=by)
        if pickup.proof_message_id is None:
            raise NotFoundError("No payment screenshot has been sent.")
        return await self.session.get(Message, pickup.proof_message_id)

    async def confirm_proof(self, pickup_id: str, *, by: User) -> AssistedPickup:
        """The trip's Dispatcher confirms the screenshot to the Terminal
        Manager: the unpaid seats of the pair are paid (V)."""
        pickup, trip = await self._for_crew(pickup_id, by)
        if trip.status not in BEFORE_DEPARTURE:
            raise ConflictError(f"This trip is {trip.status}: seats are paid before departure.")
        if pickup.status not in ("requested", "activated"):
            raise ConflictError(f"This home pickup is {pickup.status}.")
        if pickup.proof_message_id is None:
            raise ConflictError("No payment screenshot has been sent.")
        unpaid = await self._unpaid(pickup)
        if not unpaid:
            raise ConflictError("Both seats are already paid.")

        now = _now()
        seats = SeatRepository(self.session)
        for booking in unpaid:
            booking.status = BookingStatus.CONFIRMED.value
            booking.updated_at = now
            await seats.confirm(booking_id=booking.booking_id)
        pickup.proof_confirmed_by = by.user_id
        pickup.proof_confirmed_at = now
        pickup.updated_at = now
        total = sum(b.fare_amount for b in unpaid)
        await NotificationService(self.session).notify_trip(
            trip=trip, type="home_pickup_proof", title="Home pickup proof",
            message=(f"{display_name(by)} confirmed a payment screenshot for the home pickup "
                     f"of {pickup.beneficiary_name} on {trip_label(trip)}: "
                     f"{len(unpaid)} seat{'s' if len(unpaid) > 1 else ''}, ₱{total:,.2f}."),
            roles=(Role.TERMINAL_MANAGER,),
        )
        await self.session.commit()
        return pickup

    async def _unpaid(self, pickup: AssistedPickup) -> list[BookingRow]:
        """The pair's unpaid seats, locked: a webhook settling one of them
        waits until this is done."""
        pair = (await self.session.execute(
            select(BookingRow).where(BookingRow.booking_id.in_(
                (pickup.relative_booking_id, pickup.booking_id)))
            .with_for_update().execution_options(populate_existing=True)
        )).scalars().all()
        return [b for b in pair if b.status == BookingStatus.PENDING.value]

    # -------------------------------------------------------- activation
    async def activate_by_scan(self, relative_seat: BookingRow) -> str | None:
        """Called on a valid scan of a ticket at the door, before its commit.
        None when the ticket is no relative's; otherwise what the
        Dispatcher is told about the pickup."""
        pickup = (await self.session.execute(
            select(AssistedPickup).where(
                AssistedPickup.relative_booking_id == relative_seat.booking_id,
                AssistedPickup.status == "requested")
            .with_for_update()
        )).scalar_one_or_none()
        if pickup is None:
            return None
        if not await self._seat_paid(pickup):
            return (f"Home pickup of {pickup.beneficiary_name} not activated: "
                    "their seat is not paid.")
        self._activate(pickup, mode="qr_scan", by=None)
        return f"Home pickup of {pickup.beneficiary_name} activated."

    async def activate(self, pickup_id: str, *, by: User) -> AssistedPickup:
        """The trip's Dispatcher, by hand (T32 b)."""
        pickup, trip = await self._for_crew(pickup_id, by)
        if trip.status not in BEFORE_DEPARTURE:
            raise ConflictError(f"This trip is {trip.status}: activate before departure.")
        if pickup.status != "requested":
            raise ConflictError(f"This home pickup is {pickup.status}.")
        if not await self._seat_paid(pickup):
            raise ConflictError(f"{pickup.beneficiary_name}'s seat is not paid yet.")
        self._activate(pickup, mode="dispatcher_entry", by=by.user_id)
        await self.session.commit()
        return pickup

    def _activate(self, pickup: AssistedPickup, *, mode: str, by: str | None) -> None:
        now = _now()
        pickup.status = "activated"
        pickup.activation_mode = mode
        pickup.activated_by = by
        pickup.activated_at = now
        pickup.updated_at = now

    async def _seat_paid(self, pickup: AssistedPickup) -> bool:
        seat = await self.session.get(BookingRow, pickup.booking_id)
        return seat.status in PAID

    # ------------------------------------------------------ on the trip
    async def arrived(self, pickup_id: str, *, by: User) -> AssistedPickup:
        """The van is at the pin; the wait starts."""
        pickup, trip = await self._for_crew(pickup_id, by)
        if trip.status != TripStatus.DEPARTED.value:
            raise ConflictError(f"This trip is {trip.status}: the van goes to the pin after it leaves.")
        if pickup.status != "activated":
            raise ConflictError(f"This home pickup is {pickup.status}.")
        now = _now()
        pickup.status = "arrived"
        pickup.arrived_at = now
        pickup.updated_at = now
        await self.session.commit()
        return pickup

    async def close(self, pickup_id: str, *, boarded: bool, by: User) -> AssistedPickup:
        """End the stop: the passenger boarded, or was not found. Inside the
        wait it is an early end, logged with the Dispatcher."""
        pickup, trip = await self._for_crew(pickup_id, by)
        if pickup.status != "arrived":
            raise ConflictError(
                "Mark the van at the pin first." if pickup.status == "activated"
                else f"This home pickup is {pickup.status}.")
        wait = await PolicyRepository(self.session).get_int("home_pickup_wait_minutes")
        now = _now()
        pickup.status = "boarded" if boarded else "no_show"
        pickup.left_at = now
        pickup.closed_by = by.user_id
        pickup.closed_early = now - pickup.arrived_at < timedelta(minutes=wait)
        pickup.updated_at = now

        seat = await self.session.get(BookingRow, pickup.booking_id)
        seat.updated_at = now
        if boarded:
            seat.status = BookingStatus.BOARDED.value
        else:
            # Owed all the same (2.1); the space is empty, so released.
            seat.status = BookingStatus.NO_SHOW.value
            await SeatRepository(self.session).release(booking_id=seat.booking_id)
        await self.session.commit()
        return pickup

    async def _for_crew(self, pickup_id: str, by: User) -> tuple[AssistedPickup, Trip]:
        pickup, trip = await self._locked(pickup_id)
        await assert_assigned_to_trip(self.session, trip_id=trip.trip_id, user=by)
        return pickup, trip

    async def _locked(self, pickup_id: str) -> tuple[AssistedPickup, Trip]:
        """The pickup and its trip, the trip locked first as Depart locks
        them, so neither waits on the other."""
        trip_id = await self.session.scalar(
            select(AssistedPickup.trip_id).where(AssistedPickup.pickup_id == pickup_id))
        if trip_id is None:
            raise NotFoundError("Home pickup not found.")
        trip = (await self.session.execute(
            select(Trip).where(Trip.trip_id == trip_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one()
        pickup = (await self.session.execute(
            select(AssistedPickup).where(AssistedPickup.pickup_id == pickup_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one()
        return pickup, trip

    # ------------------------------------------- the rest of the system
    async def at_departure(self, trip: Trip) -> set[str]:
        """Called by Depart under the trip's lock. Returns the seats it must
        not make no-shows: activated pickups, which board after the van
        leaves. Pickups not activated become no-shows."""
        pickups = (await self.session.execute(
            select(AssistedPickup).where(AssistedPickup.trip_id == trip.trip_id,
                                         AssistedPickup.status.in_(("requested", "activated")))
        )).scalars().all()
        now = _now()
        for pickup in pickups:
            if pickup.status == "requested":
                pickup.status = "no_show"
                pickup.updated_at = now
        return {p.booking_id for p in pickups if p.status == "activated"}

    async def on_cancelled(self, booking: BookingRow) -> None:
        """A seat of a pickup was cancelled, before the list locked."""
        pickup = await pickup_of(self.session, booking.booking_id)
        if pickup is None or pickup.status not in OPEN:
            return
        now = _now()
        pickup.status = "cancelled"
        pickup.updated_at = now
        if pickup.relative_booking_id != booking.booking_id:
            return
        seat = await self.session.get(BookingRow, pickup.booking_id)
        if seat.status in PAID | {BookingStatus.PENDING.value}:
            seat.status = BookingStatus.CANCELLED.value
            seat.cancelled_at = now
            seat.updated_at = now
            await SeatRepository(self.session).release(booking_id=seat.booking_id)

    async def for_trip(self, trip_id: str, *, by: User) -> list[AssistedPickup]:
        await assert_assigned_to_trip(self.session, trip_id=trip_id, user=by)
        return list((await self.session.execute(
            select(AssistedPickup).where(AssistedPickup.trip_id == trip_id)
            .order_by(AssistedPickup.created_at)
        )).scalars().all())
