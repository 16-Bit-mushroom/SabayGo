"""Evidence retention: blurred stills, GPS readings and chat images.

Rev 603, change brief 4.5 (tests T36-T41). One fixed period,
`retention_days` (30, assumed), covers the blurred stills of door events
and the raw GPS readings, measured from the event's or the reading's own
time. Chat images (a home pickup's payment screenshot) have their own,
fixed on the message as `retain_until` when it is sent, and go on that
day.

Kept past the period, until a person has looked:
  - a still whose boarding is unlisted and unresolved (`pending`, T37);
  - every still and reading of a trip with an open dispute (T40);
  - the readings of a trip with a driving flag not yet reviewed, since
    they are its evidence.
Deleting a still deletes the file and its URL, stamps
`snapshot_deleted_at` and keeps `snapshot_hash`, so the trip's hash chain
still verifies without the image (T36, T39). A held door event's still
goes the same way: the ledger claims held events within 12 h, so one
past the period is never claimed. A reading is deleted outright; the
driving flags computed from it stay. A chat image's message stays, with
no attachment.

A file is deleted before its row is changed: a failed commit leaves a
URL to a missing file, which the next run clears, never a file nobody
points to. Each run logs what it deleted. It runs as a `PeriodicJob`.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from sqlalchemy import delete, exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.messaging.service import STORAGE_DIR
from app.core import timezone as app_tz
from app.infrastructure.models import (
    Dispute,
    DrivingEvent,
    HeldDoorEvent,
    Message,
    PassengerEvent,
    TripLocationPing,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


@dataclass(frozen=True)
class Purged:
    stills: int
    readings: int
    chat_images: int


async def cutoff(session: AsyncSession, now: datetime | None = None) -> datetime:
    """Evidence from before this moment is past the retention period."""
    days = await PolicyRepository(session).get_int("retention_days")
    return (now or _now()) - timedelta(days=days)


def _unlink(url: str | None) -> None:
    if url:
        Path(STORAGE_DIR / url).unlink(missing_ok=True)


class Retention:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def run(self, now: datetime | None = None) -> Purged:
        now = now or _now()
        before = await cutoff(self.session, now)
        stills = await self._stills(before, now)
        readings = await self._readings(before)
        images = await self._chat_images(now)
        await self.session.commit()
        if stills or readings or images:
            log.info("Retention: deleted %d stills, %d GPS readings and %d chat images "
                     "from before %s.", stills, readings, images, f"{before:%Y-%m-%d %H:%M}")
        return Purged(stills, readings, images)

    async def _stills(self, before: datetime, now: datetime) -> int:
        disputed = exists().where(Dispute.trip_id == PassengerEvent.trip_id,
                                  Dispute.status == "open")
        events = (await self.session.execute(
            select(PassengerEvent).where(
                PassengerEvent.snapshot_url.is_not(None),
                PassengerEvent.event_at < before,
                PassengerEvent.resolution_status != "pending",
                ~disputed,
            )
        )).scalars().all()
        for event in events:
            _unlink(event.snapshot_url)
            event.snapshot_url = None
            event.snapshot_deleted_at = now
        held = (await self.session.execute(
            select(HeldDoorEvent).where(HeldDoorEvent.snapshot_url.is_not(None),
                                        HeldDoorEvent.event_at < before)
        )).scalars().all()
        for event in held:
            _unlink(event.snapshot_url)
            event.snapshot_url = None
        return len(events) + len(held)

    async def _readings(self, before: datetime) -> int:
        kept = or_(
            exists().where(Dispute.trip_id == TripLocationPing.trip_id,
                           Dispute.status == "open").correlate(TripLocationPing),
            exists().where(DrivingEvent.trip_id == TripLocationPing.trip_id,
                           DrivingEvent.review_status == "open").correlate(TripLocationPing),
        )
        result = await self.session.execute(
            delete(TripLocationPing)
            .where(TripLocationPing.recorded_at < before, ~kept)
            .execution_options(synchronize_session=False)
        )
        return result.rowcount or 0

    async def _chat_images(self, now: datetime) -> int:
        messages = (await self.session.execute(
            select(Message).where(Message.attachment_url.is_not(None),
                                  Message.retain_until <= now.date())
        )).scalars().all()
        for msg in messages:
            _unlink(msg.attachment_url)
            msg.attachment_url = None
        return len(messages)


async def purge_expired_evidence(session_factory) -> Purged:
    """One run of the retention job (a `PeriodicJob` tick)."""
    async with session_factory() as session:
        return await Retention(session).run()
