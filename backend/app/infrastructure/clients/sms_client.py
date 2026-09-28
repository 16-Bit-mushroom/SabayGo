"""Outbound SMS for SOS emergency alerts (spec 2.3.5).

Two providers, one interface, and one rule they share with the YOLOv8
node: **never report a delivery that did not happen.** Every method here
returns an SmsResult per recipient -- 'sent', 'failed' or 'skipped' -- and
none of them raises. A dead gateway must not take down the endpoint that
is recording someone's emergency.

  android_gateway   A spare Android handset on the cooperative's own SIM
                    running an SMS-gateway app (capcom6/android-sms-gateway
                    and its kin: Apache-2.0, plain HTTP + basic auth).
                    No vendor account and no per-message charge beyond the
                    unli-text plan the cooperative already pays for. This
                    is the option A2Z can actually afford to leave running.

  twilio            The vendor the manuscript names. Paid per segment, and
                    a trial account only reaches numbers verified in the
                    console -- fine for a defence demo, not for a fleet.

Both are one authenticated POST, which is why supporting both costs about
thirty lines rather than an abstraction layer.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from app.config import settings

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class SmsResult:
    recipient: str
    provider: str
    status: str  # sent | failed | skipped
    message_id: str | None = None
    error: str | None = None


class SmsClient:
    """Sends one message to each recipient, one request per number.

    Per-number requests rather than one bulk call: the dispatch log records
    one row per recipient, and a bulk call that half-succeeds cannot say
    which half.
    """

    def __init__(self, provider: str | None = None):
        self.provider = provider or settings.sms_provider

    async def send_many(self, recipients: list[str], body: str) -> list[SmsResult]:
        if not recipients:
            return []
        if self.provider == "disabled":
            return [
                SmsResult(r, "disabled", "skipped", error="No SMS provider configured.")
                for r in recipients
            ]

        missing = self._missing_credentials()
        if missing:
            # Misconfiguration is reported as a skip with its reason, not
            # as a send. The console shows the reason next to the alert.
            log.error("SOS SMS not attempted: %s", missing)
            return [
                SmsResult(r, self.provider, "skipped", error=missing[:255])
                for r in recipients
            ]

        async with httpx.AsyncClient(timeout=settings.sms_timeout_s) as client:
            return [await self._send_one(client, r, body) for r in recipients]

    # ------------------------------------------------------------------
    def _missing_credentials(self) -> str | None:
        if self.provider == "android_gateway":
            if not settings.sms_gateway_url:
                return "sms_gateway_url is not set."
        elif self.provider == "twilio":
            if not (settings.twilio_account_sid and settings.twilio_auth_token):
                return "Twilio credentials are not set."
            if not settings.twilio_from_number:
                return "twilio_from_number is not set."
        return None

    async def _send_one(
        self, client: httpx.AsyncClient, recipient: str, body: str
    ) -> SmsResult:
        try:
            if self.provider == "android_gateway":
                return await self._send_android_gateway(client, recipient, body)
            return await self._send_twilio(client, recipient, body)
        except httpx.HTTPError as exc:
            log.error("SOS SMS to %s failed: %s", recipient, exc)
            return SmsResult(
                recipient, self.provider, "failed", error=f"{type(exc).__name__}: {exc}"[:255]
            )

    async def _send_android_gateway(
        self, client: httpx.AsyncClient, recipient: str, body: str
    ) -> SmsResult:
        auth = None
        if settings.sms_gateway_username:
            auth = (settings.sms_gateway_username, settings.sms_gateway_password or "")
        resp = await client.post(
            f"{settings.sms_gateway_url.rstrip('/')}/message",
            json={"message": body, "phoneNumbers": [recipient]},
            auth=auth,
        )
        if resp.status_code >= 400:
            return SmsResult(
                recipient, self.provider, "failed",
                error=f"HTTP {resp.status_code}: {resp.text[:180]}",
            )
        payload = resp.json() if resp.content else {}
        return SmsResult(
            recipient, self.provider, "sent",
            message_id=str(payload.get("id")) if payload.get("id") else None,
        )

    async def _send_twilio(
        self, client: httpx.AsyncClient, recipient: str, body: str
    ) -> SmsResult:
        resp = await client.post(
            f"https://api.twilio.com/2010-04-01/Accounts/"
            f"{settings.twilio_account_sid}/Messages.json",
            data={
                "To": recipient,
                "From": settings.twilio_from_number,
                "Body": body,
            },
            auth=(settings.twilio_account_sid, settings.twilio_auth_token),
        )
        payload = resp.json() if resp.content else {}
        if resp.status_code >= 400:
            # Twilio puts the useful part in `message` (e.g. "The number
            # +63... is unverified. Trial accounts may only send to
            # verified numbers.") -- surface it verbatim.
            return SmsResult(
                recipient, self.provider, "failed",
                error=str(payload.get("message") or f"HTTP {resp.status_code}")[:255],
            )
        return SmsResult(
            recipient, self.provider, "sent", message_id=payload.get("sid")
        )
