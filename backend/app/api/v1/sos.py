"""SOS emergency alerts (spec 2.3.5).

Raising one is open to every signed-in role: an emergency is not a
privilege. Reading and closing the queue is the office's.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.safety.sos import (
    DispositionSosUseCase,
    RaiseSosUseCase,
    SosQueueUseCase,
)
from app.domain.enums import Role

router = APIRouter(prefix="/sos", tags=["sos"])

COOP_ADMIN = require_roles(Role.COOP_ADMIN, Role.ADMIN)


class RaiseSosRequest(BaseModel):
    trip_id: str | None = None
    category: str = Field(
        default="other", pattern="^(medical|accident|security|breakdown|other)$"
    )
    note: str | None = Field(default=None, max_length=255)
    # Best effort. A denied location permission must never stop an SOS,
    # so the client sends what it has and the server says so plainly.
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)


class SmsRecipientOut(BaseModel):
    recipient: str
    provider: str
    status: str
    error: str | None


class SmsSummaryOut(BaseModel):
    attempted: int
    sent: int
    failed: int
    skipped: int
    recipients: list[SmsRecipientOut]


class RaiseSosResponse(BaseModel):
    sos_id: str
    status: str
    raised_at: dt.datetime
    duplicate: bool
    notified_in_app: int
    sms: SmsSummaryOut
    message: str


@router.post("", response_model=RaiseSosResponse, status_code=201)
async def raise_sos(
    payload: RaiseSosRequest, session: SessionDep, user: CurrentUser
) -> dict:
    """Record an emergency, alert the office, then text the contact list.

    Returns 201 even when no text message could be sent -- the alert is
    the record, and `sms` says exactly what happened. It never reports a
    delivery that did not occur.
    """
    return await RaiseSosUseCase(session).execute(
        user=user,
        trip_id=payload.trip_id,
        category=payload.category,
        note=payload.note,
        latitude=payload.latitude,
        longitude=payload.longitude,
        accuracy_m=payload.accuracy_m,
    )


class SosAlertOut(BaseModel):
    sos_id: str
    status: str
    category: str
    note: str | None
    raised_by: str
    raised_by_role: str
    raised_by_phone: str | None
    raised_at: dt.datetime
    trip_id: str | None
    trip_label: str | None
    latitude: float | None
    longitude: float | None
    accuracy_m: float | None
    map_url: str | None
    acknowledged_by: str | None
    acknowledged_at: dt.datetime | None
    resolved_at: dt.datetime | None
    resolution_notes: str | None
    sms: SmsSummaryOut


@router.get("", response_model=list[SosAlertOut], dependencies=[Depends(COOP_ADMIN)])
async def list_sos(
    session: SessionDep,
    status: str | None = Query(
        None, description="open (= not yet resolved) | acknowledged | resolved"
    ),
    limit: int = Query(50, ge=1, le=200),
) -> list:
    return await SosQueueUseCase(session).list(status=status, limit=limit)


class DispositionRequest(BaseModel):
    notes: str | None = Field(default=None, max_length=512)


@router.post("/{sos_id}/acknowledge", dependencies=[Depends(COOP_ADMIN)])
async def acknowledge_sos(
    sos_id: str, session: SessionDep, user: CurrentUser
) -> dict:
    """Tell the person who raised it that a human has seen it."""
    return await DispositionSosUseCase(session).execute(
        sos_id=sos_id, action="acknowledge", notes=None, user_id=user.user_id
    )


@router.post("/{sos_id}/resolve", dependencies=[Depends(COOP_ADMIN)])
async def resolve_sos(
    sos_id: str, payload: DispositionRequest, session: SessionDep, user: CurrentUser
) -> dict:
    """Close it, with an account of what happened. The note is required."""
    return await DispositionSosUseCase(session).execute(
        sos_id=sos_id, action="resolve", notes=payload.notes, user_id=user.user_id
    )
