"""A2Z's 15 %: the trip's share before Start, and the van's statements.

Rev 603, change brief 2.1, 9 (Remittance screen). The rules are in
`application/finance/statement.py`. Reading a share or a statement
first brings its fare lines in line with the passenger list, so what the
Cashier sees is what is owed now.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import CASHIER, OFFICE, SessionDep, require_roles
from app.application.finance.statement import BEFORE_DEPARTURE, Statements
from app.application.identity.naming import display_name
from app.application.operations.guards import assert_assigned_to_trip
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError
from app.domain.enums import Role
from app.infrastructure.models import (
    Operator,
    Remittance,
    RemittanceLine,
    Terminal,
    Trip,
    User,
    Van,
)

router = APIRouter(tags=["statements"])

# The Dispatcher sees the share they hand over; the office sees all.
READS_SHARE = require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER, Role.CASHIER, Role.ADMIN)


class LineOut(BaseModel):
    line_id: str
    trip_id: str
    dest_terminal_id: str | None
    dest_terminal_name: str | None
    income_group: str
    fare_per_passenger: Decimal
    passenger_count: int
    gross_fare: Decimal
    share_amount: Decimal
    is_top_up: bool
    # The trip's departure, so a statement reads trip by trip.
    trip_departure: dt.datetime


class ShareOut(BaseModel):
    trip_id: str
    payment_status: str
    list_locked_at: dt.datetime | None
    overridden: bool
    remittance_id: str | None
    # What the Cashier should receive now: the statement's undisputed
    # balance (this trip's share, plus anything the van still owes today).
    amount_due: Decimal
    disputed: Decimal
    lines: list[LineOut]


class StatementOut(BaseModel):
    remittance_id: str
    van_id: str
    plate_number: str
    operator_id: str
    service_date: dt.date
    rate_pct: Decimal
    verified_income: Decimal
    declared_income: Decimal
    remittance_owed: Decimal
    held_share: Decimal
    settled_amount: Decimal
    amount_due: Decimal
    disputed: Decimal
    status: str
    settled_at: dt.datetime | None
    settlement_ref: str | None
    recorded_by: str | None
    handed_over_by: str | None
    operator_name: str
    recorded_by_name: str | None
    handed_over_by_name: str | None
    lines: list[LineOut]


class PaymentIn(BaseModel):
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    reference: str | None = Field(default=None, max_length=64)
    # The Dispatcher who handed it over; the trip's Dispatcher by default.
    handed_over_by: str | None = None


async def _lines(session, condition) -> list[LineOut]:
    rows = (await session.execute(
        select(RemittanceLine, Terminal.terminal_name, Trip.departure_datetime)
        .outerjoin(Terminal, Terminal.terminal_id == RemittanceLine.dest_terminal_id)
        .join(Trip, Trip.trip_id == RemittanceLine.trip_id)
        .where(condition).order_by(Trip.departure_datetime, RemittanceLine.created_at)
    )).all()
    return [LineOut(
        line_id=line.line_id, trip_id=line.trip_id,
        dest_terminal_id=line.dest_terminal_id, dest_terminal_name=name,
        income_group=line.income_group, fare_per_passenger=line.fare_per_passenger,
        passenger_count=line.passenger_count, gross_fare=line.gross_fare,
        share_amount=line.share_amount, is_top_up=line.is_top_up, trip_departure=departs,
    ) for line, name, departs in rows]


async def _share(session, trip: Trip, statement: Remittance | None) -> ShareOut:
    money = Statements(session)
    return ShareOut(
        trip_id=trip.trip_id, payment_status=trip.payment_status,
        list_locked_at=trip.list_locked_at,
        overridden=trip.payment_override_by is not None,
        remittance_id=statement.remittance_id if statement else None,
        amount_due=await money.due(statement) if statement else Decimal("0.00"),
        disputed=await money.disputed(statement) if statement else Decimal("0.00"),
        lines=await _lines(session, RemittanceLine.trip_id == trip.trip_id),
    )


async def _statement(session, statement: Remittance) -> StatementOut:
    money = Statements(session)
    van = await session.get(Van, statement.van_id)
    return StatementOut(
        remittance_id=statement.remittance_id, van_id=statement.van_id,
        plate_number=van.plate_number, operator_id=statement.operator_id,
        service_date=statement.service_date, rate_pct=statement.rate_pct,
        verified_income=statement.verified_income, declared_income=statement.declared_income,
        remittance_owed=statement.remittance_owed, held_share=statement.held_share,
        settled_amount=statement.settled_amount, amount_due=await money.due(statement),
        disputed=await money.disputed(statement), status=statement.status,
        settled_at=statement.settled_at, settlement_ref=statement.settlement_ref,
        recorded_by=statement.recorded_by, handed_over_by=statement.handed_over_by,
        operator_name=(await session.get(Operator, statement.operator_id)).full_name,
        recorded_by_name=await _name(session, statement.recorded_by),
        handed_over_by_name=await _name(session, statement.handed_over_by),
        lines=await _lines(session, RemittanceLine.remittance_id == statement.remittance_id),
    )


async def _name(session, user_id: str | None) -> str | None:
    user = await session.get(User, user_id) if user_id else None
    return display_name(user) if user else None


async def _trip(session, trip_id: str) -> Trip:
    trip = (await session.execute(
        select(Trip).where(Trip.trip_id == trip_id).with_for_update()
    )).scalar_one_or_none()
    if trip is None:
        raise NotFoundError("Trip not found.")
    return trip


@router.get("/trips/{trip_id}/share", response_model=ShareOut)
async def trip_share(
    trip_id: str, session: SessionDep, user: Annotated[User, Depends(READS_SHARE)],
) -> ShareOut:
    """The trip's fare lines and what is due before Start."""
    if user.role == Role.DISPATCHER.value:
        await assert_assigned_to_trip(session, trip_id=trip_id, user=user)
    trip = await _trip(session, trip_id)
    statement = await Statements(session).sync(trip)
    out = await _share(session, trip, statement)
    await session.commit()
    return out


