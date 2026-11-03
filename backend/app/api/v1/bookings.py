"""Booking endpoints."""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.booking.cash import CashDesk, SeatOnList
from app.application.booking.reserve_seat import (
    ReserveSeatCommand,
    ReserveSeatUseCase,
)
from app.application.edge.checking import ListCheck
from app.application.operations.guards import assert_assigned_to_trip
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError, PolicyViolationError
from app.domain.enums import BookingType, CancelReason, Role
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import AssistedPickup, RouteStop, Terminal, Trip
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.infrastructure.repositories.seat_repository import SeatRepository
from app.domain.value_objects import Segment

router = APIRouter(prefix="/bookings", tags=["bookings"])


class ReserveRequest(BaseModel):
    trip_id: str
    boarding_stop: int = Field(ge=1)
    alighting_stop: int = Field(ge=2)


class WalkInRequest(BaseModel):
    trip_id: str
    boarding_stop: int = Field(ge=1)
    alighting_stop: int = Field(ge=2)
    # Optional, captured only if the passenger wants a receipt.
    name: str | None = None
    phone: str | None = None
    wants_receipt: bool = False
    # Always refused when true (rev 468). Kept so a stale build, or a
    # roadside entry still waiting in a handset's offline queue, is told
    # so instead of being re-recorded as a terminal walk-in.
    is_roadside_pickup: bool = False
    # Set by the mobile client only when this walk-in was queued
    # offline. A sync retry after an ambiguous connectivity drop is
    # recognised by this id and returns the original booking instead of
    # creating a second one.
    client_request_id: str | None = None
    # The unlisted boarding this person was (brief 2.4): the Dispatcher
    # fixes the list before Depart.
    for_event_id: str | None = None


class BookingResponse(BaseModel):
    booking_id: str
    # The short code the passenger gives the Dispatcher at the terminal.
    booking_code: str
    # No seat number: UV Express does not assign seats. The system tracks
    # capacity per section internally, but a passenger is never told where
    # to sit.
    boarding_stop: int
    alighting_stop: int
    fare_amount: Decimal
    status: str
    # 'unpaid' until the Dispatcher takes the cash at the terminal.
    payment_status: str


class AvailabilityResponse(BaseModel):
    trip_id: str
    boarding_stop: int
    alighting_stop: int
    seats_available: int


@router.post("/reserve", response_model=BookingResponse, status_code=201)
async def reserve(
    payload: ReserveRequest, session: SessionDep, user: CurrentUser
) -> BookingResponse:
    """Reserve a seat for the authenticated passenger.

    Runs the pessimistic-locking allocation. Under contention a caller may
    receive 409 (genuinely sold out) or 503 (lock contention) -- these are
    deliberately distinct so clients can retry the second and not the first.
    """
    result = await ReserveSeatUseCase(session).execute(
        ReserveSeatCommand(
            trip_id=payload.trip_id,
            boarding_stop=payload.boarding_stop,
            alighting_stop=payload.alighting_stop,
            booking_type=BookingType.APP,
            passenger_user_id=user.user_id,
        )
    )
    return BookingResponse(
        booking_id=result.booking_id,
        booking_code=result.booking_code,
        boarding_stop=result.boarding_stop,
        alighting_stop=result.alighting_stop,
        fare_amount=result.fare_amount,
        status=result.status.value,
        payment_status=result.payment_status.value,
    )


