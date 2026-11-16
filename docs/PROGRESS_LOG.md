# SabayGo build log

What was built, decided and fixed, in order, moved out of CLAUDE.md on
24 Oct 2026 so it is read when needed rather than every session. The
newest step is at the end; record each finished step there.

---

## State as of 15 September 2026

### Backend — complete

Schema (13 migrations) · JWT auth · segment booking with pessimistic
locking · PayMongo checkout and verified webhooks · cash remittance ·
geofenced check-in (window against the passenger's own stop, undoable) ·
QR boarding · manifest · YOLOv8
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
wrong-trip verdicts) · walk-in cash logging (roadside logging and the
conductor-set fare removed 13 Oct, rev 468) · depart with
automatic no-show release (moved to the office console 14 Oct, rev 468) · cash remittance with variance flagging.

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
The palettes are the console's own now, no longer a copy of `mobile/`'s:
`AppPalette.dark` (default) and `AppPalette.light`, switched by the
sun/moon button in the top bar (`core/design/appearance.dart`, saved in
`localStorage`). `AppColors.x` are getters over the palette in use, so
**a colour cannot appear inside a `const` expression** -- the compiler
says so. A switch redraws every widget with `reassembleApplication()`
(the hot-reload path, active in release), because many widgets that read
colours are `const` instances an ordinary rebuild would skip; state is
kept. Full list: `docs/CONSOLE_REDESIGN.md`.

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


---

## Redesign — paper revision 468 (decided 13 Oct)

After the research coordinator's consultation and the A2Z interview, the
study is now a **revenue audit**: A2Z takes 15 % of each van's gross fares
daily, and door events (boardings and alightings) matched to QR scans and
cash logs find fares that never entered the record. The spec is
`docs/SabayGo-Changes-for-Claude-Code (1).md`; what exists against it is
`docs/GAP_REPORT.md`. **Where they conflict with anything below, the brief
wins.** Decisions:

- Build the brief in its own order (section 13), Kotlin edge app last,
  after a phone is benchmarked.
- **YOLOv8n + ByteTrack run on the in-van phone** (paper design). The
  phone sends door events and a blurred still as evidence, no video. This
  reverses "YOLOv8 stays server-side" in Next, item 4.
- **Unrecorded boardings are priced from the nearest stop** (brief 6.1,
  configurable). This reverses the "previous terminal" roadside invariant.
- **14 is passenger capacity per van, counted per stretch, as built.** A
  space freed when someone alights may be resold, but only to a boarding
  at a terminal stop.
- **The Dispatcher cannot log a roadside passenger at all.** Cash
  walk-ins are terminal-stop boardings only. A roadside boarding is seen
  only by the camera: an unrecorded boarding, priced from the nearest
  stop, flagged as a side pickup. Built 13 Oct: `POST /bookings/walk-in`
  refuses `is_roadside_pickup` (422), every fare comes from the fare
  table (no Dispatcher-set fare), and the app has no roadside mode. The
  camera half arrives with the door-event pipeline.
- Keep JWT, polled notifications and OpenStreetMap; the paper is
  corrected, not the code.
- Contribution statement follows the brief (revenue audit, Equation 2,
  hash chain, NAHGM driving flags), not segment booking.
- Repo keeps snake_case names; map paper names to them in docs.
- Every new migration ships a `db/migrations/down/` script;
  `./db/rollback.sh <version>` runs it.

Done: migration 017 — `conductor` → `dispatcher`, `coop_admin` →
`terminal_manager`, new `cashier`, `trips.conductor_id` → `dispatcher_id`,
`operators` roster table (no login), `vans.operator_id` UNIQUE. Driver
accounts became operator rows and were deactivated; the contraction is
migration 020 (below).

Done: migration 018 — the brief's new tables (28–39, less 26, 27, 33):
`route_stretches`, `edge_devices`, `device_checkouts` (one open
check-out per phone and per van, functional unique indexes),
`passenger_events`, `driving_events`, `special_trip_requests`,
`remittances` (daily, per van), `remittance_lines`, `data_transfers`,
`disputes`; plus `operators.import_batch_id` and Table 31's two columns
on `trip_location_pings`. The paper→repo name map is the migration's
header. Schema only, no ORM models or code yet.

