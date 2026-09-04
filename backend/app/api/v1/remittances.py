"""Cash remittance endpoints."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.finance.remittance import RemittanceService
from app.domain.enums import Role

router = APIRouter(prefix="/remittances", tags=["remittance"])

CREW = require_roles(Role.CONDUCTOR, Role.DRIVER, Role.COOP_ADMIN, Role.ADMIN)
COOP_ADMIN = require_roles(Role.COOP_ADMIN, Role.ADMIN)


class RemittanceOut(BaseModel):
    remittance_id: str | None
    trip_id: str
    trip_label: str | None
    service_date: dt.date
    collected_by_user_id: str
    collected_by_name: str | None
    booking_count: int
    expected_amount: Decimal
    declared_amount: Decimal | None
    received_amount: Decimal | None
    variance: Decimal | None
    status: str
    submitted_at: dt.datetime | None
    received_at: dt.datetime | None
    notes: str | None


class SubmitRequest(BaseModel):
    declared_amount: Decimal = Field(ge=0)
    notes: str | None = Field(default=None, max_length=512)


class ReceiveRequest(BaseModel):
    received_amount: Decimal = Field(ge=0)
    notes: str | None = Field(default=None, max_length=512)


@router.get(
    "/trips/{trip_id}/preview",
    response_model=RemittanceOut,
    dependencies=[Depends(CREW)],
)
async def preview(
    trip_id: str, session: SessionDep, user: CurrentUser
) -> RemittanceOut:
    """How much cash the crew member is holding for this trip.

    Computed from the bookings they logged, never typed in -- the figure a
    person is measured against must not be editable by that person.
    """
    result = await RemittanceService(session).preview(
        trip_id=trip_id, user_id=user.user_id
    )
    return RemittanceOut(**result.__dict__)


@router.post(
    "/trips/{trip_id}/submit",
    response_model=RemittanceOut,
    dependencies=[Depends(CREW)],
)
async def submit(
    trip_id: str, payload: SubmitRequest, session: SessionDep, user: CurrentUser
) -> RemittanceOut:
    """Crew declares the cash they are handing over, after the trip runs."""
    result = await RemittanceService(session).submit(
        trip_id=trip_id,
        user_id=user.user_id,
        declared_amount=payload.declared_amount,
        notes=payload.notes,
    )
    return RemittanceOut(**result.__dict__)


@router.post(
    "/{remittance_id}/receive",
    response_model=RemittanceOut,
    dependencies=[Depends(COOP_ADMIN)],
)
async def receive(
    remittance_id: str,
    payload: ReceiveRequest,
    session: SessionDep,
    user: CurrentUser,
) -> RemittanceOut:
    """Office records what it actually counted.

    This is what moves the money from `cash_in_hand` to `collected_fare`
    on the revenue view. A shortage is recorded and flagged rather than
    refused -- refusing would only mean it goes unrecorded.
    """
    result = await RemittanceService(session).confirm_receipt(
        remittance_id=remittance_id,
        received_amount=payload.received_amount,
        received_by_user_id=user.user_id,
        notes=payload.notes,
    )
    return RemittanceOut(**result.__dict__)


@router.get("/outstanding", dependencies=[Depends(COOP_ADMIN)])
async def outstanding(
    session: SessionDep, limit: int = Query(100, le=500)
) -> list[RemittanceOut]:
    """Handovers started but not yet received."""
    results = await RemittanceService(session).outstanding(limit=limit)
    return [RemittanceOut(**r.__dict__) for r in results]


@router.get("/unremitted-trips", dependencies=[Depends(COOP_ADMIN)])
async def unremitted_trips(
    session: SessionDep, limit: int = Query(100, le=500)
) -> list[dict]:
    """Finished trips with cash still outstanding and no handover started.

    A crew member who simply never submits would otherwise be invisible --
    the outstanding list only shows handovers that were begun.
    """
    return await RemittanceService(session).unremitted_trips(limit=limit)
