"""Operator disputes: recorded at the counter, decided by the Terminal
Manager.

Rev 603, change brief 2.1, Table 39. The rules are in
`application/finance/disputes.py`; what a dispute does to the amount due
shows on the trip's share and the van's statement (`statements.py`).
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select

from app.api.v1.deps import MANAGER, SessionDep, require_roles
from app.application.finance.disputes import Disputes
from app.application.operations.guards import assert_assigned_to_trip
from app.core.exceptions import InvalidInputError
from app.domain.enums import Role
from app.infrastructure.models import Dispute, User

router = APIRouter(prefix="/disputes", tags=["disputes"])

# Who records the operator's words at the counter (brief 3). The trip's
# Dispatcher only, for a Dispatcher.
RECORDS = require_roles(Role.DISPATCHER, Role.CASHIER, Role.TERMINAL_MANAGER)
READS = require_roles(Role.DISPATCHER, Role.CASHIER, Role.TERMINAL_MANAGER, Role.ADMIN)


class DisputeIn(BaseModel):
    subject: Literal["fare_line", "driving_flag"]
    line_id: str | None = None
    driving_event_id: str | None = None
    operator_statement: str = Field(max_length=500)

    @model_validator(mode="after")
    def _one_item(self) -> DisputeIn:
        wanted = self.line_id if self.subject == "fare_line" else self.driving_event_id
        other = self.driving_event_id if self.subject == "fare_line" else self.line_id
        if wanted is None or other is not None:
            raise ValueError("Name the one item the subject says: line_id for a fare "
                             "line, driving_event_id for a driving flag.")
        return self


class WithdrawIn(BaseModel):
    note: str | None = Field(default=None, max_length=255)


class DecisionIn(BaseModel):
    outcome: Literal["upheld", "rejected", "adjusted"]
    note: str = Field(max_length=255)
    # The share due, for an adjusted decision only.
    adjusted_amount: Decimal | None = Field(default=None, ge=0, max_digits=10, decimal_places=2)


class DisputeOut(BaseModel):
    dispute_id: str
    remittance_id: str
    trip_id: str
    subject: str
    line_id: str | None
    driving_event_id: str | None
    operator_statement: str
    amount_disputed: Decimal
    raised_by_role: str
    raised_by: str
    raised_at: dt.datetime
    status: str
    outcome: str | None
    adjusted_amount: Decimal | None
    decided_by: str | None
    decided_at: dt.datetime | None
    decision_note: str | None

    model_config = {"from_attributes": True}


@router.post("", response_model=DisputeOut, status_code=201)
async def record_dispute(
    payload: DisputeIn, session: SessionDep, user: Annotated[User, Depends(RECORDS)],
) -> Dispute:
    """Record the operator's dispute of a fare line (before the payment)
    or a driving flag."""
    disputes = Disputes(session)
    if payload.subject == "fare_line":
        return await disputes.raise_on_line(
            payload.line_id, by=user, statement=payload.operator_statement)
    return await disputes.raise_on_flag(
        payload.driving_event_id, by=user, statement=payload.operator_statement)


@router.get("", response_model=list[DisputeOut])
async def list_disputes(
    session: SessionDep, user: Annotated[User, Depends(READS)],
    status: Literal["open", "resolved", "withdrawn"] | None = None,
    trip_id: str | None = None, remittance_id: str | None = None,
) -> list[Dispute]:
    """Disputes, newest first. A Dispatcher sees their own trip's."""
    if user.role == Role.DISPATCHER.value:
        if trip_id is None:
            raise InvalidInputError("Name the trip.")
        await assert_assigned_to_trip(session, trip_id=trip_id, user=user)
    query = select(Dispute).order_by(Dispute.raised_at.desc())
    if status is not None:
        query = query.where(Dispute.status == status)
    if trip_id is not None:
        query = query.where(Dispute.trip_id == trip_id)
    if remittance_id is not None:
        query = query.where(Dispute.remittance_id == remittance_id)
    return list((await session.execute(query)).scalars().all())


@router.post("/{dispute_id}/withdraw", response_model=DisputeOut)
async def withdraw_dispute(
    dispute_id: str, payload: WithdrawIn, session: SessionDep,
    user: Annotated[User, Depends(RECORDS)],
) -> Dispute:
    """The operator drops the dispute; the share is due again."""
    return await Disputes(session).withdraw(dispute_id, by=user, note=payload.note)


@router.post("/{dispute_id}/decide", response_model=DisputeOut)
async def decide_dispute(
    dispute_id: str, payload: DecisionIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> Dispute:
    """The Terminal Manager decides: upheld, rejected or adjusted, with
    the reason."""
    return await Disputes(session).decide(
        dispute_id, by=user, outcome=payload.outcome, note=payload.note,
        adjusted_amount=payload.adjusted_amount,
    )
