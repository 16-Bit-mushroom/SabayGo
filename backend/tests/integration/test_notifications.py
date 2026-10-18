"""E.1 -- an alert reaches the roles it names, not the person who caused it, and
marking it read is scoped to its owner.

The producer is a rev 603 trip alert: the Terminal Manager lifts a trip's
payment block (brief 2.1), which tells the Cashier. The Terminal Manager
did it and is not told; the Dispatcher is not an office role and is not
told either. Until 16 Oct this test drove the rev 468 YOLOv8 variance
alert through a fake camera; that audit is retired. HTTP only. Needs the
backend on :8000 and a reset dev database.

    python tests/integration/test_notifications.py
"""

from __future__ import annotations

import asyncio
import sys

import httpx

API = "http://127.0.0.1:8000/api/v1"
TRIP = "TRIP-DEMO-00000001"
PASSWORD = "sabaygo123"
ACCOUNTS = {
    "terminal_manager": "manager@sabaygo.dev",
    "dispatcher": "dispatcher@sabaygo.dev",
    "cashier": "cashier@sabaygo.dev",
}
ALERTED = {"cashier"}

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

        async def inbox(role: str) -> dict:
            return (await client.get(f"{API}/notifications", headers=auth[role])).json()

        before = {role: (await inbox(role))["unread_count"] for role in auth}

        # --- the producer: lift the payment block on a scheduled trip ------
        r = await client.post(
            f"{API}/trips/{TRIP}/payment-override", headers=auth["terminal_manager"],
            json={"note": "Share brought to the office after the first run"},
        )
        check(r.status_code == 200, f"payment block lifted ({r.status_code})")

        # --- each audience: one new row, or none ---------------------------
        rows: dict[str, list[dict]] = {}
        for role in auth:
            body = await inbox(role)
            rows[role] = [n for n in body["items"]
                          if n["type"] == "payment_block_override" and n["related_entity_id"] == TRIP]
            if role not in ALERTED:
                check(not rows[role] and body["unread_count"] == before[role], f"{role} not alerted")
                continue
            check(len(rows[role]) == 1, f"{role} received one payment_block_override")
            if rows[role]:
                n = rows[role][0]
                check(n["related_entity_type"] == "trip", f"{role} row points at the trip")
                check(not n["is_read"], f"{role} row unread")
            check(body["unread_count"] == before[role] + 1, f"{role} unread_count +1")

        # --- mark read is scoped to the caller -----------------------------
        if rows["cashier"]:
            nid = rows["cashier"][0]["notification_id"]
            r = await client.post(f"{API}/notifications/{nid}/read", headers=auth["terminal_manager"])
            check(r.status_code == 404, "Terminal Manager cannot mark the Cashier's row read")
            r = await client.post(f"{API}/notifications/{nid}/read", headers=auth["cashier"])
            check(r.status_code == 200, "Cashier marks own row read")
            check((await inbox("cashier"))["unread_count"] == before["cashier"],
                  "Cashier unread_count back to baseline")

        r = await client.post(f"{API}/notifications/read-all", headers=auth["dispatcher"])
        check(r.status_code == 200, "Dispatcher read-all")
        check((await inbox("dispatcher"))["unread_count"] == 0, "Dispatcher has nothing unread after read-all")

    print(f"\n{'ALL PASSED' if not failures else f'{len(failures)} FAILED'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
