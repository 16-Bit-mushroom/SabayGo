# SabayGo

Capstone project: a booking and fleet-management system for terminal-based
UV Express vans in Davao City, with A2Z Transport Cooperative as pilot
partner. BSIT, University of Mindanao.

**Development deadline 27 September 2026. Final defence 20 October.**

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
| `docs/RULES.md` | Business rules vs application rules, in plain language |
| `docs/HOW_IT_WORKS.md` | Same, written for the cooperative and the panel |
| `docs/REMAINING_WORK.md` | What is left, grouped |
| `docs/MANUSCRIPT_CORRECTIONS.md` | Where the paper and the code disagree, with replacement wording |
| `docs/FLUTTER_PHASE1_ISSUES.md` | 20 documented setup failures and fixes |
| `backend/app/infrastructure/repositories/seat_repository.py` | The thesis. Read its docstring before touching it |
| `docs/MODEL_EVALUATION_EXPLAINED.md` | The model metrics in plain language, with the talk track for the adviser |
| `ai_service/eval/README.md` | How the YOLOv8 model is evaluated, and why those metrics and not others |

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

**Space (not seat)** — capacity is counted per leg. UV Express does **not
assign seat numbers**; `seat_number` in the database is an internal slot
counter and is never shown to a passenger.

This is why one space can carry two paying passengers on one trip when
their journeys do not overlap — which is real revenue a paper logbook
cannot capture.

---

## Roles

| Role | Who |
|---|---|
| `passenger` | The commuting public. Self-registers |
| `conductor` | Crew aboard. Scans, logs cash passengers, remits |
| `driver` | Same as conductor plus a licence record |
| `coop_admin` | Cooperative office staff. Web console only |
| `admin` | System administrator — the development team |

**Never call `coop_admin` "operator."** Under LTFRB usage an *operator* is
the franchise holder — the CPC holder, usually the van owner — which is a
different party from office staff. This was renamed deliberately in
migration 010.

---

## Stack

```
db/           MySQL 8.0 in Docker, host port 3307. Migrations are truth.
backend/      FastAPI, async SQLAlchemy 2.0, Clean Architecture
ai_service/   Flask + YOLOv8 headcount, port 5000
mobile/       Flutter: passenger, conductor, driver
operator_console/  Flutter Web: coop_admin only
```

Package name is still `mobile_v2_uv_express` though the folder is
`mobile/`. Renaming would touch every import; not worth it.

---

## Running it

On a machine that is not set up yet, `./setup.sh` does the whole thing and
`docs/SETUP.md` explains it. Everything below assumes it has been run.

**`./run.sh` starts the whole system in one command** and is what the demo
uses. It resolves this machine's LAN address once and hands the same
address to every process — backend CORS, console, handset, capture app —
because four hand-maintained copies of an IP address is what broke the
last demo.

```fish
./run.sh                      # db + backend + AI node + console
./run.sh --mobile --capture   # also the two handset apps, on an attached device
./run.sh --host 10.0.52.117   # force the address, when detection picks the wrong NIC
./run.sh --soon               # rebuild demo data, trip departs in 20 min
./run.sh --reset-db           # rebuild demo data; live trips dated from now
```

`002_demo_dataset.sql` seeds three **live trips dated from the moment of
the reset**, so reset shortly before a demo: `TRIP-A2Z-LIVE-BOARD`
(boarding, the dev conductor@/driver@, passenger@ holds a ticket; leg 1
manifest = 4, so photograph 4 people for a match and 5+ for a flag),
`TRIP-A2Z-LIVE-DEPART` (departed, roadside pickup, a no-show) and
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

Handset apps (`--mobile`, `--capture`) are built with `flutter build apk
--debug`, installed with `adb install -r` (keeps app data, so the conductor
stays signed in) and launched, one after the other, before the launcher
reports "up". They are not left under `flutter run`: two of those at one
phone queued on Flutter's startup lock, and stopping the launcher killed
both mid-Gradle with nothing installed. An installed app outlives the
launcher. When the venue's network
changes, re-run `./run.sh` — or, on a handset whose app is already
installed, press **Find server** in the capture app, which sweeps its own
/24 for the backend's `/health` and re-points itself with no rebuild.

