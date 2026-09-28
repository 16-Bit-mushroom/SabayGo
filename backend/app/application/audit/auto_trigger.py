"""Event-driven cabin capture -- the automatic half of 2.3.5.

    "an in-van IoT camera captures cabin snapshots triggered by door
     closures or specific GPS nodes to initiate physical audits"

Until now every capture began with a person: the conductor tapping the
manifest, the office tapping the queue, or the demo phone being polled.
That is the weakest possible form of a leakage check, because the party it
audits chooses when it happens. The two triggers here do not ask anyone.

    door_close  the conductor closes boarding and the trip departs, so the
                cabin for leg 1 is final -- no-shows released, everyone
                who boarded aboard. See DepartTripUseCase.

    gps_node    a position report shows the van has pulled out of a route
                node's geofence, so the cabin for the leg it just entered
                is final. See TrackingService.record_ping.

Both fire *after* leaving a stop rather than on arrival, because that is
when the count is meaningful: an undocumented passenger boards at a
terminal, and leg k is exactly the stretch they are now riding.

Three rules this module exists to keep:

**One automatic audit per leg, counted over automatic rows only.** A
conductor's manual spot check must not satisfy the quota -- otherwise the
systematic check is disabled by pre-empting it, which is precisely the
behaviour it is meant to catch. A repeated GPS ping outside the fence must
not fire a second time either.

**The operation never waits on the camera, and never fails with it.** A
capture is seconds of shutter plus inference. A departure that blocked on
it would stall the crew at the door, and a GPS ping that rejected on it
would put a hole in the track. So the work is detached and every failure
is logged, not raised. Same rule as the SOS dispatcher: a dead device
loses the audit, never the operation.

**Nothing is fabricated.** A failed capture writes no row at all -- not a
zero, not a placeholder. TriggerAuditUseCase.execute() raises before it
reaches the insert, which is the behaviour being relied on here.

In-process, like HoldSweeper and the phone capture slot: one backend
worker. With two workers the durable per-leg check still holds (it is a
SELECT against yolov8_audit_logs), but the in-flight guard would not, so
a simultaneous double-fire could produce two rows for one leg. Stated in
Limitations alongside the other single-process assumptions.
"""

from __future__ import annotations

import asyncio
import logging

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.audit.trigger_audit import AuditResult, TriggerAuditUseCase
from app.core.db import SessionFactory
from app.core.exceptions import DomainError, UpstreamServiceError
from app.domain.enums import AuditTrigger
from app.infrastructure.models import Yolov8AuditLog

log = logging.getLogger(__name__)

# Legs with a capture already running, so two events in the same instant
# cannot both pass the database check before either has written a row.
_in_flight: set[tuple[str, int]] = set()
# Strong references to detached tasks. asyncio only holds a weak one, so
# without this the garbage collector may cancel a capture mid-inference.
_tasks: set[asyncio.Task] = set()


async def already_audited(
    session: AsyncSession, *, trip_id: str, leg_sequence: int
) -> bool:
    """Has an automatic capture already covered this leg?

    Manual rows are excluded deliberately -- see the module docstring.
    """
    result = await session.execute(
        select(func.count())
        .select_from(Yolov8AuditLog)
        .where(
            Yolov8AuditLog.trip_id == trip_id,
            Yolov8AuditLog.leg_sequence == leg_sequence,
            Yolov8AuditLog.trigger_type != AuditTrigger.MANUAL.value,
        )
    )
    return result.scalar_one() > 0


async def fire(
    session: AsyncSession,
    *,
    trip_id: str,
    leg_sequence: int,
    trigger: AuditTrigger,
) -> AuditResult | None:
    """Capture and reconcile this leg unless it is already covered.

    Returns None when suppressed. Raises on a capture failure, which the
    detached runner turns into a log line -- callers that await this
    directly (the tests) want to see the failure.
    """
    if not trigger.is_automatic:
        raise ValueError(f"{trigger.value} is not an automatic trigger.")
    if await already_audited(session, trip_id=trip_id, leg_sequence=leg_sequence):
        log.debug(
            "Skipping %s audit: trip=%s leg=%s already covered automatically.",
            trigger.value, trip_id, leg_sequence,
        )
        return None

    return await TriggerAuditUseCase(session).execute(
        trip_id=trip_id,
        leg_sequence=leg_sequence,
        # NULL is the record that no person asked for this -- migration
        # 006 nulls the column for exactly this case.
        triggered_by_user_id=None,
        trigger_type=trigger.value,
    )


def schedule(*, trip_id: str, leg_sequence: int, trigger: AuditTrigger) -> None:
    """Fire the capture out of band. Returns immediately; never raises."""
    key = (trip_id, leg_sequence)
    if key in _in_flight:
        return
    _in_flight.add(key)
    task = asyncio.create_task(_run(key, trigger))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def _run(key: tuple[str, int], trigger: AuditTrigger) -> None:
    trip_id, leg_sequence = key
    try:
        async with SessionFactory() as session:
            result = await fire(
                session, trip_id=trip_id, leg_sequence=leg_sequence, trigger=trigger
            )
        if result is not None:
            log.info(
                "Automatic %s audit %s: trip=%s leg=%s variance=%+d",
                trigger.value, result.audit_id, trip_id, leg_sequence, result.variance,
            )
    except UpstreamServiceError as exc:
        # The camera or the node is down. No row, no fabricated count, and
        # the departure or ping that prompted this has already succeeded.
        log.warning(
            "Automatic %s audit skipped (trip=%s leg=%s): %s",
            trigger.value, trip_id, leg_sequence, exc.message,
        )
    except DomainError as exc:
        # Trip no longer in progress, or it vanished. Expected at the
        # edges -- a ping can arrive just after the trip is completed.
        log.info(
            "Automatic %s audit not applicable (trip=%s leg=%s): %s",
            trigger.value, trip_id, leg_sequence, exc.message,
        )
    except Exception:
        log.exception(
            "Automatic %s audit failed (trip=%s leg=%s).",
            trigger.value, trip_id, leg_sequence,
        )
    finally:
        _in_flight.discard(key)


async def drain() -> None:
    """Await every capture still running. For tests.

    Not called on shutdown: a detached capture that is cut off simply
    loses its audit, and blocking the process for a hung camera's full
    timeout would be the worse trade.
    """
    while _tasks:
        await asyncio.gather(*list(_tasks), return_exceptions=True)
