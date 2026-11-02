# SabayGo

Capstone project: a booking and fleet-management system for terminal-based
UV Express vans in Davao City, with A2Z Transport Cooperative as pilot
partner. BSIT, University of Mindanao.

**Final defence moved: the date waits on endorsement (was 20 October).**

**The spec is brief rev 721** (`docs/SabayGo-Changes-for-Claude-Code.md`,
2 Nov), matching the revised ACM paper (the PDF's filename still says
rev 603; its text does not). It replaced rev 603 and makes A2Z **cash
only**: no online payment, no QR ticket. A passenger reserves a seat and
gets a **booking code**, and the **Dispatcher marks the seat Paid** when
the cash is handed over at the terminal. Income groups are **Booked (B)**
and **Walk-up (W)**, and beside the 15 % A2Z charges a **₱75 DCOTT
ticket for each trip** and a **₱50 parking fee for each van each service
day** — the three are the **terminal fees**, and what is left of the cash
is the **operator's share**. Its delta, decisions and roadmap S1–S11 are
`docs/GAP_REPORT.md` §10. **Where anything conflicts with it, rev 721
wins.**

**What is built, and why, is `docs/PROGRESS_LOG.md`**: rev 468, rev 603
R1–R10, the edge app and every step since. Before changing an area, read
its entry there (each names the module whose docstring holds the rules).
Record each finished step at the end of that file, not here.

---

## What the system does

Passengers book a seat on a fixed LTFRB route through an app. Crew scan
tickets at the van door and record cash passengers. The cooperative office
configures fleet, routes, fares and schedules, and reconciles revenue. A
camera in the van counts passengers and compares that count against the
manifest to detect undocumented boardings — the project's core
contribution.

---

## Read these first

@docs/SESSION_RULES.md — token discipline, loaded every session.

| File | Why |
|---|---|
| `docs/REMAINING_WORK.md` | What is left, grouped |
| `docs/MANUSCRIPT_CORRECTIONS.md` | Where the paper and the code disagree, with replacement wording |
| `docs/FLUTTER_PHASE1_ISSUES.md` | 20 documented setup failures and fixes |
| `backend/app/infrastructure/repositories/seat_repository.py` | The thesis. Read its docstring before touching it |
| `docs/MODEL_EVALUATION_EXPLAINED.md` | The model metrics in plain language, with the talk track for the adviser |
| `ai_service/eval/README.md` | How the YOLOv8 model is evaluated, and why those metrics and not others |
| `docs/PROGRESS_LOG.md` | What each step built, and where its rules live |
| `docs/KNOWN_ISSUES.md` | Open defects and traps, with their history |

---

## Vocabulary — get this right

**Route** — a fixed LTFRB path: an ordered list of terminals, numbered 1..N.

**Stop** — a terminal's *position* on a route. The same terminal can be
stop 2 on one route and stop 5 on another, which is why booking works in
stop sequences rather than terminal IDs.

**Leg / section** — the stretch between two neighbouring stops. Leg *k*
runs from stop *k* to stop *k+1*. A route with N stops has N−1 legs.

**Segment / journey** — one passenger's boarding and alighting pair. It
consumes every leg between them: `boarding ≤ leg < alighting`. A passenger
riding 1→2 is **not** aboard on leg 2.

**Space (not seat)** — UV Express does **not assign seat numbers**;
`seat_number` in the database is an internal slot counter and is never
shown to a passenger.

**Capacity is 14 per trip.** Passengers board **only at the starting
terminal**, so every booking on a trip consumes leg 1 and the per-leg
rows in `seat_inventory` already count per trip. Do not read the old
claim that one space carries two paying passengers on one trip: it was
true only while boarding at a middle stop was allowed, and it has not
been since rev 603.

---

## Roles

| Role | Who |
|---|---|
| `passenger` | The commuting public. Self-registers |
| `dispatcher` | A2Z staff who rides the van. Scans, logs cash passengers. Mobile app |
| `terminal_manager` | Decides what is owed, sets rules, validates records. Web console |
| `cashier` | Records payments, starts trips. Web console; Terminal-Manager-only pages hidden |
| `admin` | System administrator — the development team |

The **operator** is the van owner, who always drives: a row in
`operators`, **no login**, one van each. Never call office staff
"operator" — under LTFRB usage that word is the franchise holder. Guards:
`MANAGER` and `OFFICE` in `api/v1/deps.py`.

---

## Stack

