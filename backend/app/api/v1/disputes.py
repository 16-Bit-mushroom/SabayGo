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
from app.application.identity.naming import display_name
from app.application.notifications.service import trip_label
from app.application.operations.guards import assert_assigned_to_trip
from app.core.exceptions import InvalidInputError
from app.domain.enums import Role
from app.infrastructure.models import (
    Dispute,
    DrivingEvent,
    RemittanceLine,
    Terminal,
    Trip,
    User,
)

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
    # For the screen: the trip and van, and the contested item in words.
    trip_label: str
    plate_number: str | None
    item: str
    raised_by_name: str
    decided_by_name: str | None


async def _out(session, rows: list[Dispute]) -> list[DisputeOut]:
    if not rows:
        return []
    trips = {t.trip_id: t for t in (await session.execute(
        select(Trip).where(Trip.trip_id.in_({d.trip_id for d in rows}))
    )).scalars()}
    lines = {l.line_id: (l, name) for l, name in (await session.execute(
        select(RemittanceLine, Terminal.terminal_name)
        .outerjoin(Terminal, Terminal.terminal_id == RemittanceLine.dest_terminal_id)
        .where(RemittanceLine.line_id.in_({d.line_id for d in rows} - {None}))
    )).all()}
    flags = {f.driving_event_id: f for f in (await session.execute(
        select(DrivingEvent).where(
            DrivingEvent.driving_event_id.in_({d.driving_event_id for d in rows} - {None}))
    )).scalars()}
    people = {u.user_id: display_name(u) for u in (await session.execute(
        select(User).where(User.user_id.in_({d.raised_by for d in rows} | {d.decided_by for d in rows}))
    )).scalars()}
    out = []
    for d in rows:
        trip = trips[d.trip_id]
        if d.line_id is not None:
            line, dest = lines[d.line_id]
            item = (f"{line.passenger_count} × ₱{line.fare_per_passenger:,.2f} to "
                    f"{dest or 'no drop-off terminal'}{' (top-up)' if line.is_top_up else ''}")
        else:
            flag = flags[d.driving_event_id]
            item = f"{flag.flag_type.replace('_', ' ').capitalize()} at {flag.start_at:%H:%M}"
        fields = {c: getattr(d, c) for c in DisputeOut.model_fields if hasattr(Dispute, c)}
        out.append(DisputeOut(
            **fields, trip_label=trip_label(trip),
            plate_number=trip.van_plate_number or (trip.van.plate_number if trip.van else None),
            item=item, raised_by_name=people.get(d.raised_by, ""),
            decided_by_name=people.get(d.decided_by),
        ))
    return out


@router.post("", response_model=DisputeOut, status_code=201)
async def record_dispute(
    payload: DisputeIn, session: SessionDep, user: Annotated[User, Depends(RECORDS)],
) -> DisputeOut:
    """Record the operator's dispute of a fare line (before the payment)
    or a driving flag."""
    disputes = Disputes(session)
    if payload.subject == "fare_line":
        dispute = await disputes.raise_on_line(
            payload.line_id, by=user, statement=payload.operator_statement)
    else:
        dispute = await disputes.raise_on_flag(
            payload.driving_event_id, by=user, statement=payload.operator_statement)
    return (await _out(session, [dispute]))[0]


@router.get("", response_model=list[DisputeOut])
async def list_disputes(
    session: SessionDep, user: Annotated[User, Depends(READS)],
    status: Literal["open", "resolved", "withdrawn"] | None = None,
    trip_id: str | None = None, remittance_id: str | None = None,
) -> list[DisputeOut]:
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
    return await _out(session, list((await session.execute(query)).scalars().all()))


@router.post("/{dispute_id}/withdraw", response_model=DisputeOut)
async def withdraw_dispute(
    dispute_id: str, payload: WithdrawIn, session: SessionDep,
    user: Annotated[User, Depends(RECORDS)],
) -> DisputeOut:
    """The operator drops the dispute; the share is due again."""
    dispute = await Disputes(session).withdraw(dispute_id, by=user, note=payload.note)
    return (await _out(session, [dispute]))[0]


@router.post("/{dispute_id}/decide", response_model=DisputeOut)
async def decide_dispute(
    dispute_id: str, payload: DecisionIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> DisputeOut:
    """The Terminal Manager decides: upheld, rejected or adjusted, with
    the reason."""
    dispute = await Disputes(session).decide(
        dispute_id, by=user, outcome=payload.outcome, note=payload.note,
        adjusted_amount=payload.adjusted_amount,
    )
    return (await _out(session, [dispute]))[0]
