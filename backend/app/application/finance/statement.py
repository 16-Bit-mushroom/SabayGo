"""A2Z's 15 %: fare lines, the van's daily statement, and the payment
before Start.

Rev 603, change brief 2.1-2.2. The operator remits 15 % of the fares on
the passenger list of each trip that boards at the terminal, handed by
the Dispatcher to the Cashier before Start. Equation (2):

    remittance owed = rate x (V + D)

V is the seats paid through the gateway (QR tickets), D the cash seats
the Dispatcher listed. A seat counts whether or not its passenger comes;
the camera adds nothing. The system records the payment; it never holds
the money.

Fare lines follow the passenger list (`sync`). A line groups a trip's
seats to one drop-off terminal, at one fare, in one income group. Before
the list locks they are kept equal to the list, so a cancellation takes
its share away and an operator can dispute a line before paying. The
list locks at the Cashier's payment or the departure, whichever comes
first; after that it can only grow, and a seat added then is a top-up
line (`is_top_up`), which sets the trip back to 'unpaid' until it is paid.

The statement, one per van per service date, is recomputed from its
lines whenever they change, so its totals cannot drift from them:
  - V, D and remittance_owed count the lines of trips that ran or will
    run (not voided) and are not waiting for a review;
  - held_share is the lines of trips the system started and the
    Terminal Manager has not reviewed: off the statement, still owed;
  - the balance is owed + held - settled. The share of an open fare-line
    dispute waits: the undisputed balance leaves it out.
Payments are recorded against a statement and add up in settled_amount.

Two blocks read the undisputed balance (brief 2.1): Start waits for the
trip's statement to reach 0, and a van with any balance is refused its
next assignment. The Terminal Manager's override on a trip lifts both
for that trip ([ASSUMED] one override covers both).

A change of van after a payment moves the trip's lines to the new van's
statement; the payment stays where it was recorded.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import BookingStatus, BookingType, Role, StartReview, TripStatus
from app.infrastructure.models import (
    Booking,
    Dispute,
    Remittance,
    RemittanceLine,
    RouteStop,
    Trip,
    User,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

CENT = Decimal("0.01")
ZERO = Decimal("0.00")

# Seats on the list: paid, whether or not the passenger came (brief 2.1).
# A pending app booking is an unpaid hold and is not on it.
LISTED = (
    BookingStatus.CONFIRMED.value, BookingStatus.CHECKED_IN.value,
    BookingStatus.BOARDED.value, BookingStatus.COMPLETED.value,
    BookingStatus.NO_SHOW.value,
)
CASH = (BookingType.WALK_IN.value, BookingType.DRIVER_ISSUED.value)
BEFORE_DEPARTURE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


def share_of(gross: Decimal, rate_pct: Decimal) -> Decimal:
    return (gross * rate_pct / 100).quantize(CENT, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class LineKey:
    dest_terminal_id: str
    fare: Decimal
    group: str          # 'verified' | 'declared'


class Statements:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ---------------------------------------------------------- the list
    async def listed(self, trip: Trip) -> dict[LineKey, int]:
        """The trip's paid seats, grouped as fare lines."""
        if trip.route_id is None:
            return {}
        terminal_at = await self._terminals(trip)
        rows = (await self.session.execute(
            select(Booking.alighting_stop_sequence, Booking.fare_amount, Booking.booking_type)
            .where(Booking.trip_id == trip.trip_id, Booking.status.in_(LISTED))
        )).all()
        out: dict[LineKey, int] = {}
        for alight, fare, kind in rows:
            key = LineKey(terminal_at[alight], Decimal(fare),
                          "declared" if kind in CASH else "verified")
            out[key] = out.get(key, 0) + 1
        return out

    async def _terminals(self, trip: Trip) -> dict[int, str]:
        """Stop sequence -> terminal on the trip's route."""
        return dict((await self.session.execute(
            select(RouteStop.stop_sequence, RouteStop.terminal_id)
            .where(RouteStop.route_id == trip.route_id)
        )).all())

    async def lines_of(self, trip_id: str) -> list[RemittanceLine]:
        return list((await self.session.execute(
            select(RemittanceLine).where(RemittanceLine.trip_id == trip_id)
            .order_by(RemittanceLine.created_at)
        )).scalars().all())

    # ------------------------------------------------------------- sync
    async def sync(self, trip: Trip) -> Remittance | None:
        """Bring the trip's fare lines in line with its passenger list and
        recompute the statements they touch. The caller commits.

        Returns the trip's statement, or None when the trip has no van
        (no operator to owe anything) and no lines."""
        lines = await self.lines_of(trip.trip_id)
        if trip.van_id is None:
            # The van was taken off before Start: its lines go with it.
            if lines and trip.list_locked_at is None:
                touched = {line.remittance_id for line in lines}
                await self._drop(lines)
                await self.session.flush()
                for remittance_id in touched:
                    await self.recompute(await self.session.get(Remittance, remittance_id))
            return None
        if not lines and not await self.listed(trip):
            # Nothing to owe: no statement is opened for it.
            return await self._locked_statement(trip.van_id, trip.service_date)
        statement = await self.statement_for(trip.van_id, trip.service_date)
        touched = {statement.remittance_id}

        # The van changed: the lines follow the trip.
        for line in lines:
            if line.remittance_id != statement.remittance_id:
                touched.add(line.remittance_id)
                line.remittance_id = statement.remittance_id

        if trip.status == TripStatus.CANCELLED.value:
            # A voided trip owes nothing; recompute leaves its lines out.
            # Before the lock nothing was paid, so they go.
            if trip.list_locked_at is None:
                await self._drop(lines)
        elif trip.list_locked_at is None:
            await self._mirror(trip, statement, lines)
        else:
            await self._top_up(trip, statement, lines)

        await self.session.flush()
        for remittance_id in touched:
            await self.recompute(await self.session.get(Remittance, remittance_id))
        return statement

    async def _mirror(self, trip: Trip, statement: Remittance,
                      lines: list[RemittanceLine]) -> None:
        """Before the lock: the lines are the list."""
        want = await self.listed(trip)
        origin = (await self._terminals(trip)).get(1) if want else None
        have: dict[LineKey, RemittanceLine] = {}
        stale: list[RemittanceLine] = []
        for line in lines:
            key = self._key(line)
            if key in have or key not in want:
                stale.append(line)
            else:
                have[key] = line
        for key, count in want.items():
            line = have.get(key)
            if line is None:
                self._add(trip, statement, origin, key, count, top_up=False)
            elif line.passenger_count != count:
                self._set_count(line, count, statement.rate_pct)
        await self._drop(stale)

    async def _top_up(self, trip: Trip, statement: Remittance,
                      lines: list[RemittanceLine]) -> None:
        """After the lock the list only grows: a new seat is a top-up."""
        written: dict[LineKey, int] = {}
        for line in lines:
            key = self._key(line)
            written[key] = written.get(key, 0) + line.passenger_count
        added = False
        want = await self.listed(trip)
        origin = (await self._terminals(trip)).get(1) if want else None
        for key, count in want.items():
            extra = count - written.get(key, 0)
            if extra > 0:
                self._add(trip, statement, origin, key, extra, top_up=bool(lines))
                added = True
        if added and lines and trip.payment_status == "paid":
            trip.payment_status = "unpaid"

    def _add(self, trip: Trip, statement: Remittance, origin: str | None,
             key: LineKey, count: int, *, top_up: bool) -> None:
        gross = key.fare * count
        self.session.add(RemittanceLine(
            line_id=str(uuid.uuid4()),
            remittance_id=statement.remittance_id,
            trip_id=trip.trip_id,
            origin_terminal_id=origin,
            dest_terminal_id=key.dest_terminal_id,
            income_group=key.group,
            fare_per_passenger=key.fare,
            passenger_count=count,
            gross_fare=gross,
            share_amount=share_of(gross, statement.rate_pct),
            is_top_up=top_up,
            created_at=_now(),
        ))

    @staticmethod
    def _set_count(line: RemittanceLine, count: int, rate_pct: Decimal) -> None:
        line.passenger_count = count
        line.gross_fare = line.fare_per_passenger * count
        line.share_amount = share_of(line.gross_fare, rate_pct)

    async def _drop(self, lines: list[RemittanceLine]) -> None:
        """Delete lines nobody disputes; a disputed line stays for the
        Terminal Manager's decision."""
        for line in lines:
            disputed = (await self.session.execute(
                select(func.count()).select_from(Dispute).where(Dispute.line_id == line.line_id)
            )).scalar_one()
            if not disputed:
                await self.session.delete(line)

    @staticmethod
    def _key(line: RemittanceLine) -> LineKey:
        return LineKey(line.dest_terminal_id, Decimal(line.fare_per_passenger), line.income_group)

    # -------------------------------------------------------- statements
    async def statement_for(self, van_id: str, service_date: date) -> Remittance:
        """The van's statement for the day, created on first use, locked."""
        found = await self._locked_statement(van_id, service_date)
        if found is not None:
            return found
        van = await self.session.get(Van, van_id)
        rate = await PolicyRepository(self.session).get_decimal("remittance_rate_pct")
        now = _now()
        try:
            async with self.session.begin_nested():
                self.session.add(Remittance(
                    remittance_id=str(uuid.uuid4()), operator_id=van.operator_id,
                    van_id=van_id, service_date=service_date, rate_pct=rate,
                    created_at=now, updated_at=now,
                ))
        except IntegrityError:
            pass  # another request created it first
        return await self._locked_statement(van_id, service_date)

    async def _locked_statement(self, van_id: str, service_date: date) -> Remittance | None:
        return (await self.session.execute(
            select(Remittance).where(Remittance.van_id == van_id,
                                     Remittance.service_date == service_date)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one_or_none()

    async def recompute(self, statement: Remittance) -> None:
        rows = (await self.session.execute(
            select(RemittanceLine.income_group, RemittanceLine.gross_fare,
                   RemittanceLine.share_amount, Trip.start_review_status)
            .join(Trip, Trip.trip_id == RemittanceLine.trip_id)
            .where(RemittanceLine.remittance_id == statement.remittance_id,
                   Trip.status != TripStatus.CANCELLED.value)
        )).all()
        verified = declared = owed = held = ZERO
        for group, gross, share, review in rows:
            if review == StartReview.PENDING.value:
                held += share
                continue
            owed += share
            if group == "verified":
                verified += gross
            else:
                declared += gross
        statement.verified_income = verified
        statement.declared_income = declared
        statement.remittance_owed = owed
        statement.held_share = held
        settled = owed + held - statement.settled_amount <= 0
        statement.status = "settled" if settled and statement.recorded_by else "open"
        statement.updated_at = _now()

    # ---------------------------------------------------------- balances
    async def disputed(self, statement: Remittance) -> Decimal:
        return Decimal((await self.session.execute(
            select(func.coalesce(func.sum(Dispute.amount_disputed), 0)).where(
                Dispute.remittance_id == statement.remittance_id,
                Dispute.subject == "fare_line", Dispute.status == "open",
            )
        )).scalar_one())

    async def due(self, statement: Remittance) -> Decimal:
        """What the Cashier should receive now: the undisputed balance."""
        owing = (statement.remittance_owed + statement.held_share
                 - statement.settled_amount - await self.disputed(statement))
        return max(owing, ZERO)

    async def van_balance(self, van_id: str) -> Decimal:
        """Everything the van owes, on every statement (the assignment block)."""
        total = ZERO
        for statement in (await self.session.execute(
            select(Remittance).where(Remittance.van_id == van_id, Remittance.status == "open")
        )).scalars():
            total += await self.due(statement)
        return total

    # ---------------------------------------------------------- payments
    async def record_payment(
        self, statement: Remittance, *, by: User, amount: Decimal,
        reference: str | None, handed_over_by: str | None,
    ) -> Remittance:
        """The Cashier records money the Dispatcher handed over. The caller
        commits."""
        amount = Decimal(amount).quantize(CENT)
        due = await self.due(statement)
        if amount <= 0:
            raise ConflictError("Record an amount above zero.")
        if due == 0:
            raise ConflictError("Nothing is due on this statement.")
        if amount > due:
            raise ConflictError(f"Only ₱{due:,.2f} is due; record that amount or less.")
        if handed_over_by is not None:
            dispatcher = await self.session.get(User, handed_over_by)
            if dispatcher is None or dispatcher.role != Role.DISPATCHER.value:
                raise NotFoundError("The Dispatcher who handed it over was not found.")

        now = _now()
        statement.settled_amount += amount
        statement.settled_at = now
        statement.recorded_by = by.user_id
        statement.handed_over_by = handed_over_by
        if reference and reference.strip():
            refs = [r for r in (statement.settlement_ref or "").split("; ") if r]
            refs.append(reference.strip())
            statement.settlement_ref = "; ".join(refs)[-255:]
        await self.recompute(statement)

        if await self.due(statement) == 0:
            for trip in (await self.session.execute(
                select(Trip).join(RemittanceLine, RemittanceLine.trip_id == Trip.trip_id)
                .where(RemittanceLine.remittance_id == statement.remittance_id,
                       Trip.payment_status == "unpaid",
                       Trip.status.in_(BEFORE_DEPARTURE))
                .distinct()
            )).scalars():
                trip.payment_status = "paid"
        return statement

    async def pay_trip(
        self, trip: Trip, *, by: User, amount: Decimal,
        reference: str | None, handed_over_by: str | None,
    ) -> Remittance:
        """The share of the trip about to leave (brief 2.1): recorded on
        its van's statement, and the list locks to cancellations."""
        if trip.status not in BEFORE_DEPARTURE:
            raise ConflictError(
                f"This trip is {trip.status}. Record a payment for a departed trip "
                "on its van's statement."
            )
        if trip.van_id is None:
            raise ConflictError("Assign a van first: the share is the van's.")
        statement = await self.sync(trip)
        await self.record_payment(
            statement, by=by, amount=amount, reference=reference,
            handed_over_by=handed_over_by or trip.dispatcher_id,
        )
        trip.list_locked_at = trip.list_locked_at or _now()
        return statement

    async def lock_at_departure(self, trip: Trip) -> Decimal:
        """The van has left: the list is final. Returns the share it left
        without paying ('left_unpaid', brief 2.1), or 0."""
        statement = await self.sync(trip)
        trip.list_locked_at = trip.list_locked_at or _now()
        if statement is None or trip.payment_status != "unpaid":
            return ZERO
        due = await self.due(statement)
        if due > 0:
            trip.payment_status = "left_unpaid"
        return due
