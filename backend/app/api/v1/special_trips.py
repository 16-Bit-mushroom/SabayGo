"""Special trips: a whole van rented from a chosen pickup (rev 603, change
brief 2.5). The rules are `application/operations/special_trips.py`.

The passenger asks and may withdraw before approval; the office (the
Terminal Manager or the Cashier) enters counter requests, approves with
the agreed fee, or rejects; the trip's Dispatcher logs a cash fee. The
van and the Dispatcher are assigned through `PUT /trips/{id}/assignment`.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import OFFICE, SessionDep, require_roles
from app.application.operations.special_trips import Place, SpecialTrips
from app.core import timezone as app_tz
from app.domain.enums import Role
from app.infrastructure.models import SpecialTripRequest, User

router = APIRouter(prefix="/special-trips", tags=["special-trips"])

PASSENGER = require_roles(Role.PASSENGER)
# The trip's Dispatcher logs the cash; the Terminal Manager may step in.
CASH_LOGGERS = require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER, Role.ADMIN)


class PlaceIn(BaseModel):
    address: str = Field(min_length=3, max_length=255)
    latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    longitude: Decimal | None = Field(default=None, ge=-180, le=180)

    def place(self) -> Place:
        return Place(self.address.strip(), self.latitude, self.longitude)


class RequestIn(BaseModel):
    pickup_at: dt.datetime
    pickup: PlaceIn
    destination: PlaceIn
    # The van seats 14 (T50).
    passenger_count: int = Field(ge=1, le=14)


class FeeIn(BaseModel):
    fee: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    # What the fee is based on: pickup, destination, hours, an agreed amount.
    fee_note: str = Field(min_length=3, max_length=255)


class WalkInIn(RequestIn, FeeIn):
    customer_name: str = Field(min_length=2, max_length=100)
    customer_contact: str = Field(min_length=7, max_length=20)


class RejectIn(BaseModel):
    reason: str = Field(min_length=3, max_length=255)


class RequestOut(BaseModel):
    request_id: str
    passenger_user_id: str | None
    customer_name: str | None
    customer_contact: str | None
    entered_by: str | None
    pickup_at: dt.datetime
    pickup_address: str
    destination_address: str
    passenger_count: int
    rental_fee: Decimal | None
    fee_note: str | None
    payment_status: str
    status: str
    trip_id: str | None
    reviewed_by: str | None
    reviewed_at: dt.datetime | None
    created_at: dt.datetime

    @classmethod
    def of(cls, r: SpecialTripRequest) -> RequestOut:
        return cls.model_validate(r, from_attributes=True)


def _local(value: dt.datetime) -> dt.datetime:
    """Naive Manila time, as MySQL stores it."""
    return value.astimezone(app_tz.APP_TZ).replace(tzinfo=None) if value.tzinfo else value


@router.post("", response_model=RequestOut, status_code=201)
async def request_special_trip(
    payload: RequestIn, session: SessionDep, user: Annotated[User, Depends(PASSENGER)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).request(
        by=user, pickup_at=_local(payload.pickup_at), pickup=payload.pickup.place(),
        destination=payload.destination.place(), passenger_count=payload.passenger_count,
    ))


@router.get("/mine", response_model=list[RequestOut])
async def my_special_trips(
    session: SessionDep, user: Annotated[User, Depends(PASSENGER)],
) -> list[RequestOut]:
    rows = (await session.execute(
        select(SpecialTripRequest).where(SpecialTripRequest.passenger_user_id == user.user_id)
        .order_by(SpecialTripRequest.created_at.desc())
    )).scalars().all()
    return [RequestOut.of(r) for r in rows]


@router.post("/{request_id}/withdraw", response_model=RequestOut)
async def withdraw_special_trip(
    request_id: str, session: SessionDep, user: Annotated[User, Depends(PASSENGER)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).withdraw(request_id, by=user))


@router.get("", response_model=list[RequestOut], dependencies=[Depends(OFFICE)])
async def special_trips(
    session: SessionDep,
    status: Annotated[str | None, Query(pattern="^(requested|approved|rejected|completed|cancelled)$")] = None,
) -> list[RequestOut]:
    query = select(SpecialTripRequest).order_by(SpecialTripRequest.pickup_at)
    if status is not None:
        query = query.where(SpecialTripRequest.status == status)
    return [RequestOut.of(r) for r in (await session.execute(query)).scalars().all()]


@router.post("/walk-in", response_model=RequestOut, status_code=201)
async def enter_walk_in(
    payload: WalkInIn, session: SessionDep, user: Annotated[User, Depends(OFFICE)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).walk_in(
        by=user, customer_name=payload.customer_name.strip(),
        customer_contact=payload.customer_contact.strip(),
        pickup_at=_local(payload.pickup_at), pickup=payload.pickup.place(),
        destination=payload.destination.place(), passenger_count=payload.passenger_count,
        fee=payload.fee, fee_note=payload.fee_note.strip(),
    ))


@router.post("/{request_id}/approve", response_model=RequestOut)
async def approve_special_trip(
    request_id: str, payload: FeeIn, session: SessionDep,
    user: Annotated[User, Depends(OFFICE)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).approve(
        request_id, by=user, fee=payload.fee, fee_note=payload.fee_note.strip()))


@router.post("/{request_id}/reject", response_model=RequestOut)
async def reject_special_trip(
    request_id: str, payload: RejectIn, session: SessionDep,
    user: Annotated[User, Depends(OFFICE)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).reject(
        request_id, by=user, reason=payload.reason.strip()))


@router.post("/{request_id}/cash", response_model=RequestOut)
async def log_cash_fee(
    request_id: str, session: SessionDep, user: Annotated[User, Depends(CASH_LOGGERS)],
) -> RequestOut:
    return RequestOut.of(await SpecialTrips(session).log_cash(request_id, by=user))
