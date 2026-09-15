"""E.1 -- a flagged YOLOv8 variance alerts office, driver and conductor.

The camera is replaced with a fake capture so the test is repeatable; the
rest of the path (use case, notification rows, HTTP list/read endpoints)
is real. Needs the backend on :8000 and a reset dev database.

    python tests/integration/test_notifications.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import httpx  # noqa: E402

from app.application.audit.trigger_audit import TriggerAuditUseCase  # noqa: E402
from app.core.db import SessionFactory  # noqa: E402
from app.infrastructure.clients.ai_node_client import AiNodeClient, CaptureResult  # noqa: E402
from app.infrastructure.repositories.policy_repository import PolicyRepository  # noqa: E402

API = "http://127.0.0.1:8000/api/v1"
TRIP = "TRIP-DEMO-00000001"
PASSWORD = "sabaygo123"
ACCOUNTS = {
    "coop_admin": "coopadmin@sabaygo.dev",
    "driver": "driver@sabaygo.dev",
    "conductor": "conductor@sabaygo.dev",
}

failures: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        failures.append(label)


async def login(client: httpx.AsyncClient, email: str) -> str:
    r = await client.post(f"{API}/auth/login", json={"email": email, "password": PASSWORD})
    r.raise_for_status()
    return r.json()["access_token"]


async def main() -> int:
    async with httpx.AsyncClient(timeout=10) as client:
        tokens = {role: await login(client, email) for role, email in ACCOUNTS.items()}
        auth = {role: {"Authorization": f"Bearer {t}"} for role, t in tokens.items()}

        # Trip must be in progress for an audit to apply.
        await client.post(f"{API}/trips/{TRIP}/start-boarding", headers=auth["conductor"])

        before = {
            role: (await client.get(f"{API}/notifications", headers=h)).json()["unread_count"]
            for role, h in auth.items()
        }

        # --- fake camera: exceed the threshold by exactly one ---------------
        async with SessionFactory() as s:
            threshold = await PolicyRepository(s).get_int("variance_alert_threshold")
            user_id = (await client.get(f"{API}/auth/me", headers=auth["conductor"])).json()["user_id"]

        from app.application.operations.boarding import ManifestUseCase

        async with SessionFactory() as s:
            booked = await ManifestUseCase(s).booked_count_on_leg(TRIP, 1)

        async def fake_capture(self):  # noqa: ANN001
            return CaptureResult(
                visual_count=booked + threshold,
                confidence_avg=0.9,
                model_version="fake-test",
                conf_threshold=0.5,
                capture_ms=1,
                inference_ms=1,
                total_ms=2,
                snapshot_b64="",
            )

        AiNodeClient.capture = fake_capture  # type: ignore[method-assign]

        async with SessionFactory() as s:
            result = await TriggerAuditUseCase(s).execute(
                trip_id=TRIP, leg_sequence=1,
                triggered_by_user_id=user_id, trigger_type="manual",
            )
        print(f"== audit {result.audit_id} variance={result.variance:+d} alert={result.alert_raised}")
        check(result.alert_raised, "variance meets threshold -> alert raised")

        # --- each audience received exactly one new row --------------------
        for role, h in auth.items():
            body = (await client.get(f"{API}/notifications", headers=h)).json()
            mine = [n for n in body["items"] if n["related_entity_id"] == result.audit_id]
            check(len(mine) == 1, f"{role} received one variance_alert")
            if mine:
                check(mine[0]["type"] == "variance_alert", f"{role} row typed variance_alert")
                check(not mine[0]["is_read"], f"{role} row unread")
            check(body["unread_count"] == before[role] + 1, f"{role} unread_count +1")

        # --- mark read is scoped to the caller -----------------------------
        admin_rows = (await client.get(f"{API}/notifications", headers=auth["coop_admin"])).json()["items"]
        nid = next(n["notification_id"] for n in admin_rows if n["related_entity_id"] == result.audit_id)
        r = await client.post(f"{API}/notifications/{nid}/read", headers=auth["driver"])
        check(r.status_code == 404, "driver cannot mark coop_admin's row read")
        r = await client.post(f"{API}/notifications/{nid}/read", headers=auth["coop_admin"])
        check(r.status_code == 200, "coop_admin marks own row read")
        after = (await client.get(f"{API}/notifications", headers=auth["coop_admin"])).json()["unread_count"]
        check(after == before["coop_admin"], "coop_admin unread_count back to baseline")

        r = await client.post(f"{API}/notifications/read-all", headers=auth["conductor"])
        check(r.status_code == 200 and r.json()["marked"] >= 1, "conductor read-all")

        # --- no alert, no rows ----------------------------------------------
        async def quiet_capture(self):  # noqa: ANN001
            return CaptureResult(
                visual_count=booked, confidence_avg=0.9, model_version="fake-test",
                conf_threshold=0.5, capture_ms=1, inference_ms=1, total_ms=2, snapshot_b64="",
            )

        AiNodeClient.capture = quiet_capture  # type: ignore[method-assign]
        async with SessionFactory() as s:
            quiet = await TriggerAuditUseCase(s).execute(
                trip_id=TRIP, leg_sequence=1, triggered_by_user_id=user_id,
            )
        body = (await client.get(f"{API}/notifications", headers=auth["coop_admin"])).json()
        check(
            not quiet.alert_raised
            and not any(n["related_entity_id"] == quiet.audit_id for n in body["items"]),
            "matching headcount produces no notification",
        )

    print(f"\n{'ALL PASSED' if not failures else f'{len(failures)} FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