@router.post(
    "/walk-in",
    response_model=BookingResponse,
    status_code=201,
    dependencies=[Depends(require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER))],
)
async def log_walk_in(
    payload: WalkInRequest, session: SessionDep, user: CurrentUser
) -> BookingResponse:
    """List a cash (pasabay) passenger with their destination.

    Accepted at the starting terminal only, before the van departs (rev
    603, brief 2.4): on the scheduled trip once the Dispatcher is
    assigned, and while it boards. The fare is the approved fare to the
    drop-off terminal; the Dispatcher never sets it.

    A roadside pickup is refused. After departure the camera only holds
    the van to 14; a passenger picked up on the road is neither listed
    nor priced (a disclosed limitation).

    Passenger details are optional; supply them only for a receipt.

    A `client_request_id` is a replay signal, not a new request: the
    mobile offline queue sets it when a walk-in may have already reached
    the server on a previous attempt whose response was lost. If a
    booking with that id already exists for this trip, it is returned
    as-is rather than reserving a second space.
    """
    if payload.is_roadside_pickup:
        raise PolicyViolationError(
            "A roadside pickup cannot be logged. Passengers board only at the "
            "starting terminal, before the van departs."
        )
    if payload.client_request_id is not None:
        existing = await session.execute(
            select(BookingRow).where(
                BookingRow.trip_id == payload.trip_id,
                BookingRow.client_request_id == payload.client_request_id,
            )
        )
        row = existing.scalar_one_or_none()
        if row is not None:
            return BookingResponse(
                booking_id=row.booking_id,
                booking_code=row.booking_code,
                boarding_stop=row.boarding_stop_sequence,
                alighting_stop=row.alighting_stop_sequence,
                fare_amount=row.fare_amount,
                status=row.status,
                payment_status=row.payment_status,
            )

    checks = ListCheck(session)
    event = None
    if payload.for_event_id is not None:
        event = await checks.pending_event(payload.for_event_id, by=user)
        if event.trip_id != payload.trip_id:
            raise NotFoundError("Door event not found.")
    result = await ReserveSeatUseCase(session).execute(
        ReserveSeatCommand(
            trip_id=payload.trip_id,
            boarding_stop=payload.boarding_stop,
            alighting_stop=payload.alighting_stop,
            booking_type=BookingType.WALK_IN,
            walkin_name=payload.name,
            walkin_phone=payload.phone,
            walkin_wants_receipt=payload.wants_receipt,
            logged_by=user.user_id,
            client_request_id=payload.client_request_id,
        )
    )
    if event is not None:
        await checks.mark_listed(event, booking_id=result.booking_id, by=user)
    return BookingResponse(
        booking_id=result.booking_id,
        booking_code=result.booking_code,
        boarding_stop=result.boarding_stop,
        alighting_stop=result.alighting_stop,
        fare_amount=result.fare_amount,
        status=result.status.value,
        payment_status=result.payment_status.value,
    )


@router.get("/availability", response_model=AvailabilityResponse)
async def availability(
    trip_id: str, boarding_stop: int, alighting_stop: int, session: SessionDep
) -> AvailabilityResponse:
    """Non-locking availability hint for search results."""
    segment = Segment.from_starting_terminal(boarding_stop, alighting_stop)
    count = await SeatRepository(session).count_available(
        trip_id=trip_id, segment=segment
    )
    return AvailabilityResponse(
        trip_id=trip_id,
        boarding_stop=boarding_stop,
        alighting_stop=alighting_stop,
        seats_available=count,
    )


class HomePickupRef(BaseModel):
    pickup_id: str
    beneficiary_name: str
    # True on the passenger's seat (boards at the pin), false on the
    # relative's own seat (boards at the terminal).
    is_passenger_seat: bool
    status: str
    # Whether the relative sent a photo of a landmark at the pickup
    # place. Nothing depends on it (brief 2.6).
    photo_sent: bool


class MyBookingOut(BaseModel):
    booking_id: str
    booking_code: str
    trip_id: str
    departure_datetime: datetime
    route_id: str
    route_name: str
    boarding_stop: int
    alighting_stop: int
    boarding_terminal: str
    alighting_terminal: str
    fare_amount: Decimal
    status: str
    # Cash only: 'unpaid' until the Dispatcher marks the seat Paid at the
    # terminal. An unpaid reservation is not on the passenger list.
    payment_status: str
    paid_at: datetime | None
    # A passenger cancels only an unpaid seat, and only before the
    # trip's list locks. A paid one goes through the Dispatcher.
    can_cancel: bool
    # Why the reservation ended, when it has: the passenger cancelled it,
    # the Dispatcher did, or the cutoff job released it for being unpaid
    # ('auto_release'). The app tells the passenger which, rather than
    # showing a seat that silently stopped existing.
    cancelled_at: datetime | None = None
    cancel_reason: str | None = None
    # When the cutoff job releases this seat if it is still unpaid
    # (`unpaid_cutoff_min` before departure, the value the job reads), so
    # the app can say "pay the Dispatcher before ...". None once it is
    # paid or no longer standing.
    pay_by: datetime | None = None
    # D.1: when the van is due at the passenger's OWN stop, and when
    # check-in there opens. The app shows these; the server enforces them.
    boarding_due_at: datetime
    checkin_opens_at: datetime
    # Set when the booking is one of a home pickup's pair (brief 2.6).
    home_pickup: HomePickupRef | None = None


