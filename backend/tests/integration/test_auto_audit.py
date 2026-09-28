"""2.3.5 -- door-closure and GPS-node triggered captures.

Proves the automatic half of the AI audit: that a capture happens with no
person asking, that it cannot fire twice for one leg, that a conductor's
own spot check does not suppress it, and that a dead camera loses the
audit rather than the operation.

The camera is faked (as in test_notifications.py) so the test is
repeatable without the AI node. Everything else is real: the use case, the
transition detector, the rows in MySQL. Needs only a reset dev database --
no running backend.

    python tests/integration/test_auto_audit.py
"""

from __future__ import annotations

import asyncio
import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import delete, select  # noqa: E402

from app.application.audit import auto_trigger  # noqa: E402
from app.application.audit.trigger_audit import TriggerAuditUseCase  # noqa: E402
from app.application.tracking.nahgm import TrackingService  # noqa: E402
from app.core import timezone as app_tz  # noqa: E402
from app.core.db import SessionFactory  # noqa: E402
from app.core.exceptions import UpstreamServiceError  # noqa: E402
from app.domain.enums import AuditTrigger, TripStatus  # noqa: E402
from app.infrastructure.clients.ai_node_client import AiNodeClient, CaptureResult  # noqa: E402
from app.infrastructure.models import Trip, TripLocationPing, Yolov8AuditLog  # noqa: E402

TRIP = "TRIP-DEMO-00000001"

failures: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        failures.append(label)


def fake_camera(count: int) -> None:
    async def capture(self):  # noqa: ANN001
        return CaptureResult(
            visual_count=count, confidence_avg=0.9, model_version="fake-test",
            conf_threshold=0.5, capture_ms=1, inference_ms=1, total_ms=2,
            snapshot_b64="",
        )

    AiNodeClient.capture = capture  # type: ignore[method-assign]


def dead_camera() -> None:
    async def capture(self):  # noqa: ANN001
        raise UpstreamServiceError("The van's camera node did not respond.")

    AiNodeClient.capture = capture  # type: ignore[method-assign]


async def audits_on(session, leg: int) -> list[Yolov8AuditLog]:
    result = await session.execute(
        select(Yolov8AuditLog).where(
            Yolov8AuditLog.trip_id == TRIP, Yolov8AuditLog.leg_sequence == leg
        )
    )
    return list(result.scalars().all())


# ---------------------------------------------------------------------
# The transition detector, with no database writes involved.
# ---------------------------------------------------------------------
async def test_node_departure_detection() -> None:
    print("\n== GPS-node departure is a transition, not a state")
    async with SessionFactory() as s:
        trip = await s.get(Trip, TRIP)
        svc = TrackingService(s)
        stops = await svc._route_stops(trip.route_id)
        last = max(rs.stop_sequence for rs, _ in stops)

        def ping(seq, dist):
            return TripLocationPing(
                nearest_stop_sequence=seq,
                distance_to_stop_m=None if dist is None else Decimal(str(dist)),
            )

        # Inside stop 1's fence (200 m), then well clear of it.
        check(
            await svc._leg_just_entered(ping(1, 40), 2, 30_000.0, stops) == 1,
            "left stop 1 -> leg 1",
        )
        # Still parked: same node, still inside the fence.
        check(
            await svc._leg_just_entered(ping(1, 40), 1, 60.0, stops) is None,
            "still inside stop 1's fence -> no trigger",
        )
        # Already out on the road when it last reported: not an event.
        check(
            await svc._leg_just_entered(ping(1, 5_000), 2, 4_000.0, stops) is None,
            "already between nodes -> no trigger",
        )
        # First report of the trip has nothing to transition from.
        check(
            await svc._leg_just_entered(None, 1, 10.0, stops) is None,
            "first ping of the trip -> no trigger",
        )
        # The route's last stop has no outgoing leg.
        check(
            await svc._leg_just_entered(ping(last, 20), last, 900.0, stops) is None,
            f"left final stop {last} -> no trigger",
        )


