"""Crew assignment guard: a Dispatcher acts on their own trip only."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.domain.enums import Role
from app.infrastructure.models import Trip, User


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
