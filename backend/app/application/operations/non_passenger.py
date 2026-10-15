"""'Not a passenger trip' (rev 603, brief 4.2 rule 10, Table 40).

A van sometimes leaves for a reason that is not a passenger trip -- an
errand at the operator's home, fuel, a repair. Before leaving, the
Dispatcher presses 'Not a passenger trip' and picks a reason. While the
move is open nothing is started and nothing is owed, and the GPS
departure fallback does not start the van's trip (`TripLifecycle.
van_left_origin`).

The move ends when the Dispatcher turns it off, or when the van comes
back into a terminal zone after having left it. A passenger seen
boarding while it is open starts the trip 'auto_detected', pending
review; the door-event side of that arrives with the checking step (R5).

The move is the van's, found through the Dispatcher's open phone
check-out: a van with no phone out has no GPS fallback to hold off.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.operations.check_in import haversine_m
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import TripStatus
from app.infrastructure.models import (
    DeviceCheckout,
    NonPassengerMove,
    Terminal,
    Trip,
    TripLocationPing,
    User,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

REASONS = ("errand", "fuel_or_repair", "other")


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


class NonPassengerMoves:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def start(self, *, by: User, reason: str, note: str | None) -> NonPassengerMove:
        if reason not in REASONS:
            raise ConflictError(f"Pick a reason: {', '.join(REASONS)}.")
        note = (note or "").strip() or None
        if reason == "other" and note is None:
            raise ConflictError("Say what the move is for.")
        checkout = (await self.session.execute(
            select(DeviceCheckout).where(DeviceCheckout.dispatcher_id == by.user_id,
                                         DeviceCheckout.returned_at.is_(None))
        )).scalars().first()
        if checkout is None:
            raise ConflictError(
                "No phone is checked out with you, so no van is yours to mark. "
                "A van with no phone has no GPS departure to hold off."
            )
        if await self.open_for(checkout.van_id) is not None:
            raise ConflictError("This van already has an open 'Not a passenger trip'.")
        assigned = (await self.session.execute(
            select(Trip.trip_id).where(
                Trip.van_id == checkout.van_id,
                Trip.status == TripStatus.SCHEDULED.value,
            ).order_by(Trip.departure_datetime).limit(1)
        )).scalar_one_or_none()
        move = NonPassengerMove(
            move_id=str(uuid.uuid4()), van_id=checkout.van_id,
            device_id=checkout.device_id, dispatcher_id=by.user_id,
            trip_id=assigned, reason=reason, reason_note=note, started_at=_now(),
        )
        self.session.add(move)
        await self.session.commit()
        return move

    async def end(self, move_id: str, *, by: User) -> NonPassengerMove:
        move = await self.session.get(NonPassengerMove, move_id)
        if move is None:
            raise NotFoundError("Move not found.")
        if move.dispatcher_id != by.user_id:
            raise ConflictError("Only the Dispatcher who pressed it turns it off.")
        if move.ended_at is not None:
            raise ConflictError("This move has already ended.")
        move.ended_at = _now()
        await self.session.commit()
        return move

    async def open_for(self, van_id: str) -> NonPassengerMove | None:
        return (await self.session.execute(
            select(NonPassengerMove).where(NonPassengerMove.van_id == van_id,
                                           NonPassengerMove.ended_at.is_(None))
        )).scalar_one_or_none()

    async def on_reading(self, van_id: str, latitude: float, longitude: float,
                         at: datetime) -> None:
        """A GPS reading of the van: back inside a terminal zone after
        having left it ends the open move. The caller commits."""
        move = await self.open_for(van_id)
        if move is None:
            return
        radius = await PolicyRepository(self.session).get_optional_int("depart_zone_radius_m")
        if radius is None:
            return
        zones = [(float(t.latitude), float(t.longitude)) for t in (await self.session.execute(
            select(Terminal).where(Terminal.is_active.is_(True))
        )).scalars()]

        def inside(lat: float, lon: float) -> bool:
            return any(haversine_m(lat, lon, z_lat, z_lon) <= radius for z_lat, z_lon in zones)

        if not inside(latitude, longitude):
            return
        since = (await self.session.execute(
            select(TripLocationPing.latitude, TripLocationPing.longitude).where(
                TripLocationPing.van_id == van_id,
                TripLocationPing.recorded_at >= move.started_at,
                TripLocationPing.recorded_at < at,
            )
        )).all()
        if any(not inside(float(lat), float(lon)) for lat, lon in since):
            move.ended_at = at