```
db/           MySQL 8.0 in Docker, host port 3307. Migrations are truth.
backend/      FastAPI, async SQLAlchemy 2.0, Clean Architecture
ai_service/   YOLOv8 evaluation harness only (eval/); no server since 16 Oct
edge_app/     native Kotlin, the in-van phone (benchmark first, then door events)
mobile/       Flutter: passenger, Dispatcher
operator_console/  Flutter Web: Terminal Manager, Cashier
```

Package name is still `mobile_v2_uv_express` though the folder is
`mobile/`. Renaming would touch every import; not worth it.

---

## Running it

On a machine that is not set up yet, `./setup.sh` does the whole thing and
`docs/SETUP.md` explains it. Everything below assumes it has been run.

**`./run.sh` starts the whole system in one command** and is what the demo
uses. It resolves this machine's LAN address once and hands the same
address to every process — backend CORS, console, handset — because
four hand-maintained copies of an IP address is what broke the last demo.

```fish
./run.sh                      # db + backend + console
./run.sh --mobile             # also the passenger/Dispatcher app, on an attached device
./run.sh --host 10.0.52.117   # force the address, when detection picks the wrong NIC
./run.sh --soon               # rebuild demo data, trip departs in 20 min
./run.sh --reset-db           # rebuild demo data; live trips dated from now
```

`002_demo_dataset.sql` seeds three **live trips dated from the moment of
the reset**, so reset shortly before a demo: `TRIP-A2Z-LIVE-BOARD`
(boarding, the dev dispatcher@, passenger@ holds a ticket; its list is
5),
`TRIP-A2Z-LIVE-DEPART` (departed, a no-show) and
`TRIP-A2Z-LIVE-SOON` (scheduled in 2 h, bookable). They are special trips
(template `NULL`) because `uq_trip_instance` is (template, date).

Ctrl-C stops everything it started; MySQL is left up. Each process logs to
`logs/`, so grep the log, never stream it.

The console is **built** (`flutter build web --release --pwa-strategy=none`)
and served from `operator_console/build/web` with `python3 -m http.server`
on port 3001, not started with `flutter run`. On this machine `flutter run
-d chrome` finds no Chrome (only `/usr/bin/chromium`) and `-d web-server`
opens the port but never accepts a connection. The build takes ~3.5 min
and is skipped on later runs unless `lib/`, `pubspec.yaml` or the baked-in
API address changed (stamp: `build/web/.sabaygo-api-base`). Run `./run.sh`
once before a demo so the build is not on stage.

The handset app (`--mobile`) is built with `flutter build apk --debug`,
installed with `adb install -r` (keeps app data, so the Dispatcher stays
signed in) and launched before the launcher reports "up". It is not left
under `flutter run`: two of those at one phone queued on Flutter's
startup lock, and stopping the launcher killed both mid-Gradle with
nothing installed. An installed app outlives the launcher. When the
venue's network changes, re-run `./run.sh --mobile` so the app is rebuilt
against the new address.

Piece by piece, when one component is being worked on:

```fish
# database
docker compose up -d
./db/reset-dev.sh              # clean state, trip departs tomorrow 05:30
./db/reset-dev.sh --soon       # departs in 20 min, so check-in is testable

# backend — 0.0.0.0, not localhost, or the phone cannot reach it
cd backend && source venv/bin/activate.fish
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# mobile, on a physical device over wireless adb
cd mobile
flutter run -d 192.168.1.2:5555 --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1

# operator console
cd operator_console
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# The live map needs no key or extra flag -- OpenStreetMap tiles via
# flutter_map. Internet access for the tiles is the only requirement.

# tests
cd backend && ./tests/integration/run_all_journeys.sh
python tests/integration/test_concurrency.py --requests 50
python scripts/tracking_simulator.py --trip TRIP-DEMO-00000001 --speed 30
```

Dev accounts: `passenger@` `dispatcher@` `manager@` `cashier@sabaygo.dev`,
password `sabaygo123`.

Journey tests need the backend venv on `PATH` and `backend/.env`
exported: `test_notifications.py` and the release sweep in
`test_unpaid_release.sh` are run as plain `python` against the backend
package.

The shell is **fish**. `set VAR (cmd)` not `VAR=$(cmd)`; no heredocs —
wrap them in `bash -c '...'`.

---

## Rules that are not obvious

**Every change follows these** (gathered from the build log):
- Say **Dispatcher**, never Conductor. Show the operator only as name +
  licence + plate on the trip.
