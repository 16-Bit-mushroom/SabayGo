# Handoff: the rev 721 refactor, steps S7 and S9–S11

*Written 3 Nov 2026, at the end of S8. All the work is on branch
**`console-v3`**, which is not merged into `main` yet: `main` is 13
commits behind.*

This picks up the cash-only refactor halfway. The backend is finished
apart from S7. What is left is one small backend step, the two Flutter
front ends, and the docs.

## Where we left off

- **S8 is finished and committed** (`feat(backend): T60 sweep`):
  migration 037, the stale gateway/QR wording, the demo rehearsal and
  `setup.sh` cleaned, and two journey assertions fixed that passed only
  in the afternoon. The last full suite (00:07–00:16, 3 Nov) gave
  **1061 passed, 0 failed, 0 gaps**:
  `docs/test-reports/journeys_20261103_000748.txt`.
- **Next is S7**, then S9, S10, S11 (below). The owner chose to skip S7
  and do S8 first, so S7 has not been started.
- **The two front ends do not match the backend yet.** Until S9 and S10
  land, the console's Remittance screen reads fields that no longer
  exist (it shows zeros). The app's ticket screen, QR scanner and
  reschedule sheet call endpoints that are gone (404). That is expected.
  The backend is the source of truth; do not "fix" it back.

### Why the suite seemed to take so long

It didn't. `run_all_journeys.sh` takes **about 9–10 minutes**. It runs
26 scripts, about 1060 assertions, and **16 database rebuilds** (each
`reset-dev.sh` replays all 37 migrations and both seeds, roughly 15–20 s
each). What hung was the wait around it: a loop like

```bash
until ! pgrep -f "run_all_journeys.sh"; do sleep 10; done   # never ends
```

never ends, because `pgrep -f` also matches the loop's own command line,
which contains the same text. Two such loops left running keep matching
each other forever. Run the suite in the foreground, or wait on its PID
(`wait $PID`, or `while kill -0 $PID; do sleep 10; done`), never on
`pgrep -f` with the script's name.

## Setup (a fresh clone)

```bash
git clone https://github.com/16-Bit-mushroom/SabayGo.git && cd SabayGo
git checkout console-v3
./setup.sh                       # .env files, venvs, Docker MySQL; docs/SETUP.md explains it
./db/reset-dev.sh --soon         # all 37 migrations + demo data; a trip departs in 20 min
cd backend && source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000   # leave running; a second terminal for tests
```

Dev logins: `passenger@`, `dispatcher@`, `manager@` and
`cashier@sabaygo.dev`, all with password `sabaygo123`. `./run.sh`
starts the database, the backend and the console in one command (see
CLAUDE.md, "Running it").

Check the setup: from `backend/`, with the venv active and `.env`
exported (`set -a && source .env && set +a`), run
`../db/reset-dev.sh --soon && ./tests/integration/test_terminal_fees.sh`.
It should end `69 passed, 0 failed`.

## Starter prompt for the next Claude Code session

Paste this as the first message:

> Read `docs/HANDOFF_REV721.md`, then `CLAUDE.md` and
> `docs/GAP_REPORT.md` §10. We are on branch `console-v3`, refactoring
> SabayGo to brief rev 721 (`docs/SabayGo-Changes-for-Claude-Code.md`).
> S1–S6 and S8 are done and the full journey suite was green (1061/0/0).
> First confirm the state: `git log --oneline -8` should show the S8
> commit `feat(backend): T60 sweep` on top. If `git status` shows it is
> not on `origin/console-v3`, tell me before doing anything else. Then
> do **S7 only** (special trips, brief §2.5, T49–T52), following the
> handoff's S7 checklist. Get `test_special_trips.sh` green after a
> `./db/reset-dev.sh --soon`, record the step in its GAP_REPORT §10.4 row,
> and commit it on its own. Do not start S9 until I say. Run the full
> suite in the foreground, never behind a `pgrep -f` wait loop.

## Read first, in this order

1. `CLAUDE.md`: the project rules. The rules that matter most here are
   "Start waits for the terminal fees", "A seat is paid when the
   Dispatcher says so", the vocabulary section, and "Say Dispatcher,
   never Conductor".
2. `docs/SabayGo-Changes-for-Claude-Code.md`: **the spec (brief rev
   721).** Where anything conflicts with it, it wins.
