"""Payment endpoints."""

from __future__ import annotations

import json
import logging
from decimal import Decimal

from fastapi import APIRouter, Header, Request
from pydantic import BaseModel

from app.api.v1.deps import CurrentUser, SessionDep
from app.application.booking.payments import (
    SettlePaymentUseCase,
    StartCheckoutUseCase,
)
from app.config import settings
from app.infrastructure.clients.paymongo_client import PayMongoClient

log = logging.getLogger(__name__)
router = APIRouter(prefix="/payments", tags=["payments"])


class CheckoutRequest(BaseModel):
    booking_id: str


class CheckoutResponse(BaseModel):
    payment_id: str
    checkout_url: str
    amount: Decimal


@router.post("/checkout", response_model=CheckoutResponse, status_code=201)
async def start_checkout(
    payload: CheckoutRequest, session: SessionDep, user: CurrentUser
) -> CheckoutResponse:
    """Create a PayMongo checkout session for a pending booking."""
    result = await StartCheckoutUseCase(session).execute(
        booking_id=payload.booking_id, passenger_user_id=user.user_id
    )
    return CheckoutResponse(
        payment_id=result.payment_id,
        checkout_url=result.checkout_url,
        amount=result.amount,
    )


@router.post("/webhook", include_in_schema=False)
async def paymongo_webhook(
    request: Request,
    session: SessionDep,
    paymongo_signature: str | None = Header(default=None, alias="Paymongo-Signature"),
) -> dict[str, str]:
    """Receive and settle a PayMongo webhook.

    Unauthenticated by design -- PayMongo cannot hold a JWT. The HMAC
    signature IS the authentication, so it is verified before the body is
    parsed or trusted.

    Always returns 200, even for rejected events. PayMongo retries on any
    non-2xx, and retrying a signature failure or an unknown booking will
    never succeed -- it just floods the endpoint. Genuine processing
    errors still raise and produce a 500, which SHOULD be retried.
    """
    raw = await request.body()

    if not settings.paymongo_webhook_secret:
        log.error("PAYMONGO_WEBHOOK_SECRET unset; rejecting webhook.")
        return {"status": "rejected", "reason": "webhook secret not configured"}

    if not paymongo_signature:
        log.warning("Webhook received with no signature header.")
        return {"status": "rejected", "reason": "missing signature"}

    if not PayMongoClient.verify_signature(
        raw_body=raw,
        signature_header=paymongo_signature,
        webhook_secret=settings.paymongo_webhook_secret,
    ):
        log.warning("Webhook signature verification FAILED.")
        return {"status": "rejected", "reason": "invalid signature"}

    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        return {"status": "rejected", "reason": "malformed json"}

    return await SettlePaymentUseCase(session).execute(event)
