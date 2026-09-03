"""Cash remittance.

Cash walk-ins are money the cooperative has earned but has not yet
received -- it is in the conductor's pocket. Those are different states,
and conflating them is what made the revenue report accuse honest crew.

The handover is a three-step record:

    expected   what the system says the crew collected  (computed)
    declared   what the crew says they are handing over (crew types it)
    received   what the office actually counted         (office types it)

Only `received − expected` is a shortage. `declared` sits between them so
a disagreement is visible: if a conductor declares the right amount and
the office counts less, that is a different problem from a conductor who
declares less than they collected.

Remittance is per trip, per crew member, at the end of the trip.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, NotFoundError
from app.core.timezone import APP_TZ
from app.domain.enums import BookingStatus, BookingType, PaymentStatus
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import CashRemittance
from app.infrastructure.models import Payment as PaymentRow
from app.infrastructure.models import Trip, User

log = logging.getLogger(__name__)

CASH_TYPES = [BookingType.WALK_IN.value, BookingType.DRIVER_ISSUED.value]
COUNTED = [
    BookingStatus.CONFIRMED.value,
    BookingStatus.CHECKED_IN.value,
    BookingStatus.BOARDED.value,
    BookingStatus.COMPLETED.value,
    # A no-show still paid cash before failing to travel, so the money is
    # real and must be remitted.
    BookingStatus.NO_SHOW.value,
]


@dataclass(frozen=True)
class RemittanceSummary:
    remittance_id: str | None
    trip_id: str
    trip_label: str | None
    service_date: date
    collected_by_user_id: str
    collected_by_name: str | None
    booking_count: int
    expected_amount: Decimal
    declared_amount: Decimal | None
    received_amount: Decimal | None
    variance: Decimal | None
    status: str
    submitted_at: datetime | None
    received_at: datetime | None
    notes: str | None


class RemittanceService:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ------------------------------------------------------------------
    async def _expected_for(self, trip_id: str, user_id: str) -> tuple[Decimal, int]:
        """Sum of cash fares this crew member logged on this trip.

        Computed from the bookings themselves, never typed in. This is the
        figure the crew is measured against, so it must not be editable by
        the person being measured.
        """
        result = await self.session.execute(
            select(
                func.coalesce(func.sum(BookingRow.fare_amount), 0),
                func.count(BookingRow.booking_id),
            )
            .select_from(BookingRow)
            .join(PaymentRow, PaymentRow.booking_id == BookingRow.booking_id)
            .where(
                BookingRow.trip_id == trip_id,
                BookingRow.booking_type.in_(CASH_TYPES),
                BookingRow.status.in_(COUNTED),
                PaymentRow.provider == "cash",
                PaymentRow.status == PaymentStatus.PENDING.value,
            )
        )
        total, count = result.one()
        return Decimal(str(total)), int(count)

    # ------------------------------------------------------------------
    async def preview(self, *, trip_id: str, user_id: str) -> RemittanceSummary:
        """What the crew owes on this trip, before they hand it over."""
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        existing = await self._find(trip_id, user_id)
        if existing is not None:
            return await self._to_summary(existing)

        expected, count = await self._expected_for(trip_id, user_id)
        user = await self.session.get(User, user_id)
        return RemittanceSummary(
            remittance_id=None,
            trip_id=trip_id,
            trip_label=trip.trip_label,
            service_date=trip.service_date,
            collected_by_user_id=user_id,
            collected_by_name=_name_of(user),
            booking_count=count,
            expected_amount=expected,
            declared_amount=None,
            received_amount=None,
            variance=None,
            status="pending",
            submitted_at=None,
            received_at=None,
            notes=None,
        )

    # ------------------------------------------------------------------
    async def submit(
        self, *, trip_id: str, user_id: str, declared_amount: Decimal,
        notes: str | None = None,
    ) -> RemittanceSummary:
        """Crew declares what they are handing over, at the end of a trip."""
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")
        # Remittance closes a trip's cash. Doing it before departure would
        # miss every roadside passenger picked up along the way.
        if trip.status not in ("departed", "completed"):
            raise ConflictError(
                f"Cash is remitted after the trip runs; this one is {trip.status}."
            )
        if declared_amount < 0:
            raise ConflictError("A declared amount cannot be negative.")

        existing = await self._find(trip_id, user_id)
        if existing is not None and existing.status == "received":
            raise ConflictError("This remittance has already been received.")

        expected, count = await self._expected_for(trip_id, user_id)
        if count == 0:
            raise ConflictError("No cash fares are outstanding for you on this trip.")

        now = datetime.now(APP_TZ)
        if existing is None:
            existing = CashRemittance(
                remittance_id=str(uuid.uuid4()),
                trip_id=trip_id,
                collected_by_user_id=user_id,
                expected_amount=expected,
                created_at=now,
                updated_at=now,
            )
            self.session.add(existing)
            await self.session.flush()

        existing.expected_amount = expected
        existing.declared_amount = declared_amount
        existing.status = "submitted"
        existing.submitted_at = now
        existing.notes = notes

        # Tag the payments this handover covers, so a disputed shortage
        # can be traced back to specific fares.
        await self._attach_payments(trip_id, existing.remittance_id)

        await self.session.commit()
        log.info(
            "Remittance %s submitted: expected %s, declared %s",
            existing.remittance_id, expected, declared_amount,
        )
        return await self._to_summary(existing)

    # ------------------------------------------------------------------
    async def confirm_receipt(
        self, *, remittance_id: str, received_amount: Decimal,
        received_by_user_id: str, notes: str | None = None,
    ) -> RemittanceSummary:
        """Office records what it actually counted.

        Marking the covered payments 'paid' is what finally moves the money
        out of `cash_in_hand` and into `collected_fare` on the revenue view.
        """
        remittance = await self.session.get(CashRemittance, remittance_id)
        if remittance is None:
            raise NotFoundError("Remittance not found.")
        if remittance.status == "received":
            raise ConflictError("This remittance has already been received.")
        if received_amount < 0:
            raise ConflictError("A received amount cannot be negative.")

        now = datetime.now(APP_TZ)
        remittance.received_amount = received_amount
        remittance.variance = received_amount - remittance.expected_amount
        remittance.received_by_user_id = received_by_user_id
        remittance.received_at = now
        # A shortage does not block the handover -- it flags it. Refusing
        # to record a short remittance would just mean it goes unrecorded.
        remittance.status = "received" if remittance.variance == 0 else "disputed"
        if notes:
            remittance.notes = notes

        result = await self.session.execute(
            select(PaymentRow).where(PaymentRow.remittance_id == remittance_id)
        )
        for payment in result.scalars():
            payment.status = PaymentStatus.PAID.value
            payment.paid_at = now

        await self.session.commit()
        log.info(
            "Remittance %s received: expected %s, got %s, variance %s",
            remittance_id, remittance.expected_amount, received_amount,
            remittance.variance,
        )
        return await self._to_summary(remittance)

    # ------------------------------------------------------------------
    async def outstanding(self, *, limit: int = 100) -> list[RemittanceSummary]:
        """Cash the cooperative is still waiting on."""
        result = await self.session.execute(
            select(CashRemittance)
            .where(CashRemittance.status.in_(["pending", "submitted", "disputed"]))
            .order_by(CashRemittance.created_at.desc())
            .limit(limit)
        )
        return [await self._to_summary(r) for r in result.scalars()]

    async def unremitted_trips(self, *, limit: int = 100) -> list[dict]:
        """Finished trips with cash still in a pocket and no handover started.

        This is the list an operator chases -- a conductor who simply never
        submits would otherwise be invisible.
        """
        result = await self.session.execute(
            select(
                BookingRow.trip_id,
                Trip.trip_label,
                Trip.service_date,
                Trip.conductor_id,
                Trip.driver_id,
                func.sum(BookingRow.fare_amount).label("amount"),
                func.count(BookingRow.booking_id).label("bookings"),
            )
            .join(Trip, Trip.trip_id == BookingRow.trip_id)
            .join(PaymentRow, PaymentRow.booking_id == BookingRow.booking_id)
            .where(
                BookingRow.booking_type.in_(CASH_TYPES),
                PaymentRow.provider == "cash",
                PaymentRow.status == PaymentStatus.PENDING.value,
                PaymentRow.remittance_id.is_(None),
                Trip.status.in_(["departed", "completed"]),
            )
            .group_by(
                BookingRow.trip_id, Trip.trip_label, Trip.service_date,
                Trip.conductor_id, Trip.driver_id,
            )
            .order_by(Trip.service_date.desc())
            .limit(limit)
        )
        return [
            {
                "trip_id": row.trip_id,
                "trip_label": row.trip_label,
                "service_date": row.service_date,
                "conductor_id": row.conductor_id,
                "driver_id": row.driver_id,
                "cash_outstanding": row.amount,
                "booking_count": row.bookings,
            }
            for row in result
        ]

    # ------------------------------------------------------------------
    async def _find(self, trip_id: str, user_id: str) -> CashRemittance | None:
        result = await self.session.execute(
            select(CashRemittance).where(
                CashRemittance.trip_id == trip_id,
                CashRemittance.collected_by_user_id == user_id,
            )
        )
        return result.scalar_one_or_none()

    async def _attach_payments(self, trip_id: str, remittance_id: str) -> None:
        result = await self.session.execute(
            select(PaymentRow)
            .join(BookingRow, BookingRow.booking_id == PaymentRow.booking_id)
            .where(
                BookingRow.trip_id == trip_id,
                BookingRow.booking_type.in_(CASH_TYPES),
                PaymentRow.provider == "cash",
                PaymentRow.status == PaymentStatus.PENDING.value,
            )
        )
        for payment in result.scalars():
            payment.remittance_id = remittance_id

    async def _to_summary(self, r: CashRemittance) -> RemittanceSummary:
        trip = await self.session.get(Trip, r.trip_id)
        user = await self.session.get(User, r.collected_by_user_id)
        count = await self.session.execute(
            select(func.count())
            .select_from(PaymentRow)
            .where(PaymentRow.remittance_id == r.remittance_id)
        )
        return RemittanceSummary(
            remittance_id=r.remittance_id,
            trip_id=r.trip_id,
            trip_label=trip.trip_label if trip else None,
            service_date=trip.service_date if trip else date.today(),
            collected_by_user_id=r.collected_by_user_id,
            collected_by_name=_name_of(user),
            booking_count=int(count.scalar_one()),
            expected_amount=r.expected_amount,
            declared_amount=r.declared_amount,
            received_amount=r.received_amount,
            variance=r.variance,
            status=r.status,
            submitted_at=r.submitted_at,
            received_at=r.received_at,
            notes=r.notes,
        )


def _name_of(user: User | None) -> str | None:
    if user is None:
        return None
    profile = user.staff_profile
    return f"{profile.first_name} {profile.last_name}" if profile else user.email