3. `docs/GAP_REPORT.md` §10: what rev 721 changed, the ten decisions
   already taken (§10.4), and the S1–S11 table. Each finished step's row
   names its migration, files and test script.
4. The docstring at the top of each module named below. The rules live
   there, not in this file.

## Where things stand

| Step | State | Commit |
|---|---|---|
| S1 gap report, CLAUDE.md re-pointed | done | — |
| S2 cash-only booking: booking code, Mark as Paid, cancel; gateway, QR, `payments`, reschedule removed (032) | done | `83bdbfd` |
| S3 release of unpaid reservations at `unpaid_cutoff_min` (033) | done | `beedd17` |
| S4 income groups Booked / Walk-up (034) | done | `c3706c5` |
| S5 terminal fees (₱75 DCOTT ticket per trip, ₱50 parking per van per day) and the operator's share (035) | done | `4246f0f` |
| S6 `match_window_seconds` retired (036) | done | `dbfa288` |
| S8 T60 sweep (037) and full journey suite | done | the S8 commit |
| **S7** special trips: walk-in fee basis and counter flow | **open** | |
| **S9** operator console (Flutter Web) | **open** | |
| **S10** passenger and Dispatcher app (Flutter) | **open** | |
| **S11** docs | **open** | |

At the S8 commit the full suite was **1061 passed, 0 failed, 0 gaps**
(`docs/test-reports/journeys_20261103_000748.txt`). The concurrency test was 10/10
successes, 40 rejections and 0 double sales (last run at S5; S6–S8 did
not touch the allocator).

## How to work

- **One step at a time.** Get the step's journey script green, then
  commit the step on its own. The backend comes before the front ends.
- Every migration ships a `db/migrations/down/` script. Test the round
  trip: `./db/apply.sh`, then `./db/rollback.sh <full_version_name>`
  (for example `037_drop_payment_leftovers`, not `037`), then apply
  again.
- Read settings only through `PolicyRepository` and fares only through
  `FareRepository`.
- Record each finished step in `docs/PROGRESS_LOG.md` (at the end) and
  in its row of `GAP_REPORT.md` §10.4.
- The shell in `CLAUDE.md` is fish. The journey scripts are bash; run
  them from `backend/` with the venv active and `.env` exported:
  ```bash
  cd backend && source venv/bin/activate && set -a && source .env && set +a
  ../db/reset-dev.sh --soon && ./tests/integration/test_special_trips.sh
  ./tests/integration/run_all_journeys.sh          # the whole suite, ~10 min, in the foreground
  python tests/integration/test_concurrency.py --requests 50
  ```
- Reset before each script you run on its own (`./db/reset-dev.sh
  --soon`). The scripts change state and are not meant to run one after
  another on the same data.
- The backend runs without `--reload` in these sessions, so restart
  uvicorn after a backend change. If a migration changed the schema, run
  it before restarting.
- **Do not edit a script while it is running**: bash reads scripts
  piece by piece as it goes. That includes `run_all_journeys.sh` during a
  suite run.
- **Late-night runs.** The seed dates its live trips from the moment of
  the reset. A run after about 22:00 puts `TRIP-A2Z-LIVE-SOON` on
  tomorrow's board, and a run that crosses midnight fails on dates. If
  the suite goes red near midnight, re-run it after 00:05 before
  debugging. Before calling a test failure a bug, check whether the
  assertion depends on the hour the data was reset.
- Flutter: `$HOME/flutter/bin/flutter` on the original machine. Check
  your work with `flutter analyze | grep -E "error|warning"`. The console
  is built with `flutter build web --release --pwa-strategy=none` (see
  CLAUDE.md, "Running it").

## S7 — special trips: walk-in fee basis and counter flow

Brief §2.5 and tests T49–T52. Most of it already works:
`application/operations/special_trips.py` (read its docstring) and
`api/v1/special_trips.py` handle the app request, the counter walk-in
(`POST /special-trips/walk-in`), approval with `fee` + `fee_note`, the
van/Dispatcher assignment and T52's decline. The Dispatcher's cash mark
is `POST /special-trips/{id}/cash` with `paid_at`/`paid_by`. The rental
fee's income group follows where the request came from (app → Booked,
counter → Walk-up). The ₱75 applies to a special trip (decision 9).

