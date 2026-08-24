"""Payment use cases: start a checkout, and settle it from the webhook."""

from __future__ import annotations

import json
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import BookingStatus, PaymentStatus
from app.infrastructure.clients.paymongo_client import PayMongoClient
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Payment as PaymentRow
from app.infrastructure.models import Trip
from app.infrastructure.repositories.seat_repository import SeatRepository

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class CheckoutResult:
    payment_id: str
    checkout_url: str
    amount: Any


class StartCheckoutUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.paymongo = PayMongoClient()

    async def execute(self, *, booking_id: str, passenger_user_id: str) -> CheckoutResult:
        booking = await self.session.get(BookingRow, booking_id)
        if booking is None:
            raise NotFoundError("Booking not found.")
        if booking.passenger_user_id != passenger_user_id:
            raise NotFoundError("Booking not found.")
        if booking.status != BookingStatus.PENDING.value:
            raise ConflictError(
                f"Only pending bookings can be paid; this one is {booking.status}."
            )

        # Reuse an in-flight checkout rather than creating a second one --
        # otherwise a passenger who taps Pay twice ends up with two live
        # sessions and can be charged twice for one seat.
        existing = await self.session.execute(
            select(PaymentRow).where(
                PaymentRow.booking_id == booking_id,
                PaymentRow.status == PaymentStatus.PENDING.value,
            )
        )
        prior = existing.scalar_one_or_none()
        if prior is not None and prior.provider_ref_id:
            log.info("Reusing existing checkout for booking %s", booking_id)

        trip = await self.session.get(Trip, booking.trip_id)
        label = trip.trip_label if trip else "UV Express"

        session_data = await self.paymongo.create_checkout(
            booking_id=booking.booking_id,
            ticket_number=booking.ticket_number,
            amount=booking.fare_amount,
            description=f"{label} - seat {booking.seat_number}",
            success_url=f"{settings.payment_success_url}?ref={booking.ticket_number}",
            cancel_url=f"{settings.payment_cancel_url}?ref={booking.ticket_number}",
        )

        payment_id = str(uuid.uuid4())
        self.session.add(
            PaymentRow(
                payment_id=payment_id,
                booking_id=booking.booking_id,
                provider="paymongo",
                provider_ref_id=session_data["checkout_session_id"],
                amount=booking.fare_amount,
                status=PaymentStatus.PENDING.value,
                created_at=datetime.now(timezone.utc),
            )
        )
        await self.session.commit()

        return CheckoutResult(
            payment_id=payment_id,
            checkout_url=session_data["checkout_url"],
            amount=booking.fare_amount,
        )


class SettlePaymentUseCase:
    """Handles a verified PayMongo webhook.

    This is the ONLY place a booking becomes confirmed. The client redirect
    after payment is a UX convenience and is never trusted.
    """

    def __init__(self, session: AsyncSession):
        self.session = session
        self.seats = SeatRepository(session)

    async def execute(self, event: dict[str, Any]) -> dict[str, str]:
        event_id = event.get("data", {}).get("id")
        event_type = event.get("data", {}).get("attributes", {}).get("type")

        if event_type not in {
            "checkout_session.payment.paid",
            "payment.paid",
            "payment.failed",
        }:
            return {"status": "ignored", "reason": f"unhandled type {event_type}"}

        # Idempotency. PayMongo retries webhooks on any non-2xx, and
        # networks duplicate deliveries. `provider_event_id` is UNIQUE, so
        # a replay is detected here and short-circuits before touching
        # seats or bookings.
        seen = await self.session.execute(
            select(PaymentRow).where(PaymentRow.provider_event_id == event_id)
        )
        if seen.scalar_one_or_none() is not None:
            log.info("Duplicate webhook %s ignored.", event_id)
            return {"status": "duplicate", "event_id": event_id}

        attrs = event["data"]["attributes"]["data"]["attributes"]
        metadata = attrs.get("metadata") or {}
        booking_id = metadata.get("booking_id")

        if not booking_id:
            log.error("Webhook %s carried no booking_id metadata.", event_id)
            return {"status": "ignored", "reason": "no booking_id in metadata"}

        booking = await self.session.get(BookingRow, booking_id)
        if booking is None:
            log.error("Webhook %s references unknown booking %s", event_id, booking_id)
            return {"status": "ignored", "reason": "unknown booking"}

        result = await self.session.execute(
            select(PaymentRow)
            .where(PaymentRow.booking_id == booking_id)
            .order_by(PaymentRow.created_at.desc())
            .limit(1)
        )
        payment = result.scalar_one_or_none()
        if payment is None:
            payment = PaymentRow(
                payment_id=str(uuid.uuid4()),
                booking_id=booking_id,
                provider="paymongo",
                amount=booking.fare_amount,
                status=PaymentStatus.PENDING.value,
                created_at=datetime.now(timezone.utc),
            )
            self.session.add(payment)

        now = datetime.now(timezone.utc)
        payment.provider_event_id = event_id
        payment.raw_payload = json.dumps(event)[:65000]

        if event_type == "payment.failed":
            payment.status = PaymentStatus.FAILED.value
            await self.session.commit()
            log.info("Payment failed for booking %s; hold left to expire.", booking_id)
            return {"status": "failed", "booking_id": booking_id}

        # --- paid ---------------------------------------------------
        payment.status = PaymentStatus.PAID.value
        payment.paid_at = now
        payment.method = (attrs.get("source") or {}).get("type") or attrs.get(
            "payment_method_used"
        )

        if booking.status == BookingStatus.PENDING.value:
            booking.status = BookingStatus.CONFIRMED.value
            booking.updated_at = now
            # held -> booked, and the hold stops expiring.
            await self.seats.confirm(booking_id=booking_id)
        else:
            log.warning(
                "Payment for booking %s arrived while status was %s.",
                booking_id, booking.status,
            )

        await self.session.commit()
        log.info("Booking %s confirmed by webhook %s", booking_id, event_id)
        return {"status": "confirmed", "booking_id": booking_id}
