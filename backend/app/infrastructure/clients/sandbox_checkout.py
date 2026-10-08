"""Development stand-in for PayMongo Checkout.

A demo cannot rely on PayMongo. Its test keys need an account, and its
webhook needs a public URL a school LAN does not have -- so a booking sat
in `pending` until the hold expired, and the passenger loop could never
finish.

This replaces PayMongo's half of the flow WITHOUT replacing the rule the
flow exists for: only a verified webhook confirms a booking. The sandbox
page is the stand-in for PayMongo's servers. Pressing Pay builds a
PayMongo-shaped event, signs it with PAYMONGO_WEBHOOK_SECRET exactly as
PayMongo does -- HMAC-SHA256 over "{timestamp}.{raw_body}" -- and hands it
to the same verification and settlement path as /payments/webhook. Nothing
about a booking is confirmed by the page itself.

Active only when ENVIRONMENT=development AND no PAYMONGO_SECRET_KEY is
set. Production never reaches it, and configuring real PayMongo keys
switches it off. Its references are prefixed `cs_sandbox_` / `evt_sandbox_`
so a sandbox payment can never be mistaken for a real one in the data.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
import uuid
from decimal import Decimal
from typing import Any, Callable

from app.config import settings
from app.core.exceptions import UpstreamServiceError
from app.infrastructure.clients.paymongo_client import PayMongoClient

REF_PREFIX = "cs_sandbox_"


def sandbox_enabled() -> bool:
    return settings.environment == "development" and not settings.paymongo_secret_key


def checkout_client(page_url: Callable[[str], str]) -> PayMongoClient | SandboxCheckoutClient:
    """The checkout provider for this deployment. `page_url` maps a
    checkout session id to the sandbox page's absolute URL; only the
    sandbox uses it."""
    return SandboxCheckoutClient(page_url) if sandbox_enabled() else PayMongoClient()


class SandboxCheckoutClient:
    def __init__(self, page_url: Callable[[str], str]):
        self._page_url = page_url

    async def create_checkout(
        self,
        *,
        booking_id: str,
        ticket_number: str,
        amount: Decimal,
        description: str,
        success_url: str,
        cancel_url: str,
    ) -> dict[str, Any]:
        """Same shape PayMongoClient.create_checkout returns."""
        if not settings.paymongo_webhook_secret:
            # Without the secret the event cannot be signed, and an unsigned
            # event is exactly what the webhook is built to refuse.
            raise UpstreamServiceError(
                "Sandbox payments need PAYMONGO_WEBHOOK_SECRET set in backend/.env."
            )
        checkout_session_id = f"{REF_PREFIX}{uuid.uuid4().hex[:24]}"
        return {
            "checkout_session_id": checkout_session_id,
            "checkout_url": self._page_url(checkout_session_id),
        }

    @staticmethod
    def signed_paid_event(
        *, checkout_session_id: str, booking_id: str, ticket_number: str, amount: Decimal
    ) -> tuple[bytes, str]:
        """A `checkout_session.payment.paid` event and its Paymongo-Signature
        header, built the way PayMongo builds them. No payment method is
        claimed: recording a sandbox payment as GCash would put a fake GCash
        payment into the revenue figures."""
        event = {
            "data": {
                "id": f"evt_sandbox_{uuid.uuid4().hex[:24]}",
                "type": "event",
                "attributes": {
                    "type": "checkout_session.payment.paid",
                    "livemode": False,
                    "data": {
                        "id": checkout_session_id,
                        "type": "checkout_session",
                        "attributes": {
                            "reference_number": ticket_number,
                            "amount": int((amount * 100).to_integral_value()),
                            "metadata": {
                                "booking_id": booking_id,
                                "ticket_number": ticket_number,
                            },
                        },
                    },
                },
            }
        }
        raw = json.dumps(event).encode()
        timestamp = str(int(time.time()))
        signature = hmac.new(
            settings.paymongo_webhook_secret.encode(),
            f"{timestamp}.{raw.decode()}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return raw, f"t={timestamp},te={signature}"
