"""The terminal fees before Start, the operator's share, and the van's
statements.

Rev 721, change brief 2.1, item 13, 9 (Remittance screen). The rules are
in `application/finance/statement.py`. Reading a share or a statement
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
from app.application.finance.statement import BEFORE_DEPARTURE, ZERO, Statements
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
    income_group: str           # 'booked' | 'walk_up'
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
    # balance of terminal fees (this trip's 15 % and DCOTT ticket, the
    # day's parking if unpaid, and anything the van still owes today).
    amount_due: Decimal
    disputed: Decimal
    # What the Dispatcher hands the operator in the same step, and what
    # the Cashier has recorded so far, on the van's statement for the day.
    operator_share_owed: Decimal
    operator_share_given: Decimal
    lines: list[LineOut]


class StatementOut(BaseModel):
    remittance_id: str
    van_id: str
    plate_number: str
    operator_id: str
    service_date: dt.date
    rate_pct: Decimal
    booked_income: Decimal
    walk_up_income: Decimal
    remittance_owed: Decimal
    dcott_ticket_fee: Decimal
    dcott_fees: Decimal
    parking_fee: Decimal
    terminal_fees_owed: Decimal
    held_share: Decimal
    settled_amount: Decimal
    amount_due: Decimal
    disputed: Decimal
    operator_share_owed: Decimal
    operator_share_given: Decimal
    operator_share_given_at: dt.datetime | None
    operator_share_recorded_by_name: str | None
    # 'Operator share differs' (T68): owed less given, positive when the
    # operator got less. None until every trip's list is locked; it
    # blocks nothing.
    operator_share_difference: Decimal | None
    operator_share_differs: bool
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
    # The operator's share the Dispatcher handed to the operator in the
    # same step, which the Cashier records with the payment.
    operator_share: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)


class OperatorShareIn(BaseModel):
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)


class ParkingIn(BaseModel):
    van_id: str
    # Today by default.
    service_date: dt.date | None = None


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
        amount_due=await money.due(statement) if statement else ZERO,
        disputed=await money.disputed(statement) if statement else ZERO,
        operator_share_owed=statement.operator_share_owed if statement else ZERO,
        operator_share_given=statement.operator_share_given if statement else ZERO,
        lines=await _lines(session, RemittanceLine.trip_id == trip.trip_id),
    )


async def _statement(session, statement: Remittance) -> StatementOut:
    money = Statements(session)
    van = await session.get(Van, statement.van_id)
    difference = await money.share_difference(statement)
    return StatementOut(
        remittance_id=statement.remittance_id, van_id=statement.van_id,
        plate_number=van.plate_number, operator_id=statement.operator_id,
        service_date=statement.service_date, rate_pct=statement.rate_pct,
        booked_income=statement.booked_income, walk_up_income=statement.walk_up_income,
        remittance_owed=statement.remittance_owed,
        dcott_ticket_fee=statement.dcott_ticket_fee, dcott_fees=statement.dcott_fees,
        parking_fee=statement.parking_fee, terminal_fees_owed=statement.terminal_fees_owed,
        held_share=statement.held_share,
        settled_amount=statement.settled_amount, amount_due=await money.due(statement),
        disputed=await money.disputed(statement),
        operator_share_owed=statement.operator_share_owed,
        operator_share_given=statement.operator_share_given,
        operator_share_given_at=statement.operator_share_given_at,
        operator_share_recorded_by_name=await _name(session, statement.operator_share_recorded_by),
        operator_share_difference=difference,
        operator_share_differs=bool(difference),
        status=statement.status,
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
    """The Cashier records the terminal fees the Dispatcher handed over,
    and the operator's share handed to the operator. The list locks to
    cancellations."""
    trip = await _trip(session, trip_id)
    statement = await Statements(session).pay_trip(
        trip, by=user, amount=payload.amount, reference=payload.reference,
        handed_over_by=payload.handed_over_by, operator_share=payload.operator_share,
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
    """A payment toward a van's statement: a trip that left unpaid, one
    the Terminal Manager let start before its fees were recorded, or a
    parking-only charge."""
    statement = await _locked(session, remittance_id)
    await Statements(session).record_payment(
        statement, by=user, amount=payload.amount, reference=payload.reference,
        handed_over_by=payload.handed_over_by, operator_share=payload.operator_share,
    )
    out = await _statement(session, statement)
    await session.commit()
    return out


@router.post("/statements/{remittance_id}/operator-share", response_model=StatementOut)
async def record_operator_share(
    remittance_id: str, payload: OperatorShareIn, session: SessionDep,
    user: Annotated[User, Depends(CASHIER)],
) -> StatementOut:
    """The operator's share recorded on its own: a difference handed over
    after the payment."""
    statement = await _locked(session, remittance_id)
    await Statements(session).record_operator_share(statement, by=user, amount=payload.amount)
    out = await _statement(session, statement)
    await session.commit()
    return out


@router.post("/statements/parking", response_model=StatementOut, status_code=201)
async def charge_parking(
    payload: ParkingIn, session: SessionDep, user: Annotated[User, Depends(CASHIER)],
) -> StatementOut:
    """A parking-only charge for a van parked at the terminal with no trip
    that day: the P50 on a statement of its own, paid like any other."""
    if await session.get(Van, payload.van_id) is None:
        raise NotFoundError("Van not found.")
    statement = await Statements(session).charge_parking(
        payload.van_id, payload.service_date or app_tz.now().date())
    out = await _statement(session, statement)
    await session.commit()
    return out


async def _locked(session, remittance_id: str) -> Remittance:
    statement = (await session.execute(
        select(Remittance).where(Remittance.remittance_id == remittance_id).with_for_update()
    )).scalar_one_or_none()
    if statement is None:
        raise NotFoundError("Statement not found.")
    return statement
