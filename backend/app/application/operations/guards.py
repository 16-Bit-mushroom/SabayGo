"""Crew assignment guard and the abandoned-hold sweeper."""

from __future__ import annotations

import asyncio
import logging

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.domain.enums import Role
from app.infrastructure.models import Trip, User

log = logging.getLogger(__name__)


async def assert_assigned_to_trip(
    session: AsyncSession, *, trip_id: str, user: User
) -> Trip:
    """A conductor or driver may only act on the trip they are rostered to.

    Without this, any conductor could scan tickets, log cash passengers, or
    confirm a headcount on any trip in the system -- which makes the
    remittance record meaningless, since the fares a person is accountable
    for would no longer correspond to the runs they actually worked.

    Operators and admins are exempt: someone has to be able to step in when
    a conductor's phone dies mid-route.
    """
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")

    if user.role in (Role.OPERATOR.value, Role.ADMIN.value):
        return trip

    if user.user_id in (trip.conductor_id, trip.driver_id):
        return trip

    # An unassigned trip is a roster gap, not an open invitation. Say so
    # plainly rather than returning a bare 403 the crew cannot act on.
    if trip.conductor_id is None and trip.driver_id is None:
        raise PermissionDeniedError(
            "No crew is assigned to this trip. Ask the office to assign it."
        )

    raise PermissionDeniedError(
        "You are not assigned to this trip. Ask the office if this is wrong."
    )


class HoldSweeper:
    """Returns abandoned payment holds to the pool on a timer.

    A passenger who starts paying and closes the app leaves their space
    held. `sweep_expired_holds()` releases it, but nothing was calling it --
    so the space only freed up when another booking happened to try that
    exact slot, and search showed it as unavailable in the meantime.

    Runs in-process. Fine for a single deployment; a multi-instance setup
    would want one worker holding a lock so the sweep does not run N times
    concurrently. Worth stating in Limitations.
    """

    def __init__(self, session_factory, interval_seconds: int = 60):
        self.session_factory = session_factory
        self.interval = interval_seconds
        self._task: asyncio.Task | None = None

    async def _loop(self) -> None:
        from app.infrastructure.repositories.seat_repository import SeatRepository

        while True:
            try:
                await asyncio.sleep(self.interval)
                async with self.session_factory() as session:
                    released = await SeatRepository(session).sweep_expired_holds()
                    if released:
                        await session.commit()
                        log.info("Released %d abandoned hold(s).", released)
            except asyncio.CancelledError:
                raise
            except Exception:
                # A failed sweep must not kill the loop -- the next tick
                # should try again rather than leaving holds stranded until
                # the next restart.
                log.exception("Hold sweep failed; continuing.")

    def start(self) -> None:
        self._task = asyncio.create_task(self._loop())
        log.info("Hold sweeper started (every %ss).", self.interval)

    async def stop(self) -> None:
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        log.info("Hold sweeper stopped.")
