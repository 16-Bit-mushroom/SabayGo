"""Booking endpoints."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.booking.reschedule import (
    CancelBookingUseCase,
    RescheduleBookingUseCase,
)
from app.application.booking.reserve_seat import (
    ReserveSeatCommand,
    ReserveSeatUseCase,
)
from app.domain.enums import BookingType, Role
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Trip
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
    # Flagged down between terminals. Recorded from the section they are
    # travelling on, which means the LAST terminal the van passed.
    is_roadside_pickup: bool = False
    pickup_landmark: str | None = None
    # Required for a roadside pickup: they have not travelled a fare-table
    # distance, so the conductor sets the price.
    fare_override: Decimal | None = Field(default=None, ge=0)
    fare_note: str | None = None


class BookingResponse(BaseModel):
    booking_id: str
    ticket_number: str
    # No seat number: UV Express does not assign seats. The system tracks
    # capacity per section internally, but a passenger is never told where
    # to sit.
    boarding_stop: int
    alighting_stop: int
    fare_amount: Decimal
    fare_is_manual: bool = False
    status: str
    qr_payload: str | None
    is_roadside_pickup: bool = False


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
        ticket_number=result.ticket_number,
        boarding_stop=result.boarding_stop,
        alighting_stop=result.alighting_stop,
        fare_amount=result.fare_amount,
        fare_is_manual=result.fare_is_manual,
        status=result.status.value,
        qr_payload=result.qr_payload,
        is_roadside_pickup=result.is_roadside_pickup,
    )


@router.post(
    "/walk-in",
    response_model=BookingResponse,
    status_code=201,
    dependencies=[Depends(require_roles(Role.CONDUCTOR, Role.DRIVER, Role.OPERATOR))],
)
async def log_walk_in(payload: WalkInRequest, session: SessionDep) -> BookingResponse:
    """Record a cash passenger -- at the terminal or flagged down en route.

    Accepted whenever the trip has space, including while the van is
    loading and after it has departed. Blocking either would make the
    honest path impossible and leave undocumented boarding as the only
    option.

    Passenger details are optional; supply them only for a receipt.
    """
    result = await ReserveSeatUseCase(session).execute(
        ReserveSeatCommand(
            trip_id=payload.trip_id,
            boarding_stop=payload.boarding_stop,
            alighting_stop=payload.alighting_stop,
            booking_type=BookingType.WALK_IN,
            walkin_name=payload.name,
            walkin_phone=payload.phone,
            walkin_wants_receipt=payload.wants_receipt,
            is_roadside_pickup=payload.is_roadside_pickup,
            pickup_landmark=payload.pickup_landmark,
            fare_override=payload.fare_override,
            fare_note=payload.fare_note,
        )
    )
    return BookingResponse(
        booking_id=result.booking_id,
        ticket_number=result.ticket_number,
        boarding_stop=result.boarding_stop,
        alighting_stop=result.alighting_stop,
        fare_amount=result.fare_amount,
        fare_is_manual=result.fare_is_manual,
        status=result.status.value,
        qr_payload=result.qr_payload,
        is_roadside_pickup=result.is_roadside_pickup,
    )


@router.get("/availability", response_model=AvailabilityResponse)
async def availability(
    trip_id: str, boarding_stop: int, alighting_stop: int, session: SessionDep
) -> AvailabilityResponse:
    """Non-locking availability hint for search results."""
    segment = Segment(boarding_stop, alighting_stop)
    count = await SeatRepository(session).count_available(
        trip_id=trip_id, segment=segment
    )
    return AvailabilityResponse(
        trip_id=trip_id,
        boarding_stop=boarding_stop,
        alighting_stop=alighting_stop,
        seats_available=count,
    )


class RescheduleRequest(BaseModel):
    new_trip_id: str


class RescheduleResponse(BaseModel):
    old_booking_id: str
    new_booking_id: str
    new_ticket_number: str
    new_trip_id: str
    reschedule_count: int
    qr_payload: str | None


class MyBookingOut(BaseModel):
    booking_id: str
    ticket_number: str
    trip_id: str
    departure_datetime: datetime
    route_name: str
    boarding_stop: int
    alighting_stop: int
    fare_amount: Decimal
    status: str
    qr_payload: str | None
    can_reschedule: bool
    reschedule_deadline: datetime | None


@router.get("/mine", response_model=list[MyBookingOut])
async def my_bookings(session: SessionDep, user: CurrentUser) -> list[MyBookingOut]:
    """The passenger's own bookings, newest first.

    `can_reschedule` and `reschedule_deadline` are computed server-side so
    the app never has to reimplement the policy -- it just enables or
    disables the button. The server re-checks on the actual request.
    """
    result = await session.execute(
        select(BookingRow, Trip)
        .join(Trip, Trip.trip_id == BookingRow.trip_id)
        .where(BookingRow.passenger_user_id == user.user_id)
        .order_by(BookingRow.booked_at.desc())
        .limit(50)
    )

    now = datetime.now(timezone.utc)
    active = {"pending", "confirmed", "checked_in"}
    out: list[MyBookingOut] = []

    for booking, trip in result.all():
        departure = trip.departure_datetime
        if departure.tzinfo is None:
            departure = departure.replace(tzinfo=timezone.utc)
        deadline = departure - timedelta(hours=trip.reschedule_cutoff_hours)

        out.append(
            MyBookingOut(
                booking_id=booking.booking_id,
                ticket_number=booking.ticket_number,
                trip_id=booking.trip_id,
                departure_datetime=trip.departure_datetime,
                route_name=trip.route.route_name if trip.route else "",
                boarding_stop=booking.boarding_stop_sequence,
                alighting_stop=booking.alighting_stop_sequence,
                fare_amount=booking.fare_amount,
                status=booking.status,
                qr_payload=booking.qr_payload,
                can_reschedule=booking.status in active and now < deadline,
                reschedule_deadline=deadline,
            )
        )
    return out


@router.post("/{booking_id}/reschedule", response_model=RescheduleResponse)
async def reschedule(
    booking_id: str,
    payload: RescheduleRequest,
    session: SessionDep,
    user: CurrentUser,
) -> RescheduleResponse:
    """Move a booking to another trip on the same route.

    Cooperative policy: no refunds, but a move is allowed inside the
    cutoff window. The segment stays the same; only the trip changes.
    """
    result = await RescheduleBookingUseCase(session).execute(
        booking_id=booking_id,
        new_trip_id=payload.new_trip_id,
        passenger_user_id=user.user_id,
    )
    return RescheduleResponse(
        **{k: v for k, v in result.__dict__.items() if k != "seat_number"}
    )


@router.post("/{booking_id}/cancel")
async def cancel(
    booking_id: str, session: SessionDep, user: CurrentUser
) -> dict[str, str]:
    """Cancel a booking and release its seat. No refund is issued."""
    return await CancelBookingUseCase(session).execute(
        booking_id=booking_id, passenger_user_id=user.user_id
    )