Done: migration 019 — the brief's 7.3 column edits, expand only. `trips`:
`route_id` may be NULL (a van rental = `is_special_trip` and no route;
`is_special_trip` alone still marks the office's extra departures), plus
assignment, start, review, audit, departure-source and change columns
(brief 4.3) and the operator name/licence/plate copied at start
(backfilled for trips that already ran). `vans`: validation, import
batch, four photo URLs. `staff_profiles`: the Dispatcher's validation and
import batch. `bookings.logged_by`: who recorded a walk-in (written by
`POST /bookings/walk-in`). Ten new notification types. Decided 13 Oct and
**not** stored: booking origin/destination terminals and payment status
(derived from stop sequences and `payments`), and `fare_matrix` stays per
route by stop sequence — both written up in `MANUSCRIPT_CORRECTIONS.md`
§11. Left for the settings step: `cooperative_policies` + `effective_from`
(Table 33).

Done: migration 020 — the contraction. Dropped: the `driver` role value
(users, notifications, SOS), `driver_credentials`, `trips.driver_id`,
`schedule_templates.default_driver_id`, the roadside/manual-fare booking
columns, and `driver_headcounts` with the Dispatcher's manual headcount
(endpoint, dialog, tests): a self-report by the person being audited that
nothing read; the camera's per-stop snapshot is the brief's drift check.
The revenue view no longer sums roadside columns and LEFT JOINs routes (a
rental has none). A preflight stops 020 before any change on a database
with driver accounts or other history it would lose. The timetable's
default van and Dispatcher went in 022 (step 4).

Done: brief step 3, settings and roster (migration 021, 14 Oct).
`cooperative_policies` is Table 33: keyed (`policy_key`, `effective_from`),
a change is a new row with `updated_by`, the value in force is the latest
row that has taken effect. **Read policies only through
`PolicyRepository`** — a bare lookup by key finds an arbitrary old row.
Value rules (type, bounds, choices) are `domain/policies.py`. New keys:
`start_opens_minutes` 30, `start_grace_minutes` 10,
`heartbeat_gap_seconds` 120, `remittance_rate_pct` 15.00,
`retention_mode` / `retention_days` shipped unset (no default in the
paper; unset must delete nothing). `vans.operator_id` NOT NULL: a van is
created with its operator. Roster (`api/v1/fleet.py`): operators CRUD;
`PATCH .../validation` on operators, vans and Dispatchers (Terminal
Manager); a van validates only with its four photos (`PUT
/fleet/vans/{id}/photos/{side}`, bytes sniffed, `media/vans/`); any edit
or new photo returns a validated record to Pending; whoever imported a
record cannot validate it (brief 3). Plate, licence and CPC formats are
value objects (`ABC-1234`, `N01-23-456789`; CPC is a placeholder rule).
Import/export (`api/v1/roster.py`, `application/roster/`): template
CSV/XLSX, preview, confirm re-checks the file, passing rows saved Pending
under one batch, rejected rows + reason kept in `backend/storage/`
(git-ignored) for re-upload; operators and vans only. Export CSV or PDF
(fpdf2, new dependency), backup columns re-import as-is, `ltfrb_check`
is vans only; every import and export logged in `data_transfers`. Phone
pool (`api/v1/devices.py`): Terminal Manager adds and retires, office
checks out to a Dispatcher and van and records the return; one open
check-out per phone and per van; the phone's last report comes back as
warnings, never a refusal. Console: the add-van dialog picks the operator
and can add one; the rest of Member Records, Phones and the settings
history screen are step 9. Test: `tests/integration/test_roster.sh`
(94 checks, in the journey runner).

Done: brief step 4, trip lifecycle (migration 022, 14 Oct). The rules
live in `application/operations/trip_lifecycle.py` (read its docstring);
the endpoints are in `api/v1/operations.py`. The generator creates trips
days ahead with **no van or Dispatcher**, and skips a departure already
past; 022 dropped `schedule_templates.default_van_id` /
`default_conductor_id`. `PUT /trips/{id}/assignment` (office) takes a
validated van (validated, active operator) and a validated Dispatcher.
It refuses a clash. A Cashier's assignment alerts the Terminal Manager.
Special trips assign through the same path. `POST .../start` (office)
opens `start_opens_minutes` before departure and needs both assigned. It
copies operator name, licence and plate onto the trip, and warns (never
refuses) on an expired licence, no phone out with the van (→ Unaudited
`no_phone` + alert to the Terminal Manager, Cashier and Dispatcher), or
the Dispatcher's phone being on another van. **The Dispatcher no longer
starts or departs**: scanning and cash work on a scheduled trip once
assigned, and the app's only lifecycle action is **Arrived**
(`POST .../arrive`, departed → completed). `POST .../depart` (office)
needs a started trip and records `departure_source`. The fallback is
`start_overdue_trips`, a `PeriodicJob` (`core/periodic.py`, which now
runs the hold sweep too). At departure + `start_grace_minutes` it starts
the trip with its assigned van (`auto_assigned`, review `pending`,
'Unconfirmed Trip Start', "No Dispatcher" when none). With no van it
raises 'Trip Not Started' once. It reaches back 12 h at most. A GPS ping
leaving stop 1 with a boarding counted starts the trip if nobody did,
then departs it as `detected` (`nahgm.record_ping` →
`van_left_origin`). Terminal Manager only: `start-review`, `change-van`
(started trips) and `void` (scheduled or boarding), each with who, when
and why, earlier van and operator in `change_note`. Voiding notifies
ticket holders and refunds nothing. Console: the Trips page's **Start
and departure** panel (`trip_monitor/trip_lifecycle_panel.dart`); the
Timetable lost its crew pickers; trip alerts open Trips. Demo seed:
vans and Dispatchers validated (VAN-0007 stays pending); upcoming
timetable trips unassigned; today's departures already past are seeded
completed. Test: `tests/integration/test_trip_lifecycle.sh` (80 checks,
in the runner). **Fixed on the way:** a cash walk-in was created
`confirmed`, so Depart made it a no-show and released a space someone
sat in. It is created `boarded` now.

Waits for step 5 (needs the phone's reports): `auto_detected` starts,
`silent_at_start` / `lens_blocked`, completion when aboard reaches 0,
and boardings counted from door events rather than bookings. Waits for
step 6: the statement leaving out `pending` starts and creating fare
lines at review. A GPS-not-working phone warns only: no Unaudited reason
fits (4.4 lists four, none for GPS).

Done: brief step 5, server half (migration 023, 14 Oct).

**Phone authentication.** Each phone has its own token, sent as
`X-Device-Token`. The token is shown once when the Terminal Manager adds
the phone (`POST /devices`), and `POST /devices/{id}/token` re-issues it
and revokes the old one. Only its SHA-256 is stored; retiring the phone
clears it.

**API** (`api/v1/edge.py`, every upload a batch that is safe to resend):
- `GET /edge/session`: server time for the phone's clock, its van and
  Dispatcher, the silence gap.
- `POST /edge/heartbeats`: one `device_heartbeats` row per report, so
  the reports a phone stored offline can be judged.
- `POST /edge/events`: door events, keyed by the phone's own `event_id`.
- `PUT /edge/events/{id}/snapshot`: the blurred still, saved to
  `storage/snapshots/` (not the public `/media`) with its SHA-256. It is
  never replaced.
- `POST /edge/fixes`: GPS readings, which go on the trip of the van at
  that time and through `TrackingService.record_ping`.

A batch dated more than 2 min ahead is refused whole.

**Which trip an event belongs to** (`application/edge/ledger.py`): the
van the phone was checked out with at the event's time, then that van's
started trip covering that time, or else its next trip whose start
window was open. Matching is by time, never by what is open at upload,
because a phone offline all trip uploads afterwards. An event with no
such trip goes to `held_door_events` (rule 12) and raises 'Trip Not
Started' once per van. A trip's start moves the held events it claims.

**Unaudited** (`application/edge/evidence.py`, read its docstring): at
the start, `no_phone`, `silent_at_start` or `lens_blocked` (a covered
lens or a camera not working). During the trip, a covered lens is
marked at once. A silence is alerted at once by the `Phone silence`
`PeriodicJob`, but marked `lost_en_route`, from the start of the gap,
only if the stored reports the phone sends on reconnecting leave the
gap open, or the trip ends first. A report covers time only when the
camera and the GPS both worked.

**Detected departures.** "Boarding counted" now includes door events.
When a phone has held boardings at a terminal and its van then leaves
that terminal with no trip, `TripLifecycle.detected_start` takes action
(rule 7, `auto_detected`, held for review, then departed as detected):
- it gives the van the trip on its own route from that terminal still
  waiting for a van, nearest in time;
- otherwise it creates an **"Unscheduled run"** (special trip, no
  template) on the van's route, starting from the first boarding.
- This answers brief 4.6's open question for vans running outside the
  timetable. Nothing a phone counts is lost, and a person decides at
  review what the run was. When the route cannot be told (the van's
  route does not start at that terminal), the events stay held and the
  Terminal Manager is alerted.

Image sniffing is shared in `core/images.py`. Test:
`tests/integration/test_edge_ingestion.sh` (66 checks, in the runner),
which plays four phones.

**Handoff, 14 Oct: steps 6–9 are next and need no phone.** Two tracks
now run side by side. The phone track (below) stays with whoever holds
the Realme. Steps 6–9 are server and console work against tables and
endpoints that already exist: build them in the brief's order (§13).
The phone's interface is `/edge/*`, done and tested, so a test plays
the phone the way `test_edge_ingestion.sh` does: add a phone
(`POST /devices`, token shown once), check it out to a van, then
`POST /edge/events`, `/edge/fixes`, `/edge/heartbeats`.

- **Step 6: matching, hash chain, alerts, remittance, disputes.** Read
  brief §2.1–2.4 (money, fare lines, capacity, boarding rule), §6.1–6.2
  (matching, the four phases) and §12 (acceptance tests, sample trip in
  §12.1). Tables are migration 018 (`passenger_events`,
  `remittances`, `remittance_lines`, `disputes`). Also due here, from
  step 4: the statement leaves out `pending` starts, and fare lines are
  created at review. Check whether boardings and completion ("aboard
  reaches 0") should now come from door events. **Open: the hash
  chain's genesis value** (brief §6.2 `EventHash`, marked [OPEN]). The
  brief advises one derived from the trip ID and so does Claude; the
  owner has not answered yet. Ask before writing the chain; the rest of
  step 6 does not wait on it.
- **Step 7: retention job** (brief §4.5, test T18 in §12.2), after the
  hash chain works. It skips trips with an open dispute, keeps
  `SnapshotHash` when it deletes a still, and must delete nothing while
  `retention_mode` / `retention_days` are unset (they ship unset). Run
  it as a `PeriodicJob` (`core/periodic.py`).
- **Step 8: driving flags** (brief §6.3–6.4) into `driving_events` from
  the GPS readings. `POST /edge/fixes` already feeds
  `TrackingService.record_ping`; `scripts/tracking_simulator.py` drives a
  trip without a van.
- **Step 9: screens** (brief §9). Already there: the Trips page's Start
  and departure panel (step 4) and the add-van dialog. Deferred to here
  from step 3: Member Records, Phones, the settings history screen.

The usual rules hold: the brief wins over this file; every migration
ships a `db/migrations/down/` script; read policies only through
`PolicyRepository`; run the one test script for the feature, add it to
`run_all_journeys.sh`, and record what is done here.

**Next: brief step 5, the phone half.** A2Z allows a camera in the
cabin (confirmed 14 Oct). The Realme phone is not a clean device: 17
user apps and 97 of 107 GB used. **Decided 14 Oct:** develop and
benchmark on it as it is, factory-reset it at deployment. The benchmark
report states the background apps, and a short re-run after the reset
confirms its figures. Storage is not a constraint (the app needs under
100 MB, a day offline about 100 MB, 1 GB at the 2 MB snapshot cap).
Work in this order:

1. **Set up the phone.** *Done 14 Oct:* `adb devices` lists it
   (RMX3241, Android 13), authorised over USB, and `adb install` works
   without the permission-monitoring toggle.
   - Settings → About phone → Version: tap *Build number* 7 times.
   - Developer options: turn on USB debugging (and *Disable permission
     monitoring* if `adb install` is blocked).
   - Plug the phone into this laptop and accept the prompt;
     `adb devices` (`/usr/bin/adb`) should list it. The Android SDK is
     at `/opt/android-sdk`; Java is 17.
2. **Record what the phone is.** *Done 14 Oct:* realme 8 5G, Android 13,
   Dimensity 700 (MT6833), 7.5 GiB RAM, 10 GB free; written into brief
   5.1 and `GAP_REPORT.md` §5. Read
   `adb shell getprop ro.product.model`, `ro.build.version.release`,
   `ro.soc.model` (or `ro.board.platform`), and the total in
   `/proc/meminfo`. Write them into the docs, replacing the brief's
   "[OPEN] exact model" placeholder (5.1).
3. **Benchmark before anything else.** Export YOLOv8n to TFLite at 320
   and 416 px (`ultralytics` in the `ai_service` venv). Build a minimal
   native Kotlin app (new folder, separate from `mobile/`, brief 5.3)
   with CameraX and TFLite. It logs inference time, battery temperature
   and level to CSV over a full trip on vehicle power. The report goes
   in `docs/benchmarks/`. No frame rate is stated anywhere until that
   report exists.
   *Built 14 Oct, not yet run:* `edge_app/` (read its README). Export is
   `edge_app/tools/export_models.sh`, its own Python 3.13 venv, not
   `ai_service`'s (litert-torch targets 3.13; that venv is 3.14). Runtime
   is LiteRT 2.3 `CompiledModel` (GPU only exists there), so the app uses
   Kotlin 2.3.21, not `mobile/`'s 2.2.20. Sweep (4 backends × 2 sizes)
   and Run (until Stop, the trip); `tools/summarise_benchmark.py` turns
   the CSVs into the report's tables. Realme refuses `pm grant`: allow
   the camera on screen at first launch.
4. **Then the edge app** (brief 5.1–5.3) against `/edge/*` above:
   - door line and seat mask, ByteTrack, the offline queue, heartbeats
     every 30–60 s, clock sync from `GET /edge/session`, and the
     blurred still;
   - the Realme setup checklist: auto-launch, background activity,
     battery optimisation off, Location "Allow all the time".

### Rev 603 progress (roadmap R1–R10, `docs/GAP_REPORT.md` §9.4)

Done: **R1, migration 024** (15 Oct). Drops the rev 514 estimate and
side-pickup columns (preflight refuses a database where they hold
data); `departure_source` is now `dispatcher`/`staff`/`gps` (old rows
mapped); new `trips.payment_status`, `list_locked_at`, `crew_aboard`,
`payment_override_*`; `passenger_events.pre_departure`, `chain_seq`,
`resolution_status` (`not_needed`/`pending`/`listed`/`explained`) +
`resolution_note`; `remittances.held_share`, `handed_over_by`;
`remittance_lines.is_top_up`; walk-in special-trip columns; booking
home-pickup flags; image columns on the existing chat `messages` (014);
Tables 40 `non_passenger_moves` and 41 `assisted_pickups`; four new
notification types. Policies: `start_grace_minutes` and `retention_mode`
gone, `retention_days` 30, new `match_window_seconds` 120,
`home_pickup_wait_minutes` 10, `chat_image_max_kb` 10240,
`chat_image_retention_days` 30, and **unset** `depart_zone_radius_m`,
`depart_readings`, `home_pickup_max_route_m` (unset = no GPS departure,
no home pickup offered). The grace-timer job is gone with its key. ORM
models for the money tables (remittances, lines, disputes, special trip
requests, Tables 40–41) come with the step that uses them. Rollback
verified to the exact pre-024 schema.

Done: **R2, boarding at the starting terminal** (15 Oct). The rule is
`Segment.from_starting_terminal` (`domain/value_objects.py`), used by
reserve, walk-in, reschedule, search and availability; the plain
`Segment(...)` still rebuilds a stored booking (cancel), which may
predate the rule. Search by terminals offers only routes that start at
the origin. Cash listing closes at departure (`CASH_BOOKABLE` =
scheduled, boarding). `seat_repository.py` untouched: with every
boarding at stop 1 the per-leg count is the per-van count. Test:
`test_roadside.sh` (21 checks, now in the runner). Left for R10: the
Dispatcher app still offers a "Van is at" stop for walk-ins; the server
refuses anything but stop 1.

Done: **R3, lifecycle rework** (15 Oct). Built:
`application/finance/statement.py` (read its docstring: fare lines follow
the list, lock at payment or departure, top-ups, held share, statement
recomputed from lines, undisputed balance), `api/v1/statements.py`
(`GET /trips/{id}/share`, `POST /trips/{id}/payment` Cashier only,
`GET /statements?date=`, `POST /statements/{id}/payments`), Start
refused while the trip's statement owes, assignment refused while the
van owes, `POST /trips/{id}/payment-override` (Terminal Manager, note;
lifts both blocks for that trip), Depart by the assigned Dispatcher or
the office (`dispatcher`/`staff`), refused while an unlisted boarding is
pending; departure locks the list and marks `left_unpaid` + alert;
GPS departure = last N readings outside the terminal zone, moving
(`TrackingService.left_zone`, off while the two survey settings are
unset); migration **025** holds a no-trip van's readings (`trip_id`
NULL) and `release_held` moves them; `PUT /trips/{id}/crew`;
`non_passenger.py` + `POST /non-passenger-moves`, `.../{id}/end` (ends
itself when the van is back in a terminal zone); Unscheduled run
removed; cancel/reschedule refused once the list is locked; seed: all
boardings at stop 1, every started trip has a paid statement.
`test_trip_lifecycle.sh` rewritten for T1-T21 (129 checks). A van that
leaves with held boardings and no trip waiting gets one 'Trip not
started · van left' alert while its events wait (`ledger.alerted_while_held`),
not one per GPS fix. Tests moved to rev 603: `test_edge_ingestion.sh`
(68; pays before Start, sets the zone settings and sends N fixes, the
Unscheduled-run case became "events stay held, alerted once"),
`test_roadside.sh` (24; the legacy stop-2 booking is made with SQL),
`test_dispatcher_journey.sh`, `test_notifications.py`,
`scripts/demo_rehearsal.sh` (pay before Start). Journey suite **475
passed, 1 failed** (the known `--soon` reschedule cutoff); the
passenger journey's terminal search no longer assumes the fixture
departs today, so it passes 37/0 after a plain reset too.
Pulled forward from R10 (it blocked Start in the console): the Trips
page's Start and departure panel shows the share's state, the Cashier's
**Record A2Z's share** (line by line; before departure on the trip, after
a Left Unpaid on the van's statement) and the Terminal Manager's **Lift
payment block**. `DEMO_SCRIPT.md` row 9a records it as cashier@ in a
private window. The Remittance screen itself is still R10. The old `cash_remittances` flow (Fares &
Cash) is the rev 514 model; retire it with the screens (R10). Seed note:
LIVE-BOARD's leg-1 list is now 5.
Done: **R3b-1, special trips, cash path** (15 Oct). Rules:
`application/operations/special_trips.py` (read its docstring); API
`api/v1/special_trips.py`: `POST /special-trips` (passenger, 1-14),
`GET .../mine`, `POST .../{id}/withdraw` (before approval only); office
`GET /special-trips?status=`, `POST .../walk-in` (counter customer,
approved as entered, fee + note), `.../{id}/approve` (fee + note, creates
the trip: no route, `is_special_trip`, label "Rental · name", no seat
booking), `.../{id}/reject` (reason, told to the passenger); the trip's
Dispatcher `POST .../{id}/cash`. Van and Dispatcher via the usual
`PUT /trips/{id}/assignment` (T52 = re-assign). A paid fee is one fare
line (`request_id`, no drop-off; D for cash), so the 15 % block applies;
**Start also waits for the fee itself, and no override lifts that.** The
request closes with its trip (void → cancelled, arrive → completed).
`NotificationService.notify_passenger` for a passenger alert with no
trip. A rental's length is unknown, so the clash check counts only the
45-min turnaround. Test: `test_special_trips.sh` (in the runner).

Done: **R3b-2, rental fee through the gateway** (15 Oct). No migration:
Table 34 keeps a rental's payment on the request (`payment_status`,
`payment_reference` = the checkout session, NULL for cash), and MySQL
forbids a CHECK on `payments.booking_id` (ON DELETE CASCADE).
`POST /special-trips/{id}/checkout` (the renter, approved and unpaid,
before departure). Checkout clients take `reference` + `metadata`
(`booking_id` or `request_id`); `SettlePaymentUseCase` hands a
`request_id` event to `SpecialTrips.settle_gateway` after the same
signature check, idempotent on the request's state. The sandbox page
finds either kind. A paid fee is a verified (V) line. Rental fees are not
in `payments`, so the rev 514 revenue view leaves them out; statements
are the record. `test_special_trips.sh` **70 passed** (forged unsigned
webhook refused, sandbox pay, no double line).
Done: **R4, edge events to the assigned trip** (15 Oct). `ledger.trip_for`
rule 2 is now the van's assigned trip that has not started (earliest,
within 12 h either way), no longer "start window open", so boardings
before Start are kept from the assignment on (rule 14). An assignment
releases held events, as a start does. `GET /edge/session` returns
`counting` + `trip_id` from `trip_for(now)`: the phone counts from
assignment until arrival and pauses otherwise (rule 13; the way back is
not counted). Not done: events already on a trip whose van is taken off
it before Start stay there (the brief is silent). `test_edge_ingestion.sh`
**76**; journey suite **553 passed, 1 failed** (the known `--soon`
reschedule cutoff).
Done: **R5a, door events against the list** (15 Oct). Rules:
`application/edge/checking.py` (read its docstring). A boarding before
departure is matched by time (±`match_window_seconds`) to a valid QR scan
or a cash entry, each used once, nearest first: `matched_qr` /
`matched_log`, else `unlisted` + `pending`. Recomputed from stored rows on
every check, so arrival order does not matter; the Dispatcher's fixes and
reasons are kept. **Depart is gated on the count, not the events:**
aboard (boards − alights before departure − crew) against listed (paid
seats, home-pickup seats only once boarded) + explained. Fix = walk-in
with `for_event_id` (→ `listed`, the booking named; migration **026**
widened `chk_event_booking_only_if_matched` for it, with down script);
reason = `POST /door-events/{id}/explain`. `GET /trips/{id}/door-check`
is the Dispatcher's screen (rechecks on read). 'Departed With More Than
Listed' once per trip, at departure or when an offline phone's late
upload shows it. After departure nothing is matched or priced.
Test: `test_door_check.sh` (40, in the runner); suite **593 passed, 1
failed** (known). **The Dispatcher app has no screen for this yet
(R10):** until it does, a phone counting more than listed blocks a
person's Depart and only the GPS departs the van.
Done: **R5b, capacity and completion** (15 Oct). `application/edge/
capacity.py` (`Ride.follow`, run after each upload batch; kept out of
`checking.py`, which NAHGM's import chain reaches). Aboard = boards −
alights in time order − crew. Each rise above `seat_capacity` alerts the
Terminal Manager, the Cashier and the trip's Dispatcher once per crossing
(entity = the crossing event), with the time and the place.
`TrackingService.geotag` (brief 6.3): the event's fix, else interpolated
between the trip's readings either side, snapped to the nearest straight
stretch; "at Stop" inside a stop zone, else "between A and B"; stored on
the event (stretch, nearest stop, distance from start). Ready for R9's
driving flags. After departure, an alighting that leaves nobody aboard
completes the trip dated by that alighting (`arrive(at=)`), and the
phone pauses. `test_door_check.sh` **52**; suite **605 passed, 1 failed**
(known).
Done: **R5c, the hash chain** (15 Oct). `application/edge/chain.py`
(read its docstring). Each event entering the ledger gets the trip's next
`chain_seq` and `event_hash` = SHA-256 over trip, seq, the phone's own
fields, `snapshot_hash` and the previous hash; genesis = SHA-256 of
`"sabaygo:" + trip_id`. Order = order of entry (late uploads append), under
the trip's row lock; held events are chained when claimed. Server
readings (match, resolution, geotag) are not hashed, so R5b's geotag no
longer writes `latitude`/`longitude`. **Phone protocol change:** the
phone declares the still's SHA-256 as `snapshot_hash` on the event; the
upload must match it, and an event that declared none takes no still.
`GET /trips/{id}/chain` (office) verifies: holds after a still is deleted
(T39), breaks at the first altered link. `test_edge_ingestion.sh` **85**;
suite **614 passed, 1 failed** (known).
Done: **R6a, home pickup: booking, pin, activation, the stop** (15 Oct).
No migration. Rules: `application/booking/home_pickup.py` (read its
docstring); API `api/v1/home_pickups.py`: `POST /home-pickups` (the
relative, a passenger: trip, drop-off, beneficiary name and contact, pin
+ note), `GET /home-pickups?trip_id=` and `.../{id}/activate`,
`/arrived`, `/close` {boarded | no_show} (the trip's Dispatcher, or the
Terminal Manager). Both seats are reserved **in one transaction**:
`ReserveSeatUseCase.reserve()` is everything but the commit (`execute()`
= reserve + commit), so the pair is kept whole or not at all. Both from
stop 1 to one drop-off; the passenger's seat is `booked_for_other` +
`is_home_pickup_seat`, both owned by the relative, each paid through
`POST /payments/checkout`. The pin is measured against the route from
stop 1 to the drop-off; refused while `home_pickup_max_route_m` is unset
or beyond it. Route snapping and `haversine_m` now live in the pure
`application/tracking/geometry.py` (`snap_to_route`), used by
`TrackingService.geotag` and the pickup; `check_in` and `non_passenger`
import `haversine_m` from there. Activation needs the passenger's seat
paid: a valid scan of the relative's ticket (`qr_scan`, the scan's
message says activated or why not) or by hand (`dispatcher_entry` + who).
`boarding.py`: the passenger's own ticket scans `wrong_stop` ("board at
the pin"); Depart keeps activated pickups' seats and turns pickups not
activated into no-shows (the relative did not come, so the van does not
go). Close inside `home_pickup_wait_minutes` = `closed_early`; a no-show
seat is released and still owed. Cancelling the relative's seat cancels
the passenger's and the pickup; cancelling the passenger's seat cancels
only the pickup; neither seat reschedules (422). Test:
`test_home_pickup.sh` (56, in the runner); suite **670 passed, 1 failed**
(known).
Done: **R6b, the payment screenshot** (15 Oct). No migration. When the
gateway is down the relative sends `POST /home-pickups/{id}/proof`
(multipart `image`): an image message in their chat with the trip's
Dispatcher (opened if new; refused while no Dispatcher is assigned),
which becomes `proof_message_id` (a later one replaces it until
confirmed). `MessagingService.add_image` owns chat images: at most
`chat_image_max_kb` (T41 a), typed from the bytes, kept in
`storage/chat/` (not `/media`), `retain_until` = today +
`chat_image_retention_days`; `MessageOut` now carries the attachment
fields. Images are taken for this proof only (no general image send).
**Holds:** the screenshot re-holds the pair's unpaid seats **until
departure** through `SeatRepository`'s own `release`/`allocate_seat`
(a lapsed hold is taken again, 409 if the van is now full), so neither
the sweep nor `seat_repository.py` changed. `GET .../proof` serves the
image to the relative, the trip's Dispatcher and the Terminal Manager.
`POST .../proof/confirm` is **the trip's Dispatcher only**: the unpaid
seats become confirmed (app seats, so V), `proof_confirmed_*`, 'Home
Pickup Proof' to the Terminal Manager. No `payments` row (its provider
enum has no such kind); the pickup's proof fields are the record. The
proof paths lock trip then pickup (Depart's order) and the pair's
bookings (a concurrent webhook waits). Not built: a reject for a bad
screenshot (the relative sends another; unconfirmed seats lapse at
departure). `test_home_pickup.sh` **84**. Committed as one commit
(`0f44c8a`).
Done: **R7, disputes** (15 Oct). No migration. Rules:
`application/finance/disputes.py` (read its docstring); API
`api/v1/disputes.py`: `POST /disputes` (subject + `line_id` or
`driving_event_id`, the operator's words; the trip's Dispatcher, the
Cashier or the Terminal Manager), `GET /disputes?status=&trip_id=&remittance_id=`
(a Dispatcher names their own trip), `.../{id}/withdraw` (recorders),
`.../{id}/decide` (Terminal Manager: upheld / rejected / adjusted +
amount, note required, final). A fare line is disputable until a payment
is recorded on its statement after the line was written (so a top-up
until its own payment); a driving flag after the trip too, while the
trip has GPS readings; one standing dispute per item (a withdrawn one
does not block). Money, in `statement.py`: an open dispute's share waits
(left out of `due`, so it blocks neither Start nor assignment); upheld
takes the line out of V/D and owed; adjusted makes its share the
Terminal Manager's amount, fares kept; rejected / withdrawn make it due
again, and a trip not yet departed goes back to `unpaid`. A contested
line is frozen (`_mirror` no longer changes it; same-kind seats go on a
new line), and a van change moves the trip's disputes with its lines.
A flag's decision is its review: upheld → `dismissed`, rejected →
`reviewed`; a flag cannot be adjusted. 'Dispute Raised' to the Terminal
Manager. New ORM model `DrivingEvent` (Table 30) for R9. Test:
`test_disputes.sh` (78, in the runner; flags written with SQL). Left
alone: a disputed line whose seat is cancelled before the lock keeps its
count until decided (R3's `_drop` keeps it for the decision). Committed
(`e25fe42`).
Done: **R8, retention** (15 Oct). No migration. Rules:
`application/edge/retention.py` (read its docstring), run hourly as the
`Evidence retention` `PeriodicJob`. Past `retention_days` (from the
event's or reading's own time): a door event's still is deleted (file,
URL; `snapshot_deleted_at` stamped, `snapshot_hash` kept, so the chain
verifies, T36/T39) unless its boarding is `pending` (T37) or its trip has
an open dispute (T40); a held event's still too (held events are claimed
within 12 h); raw GPS readings are deleted unless their trip has an open
dispute or an open driving flag (the flags stay). Chat images go on their
`retain_until` (T41 b); the message stays. `snapshot()` keeps a deleted
still deleted on resend and refuses one past the period.
`GET /door-events/{id}/snapshot` serves the still to the **Terminal
Manager only** (T38; others never get it or its address). Not covered:
the rev 468 YOLOv8 audit snapshots in public `/media` (`audits.py`
`snapshot_url`), retired with the old screens in R10. Test:
`test_retention.sh` (34, in the runner; runs the job with "now" moved
31 days ahead, so nothing hashed is backdated). Committed (`81e0885`).
Done: **R9, driving flags** (15 Oct). Migration **027** (down script):
settings `overspeed_seconds` 10, `stop_seconds` 120, `slow_tolerance_pct`
25, `expected_speed_kmh` 55, `standstill_kmh` 2. The rules are the pure
`application/tracking/driving.py` (read its docstring), replayed on the
paper's sample trip by `tests/test_driving_flags.py` (overspeed 40 s,
pickup wait not flagged, en-route 34 s recorded, unscheduled 244 s at
8,830 m, stretches 0.99 / 1.01 / 1.45). `application/tracking/flags.py`
(`DrivingFlags.review`) recomputes a departed or completed trip's flags
from its readings after every GPS batch (`/edge/fixes`, and the
tracking ping), reconciles by kind + start (a stop or run that goes on
updates its row; a flag no longer found is deleted only while open and
undisputed), geotags new ones and alerts the Terminal Manager and the
trip's Dispatcher (not for en-route stops). The silent-phone gap breaks
an episode. Speed limits per stretch: `GET/PUT
/config/routes/{id}/stretches` (Terminal Manager; lengths along the
straight route line, expected time saved with the stretch); without them
only stops are flagged. Once set, the route's stop zone is NAHGM's stop
zone everywhere (`TrackingService.stop_zones`, geotag too). **Late
readings:** a reading dated before a completed trip's `completed_at` is
now filed on it (`file_late_reading`, no live hooks) instead of ignored,
so a phone offline on the road still has its driving counted. Test:
`test_driving_flags.sh` (27) + the unit test, both in the runner.

