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
(or the same one, after) as `dispatcher@sabaygo.dev`. Laptop: office
console as `manager@sabaygo.dev`. Password everywhere `sabaygo123`.

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
| 9a | Laptop, private window as `cashier@` | Trips → First Trip → **Record A2Z's share** → **Start trip** | Share shown line by line, recorded; then Started, warning *no phone is checked out*, trip marked **Unaudited** | Rev 603: Start waits for A2Z's 15 %, handed over by the Dispatcher and recorded by the Cashier. The manager's window has no record button: separation of duties. The office starts the trip, not the Dispatcher, and who started it is on the record. A private window because the console keeps one sign-in per browser |
| 10 | Dispatcher | Trip dashboard | Camera count aboard against listed; the crew switch; **Depart** | The phone's door count against the list. More aboard than listed stops Depart until each boarding is listed (with a destination) or given a reason. Without the edge phone the count is 0: fewer aboard is a no-show, nothing to do |
| 11 | Laptop, `manager@` | **Boarding Audit** | Unlisted boardings with the Dispatcher's fix or reason, capacity alerts with their place, the hash chain | Only the Terminal Manager sees the blurred stills; a changed record breaks the chain. To fill this page without a phone, run `tests/integration/test_door_check.sh` on a reset database first |
| 12 | Laptop, `cashier@` | **Remittance** | Each van's statement: paid through the app (verified) and in cash (declared), A2Z's 15 %, paid | No estimated income: the lines are the passenger list. A line can be disputed until it is paid |
| 13 | Laptop, `manager@` | **Disputes**, **Driving Flags** | Decide a dispute; review or dismiss a flag | Only the Terminal Manager decides. A flag is for review, not proof |
| 14 | Laptop | **Van Status Board** | Vans travelling, on site, out of service; who still owes | From trip status and GPS already stored; no extra data entry |

Stop there. Fifteen steps is twelve minutes at a comfortable pace.

## If the camera is off

Step 10 returns **502**. Do not apologise — that is the design: *"the node
never fabricates a count. An earlier prototype substituted 1 and displayed
it as real, which would flag an innocent driver."* Then go to step 12 and
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
