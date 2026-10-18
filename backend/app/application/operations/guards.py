"""Crew assignment guard and the abandoned-hold sweep."""

from __future__ import annotations

import logging

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.domain.enums import Role
from app.infrastructure.models import Trip, User

log = logging.getLogger(__name__)


async def assert_assigned_to_trip(
    session: AsyncSession, *, trip_id: str, user: User
) -> Trip:
    """A Dispatcher may only act on the trip they are assigned to.

    Without this, any Dispatcher could scan tickets or log cash passengers
    on any trip in the system -- which makes the
    remittance record meaningless, since the fares a person is accountable
    for would no longer correspond to the runs they actually worked.

    The Terminal Manager and system admins are exempt: someone has to be
    able to step in when a Dispatcher's phone dies mid-route.
    """
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")

    if user.role in (Role.TERMINAL_MANAGER.value, Role.ADMIN.value):
        return trip

    if user.user_id == trip.dispatcher_id:
        return trip

    # An unassigned trip is a roster gap, not an open invitation. Say so
    # plainly rather than returning a bare 403 the crew cannot act on.
    if trip.dispatcher_id is None:
        raise PermissionDeniedError(
            "No Dispatcher is assigned to this trip. Ask the office to assign one."
        )

    raise PermissionDeniedError(
        "You are not assigned to this trip. Ask the office if this is wrong."
    )


async def sweep_abandoned_holds(session_factory) -> None:
    """Return abandoned payment holds to the pool (a `PeriodicJob` tick).

    A passenger who starts paying and closes the app leaves their space
    held. `sweep_expired_holds()` releases it, but nothing was calling it --
    so the space only freed up when another booking happened to try that
    exact slot, and search showed it as unavailable in the meantime.
    """
    from app.infrastructure.repositories.seat_repository import SeatRepository

    async with session_factory() as session:
        released = await SeatRepository(session).sweep_expired_holds()
        if released:
            await session.commit()
            log.info("Released %d abandoned hold(s).", released)
