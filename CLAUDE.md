# SabayGo

Capstone project: a booking and fleet-management system for terminal-based
UV Express vans in Davao City, with A2Z Transport Cooperative as pilot
partner. BSIT, University of Mindanao.

**Final defence moved: the date waits on endorsement (was 20 October).**

**15 Oct: brief rev 603 arrived** (`docs/SabayGo-Changes-for-Claude-Code
(3).md`) and replaces `(1).md` (rev 514) as the spec. It reverses parts of
steps 4–5 below (boarding at stop 1 only, no camera pricing, Dispatcher
taps Depart, no grace timer, payment before Start). The delta, the
decisions (owner delegated them 15 Oct) and the roadmap R1–R10 are
`docs/GAP_REPORT.md` §9. **Where rev 603 conflicts with the rev 468/514
notes below, rev 603 wins.** Progress is recorded under "Rev 603
progress" at the end of this section.

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
**Next: R6, home pickup (brief 2.6; T30-T32, T41).** Not started; the
plan, worked out 15 Oct from the brief, `assisted_pickups` (024) and the
existing chat (014, `application/messaging/service.py`):
- **R6a, booking and the pin.** `POST /bookings/home-pickup` (the
  relative): two app bookings through `ReserveSeatUseCase` (the relative's
  and the beneficiary's, both from stop 1; the second gets
  `booked_for_other` + `is_home_pickup_seat`; if it fails, cancel the
  first), plus an `assisted_pickups` row. Refused while
  `home_pickup_max_route_m` is unset, and when the pin is further from the
  route than that (store `route_distance_m`). The relative pays each
  booking through the existing `POST /payments/checkout` (both bookings
  are theirs). **Move the route snapping out of `TrackingService.geotag`
  into a pure `tracking/geometry.py`** and use it in both places:
  importing NAHGM from the pickup or scan path makes an import cycle
  (NAHGM → trip_lifecycle → boarding). Activation: a valid scan of the
  relative's ticket → `qr_scan`; `POST /home-pickups/{id}/activate` by the
  trip's Dispatcher → `dispatcher_entry` + who; either only once the
  beneficiary's seat is paid. On the trip: `.../arrived` (the van at the
  pin), `.../close` {boarded | no_show} → `left_at`, `closed_early` when
  inside `home_pickup_wait_minutes`, `closed_by`, and the seat's booking
  boarded or no-show (still owed). **Two fixes this needs in
  `boarding.py`:** `DepartTripUseCase` must not turn a home-pickup seat
  into a no-show and release it at departure (it boards after), and a scan
  of a home-pickup ticket at the terminal is refused ("boards at the pin").
- **R6b, screenshot proof.** An image message in the trip chat
  (`attachment_*`, ≤ `chat_image_max_kb`, sniffed, kept in `storage/`,
  `retain_until` = today + `chat_image_retention_days`); the relative
  links it to the pickup (`proof_message_id`); the Dispatcher confirms →
  both bookings confirmed (V), `proof_confirmed_*`, 'Home Pickup Proof' to
  the Terminal Manager. **Pending holds expire in 10 min:** have
  `sweep_abandoned_holds` (`operations/guards.py`) skip a pickup's
  bookings while a linked proof awaits the Dispatcher, without touching
  `seat_repository.py`. A retention job for chat images comes with R8.
Then R7 disputes, R8 retention, R9 driving flags (reuse `geotag`; subtract
a pickup's `arrived_at`..`left_at` from the stretch time), R10 screens.

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
(boarding, the dev dispatcher@, passenger@ holds a ticket; leg 1
manifest = 4, so photograph 4 people for a match and 5+ for a flag),
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

Dev accounts: `passenger@` `dispatcher@` `manager@` `cashier@sabaygo.dev`,
password `sabaygo123`.

Journey tests need the backend venv on `PATH` (the webhook simulator is
run as plain `python`) and `backend/.env` exported, or every payment step
fails as "unpaid".

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
  passed, with a conductor-set fare. *(Superseded 13 Oct: roadside
  logging is blocked; a roadside boarding is a camera-detected,
  unrecorded boarding priced from the nearest stop.)* Anchoring forward would leave that
  stretch of road looking empty while someone sits in it, and the camera
  check would flag a real passenger as leakage.

Changing any of these is a schema migration, not a config change.

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
4. *(Superseded by rev 468: the model runs on the phone.)* **Phone camera
   as the AI capture device** — YOLOv8 stays server-side
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
- Automatic captures are in-process, like the hold sweep and the phone
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
