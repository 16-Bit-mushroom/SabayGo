"""The terminal fees: fare lines, the van's daily statement, the payment
before Start, and the operator's share.

Rev 721, change brief 2.1-2.2 and item 13. The operator remits 15 % of
the fares on the passenger list of each trip that boards at the
terminal, Equation (2):

    remittance owed = rate x (B + W)

B (booked) is the seats reserved in the app that the Dispatcher marked
as paid, a home-pickup seat among them; W (walk-up) the cash walk-ups
the Dispatcher listed (rev 721 item 3). Every fare is cash, handed to
the Dispatcher at the terminal: the group says where the seat came
from, not how it was paid. A seat counts whether or not its passenger
comes; the camera adds nothing. A special trip's rental fee, once paid,
is one line of its own (`request_id`, no drop-off terminal): B when the
trip was requested in the app, W when it was entered at the counter
(2.2, 2.5).

Beside the 15 %, A2Z's trip ticket carries two fixed fees, settings
dated like the rate: the DCOTT ticket (`dcott_ticket_fee`, P75) for each
trip, and parking (`parking_fee`, P50) once per van per service day,
even with no trip. The three are the terminal fees; the rest of the cash
on the list is the operator's share:

    terminal fees owed    = rate x (B + W) + dcott x trips + parking
    operator's share owed = (B + W) - terminal fees owed, never below 0

The Dispatcher hands the terminal fees to the Cashier before Start and
the operator's share to the operator, at the counter in the same step,
and the Cashier records both. The system records amounts; it never holds
the money. The fixed fees are not fare lines, do not depend on the
number of passengers, and cannot be disputed [ASSUMED].

A trip counts on its van's statement for the day once it has a van and
until it is voided -- with or without paid seats, because the DCOTT
ticket is bought for the dispatch, not for the passengers. The parking
is charged once, when the statement opens: for the van's first trip of
the day, or by the Cashier's parking-only charge for a van with no trip
(`charge_parking`). Both fees are read from the settings when the
statement opens and kept on it, as the rate is.

Fare lines follow the passenger list (`sync`). A line groups a trip's
seats to one drop-off terminal, at one fare, in one income group. Before
the list locks they are kept equal to the list, so a cancellation takes
its share away and an operator can dispute a line before paying. The
list locks at the Cashier's payment or the departure, whichever comes
first; after that it can only grow, and a seat added then is a top-up
line (`is_top_up`), which sets the trip back to 'unpaid' until it is paid.

The statement, one per van per service date, is recomputed from its
lines and its trips whenever they change, so its totals cannot drift:
  - B, W and remittance_owed count the lines of trips that ran or will
    run (not voided) and are not waiting for a review; dcott_fees counts
    those trips;
  - held_share is the 15 % and the DCOTT ticket of trips the system
    started and the Terminal Manager has not reviewed: off the
    statement, still owed;
  - the balance is terminal fees + held - settled. The share of an open
    fare-line dispute waits: the undisputed balance leaves it out.
Payments are recorded against a statement and add up in settled_amount;
the operator's share handed over adds up in operator_share_given. Once
every trip's list on the statement is locked, a given share that differs
from the owed one is flagged (`share_difference`). The flag blocks
nothing: it is for the Terminal Manager to look at.

A decided dispute (`application/finance/disputes.py`) changes its line's
count here: upheld, the line leaves the statement (fares and share);
adjusted, its share is the Terminal Manager's amount and its fares stay;
rejected or withdrawn, nothing changes and the share is due again. A
contested line is frozen as it was contested: the list no longer changes
it, and seats of the same kind added later go on a line of their own.

Two blocks read the undisputed balance (brief 2.1): Start waits for the
trip's statement to reach 0 -- the 15 %, the trip's DCOTT ticket and the
day's parking -- and a van with any balance is refused its next
assignment. The operator's share is never part of either. The Terminal Manager's override on a trip lifts both
for that trip ([ASSUMED] one override covers both).

A change of van after a payment moves the trip's lines and its DCOTT
ticket to the new van's statement; the payment stays where it was
recorded.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import (
    BookingStatus,
    BookingType,
    PaymentStatus,
    Role,
    StartReview,
    TripStatus,
)
from app.infrastructure.models import (
    Booking,
    Dispute,
    Remittance,
    RemittanceLine,
    RouteStop,
    SpecialTripRequest,
    Trip,
    User,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

CENT = Decimal("0.01")
ZERO = Decimal("0.00")

# Seats on the passenger list (brief 2.1): the ones the Dispatcher
# marked as paid in cash, whether or not the passenger came -- a paid
# no-show still counts, because the seat was paid for. A reservation
# that is not paid is not on the list and adds nothing to the amount
# owed; a cancelled seat has left it.
#
# A tuple of predicates, spread into a .where() by every caller, so that
# "on the list" has exactly one definition in the backend.
PAID_SEAT = (
    Booking.payment_status == PaymentStatus.PAID.value,
    Booking.status != BookingStatus.CANCELLED.value,
)
# The Dispatcher's own entries: a walk-up, in group W. Every other paid
# seat was reserved in the app, in group B.
WALK_UP_TYPES = (BookingType.WALK_IN.value, BookingType.DRIVER_ISSUED.value)
BOOKED, WALK_UP = "booked", "walk_up"
BEFORE_DEPARTURE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


def _trips_of(statement: Remittance) -> tuple:
    """The van's trips of the statement's day, voided ones included."""
    return (Trip.van_id == statement.van_id, Trip.service_date == statement.service_date)


def share_of(gross: Decimal, rate_pct: Decimal) -> Decimal:
    return (gross * rate_pct / 100).quantize(CENT, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class LineKey:
    dest_terminal_id: str | None    # None on a rental
    fare: Decimal
    group: str          # BOOKED | WALK_UP
    request_id: str | None = None   # a rental fee's request


class Statements:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ---------------------------------------------------------- the list
    async def listed(self, trip: Trip) -> dict[LineKey, int]:
        """The trip's paid seats, grouped as fare lines; on a rental, its
        paid fee."""
        if trip.route_id is None:
            rental = (await self.session.execute(
                select(SpecialTripRequest).where(
                    SpecialTripRequest.trip_id == trip.trip_id,
                    SpecialTripRequest.payment_status == "paid",
                )
            )).scalar_one_or_none()
            if rental is None:
                return {}
            # Brief 2.5: the fee is the whole income of the trip, and
            # which group it falls in is where the rental came from --
            # booked when the passenger requested it in the app,
            # walk-up when it was entered at the counter. The Dispatcher
            # takes the cash either way.
            group = BOOKED if rental.passenger_user_id else WALK_UP
            return {LineKey(None, Decimal(rental.rental_fee), group, rental.request_id): 1}
        terminal_at = await self._terminals(trip)
        rows = (await self.session.execute(
            select(Booking.alighting_stop_sequence, Booking.fare_amount, Booking.booking_type)
            .where(Booking.trip_id == trip.trip_id, *PAID_SEAT)
        )).all()
        out: dict[LineKey, int] = {}
        for alight, fare, kind in rows:
            key = LineKey(terminal_at[alight], Decimal(fare),
                          WALK_UP if kind in WALK_UP_TYPES else BOOKED)
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
    async def sync(self, trip: Trip, *, left_van: str | None = None) -> Remittance | None:
        """Bring the trip's fare lines in line with its passenger list and
        recompute the statements they touch. The caller commits.

        `left_van` is the van the trip was just taken from: its statement
        loses the trip's DCOTT ticket even when no line moves.

        Returns the trip's statement, or None when the trip has no van
        (no operator to owe anything)."""
        if left_van is not None and left_van != trip.van_id:
            left = await self._locked_statement(left_van, trip.service_date)
            if left is not None:
                await self.recompute(left)
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
        if trip.status == TripStatus.CANCELLED.value and not lines:
            # A voided trip opens nothing; one already counted leaves.
            statement = await self._locked_statement(trip.van_id, trip.service_date)
            if statement is not None:
                await self.recompute(statement)
            return statement
        statement = await self.statement_for(trip.van_id, trip.service_date)
        touched = {statement.remittance_id}

        # The van changed: the lines follow the trip, and so do the
        # disputes, which are about the trip's items.
        for line in lines:
            if line.remittance_id != statement.remittance_id:
                touched.add(line.remittance_id)
                line.remittance_id = statement.remittance_id
        if len(touched) > 1:
            await self.session.execute(
                update(Dispute).where(Dispute.trip_id == trip.trip_id)
                .values(remittance_id=statement.remittance_id)
            )

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
        """Before the lock: the lines are the list. A contested line
        stays as it was contested; the rest of the list fills the others."""
        want = await self.listed(trip)
        origin = (await self._terminals(trip)).get(1) if want else None
        contested = await self._contested(lines)
        for line in lines:
            key = self._key(line)
            if line.line_id in contested and key in want:
                want[key] -= line.passenger_count
                if want[key] <= 0:
                    del want[key]
        lines = [line for line in lines if line.line_id not in contested]
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
                # A top-up even when the list was empty at the payment:
                # the fees recorded then held no 15 % for this seat.
                self._add(trip, statement, origin, key, extra, top_up=True)
                added = True
        if added and trip.payment_status == "paid":
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
            request_id=key.request_id,
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

    async def _contested(self, lines: list[RemittanceLine]) -> set[str]:
        """The lines a dispute names, whatever became of it: its record
        needs the line as it was contested."""
        if not lines:
            return set()
        return set((await self.session.execute(
            select(Dispute.line_id).where(Dispute.line_id.in_([line.line_id for line in lines]))
        )).scalars())

    async def _drop(self, lines: list[RemittanceLine]) -> None:
        """Delete lines nobody disputes; a disputed line stays for the
        Terminal Manager's decision."""
        contested = await self._contested(lines)
        for line in lines:
            if line.line_id not in contested:
                await self.session.delete(line)

    @staticmethod
    def _key(line: RemittanceLine) -> LineKey:
        return LineKey(line.dest_terminal_id, Decimal(line.fare_per_passenger),
                       line.income_group, line.request_id)

    # -------------------------------------------------------- statements
    async def statement_for(self, van_id: str, service_date: date) -> Remittance:
        """The van's statement for the day, created on first use, locked.

        Opening it charges the day's parking, and keeps the rate and the
        DCOTT ticket in force for the rest of the day."""
        found = await self._locked_statement(van_id, service_date)
        if found is not None:
            return found
        van = await self.session.get(Van, van_id)
        policies = PolicyRepository(self.session)
        rate = await policies.get_decimal("remittance_rate_pct")
        dcott = await policies.get_decimal("dcott_ticket_fee")
        parking = await policies.get_decimal("parking_fee")
        now = _now()
        try:
            async with self.session.begin_nested():
                self.session.add(Remittance(
                    remittance_id=str(uuid.uuid4()), operator_id=van.operator_id,
                    van_id=van_id, service_date=service_date, rate_pct=rate,
                    dcott_ticket_fee=dcott, parking_fee=parking,
                    terminal_fees_owed=parking, created_at=now, updated_at=now,
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
        # A line carries at most one decided dispute (disputes.py).
        rows = (await self.session.execute(
            select(RemittanceLine.income_group, RemittanceLine.gross_fare,
                   RemittanceLine.share_amount, Trip.start_review_status,
                   Dispute.outcome, Dispute.adjusted_amount)
            .join(Trip, Trip.trip_id == RemittanceLine.trip_id)
            .outerjoin(Dispute, and_(Dispute.line_id == RemittanceLine.line_id,
                                     Dispute.status == "resolved"))
            .where(RemittanceLine.remittance_id == statement.remittance_id,
                   Trip.status != TripStatus.CANCELLED.value)
        )).all()
        booked = walk_up = owed = held = ZERO
        counted = 0
        for review, trips in (await self.session.execute(
            select(Trip.start_review_status, func.count())
            .where(*_trips_of(statement), Trip.status != TripStatus.CANCELLED.value)
            .group_by(Trip.start_review_status)
        )).all():
            if review == StartReview.PENDING.value:
                held += statement.dcott_ticket_fee * trips
            else:
                counted += trips
        for group, gross, share, review, outcome, adjusted in rows:
            if outcome == "upheld":
                continue
            if outcome == "adjusted":
                share = adjusted
            if review == StartReview.PENDING.value:
                held += share
                continue
            owed += share
            if group == BOOKED:
                booked += gross
            else:
                walk_up += gross
        statement.booked_income = booked
        statement.walk_up_income = walk_up
        statement.remittance_owed = owed
        statement.dcott_fees = statement.dcott_ticket_fee * counted
        statement.terminal_fees_owed = owed + statement.dcott_fees + statement.parking_fee
        statement.operator_share_owed = max(booked + walk_up - statement.terminal_fees_owed, ZERO)
        statement.held_share = held
        settled = statement.terminal_fees_owed + held - statement.settled_amount <= 0
        statement.status = "settled" if settled and statement.recorded_by else "open"
        statement.updated_at = _now()

    # ---------------------------------------------------------- balances
    async def disputed(self, statement: Remittance) -> Decimal:
        """The shares that wait for the Terminal Manager's decision, on
        lines the statement still counts."""
        return Decimal((await self.session.execute(
            select(func.coalesce(func.sum(Dispute.amount_disputed), 0))
            .join(Trip, Trip.trip_id == Dispute.trip_id)
            .where(
                Dispute.remittance_id == statement.remittance_id,
                Dispute.subject == "fare_line", Dispute.status == "open",
                Trip.status != TripStatus.CANCELLED.value,
            )
        )).scalar_one())

    async def due(self, statement: Remittance) -> Decimal:
        """What the Cashier should receive now: the undisputed balance of
        the terminal fees."""
        owing = (statement.terminal_fees_owed + statement.held_share
                 - statement.settled_amount - await self.disputed(statement))
        return max(owing, ZERO)

    async def van_balance(self, van_id: str) -> Decimal:
        """Everything the van owes that has fallen due (the assignment block).

        A statement for a day still to come is left out until one of its
        trips runs: a trip assigned ahead -- a rental booked for Friday --
        owes its DCOTT ticket and that day's parking on Friday, not today.
        A trip that has already left owes now, whatever its date."""
        ran = select(Trip.trip_id).where(
            Trip.van_id == Remittance.van_id, Trip.service_date == Remittance.service_date,
            Trip.status.notin_((TripStatus.SCHEDULED.value, TripStatus.CANCELLED.value)),
        ).exists()
        total = ZERO
        for statement in (await self.session.execute(
            select(Remittance).where(
                Remittance.van_id == van_id, Remittance.status == "open",
                or_(Remittance.service_date <= app_tz.now().date(), ran),
            )
        )).scalars():
            total += await self.due(statement)
        return total

    async def share_difference(self, statement: Remittance) -> Decimal | None:
        """The operator's share owed less the share given, once every
        trip's list on the statement is locked; None before. Positive is
        short, negative over (T68)."""
        open_list = await self.session.scalar(
            select(func.count()).select_from(Trip).where(
                *_trips_of(statement), Trip.status != TripStatus.CANCELLED.value,
                Trip.list_locked_at.is_(None),
            ))
        if open_list:
            return None
        return statement.operator_share_owed - statement.operator_share_given

    # ---------------------------------------------------------- payments
    async def record_payment(
        self, statement: Remittance, *, by: User, amount: Decimal,
        reference: str | None, handed_over_by: str | None,
        operator_share: Decimal | None = None,
    ) -> Remittance:
        """The Cashier records the terminal fees the Dispatcher handed
        over and, in the same step, the operator's share handed to the
        operator. The caller commits."""
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
        if operator_share:
            self._give_share(statement, by=by, amount=operator_share, at=now)
        await self.recompute(statement)

        if await self.due(statement) == 0:
            for trip in (await self.session.execute(
                select(Trip).where(*_trips_of(statement),
                                   Trip.payment_status == "unpaid",
                                   Trip.status.in_(BEFORE_DEPARTURE))
            )).scalars():
                trip.payment_status = "paid"
        return statement

    async def record_operator_share(
        self, statement: Remittance, *, by: User, amount: Decimal,
    ) -> Remittance:
        """The operator's share recorded on its own: a difference handed
        over after the payment (T68). The caller commits."""
        amount = Decimal(amount).quantize(CENT)
        if amount <= 0:
            raise ConflictError("Record an amount above zero.")
        self._give_share(statement, by=by, amount=amount, at=_now())
        await self.recompute(statement)
        return statement

    @staticmethod
    def _give_share(statement: Remittance, *, by: User, amount: Decimal, at: datetime) -> None:
        # Amounts only: the system never holds the money, and the operator
        # has no account to confirm it ([ASSUMED] the operator does not sign).
        statement.operator_share_given += Decimal(amount).quantize(CENT)
        statement.operator_share_given_at = at
        statement.operator_share_recorded_by = by.user_id

    async def charge_parking(self, van_id: str, service_date: date) -> Remittance:
        """The Cashier's parking-only charge for a van parked at the
        terminal with no trip that day (T65): a statement with the P50,
        no trip and no fare line. The caller commits."""
        if service_date > app_tz.now().date():
            raise ConflictError("Parking is charged for a day the van was at the terminal.")
        if await self._locked_statement(van_id, service_date) is not None:
            raise ConflictError(
                "This van already has a statement for that day, and its parking is on it."
            )
        statement = await self.statement_for(van_id, service_date)
        await self.recompute(statement)
        return statement

    async def pay_trip(
        self, trip: Trip, *, by: User, amount: Decimal,
        reference: str | None, handed_over_by: str | None,
        operator_share: Decimal | None = None,
    ) -> Remittance:
        """The terminal fees of the trip about to leave (brief 2.1),
        recorded on its van's statement with the operator's share, and the
        list locks to cancellations."""
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
            operator_share=operator_share,
        )
        trip.list_locked_at = trip.list_locked_at or _now()
        return statement

    async def lock_at_departure(self, trip: Trip) -> Decimal:
        """The van has left: the list is final. Returns the terminal fees it
        left without paying ('left_unpaid', brief 2.1), or 0."""
        statement = await self.sync(trip)
        trip.list_locked_at = trip.list_locked_at or _now()
        if statement is None or trip.payment_status != "unpaid":
            return ZERO
        due = await self.due(statement)
        if due > 0:
            trip.payment_status = "left_unpaid"
        return due
