"""PayMongo client -- Checkout Sessions and webhook verification.

SANDBOX ONLY for this project. Live merchant accounts require KYC that
takes weeks; test keys give real GCash/Maya redirect flows and real
webhook deliveries, which is everything the capstone needs. State this
plainly in the Limitations section.

Flow:
    1. Passenger reserves    -> booking 'pending', seat 'held' (10 min TTL)
    2. create_checkout()     -> PayMongo returns a checkout_url
    3. Passenger pays in GCash/Maya via that URL
    4. PayMongo POSTs a webhook -> booking 'confirmed', seat 'booked'
    5. No webhook inside the TTL -> sweeper releases the seat

Step 4 is authoritative, NOT the client redirect. A client that "returns
successfully" proves nothing -- it can be replayed, faked, or simply lost
when the passenger closes the browser. Only the server-to-server webhook
confirms money moved.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import logging
from decimal import Decimal
from typing import Any

import httpx

from app.config import settings
from app.core.exceptions import UpstreamServiceError

log = logging.getLogger(__name__)

BASE_URL = "https://api.paymongo.com/v1"


class PayMongoClient:
    def __init__(self, secret_key: str | None = None):
        self.secret_key = secret_key or settings.paymongo_secret_key
        if not self.secret_key:
            log.warning("PAYMONGO_SECRET_KEY unset -- payment calls will fail.")

    def _auth_header(self) -> str:
        token = base64.b64encode(f"{self.secret_key}:".encode()).decode()
        return f"Basic {token}"

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
        """Create a Checkout Session. Returns {id, checkout_url}.

        PayMongo works in centavos, so a 500.00 fare is sent as 50000.
        Getting this wrong charges 100x or 1/100x, and the sandbox will
        happily accept either -- worth an assertion in your test script.
        """
        if not self.secret_key:
            raise UpstreamServiceError("Payment provider is not configured.")

        centavos = int((amount * 100).to_integral_value())

        payload = {
            "data": {
                "attributes": {
                    "line_items": [
                        {
                            "currency": "PHP",
                            "amount": centavos,
                            "name": description,
                            "quantity": 1,
                        }
                    ],
                    "payment_method_types": ["gcash", "paymaya", "card"],
                    "description": f"SabayGo ticket {ticket_number}",
                    "reference_number": ticket_number,
                    "success_url": success_url,
                    "cancel_url": cancel_url,
                    # Echoed back in the webhook -- this is how the handler
                    # knows which booking a payment belongs to without
                    # trusting anything the client sent.
                    "metadata": {
                        "booking_id": booking_id,
                        "ticket_number": ticket_number,
                    },
                }
            }
        }

        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                r = await client.post(
                    f"{BASE_URL}/checkout_sessions",
                    headers={
                        "Authorization": self._auth_header(),
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
        except httpx.RequestError as exc:
            log.error("PayMongo unreachable: %s", exc)
            raise UpstreamServiceError("Payment provider is unreachable.") from exc

        if r.status_code >= 400:
            log.error("PayMongo error %s: %s", r.status_code, r.text[:500])
            raise UpstreamServiceError(
                f"Payment provider rejected the request ({r.status_code})."
            )

        data = r.json()["data"]
        return {
            "checkout_session_id": data["id"],
            "checkout_url": data["attributes"]["checkout_url"],
        }

    # ------------------------------------------------------------------
    @staticmethod
    def verify_signature(
        *, raw_body: bytes, signature_header: str, webhook_secret: str
    ) -> bool:
        """Verify the Paymongo-Signature header.

        Header format:  t=<timestamp>,te=<test_sig>,li=<live_sig>
        Signed payload: "<timestamp>.<raw_body>"  HMAC-SHA256

        The RAW body matters. Re-serialising the parsed JSON changes key
        order and whitespace, and the signature will never match -- a
        classic and very time-consuming webhook bug.

        Without this check anyone who learns the endpoint URL can POST a
        fake "payment succeeded" and ride for free.
        """
        try:
            parts = dict(
                kv.split("=", 1) for kv in signature_header.split(",") if "=" in kv
            )
        except ValueError:
            return False

        timestamp = parts.get("t")
        # Test keys sign into `te`, live keys into `li`.
        provided = parts.get("te") or parts.get("li")
        if not timestamp or not provided:
            return False

        expected = hmac.new(
            webhook_secret.encode(),
            f"{timestamp}.{raw_body.decode()}".encode(),
            hashlib.sha256,
        ).hexdigest()

        # Constant-time compare: a plain == leaks information through
        # timing that lets an attacker recover the signature byte by byte.
        return hmac.compare_digest(expected, provided)
