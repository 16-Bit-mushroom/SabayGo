"""An operator's dispute of a fare line or a driving flag.

Rev 603, change brief 2.1 (Table 39, tests T9-T11). The operator has no
account, so a dispute is recorded at the counter, in the operator's own
words, by the trip's Dispatcher, the Cashier or the Terminal Manager.
Only the Terminal Manager decides, with a written reason, logged with
who and when. A decision is final. The Terminal Manager may decide a
dispute over their own earlier decision, since there is no third role
(a limitation the paper states).

What can be disputed, and until when:
  - a fare line, until the Cashier records a payment on its statement
    after the line was written (T11). Payments are recorded against the
    statement, not against lines, so that payment is the one that
    covered it. A top-up line can be disputed until the next payment;
  - a driving flag, after the trip too, while the trip's GPS readings
    are kept (T10). It withholds nothing (amount_disputed 0.00).
One item carries one dispute: a second is refused while one is open or
decided. A withdrawn dispute does not block a new one.

What it does to the money (applied in `Statements`):
  - open: the line's share (rate x its fare) waits. The undisputed
    balance leaves it out, so it blocks neither Start nor the van's next
    assignment, and the operator pays the rest (T9);
  - upheld: the line leaves the amount owed;
  - rejected, or withdrawn by the operator: the share is due again, and
    both blocks see it. A trip not yet departed goes back to 'unpaid',
    as it does for a top-up;
  - adjusted: the share due is the Terminal Manager's amount, between
    0.00 and the disputed share. A flag withholds nothing, so it cannot
    be adjusted.
A driving flag's decision is its review: upheld dismisses the flag,
rejected keeps it ('reviewed').

Every write locks the trip, then its statement, as the payment does.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.finance.statement import BEFORE_DEPARTURE, Statements
from app.application.identity.naming import display_name
from app.application.notifications.service import NotificationService, trip_label
from app.application.operations.guards import assert_assigned_to_trip
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, InvalidInputError, NotFoundError
from app.domain.enums import Role, TripStatus
from app.infrastructure.models import (
    Dispute,
    DrivingEvent,
    Remittance,
    RemittanceLine,
    Terminal,
    Trip,
    TripLocationPing,
    User,
)

log = logging.getLogger(__name__)

OUTCOMES = ("upheld", "rejected", "adjusted")
# A dispute that still stands on its item.
STANDING = ("open", "resolved")


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


def _text(value: str | None, *, limit: int, what: str) -> str:
    value = (value or "").strip()
    if not value:
        raise InvalidInputError(f"Write {what}.")
    if len(value) > limit:
        raise InvalidInputError(f"Keep {what} to {limit} characters.")
    return value


class Disputes:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.money = Statements(session)

    # ------------------------------------------------------------ record
    async def raise_on_line(self, line_id: str, *, by: User, statement: str) -> Dispute:
        """The operator contests a fare line before paying (T9, T11)."""
        words = _text(statement, limit=500, what="the operator's statement")
        trip_id = await self.session.scalar(
            select(RemittanceLine.trip_id).where(RemittanceLine.line_id == line_id))
        if trip_id is None:
            raise NotFoundError("Fare line not found.")
        trip = await self._recorder_trip(trip_id, by)
        # Re-read under the trip's lock: a change of van moves the line.
        line = (await self.session.execute(
            select(RemittanceLine).where(RemittanceLine.line_id == line_id)
            .execution_options(populate_existing=True)
        )).scalar_one()
        account = await self._locked_statement(line.remittance_id)
        if trip.status == TripStatus.CANCELLED.value:
            raise ConflictError("This trip was voided: it owes nothing.")
        if account.settled_at is not None and line.created_at <= account.settled_at:
            raise ConflictError(
                f"The payment covering this line was recorded at {account.settled_at:%H:%M}. "
                "A fare line is disputed before the share is paid, not after."
            )
        await self._none_standing(Dispute.line_id == line_id)
        dispute = self._new(trip, account, by=by, words=words, subject="fare_line",
                            line_id=line_id, amount=line.share_amount)
        await self._tell_manager(trip, by, await self._line_text(line), dispute)
        await self.session.commit()
        return dispute

    async def raise_on_flag(self, driving_event_id: str, *, by: User, statement: str) -> Dispute:
        """The operator contests a driving flag, after the trip too (T10)."""
        words = _text(statement, limit=500, what="the operator's statement")
        trip_id = await self.session.scalar(
            select(DrivingEvent.trip_id)
            .where(DrivingEvent.driving_event_id == driving_event_id))
        if trip_id is None:
            raise NotFoundError("Driving flag not found.")
        trip = await self._recorder_trip(trip_id, by)
        flag = await self.session.get(DrivingEvent, driving_event_id)
        if flag.review_status == "dismissed":
            raise ConflictError("This flag was dismissed: there is nothing to dispute.")
        if trip.van_id is None:
            raise ConflictError("This trip has no van, so no operator to dispute for.")
        kept = await self.session.scalar(
            select(exists().where(TripLocationPing.trip_id == trip.trip_id)))
        if not kept:
            raise ConflictError(
                "This trip's GPS readings are no longer kept, so the flag can no "
                "longer be disputed."
            )
        await self._none_standing(Dispute.driving_event_id == driving_event_id)
        account = await self.money.statement_for(trip.van_id, trip.service_date)
        dispute = self._new(trip, account, by=by, words=words, subject="driving_flag",
                            driving_event_id=driving_event_id, amount=Decimal("0.00"))
        await self._tell_manager(
            trip, by, f"the {flag.flag_type.replace('_', ' ')} flag at {flag.start_at:%H:%M}",
            dispute)
        await self.session.commit()
        return dispute

    async def withdraw(self, dispute_id: str, *, by: User, note: str | None) -> Dispute:
        """The operator drops the dispute: the share is due again."""
        dispute, trip, account = await self._locked(dispute_id)
        if by.role == Role.DISPATCHER.value:
            await assert_assigned_to_trip(self.session, trip_id=trip.trip_id, user=by)
        self._still_open(dispute)
        note = (note or "").strip()
        dispute.status = "withdrawn"
        dispute.decided_by = by.user_id
        dispute.decided_at = _now()
        dispute.decision_note = note[:255] or None
        await self._settle(dispute, trip, account)
        await self.session.commit()
        return dispute

    # ------------------------------------------------------------ decide
    async def decide(
        self, dispute_id: str, *, by: User, outcome: str, note: str,
        adjusted_amount: Decimal | None = None,
    ) -> Dispute:
        """The Terminal Manager's decision (the guard is the endpoint's)."""
        if outcome not in OUTCOMES:
            raise InvalidInputError("Decide upheld, rejected or adjusted.")
        note = _text(note, limit=255, what="the reason for the decision")
        dispute, trip, account = await self._locked(dispute_id)
        self._still_open(dispute)
        if outcome == "adjusted":
            if dispute.subject == "driving_flag":
                raise ConflictError("A driving flag withholds nothing: uphold or reject it.")
            if adjusted_amount is None:
                raise InvalidInputError("Give the share that is due.")
            adjusted_amount = Decimal(adjusted_amount).quantize(Decimal("0.01"))
            if not Decimal("0.00") <= adjusted_amount <= dispute.amount_disputed:
                raise InvalidInputError(
                    f"The share due is between ₱0.00 and the disputed ₱{dispute.amount_disputed:,.2f}."
                )
        elif adjusted_amount is not None:
            raise InvalidInputError("Only an adjusted decision sets the share due.")

        dispute.status = "resolved"
        dispute.outcome = outcome
        dispute.adjusted_amount = adjusted_amount
        dispute.decided_by = by.user_id
        dispute.decided_at = _now()
        dispute.decision_note = note
        if dispute.subject == "driving_flag":
            flag = await self.session.get(DrivingEvent, dispute.driving_event_id)
            flag.review_status = "dismissed" if outcome == "upheld" else "reviewed"
            flag.reviewed_by, flag.reviewed_at = by.user_id, dispute.decided_at
            flag.review_note = f"Dispute {outcome}: {note}"[:255]
        await self._settle(dispute, trip, account)
        await self.session.commit()
        log.info("Dispute %s %s by %s.", dispute_id, outcome, by.user_id)
        return dispute

    # ----------------------------------------------------------- helpers
    async def _recorder_trip(self, trip_id: str, by: User) -> Trip:
        if by.role == Role.DISPATCHER.value:
            await assert_assigned_to_trip(self.session, trip_id=trip_id, user=by)
        return (await self.session.execute(
            select(Trip).where(Trip.trip_id == trip_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one()

    async def _locked_statement(self, remittance_id: str) -> Remittance:
        return (await self.session.execute(
            select(Remittance).where(Remittance.remittance_id == remittance_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one()

    async def _locked(self, dispute_id: str) -> tuple[Dispute, Trip, Remittance]:
        trip_id = await self.session.scalar(
            select(Dispute.trip_id).where(Dispute.dispute_id == dispute_id))
        if trip_id is None:
            raise NotFoundError("Dispute not found.")
        trip = (await self.session.execute(
            select(Trip).where(Trip.trip_id == trip_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one()
        dispute = (await self.session.execute(
            select(Dispute).where(Dispute.dispute_id == dispute_id)
            .execution_options(populate_existing=True)
        )).scalar_one()
        return dispute, trip, await self._locked_statement(dispute.remittance_id)

    @staticmethod
    def _still_open(dispute: Dispute) -> None:
        if dispute.status != "open":
            raise ConflictError(
                "This dispute was withdrawn." if dispute.status == "withdrawn"
                else f"This dispute was already decided: {dispute.outcome}."
            )

    async def _none_standing(self, item) -> None:
        if await self.session.scalar(
            select(exists().where(item, Dispute.status.in_(STANDING)))
        ):
            raise ConflictError("This item is already disputed. Its dispute is decided once.")

    def _new(self, trip: Trip, account: Remittance, *, by: User, words: str, subject: str,
             amount: Decimal, line_id: str | None = None,
             driving_event_id: str | None = None) -> Dispute:
        dispute = Dispute(
            dispute_id=str(uuid.uuid4()), remittance_id=account.remittance_id,
            trip_id=trip.trip_id, subject=subject, line_id=line_id,
            driving_event_id=driving_event_id, operator_statement=words,
            amount_disputed=amount, raised_by_role=by.role, raised_by=by.user_id,
            raised_at=_now(), status="open",
        )
        self.session.add(dispute)
        return dispute

    async def _settle(self, dispute: Dispute, trip: Trip, account: Remittance) -> None:
        """Recompute the statement after a decision or a withdrawal. A
        share due again before departure blocks Start, as a top-up does."""
        if dispute.subject != "fare_line":
            return
        await self.session.flush()
        await self.money.recompute(account)
        if (trip.status in BEFORE_DEPARTURE and trip.payment_status == "paid"
                and await self.money.due(account) > 0):
            trip.payment_status = "unpaid"

    async def _line_text(self, line: RemittanceLine) -> str:
        if line.request_id is not None:
            return f"the rental fee of ₱{line.gross_fare:,.2f}"
        to = await self.session.scalar(
            select(Terminal.terminal_name).where(Terminal.terminal_id == line.dest_terminal_id))
        seats = f"{line.passenger_count} seat{'s' if line.passenger_count > 1 else ''}"
        return f"the {line.income_group} line to {to} ({seats}, share ₱{line.share_amount:,.2f})"

    async def _tell_manager(self, trip: Trip, by: User, item: str, dispute: Dispute) -> None:
        await self.session.flush()
        await NotificationService(self.session).notify_trip(
            trip=trip, type="dispute_raised", title="Dispute raised",
            message=(f"{display_name(by)} recorded the operator's dispute of {item} on "
                     f"{trip_label(trip)}: “{dispute.operator_statement}”"),
            roles=(Role.TERMINAL_MANAGER,), skip_user_id=by.user_id,
        )