# ---------------------------------------------------------------------
# The capture itself.
# ---------------------------------------------------------------------
async def test_automatic_capture() -> None:
    print("\n== an automatic capture writes an unattributed audit row")
    async with SessionFactory() as s:
        trip = await s.get(Trip, TRIP)
        trip.status = TripStatus.DEPARTED.value
        # Start from a clean slate on the legs this test uses.
        await s.execute(
            delete(Yolov8AuditLog).where(
                Yolov8AuditLog.trip_id == TRIP,
                Yolov8AuditLog.leg_sequence.in_([1, 3]),
            )
        )
        await s.commit()

    fake_camera(7)

    async with SessionFactory() as s:
        result = await auto_trigger.fire(
            s, trip_id=TRIP, leg_sequence=1, trigger=AuditTrigger.DOOR_CLOSE
        )
    check(result is not None, "door_close fires a capture")

    async with SessionFactory() as s:
        rows = await audits_on(s, 1)
        check(len(rows) == 1, "exactly one row on leg 1")
        if rows:
            check(rows[0].trigger_type == "door_close", "row labelled door_close")
            check(
                rows[0].triggered_by_user_id is None,
                "triggered_by_user_id is NULL -- nobody asked",
            )

    print("\n== one automatic audit per leg")
    async with SessionFactory() as s:
        again = await auto_trigger.fire(
            s, trip_id=TRIP, leg_sequence=1, trigger=AuditTrigger.GPS_NODE
        )
    check(again is None, "a second automatic trigger on leg 1 is suppressed")
    async with SessionFactory() as s:
        check(len(await audits_on(s, 1)) == 1, "still exactly one row on leg 1")

    print("\n== a manual spot check does not satisfy the quota")
    async with SessionFactory() as s:
        crew = trip.conductor_id
        await TriggerAuditUseCase(s).execute(
            trip_id=TRIP, leg_sequence=3, triggered_by_user_id=crew,
            trigger_type=AuditTrigger.MANUAL.value,
        )
    async with SessionFactory() as s:
        auto = await auto_trigger.fire(
            s, trip_id=TRIP, leg_sequence=3, trigger=AuditTrigger.GPS_NODE
        )
    check(auto is not None, "gps_node still fires on a manually audited leg")
    async with SessionFactory() as s:
        kinds = sorted(a.trigger_type for a in await audits_on(s, 3))
        check(kinds == ["gps_node", "manual"], f"leg 3 holds both rows: {kinds}")


async def test_ping_path_fires_the_trigger() -> None:
    """The wiring, not just the detector: two real position reports through
    record_ping, the second one clear of the terminal, must produce an
    audit with nobody having asked for one."""
    print("\n== a position report out of the terminal fires the capture")
    started = app_tz.now()
    async with SessionFactory() as s:
        await s.execute(
            delete(Yolov8AuditLog).where(
                Yolov8AuditLog.trip_id == TRIP, Yolov8AuditLog.leg_sequence == 1
            )
        )
        await s.commit()

    fake_camera(9)
    try:
        async with SessionFactory() as s:
            svc = TrackingService(s)
            # Parked at Ecoland, inside its 200 m fence.
            await svc.record_ping(trip_id=TRIP, latitude=7.0524, longitude=125.5931)
        async with SessionFactory() as s:
            # Out on the highway toward Digos -- fence left.
            await TrackingService(s).record_ping(
                trip_id=TRIP, latitude=6.9500, longitude=125.5000, speed_kph=55.0
            )
        await auto_trigger.drain()

        async with SessionFactory() as s:
            rows = await audits_on(s, 1)
            check(len(rows) == 1, "record_ping produced one audit on leg 1")
            if rows:
                check(rows[0].trigger_type == "gps_node", "row labelled gps_node")
                check(rows[0].visual_count == 9, "count came from the camera, not a guess")
    finally:
        # Leave the breadcrumb trail as we found it.
        async with SessionFactory() as s:
            await s.execute(
                delete(TripLocationPing).where(
                    TripLocationPing.trip_id == TRIP,
                    TripLocationPing.recorded_at >= started,
                )
            )
            await s.commit()


async def test_dead_camera_loses_only_the_audit() -> None:
    print("\n== a dead camera loses the audit, never the operation")
    async with SessionFactory() as s:
        await s.execute(
            delete(Yolov8AuditLog).where(
                Yolov8AuditLog.trip_id == TRIP, Yolov8AuditLog.leg_sequence == 2
            )
        )
        await s.commit()

    dead_camera()
    # schedule() is what the departure and the ping path actually call: it
    # must return without raising even though the capture will fail.
    auto_trigger.schedule(trip_id=TRIP, leg_sequence=2, trigger=AuditTrigger.GPS_NODE)
    check(True, "schedule() returned without raising")
    await auto_trigger.drain()

    async with SessionFactory() as s:
        check(
            await audits_on(s, 2) == [],
            "no row written -- not a zero, not a placeholder",
        )


async def main() -> int:
    await test_node_departure_detection()
    await test_automatic_capture()
    await test_ping_path_fires_the_trigger()
    await test_dead_camera_loses_only_the_audit()
    print(f"\n{'ALL PASSED' if not failures else f'{len(failures)} FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
