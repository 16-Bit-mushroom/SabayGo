"""The hash chain over a trip's door events (rev 603, change brief 6.2
phase 4, 4.5; T36, T39).

Each event, as it enters the ledger, is given the next `chain_seq` of its
trip and

    event_hash = SHA-256(trip | seq | event_id | device | type | time |
                         latitude | longitude | occupancy | track |
                         snapshot_hash | previous event_hash)

with the first event's previous hash the trip's genesis, SHA-256 of
"sabaygo:" + trip_id (the brief's advice; decided 15 Oct). A later
change to any hashed field, or a removed or reordered event, breaks
every hash after it (`verify`).

Only what the phone sent is hashed. The server's own readings of an
event -- matched or unlisted, its resolution, its place on the route --
change as the list and the GPS readings change, and are not. The blurred
still is in through its SHA-256, which the phone declares with the event
(the upload must match it), so the chain still verifies after the
retention rule deletes the image (T39).

Order is the order events entered the ledger, not their time: a phone
that was offline appends its events late, after the ones already
chained. The trip's row is locked while its events are appended.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.infrastructure.models import PassengerEvent, Trip


def genesis(trip_id: str) -> str:
    return hashlib.sha256(f"sabaygo:{trip_id}".encode()).hexdigest()


def event_hash(e: PassengerEvent, previous: str) -> str:
    fields = [
        e.trip_id, str(e.chain_seq), e.event_id, e.device_id, e.event_type,
        _time(e.event_at), _place(e.latitude), _place(e.longitude),
        _int(e.occupancy_after), _int(e.track_id), e.snapshot_hash or "", previous,
    ]
    return hashlib.sha256("|".join(fields).encode()).hexdigest()


async def append(session: AsyncSession, events: list[PassengerEvent]) -> None:
    """Chain events that have just entered the ledger, per trip, in time
    order within the batch. The caller commits."""
    by_trip: dict[str, list[PassengerEvent]] = {}
    for e in events:
        by_trip.setdefault(e.trip_id, []).append(e)
    for trip_id, new in by_trip.items():
        await session.execute(select(Trip.trip_id).where(Trip.trip_id == trip_id).with_for_update())
        last = (await session.execute(
            select(PassengerEvent.chain_seq, PassengerEvent.event_hash)
            .where(PassengerEvent.trip_id == trip_id, PassengerEvent.chain_seq.is_not(None))
            .order_by(PassengerEvent.chain_seq.desc()).limit(1)
        )).first()
        seq, previous = (last[0], last[1]) if last else (0, genesis(trip_id))
        for e in sorted(new, key=lambda e: e.event_at):
            seq += 1
            e.chain_seq = seq
            e.event_hash = event_hash(e, previous)
            previous = e.event_hash
    await session.flush()


@dataclass(frozen=True)
class ChainCheck:
    events: int
    verified: bool
    broken_at: int | None     # the first chain_seq whose hash does not hold
    unchained: int            # events from before the chain existed


async def verify(session: AsyncSession, trip_id: str) -> ChainCheck:
    rows = (await session.execute(
        select(PassengerEvent).where(PassengerEvent.trip_id == trip_id)
        .order_by(PassengerEvent.chain_seq)
    )).scalars().all()
    chained = [e for e in rows if e.chain_seq is not None]
    previous = genesis(trip_id)
    for expected, e in enumerate(chained, start=1):
        if e.chain_seq != expected or event_hash(e, previous) != e.event_hash:
            return ChainCheck(len(chained), False, expected, len(rows) - len(chained))
        previous = e.event_hash
    return ChainCheck(len(chained), True, None, len(rows) - len(chained))


def _time(at: datetime) -> str:
    return at.replace(tzinfo=None).isoformat(timespec="microseconds")


def _place(value: Decimal | float | None) -> str:
    return "" if value is None else format(Decimal(str(value)), ".6f")


def _int(value: int | None) -> str:
    return "" if value is None else str(value)
