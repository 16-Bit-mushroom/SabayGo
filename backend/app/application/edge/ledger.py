"""Which trip a door event belongs to (brief 4.2 rules 11 and 12).

The edge phone does not start or stop with the trip: it counts from its
setup check at check-out until it is returned, and every event carries
its `device_id`. The server finds the van the phone was checked out with
at the event's time, then that van's trip at that time:

  1. the started trip whose run covers the moment (started at or before
     it, not completed before it) -- the latest such, if two overlap;
  2. otherwise the trip the van is assigned to that had not yet started,
     the earliest -- started or not, so the boardings before Start are
     kept (rev 603, 4.2 rule 14; T2);
  3. otherwise none: the event is held outside the ledger, and moves the
     moment a trip of that van is assigned or started and claims it by
     the same rule.

By time, never by the trip that happens to be open when the upload
arrives: a phone that was offline for the whole trip uploads afterwards.

The phone counts from the van's assignment until it arrives, then
pauses until the next assignment (rule 13): it counts while rule 1 or 2
names a trip for now (`GET /edge/session`). The way back is the
operator's and is not counted.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import TripStatus
from app.infrastructure.models import (
    DeviceCheckout,
    HeldDoorEvent,
    Notification,
    PassengerEvent,
    Trip,
    TripLocationPing,
)

STARTED = (TripStatus.BOARDING.value, TripStatus.DEPARTED.value, TripStatus.COMPLETED.value)

# A trip that has not started is still live this long after its departure.
# Further back it did not run, or ran without the system; it neither
# claims door events nor is started by the fallback, and stays for the
# Terminal Manager. An assignment claims no further ahead either: a van
# is assigned at its turn, not for tomorrow.
TRIP_REACH = timedelta(hours=12)


async def van_at(session: AsyncSession, device_id: str, at: datetime) -> str | None:
    """The van this phone was checked out with at `at`, by its check-outs."""
    return (await session.execute(
        select(DeviceCheckout.van_id).where(
            DeviceCheckout.device_id == device_id,
            DeviceCheckout.checked_out_at <= at,
            or_(DeviceCheckout.returned_at.is_(None), DeviceCheckout.returned_at >= at),
        ).order_by(DeviceCheckout.checked_out_at.desc()).limit(1)
    )).scalar_one_or_none()


async def trip_for(session: AsyncSession, van_id: str, at: datetime) -> Trip | None:
    running = (await session.execute(
        select(Trip).where(
            Trip.van_id == van_id,
            Trip.status.in_(STARTED),
            Trip.started_at <= at,
            or_(Trip.completed_at.is_(None), Trip.completed_at >= at),
        ).order_by(Trip.started_at.desc()).limit(1)
    )).scalar_one_or_none()
    if running is not None:
        return running

    return (await session.execute(
        select(Trip).where(
            Trip.van_id == van_id,
            Trip.status != TripStatus.CANCELLED.value,
            Trip.departure_datetime <= at + TRIP_REACH,
            Trip.departure_datetime >= at - TRIP_REACH,
            or_(Trip.started_at.is_(None), Trip.started_at > at),
        ).order_by(Trip.departure_datetime).limit(1)
    )).scalar_one_or_none()


def to_ledger(held: HeldDoorEvent, trip_id: str, now: datetime) -> PassengerEvent:
    """The held event as a ledger row, keeping its event_id."""
    return PassengerEvent(
        event_id=held.event_id,
        trip_id=trip_id,
        device_id=held.device_id,
        event_type=held.event_type,
        event_at=held.event_at,
        latitude=held.latitude,
        longitude=held.longitude,
        occupancy_after=held.occupancy_after,
        track_id=held.track_id,
        snapshot_url=held.snapshot_url,
        snapshot_hash=held.snapshot_hash,
        created_at=now,
    )


async def release_held(session: AsyncSession, trip: Trip, now: datetime) -> int:
    """Move the van's held events that this trip now claims (rule 14).

    Called when a trip is assigned a van or starts, inside its
    transaction, after the change has been flushed so the claim rule
    sees it."""
    if trip.van_id is None:
        return 0
    held = (await session.execute(
        select(HeldDoorEvent).where(HeldDoorEvent.van_id == trip.van_id)
        .order_by(HeldDoorEvent.event_at)
    )).scalars().all()
    moved = 0
    for event in held:
        owner = await trip_for(session, trip.van_id, event.event_at)
        if owner is not None and owner.trip_id == trip.trip_id:
            session.add(to_ledger(event, trip.trip_id, now))
            await session.delete(event)
            moved += 1
    # The van's held GPS readings within reach go with it: the trip's
    # trail starts where the van left the terminal (025).
    await session.execute(
        update(TripLocationPing)
        .where(TripLocationPing.van_id == trip.van_id,
               TripLocationPing.trip_id.is_(None),
               TripLocationPing.recorded_at >= trip.departure_datetime - TRIP_REACH)
        .values(trip_id=trip.trip_id)
    )
    if moved:
        await session.flush()
    return moved


async def alerted_while_held(session: AsyncSession, van_id: str, title: str) -> bool:
    """Whether a 'Trip Not Started' with this title went out about the van
    since its oldest held event: each alert is raised once while the
    van's events wait, not on every upload."""
    oldest = (await session.execute(
        select(HeldDoorEvent.received_at).where(HeldDoorEvent.van_id == van_id)
        .order_by(HeldDoorEvent.received_at).limit(1)
    )).scalar_one_or_none()
    if oldest is None:
        return False
    return (await session.execute(
        select(Notification.notification_id).where(
            Notification.type == "trip_not_started",
            Notification.related_entity_id == van_id,
            Notification.title == title,
            Notification.created_at >= oldest,
        ).limit(1)
    )).first() is not None
