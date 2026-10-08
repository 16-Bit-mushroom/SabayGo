"""Payment endpoints."""

from __future__ import annotations

import html
import json
import logging
from decimal import Decimal

from fastapi import APIRouter, Header, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select

from app.api.v1.deps import CurrentUser, SessionDep
from app.application.booking.payments import (
    SettlePaymentUseCase,
    StartCheckoutUseCase,
)
from app.config import settings
from app.core.exceptions import NotFoundError
from app.domain.enums import BookingStatus
from app.infrastructure.clients.paymongo_client import PayMongoClient
from app.infrastructure.clients.sandbox_checkout import (
    SandboxCheckoutClient,
    checkout_client,
    sandbox_enabled,
)
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import Payment as PaymentRow

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
    payload: CheckoutRequest, session: SessionDep, user: CurrentUser, request: Request
) -> CheckoutResponse:
    """Create a checkout session for a pending booking -- PayMongo, or in
    development without PayMongo keys, the sandbox below.

    The sandbox URL is built from the host the CLIENT used, so a phone that
    reached the backend at its LAN address is sent back to that address,
    not to a localhost it cannot see."""
    checkout = checkout_client(
        lambda cs_id: str(request.url_for("sandbox_checkout_page", checkout_session_id=cs_id))
    )
    result = await StartCheckoutUseCase(session, checkout).execute(
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
    return await _receive_webhook(await request.body(), paymongo_signature, session)


async def _receive_webhook(
    raw: bytes, paymongo_signature: str | None, session
) -> dict[str, str]:
    """Verify, then settle. The one path a payment confirmation can take --
    the sandbox's signed events come through here too."""
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


# ===================================================================
# Development sandbox -- see infrastructure/clients/sandbox_checkout.py.
# Every route here is a 404 unless sandbox_enabled().
# ===================================================================
async def _sandbox_booking(session, checkout_session_id: str) -> tuple[PaymentRow, BookingRow]:
    if not sandbox_enabled():
        raise NotFoundError("Not found.")
    payment = (
        await session.execute(
            select(PaymentRow).where(PaymentRow.provider_ref_id == checkout_session_id)
        )
    ).scalar_one_or_none()
    booking = await session.get(BookingRow, payment.booking_id) if payment else None
    if payment is None or booking is None:
        raise NotFoundError("Unknown checkout session.")
    return payment, booking


def _sandbox_page(title: str, body: str) -> HTMLResponse:
    return HTMLResponse(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
  body {{ font-family: system-ui, sans-serif; margin: 0; padding: 24px 16px;
         background: #f4f6f8; color: #14212b; }}
  .card {{ max-width: 420px; margin: 0 auto; background: #fff; border-radius: 12px;
          padding: 24px; box-shadow: 0 1px 3px rgba(0,0,0,.12); }}
  .tag {{ display: inline-block; font-size: 12px; font-weight: 600; letter-spacing: .04em;
         background: #fff3cd; color: #7a5b00; padding: 4px 8px; border-radius: 6px; }}
  .amount {{ font-size: 36px; font-weight: 700; margin: 16px 0 4px; }}
  .muted {{ color: #5b6b78; font-size: 14px; line-height: 1.5; }}
  button {{ width: 100%; padding: 14px; font-size: 16px; font-weight: 600; border: 0;
           border-radius: 8px; background: #0f766e; color: #fff; margin-top: 20px; }}
  a {{ display: block; text-align: center; margin-top: 14px; color: #5b6b78; }}
</style></head>
<body><div class="card">{body}</div></body></html>""")


@router.get("/sandbox/{checkout_session_id}", include_in_schema=False,
            name="sandbox_checkout_page")
async def sandbox_checkout_page(
    checkout_session_id: str, session: SessionDep, cancelled: bool = False
) -> HTMLResponse:
    payment, booking = await _sandbox_booking(session, checkout_session_id)
    ticket = html.escape(booking.ticket_number)
    tag = '<span class="tag">SANDBOX -- NO REAL MONEY</span>'
    if cancelled:
        return _sandbox_page("Payment cancelled", f"""{tag}
<h2>Payment cancelled</h2>
<p class="muted">Ticket {ticket} was not paid. The space is held until the
hold expires. Return to the SabayGo app.</p>""")
    if booking.status != BookingStatus.PENDING.value:
        return _sandbox_page("Not awaiting payment", f"""{tag}
<h2>Nothing to pay</h2>
<p class="muted">Ticket {ticket} is <b>{html.escape(booking.status)}</b>, not awaiting
payment. Return to the SabayGo app.</p>""")
    cs = html.escape(checkout_session_id)
    return _sandbox_page("SabayGo payment", f"""{tag}
<p class="muted" style="margin-top:16px">Ticket {ticket}</p>
<div class="amount">&#8369;{payment.amount:,.2f}</div>
<p class="muted">This page stands in for PayMongo during development. Paying
sends a signed webhook through the same check a real PayMongo payment
passes.</p>
<form method="post" action="{cs}/pay"><button type="submit">Pay &#8369;{payment.amount:,.2f}</button></form>
<a href="{cs}?cancelled=true">Cancel</a>""")


@router.post("/sandbox/{checkout_session_id}/pay", include_in_schema=False)
async def sandbox_pay(checkout_session_id: str, session: SessionDep) -> HTMLResponse:
    payment, booking = await _sandbox_booking(session, checkout_session_id)
    ticket = html.escape(booking.ticket_number)
    tag = '<span class="tag">SANDBOX -- NO REAL MONEY</span>'
    # Refused here rather than settled: a paid event for a hold that has
    # already expired would record money against a space given away.
    if booking.status != BookingStatus.PENDING.value:
        return _sandbox_page("Not awaiting payment", f"""{tag}
<h2>Nothing to pay</h2>
<p class="muted">Ticket {ticket} is <b>{html.escape(booking.status)}</b>.
Return to the SabayGo app.</p>""")

    raw, signature = SandboxCheckoutClient.signed_paid_event(
        checkout_session_id=checkout_session_id,
        booking_id=booking.booking_id,
        ticket_number=booking.ticket_number,
        amount=payment.amount,
    )
    outcome = await _receive_webhook(raw, signature, session)

    if outcome.get("status") == "confirmed":
        return _sandbox_page("Payment received", f"""{tag}
<h2>Payment received</h2>
<p class="muted">Ticket {ticket} is confirmed by the signed webhook. Return to
the SabayGo app -- it will show your boarding pass.</p>""")
    return _sandbox_page("Payment not confirmed", f"""{tag}
<h2>Payment not confirmed</h2>
<p class="muted">The webhook answered <b>{html.escape(str(outcome))}</b>.
Nothing was confirmed.</p>""")
