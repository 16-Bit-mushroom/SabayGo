"""Single-slot pending request for the phone-as-camera PoC.

The Orange Pi answers /api/audit/capture directly because it can accept
an inbound call -- it is always-on hardware sitting on the van's network.
A phone cannot accept an inbound call the same way, so the direction
flips: the phone polls for a pending request instead of being pushed one.

In-memory, not persisted. This stand-in retires once the Pi is in hand,
so it is not worth a migration or surviving a restart; one slot is enough
for one demo phone. Process-local only -- do not run the backend with
more than one worker while this is in use.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime

from app.core import timezone as app_tz


@dataclass(frozen=True)
class PendingPhoneCapture:
    trip_id: str
    leg_sequence: int
    requested_by_user_id: str
    requested_at: datetime


_lock = asyncio.Lock()
_pending: PendingPhoneCapture | None = None


async def set_pending(
    *, trip_id: str, leg_sequence: int, requested_by_user_id: str
) -> PendingPhoneCapture:
    """A new trigger overwrites any request the phone hasn't fulfilled yet."""
    global _pending
    req = PendingPhoneCapture(
        trip_id=trip_id,
        leg_sequence=leg_sequence,
        requested_by_user_id=requested_by_user_id,
        requested_at=app_tz.now(),
    )
    async with _lock:
        _pending = req
    return req


async def peek_pending() -> PendingPhoneCapture | None:
    async with _lock:
        return _pending


async def consume_pending() -> PendingPhoneCapture | None:
    """Fulfilling a request clears the slot so it can't be double-spent."""
    global _pending
    async with _lock:
        req, _pending = _pending, None
        return req