Piece by piece, when one component is being worked on:

```fish
# database
docker compose up -d
./db/reset-dev.sh              # clean state, trip departs tomorrow 05:30
./db/reset-dev.sh --soon       # departs in 20 min, so check-in is testable

# backend — 0.0.0.0, not localhost, or the phone cannot reach it
cd backend && source venv/bin/activate.fish
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# AI node
cd ai_service && source venv/bin/activate.fish
export (grep -v '^#' .env | xargs -L1)
python app.py

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

Dev accounts: `passenger@` `conductor@` `driver@` `coopadmin@sabaygo.dev`,
password `sabaygo123`.

The shell is **fish**. `set VAR (cmd)` not `VAR=$(cmd)`; no heredocs —
wrap them in `bash -c '...'`.

---

## Rules that are not obvious

**Migrations define the schema; ORM models describe it.** Never run
`create_all()`.

**`seat_repository.allocate_seat()` locks coarsely on purpose.** It locks
the whole candidate window rather than using a single
`GROUP BY ... FOR UPDATE`, because MySQL's locking semantics with GROUP BY
and LIMIT depend on the query plan — poor ground for a correctness claim.
Read the module docstring before "optimising" it.

**Sandbox payments in development.** With `ENVIRONMENT=development` and no
`PAYMONGO_SECRET_KEY`, checkout returns a backend-served page
(`/payments/sandbox/{cs_id}`) instead of PayMongo. Pay builds a
PayMongo-shaped event, signs it with `PAYMONGO_WEBHOOK_SECRET`, and sends
it through the same `_receive_webhook` verify-then-settle path as the real
webhook, so the rule below still holds. References are prefixed
`cs_sandbox_` / `evt_sandbox_`; no payment method is recorded. Production,
or a real key, turns the sandbox off (404). See
`infrastructure/clients/sandbox_checkout.py`.

**Only a verified webhook confirms a booking.** Never the client redirect.
Signature is HMAC-SHA256 over `{timestamp}.{raw_body}` — the *raw* bytes,
because re-serialising the parsed JSON changes key order and the signature
never matches.

**Policy values are snapshotted onto each trip at generation.** Changing a
policy must not alter terms a passenger already booked under. The
reschedule check reads `trips.reschedule_cutoff_hours`, not the live row.

**The AI node never fabricates a count.** If the camera is unreachable the
endpoint returns 502. An earlier prototype substituted `visual_count = 1`
and displayed it as real, which would flag an innocent driver on an
invented number.

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

**Cash is not missing money.** A cash walk-in writes a `pending` payment
row so the revenue view can separate `cash_in_hand` from `unreconciled`.
Before this, every honest conductor appeared to be stealing.

---

## Domain invariants — do not "improve" these

- Every booking has a fixed space. Terminal-based dispatch, not hail-and-ride.
- Fares come from a pairwise terminal matrix per LTFRB approval. Not
  distance-based, not dynamic.
- Reschedule keeps the same journey; only the trip changes. Follows from
  no-refund — a cheaper journey would owe money back.
- No refunds. Cooperative policy.
- Roadside pickup is normal. Recorded from the **previous** terminal
  passed, with a conductor-set fare. Anchoring forward would leave that
  stretch of road looking empty while someone sits in it, and the camera
  check would flag a real passenger as leakage.

Changing any of these is a schema migration, not a config change.

---

## State as of 15 September 2026

### Backend — complete

Schema (13 migrations) · JWT auth · segment booking with pessimistic
locking · PayMongo checkout and verified webhooks · cash remittance ·
geofenced check-in (window against the passenger's own stop, undoable) ·
QR boarding · manifest · driver headcount · YOLOv8
audit · revenue reconciliation · trip generation · fleet/crew/route/fare/
policy CRUD · scheduling conflict detection · NAHGM live tracking ·
`GET /trips/assigned` for crew · in-app notifications (`/notifications`),
written when a YOLOv8 audit flags a variance — office, driver and conductor
each get a row in the same transaction as the audit log · `GET
/bookings/{id}` · `GET /audits/history` (who closed what, with notes) ·
`GET /revenue/export?format=xlsx|csv` (openpyxl; totals row, About sheet) ·
SOS emergency alerts (`/sos`, migration 016): any signed-in role raises
one, the office and the trip's crew get in-app rows, and the numbers in
the `sos_contact_numbers` policy are texted.

**Automatic AI capture (28 Sep, §2.3.5).** Captures no longer need a
person. `application/audit/auto_trigger.py` fires two system events:
`door_close` when `DepartTripUseCase` closes boarding (leg 1 is final —
no-shows released, everyone aboard), and `gps_node` when `record_ping`
sees the van cross out of a terminal's geofence (leg *k* just entered).
Both fire on *leaving* a node, never arriving: an undocumented passenger
boards at a terminal, and leg *k* is the stretch they are now riding.
Three rules the module exists to keep — one automatic audit per leg
counted over automatic rows only, so a conductor's manual spot check
cannot satisfy the quota and pre-empt the systematic check; the work is
detached, so a departure never waits at the door for a camera and a GPS
ping is never rejected because one is down; and a failed capture writes
no row at all. `POST /audits/trigger` no longer accepts `trigger_type` —
provenance is the server's to set, or the audited party could label its
own audit `gps_node`. The console's audit panel shows the trigger.

Trip search takes `origin_terminal_id` + `destination_terminal_id` and
resolves the stop pair per route (a terminal is stop 2 on one route and
stop 5 on another); the sequence form stays for reschedule (`route_id`
pinned) and the test scripts. `/trips/terminals` is one row per terminal.

Journey suite: **162 passed, 1 failed** (28 Sep) — the one failure is
fixture self-conflict, not a defect. `test_notifications.py` fakes the
camera so E.1 is repeatable.

**Check-in is a heads-up, not a gate** (Group D, decided 15 Sep). The
conductor's manifest shows "AT TERMINAL"; a scan never requires it. The
window is `departure + route_stops.offset_minutes` for the boarding stop,
and `DELETE /bookings/{id}/check-in` withdraws it while still
`checked_in` — the `check_ins` row stays, stamped `undone_at`.

Concurrency experiment: 50 simultaneous bookings, **0 double-bookings**,
advance cap respected. A controlled comparison is recorded — with the cap
checked *outside* the lock, 14 bookings passed a limit of 10.

### Mobile — Phase 2 passenger loop and Phase 3 conductor workflow complete

Done: `ApiClient` with typed exceptions · `flutter_secure_storage` for the
JWT · Provider · role-based routing from the server · registration · trip
search · reserve · PayMongo checkout with status polled from the server ·
real QR from `qr_payload` · geofenced check-in via `geolocator` · my
bookings · reschedule · cancel · conductor trip list and manifest · QR
boarding scan (valid/already-boarded/unpaid/cancelled/wrong-stop/
wrong-trip verdicts) · walk-in and roadside cash logging with a
conductor-set fare · driver/conductor headcount cross-check · depart with
automatic no-show release · cash remittance with variance flagging.

Verified on a physical device on 11 and 14 September: the full passenger
loop (reserve → webhook-confirmed → QR → check-in rejection → cancel →
reschedule → reschedule limit) and the full conductor loop (load assigned
trips → open boarding → scan valid/already-boarded/wrong-stop → walk-in →
headcount, incl. rejecting a negative count → depart with no-shows →
roadside pickup → remit cash with a real variance). No Dart exceptions.

SOS (28 Sep): a red `SosButton` in the conductor manifest app bar and on
the passenger's live-map app bar. Two taps -- icon, then category and
optional note -- so a control used all day cannot fire by accident.
Location is best-effort via `CurrentPosition.tryResolve()` (extracted from
`TicketViewModel`); a denied permission sends the alert without a fix
rather than blocking it. The confirmation repeats the server's own
sentence about SMS delivery and never invents one.

Notifications: passenger tab and a conductor app-bar bell (30 s poll) read
`/notifications`; the console has the same bell in its sidebar, and a
variance alert jumps to the audit queue.

Console (28 Sep): an **Emergency (SOS)** tab -- Open / History, 10 s poll,
Acknowledge and Close-with-a-note, each alert showing its SMS row by row
(sent / failed / skipped, with the gateway's own error). Acknowledging
writes a notification back to the person who raised it, the one message in
the system that flows toward the passenger rather than away. The
notification bell now hands the whole notification to the shell, which
maps kind to tab, so the SOS and variance destinations cannot drift apart.

Console (9 Oct): a **Trips** tab under Operations -- the day's trips from
`GET /config/trips?date=` with live status, crew and counts, and the
selected trip's manifest from the conductor's own `GET /trips/{id}/manifest`
with the conductor app's status words. **My profile** opens from the
account menu at the right of the top bar: name, phone, password via `PATCH
/auth/me`, which now edits staff names too. **Check with phone camera**
(phone capture) lives on the Trips screen, in the selected trip's panel
(`ai_audit_queue/phone_capture.dart`; moved off the Audits tab): enabled only while the trip is boarding or
departed, legs offered by stop name, and the result is reported through
the app-wide messenger by polling `GET /audits/phone/status` -- a matching
capture is filed `reconciled` (History, not the Queue), so the queue alone
could not say it worked.

**Audit readings** (`domain/audit_reading.py`). Every audit response and
list row carries `verdict` / `headline` / `explanation` / `next_step` /
`caution`, derived from the stored counts on read (never stored, so the
wording can change without rewriting the trail). More people than the
manifest reads as possible undocumented boarding; fewer reads as a
camera-view question and explicitly *not* lost revenue. The console's
`AuditReadingCard` shows it on Passenger Count Checks and in the Trips
screen's **Camera passenger checks** panel (`GET /audits/trips/{id}`, open
and closed). `tests/test_audit_reading.py` pins the direction of each
reading.

**Console redesign (9 Oct, branch `console-redesign`).** Dark operations-
dashboard theme, a labelled sidebar in three groups (Today / Money &
checks / Setup, foldable to icons) and a top bar with today's figures
(`core/layout/today_strip.dart`), the bell and the account menu. Pages
were renamed in the office's words, with the technical term kept as a
small note on the page: Live Fleet → **Overview**, Trip Dispatcher →
**Special Trips**, YOLOv8 Audits → **Passenger Count Checks**, Revenue →
**Fares & Cash**, Schedules → **Timetable**, Fleet & Crew → **Vans &
Crew**, Policies → **Rules & Settings**. On screen, manifest → passenger
list, leg → section, variance → difference. Shared pieces are in
`core/design/components/` (`PageHeader`, `Panel`, `StatTile`,
`StatusBadge` with the one trip/passenger word mapping, `LoadError`,
`EmptyState`, `PersonRow`, `BrandPlate`); `auditOutcomeBadge()` in
`audit_reading_card.dart` is the one mapping for a check's review state.
The palette is the console's own now (dark), no longer a copy of
`mobile/`'s light tokens. Full list: `docs/CONSOLE_REDESIGN.md`.

Console (15 Sep): the Audits tab has a Queue / History switch — a closed
audit shows outcome, resolver, time and notes instead of the buttons. The
Revenue tab has an Export menu (`.xlsx` / `.csv`) for the date range shown;
bytes go through the authenticated `ApiClient.getBytes` and
`core/util/download.dart` (`package:web`) hands them to the browser.

Not done: chat.

### Operator console — complete

All coop_admin modules on the live backend (`1708ace`, 14 Sep): Fleet &
Crew, Trip Dispatcher, Schedules, Policy Editor, YOLOv8 Audits, Revenue.
Same `ApiClient` / typed exception / `flutter_secure_storage` shape as
`mobile/`. `GET /config/routes` was added to the backend for its route
pickers. Verified by CDP click-through: 0 exceptions, 0 network errors.

### Hardening — started 15 Sep

- `db/seed/002_demo_dataset.sql`: three more routes (Tagum, Digos, Mati),
  eight crew, six passengers, five vans, departures for three days, and
  two days of completed trips with remittances in every state and audits
  in every state. Placeholders shaped like the Davao network — swap for
  A2Z's own. The fixture in `001` is untouched; `reset-dev.sh` re-dates
  only `TRIP-DEMO-*`.
- The seed surfaced two real defects, both fixed: search was single-route
  (above), and `v_trip_revenue_reconciliation` fanned out — two audit rows
  on a trip doubled its fares (migration 013; the view now aggregates each
  side before joining, and no longer counts `pending` holds as owed fare).
- `backend/scripts/demo_rehearsal.sh` walks the Tier 1 loop in demo order
  and stops at the first failure; `docs/DEMO_SCRIPT.md` is the talk track.
- `datetime.now(timezone.utc)` removed from `payments.py`,
  `register_passenger.py`, `auth.py`, `trips.py` (see Known issues).

### Model evaluation — harness built 8 Oct, numbers not yet generated

The adviser asked for metrics on the YOLOv8 model. `ai_service/eval/`
produces them; read its README before touching any of it, because the
framing matters more than the code does.

The model is **pretrained and unmodified**, so there are no training
curves to report and claiming any would describe work nobody did. What is
measured instead: counting accuracy (MAE, RMSE, signed bias, exact and ±1
rates, stratified by occupancy), **leakage-detection performance** — the
false-alarm rate against an honest crew and the detection rate for 1, 2 and
3 hidden passengers — a confidence-threshold sweep that justifies the
`0.45` default instead of leaving it taste, and latency.

The leakage table is the one to lead with: it is the only number that
speaks to the contribution, and it is pure arithmetic over the same count
errors, verified against hand-computed cases in `eval/test_metrics.py`.

**`inference.py` was extracted from `app.py`** so the harness counts
through `count_people()` — the function the service itself calls on every
audit. A harness with its own YOLO handle and its own thresholds would
publish numbers the running system does not produce. Only the confidence
threshold is overridable, for the sweep. `app.py` keeps the camera, the
HTTP layer and the never-fabricate-a-count error handling; the model load
is now lazy and called explicitly after logging is configured.

Dataset: COCO val2017 (held out — the weights trained on train2017), with
ground-truth counts free from `instances_val2017.json` and **no box
labelling anywhere**. Filtered to 1–14 people, no `iscrowd` blobs, every
person ≥1% of frame, plus 50 empty frames as the false-positive measure.
`degrade.py` adds resolution/brightness/motion-blur/JPEG copies standing
in for cabin conditions.

These are street photographs, not a van cabin — stated in the report's own
closing section and in `MANUSCRIPT_CORRECTIONS.md` §10. A half-day staged
shoot in a parked van at known occupancy closes it; append the rows with
`source=staged` and Table 1b reports them beside the COCO figures with no
code change.

The harness also surfaced a **contradiction in the manuscript**: §2.3.2.1
says `Δ ≠ 0` flags a discrepancy, §2.3.4 says alert when the physical count
*exceeds* the manifest. Those are different rules with very different
false-alarm costs. The code follows §2.3.2.1; see
`MANUSCRIPT_CORRECTIONS.md` §9.

### Non-code milestones — clear

Objectives approved by adviser. Paper revision adviser-approved; research
coordinator reviewing the week of 15 Sep. A2Z reconciled as pilot partner;
alpha testing from 6 Oct.

---

## Next

1. **Hardening, continued** — replace the placeholder routes in
   `002_demo_dataset.sql` with A2Z's real routes, fares and templates once
   they answer; run `scripts/demo_rehearsal.sh` on the demo machine with
   the AI node up; confirm the release build hides the dev-account chips.
   Remaining Group G items (roster, profile edit, account deletion) in
   `docs/REMAINING_WORK.md` if time allows. The van kit (camera, GPS) is
   not a blocker — the laptop webcam and `tracking_simulator.py` are
   verified plug-in stand-ins for both, see `docs/REMAINING_WORK.md`.
2. **Chat** — messages in MySQL, delivered via FCM. Not Firestore: the
   ERD would have a hole where the data model should be.
3. **Auto-detect "Van is at"** — the conductor currently sets the current
   stop by hand on the manifest screen, which is poor UX for someone
   whose hands are full at the door. `geolocator` is already a dependency
   (used for passenger check-in); reuse it to snap to the nearest
   terminal automatically, keeping the dropdown as a manual override.
4. **Phone camera as the AI capture device** — YOLOv8 stays server-side
   in `ai_service` on the server PC, never on the edge device; a phone
   just captures a photo and uploads it there for inference. Needs a new
   `ai_service` endpoint that accepts an uploaded image, since
   `POST /api/audit/capture` only pulls a frame from a server-attached
   camera (`camera.capture()`) — it takes no upload today. The Flutter
   side is a small standalone app, not a `mobile/` feature: take a photo,
   POST it to the new endpoint, show the returned count. Same
   never-fabricate-a-count rule applies — a failed upload or inference is
   an error state, not a placeholder number.

For the demo itself: `docs/DEMO_SCRIPT.md`.

---

### Live map — complete (28 Sep)

NAHGM's client half, the other side of the pipeline in `cfa189c`.
`GET /trips/{id}/stops` now carries each node's `latitude`/`longitude` —
the same coordinates NAHGM map-matches against server-side, so the marker
and the node it was matched to cannot disagree.

Passenger: "Track the van" on the boarding pass opens
`views/tracking/live_map_screen.dart` — route nodes, the passenger's own
boarding and alighting stops picked out, the travelled trail, the van with
its heading, and the ETA list. Polls `/tracking/trips/{id}/position` every
10 s. A trip with no fix yet is *not* an error: the route draws and the
panel says tracking begins at departure. A stale fix is labelled as a last
known position, never dressed up as current.

Console: a **Live Fleet** tab on `/tracking/fleet`, refreshing every 15 s;
selecting a van draws its route. A silent van is chipped `SILENT`.

Route legs are drawn straight between terminals, not snapped to roads —
NAHGM measures haversine hops node to node, and a road-following line
would draw a path its ETAs never came from.

Tiles are **OpenStreetMap via `flutter_map`**, not the Google Maps SDK.
No API key, no billing account and no per-load quota between the panel and
a working demo, and one widget runs on both Android and Flutter Web, so the
handset and the console draw the route with the same implementation. ODbL
attribution is on both maps -- a licence condition, not decoration, so do
not remove it.

Note this contradicts **§2.3.5 of the manuscript**, which says the client
"integrates the Google Maps SDK". That sentence needs rewording to name
OpenStreetMap; the tile vendor is incidental to NAHGM, which is where the
contribution is.

`operator_shell.dart` paired each module with its sidebar entry in the
process — the two parallel lists and the hand-written `_auditsIndex = 5`
would have sent the variance alert to the wrong tab the moment a module
was inserted.

## Known issues

- One journey-test failure is fixture self-conflict: `run_all_journeys.sh`
  resets `--soon` before each journey, so the trip departs in 20 min and
  the 6-hour reschedule cutoff has already passed — 422
  `PolicyViolationError`. `--soon` cannot make check-in and reschedule
  testable at once. Proven not a defect: a direct reschedule call returns
  200, and the passenger journey passes standalone after a plain reset.
  The same applies on the device: the reschedule button is correctly
  hidden on a `--soon` trip.
- The *second* failure here was long recorded as fixture self-conflict
  too. It was not — it was a test bug, fixed 28 Sep. The conductor
  journey reserved its unpaid ticket *after* `start-boarding`, but
  `APP_BOOKABLE` is `{scheduled}`, so the reserve was refused, `UNPAID_QR`
  came back empty, and scanning an empty payload returned `wrong_trip`.
  The unpaid-at-the-door verdict was never actually under test. The
  reserve now happens while the trip is still `scheduled`. Lesson: a
  failing assertion inherited as "known fixture noise" is worth
  re-deriving once.
- The ticket screen polls `GET /bookings/{id}` every 4 s while a booking
  is pending, capped at ~2 min; after the cap it offers a manual "check
  again". A webhook-driven push would remove the poll, but that is FCM.
- Passenger avatar hits `i.pravatar.cc` on every build; fails offline.
- AGP 8.11.1 and Kotlin 2.2.20 are below what Flutter will soon require.
  Deferred deliberately.
- Dev-account chips on the sign-in screen are guarded by
  `AppConfig.isDebug`. Confirm they are absent from a release build.
- The live map needs internet access for OpenStreetMap tiles. OSM's tile
  policy is for modest use and asks for an identifying user agent, which
  both maps send; a defence-room demo is well inside it, but heavy
  automated polling is not.
- **The manuscript claims five things the code does not do.** Google Maps
  SDK (it is OpenStreetMap via `flutter_map`), Firebase Authentication (it
  is JWT), FCM background push (rows are polled; FCM is schema-ready,
  `delivery_status` stays `queued`), Twilio as *the* SOS mechanism (it is
  one of three `SMS_PROVIDER` options and not the default), and "door
  closures" (there is no door sensor). Replacement wording for each, ready
  to paste, is in `docs/MANUSCRIPT_CORRECTIONS.md` — edit the `.docx`, not
  the `.docx.md`, which is a pandoc export and reaches nothing.
- SOS contact numbers are seeded for the demo (28 Sep) in
  `002_demo_dataset.sql`, as two placeholders on the **+63 900** prefix,
  which is not assigned to any Philippine network — so they cannot reach a
  real handset even if `SMS_PROVIDER` is switched off `disabled`. Swap
  them for A2Z's real numbers before the pilot, and only then, because
  from that moment a raised SOS texts actual people. Migration 016 still
  ships the policy **empty**, which is correct for production.
- `datetime.now(timezone.utc)` written into a naive Manila DATETIME
  column skews it eight hours. Fixed in `boarding.py` (14 Sep),
  `trigger_audit.py`, `payments.py`, `register_passenger.py`, `auth.py`
  and the `trips.py` search guard (15 Sep). The only remaining use is
  `seat_repository.py` (seat-hold expiry), left alone because it is the
  thesis file and any change there needs its own review — and
  `security.py`, where UTC is correct because JWT `exp` is epoch time.
- The conductor sets "Van is at" manually on the manifest screen — see
  Next, item 3.
- **The model-evaluation numbers do not exist yet.** `ai_service/eval/` is
  built and tested end to end on sample images, but the full run needs COCO
  val2017 (~800 MB) downloaded via `eval/fetch_coco.sh`. On CPU, budget
  ~100 ms per inference: the whole manifest with all six degradation
  conditions and the five-point threshold sweep is a few hours, so start it
  and leave it. A single-threshold run over original frames only is
  minutes, and is enough to sanity-check the tables before committing to
  the long one. Nothing may be quoted to the adviser until a report file
  exists in `docs/benchmarks/`.
- **There is no physical door sensor.** §2.3.5's "door closures" is
  implemented as the conductor closing boarding and departing, which is
  the closest event the system genuinely observes. Say it that way in the
  paper rather than implying a reed switch on the sliding door; the van
  kit has a camera and a GPS unit, not door hardware. The `gps_node`
  trigger needs no proxy — it is the real thing.
- **Automatic capture needs a camera on the inference host.**
  `door_close` and `gps_node` go through `TriggerAuditUseCase.execute()`
  → `ai.capture()` → the AI node's server-attached camera. On the demo
  laptop the webcam *is* that camera, so automatic audits run end to end.
  In a van with no kit there is no such camera, so they write nothing —
  correctly: `UpstreamServiceError`, a log line, no row, no invented
  count. The phone path is a different method (`ai.upload()`) reached only
  when a person creates a pending request the phone polls for, because a
  handset cannot accept an inbound call — so it is manual-only *by
  construction* and cannot serve an automatic trigger. Do not bridge the
  two: the phone slot is an in-memory single-slot stand-in that retires
  when the Orange Pi arrives. Alpha testing in real vans from 6 Oct will
  produce no automatic audits until the kit is installed.
- Automatic captures are in-process, like `HoldSweeper` and the phone
  capture slot. With more than one backend worker the per-leg check
  against `yolov8_audit_logs` still holds, but the in-flight guard does
  not, so a simultaneous double-fire could write two rows for one leg.
  One more entry for the single-process list in Limitations.

---

## Open questions for the cooperative

Answerable in ten minutes by any A2Z dispatcher. A printable plain-language
version in English, Tagalog and Bisaya is in
`docs/QUESTIONS_FOR_COOPERATIVE.md` — hand that one over, not this list.

1. Do passengers GCash conductors directly? It behaves like cash, but the
   office counts a handover of banknotes differently from one partly in
   an e-wallet.
2. Cancellation deadline — useful, and how many hours?
3. Would knowing in advance who has arrived help dispatch? Check-in is
   built as advisory; this confirms whether dispatch will use it.
4. How far across the terminal compound might a waiting passenger be? A
   terminal is not a point; too tight a radius fails honest passengers.

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