What is left to check against §2.5 and Table 34:
- `fee_note` is required, and the fee basis is still **[INTERPRETED]**
  in the brief (pickup and destination, no fare table). Keep it free
  text and do not add a fare table. The question goes to A2Z (S11).
- The counter flow end to end: entered by the Terminal Manager or the
  Cashier (`entered_by`), approved as entered, a Dispatcher assigned,
  cash marked by the trip's Dispatcher, 15 % + ₱75 recorded before
  Start. `test_special_trips.sh` covers most of this. Extend it rather
  than writing a new script.
- [OPEN] items stay open: whether the Cashier may agree a fee, and
  whether a van that declines keeps its place in the queue. They go on
  the list for A2Z; do not code either.

Proof: `test_special_trips.sh` green, then commit.

## S9 — operator console (`operator_console/`)

The backend responses already carry everything; the console reads old
names. Found by the S8 sweep:

- `lib/data/repositories/money_repository.dart` reads `verified_income`
  and `declared_income`, which are now **`booked_income`** and
  **`walk_up_income`**. Add the S5 fields from `StatementOut` in
  `backend/app/api/v1/statements.py`: `dcott_ticket_fee`, `dcott_fees`,
  `parking_fee`, `terminal_fees_owed`, `operator_share_owed`,
  `operator_share_given`, `operator_share_given_at`,
  `operator_share_recorded_by_name`, `operator_share_difference`,
  `operator_share_differs`. A line's `income_group` is `'booked'` or
  `'walk_up'`.
- `lib/modules/remittance/remittance_screen.dart`: show Booked and
  Walk-up income, remittance owed (15 %), the ₱75 × trips line, the ₱50
  parking line, **terminal fees owed**, held share, amount due, the
  **operator's share owed and given**, and the **'Operator share
  differs'** flag (a warning only; it blocks nothing). The screen also
  needs these actions:
  - Record a payment with the operator's share:
    `POST /statements/{id}/payments`, body `{amount, reference,
    operator_share}`.
  - Record a share difference on its own:
    `POST /statements/{id}/operator-share`, body `{amount}`.
  - A **parking-only charge** for a van with no trip today:
    `POST /statements/parking`, body `{van_id}` (returns 201, or 409 if
    the van already has a statement).
  - Top-up lines (`is_top_up`) already come in the lines.
