#!/usr/bin/env python3
"""Concurrency experiment for the pessimistic seat-locking claim.

THIS SCRIPT PRODUCES YOUR RESULTS CHAPTER.

It fires N simultaneous reservation requests at a single trip with a known
seat capacity and checks the one invariant that matters:

    successful bookings <= capacity, and no seat-leg is ever double-sold.

Run it end-to-end against the live API rather than calling the repository
directly -- an experiment that bypasses the HTTP and session layers does
not prove the deployed system is safe, only that one function is.

    python tests/integration/test_concurrency.py --requests 50

Prerequisites:
    - docker compose up -d           (MySQL running)
    - ./db/apply.sh --reset --seed   (fresh 14-seat trip, 42 seat-legs)
    - uvicorn app.main:app           (API running)
    - a real bcrypt hash seeded for the test passenger
"""

from __future__ import annotations

import argparse
import asyncio
import statistics
import time
from collections import Counter
from dataclasses import dataclass

import httpx

API = "http://127.0.0.1:8000/api/v1"
TRIP_ID = "TRIP-DEMO-00000001"
EMAIL = "passenger@sabaygo.dev"
PASSWORD = "sabaygo123"


@dataclass
class Attempt:
    index: int
    status_code: int
    seat_number: int | None
    error: str | None
    elapsed_ms: float


async def login(client: httpx.AsyncClient) -> str:
    r = await client.post(f"{API}/auth/login", json={"email": EMAIL, "password": PASSWORD})
    r.raise_for_status()
    return r.json()["access_token"]


async def attempt(
    client: httpx.AsyncClient, token: str, index: int, boarding: int, alighting: int
) -> Attempt:
    started = time.perf_counter()
    try:
        r = await client.post(
            f"{API}/bookings/reserve",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "trip_id": TRIP_ID,
                "boarding_stop": boarding,
                "alighting_stop": alighting,
            },
        )
        elapsed = (time.perf_counter() - started) * 1000
        body = r.json()
        return Attempt(
            index=index,
            status_code=r.status_code,
            seat_number=body.get("seat_number") if r.status_code == 201 else None,
            error=body.get("error") if r.status_code != 201 else None,
            elapsed_ms=elapsed,
        )
    except Exception as exc:  # noqa: BLE001
        return Attempt(
            index=index,
            status_code=0,
            seat_number=None,
            error=type(exc).__name__,
            elapsed_ms=(time.perf_counter() - started) * 1000,
        )


async def run(n: int, boarding: int, alighting: int, capacity: int) -> None:
    async with httpx.AsyncClient(timeout=30.0) as client:
        token = await login(client)

        print(f"\nFiring {n} simultaneous reservations "
              f"at stops {boarding}->{alighting} on {TRIP_ID}\n")

        wall_start = time.perf_counter()
        # gather() releases all coroutines at once -- this is the actual
        # race. Sequential requests would prove nothing.
        results: list[Attempt] = await asyncio.gather(
            *(attempt(client, token, i, boarding, alighting) for i in range(n))
        )
        wall_ms = (time.perf_counter() - wall_start) * 1000

    successes = [a for a in results if a.status_code == 201]
    seats = [a.seat_number for a in successes]
    duplicates = [s for s, c in Counter(seats).items() if c > 1]
    codes = Counter(a.status_code for a in results)
    errors = Counter(a.error for a in results if a.error)
    latencies = sorted(a.elapsed_ms for a in results)

    def pct(p: float) -> float:
        return latencies[min(int(len(latencies) * p), len(latencies) - 1)]

    print("=" * 62)
    print("CONCURRENCY EXPERIMENT RESULTS")
    print("=" * 62)
    print(f"Concurrent requests      : {n}")
    print(f"Trip seat capacity       : {capacity}")
    print(f"Successful bookings      : {len(successes)}")
    print(f"Rejected                 : {n - len(successes)}")
    print(f"Distinct seats allocated : {len(set(seats))}")
    print(f"DOUBLE-BOOKED SEATS      : {len(duplicates)}   <-- must be 0")
    print()
    print("Response codes:")
    for code, count in sorted(codes.items()):
        label = {
            201: "created",
            409: "no seat available / conflict",
            422: "policy violation",
            503: "lock contention",
        }.get(code, "other")
        print(f"  {code}  {count:>4}   {label}")
    if errors:
        print("\nError codes:")
        for err, count in errors.most_common():
            print(f"  {err:<24} {count}")
    print()
    print("Latency (ms):")
    print(f"  min    {latencies[0]:8.1f}")
    print(f"  median {statistics.median(latencies):8.1f}")
    print(f"  p95    {pct(0.95):8.1f}")
    print(f"  max    {latencies[-1]:8.1f}")
    print(f"  wall   {wall_ms:8.1f}  (all {n} requests)")
    print()

    overbooked = len(successes) > capacity
    if duplicates:
        print(f"FAIL: seats {duplicates} were allocated more than once.")
    elif overbooked:
        print(f"FAIL: {len(successes)} bookings exceeded capacity {capacity}.")
    else:
        print("PASS: no double-booking, no overbooking.")
        print("      Pessimistic locking held under concurrent load.")
    print("=" * 62)

    print("\nVerify independently in MySQL:")
    print(f"""
  SELECT seat_number, leg_sequence, COUNT(*) AS allocations
    FROM seat_inventory
   WHERE trip_id = '{TRIP_ID}' AND status <> 'available'
   GROUP BY seat_number, leg_sequence
  HAVING COUNT(*) > 1;      -- must return zero rows
""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--requests", type=int, default=50)
    parser.add_argument("--boarding", type=int, default=1)
    parser.add_argument("--alighting", type=int, default=4)
    parser.add_argument("--capacity", type=int, default=10,
                        help="advance_booking_seat_cap, not seat_capacity")
    args = parser.parse_args()
    asyncio.run(run(args.requests, args.boarding, args.alighting, args.capacity))