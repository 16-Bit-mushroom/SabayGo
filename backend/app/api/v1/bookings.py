"""Booking endpoints."""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.booking.reserve_seat import (
    ReserveSeatCommand,
    ReserveSeatUseCase,
)
from app.domain.enums import BookingType, Role
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
    # Consultation: optional, captured only if the passenger wants a receipt.
    name: str | None = None
    phone: str | None = None
    wants_receipt: bool = False


class BookingResponse(BaseModel):
    booking_id: str
    ticket_number: str
    seat_number: int
    fare_amount: Decimal
    status: str
    qr_payload: str | None


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
        seat_number=result.seat_number,
        fare_amount=result.fare_amount,
        status=result.status.value,
        qr_payload=result.qr_payload,
    )


@router.post(
    "/walk-in",
    response_model=BookingResponse,
    status_code=201,
    dependencies=[Depends(require_roles(Role.CONDUCTOR, Role.DRIVER, Role.OPERATOR))],
)
async def log_walk_in(payload: WalkInRequest, session: SessionDep) -> BookingResponse:
    """Log a cash walk-in. Passenger details optional per cooperative policy."""
    result = await ReserveSeatUseCase(session).execute(
        ReserveSeatCommand(
            trip_id=payload.trip_id,
            boarding_stop=payload.boarding_stop,
            alighting_stop=payload.alighting_stop,
            booking_type=BookingType.WALK_IN,
            walkin_name=payload.name,
            walkin_phone=payload.phone,
            walkin_wants_receipt=payload.wants_receipt,
        )
    )
    return BookingResponse(
        booking_id=result.booking_id,
        ticket_number=result.ticket_number,
        seat_number=result.seat_number,
        fare_amount=result.fare_amount,
        status=result.status.value,
        qr_payload=result.qr_payload,
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