- Every new migration ships a `db/migrations/down/` script;
  `./db/rollback.sh <version>` runs it.
- Read policies only through `PolicyRepository` and fares only through
  `FareRepository`: a bare lookup by key or pair finds an arbitrary old row.
- Run the one journey script for the feature (add a new one to
  `run_all_journeys.sh`), then record the step in `docs/PROGRESS_LOG.md`.
- In Claude's bash `flutter` is not on PATH: use `$HOME/flutter/bin/flutter`
  (a filtered `analyze | grep` hides "command not found"). Verify Flutter
  with `flutter analyze` and the journey scripts, not a device, unless asked.
- Both live maps carry OpenStreetMap's ODbL attribution: a licence
  condition, not decoration.

**Migrations define the schema; ORM models describe it.** Never run
`create_all()`.

**`seat_repository.allocate_seat()` locks coarsely on purpose.** It locks
the whole candidate window rather than using a single
`GROUP BY ... FOR UPDATE`, because MySQL's locking semantics with GROUP BY
and LIMIT depend on the query plan — poor ground for a correctness claim.
Read the module docstring before "optimising" it.

**A seat is paid when the Dispatcher says so, and never before.** There
is no gateway and no webhook to confirm one: `payment_status` goes to
'paid' only through `CashDesk.mark_paid` (`application/booking/cash.py`),
which records `paid_at` and `paid_by`. A check-in says where a phone is,
not that money changed hands, so it neither pays a seat nor saves it from
the cutoff. The sandbox checkout, the PayMongo client and the `payments`
table were removed in migration 032.

**An unpaid reservation is released before departure, and the release is
a decision, not a timer.** `application/booking/unpaid_release.py` runs
every 60 s: `unpaid_cutoff_min` (30) minutes before departure it cancels
each unpaid seat with `cancel_reason='auto_release'` and `cancelled_by`
NULL, frees the seat and tells the passenger, having reminded them one
cutoff-length earlier. A Paid mark that syncs after that restores the
seat if the trip still has one, and otherwise alerts the Terminal
Manager (`paid_after_release`) — there is real cash to settle either way.
Migration 033 retired the gateway-era seat hold with its TTL, its sweeper
and `seat_inventory.hold_expires_at`.

**Start waits for the terminal fees, not the 15 %.** A trip owes the
DCOTT ticket (`dcott_ticket_fee`, ₱75) once it has a van, even with
nobody on the list, and the van's statement charges the day's parking
(`parking_fee`, ₱50) when it opens. Start and the next assignment are
blocked until the 15 %, the ticket and the parking are recorded; the
operator's share is recorded beside them and blocks nothing
(`application/finance/statement.py`).

**Policy values are snapshotted onto each trip at generation.** Changing a
policy must not alter terms a passenger already booked under. A trip is
read for the values it was generated with, never the live row.

**The system never fabricates a count.** A trip with no phone reporting
is marked Unaudited (`no_phone`, `silent_at_start`, `lens_blocked`,
`lost_en_route`), never counted as zero. An earlier prototype substituted
`visual_count = 1` when the camera was unreachable and displayed it as
real, which would flag an innocent driver on an invented number.

**An SOS is recorded before any SMS is attempted, and a text message is
never reported as sent unless the gateway accepted it.** `RaiseSosUseCase`
commits the alert and its notifications first, then dispatches, then
commits one `sos_alert_dispatches` row per number with the real outcome.
A dead gateway loses the text, never the emergency. Same rule as the AI
node: an unreachable device is an error state, not a fabricated success.

**SMS has two providers and neither is required.** `SMS_PROVIDER` is
`disabled` (development), `android_gateway` (a handset on the
cooperative's own SIM -- FOSS, no per-message charge) or `twilio` (the
vendor §2.3.5 names; paid, trial reaches verified numbers only). Who gets
texted is the `sos_contact_numbers` cooperative policy, edited in the
console's Rules & Settings page, not an env var.

**MySQL stores naive local time (Asia/Manila).** Use `app.core.timezone`.
Treating those timestamps as UTC shifts everything eight hours and breaks
check-in windows silently.

**Seed emails must end `.dev`, not `.test`** — `.test` is an RFC 2606
reserved TLD and Pydantic's `EmailStr` rejects it.

**Cash is not missing money.** A walk-up the Dispatcher lists is paid as
it is listed (`paid_at` set at creation), so it counts as income in hand
and never as something unreconciled. Before this rule, every honest
conductor appeared to be stealing.

