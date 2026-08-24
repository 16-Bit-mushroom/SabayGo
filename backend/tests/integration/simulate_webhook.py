#!/usr/bin/env python3
"""PayMongo webhook simulator.

Builds a realistic PayMongo event, signs it with YOUR OWN
PAYMONGO_WEBHOOK_SECRET using the exact HMAC-SHA256 scheme PayMongo uses,
and POSTs it to the local webhook endpoint.

This is not a mock of your own code -- the request goes over real HTTP and
the server verifies the signature for real. Only the sender is simulated.

Worth keeping even after the PayMongo account clears:
  * it triggers failure cases the sandbox cannot produce on demand
    (duplicate delivery, tampered signature, unknown booking, payment
    failed), and those are the paths most likely to be quietly broken
  * the defense demo stops depending on ngrok and PayMongo uptime

Usage:
    python tests/integration/simulate_webhook.py --booking-id <uuid>
    python tests/integration/simulate_webhook.py --booking-id <uuid> --scenario duplicate
    python tests/integration/simulate_webhook.py --booking-id <uuid> --scenario tampered
    python tests/integration/simulate_webhook.py --booking-id <uuid> --scenario failed
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import uuid
from pathlib import Path

import httpx

WEBHOOK_URL = "http://127.0.0.1:8000/api/v1/payments/webhook"


def load_secret() -> str:
    """Read PAYMONGO_WEBHOOK_SECRET from backend/.env."""
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("PAYMONGO_WEBHOOK_SECRET="):
                value = line.split("=", 1)[1].strip()
                if value:
                    return value
    secret = os.getenv("PAYMONGO_WEBHOOK_SECRET", "")
    if not secret:
        sys.exit(
            "PAYMONGO_WEBHOOK_SECRET is not set in backend/.env.\n"
            "For local testing any value works -- it only has to match what\n"
            "the server reads. Add a line like:\n\n"
            "  PAYMONGO_WEBHOOK_SECRET=whsk_local_testing_secret\n\n"
            "then restart uvicorn (settings are read once at import)."
        )
    return secret


def build_event(booking_id: str, ticket_number: str, amount_centavos: int,
                paid: bool, event_id: str | None = None) -> dict:
    """Mirror the shape of a real checkout_session.payment.paid event.

    The nesting is deep and easy to get wrong -- data.attributes.data
    .attributes is not a typo. SettlePaymentUseCase reads metadata from
    that inner attributes object.
    """
    return {
        "data": {
            "id": event_id or f"evt_{uuid.uuid4().hex[:20]}",
            "type": "event",
            "attributes": {
                "type": "payment.paid" if paid else "payment.failed",
                "livemode": False,
                "created_at": int(time.time()),
                "data": {
                    "id": f"pay_{uuid.uuid4().hex[:20]}",
                    "type": "payment",
                    "attributes": {
                        "amount": amount_centavos,
                        "currency": "PHP",
                        "status": "paid" if paid else "failed",
                        "source": {"type": "gcash"},
                        "payment_method_used": "gcash",
                        "metadata": {
                            "booking_id": booking_id,
                            "ticket_number": ticket_number,
                        },
                    },
                },
            },
        }
    }


def sign(raw: bytes, secret: str, timestamp: int) -> str:
    """Produce a Paymongo-Signature header.

    Signed payload is "<timestamp>.<raw body>". The RAW bytes matter --
    re-serialising the parsed JSON changes key order and whitespace and
    the signature will never match.

    Test-mode events sign into `te`; live-mode into `li`.
    """
    signature = hmac.new(
        secret.encode(), f"{timestamp}.{raw.decode()}".encode(), hashlib.sha256
    ).hexdigest()
    return f"t={timestamp},te={signature},li="


def post(raw: bytes, header: str) -> httpx.Response:
    return httpx.post(
        WEBHOOK_URL,
        content=raw,
        headers={"Content-Type": "application/json", "Paymongo-Signature": header},
        timeout=15.0,
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--booking-id", required=True)
    ap.add_argument("--ticket-number", default="SBG-SIMULATED")
    ap.add_argument("--amount", type=float, default=500.00,
                    help="Peso amount; converted to centavos like PayMongo does")
    ap.add_argument(
        "--scenario",
        default="paid",
        choices=["paid", "duplicate", "tampered", "failed", "unknown-booking"],
    )
    args = ap.parse_args()

    secret = load_secret()
    centavos = int(round(args.amount * 100))

    booking_id = (
        "00000000-0000-0000-0000-000000000000"
        if args.scenario == "unknown-booking"
        else args.booking_id
    )

    event = build_event(
        booking_id, args.ticket_number, centavos, paid=(args.scenario != "failed")
    )
    raw = json.dumps(event).encode()
    timestamp = int(time.time())
    header = sign(raw, secret, timestamp)

    if args.scenario == "tampered":
        # Valid signature, then the body is altered -- exactly what an
        # attacker replaying a captured webhook would produce.
        event["data"]["attributes"]["data"]["attributes"]["amount"] = 1
        raw = json.dumps(event).encode()

    print(f"scenario   : {args.scenario}")
    print(f"event id   : {event['data']['id']}")
    print(f"booking    : {booking_id}")
    print(f"amount     : {centavos} centavos (P{args.amount:.2f})")
    print(f"POST       : {WEBHOOK_URL}\n")

    r = post(raw, header)
    print(f"-> {r.status_code}  {r.text}")

    if args.scenario == "duplicate":
        print("\nresending the identical event...")
        r2 = post(raw, header)
        print(f"-> {r2.status_code}  {r2.text}")
        if '"duplicate"' in r2.text:
            print("\nPASS: replay was detected and ignored.")
        else:
            print("\nFAIL: replay was processed twice. Check the "
                  "provider_event_id UNIQUE constraint.")

    expectations = {
        "paid": 'expect {"status":"confirmed"} and the seat to become booked',
        "tampered": 'expect {"status":"rejected","reason":"invalid signature"}',
        "failed": 'expect {"status":"failed"} and the hold left to expire',
        "unknown-booking": 'expect {"status":"ignored"}',
    }
    if args.scenario in expectations:
        print(f"\n{expectations[args.scenario]}")


if __name__ == "__main__":
    main()