Done: **R10a, the server gaps** (15 Oct). Migration **028** (down
script): `driving_events.reviewed_by`, `reviewed_at`, `review_note`.
`GET /driving-flags?status=&trip_id=&date=` (office; a Dispatcher names
their own trip) lists flags with the operator copied at start, the
stretch in words and the standing dispute; `POST /driving-flags/{id}/
review` {reviewed | dismissed (note required)}, Terminal Manager, open
flags only, refused while disputed (the dispute's decision now fills the
same three columns) and for en-route stops. `GET /boarding-audit?date=`
(Terminal Manager; `application/edge/boarding_audit.py`): per trip with
something to review, unlisted boardings before departure (fix with the
destination, or reason, or pending; still kept or not), capacity alerts
(from the alert notifications, aboard recounted, place in words),
'Departed With More Than Listed' and the chain check; `crew_aboard` says
when one unmatched boarding is the Dispatcher's. `GET /fleet/vans/board`
(office; `application/operations/van_board.py`): travelling > out of
service > on site > not on a trip, aboard (door count, None without a
phone), last position, and `owes` (`van_balance`). Shared on the way:
`capacity.aboard_after` (the running count, used by `Ride.follow`) and
`TrackingService.place` (a stored geotag in words, used by `geotag`).
Tests: `test_driving_flags.sh` §7 (49), `test_door_check.sh` §9 (64),
new `test_van_board.sh` (28, in the runner). Decided by Claude (owner
delegated 15 Oct): the Dispatcher records disputes **in the app**, on
their own trip's lines and flags; **Emergencies stays** as built.

Done: **R10b, the console** (15 Oct). New pages (`operator_console/lib/
modules/`): **Remittance** (statements by van and trip, Cashier records
the payment with who handed it over, dispute a line), **Disputes**
(open / decided / withdrawn; the Terminal Manager decides, upheld /
rejected / adjusted), **Boarding Audit** (Terminal Manager; the still
opens through `getBytes`), **Driving Flags** (review, dismiss, record the
operator's dispute), **Review Starts** (the day's trips needing a look,
with the Trips page's `TripLifecyclePanel` beside them), **Van Status
Board** (15 s refresh), **Phones** (add with the token shown once, new
token, retire, check out after the setup check, return). Vans & Crew is
now **Member Records** (operators / vans / staff, validation menus, the
four van photos, import with preview, export CSV/PDF and the LTFRB list,
the transfer log); Rules & Settings has the rev 603 keys in plain words,
each key's history, "not set" shown as off, and **speed limits by
route**. Shared: `core/design/components/actions.dart` (`runAction`,
`askText`, `DayPicker`, `FactLine`, `peso`), `ApiClient.upload`
(multipart), `core/util/pick_file.dart`. Repositories: `money_`,
`oversight_`, `device_repository.dart`. Small server additions for the
screens: disputes carry `trip_label`, `plate_number`, `item`,
`raised_by_name`, `decided_by_name`; statements carry `operator_name`,
the recorder's and hander's names and each line's `trip_departure`;
policies carry `updated_by_name`. Alerts open their page (capacity →
Boarding Audit, flag → Driving Flags, dispute → Disputes, left unpaid →
Remittance). Fares & Cash and Passenger Count Checks still show (R10e).
`flutter analyze`: 0 errors, 0 warnings. **In Claude's bash, `flutter`
is not on PATH: use `$HOME/flutter/bin/flutter`**, or `analyze | grep`
hides "command not found". Tests: `test_disputes.sh` 80,
`test_office_journey.sh` 49 (policy history).

Done: **R10c, the Dispatcher app** (15 Oct). The trip screen
(`mobile/lib/views/dispatcher/trip_manifest_screen.dart`) is the
dashboard; panels in `dashboard_panels.dart`: the camera's count aboard
against listed with **Add to list** (walk-in `for_event_id`, sent at
once, never queued) or **Reason** per unlisted boarding, the **crew**
switch, **Depart** (once started; warns when the van would leave
unpaid), **Not a passenger trip** (reason, End, ends itself back at a
terminal), home pickups (activate, at the pin, boarded / no-show, view
and confirm the screenshot), the rental's cash fee, **A2Z's share** to
hand to the Cashier with the operator's **dispute per line**, and
driving flags with **Dispute** (decided 15 Oct: the Dispatcher records
disputes in the app). The operator shows as name + licence beside the
plate. **"Van is at" is gone**: `ShiftViewModel.currentStop` removed,
scans and walk-ins use `CrewTrip.boardingStop` (stop 1), walk-ins only
before departure. "Remit cash" (rev 514) left the dashboard; its screen
file goes in R10e. Server: `GET /trips/assigned` adds `operator_name`,
`operator_licence`, `payment_status`, `crew_aboard`, `rental`;
`GET /non-passenger-moves/open`. Mobile `ApiClient.getBytes` / `upload`.
Tests: `test_trip_lifecycle.sh` 133, `test_special_trips.sh` 71,
`test_dispatcher_journey.sh` 24. `flutter analyze`: 0 errors, 0
warnings.

Done: **R10d, the Passenger app** (15 Oct). **Request a Special Trip**
(`views/special_trips/`, "Rent a van" in the Home app bar): request
(when, pickup, destination, 1-14), follow, withdraw before approval, pay
the agreed fee through the gateway. **Book for Someone Else**
(`views/home_pickup/`, a button on the booking sheet when 2 spaces are
left): name, contact, a pin on the OpenStreetMap map (tap or "Here")
with a note, both seats reserved, then pay each seat or **send a payment
screenshot** (`image_picker`, new dependency, offline from the pub
cache); the Trips tab's next-trip card shows the pickup and can send a
screenshot later. **Camera notice** on the booking sheet
(`camera_notice.dart`), its period read from A2Z's settings. Server:
`GET /trips/privacy-notice` (signed-in; retention days, chat image limit
and retention, the privacy-contact placeholder); `/bookings/mine` adds
`home_pickup` (pickup id, beneficiary, which seat, proof state) and no
longer offers reschedule on either seat. Tests: `test_home_pickup.sh`
85, `test_retention.sh` 35, `test_passenger_journey.sh` 37 after a plain
reset. `flutter analyze`: 0 errors, 0 warnings.

Done: **R10e, retirements** (15 Oct). Console: **Fares & Cash** and
**Passenger Count Checks** are gone (`modules/revenue`, `modules/
ai_audit_queue`, `revenue_` and `audit_repository.dart`), and so are the
Trips page's rev 468 **Check with phone camera** button and **Camera
passenger checks** panel. The top strip's third chip is now "Boardings
to review" (Terminal Manager → Boarding Audit) or "Vans owing the share"
(Cashier → Van Status Board). App: the Dispatcher's rev 514 "Remit
cash" screen and its calls are gone. Server, decided by Claude (owner
delegated 15 Oct): the rev 514 cash-remittance write path is removed
(`api/v1/remittances.py`, `application/finance/remittance.py`,
`test_remittance.sh`; the `cash_remittances` table and ORM model stay,
no migration); the automatic rev 468 door-close and GPS-node cabin
captures are removed (`application/audit/auto_trigger.py`,
`test_auto_audit.py`): they fed only the retired page, and the phone's
door events are the automatic check now; a rev 468 audit **no longer
stores a still** in public `/media` (closes the T38 gap R8 left open).
Kept on purpose: the manual `/audits/*` endpoints the `ai_capture_app`
uses, `ai_service`, and the read-only `/revenue/*` report and its view
(no client now; retire with the capture app if wanted). `DEMO_SCRIPT.md`
steps 10-14 now walk the rev 603 screens. Journey suite **907 passed, 1
failed** (the known `--soon` reschedule cutoff).

