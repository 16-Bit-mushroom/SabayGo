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
