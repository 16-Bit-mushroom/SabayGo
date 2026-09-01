#!/usr/bin/env python3
"""Nightly trip generation job.

Add to crontab (runs at 00:15 Manila time):

    15 0 * * * cd /path/to/backend && venv/bin/python scripts/generate_trips.py --days 7

Generating a 7-day rolling window rather than just tomorrow means a missed
run does not leave a hole in the schedule -- the next run backfills it.
Re-runs are idempotent via UNIQUE (template_id, service_date).
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.application.scheduling.generate_trips import GenerateDailyTripsUseCase
from app.core.db import SessionFactory, engine


async def main(days: int) -> int:
    async with SessionFactory() as session:
        reports = await GenerateDailyTripsUseCase(session).execute(days_ahead=days)

    created = sum(r.trips_created for r in reports)
    for r in reports:
        print(f"{r.service_date}  created={r.trips_created:<3} "
              f"skipped={r.trips_skipped:<3} seat_legs={r.seat_legs_created}")
        for w in r.warnings:
            print(f"   warning: {w}")

    await engine.dispose()
    print(f"\ntotal trips created: {created}")
    # Non-zero exit if nothing was created AND nothing was skipped -- that
    # means no templates matched at all, which usually signals a config
    # problem rather than a quiet day.
    return 0 if created or any(r.trips_skipped for r in reports) else 1


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=7)
    sys.exit(asyncio.run(main(p.parse_args().days)))