Done: **office Special Trips page** (15 Oct, a §9 gap R10 did not
list). `operator_console/lib/modules/special_trips/`: requests waiting /
approved / closed, **Walk-in request** (customer, pickup, destination,
count, fee and basis note), **Agree the fee** (creates the trip),
**Refuse** with a reason; an approved request shows its trip's Start and
departure panel for assignment. Terminal Manager and Cashier (brief 3).
The rev 468 extra-departure form (`modules/trip_dispatcher`, and the
repository's `TripBoardRow`, `todaysTrips`, `createSpecialTrip`) is
gone: brief 2.5 has no van-outside-the-timetable path but a rental;
`POST /config/trips/special` stays for the tests and seed.

Done: **rental overspeed** (15 Oct, brief 2.5, a gap R9 left: "a
rental has no route: no flags"). Migration **029** (down script): the
setting `special_trip_speed_kmh`, shipped **unset** (no value in the
brief; unset = no rental flagged). `driving.rental_flags` is overspeed
only, against that one limit (a rental has no stretches or stop zones);
the overspeed run is shared as `driving._overspeed`. `DrivingFlags.
review` uses it for a route-less trip. Rules & Settings names it.
`test_special_trips.sh` 75 (unset: no flag; set to 60: flagged, no
stretch); the sample-trip unit test and `test_driving_flags.sh` (49)
still pass.

Done: **Trip Monitoring additions** (15 Oct, brief §9 "the phone's last
report"). `GET /config/trips` adds `door_aboard` (the camera's count,
less the crew; None with no events) and the phone out with the van
(`phone_last_report_at`, `phone_battery_pct`, `phone_silent`; None with
no phone out). The Trips page shows a **Camera count** tile and the
phone's state in the Start and departure panel; the Overview map's
"aboard" uses the camera count when there is one. `test_door_check.sh`
65.

**R10 is done.**

Done: **runner probes and the reschedule failure** (16 Oct, `1169e7b`).
Four "gaps" were done features probed at URLs never built: password
change is `PATCH /auth/me`, account close `POST /auth/me/close`, an
unpaid hold is released by `POST /bookings/{id}/cancel`, who is on what
is `GET /config/trips?date=`. The probes now call them. Passenger lookup,
saved destinations and notification settings are not in rev 603: probes
removed, listed in `REMAINING_WORK.md`. **The long-standing `--soon`
reschedule failure was a reset gap, not fixture self-conflict:**
`reset-dev.sh` zeroed the policy but not the cutoff each fixture trip
copied at generation. It zeroes both now. Suite **922 passed, 0 failed**.

Done: **rev 468 leftovers retired** (16 Oct). Removed: the Flask AI node
(`ai_service/app.py`), `ai_capture_app/`, `api/v1/audits.py` (`/audits/*`
and `/revenue/*`), `application/audit/`, `ai_node_client.py`,
`domain/audit_reading.py`, `NotificationService.notify_variance`, the
`AI_NODE_*` / `PHONE_CAPTURE_API_KEY` settings, and `run.sh`'s AI node
and `--capture`. Migration **030** (down script) removes the
`variance_alert_threshold` setting, which nothing reads now. **Kept:**
`ai_service/inference.py` + `ai_service/eval/` (they measured
`yolov8n.pt`, the weights the phone runs; the harness counts at 640 px,
the phone at 320/416), and the tables (`yolov8_audit_logs`,
`cash_remittances`, the revenue view) as history, no migration.
`test_notifications.py` now drives a rev 603 alert (payment block lifted
→ Cashier) over HTTP. `MANUSCRIPT_CORRECTIONS.md` §3, §7, §9 are marked
superseded and §12 records the rev 603 open points the code settled.

Done: **Edge app** (18 Oct; read `edge_app/README.md`). Migration **031**
(down script): `vans.door_layout` (JSON: door line, cabin side, seat
mask, in frame fractions) + `door_layout_set_at` / `_device_id`; the
layout is the van's, not the phone's, and setting it does not reopen a
validated van. `GET /edge/session` returns it; `PUT /edge/door-layout`
sets it for the phone's checked-out van (409 when none).
`test_edge_ingestion.sh` **92**. The phone (`edge_app/`, v0.2): a
foreground service (camera + location) that counts while the session
says so (or offline with a van, 2 min stale), YOLOv8n CPU FP16 at 320
(416 selectable until the Run), ByteTrack in Kotlin (thresholds 0.45 /
0.1, lost tracks by time), door-line crossings by box centre, the seat
mask, a pixelated still per event with its SHA-256 on the event, GPS
every 1 s, a report every 30 s, a covered-lens check, and an SQLite
outbox sent in order with retry. Benchmark kept behind a button.
14 JVM unit tests (`./gradlew testDebugUnitTest`). Verified on the
Realme against the dev backend: set-up over adb, session, reports and
uploads. **Not yet verified: crossings with people, or in a van.** The
token is typed (or sent by adb on a debug build); a QR entry is not built.

Done: **review fixes** (19 Oct). `POST /tracking/trips/{id}/ping` is
**development only** (404 otherwise) and `TRACKER_API_KEY` is gone: it
accepted unauthenticated readings that could depart a trip or raise
flags, and only `tracking_simulator.py` (run.sh's moving vans) and
`test_trip_lifecycle.sh` post there; the phone uses `/edge/fixes`. T8
(a paid no-show leaves the share unchanged) is now tested in
`test_trip_lifecycle.sh` (135).

Done: **Routes & Fares** (22 Oct, console page, Terminal Manager only;
`modules/routes_fares/`, `data/repositories/route_repository.dart`). No
migration. Terminals: `GET /config/terminals` (every terminal, closed
too, with the active routes through it), `PUT /config/terminals/{id}`
(correct or close; closes only while no active route stops there;
moving one re-measures its routes' stretches, limits kept; a duplicate
name in a city is 409, no longer a 500). Routes: `GET /config/routes`
carries the stops in order and the LTFRB case; create checks stop 1 is
offset 0, offsets never go down and every terminal is open; `PUT
/config/routes/{id}` renames, records the case, takes it out of service
(no search, no generation, no new timetable entry; generated trips stay)
and returns it only while its terminals are open. Stops stay fixed once
saved. Fares: one per drop-off from stop 1 (rev 603), dated, today or
later (a past date is 422); the same day saved again corrects that row;
`GET .../fares` labels each row `in_force` / `scheduled` / `replaced`.
**Read fares only through `FareRepository`** (`infrastructure/
repositories/fare_repository.py`): search, the walk-in preview and the
charge now take the row in force on the trip's service date. Before, a
fare dated ahead applied at once. `test_office_journey.sh` 62.

Done: **Console redesign v3** (25 Oct; brief
`docs/Web-console-redesign/UI-UX-redesign-v3.txt`; direction "The Pila
Board", contract in `.impeccable/surfaces/operator-console-lib.md`). No
backend change, no migration. **Look:** one light palette
(`core/design/tokens.dart`): white page, terminal-green sidebar and
primary, black text, red only for SOS, danger and route pins, every
pairing measured AA; the dark palette and the sun/moon switch are gone
(`appearance.dart` deleted). The map's selection is now marker black, not
lime. **Menu:** seven entries (`core/layout/operator_shell.dart`), related
pages as tabs whose labels are the pages' titles; Reviews' tabs and menu
entry carry counts (`core/layout/review_counts.dart`, the screens' own
endpoints, polled 30 s, no number when a count fails, never 0);
Emergencies pinned at the sidebar's foot. Notifications and the today
strip open the right hub and tab. **Setup** (`modules/setup/`) replaces
Member Records, Routes & Fares, Phones, Timetable and Rules & Settings as
menu entries: a queue of steps judged from the database
(`setup_status.dart`: two open terminals, a route in service, every
drop-off priced, a validated van with a validated operator, a validated
Dispatcher and a Cashier, an active departure, a phone), each step's
records added and edited in a panel beside its list instead of a dialog.
The Cashier sees Operators & vans, Staff and Phones, read-only as before.
`modules/routes_fares/` and `fleet_roster_screen.dart` are removed; their
forms live on in the steps. **Fixes from the screenshots:** a shared
`PasswordField` with show/hide (login, Add staff, My profile); office
accounts show "Not needed" under validation with the reason; validation is
decided in the record's panel, which lists what the record holds and
disables Validate while a van lacks photos (`fleet_management/
roster_parts.dart`). What A2Z checks before validating is question 15 in
`QUESTIONS_FOR_COOPERATIVE.md`. The technical-term chips beside page
titles ("StartReviewStatus · HeldShare · AuditStatus") are removed, with
`PageHeader.technicalNote`: the owner's decision, for learnability. Verified: `flutter analyze` clean; the
widget test passes with `--platform chrome` (on the VM it cannot load
`package:web`, as before this change); a live build was driven at 1440
and 1280 as the Terminal Manager and a Cashier, including adding a staff
member through the inline form.

Done: **Console v3: critique, harden, polish** (25–26 Oct; the three
passes `docs/Web-console-redesign/HANDOFF.md` asked for). **Critique**
scored the console 24/40 on Nielsen's heuristics (snapshot in
`.impeccable/critique/`) and found four major problems, all fixed here:
(1) the Cashier's trip detail called the passenger list, which the
server keeps for the Dispatcher and the Terminal Manager, and showed
"This action requires: dispatcher, terminal_manager." with loading bars
that never ended. The Cashier now sees the trip's own counts and a
sentence pointing to Money (the owner's choice: the list stays closed);
a list that fails to load says so with Try again. Every role refusal
from the server now reads "Only the Terminal Manager can do this."
(`api/v1/deps.py`, the one backend change). (2) Two screens claimed what
nobody checked: Boarding Audit's empty day said "Every boarding matched
the passenger list" (it lists only what phones reported; now it says
so, and that a silent trip is Unaudited, not cleared), and Setup said
"Ready" with no SOS numbers set (now a warning on the Rules step and in
the Ready block, not a block: the owner's choice). (3) Keyboard and
screen reader: queue steps had no tap action for a screen reader; the
bell had no name; no page title was a heading; the map was announced as
"flutter_map"; focus showed only as a faint fill. Now a 2px ring
(`core/design/components/focus_ring.dart`, and the button themes), Tab
works region by region (menu, top bar, tabs, page; in Setup the queue,
then the step), titles are headings. (4) Rules & Settings showed stored
setting names and took "false" as typed text: it now speaks A2Z's words
(titles, descriptions and what "not set" means live in the screen;
the database's descriptions stay for the code), a yes/no setting is a
switch, Save appears only once a value changed, and four tuning
settings fold under Advanced. **Harden**, on a database built from the
migrations alone and on 39 long-named terminals: under 980 px the queue
strip scrolls with a visible bar and keeps the open step in view, the
form scrolls to its Save, and the top bar keeps all four figures
(words in a tooltip); long names wrap to two lines; Timetable waits
for a route like Route and Fares do; a second click while an action is
out is dropped (`runAction`); the Van Status Board says when it shows
the last reading; Reject and Suspend ask first; the page no longer
flashes dark at load (`web/index.html`). A save with the server down
says "Cannot reach SabayGo" and keeps the form. **Polish:** weights
match the bundled Roboto (400, 500, 700; a 600 or 800 was drawn as 700,
so the selected tab and row now read by weight); buttons look 40 px but
take a 48 px target; a done queue step keeps its number; on a trip the
filled button is the next step (Assign, then Start); spaces, not seats;
money owed is ochre, not red; the Van Status Board has column heads and
plate tags; one date format; the notification sheet and SOS cards are
flat; the role shows under the signed-in name. Verified: `flutter
analyze` clean; the widget test passes (`--platform chrome`);
`test_office_journey.sh` 61 of 62 (the one failure is the dev seed's
live trips dated an earlier day); each change seen in a live build as
the Terminal Manager and the Cashier at 1440, 1000 and keyboard-only.
Open: see `docs/Web-console-redesign/HANDOFF.md`.

**Handoff, 15 Oct: R10, the screens (brief §9), in a separate session.**
The server side of R1-R9 is done; R10 is Flutter work in `mobile/`
(Passenger, Dispatcher) and `operator_console/` (Terminal Manager,
Cashier). Verify with `flutter analyze` and the journey scripts, not a
device, unless asked. Say **Dispatcher**, never Conductor; show the
operator only as name + licence + plate on the trip. Already built in
the console: the Trips page's Start and departure panel (assign, Start,
Record A2Z's share, Lift payment block), the add-van dialog.

| Screen (brief §9) | Endpoints that exist |
|---|---|
| Dispatcher dashboard (app) | `GET /trips/{id}/door-check`, walk-in `for_event_id`, `POST /door-events/{id}/explain`, `PUT /trips/{id}/crew`, `POST .../depart`, `.../arrive`, `POST /non-passenger-moves` + `/{id}/end`, home pickups `activate`/`arrived`/`close`/`proof`/`proof/confirm`, rental `POST /special-trips/{id}/cash`, `GET /trips/{id}/share` |
| Passenger app | `POST /special-trips`, `GET .../mine`, `.../withdraw`, `.../checkout`; `POST /home-pickups`, `.../proof`; camera notice on the booking screen (brief 4.5) |
| Start Trip / Review Automatic Starts | `PUT /trips/{id}/assignment`, `.../start`, `.../start-review`, `.../change-van`, `.../void`, `.../payment-override`; trips from `GET /config/trips?date=` |
| Remittance (replaces Fares & Cash) | `GET /statements?date=`, `POST /statements/{id}/payments`, `POST /trips/{id}/payment` |
| Disputes | `POST /disputes`, `GET /disputes?status=&trip_id=&remittance_id=`, `.../withdraw`, `.../decide` |
| Boarding Audit (replaces Passenger Count Checks) | door-check per trip, `GET /door-events/{id}/snapshot` (Terminal Manager only), `GET /trips/{id}/chain` |
| Phones, Member Records | `api/v1/devices.py`, `api/v1/fleet.py`, `api/v1/roster.py` |
| Rules and Settings | policies + history (`config.py`), `GET/PUT /config/routes/{id}/stretches` (speed limits) |

The server gaps are closed (R10a, below). Retire with the new screens: Fares & Cash (`cash_remittances`, rev 514) and Passenger Count
Checks (rev 468 YOLOv8 audits, whose snapshots sit in public `/media`,
against T38). The Dispatcher app still offers a "Van is at" stop for
walk-ins (R2: only stop 1 is accepted). Open in the brief: where the
Dispatcher records a dispute (app or web), Emergencies kept or dropped.

### Rev 721 S9, S10 and the Day 1 test (3 Nov)

Branch `rev721-frontends`. **S9** (console) and **S10** (app) brought
both front ends onto the cash-only backend; what each covers is in
`docs/GAP_REPORT.md` §10.4. Then the **Day 1 test**: the database
rebuilt empty, the first Terminal Manager made by
`backend/scripts/create_first_manager.py` (staff do not self-register),
A2Z's setup entered through the console from their trip-schedule poster,
and one cash trip run from reservation to statement, all four roles in
one browser (`docs/DAY1_TEST_GUIDE.md`). Twenty-three findings
(`docs/DAY1_FINDINGS.md`); the fixes that touch rules:

- **Any seat paid after the list locks is a top-up** and puts the trip
  back to unpaid, even when the list was empty at the payment
  (`finance/statement._top_up`), and a payment recorded from the
  statement locks the lists of the trips it pays, as paying the trip
  does (`record_payment`). Before, a seat paid after the fees of an
  empty trip left the trip Paid while its statement owed the 15 %, so
  Start did not wait for it. `test_terminal_fees.sh` gained ten checks
  ("Fees recorded on an empty list, then a seat"): 79/0;
  `test_trip_lifecycle.sh` 135/0.
- **The manifest names app passengers** from their profile
  (`operations/boarding.ManifestUseCase`); before, only a walk-up's
  typed name was sent.

The rest were front-end fixes (unread badges in both apps, row buttons,
a web-only crash in the walk-up request id, the Money title) and
`tracking_simulator.py` reading names as utf8mb4. The data the test
ended with ships as `db/day1/day1_a2z.sql`, loaded by
`./db/load-day1.sh` in place of the demo seed. Full suite 1070 passed,
0 failed, 0 gaps (`journeys_20261103_154759.txt`). Handoff:
`docs/HANDOFF_DAY1.md`.

### Alpha preparation (8–9 Nov)

Two fixes found while preparing the alpha test, both about reaching the
backend from a machine other than the server laptop. `run.sh` built the
console against `127.0.0.1`, so a second laptop loaded the sign-in page
and then failed every API call; it now builds against the LAN address
it gives the backend and the APK (checked: the stamp and the bundle
carry the LAN address, and CORS answers a tester laptop's origin). The
app's network security config allowed cleartext to four fixed hosts
only; a debug-only override
(`mobile/android/app/src/debug/res/xml/network_security_config.xml`)
permits it to any host, so a debug APK works on whatever address the
venue hands out, and release builds keep the strict config (checked in
the built APK's binary XML: `base-config`, no `domain-config`). Merged
into `main` with rev 721 S9 and S10. Handoff for the simulation test
before alpha: `docs/HANDOFF_ALPHA_PREP.md`.

### Design polish, both apps (10 Nov)

A polish pass inside the two existing design systems (`DESIGN.md`,
`mobile/DESIGN.md`), from screenshots of every console page and the main
app screens: no new palette, font or component.

Console: stat tiles take a minimum height so a row lines up with or
without a caption (`core/design/components/panel.dart`). Money reads as
a ledger in three groups (fares on the list, terminal fees, operator's
share) in place of ten equal figures, and its fare lines carry column
heads and the words Booked / Walk-up (`remittance_screen.dart`). The
Van Status Board says the trip as route and departure time with the
detail on a muted second line, dropping the plate and status the row
already shows and the 24-hour time (`van_board_screen.dart`). A trip row
on Trips puts its badge beside the route, so the Dispatcher's name is no
longer cut off. Disputes' empty state says where a dispute comes from.

App: the profile screen leaves the retired purple, the duplicate
heading, the green and amber accents and its capitalised labels for the
tokens and `AppSectionHeader`, and no longer shows the trust rating: a
column default of 5.0 that nothing updates, which shown as a score would
be an invented number. Notifications map each type to a `StatusTone`
(money owed is ochre, never red) and use `AppEmptyState`, telling no
updates from no match; conversations use the tokens and `AppEmptyState`.
A Dispatcher action label wraps instead of ending in an ellipsis. The
reserve-sheet layout tests get an offline `ApiClient` for the camera
notice, so `flutter test` is 29/0 (was 25/4).

Found, not changed: `GET /trips/{id}/door-check` answers `aboard: 0`
when no phone reports, and the Dispatcher app shows "0 aboard (camera)"
and "no-shows, nothing to do" -- a count the system does not have.

Second pass the same day. The last four app screens with hand-picked
colours left them: edit profile (input edges were `grey.shade300`, about
1.3:1, under the 3:1 a control edge needs; green Save and focus; the
retired purple avatar; a controller built on every frame and never
disposed; the password switch now a `SwitchListTile`, so its label names
it), saved destinations (with an empty state that offers Add), and the
conversation thread (own messages in ink, not Paid Green; a 10 px grey
timestamp under AA). No screen in `mobile/lib/views` now writes a raw
colour except the shadows DESIGN.md specifies. Ten icon buttons across
both apps had no name for a screen reader and now have a tooltip. The
app's layout test also runs `flutter_test`'s WCAG guidelines (48 dp
targets, labelled targets, text contrast) on each screen; the reserve
sheet is exempt from the contrast check only, a false reading checked
against a rendered image. `flutter test` 29/0. Recommendations for what
is left, and for the Flutter stack: `docs/UI_UX_RECOMMENDATIONS.md`.

Third pass, on the owner's review of the running console. The stat
tiles read as greyed out: they are now white cards with a divider edge,
the icon on a small plate in the figure's status tint and a 24 px
figure (`StatTile`, `core/design/components/panel.dart`; the Trips
tiles gained icons; `DESIGN.md` records the new spec). The profile was a
dialog; it is now the My account page (`core/layout/account_screen.dart`,
replacing `profile_dialog.dart`), with details and password in separate
panels saved separately, and the person's real role where the dialog
said "Cooperative office staff" for everyone. Each page now has an
address: `MaterialApp.router` with a small delegate
(`core/layout/console_router.dart`, no new package) and the shell
following it, so a refresh keeps the page, Back and Forward work, a
link survives sign-in, and the browser tab names the page. Checked in a
headless browser: `#/trips/van-status-board` survives a reload, Back
steps to Trips then Money, sign-in returns to the page it was on.
`flutter analyze` unchanged (16 infos); the console's boot test runs
only in a browser (`flutter test --platform chrome`, web-only imports)
and passes there.

Fourth pass, the owner's palette and type. The console is a
monochromatic emerald on clean white: six shades of one green
(`#9FFFCC` to `#0C6033`), the emerald `#26DA8D` as the main action with
dark ink text on it (white would be 1.83:1), forest `#0C6033` for every
green text and icon and the sidebar, near-neutral greys; every pairing
computed against AA (`tokens.dart`). Fonts: Inter for the interface and
money (tabular figures), Plus Jakarta Sans for page titles and the card
figures, static weights cut from the OFL variable fonts and bundled with
their licences; Roboto is gone from the console. The figure card follows
the owner's reference (icon tile left, label over figure); a row of
cards spans the page (`CardRow`), so on Money its edges are the
statements' edges, and each statement is three equal columns with each
hand-over's "recorded by" under its own column and the fare lines a
table with a header row. Danger buttons now set white text explicitly
(the theme's dark action text would be 2.9:1 on red). `DESIGN.md`
rewritten for the palette and type. The app (`mobile/`) is unchanged.

The sidebar followed: the forest rail read as too green beside the
white pages, so it is white with a divider edge, ink labels and muted
icons; the selected entry is the mint tint with a forest label and its
icon on an emerald tile; counts are forest pills; Emergencies keeps its
red tile and turns red when open, with a white label (`tokens.dart`
sidebar tokens, `operator_shell.dart`). Focus rings on it are forest. Then, at the owner's
word, the selected entry swapped to the palette's light green `#9FFFCC`
as the highlight, with an ink label and a forest icon tile. Finally the owner settled it: the
sidebar itself is the mint `#9FFFCC`, the main colour, with ink labels
(15.15:1) and the selected entry white with a forest icon tile. Mint proved too pale: the base colour is the light green
`#26DA8D`, now the sidebar (ink labels 9.86:1, deep-green icons
`#173A28` 6.87:1, since the grey would be 4.25:1), the main buttons and
the figure cards' icon tiles (dark icons).

Fifth pass, the owner's VerdantPulse reference, mapped onto SabayGo's
real operations. Palette: meadow mist `#F0FDF4`, white and `#DCFCE7`
cards, `#86EFAC` edges, kelly `#22C55E` and emerald `#10B981`, `#059669`
for secondary hover, `#1E3A2F` type; where the reference fails AA (white
on emerald, 2.54:1) the text is dark, and green text is `#047857`. The
sidebar is white with grouped entries ("Daily work", "System") and the
selected entry an emerald pill. Four widgets, each on recorded data and
none of the reference's invented scores or growth rates: (1) figure
cards with a progress bar for a real ratio (`StatTile.progress`; Money
paid of owed and given of owed, Trips aboard of booked and booked of
capacity, Van Status Board each state of all vans); (2) a Today panel on
Overview (`modules/live_map/today_panel.dart`: trips by status as a
donut, "Needs you today" from `ReviewCounts` with each row opening its
page, fees paid of owed); (3) search on Money and Trips; (4) the fees
chart (`modules/remittance/fees_chart.dart`, 7D/30D/1Y) on a new
endpoint `GET /statements/history` (`api/v1/statements.py`: sums of the
stored statements by day or month, today synced first, a day with no
statement a true zero; the day-sync is now `_sync_day`, shared with
`GET /statements`). Journey: `test_fee_history.sh` 18/0, added to
`run_all_journeys.sh`; `test_terminal_fees.sh` 79/0 after the refactor.

Sixth pass, the owner's three asks. (1) The day picker's date opens a
calendar (`DayPicker`, `core/design/components/actions.dart`); the pick
reaches the page as a shift, so Trips, Reviews and Money all have it.
(2) Cards that open a page look it and do it (`ClickableCard`,
`StatTile.onTap`): Overview's Today's trips opens Trips, Terminal fees
today opens Money. (3) A live van monitor beside the Overview map
(`modules/live_map/live_vans_panel.dart`): for each van boarding or on
the road, the YOLOv8 door count against its spaces with a load bar, the
camera's state, the GPS state and open driving flags; a van over its
spaces leads in red. The data is the Van Status Board's
(`operations/van_board.py`), which now carries, for a trip under way,
`camera` ('live' / 'lens_blocked' / 'silent' / 'no_phone', the same tests
as the Unaudited rule), `camera_seen_at`, `seat_capacity` and
`open_flags` (driving flags still open, en-route stops left out); the
count is computed for boarding trips too, and is zero only when a live
camera has seen nobody board. The overload alert itself was already the
server's (`edge/capacity.py` notifies the Terminal Manager, the Cashier
and the Dispatcher on each crossing); the panel shows it. Journey:
`test_van_board.sh` 35/0 with five new checks (no phone, silent, live
with a real 0, lens covered, capacity), run with `run.sh`'s GPS
simulator stopped, since that simulator puts readings on the departed
trip that the script expects to have none. Checked in a browser with a
test phone counting 16 into LAB-4521: the red overload card, the bell's
"Capacity alert" and Boarding Audit's 11 unlisted boardings; the test
data was reset away afterwards.

The console's new logo (the owner's art, 10 Nov): a light-green van with
its passengers in detection boxes and the GPS signal, over the
"SabayGo" wordmark. Its mint background was cut to transparency and the
logo trimmed (`assets/branding/sabaygo_logo.png`, replacing the owl);
the van alone is `sabaygo_mark.png`, for the folded sidebar, the
favicon and the web app icons (the maskable ones with the 66 % safe
zone). The swoosh runs through the wordmark, so the logo is shown whole,
never split into a side-by-side lockup: 80 px tall in the sidebar, 116
on sign-in, 120 on the start-up screen (first 112/150/160; the owner found
it too big). The web manifest's colours
follow the palette. The app keeps the owl.

The owner's browser still showed the owl after the rebuild: `python3 -m
http.server` sends no Cache-Control, so the browser kept the weeks-old
logo by its own heuristic (a tenth of the file's age) without asking.
Two fixes: the logo files and the favicon have new names
(`sabaygo_van_logo.png`, `sabaygo_van_mark.png`, `favicon-van.png`), so
no browser holds them; and `run.sh` serves the console through
`operator_console/tool/serve_web.py`, which sends `Cache-Control:
no-cache` on every file, so any later rebuild reaches every office PC on
its next load (an unchanged file is a 304).

### Alpha run with A2Z's trip ticket (10 Nov)

The owner's paper trip ticket Nº 0012223 (Cotabato ₱363 × 2, senior
₱290 × 4, ₱149 × 1, Digos ₱150 × 1; ₱2,185; 15 % ₱327.75 + parking ₱50 +
DCOTT ₱75) replayed on the Day 1 data, typed into the console as A2Z's
office would: the ticket's fares, an operator and van TST-1023 (photos,
validation), a new Dispatcher, Start and check-in opened 300 minutes
early for the test, three departures added to the timetable and **Create
upcoming trips**. Four new users (a Dispatcher and three passengers who
signed up). Five trips ran from reservation to arrival, trip 1's
assignment, payment and Start in the console, the rest through the apps'
endpoints; every amount matched the hand calculation (₱525.20, ₱438.80,
₱570.20, ₱369.75 with parking once, ₱478.65 after a dispute adjusted
₱51.00 to ₱22.50; the day ₱2,382.60). Findings 24–33
(`docs/DAY1_FINDINGS.md`): fixed, a plate wrapping in the van list, a
dialog left stuck when the page changed under it, the first sign-in on
a browser lost at the next load (the session values written at once,
each making its own encryption key; console and app), Start shown as
the next step while blocked by the fees, the chart above the Cashier's
statements, the operator's-share hint on a van's second trip, a
departed trip undercounting its paid seats, and the timetable form
forgetting the only route. Open for the owner: paid app bookings are
marked no-show at departure (31) and there are no discount fares (32).
The run is written up as a test case (`docs/ALPHA_TEST_CASE_TRIP_TICKET.md`)
and automated (`tests/integration/test_trip_ticket.py`, on fresh Day 1
data, added to `run_all_journeys.sh`).

The console's sign-in, on the owner's split design: a deep green panel
(what the console does, a van shown as it appears inside, marked
"Example") beside the form (labels above the fields, "Forgot password?"
and "Need help?" pointing to the Terminal Manager, the 12-hour session
stated). The mock-up's live-looking "14 / 15 Seated", "Secure SSL",
"A2Z Auth Guard" and pre-sign-in "Role: Manager" were left out as untrue,
and its 12-hour checkbox is a sentence because the session is not a
choice. Narrow windows show the form alone. `PasswordField.labelAbove`
puts its label in the placeholder under a heading. The full journey
suite ran after the day's backend changes: 1,149 passed, 0 failed, 0
gaps, including `test_trip_ticket.py`.


### Phone app on the console's palette (10 Nov)

The passenger and Dispatcher app now wears the office console's
VerdantPulse look, so the three roles see one product. `mobile/lib/core/
design/tokens.dart` takes the console's values under the names the screens
already used (`primary` 047857, page F0FDF4, cards white with an 86EFAC
`edge`, type 1E3A2F, one green-grey `AppRamp`) and adds `action` (emerald
10B981), `actionHover`, `onAction`, `edge`, `surfaceSunken`, `onFill` and
`disabled`; `info` moves from blue to the console's slate. `theme.dart`:
Inter for text and Plus Jakarta Sans for headings (bundled from the
console; Roboto no longer bundled), emerald filled buttons with dark text
(kelly pressed, sunken disabled), a green rule under the app bar, green-
edged cards with no shadow, and the selected bottom-nav item as an emerald
pill (the console's selected sidebar entry). The owl gives way to the van
logo, the van-only mark in the app bars. Screens: spinners on filled
buttons go dark (white on emerald is 2.54:1); the three red buttons (sign
out, SOS) set white text, the SOS send button stays red while sending; the
profile and destinations screens' grey shadows become green edges. Every
pair the app uses was computed (lowest 4.99:1 for text); `flutter analyze`
has no errors or warnings, and the 29 layout tests (WCAG contrast and
targets) pass. `mobile/DESIGN.md` rewritten to match. The old owl and
Roboto files stay in `assets/` unbundled.

Alpha finding 34 (Money): the payment dialog asked again for an
operator's share already given in full, and because the amounts add up a
second entry would have counted it twice. The dialog now states the share
as given; while some is still to give, it and **Record operator's share**
(shown only then) refuse more than the rest (`remittance_screen.dart`).

### An operator's share held over what is owed (10 Nov, finding 35)

Upholding a fare-line dispute takes the line's fares off the van's
statement, so a share the operator was already given can end up above the
share owed. Now it is seen before, said after, and settled:

- **Before:** `POST /disputes/{id}/preview` runs the real decision in a
  savepoint, reads the statement and rolls back
  (`Disputes.preview`, `_decide` split from `decide`), so the preview
  cannot disagree with the decision. The Decide dialog shows terminal
  fees, Due now and the operator's share owed, before → after, for the
  outcome and amount chosen, and says in words when the operator would
  hold more than the share.
- **After:** migration 038 adds `operator_share_returned` (+ when, who)
  beside `operator_share_given`; the share held is given − returned
  (`Statements.share_held`) and any excess is reported at once
  (`share_over`), lists locked or not. The decision notifies the Cashier
  and the Terminal Manager (`share_over_given`, opens Money). The
  statement shows "₱X to come back" with **Record ₱X handed back** for the
  Cashier (`record_share_returned`: never more than the excess, Cashier
  only). Given stays as handed over, so the record shows both moves.
- "Still to give" everywhere is owed − held: the Money and Trips dialogs
  and the Dispatcher's dashboard, which also says when the operator holds
  an excess. The Trips dialog gets finding 34's guard (no field once the
  share is given, no more than the rest).

`test_trip_ticket.py` section 10 (LCT-9042, an extra departure: share
given, line upheld, ₱308.55 previewed, told and handed back in two parts,
limits and roles) — 75 passed, 0 failed; `test_terminal_fees.sh` 79/0 and
`test_disputes.sh` 80/0, all on a scratch database (`sabaygo_t`, a second
backend on :8001) so the alpha data was not reset. Console and mobile
`flutter analyze`: no errors or warnings.

### Console toned down: one place per job (10 Nov, C + F + G)

The first part of the console restructure the owner chose (the proposal's
C, F and G; the menu, the Today list, the trip stepper and the Cashier's
Counter wait):

- **C, one place and one name per job.** One **Record payment** dialog
  (`modules/remittance/record_payment_dialog.dart`, `askPayment`) for
  Money and Trips: the same intro, Due now, fields and operator's-share
  rules (findings 34 and 35). Trips before departure still posts to
  `/trips/{id}/payment` (it locks that trip's list and defaults "handed
  over by" to its Dispatcher); Money posts to the statement. "Record
  terminal fees" and "Record payment of ₱X" are now "Record payment"; the
  Terminal Manager reads that Start waits until the Cashier records it.
- **F, Add trips on Trips.** "Create upcoming trips" left Setup →
  Timetable for a Terminal-Manager-only **Add trips** on Trips
  (`trip_monitor/add_trips.dart`), a week by default since nothing makes
  trips on its own. The Timetable keeps the departures and links **Go to
  Trips**. Alpha guides updated.
- **G, toned down.** `StatTile`: white, no tinted icon square (a 16px
  icon by the label carries the status colour), the figure in the type
  colour, 24px, a flat bar; `tinted` removed. One bar a page at most
  (Money: fees paid; Overview: today's fees) and four cards a row at most:
  Money drops its Paid card, Trips folds "At terminal" into "Not yet
  boarded" and states ratios in words, the van board shows Out of service
  only when a van is. Card and panel edges take the lighter divider
  `#BBF7D0`; the bright `#86EFAC` stays on the sidebar and charts.
  `DESIGN.md` updated.

`flutter analyze`: no errors or warnings (the console's widget test does
not compile on the VM: `download.dart` and `pick_file.dart` import web-only
libraries, before this step too). Console rebuilt and served.

### Trips and Money as sheets, posting trips (11 Nov)

The owner's direction after C + F + G: "an automated Excel" for inputs
and posting trips "like a post". Previewed first as a Design canvas
(two clickable screens), then built:

- **Trips** (`trip_monitor/trip_sheet.dart`, `post_trip_box.dart`,
  `screens/trip_monitor_screen.dart`). For the Terminal Manager, **Post a
  trip** (route, day, time, van and Dispatcher optional; **Post** calls
  `POST /config/trips/special`, which had no screen, via
  `DispatchRepository.postTrip`; **Post the timetable for 7 days** is the
  old Create upcoming trips) beside **Passengers can book now** (the open
  trips as the passenger app lists them). Below, the **trip sheet**: one
  row a trip; Van and Dispatcher are dropdown cells saved on choice
  (`PUT /trips/{id}/assignment`, which takes either alone; offered from
  `assignableRoster`, the assign dialog's list); Passengers, Fares and
  Terminal fees fill themselves (fees from the van statements: the trip's
  15 % lines, its DCOTT ticket, the day's parking on the van's first trip);
  Status in words; one next step by state and role (Record payment for the
  Cashier, Start, Depart). A row opens the trip's detail as a panel from
  the right (`showTripDetail`), refreshing itself every 15 s. The old list
  and fixed detail column are gone.
- **Shared steps:** Record payment, Start and Depart moved from the trip
  panel into `trip_actions.dart` (`TripActions`), so the row button and
  the panel ask and say the same.
- **Money** (`remittance_screen.dart`): the statement cards became the
  **van statements sheet**: a row a van (operator and trips, fares with B
  and W, terminal fees with paid, due now with any disputed share, the
  operator's share held of owed or to come back, one next step), "All
  vans" / "Money due" chips and search; a row opens its statement under it
  (`_StatementPanel(embedded: true)`: fees line by line, fare lines with
  disputes, the operator's-share buttons; Record payment stays on the row).
- Wording: the timetable dialog is "Post the timetable"; the alpha guides
  say Trips → Post the timetable for 7 days. `DESIGN.md`: the sheet and the
  post box.

`flutter analyze`: no errors or warnings. Console rebuilt and served. Not
yet seen rendered by Claude (no browser in this session).

### Repeats removed from Trips and the top bar (11 Nov)

From the owner's screenshots of the new trip sheet:
- **Sheet rows:** an unassigned row said it three times ("Pick a van" cells,
  "No van yet", "Pick a van and a Dispatcher"); the next step is now empty
  there, and for arrived and cancelled trips ("Done", "Voided" repeated the
  status). "Passengers can book now" listed the sheet's own trips: removed;
  the post box is one compact row (Post the timetable at its title, Post at
  the end of the fields line).
- **Trip detail:** the header carries the time, route and the sheet's status
  words (`tripStatusWords`, shared), so the card no longer repeats "Leaves
  5:30 AM" or says "Scheduled" where the sheet says "No van yet". The
  Aboard/Not yet boarded/Unpaid tiles and the Spaces panel merged into one
  Passengers panel (figures the row lacks, then the list); Crew became
  Operator (the row has the plate and Dispatcher), shown once a van is on.
  `TripLifecyclePanel(besideSheet: true)` drops what the row does (assign,
  Record payment, Start, Depart) and facts that only restate the status, and
  vanishes when nothing is left; Special Trips and Review Starts keep the
  full panel. **Lift payment block** no longer shows on a trip with no van
  (nothing is owed yet), on every page.
- **Top bar** (`today_strip.dart`): only what needs the person, while it
  does: open emergencies (or "could not be checked", never a false zero),
  boardings to review / vans owing, vans with no signal; otherwise "Nothing
  needs you right now". "Vans on the road" and "Trips today" repeated
  Overview and Trips, so they went (one board request fewer every 30 s).

`flutter analyze`: no errors or warnings; console rebuilt and served.

### Setup redesigned; the timetable moves to Trips (11 Nov)

The owner: "trips and setups have repeated operations". Making trips was
split across two pages (Setup › Timetable kept the departures, Trips
posted them, and each linked to the other with "Go to Trips"). Now:

- **Timetable → Trips area.** A Terminal-Manager tab Trips · **Timetable**
  · Van Status Board · Special Trips (`TimetablePage`), beside the post
  box. Setup's queue keeps a Timetable step during the first set-up only,
  as a pointer ("Open the timetable"); its done-check is unchanged.
  "Go to Trips" is gone from Setup and from the timetable.
- **Setup shell.** The numbered queue and progress bar show while set-up is
  under way; once every required step is done the left side is a plain
  **Records** list with what each holds (and the SOS warning when no
  number is set), and the page says the day's work is on Trips and Money.
- **Every step (`step_frame.dart`).** `StepFrame` is stateful: the step's
  one primary action, **Add …**, sits in its header; the side panel shows
  only the clicked record (`detail`) or the add form after Add (`addForm`)
  and closes with its ✕ (the add form through `_StepFrameScope`); a step
  with no records opens its form (`openWhenEmpty`). `RecordList` takes
  `RecordColumn` heads and `RecordRow` `cells`: Terminals (Terminal, City,
  Zone, Staffed, Status), Route (Code, Route, Stops in order, Status), Fares
  (Route, Fares from the first stop, Status; the fare form gained its ✕),
  Operators (Operator, Licence with an Expired badge, Van, Validation),
  Vans (Plate, Operator, Condition, Photos, Validation), Staff (Name, Role,
  Work status, Validation). Phones keep their cards with the same Add.
  "Back to adding" became a plain ✕ everywhere. The timetable uses the
  same frame (its form now in a side panel).

`flutter analyze`: no errors or warnings; console rebuilt and served.

### The owner's reference layout; fresh alpha data (11 Nov)

The owner supplied a reference console (HTML and screenshots) to follow,
asked that the inputs be correct, for more users, and for a reset because
earlier test data blocked their testing (a van still owed ₱50 from its
last trip, so it could not be assigned).

- **Data.** Backed up (`db/backups/before_reset_20261111_0107.sql`), then
  `./db/load-day1.sh` and the new `backend/scripts/seed_alpha.py`, which
  works through the API: A2Z's trip-ticket fares from today (Digos ₱150,
  Kidapawan ₱340, Cotabato ₱363; Day 1 had ₱135 and ₱500), TST-1023 with
  Arnel Bautista (validated, four photos), Dispatchers Nonoy, Jun and Mae
  (all five validated), Cashier Rose, passengers Andrea, Rogelio, Grace,
  Paolo and Lea, and the timetable posted for 7 days (42 trips). No van
  owes anything. 14 accounts, password sabaygo123.
- **Trips** (`trip_sheet.dart`, `post_trip_box.dart`,
  `screens/trip_monitor_screen.dart`): the reference's **compact
  quick-post bar** (route, day, time with "+ Next slot", van, Dispatcher,
  7-day timetable, Post, and an "N open" pill), or by choice a **split
  view** (the full card beside "Passengers can book now"); the **sheet**
  with filter chips (All, No van yet, Boarding, On the road, Arrived),
  two-line cells (time over route, van over operator, Dispatcher over the
  phone out with the van, listed over the camera's count with a bar),
  fares and fees with "✓ Recorded"/"Unpaid", status pills (on the road
  solid), the next step (the Manager's "Start blocked (unpaid)" opens
  Lift payment block, `TripActions.liftBlock`), and a totals footer. The
  **slide-over** opens with the status and fees badges and the operator,
  then the door camera (listed vs counted, or why it was not counted),
  the van and Dispatcher (editable while scheduled), the fees worked out
  (`TripMoney`, `tripMoneyFor`), the passenger list, the Manager's
  controls, and the next step at the foot (`TripNextStep`, shared with the
  row).
- **Top bar:** the four live pills are back (vans on the road with "no
  signal", trips today with "under way", boardings to review / vans owing,
  open emergencies, a dash when a figure could not load), and a role chip
  ("Manager authority" / "Cashier duties") opens what that role may do.
- **Setup:** once set-up is done, the records are tabs across the top.
- **Left out of the reference, as untrue here:** "Auto-Assign Next Queue",
  the "Simulate" buttons, "Firebase Live", "Twilio connected", hash chains,
  "Mark Arrived" for the office (only the Dispatcher's app can: `CREW`),
  FR numbers in labels, and its made-up fares.

`flutter analyze`: no errors or warnings; console rebuilt and served.
Not yet seen rendered by Claude.

### Reference restyles: sheet spacing, Reviews, Van board, Money, Messages (11 Nov)

- **Trip sheet:** the van cell showed "LCT-9042 (Pedro Lumbay)" above "Op:
  Pedro Lumbay"; the cell now shows the plate alone (the operator stays in
  the menu and once under the cell). Wider Time & route column (the route
  no longer cut off), 88px rows, more air between a cell's two lines and
  beside the dropdowns.
- **Disputes** (`disputes_screen.dart`): reference cards, two to a row:
  the plate on a dark chip with the trip, the status, the type, what is
  contested, the operator's words in a quote box with who recorded them,
  the decision, and a footer with what is withheld and **Uphold**,
  **Adjust** (fare lines), **Reject** and Withdraw. Each decision button
  opens the Decide dialog with that outcome chosen, so the "What this
  changes" preview still shows first.
- **Driving flags:** row cards: the type chip, plate, operator, time and
  status; the place in green; what happened; review buttons on the right.
- **Van Status Board:** a card a van, three to a row: the plate on a dark
  chip and its state, operator and licence, then the trip, Dispatcher,
  door camera, GPS and terminal fees owed, and a footer saying whether it
  can be dispatched, with a link to the trip sheet.
- **Money:** the summary tiles went (the ledger's total row has them); the
  selected van's **statement card** is on top (a "STATEMENT · plate"
  chip, the operator and trips, due/paid and disputed badges; the fare
  lines by trip, drop-off and group on the left, the fees worked out with
  the hand-over buttons on the right), the **daily van statements** ledger
  below (a click selects the van shown above; Record payment on the row).
- **Messages:** a thread header (who, and their role), green bubbles for
  the office and white ones for the other side with the sender's corner
  squared, a rounder composer with "Reply to …".

Not restyled: Review Starts and Boarding Audit (their own layouts), the
Overview. `flutter analyze`: no errors or warnings; console rebuilt.

### The last three restyles, and live data from the database (11 Nov)

The owner asked for Review Starts, Boarding Audit and the Overview in the
reference style, then real-time data in them from the database.

- **Overview** (`live_map/today_panel.dart`, `fleet_map_screen.dart`): the
  fees card is a tinted card, `_FeesToday`: the day's total, due and
  disputed, the 15 %, DCOTT and parking, and a paid bar. The map takes 7
  parts of the width and the live-vans panel 5.
- **Review Starts** (`start_review/start_review_screen.dart`): a card a
  trip (`_ReviewCard`): reason pills (started by the system, left unpaid,
  more aboard than listed, Unaudited), the trip, what happened in
  sentences, and Review, which opens the trip in a slide-over with the
  whole lifecycle panel. Reloads quietly every 30 s.
- **Boarding Audit** (`boarding_audit/boarding_audit_screen.dart`): a card
  a trip: the plate chip, reason pills, a dark evidence block (the
  event chain, its count and whether it verifies), the unlisted
  boardings in a light box with the Dispatcher's explanation, capacity
  alerts. Reloads quietly every 30 s.

**Live data: `backend/scripts/seed_live_now.py`**, run after
`seed_alpha.py`. It goes through the real API as each role would, so
every screen shows what the server holds. It plays an extra trip on
TST-1023 with Nonoy (three paid reservations, four walk-ups, a phone
checked out and reporting, eight boardings at the door against seven
listed, a disputed Kidapawan line, the fees and share recorded, Start;
Depart is refused until Nonoy explains the eighth boarding, then
departs); a second extra trip on a van with nothing else today, let go
by the Terminal Manager before its fees with a written reason and no
phone aboard (Unaudited: the Review Starts case); and the next
departures given Dispatchers, one trip left vanless with two paid
reservations. It leaves the GPS replay and the phone's 30 s status
reports running in the background (`logs/`; stop with
`pkill -f seed_live_now ; pkill -f tracking_simulator`). Proved on a
scratch database rebuilt from Day 1: every step done.

Traps it found, now in the script's comments:
- An assignment **replaces the van and the Dispatcher together**: a PUT
  with only `dispatcher_id` takes the van off the trip.
- A van on a trip today **owes that trip's DCOTT ticket and the day's
  parking now** (`Statements.van_balance` counts every open statement
  dated today or earlier), so its second trip today is refused until the
  Cashier records them. The refusal says "from its last trip" even when
  that trip has not run yet, which reads oddly; the rule itself is right.
  Wording left alone for now.
- A trip let go with the block lifted reads `overridden`, not
  `left_unpaid`: Review Starts lists it for being Unaudited, not as
  left unpaid.
- An extra trip posted at 2 a.m. is still on the road at 05:30, so it
  cannot share a van with the 05:30 trip (the clash check).

`flutter analyze`: no errors or warnings; console rebuilt and served.

### Livelier console: one hover, glass, one field box (11 Nov)

The owner asked for a livelier console with hover that works everywhere,
transparency, the post bar's dropdowns and inputs the same size, a less
bland hover in Setup, and the laws named: Fitts, Hick, Miller,
proximity, visibility of system status, poka-yoke.

- **One set of interaction states** (`core/design/tokens.dart`):
  see-through emerald washes for hover (8 %), press (16 %) and focus
  (12 %), set in the theme for every InkWell, outlined and text button,
  tab and field; `AppShadow.lift` under the pointer only (a clickable card
  rises 2 px, a top-bar pill 1 px, the main button takes elevation 3).
  Reduced motion keeps the edge and drops the movement.
- **Transparency** (`operator_shell.dart`): two soft emerald glows on the
  page (`_Ambient`); the top bar and the hub's tabs are frosted glass
  (`_Glass`, white 78 % over a 14 px blur). Panels with figures stay solid.
- **One field box** (`core/design/components/field_box.dart`):
  `FieldBox`, `FieldSelect`, `FieldLabel`, 48 px (`AppSizing.field`),
  one edge, icon, chevron, hover, a fixed (lock) state and a problem
  state. Text fields are 48 too (theme padding 14). The trip sheet's van
  and Dispatcher cells use the same box.
- **Post a trip** (`post_trip_box.dart`): every box and button 48 high,
  labels on one line; grouped (proximity) as the trip (route, day, time),
  a rule, who runs it (both optional), a rule, the actions with Post the
  largest at the end (Fitts). A time that has passed turns the box red,
  says so under the bar, and disables Post (poka-yoke: it was a refusal
  after the click); "+ Next slot" is the fix one click away. Under the
  bar, "Passengers will see …" states the trip before it is posted
  (visibility of status). The "N open" pill breathes (`LiveDot`).
- **Setup** (`step_frame.dart`, `setup_screen.dart`): a record row under
  the pointer takes the wash, a 3 px emerald bar slides in at its left,
  its name turns green and a chevron slides in; the whole row is the
  target. The record tabs are 48 high with a wash pill and a faint
  underline preview on hover.
- **Trip sheet and Money ledger rows:** the same wash and accent bar, a
  hand cursor (they had a meadow-mist hover, near-invisible on white).
- **Top bar** (`today_strip.dart`): pills lift on hover; a figure that
  needs someone keeps its tint at rest; a breathing dot while vans move;
  at the end, "Live · 10 s ago", a spinner while it reloads, "Not
  updating" in red when nothing answered; a click reloads.
- **Money, a bug the screenshot showed:** a van whose trip had nobody
  listed yet read "parking only" though it owed a DCOTT ticket (trips
  were counted from fare lines). Trips are now counted from the DCOTT
  tickets too; the empty fare side says what is owed anyway and why
  (`_NoFares`).

`DESIGN.md` updated (shadows, glass, interaction states, the field box,
the chips, the sheet rows). `flutter analyze`: no issues; console rebuilt
and served.

### The clash message names people and trips, not database ids (11 Nov)

The owner's screenshot: posting a 3:30 AM trip with Jun Bautista was
refused with "This dispatcher is already on trip 0e8163b7-e349-… departing
07:30, which runs until about 13:15." The message fell back to the trip's
id whenever the trip had no label, which is every timetable trip.
`ScheduleConflictChecker._words` (`application/scheduling/conflicts.py`)
now says it as the office would: "Jun Bautista is already the Dispatcher
on the 7:30 AM Davao (Ecoland) – Cotabato City trip, and is free again at
about 1:15 PM (the route plus 45 minutes to turn round). A trip at 3:30 AM
would overlap it: choose another Dispatcher, leave it for later, or pick a
time from 1:15 PM." A van clash names the plate the same way. Times are
12-hour, as the console shows them. Proved on the scratch database (both
clashes, 409 with the new words); `test_trip_lifecycle.sh` checks only
the 409s. `seed_live_now.py heartbeat` now rides out a backend restart
instead of dying.

### Passenger and Dispatcher app: fewer steps (12 Nov)

The owner asked for the passenger and Dispatcher screens to be easier to
use. Logic and server calls are unchanged; the screens are reordered
around the task each person does most.

**Dispatcher**
- **Trip screen** (`views/dispatcher/trip_manifest_screen.dart`): a
  **Next** line under the counts says what to do now from the trip's
  state ("Collect ₱450 in cash from 3 passengers, then mark each one
  Paid"; "The camera counts more aboard than listed …"; "Everyone has
  paid. When all are aboard, tap Depart"; "On the road. Tap Arrived at
  Cotabato …"), with a bar of spaces taken. The reservations list comes
  straight after (it was below the share and flags panels), with chips
  **To collect · Paid · All** and their counts (it opens on To collect
  while anyone owes). Each row reads name, status, the booking code large,
  drop-off and fare, then the action on its own line with the amount on
  it: **Mark ₱150 paid** (the confirm with the amount stays). **Add
  walk-up** and **Depart** / **Arrived** are pinned in a bottom bar under
  the thumb, 56 high; "Not a passenger trip", used rarely, moved to the
  app bar's ⋮ menu.
- **Trip list** (`dispatcher_trips_screen.dart`): **Next** (the first
  open trip, large, "Leaves in 25 min", a full-width Open button), then
  **Later** and **Done**. "DEPARTED" reads "ON THE ROAD".
- The walk-up form was already built for speed and is unchanged.

**Passenger**
- **Search** (`home_search_viewmodel.dart`, `journey_picker_card.dart`):
  no Search button; the departures load as soon as both ends are chosen
  and follow every change (older answers are dropped). The last journey
  is remembered on the phone's secure store, so a daily commuter opens
  the app on its departures; with none saved, From is the route's
  starting terminal when there is one (everyone boards there). The day is
  three chips, **Today · Tomorrow · Other day** (the calendar), not a row
  that always opened the calendar.
- **My trips, the upcoming card** (`reservations_screen.dart`): the
  booking code as a ticket stub, large, with the fare; under it one band
  with what to do next: "Pay ₱150 in cash by 4:45 AM (in 1 h 20 min)" and
  that an unpaid space is then released; "Paid. Show this code to the
  Dispatcher at the van door"; or "You are aboard".

**A bug found on the way:** the theme drew a selected chip's label in
the same green as its fill (1:1, invisible); the time filter had worked
around it locally. The theme now draws it white (`core/design/theme.dart`).

`flutter analyze`: no errors or warnings (21 old infos in untouched
files). `flutter test`: 32 pass, including a new layout case for the
search card at 320 dp and 200 % text. Not yet installed on a phone.

### The whole day through the screens, every role (11 Nov)

The owner asked for a full simulation: data entered and screens used as
each person would. A headless Brave drove the real apps (Flutter's
accessibility tree finds each control by its label; real clicks and
typing), each role in its own browser context, the console at 1440 px.
Fourteen steps: a Dispatcher closing a trip; the Terminal Manager posting
one; a passenger reserving, another cancelling; the Dispatcher marking
Paid and listing a walk-up; the Cashier recording the fees and starting;
check-in; chat both ways; Depart and Arrived; a dispute decided and its
₱51 collected; a new passenger signing up; a new Dispatcher added and
validated; an SOS raised and closed. Every money figure was checked by
hand. Report, findings and 59 screenshots:
`docs/test-reports/ui-run-2026-11-11/` (with the driver, `ui_driver.py`).

Fixed from what it found:
- My trips reloads when its tab is shown (a new booking never appeared);
  the reservation screen asks the server on opening and every 30 s (a paid
  passenger was still told to pay).
- At 1440 px: the menu folds to icons under 1500 px, the trip sheet has a
  laptop column set so Record payment and Start stay on screen, and the
  post bar gives way to the card under 1400 px.
- Wording: cash-only copy on the trip sheet; "Walk-up passenger"; a
  cancelled reservation's card; "Start opens at 11:00 AM" (not "Start is
  open"); the dispute line in the payment dialog; the SOS card without the
  setting's key; "Parking only" in the Money ledger; one badge, not two.
- `announceChange()` (`core/design/components/actions.dart`): any action
  reloads the top bar and the review counts at once.

Open: the passenger sees no "Paid" notice (a server change); a departed
trip leaves "Next trip" at once (the owner's call); "Cash passenger" vs
"Walk-up passenger" after departure; A2Z's privacy contact.

`flutter analyze`: no errors or warnings in either app (the console's 20
"use null-aware" infos and the mobile app's 21 are older and in untouched
files; an earlier entry's "no issues" for the console was a filter that
missed them). `flutter test` (mobile): 32 pass.

### The owner's decisions of 12 Nov: walk-in, who rode, the Paid notice

Options were put to the owner first (rename depth; how the system knows
who rode with no ticket to scan; what a riding passenger sees; how the
Paid notice is typed). Chosen and built:

- **Walk-in, everywhere, stored names included.** Migration 039
  (`db/migrations/039_walk_in.sql`, down script beside it):
  `remittances.walk_up_income` → `walk_in_income`, `remittance_lines.
  income_group` `walk_up` → `walk_in`, the amounts check remade. Server,
  scripts, journey tests, both apps, the demo seed and the Day 1 dump
  renamed with it; the Dispatcher's passenger is "Walk-in passenger"
  before and after departure (it was "Cash passenger · TERMINAL CASH"
  after). The brief and the paper say Walk-up: CLAUDE.md notes the
  override; `MANUSCRIPT_CORRECTIONS.md` §13 has the wording. Tested up,
  down, up on a scratch copy (amounts unchanged), then applied to the
  live database after a backup (`db/backups/before_039_20261111_1138.sql`).
- **Who rode is who paid** (Day 1 finding 31, decided). At Depart a paid
  seat becomes `boarded`, as a walk-in already was; only an unpaid one is
  a no-show (`application/operations/boarding.py`). It had made every
  paid app passenger a no-show, and so the server refused a riding
  passenger's SOS ("no booking on this trip"): now accepted (HTTP 201 on
  scratch). `MyBookingOut` carries `trip_status`; the passenger app keeps
  a boarded booking as the current trip ("On board", Track the van, SOS)
  until the trip is completed, then files it under Past trips. No
  counting query changed: `boarded` still means rode.
- **The Paid notice.** `CashDesk.mark_paid` tells the passenger in
  Updates ("Seat SG-… is paid: ₱… in cash to the Dispatcher. Show this
  code at the van door before it leaves at 12:10 PM."), on the existing
  `trip_update` type, so no schema change; an offline mark tells them
  when it syncs; a walk-in has no account to tell.

Testing on a scratch database without touching the live one:
`SABAYGO_DB=sabaygo_t` for `db/apply.sh`, `db/reset-dev.sh` and
`db/load-day1.sh`; `SABAYGO_API` for every journey script (and
`test_notifications.py`); `test_unpaid_release.sh` now reads the
database it was given (it had read the live one by name, read-only, and
reported false failures). Results on scratch: trip lifecycle 138/0 (T8
now asserts boarded; new checks for the Paid notice and trip_status),
terminal fees 79/0, disputes 80/0, unpaid release 57/0, special trips
74/0, door check 65/0, home pickup 68/0, Dispatcher 30/0, passenger no
failures, notifications all pass, trip ticket 75/0 (Day 1 data), fee
history 18/0, retention 35/0. `flutter test` 32 pass; both apps analyze
with no errors or warnings. The system was restarted on the new code and
both web builds rebuilt.

Not changed: bookings already recorded as paid no-shows before today
keep that status (no backfill); the live passenger screens were checked
by the journey tests and the API, not clicked through again.

### Review Starts opens the console's one trip panel (12 Nov)

The owner's screenshot: Review Starts' own slide-over held one small
"Start and departure" card above an empty column. It now opens the same
panel as Trips (`showTripDetail`): status badges, the door camera's
count against the list, van and Dispatcher, the fees worked out, the
passenger list, and "More on this trip" with the review facts and Change
van; the footer says what is next. The panel fetches its figures as it
opens when the caller has none (it waited for its first 15 s round, so
the fees showed dashes). Checked at 1920 × 930
(`docs/test-reports/ui-run-2026-11-11/r01_review_panel.png`,
`r02_review_actions.png`). `flutter analyze`: no errors or warnings;
console rebuilt.

### Money: the statement's two halves are one height (12 Nov)

The owner's screenshot: on a statement with no fares yet, the short "No
passengers listed yet" box sat beside the tall fees box. Side by side the
two halves are now one height (`IntrinsicHeight`, stretched): the shorter
grows to the taller, and the empty state centres its words. With fare
lines it is the fees box that grows to the lines' length. Checked at
1920 px (`docs/test-reports/ui-run-2026-11-11/s01_statement_symmetric.png`,
`s02_statement_lines.png`). `flutter analyze`: no issues in the module;
console rebuilt.

### Seat, "I'm here to pay", the paper's terms, and the door-camera page (12 Nov)

Options were put to the owner first; chosen and built:

- **One word: seat.** 38 sentences people read, in the server's
  messages and both apps, said "space" and now say "seat" (only quoted
  sentences changed, never code names). "Reserve a seat", "Seats left",
  "Book a seat on your UV Express route", "Paid: your seat is confirmed".
  No seat numbers are shown. CLAUDE.md's vocabulary note reversed.
- **Paying is the check-in, and "I'm here to pay".** The passenger's
  check-in button is now "I'm here to pay", offered while unpaid
  (location-checked as before); when accepted the trip's Dispatcher is
  told, once, "Lea is at Ecoland to pay ₱150 for seat SG-…"
  (`application/operations/check_in.py`). Marking a seat Paid also makes
  it `checked_in` -- paid at the terminal, so there -- except a home
  pickup's seats (`application/booking/cash.py`). A paid seat's presence
  cannot be undone (409); "Undo check-in" left the passenger's screen.
  The Dispatcher's list shows HERE TO PAY at the top of To collect, the
  Next line says how many are waiting, "Checked in" reads "At terminal".
- **The paper's terms.** Overbooking (never "double booking"),
  reservation lock (never "seat lock"; "space lock" would have clashed
  with "seat"), bounding box (never "hitbox"). The passenger's lost-race
  message no longer mentions a "seat map"; the concurrency test's output
  and the demo script use the new words. `MANUSCRIPT_CORRECTIONS.md` §14
  rewords objective 1.3.2.1 and the process section.
- **Door cameras** (Overview › Door cameras, Terminal Manager): one card a
  phone -- van and Dispatcher, Reporting / Silent since / Never reported,
  camera, GPS, lens and charging in words, battery, temperature (Hot at
  45 °C, in words), detections a second, aboard now against the list,
  two small charts for the last 2 h (detections a second; temperature,
  with the 45 °C line) -- two charts, never one with two scales -- with a
  hover reading, and the trip and today's door counts. Refreshes every
  15 s; a reading not sent says "not reported", never zero.
  `GET /devices/live` (office only) builds it from what the phone already
  sends (`device_heartbeats`, `passenger_events`); no phone change, no
  migration.

Tests on scratch: trip lifecycle 139/0 (new: paying is the check-in),
edge ingestion 95/0 (new: the live page, office only), passenger
journey no failures (reordered to the new flow: I'm here to pay, undo,
again, then Paid, then undo refused), unpaid release 57/0 (a paid seat
stands as checked_in), Dispatcher 30/0, home pickup 68/0, door check
65/0. The Dispatcher's "Here to pay" and the passenger's "Paid" notices
checked in the scratch database. `flutter test` 32 pass; both apps
analyze with no errors or warnings. Left as found: `test_operations.sh`
and `test_tier2.sh` are outside the suite and already failed (the
manifest stopped returning `seat_number` before today).

Door cameras, after looking at it on the live data (12 Nov): a lone phone
takes the full width (two to a row only with two or more); each chart
runs from the first report carrying its reading to the latest, points
placed by time, the line broken across a silence over 2.5 min, the 45 °C
line drawn only when readings come near it; an empty chart says whether
no reports came or the phone does not send that reading. The simulated
phone (`seed_live_now.py heartbeat`) now sends what the real edge app
sends -- battery, its temperature, charging, detections a second -- so
the page can be seen working; still test data, as the door counts are.
Screenshots: `docs/test-reports/ui-run-2026-11-11/c10`–`c13`.

### Special trip in one card; door cameras in everyday words (12 Nov)

- **Special Trips:** the request and its trip's start and departure are
  one card -- the request's facts, a divider, then "Start and departure"
  with its buttons (`TripLifecyclePanel(bare: true)`, new, draws the
  section without its own card). "1 passengers" and "1 pax" now read
  "1 passenger"; the trip sheet's totals say "15 of 126 seats", not "pax".
- **Door cameras, for a Terminal Manager who is not an IT person:** each
  phone opens with one answer in words and what to do -- "Working:
  counting passengers at the door"; "Not counting: the phone stopped
  sending at 11:58 AM. What to do: check that the phone is switched on,
  the SabayGo camera app is open, and it has mobile data or Wi-Fi"; the
  camera off, the view blocked, too hot, battery low, location off each
  have their own. Then plain checks (Camera: working · Location: on ·
  Camera view: clear · Charger: plugged in) and four tiles of one height:
  Battery (52 %, charging), Phone heat (Normal / Warm / Too hot, the
  degrees under it), Camera (Counting / Stopped, "looks at the door 8
  times a second"), Passengers inside now (against the list). The charts
  are behind "Show the last 2 hours". No speed is called good or slow --
  no operating rate is quoted before the in-van benchmark (CLAUDE.md);
  heat words use 40 °C (warm) and 45 °C (too hot), where phones commonly
  start slowing down to cool.
Checked at 1920 px (`docs/test-reports/ui-run-2026-11-11/c14`, `c15`,
`t02`). `flutter analyze`: no errors or warnings; console rebuilt.

### Timetable: "Add a new route…" opens the route form in Setup (12 Nov)

The Route list on "Add a regular departure" ends with **Add a new
route…** (green, a road icon). Choosing it keeps the current choice and
opens Setup › Route with the Add route form already showing, so a new
route is one choice away. The "Go to Route" button shown when no route is
in service does the same. How: `SetupScreen.requested` / `requestAdd`
(read once when Setup opens), `RoutesStep(startAdding:)` and
`StepFrame(addOnOpen:)`, set by the shell's Timetable link. Checked at
1920 px (`docs/test-reports/ui-run-2026-11-11/r10_route_dropdown.png`,
`r12_setup_route_form.png`). `flutter analyze`: no errors or warnings;
console rebuilt.

### Van cards one height; the statement in equal halves (12 Nov)

- **Van Status Board:** the van cards are laid out row by row, every card
  in a row one height (`IntrinsicHeight`, stretched), a short last row
  keeping the card width; inside each card the footer ("Can be
  dispatched" / "Next assignment waits for the fees", Trip sheet) sits at
  the bottom, level across the row.
- **Money:** the statement's two halves are equal in width as well as
  height (they were 7 : 5). The fare-lines table fits its half at 1920 px.
Checked at 1920 px (`docs/test-reports/ui-run-2026-11-11/v01_van_cards_equal.png`,
`s03_statement_halves.png`, `s04_statement_lines_halves.png`).
`flutter analyze`: no issues in either module; console rebuilt.

### SabayGo-System-Information.md (12 Nov)

`docs/SabayGo-System-Information.md`: the system as built, for matching
against the ACM manuscript in another Claude chat -- what it is, the
stack, roles, vocabulary, the trip flow step by step, the manuscript's
objectives 1.3.2.1–1.3.2.5 matched to the system (built / reshaped /
built differently), each app and console page, the door camera (how it
counts, the 9 Oct evaluation with its limits, the 18 Oct phone
benchmark), NAHGM, money and disputes, notifications and SOS, the
reservation-lock experiment, the 42 tables, the 144 endpoints, every
known difference from the manuscript (pointing at MANUSCRIPT_CORRECTIONS
§1–§14), limitations, test evidence and where things are. Figures taken
from `docs/benchmarks/`, the live database and the code.

`docs/SabayGo-System-Information.md` §21 (12 Nov): answers to the
comparing Claude's questions D1–D10 (driving flags and their settings;
trust rating stored but unused, trip history built; yolov8_audit_logs
and cash_remittances unused, 0 rows; no separate walk-in ledger; every
status value; the short-share warning; 640 × 480 camera, 320 px model,
7.5 GiB RAM; the public position endpoint, with a recommendation; map
refresh rates; the matching window dropped in 036), and a note that the
manuscript's screen tables show the old UI/UX. A stale edge-app comment
that still described the two-minute matching window was corrected
(`edge_app/.../link/Link.kt`).

### Plain words, CRUD in Messages and Trip Schedules, Post a trip window, compact Overview (12 Nov)

The owner's list of 12 Nov, for a Terminal Manager who is not an IT person.

- **Messages: create, edit, delete** (migration 040, `messages.edited_at`
  and `deleted_at`, with its down script). The console's **New message**
  lists every active Dispatcher, then each passenger with a seat from
  yesterday to a week ahead, labelled with the trip
  (`MessagingService._office_contacts`), and opens the thread (an existing
  one if there is one). A person edits or deletes **a text message they
  sent themself**: not a colleague's in the shared office inbox, not the
  other side's, not a home pickup's payment photo, which is proof
  (`_own_text_message`). A delete erases the text and keeps the row; the
  thread and the conversation list say "Message deleted". `MessageOut`
  carries `edited_at`, `deleted_at` and `can_change`, so each app offers
  Edit / Delete only where the server would allow them: under the bubble
  in the console, on a long press in the mobile chat.
- **Trip Schedules** (was "Timetable"): the tab, page, Setup step and
  every sentence. Each row has **Edit** (the add form, filled in, in a
  window) and **Delete** (asks first). `PATCH` and `DELETE
  /config/schedule-templates/{id}` (Terminal Manager). An edit never moves
  a trip already posted; a delete leaves those trips running with their
  link cleared (`fk_trip_template ON DELETE SET NULL`); moving one onto
  another schedule's time is refused in words (409), not a 500. Times
  read "5:30 AM", as on the Trips page.
- **Post a trip** is a button on the Trips header that opens a window,
  beside **Post 7 days of trips** and "N open for booking" (shows the
  passengers' list). The compact bar, the split view and their toggle
  are gone (`post_trip_box.dart`, `showPostTripDialog`).
- **Money words:** Owed → **Total fees**, Paid → **Total paid**, Due now
  → **Balance**; operator's share Owed / Given → **Total share** / **Paid
  to operator**; "Vans owing terminal fees" → **Vans with a balance**;
  badges "Balance ₱…"; the trip status "Fees due" → **Fees unpaid**. In
  Money, the record-payment window, the Van Status Board, the top strip,
  Disputes, the fee chart and the trip panel.
- **No technical words on screen:** Boarding Audit's evidence reads "Door
  camera record: someone got on or off 8 times … The record is
  untouched" (or "changed … do not rely on the count from there"), not
  door events and a hash chain. A phone's "token" is its **set-up code**
  in the console and the edge app's own screens; the Live vans note no
  longer names YOLOv8.
- **Subtext behind an (i):** `PageHeader` puts its description in an
  `InfoTip` beside the title (hover, Tab, or tap), so every page and
  Setup step opens on its work. `Panel` and `SidePanel` take `info:` the
  same way (the schedule form, Needs you today, Live vans, a route's
  stops, the open-for-booking list).
- **Review Starts:** the reason a trip is there is at reading size (16 px,
  with a mark), no longer small grey subtext.
- **Overview:** the three cards above the map are one size -- equal
  widths, one height (172 px) -- and compact: the donut smaller, Needs you
  today in two columns of short rows, the fees card down to the total,
  the balance and the paid bar (its three parts behind the (i)). The map
  takes the rest of the page and eight twelfths of the width (was 7 : 5).

Proof: `tests/integration/test_messages_schedules.sh` (new, in
`run_all_journeys.sh`) 50/0 on a scratch database; re-run on scratch
because they touch messages or schedules: home pickup 68/0, office
journey 62/0, trip lifecycle 139/0, group F 13/0, trip ticket (Day 1
data) 75/0. `flutter analyze`: no errors or warnings in either app;
mobile `flutter test` 32 pass. Migration 040 applied to the live database
after `db/backups/before_040_20261111_1514.sql`; both web builds rebuilt
and the launcher restarted. Checked in headless Brave at 1440 × 900:
Overview, Trips, the Post a trip window, Trip Schedules and its Edit
window, Messages and New message, Money. Edit and Delete under a message
were not tried on the live data (the journey covers them); the edge app's
renamed strings are not built here.

### Who may see where a van is: the group's decision C5 (12 Nov)

The van's live position (`GET /tracking/trips/{id}/position`) and its GPS
trail (`.../history`) were open to anyone, and the open trip search hands
out every trip id and plate, so anyone could follow any van and read the
whole trail of a trip that had arrived. The operator always drives, so
this was a person's location (RA 10173). The rule is now in
`application/tracking/access.py` (its docstring holds it): signed out,
nothing (401); a passenger, only a trip they hold a seat on (confirmed,
checked in or boarded) and only while it is boarding or on the road,
refused in plain words otherwise (403), with "not shown" before boarding
and after arrival (404, which the app's map already reads as "no report
yet", so a trip ending while the map is open stops the van, not an error
page); the office and crew, every van, live and afterwards. No app
change: the passenger app already sends its sign-in, and "Track the van"
is offered only on the passenger's own trip. Trip search is unchanged.
The family share link (option D) is not built. D8 in
`docs/SabayGo-System-Information.md` rewritten to match.

Proof: `tests/integration/test_van_location_access.sh` (new, in
`run_all_journeys.sh`) 33/0 on a scratch database.

### Check before merging to main; YOLOv8 and NAHGM benchmarks (16 Nov)

The owner asked for a check of the console and the APKs and the models
benchmarked "to the max" before this folder goes to GitHub's `main`
(last pushed 9 Nov), by a fork and pull request from leyaaamy, which can
only read the repo.

**Checks.** The full journey suite on a scratch database: 1261 passed,
0 failed, 0 gaps (`docs/test-reports/journeys_20261116_151550.txt`).
`flutter analyze`: no errors or warnings in either app (only the
`use_null_aware_elements` style hint). Mobile `flutter test` 32 pass;
the console's one widget test passes with `--platform chrome` (the
console uses `dart:js_interop`, so it cannot load on the plain VM, as on
main). The passenger/Dispatcher release APK builds (60.7 MB), and its
binary holds none of the dev accounts or their password, so the sign-in
chips are not in a release build (KNOWN_ISSUES asked for this check).
The edge app's debug APK builds and its 15 unit tests pass; its release
build fails lint, as it does on main (KNOWN_ISSUES). In headless Brave,
on the live data, every console page as the Terminal Manager (14) and
as the Cashier (10; Door cameras, Trip Schedules, Review Starts and
Boarding Audit hidden) loaded with no failed API call and no browser
error.

**For the pull request**, `.gitignore` now keeps out what must not reach
a public repo: `db/backups/` (real accounts and records), the phone
backup under `edge_app/results/realme_backup_*/` (its device token and
101 door-camera frames), the COCO data, the manifest, the evaluation's
venv (a link to another drive) and personal editor settings.

**YOLOv8**, the full evaluation on CPU: all 1643 COCO frames, six
degradations, five thresholds, now also at the phone's input sizes
(`evaluate.py --imgsz`; `degrade.py --in-memory` applies the
degradations at read time and saves ~3 GB). At 640 px Table 1 is
identical to the 9 Oct run. At the deployed threshold 0.45, original
frames:

| input | MAE | exact | false alarm (Δ>0) | 1 hidden found | PC ms |
|---|---|---|---|---|---|
| 640 px | 0.339 | 74.7 % | 2.7 % | 77.5 % | 24 |
| 416 px | 0.384 | 74.3 % | 2.2 % | 76.5 % | 15 |
| 320 px (phone default) | 0.452 | 70.2 % | 2.3 % | 72.4 % | 11 |

The paper's figures are the 640 px run; the phone runs 320 px by
default, which finds one hidden passenger about five points less often.
Reports `docs/benchmarks/ai_count_2026-11-16_*_imgsz*.txt` (rows as
`.csv.gz`).

**NAHGM**, a new benchmark (`backend/scripts/nahgm_benchmark.py`): a
second-by-second drive along the real road of ECO-COT (OSRM over
OpenStreetMap, kept in `docs/benchmarks/nahgm_route_eco_cot_osrm.json`),
24 scenarios of GPS error, lost fixes and reported speed, scored through
NAHGM's own functions; then positions posted by N vans at 1 Hz to a
scratch backend. GPS error and lost fixes barely move the result; the
nearest-stop rule and straight-line distance do (KNOWN_ISSUES). One
uvicorn worker keeps 50 vans at p95 0.48 s; at 100 it falls behind.
Report `docs/benchmarks/nahgm_2026-11-16_1527.txt`.
