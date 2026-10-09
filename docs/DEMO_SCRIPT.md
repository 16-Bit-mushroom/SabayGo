# Demo script — final defence

*Rehearsed 15 September 2026 with `backend/scripts/demo_rehearsal.sh`.
Run that script the morning of the demo; if it prints a red ✘, fix that
before anything else.*

## Set-up (20 minutes before)

```bash
docker compose up -d
./db/reset-dev.sh --soon        # fixture trip departs in 20 min -> check-in window open
cd backend && source venv/bin/activate && set -a && source .env && set +a
uvicorn app.main:app --host 0.0.0.0 --port 8000
cd ai_service && python app.py  # optional -- see "If the camera is off"
./scripts/demo_rehearsal.sh     # green all the way down = go
```

Phone: passenger app signed in as `passenger@sabaygo.dev`; a second phone
(or the same one, after) as `conductor@sabaygo.dev`. Laptop: operator
console as `coopadmin@sabaygo.dev`. Password everywhere `sabaygo123`.

The live loop uses the **Ecoland – Cotabato "First Trip"** because
`--soon` puts it inside the check-in window. Everything else on screen
(four routes, yesterday's revenue, the audit history) is the A2Z demo
dataset from `db/seed/002_demo_dataset.sql`.

## The loop, in order

| # | Who | Screen | Show | Say |
|---|---|---|---|---|
| 1 | Passenger | Home | Pick **Ecoland → Cotabato City**, today | Terminals, not stop numbers — Ecoland is stop 1 on four routes |
| 2 | Passenger | Results | First Trip, spaces left, ₱500 | Fare comes from the LTFRB matrix, not distance |
| 3 | Passenger | Reserve → Pay | Ticket appears as *pending* | The space is held for 10 minutes; only the payment webhook confirms it |
| 4 | Laptop | terminal | `python tests/integration/simulate_webhook.py --booking-id …` | Sandbox PayMongo — a signed webhook, the same bytes the real one sends |
| 5 | Passenger | Ticket | Status flips to *confirmed*, QR appears | Polls `GET /bookings/{id}`, no refresh needed |
| 6 | Passenger | Ticket | Tap **I'm here** | Geofenced to the terminal; a heads-up for dispatch, never a gate |
| 7 | Conductor | Assigned trips → Manifest | Passenger shows **AT TERMINAL** | |
| 8 | Conductor | Scan | Scan the QR → **valid** | Scan it again → **already boarded**. This is the anti-fraud beat |
| 9 | Conductor | Walk-in | Log a cash passenger 1 → 4 | Cash is *in hand*, not missing — the office sees the difference |
| 10 | Driver / Conductor | Headcount | Enter 2 | Cross-check by a human before the camera |
| 11 | Conductor | Audit | Trigger the camera | Visual vs manifest. Variance > 0 flags the trip and notifies the office |
| 12 | Laptop | Console → bell | Variance alert → Passenger Count Checks | Same row, same transaction as the audit log |
| 13 | Laptop | Audits → **History** | Yesterday's resolved / ignored / failed | The failed one: the node returned 502 rather than invent a count |
| 14 | Laptop | Revenue | Last 3 days; cash in hand ₱790 vs unreconciled ₱0 | One conductor has not remitted yet — that is a pocket, not a leak |
| 15 | Laptop | Revenue → **Export** | Download the .xlsx, open it | Totals row; the office keeps its books in Excel |

Stop there. Fifteen steps is twelve minutes at a comfortable pace.

## If the camera is off

Step 11 returns **502**. Do not apologise — that is the design: *"the node
never fabricates a count. An earlier prototype substituted 1 and displayed
it as real, which would flag an innocent driver."* Then go to step 13 and
show yesterday's audits, including the one that failed the same way.

## If the webhook simulator fails

`set -a; source .env; set +a` was skipped. Without
`PAYMONGO_WEBHOOK_SECRET` the signature does not match and the booking
stays *pending* — which is also the correct behaviour, but not the one you
want on stage.

## What not to show

- Reschedule on the `--soon` trip — correctly hidden (6-hour cutoff passed).
  If asked, reschedule the seeded booking `BKG-A2Z-U001` on tomorrow's
  Tagum trip instead (`liza@sabaygo.dev`).
- The dev-account chips on the sign-in screen — debug build only.
- Chat and the live map: not built; say so if asked.

## Questions the panel has asked before

- *Why not seat numbers?* UV Express does not assign them. Capacity is per
  leg, so one space carries two paying passengers on non-overlapping legs —
  `seat 3` on yesterday's 06:00 Tagum trip did exactly that (Ecoland→Panabo,
  then Panabo→Tagum).
- *What if two people book the last space at once?* 50 concurrent requests,
  0 double-bookings; the comparison run with the cap outside the lock let
  14 through a limit of 10. `python tests/integration/test_concurrency.py`.
- *Why Manila time in the database?* Single-timezone cooperative. Every
  timestamp is written through `app.core.timezone`; treating them as UTC
  shifted check-in windows eight hours in an early build.