---

## Domain invariants — do not "improve" these

- Every booking has a fixed space. Terminal-based dispatch, not hail-and-ride.
- Fares come from a pairwise terminal matrix per LTFRB approval. Not
  distance-based, not dynamic.
- Boarding is at the **starting terminal, before departure**, and the
  only exception is the home pickup of a disabled or elderly passenger.
- **Cash only.** The system holds and moves no money. It records which
  seats the Dispatcher marked as paid, and the amounts handed to the
  Cashier and to the operator. No refunds, and no reschedule — an unpaid
  reservation is cancelled and booked again instead.
- A **roadside pickup after the van leaves the terminal zone is neither
  flagged nor priced**. It is a disclosed limitation of the study, not an
  oversight: the camera's count sets no fare anywhere, so pricing one
  here would be the fabrication the whole design refuses. *(This replaces
  the rev 468 rule that a roadside pickup was recorded from the previous
  terminal with a conductor-set fare, and the 13 Oct rule that priced it
  from the nearest stop.)*

Changing any of these is a schema migration, not a config change.

---

## Next

**The rev 721 refactor is the current work** (2 Nov): cash only, booking
code, terminal fees. Its eleven steps are `docs/GAP_REPORT.md` §10.4,
backend first and the two Flutter apps last, one step at a time with its
journey script green before the next. Everything below waits on it,
except items the owner runs.
**Handoff (3 Nov): `docs/HANDOFF_REV721.md`.** S1–S6 and S8 are done;
S7 (special trips), S9 (console), S10 (apps) and S11 (docs) are left,
each with its files, endpoints and proof listed there.

In the order agreed on 16 Oct, one step at a time. The runner probes and
the rev 468 retirement are done (`docs/PROGRESS_LOG.md`). Left:

1. ~~Docs and merge~~ done 18 Oct: docs brought up to date,
   `main` fast-forwarded to this branch (local, not pushed).
2. **The phone benchmark** (the owner runs it in a van). *Part 1 done
   18 Oct:* the bench Sweep, `docs/benchmarks/edge_sweep_2026-10-18.md`
   (CPU FP16 fastest at both sizes; the GPU slower on this phone; no
   throttling in 9.5 min). Left: one full Run on vehicle power (part 2).
   No operating frame rate is quoted before it exists.
3. **The edge app proper** (brief 5.1–5.3). *Built 18 Oct*
   (`docs/PROGRESS_LOG.md`, "Edge app"; `edge_app/README.md`). Left: the
   owner and team test door counting with people and in a van, run the
   Realme checklist, and the per-stop cabin snapshot (brief 5.2 item 6)
   as its own server-and-phone step.
4. **A2Z's numbers** (the owner asks A2Z): `depart_zone_radius_m`,
   `depart_readings`, `home_pickup_max_route_m`, `special_trip_speed_kmh`,
   per-stretch speed limits, the real routes, fares, timetable and SOS
   numbers, and `docs/QUESTIONS_FOR_COOPERATIVE.md`.
5. **The manuscript** (the owner): paste `MANUSCRIPT_CORRECTIONS.md` into
   the `.docx`.

For the demo itself: `docs/DEMO_SCRIPT.md`.


---

## Known issues

`docs/KNOWN_ISSUES.md`. Read it before touching the manuscript, the SOS
numbers, seat-hold expiry in `seat_repository.py`, or a release build.

---

## Open questions for the cooperative

`docs/QUESTIONS_FOR_COOPERATIVE.md` (updated 18 Oct): hand that one over,
printable in English, Tagalog and Bisaya. Part A is four questions for any
dispatcher; Part B is eleven for the Terminal Manager or office, covering the
settings that ship unset (`depart_zone_radius_m`, `home_pickup_max_route_m`,
`special_trip_speed_kmh`, stretch speed limits) and the brief's §4.6 open
points, and what A2Z checks before validating a record (Q15); then the
documents (routes, fares, timetable, vans, Dispatchers).
Its last paragraph maps each answer to the setting it fills.

---

## Working style

Ask before large refactors. Prefer patching a file in place over
regenerating it — a regenerated file silently reverted the same
`DATETIME(fsp=6)` fix four times.

After replacing any file, `git diff` before running anything.

When something fails over the network, an empty server log is itself the
diagnostic: the request never arrived. Check the port, not just ping —
ICMP passing proves a route exists and nothing more. `ufw` blocked port
8000 for an hour on this machine.