async def _render_bookings(
    session: AsyncSession, rows: list[tuple[BookingRow, Trip]]
) -> list[MyBookingOut]:
    """Shape booking rows for the passenger. Shared by `/mine` and
    `/{booking_id}` so the ticket screen sees one identical object either way.

    `can_cancel` is computed server-side so the app never has to
    reimplement the policy -- it just enables or disables the button. The
    server re-checks on the actual request.
    """
    # One name lookup for every route on the page, rather than one per booking.
    route_ids = {trip.route_id for _, trip in rows}
    stop_names: dict[tuple[str, int], str] = {}
    stop_offsets: dict[tuple[str, int], int] = {}
    if route_ids:
        stops = await session.execute(
            select(
                RouteStop.route_id,
                RouteStop.stop_sequence,
                RouteStop.offset_minutes,
                Terminal.terminal_name,
            )
            .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
            .where(RouteStop.route_id.in_(route_ids))
        )
        for rid, seq, offset, name in stops.all():
            stop_names[(rid, seq)] = name
            stop_offsets[(rid, seq)] = offset

    policies = PolicyRepository(session)
    checkin_window = timedelta(minutes=await policies.get_int("checkin_window_minutes"))
    unpaid_cutoff = timedelta(minutes=await policies.get_int("unpaid_cutoff_min"))
    now = app_tz.now()
    active = {"pending", "confirmed", "checked_in"}
    out: list[MyBookingOut] = []
    ids = [b.booking_id for b, _ in rows]
    pickups: dict[str, HomePickupRef] = {}
    if ids:
        for p in (await session.execute(
            select(AssistedPickup).where(or_(AssistedPickup.booking_id.in_(ids),
                                             AssistedPickup.relative_booking_id.in_(ids)))
        )).scalars():
            for booking_id, passenger in ((p.booking_id, True), (p.relative_booking_id, False)):
                pickups[booking_id] = HomePickupRef(
                    pickup_id=p.pickup_id, beneficiary_name=p.beneficiary_name,
                    is_passenger_seat=passenger, status=p.status,
                    photo_sent=p.photo_message_id is not None,
                )

    for booking, trip in rows:
        departure = app_tz.localize(trip.departure_datetime)
        boarding_due_at = departure + timedelta(
            minutes=stop_offsets.get((trip.route_id, booking.boarding_stop_sequence), 0)
        )

        out.append(
            MyBookingOut(
                booking_id=booking.booking_id,
                booking_code=booking.booking_code,
                trip_id=booking.trip_id,
                departure_datetime=trip.departure_datetime,
                route_id=trip.route_id,
                route_name=trip.route.route_name if trip.route else "",
                boarding_stop=booking.boarding_stop_sequence,
                alighting_stop=booking.alighting_stop_sequence,
                boarding_terminal=stop_names.get(
                    (trip.route_id, booking.boarding_stop_sequence), ""
                ),
                alighting_terminal=stop_names.get(
                    (trip.route_id, booking.alighting_stop_sequence), ""
                ),
                fare_amount=booking.fare_amount,
                status=booking.status,
                payment_status=booking.payment_status,
                paid_at=booking.paid_at,
                can_cancel=(
                    booking.status in active
                    and booking.payment_status == "unpaid"
                    and trip.list_locked_at is None
                ),
                cancelled_at=booking.cancelled_at,
                cancel_reason=booking.cancel_reason,
                pay_by=(
                    departure - unpaid_cutoff
                    if booking.status in active and booking.payment_status == "unpaid"
                    else None
                ),
                boarding_due_at=boarding_due_at,
                checkin_opens_at=boarding_due_at - checkin_window,
                home_pickup=pickups.get(booking.booking_id),
            )
        )
    return out


@router.get("/mine", response_model=list[MyBookingOut])
async def my_bookings(session: SessionDep, user: CurrentUser) -> list[MyBookingOut]:
    """The passenger's own bookings, newest first."""
    result = await session.execute(
        select(BookingRow, Trip)
        .join(Trip, Trip.trip_id == BookingRow.trip_id)
        .where(BookingRow.passenger_user_id == user.user_id)
        .order_by(BookingRow.booked_at.desc())
        .limit(50)
    )
    return await _render_bookings(session, result.all())


@router.get("/{booking_id}", response_model=MyBookingOut)
async def my_booking(
    booking_id: str, session: SessionDep, user: CurrentUser
) -> MyBookingOut:
    """One of the passenger's own bookings (G.7).

    Same shape as one element of `/mine`, so the reservation screen can
    refresh a single row (to see the Paid mark) instead of the list.
    Another passenger's booking is a 404, not a 403 -- the ID's existence is
    not the caller's business.
    """
    result = await session.execute(
        select(BookingRow, Trip)
        .join(Trip, Trip.trip_id == BookingRow.trip_id)
        .where(
            BookingRow.booking_id == booking_id,
            BookingRow.passenger_user_id == user.user_id,
        )
    )
    row = result.one_or_none()
    if row is None:
        raise NotFoundError("Booking not found.")
    return (await _render_bookings(session, [row]))[0]


# ===================================================================
# The Dispatcher's cash desk at the terminal (brief rev 721, 2.1)
# ===================================================================
class SeatOnListOut(BaseModel):
    booking_id: str
    booking_code: str
    passenger_name: str | None
    contact_number: str | None
    alighting_stop: int
    fare_amount: Decimal
    booking_type: str
    status: str
    payment_status: str
    is_home_pickup_seat: bool
    paid_at: datetime | None


class MarkPaidRequest(BaseModel):
    # The moment the Dispatcher's device recorded, so a mark queued
    # offline keeps when it happened rather than when it synced.
    paid_at: datetime | None = None


