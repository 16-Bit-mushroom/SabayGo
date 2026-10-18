"""In-process periodic jobs.

Each job is one coroutine run on a fixed interval inside the API process:
the abandoned-hold sweep and the trip-start fallback today, the evidence
retention job later. Fine for a single deployment; with more than one
worker every worker would run every job, so a multi-instance setup would
want one worker holding a lock. Worth stating in Limitations.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable

log = logging.getLogger(__name__)


class PeriodicJob:
    def __init__(
        self, name: str, interval_seconds: int, tick: Callable[[], Awaitable[object]]
    ):
        self.name = name
        self.interval = interval_seconds
        self.tick = tick
        self._task: asyncio.Task | None = None

    async def _loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(self.interval)
                await self.tick()
            except asyncio.CancelledError:
                raise
            except Exception:
                # A failed tick must not kill the loop: the next one should
                # try again rather than wait for the next restart.
                log.exception("%s failed; continuing.", self.name)

    def start(self) -> None:
        self._task = asyncio.create_task(self._loop())
        log.info("%s started (every %ss).", self.name, self.interval)

    async def stop(self) -> None:
        if self._task is None:
            return
        self._task.cancel()
        try:
            await self._task
        except asyncio.CancelledError:
            pass
        log.info("%s stopped.", self.name)
