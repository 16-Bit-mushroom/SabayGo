"""Home pickup of a disabled or elderly passenger (rev 603, change brief
2.6). The rules are `application/booking/home_pickup.py`.

The relative books both seats with the pin, then pays each booking
through `POST /payments/checkout`, or, when the gateway is down, sends a
payment screenshot into the trip chat, which the trip's Dispatcher
confirms to the Terminal Manager. The trip's Dispatcher (or the Terminal
Manager stepping in) lists the trip's pickups, activates one by hand,
marks the van at the pin, and closes the stop.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, File, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.api.v1.bookings import BookingResponse
from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.booking.home_pickup import HomePickups, Pin
from app.application.booking.reserve_seat import ReserveSeatResult
from app.application.messaging.service import MessagingService
from app.infrastructure.repositories.policy_repository import PolicyRepository
from app.domain.enums import Role
from app.infrastructure.models import AssistedPickup

router = APIRouter(prefix="/home-pickups", tags=["home-pickups"])

CREW = require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER, Role.ADMIN)
PASSENGER = require_roles(Role.PASSENGER)


class HomePickupIn(BaseModel):
    trip_id: str
    # Both seats board at stop 1 (the relative there, the passenger at
    # the pin on the way) and alight here.
    alighting_stop: int = Field(ge=2)
    beneficiary_name: str = Field(min_length=2, max_length=150)
    beneficiary_contact: str = Field(min_length=7, max_length=20)
    pickup_latitude: Decimal = Field(ge=-90, le=90)
    pickup_longitude: Decimal = Field(ge=-180, le=180)
    pickup_note: str | None = Field(default=None, max_length=255)


class PickupOut(BaseModel):
    pickup_id: str
    trip_id: str
    booking_id: str
    relative_booking_id: str
    beneficiary_name: str
    beneficiary_contact: str
    pickup_latitude: Decimal
    pickup_longitude: Decimal
    pickup_note: str | None
    route_distance_m: int
    status: str
    activation_mode: str | None
    activated_at: dt.datetime | None
    arrived_at: dt.datetime | None
    left_at: dt.datetime | None
    closed_early: bool
    proof_message_id: str | None
    proof_confirmed_at: dt.datetime | None

    @classmethod
    def of(cls, p: AssistedPickup) -> PickupOut:
        return cls.model_validate(p, from_attributes=True)


class HomePickupBookedOut(BaseModel):
    pickup: PickupOut
    relative_booking: BookingResponse
    passenger_booking: BookingResponse


class CloseIn(BaseModel):
    outcome: Literal["boarded", "no_show"]


def _booking(r: ReserveSeatResult) -> BookingResponse:
    return BookingResponse(
        booking_id=r.booking_id, ticket_number=r.ticket_number,
        boarding_stop=r.boarding_stop, alighting_stop=r.alighting_stop,
        fare_amount=r.fare_amount, status=r.status.value, qr_payload=r.qr_payload,
    )


@router.post("", response_model=HomePickupBookedOut, status_code=201,
             dependencies=[Depends(PASSENGER)])
async def book_home_pickup(
    payload: HomePickupIn, session: SessionDep, user: CurrentUser
) -> HomePickupBookedOut:
    """'Book for someone else' (T30): the relative's seat and the
    passenger's, with the pin. Refused while the Terminal Manager has not
    set `home_pickup_max_route_m`, and for a pin further than that from
    the route. Each booking is then paid like any other."""
    booked = await HomePickups(session).book(
        relative=user, trip_id=payload.trip_id, alighting_stop=payload.alighting_stop,
        beneficiary_name=payload.beneficiary_name.strip(),
        beneficiary_contact=payload.beneficiary_contact.strip(),
        pin=Pin(payload.pickup_latitude, payload.pickup_longitude,
                (payload.pickup_note or "").strip() or None),
    )
    return HomePickupBookedOut(pickup=PickupOut.of(booked.pickup),
                               relative_booking=_booking(booked.relative),
                               passenger_booking=_booking(booked.passenger))


@router.get("", response_model=list[PickupOut], dependencies=[Depends(CREW)])
async def trip_home_pickups(
    trip_id: str, session: SessionDep, user: CurrentUser
) -> list[PickupOut]:
    return [PickupOut.of(p) for p in await HomePickups(session).for_trip(trip_id, by=user)]


@router.post("/{pickup_id}/activate", response_model=PickupOut, dependencies=[Depends(CREW)])
async def activate_home_pickup(
    pickup_id: str, session: SessionDep, user: CurrentUser
) -> PickupOut:
    """By hand, at the terminal (T32 b); a scan of the relative's ticket
    activates it too."""
    return PickupOut.of(await HomePickups(session).activate(pickup_id, by=user))


@router.post("/{pickup_id}/arrived", response_model=PickupOut, dependencies=[Depends(CREW)])
async def arrived_at_pin(
    pickup_id: str, session: SessionDep, user: CurrentUser
) -> PickupOut:
    return PickupOut.of(await HomePickups(session).arrived(pickup_id, by=user))


@router.post("/{pickup_id}/close", response_model=PickupOut, dependencies=[Depends(CREW)])
async def close_home_pickup(
    pickup_id: str, payload: CloseIn, session: SessionDep, user: CurrentUser
) -> PickupOut:
    return PickupOut.of(await HomePickups(session).close(
        pickup_id, boarded=payload.outcome == "boarded", by=user))


@router.post("/{pickup_id}/proof", response_model=PickupOut, status_code=201,
             dependencies=[Depends(PASSENGER)])
async def send_payment_proof(
    pickup_id: str, session: SessionDep, user: CurrentUser,
    image: UploadFile = File(...),
) -> PickupOut:
    """The relative's payment screenshot when the gateway is down (T31 b):
    an image in their chat with the trip's Dispatcher, at most
    `chat_image_max_kb` (T41 a). The unpaid seats are held until departure
    while the Dispatcher looks."""
    limit_kb = await PolicyRepository(session).get_int("chat_image_max_kb")
    data = await image.read(limit_kb * 1024 + 1)
    return PickupOut.of(await HomePickups(session).send_proof(pickup_id, by=user, image=data))


@router.get("/{pickup_id}/proof")
async def payment_proof(pickup_id: str, session: SessionDep, user: CurrentUser) -> FileResponse:
    """The screenshot, for the relative, the trip's Dispatcher and the
    Terminal Manager."""
    msg = await HomePickups(session).proof(pickup_id, by=user)
    return FileResponse(MessagingService.attachment_path(msg))


@router.post("/{pickup_id}/proof/confirm", response_model=PickupOut,
             dependencies=[Depends(require_roles(Role.DISPATCHER))])
async def confirm_payment_proof(
    pickup_id: str, session: SessionDep, user: CurrentUser
) -> PickupOut:
    """The trip's Dispatcher confirms the screenshot to the Terminal
    Manager: the unpaid seats are paid ('Home Pickup Proof')."""
    return PickupOut.of(await HomePickups(session).confirm_proof(pickup_id, by=user))