class MarkPaidResponse(SeatOnListOut):
    """The seat as it now stands, and what to tell the Dispatcher.

    `restored` and `seat_gone` are only ever set on a mark that synced
    after the cutoff job had released the seat (T62, T63); `seat_gone`
    means the fare is in the Dispatcher's hand for a seat the trip no
    longer has, and the Terminal Manager has been alerted to settle it.
    """

    restored: bool = False
    seat_gone: bool = False
    pickup_note: str | None = None


class DispatcherCancelRequest(BaseModel):
    reason: CancelReason


class CancelResponse(BaseModel):
    booking_id: str
    booking_code: str
    status: str
    payment_status: str
    cancel_reason: str | None
    message: str


def _seat_out(seat: SeatOnList) -> SeatOnListOut:
    return SeatOnListOut(**seat.__dict__)


@router.get(
    "/trip/{trip_id}/seats",
    response_model=list[SeatOnListOut],
    dependencies=[Depends(require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER))],
)
async def seats_on_trip(
    trip_id: str, session: SessionDep, user: CurrentUser, q: str | None = None
) -> list[SeatOnListOut]:
    """The trip's reservations, searched by name or booking code.

    One box for both, because at the van door the Dispatcher has
    whatever the passenger offers. Unpaid seats sort first: those are the
    ones with cash still to collect.
    """
    await assert_assigned_to_trip(session, trip_id=trip_id, user=user)
    return [_seat_out(s) for s in await CashDesk(session).find(trip_id=trip_id, query=q)]


@router.post(
    "/{booking_id}/mark-paid",
    response_model=MarkPaidResponse,
    dependencies=[Depends(require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER))],
)
async def mark_paid(
    booking_id: str,
    payload: MarkPaidRequest,
    session: SessionDep,
    user: CurrentUser,
) -> MarkPaidResponse:
    """The passenger handed the fare to the Dispatcher in cash.

    This is what puts the seat on the passenger list, counts it into
    Booked income and stops the cutoff releasing it. Marking an
    already-paid seat is accepted and changes nothing, so an offline
    queue can replay safely -- and so is a mark that reaches us after the
    cutoff released the seat, which is restored if the trip still has a
    seat to give.
    """
    desk = CashDesk(session)
    booking = await desk.booking(booking_id)
    await assert_assigned_to_trip(session, trip_id=booking.trip_id, user=user)
    result = await desk.mark_paid(booking_id=booking_id, by=user, at=payload.paid_at)
    await session.commit()
    return MarkPaidResponse(
        **(await desk.seat(booking_id)).__dict__,
        restored=result.restored,
        seat_gone=result.seat_gone,
        pickup_note=result.pickup_note,
    )


@router.post("/{booking_id}/cancel", response_model=CancelResponse)
async def cancel(
    booking_id: str, session: SessionDep, user: CurrentUser
) -> CancelResponse:
    """The passenger cancels their own reservation, in the app.

    Only while it is unpaid: once the cash is in the Dispatcher's hand it
    has to be handed back by a person, so a paid seat is cancelled by the
    Dispatcher instead. No refund and no credit either way.
    """
    booking = await CashDesk(session).cancel_by_passenger(
        booking_id=booking_id, user=user
    )
    await session.commit()
    return CancelResponse(
        booking_id=booking.booking_id,
        booking_code=booking.booking_code,
        status=booking.status,
        payment_status=booking.payment_status,
        cancel_reason=booking.cancel_reason,
        message="Reservation cancelled and the seat released.",
    )


@router.post(
    "/{booking_id}/dispatcher-cancel",
    response_model=CancelResponse,
    dependencies=[Depends(require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER))],
)
async def dispatcher_cancel(
    booking_id: str,
    payload: DispatcherCancelRequest,
    session: SessionDep,
    user: CurrentUser,
) -> CancelResponse:
    """The Dispatcher cancels a seat (brief 2.1).

    Either the passenger asked in the chat -- and the Dispatcher hands
    back any cash already taken, which happens between them and is not
    money the system moves -- or an unpaid reservation was forgotten and
    nobody came for it.
    """
    desk = CashDesk(session)
    booking = await desk.booking(booking_id)
    await assert_assigned_to_trip(session, trip_id=booking.trip_id, user=user)
    await desk.cancel_by_dispatcher(
        booking_id=booking_id, reason=payload.reason, by=user
    )
    await session.commit()
    returned = (
        " Hand back the cash you took for it."
        if payload.reason is CancelReason.PASSENGER_ASKED_DISPATCHER
        else ""
    )
    return CancelResponse(
        booking_id=booking.booking_id,
        booking_code=booking.booking_code,
        status=booking.status,
        payment_status=booking.payment_status,
        cancel_reason=booking.cancel_reason,
        message=f"Seat released.{returned}",
    )