@router.post("/trips/{trip_id}/payment", response_model=ShareOut)
async def pay_trip(
    trip_id: str, payload: PaymentIn, session: SessionDep,
    user: Annotated[User, Depends(CASHIER)],
) -> ShareOut:
    """The Cashier records the 15 % the Dispatcher handed over. The list
    locks to cancellations."""
    trip = await _trip(session, trip_id)
    statement = await Statements(session).pay_trip(
        trip, by=user, amount=payload.amount, reference=payload.reference,
        handed_over_by=payload.handed_over_by,
    )
    out = await _share(session, trip, statement)
    await session.commit()
    return out


@router.get("/statements", response_model=list[StatementOut], dependencies=[Depends(OFFICE)])
async def statements(session: SessionDep, date: dt.date | None = None) -> list[StatementOut]:
    """The day's statements, one per van, with their fare lines."""
    day = date or app_tz.now().date()
    money = Statements(session)
    for trip in (await session.execute(
        select(Trip).where(Trip.service_date == day, Trip.van_id.is_not(None),
                           Trip.status.in_(BEFORE_DEPARTURE))
    )).scalars():
        await money.sync(trip)
    rows = (await session.execute(
        select(Remittance).where(Remittance.service_date == day)
        .order_by(Remittance.created_at)
    )).scalars().all()
    out = [await _statement(session, s) for s in rows]
    await session.commit()
    return out


@router.post("/statements/{remittance_id}/payments", response_model=StatementOut)
async def pay_statement(
    remittance_id: str, payload: PaymentIn, session: SessionDep,
    user: Annotated[User, Depends(CASHIER)],
) -> StatementOut:
    """A payment toward a van's statement: a trip that left unpaid, or one
    the Terminal Manager let start before its share was recorded."""
    statement = (await session.execute(
        select(Remittance).where(Remittance.remittance_id == remittance_id).with_for_update()
    )).scalar_one_or_none()
    if statement is None:
        raise NotFoundError("Statement not found.")
    await Statements(session).record_payment(
        statement, by=user, amount=payload.amount, reference=payload.reference,
        handed_over_by=payload.handed_over_by,
    )
    out = await _statement(session, statement)
    await session.commit()
    return out