- `lib/modules/trip_monitor/trip_lifecycle_panel.dart` and
  `lib/data/repositories/dispatch_repository.dart`: the wording says
  "A2Z's 15 %", but Start now waits for the **terminal fees** (15 % +
  ₱75 + the day's ₱50 when unpaid). The trip payment is `POST
  /trips/{id}/payment` `{amount, reference, operator_share}`. Line 67
  says "only QR tickets and logged fares count": replace it with "only
  the passenger list counts", matching the server's Unaudited alert.
- `lib/modules/policy_editor/screens/policy_editor_screen.dart`:
  **remove** `seat_hold_ttl_seconds`, `hold_sweep_interval_seconds`,
  `cancel_cutoff_hours`, `reschedule_cutoff_hours`,
  `max_reschedules_per_booking`, `refund_enabled`,
  `match_window_seconds`; **add** `unpaid_cutoff_min`,
  `dcott_ticket_fee`, `parking_fee`. The server's list (`GET
  /config/policies`) is the source of truth. Also fix the stale
  docstring in `lib/data/repositories/policy_repository.dart`.

Proof: `flutter analyze` clean, then `flutter build web --release
--pwa-strategy=none`. Walk the sample trip (below) in the console if you
can.

## S10 — passenger and Dispatcher app (`mobile/`)

The package is still named `mobile_v2_uv_express`; do not rename it.

Passenger:
- The reservation shows the fare, **Unpaid** / **Paid**, the
  **booking code** (`booking_code`), and the notice that the fare is paid
  in cash to the Dispatcher at the terminal before the cutoff
  (`unpaid_cutoff_min`, default 30 min before departure). Cancelling an
  unpaid reservation is `POST /bookings/{id}/cancel`. It is refused once
  the seat is Paid or the list is locked.
- Delete `views/ticket/ticket_screen.dart`,
  `viewmodels/ticket_viewmodel.dart` (PayMongo checkout, QR) and
  `views/reservations/reschedule_sheet.dart`, along with their routes
  and imports (`home_screen.dart`, `reservations_screen.dart`).
- `data/repositories/booking_repository.dart`: drop `qr_payload`,
  `can_reschedule`, `reschedule_deadline`, `reschedule()`,
  `/payments/checkout`, and the `'rescheduled'` status label.
- `data/repositories/special_trip_repository.dart`: drop `checkout()`
  (`/special-trips/{id}/checkout` no longer exists), and drop its use in
  `views/special_trips/special_trips_screen.dart`. The fee is paid in
  cash to the Dispatcher.

Dispatcher:
- `views/dispatcher/trip_manifest_screen.dart`: search by name or
  booking code (`GET /bookings/trip/{trip_id}/seats?q=`), **Mark as
  Paid** (`POST /bookings/{id}/mark-paid`, body `{paid_at}`; send the
  device's time so a mark queued offline keeps when it happened), and
  **Cancel Reservation** (`POST /bookings/{id}/dispatcher-cancel`, body
  `{reason}` with `passenger_asked_dispatcher` or `forgot_to_cancel`).
  Both must work **offline** and sync on reconnect. A mark-paid response
  may come back `restored: true` (the seat was released and has been
  given back) or `seat_gone: true` (no seat left; the Terminal Manager
  has been alerted). Show either to the Dispatcher.
- Delete `views/dispatcher/qr_scanner_screen.dart` and its imports in
  `dispatcher_main_screen.dart` and `trip_manifest_screen.dart`, and
  `qr_payload` in `data/repositories/operations_repository.dart`.
- `pubspec.yaml`: remove `mobile_scanner` and `qr_flutter`. Keep
  `url_launcher` only if `home_pickup_screen.dart` still needs it (it
  opens maps).
- The old comments that mention reschedule (`journey_strip.dart`,
  `money.dart`, `api_exception.dart`, `trip_repository.dart`) should go
  too.

Proof: `flutter analyze` clean. A device run only if the owner asks.

## S11 — docs

- `docs/PROGRESS_LOG.md`: one entry per step, S2–S10. None is written
  yet; the GAP_REPORT §10.4 rows hold the details to copy from.
- `docs/KNOWN_ISSUES.md`, `docs/REMAINING_WORK.md`: drop the
  gateway/QR/reschedule items and add what rev 721 left open.
- `docs/MANUSCRIPT_CORRECTIONS.md`: the leftovers brief §14 lists for
  the paper. Table 10 and Figures 6, 23 and 27 still show only the 15 %,
  and Table 33 still lists `MatchWindowS`.
- `docs/QUESTIONS_FOR_COOPERATIVE.md`: confirm the ₱75 and the ₱50,
  whether the ₱75 applies to a special trip, the 30-minute cutoff and
  its reminder (decision 5), what the special-trip fee is based on,
  whether the Cashier may agree a fee, whether a declining van keeps its
  queue place, whether the operator signs for the share, and what
  `refund_enabled` and `cancel_cutoff_hours` meant to A2Z (decision 6).
- `docs/DEMO_SCRIPT.md`, `docs/SETUP.md`, `README.md`, `START_HERE.md`,
  `PRODUCT.md`: these still describe the sandbox payment, the QR ticket
  or PayMongo. `backend/scripts/demo_rehearsal.sh` is already cash-only
  and is the order the demo follows.
- `CLAUDE.md` "Next": move the rev 721 refactor to done.

## The sample trip (brief §12.1): the end-to-end check

11 Digos passengers and 2 Sta. Cruz passengers booked and paid, plus 1
walk-up, gives B ₱1,370 and W ₱80. The statement must show:
- remittance owed (15 %): **₱217.50**
- terminal fees (15 % + ₱75 + ₱50): **₱342.50**
- operator's share: **₱1,107.50**

Start stays blocked until the full terminal fees are recorded.
`test_terminal_fees.sh` checks exactly this. The console and the app
should show the same three numbers.

## Pitfalls already met

- MySQL refuses to rename a column that a CHECK constraint names. Drop
  the CHECK, rename the column, then add the CHECK back (see 034).
- Change an ENUM in three steps: widen it, map the old values, then
  narrow it (034).
- A retired setting is deleted together with all its history rows
  (030, 033, 036), and its bound in `domain/policies.py` goes with it.
- Seed emails end in `.dev`, never `.test`.
- MySQL stores naive Manila time; use `app.core.timezone`.
