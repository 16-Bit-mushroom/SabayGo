# Gap report: repo vs change brief rev 468

Date: 13 Oct 2026. Compares the repo at `a300565` with
`docs/SabayGo-Changes-for-Claude-Code (1).md` (paper revision 468).
Nothing has been changed yet; every item in section 6 waits for a decision.

---

## 0. Timeline

CLAUDE.md gives the final defence as **20 October**, seven days from now,
and the development deadline (27 Sep) has passed. The brief is a redesign:
about 15 new or reworked tables, a new money model, a new detection
pipeline, two new staff roles, and an edge app that does not exist yet.
It does not fit in a week alongside defence preparation. Section 7
proposes a scope for each case; which one applies depends on whether the
date still holds.

---

## 1. Carries over as built

| Brief needs | Repo has it |
|---|---|
| Booking held to 14 under row-level locks | `seat_repository.allocate_seat()`, 50-request concurrency test, 0 double-bookings |
| QR ticket, scan verdicts at the door | `boarding_scans`, `POST /scans` (valid / already boarded / unpaid / wrong stop / wrong trip) |
| Gateway payment, result recorded, money not held | PayMongo checkout, verified webhook only, sandbox in development |
| Passenger check-in | Geofenced, advisory, undoable (migration 012) |
| Cash pasabay logged by crew, offline-tolerant | Walk-in and roadside bookings; `client_request_id` makes a retried log idempotent (015) |
| Trips created from the timetable days ahead | `schedule_templates` → `generate_trips.py`, `advance_booking_open_days` |
| Fares terminal-to-terminal with `EffectiveFrom` | `fare_matrix` (keyed per route by stop sequence; see 3.6) |
| Stop zone around each terminal | `terminals.geofence_radius_m`, haversine in `check_in.haversine_m` |
| Never fabricate evidence | AI node returns 502 rather than a count; SOS never reports an unsent SMS. Same rule as the brief's Unaudited mark |
| Notifications to staff | `notifications` + console bell (needs new types and audiences) |
| Settings edited by the office | `cooperative_policies` + Rules & Settings page |
| Export to xlsx/csv | Revenue export only (`openpyxl`) |
| One-command demo | `run.sh`, `reset-dev.sh`, demo dataset |
| SOS, messaging | Built (016, 014). Brief: supporting only, keep or drop [OPEN] |

---

## 2. Exists but must change

| Area | Repo now | Brief | Size |
|---|---|---|---|
| Roles | `passenger, conductor, driver, coop_admin, admin` | `passenger, dispatcher, terminal manager, cashier`. Driver and operator are not users | M: enum migration like 010, every guard, both apps, seeds |
| Operator | Not modelled. `driver` is a login with `driver_credentials` | `operators` roster row, no login, licence moves here; `vans.operator_id` NOT NULL UNIQUE | M |
| Trip columns | `van_id`, `driver_id`, `conductor_id`, status, `departed_at`, `completed_at` | ~18 columns: assignment, start mode, review, audit status, departure source, change log, copied driver name/licence/plate (4.3) | M |
| Timetable | `default_van_id / driver / conductor` ("usual van") | No usual van or Dispatcher | S: drop three columns |
| Status words | `departed` | `En Route` | S: map, don't rename |
| Money model | `cash_remittances` per trip: crew hands the office *all* cash; expected vs declared vs received | Operator keeps fares and remits **15 % of gross daily per van**; V/D/U income groups, Equation (2), fare lines, held lines, reopen rule, disputed share | L: new tables; `cash_remittances`, `v_trip_revenue_reconciliation` and the Fares & Cash page are superseded |
| YOLOv8 check | Server-side headcount of one frame vs manifest per leg (`yolov8_audit_logs`, `auto_trigger.py`) | Door-line crossing per person, matched to scans and logs. Snapshot headcount survives only as the drift check | L |
| GPS | `trip_location_pings` every 15 s, nearest-node matching, ETA. **Only `tracking_simulator.py` posts pings; no app does** | 1–2 s from the edge phone, snapped to the route line, distance from start, stretch number; no ETA | M |
| Route model | `route_stops.offset_minutes` only | `route_stretches`: from-distance, length, speed limit, stop-zone radius, expected time | S |
| Special trips | Office creates them | Passenger requests, Terminal Manager approves, sets fee, assigns | M |
| Settings | Key-value, current value only; values snapshotted onto each trip | Key-value with `EffectiveFrom` | S |
| Notifications | `audience` ENUM(`passenger, coop_admin, driver, conductor`) + `user_id` | Recipient type Passenger / Dispatcher / Manager / Cashier, 10 new types | S |
| Passenger live map + ETA | Built 28 Sep | Out of scope (non-goal) | S: remove or hide |
| Driver headcount | `driver_headcounts`, `drive_panel.dart` | Driver is not a user | S: retire |
| `yolov8_audit_logs.DriverID` | Never existed; nothing to remove | | none |

---

## 3. Missing

1. **Door-event pipeline**: intake API (DeviceID, offline batches, idempotent), NAHGM geotag (interpolate between GPS readings, snap to route), matching (±`MatchWindowS`, each record used once, FIFO ticket-count rule at each stop), `passenger_events`, capacity alert above 14, side-pickup flag, estimate confirm/dismiss.
2. **SHA-256 hash chain** over a trip's door events, including `SnapshotHash`. Genesis value is [OPEN]; brief advises one derived from `ScheduleID`.
3. **Driving flags**: overspeed, slow stretch, unscheduled stop, en-route stop; `driving_events`.
4. **Daily remittance**: `remittances`, `remittance_lines`, held lines for unreviewed starts, reopen on late lines, Cashier payment record.
5. **Trip start rules**: assignment at the van's turn (Cashier fallback + alert), manual Start/Depart, auto-start job (assigned van, then phone-detected van, then "Trip Not Started"), review hold, void / change van by Terminal Manager only, Completed on aboard = 0 or "Arrived".
6. **Phone pool**: `edge_devices`, `device_checkouts`, heartbeat, silent detection, Unaudited reasons (`No_Phone`, `Silent_At_Start`, `Lost_En_Route`, `Lens_Blocked`), stored-report back-fill.
7. **Disputes**: table, record at the counter, Terminal Manager decision, withheld share.
8. **Member roster**: operators / vans / dispatchers with validation, import with row preview and rejected-row download, CSV/PDF export, `data_transfers`.
9. **Retention job** with the pending-estimate and open-dispute safeguards.
10. **Edge app**: none. `ai_capture_app/` is a Flutter app that photographs and uploads to the server-side model; it does no on-device detection or tracking.
11. **Screens**: Start Trip, Review Automatic Starts, Boarding Audit, Remittance, Van Status Board, Phones, Disputes, Member Records, passenger Request a Special Trip.
12. **Unassigned door-event list** for events that match no open trip (rule 12).

---

## 4. Conflicts with standing project rules

These are written into CLAUDE.md as rules. The brief overrides them, so
each needs an explicit yes before code changes.

1. **YOLOv8 placement.** CLAUDE.md: "YOLOv8 stays server-side, never on the edge device." Brief: YOLOv8n + ByteTrack on the phone.
2. **Roadside fare anchor.** CLAUDE.md invariant: a roadside pickup is recorded from the *previous* terminal passed. Brief: price from the *nearest* stop, "configurable". The sample trip depends on nearest: E13/E14 price Toril→Digos and E15 prices Sta. Cruz→Digos.
3. **Space reuse.** The thesis file lets one space carry two passengers whose journeys do not overlap (capacity per leg). Brief: "strictly 14 passengers per van". Per-leg capacity already keeps the number aboard ≤ 14 on every stretch, so both can hold, but the "Before" column of the brief's table reads as if space reuse is dropped. Which is it?
4. **Paper stack vs code.** Brief section 10 still lists Firebase Authentication, FCM push and Google Maps as [PAPER]. Code uses JWT, polled notifications and OpenStreetMap; `MANUSCRIPT_CORRECTIONS.md` already has replacement wording for each.
5. **Contribution statement.** CLAUDE.md and the `seat_repository.py` docstring name segment booking and the headcount check as the contribution. Under the brief it is the revenue audit (door events → matching → Equation 2 → hash chain). Docs follow whatever is decided.

---

## 5. Brief [ADVICE] items

| Advice | Follow? |
|---|---|
| Native Kotlin edge app, YOLOv8n at 320–416 px, foreground services, Realme setup checklist | Yes for the final design. Phone recorded 14 Oct: realme 8 5G (RMX3241), Android 13, Dimensity 700 (MT6833), 7.5 GiB RAM (brief 5.1). No figure may be stated before benchmarking |
| Offline queue, clock sync, heartbeat 30–60 s, blocked-lens check | Yes, on the server side first (intake accepts late, ordered, idempotent batches) |
| Functional unique index for one open check-out per phone and per van | Yes; MySQL 8.0 in Docker is ≥ 8.0.13. Verify on the container |
| Genesis hash from `ScheduleID` | Yes |
| Provisional Unaudited flag until stored reports arrive | Yes |
| Retention as a scheduled job that logs deletions | Yes, same in-process pattern as `HoldSweeper` |
| Door line and seat mask stored per van | Yes, when the edge app exists |

---

## 6. Decisions needed

1. **Is the defence still 20 October?** Decides scope (section 7).
2. **Repo names vs paper names.** Recommend: keep snake_case repo tables (`trips`, `bookings`, `users`) and keep the status word `departed`; add a paper ↔ repo name table to the docs. Renaming `trips` → `TripSchedules` touches every query for no behavioural gain. The brief allows mapping (section 0.6).
3. **Staff as users.** Recommend: `users` stays the one login table, with roles `passenger, dispatcher, terminal_manager, cashier` (+ `admin` for the dev team, no screens). `TerminalStaff` and `Dispatchers` map to `users` + `staff_profiles`; `operators` is a new non-login table. Dispatcher sign-in stays email, which answers that [OPEN] item from the code.
4. **Existing drivers.** Recommend: migrate each `driver` user with credentials into an `operators` row, deactivate the login, and give every demo van one operator so the UNIQUE holds.
5. **Conflicts 4.1–4.5.**
6. **Brief [OPEN] items that block code**: hash genesis, retention mode default, how an independent van gets a trip, when a phone counts as missing, keep or drop SOS and messaging. Everything else [OPEN] can be built as a setting.
7. **Down migrations.** Repo migrations are forward-only. Recommend a `down/` script per new migration, since the brief asks for reversible ones.

---

## 7. Scope options

**A. Defence still 20 Oct (recommended in that case).** Build the part the
paper evaluates and the sample trip can prove:

1. Roles and operators migration; Dispatcher / Terminal Manager / Cashier wording in both apps; driver screens retired.
2. Door-event core on the server: route stretches, intake, geotag, matching, hash chain, capacity and side-pickup flags, driving flags, daily remittance with Equation (2), estimate confirm / dismiss.
3. A replay script for the paper's sample trip (section 12.1) that asserts ₱193.50 owed, ₱22.50 at risk, ₱216.00 if confirmed, the four flags and the 1.45 slow stretch. This is the regression test the brief asks for and the demo's backbone.
4. A detection stand-in: the laptop webcam running YOLOv8n with Ultralytics' built-in ByteTrack and a door line, posting door events to the same intake endpoint a phone would. The phone app later replaces only the sender. Same role the webcam already played for the Orange Pi.
5. Console: Boarding Audit and Remittance pages replacing Passenger Count Checks and Fares & Cash.

Trip-start rules, phone pool, disputes, roster import, retention and
special-trip requests go into the paper as designed and not yet built.

**B. Defence moved by several weeks.** The brief's own order (section 13)
in full, with the Kotlin edge app last, after a phone is benchmarked.

**C. Paper only.** No code change; the manuscript describes the built
system and the brief's design as future work. Lowest risk, but revision
468 then describes a system the demo does not show.

---

## 8. Decisions (13 Oct) and progress

| Question | Decision |
|---|---|
| Defence date | Moved; waits on endorsement. Scope **B**: the brief in its own order |
| YOLOv8 placement | On the phone (paper design), Kotlin edge app last, after benchmarking |
| Roadside fare anchor | Brief: nearest stop, configurable |
| Paper stack vs code | Keep JWT, polled notifications, OpenStreetMap; fix the paper |
| Space reuse | 14 is passenger capacity, per stretch as built. A freed space is resold only to a terminal-stop boarding; roadside is recorded and flagged, never sold |
| Contribution | Brief: revenue audit |
| Names | Keep snake_case repo tables; map paper names in docs |
| Staff as users | `users` stays the login table; operators are a non-login table |
| Existing drivers | Became operator rows; logins deactivated |
| Down migrations | `db/migrations/down/<version>.sql`, run by `db/rollback.sh` |

**Done — step 2a, roles and renames (migration 017).** `conductor` →
`dispatcher`, `coop_admin` → `terminal_manager`, new `cashier`,
`trips.conductor_id` → `dispatcher_id`, `operators` (Table 25 without
`import_batch_id`, which arrives with `data_transfers`), `vans.operator_id`
UNIQUE. Backend guards split into `MANAGER` (decisions) and `OFFICE`
(both office roles); the Cashier is refused rules, records, audit decisions
and staff creation. Mobile: Dispatcher only, driver panel removed (the
headcount dialog kept). Console: both office roles sign in; Special Trips,
Passenger Count Checks, Timetable and Rules & Settings are hidden from the
Cashier; Vans & Crew is read-only for the Cashier; trip panels show the
operator and the Dispatcher.

Verified: 017 applied to the pre-change dev database, rolled back to an
identical fingerprint (data, columns, indexes), re-applied; full journey
suite 157 passed, 1 failed (the known `--soon` reschedule fixture
conflict); mobile `flutter analyze` clean and 31 widget tests pass;
console `flutter analyze` clean.

**Not changed yet, deliberately.** Who may start and depart a trip (the
Dispatcher still can; the lifecycle step moves it to Cashier and Terminal
Manager). The timetable's "usual" van and Dispatcher. The cash remittance
model. Each belongs to a later step of the brief.

**Capacity, answered 13 Oct.** 14 is passenger capacity. Booking keeps
per-stretch capacity (no change to `seat_repository.py`); a freed space is
resold only to a terminal-stop boarding.

**Done — roadside logging blocked (13 Oct).** `POST /bookings/walk-in`
refuses `is_roadside_pickup: true` with 422 and writes nothing; the field
stays in the request only so a stale build, or a roadside entry still in a
handset's offline queue, is told so instead of being re-recorded as a
terminal walk-in. The Dispatcher can no longer set a fare: `fare_override`
is gone from the use case, and every cash fare comes from `fare_matrix`.
The manifest no longer reports `is_roadside_pickup`, `pickup_landmark` or
`fare_is_manual`; the columns stay for history until a contraction
migration. Mobile: no roadside mode on the walk-in screen; after
departure the manifest offers **Walk-in** (a later terminal) instead of
Roadside. The offline queue keeps its SQLite schema; a row an older build
queued as roadside is still sent with the flag, refused, and left visible
in the queue. Demo data: `BKG-A2Z-L207` dropped; the two roadside rows on
completed trips (P110, P125) stay as pre-468 history. Console: the trip
panel's "picked up on the road" note is gone.

Verified: `test_roadside.sh` (now the refusal test) 10 passed; dispatcher
journey 23 passed, office journey 47 passed; mobile `flutter analyze` no
errors or warnings, 31 widget tests pass; console `flutter analyze` no
errors or warnings. `test_remittance.sh` has 2 failures that are the same
at `39db1aa` (its second section re-opens boarding on a trip whose cash
was already received), so not caused by this change.

**Done — step 2b, new tables (migration 018).** Tables 28–39 of the brief,
reconciled with the repo (paper → repo names in the migration header):

| Brief | Repo |
|---|---|
| 28 Route_Stretches | `route_stretches`. Stretch *k* = stop *k* → *k*+1, like `trip_legs`; From/ToTerminalID are the terminals at those stops, both enforced by foreign keys to `route_stops` instead of copied |
| 29 Passenger_Events | `passenger_events`. `event_id` generated on the phone (idempotent re-send). MatchedBookingID and MatchedLogEntryID are one `matched_booking_id`: a cash log is a walk-in booking. Stops are stop sequences, as in `bookings` |
| 30 Driving_Events | `driving_events` |
| 31 Nahgm_tracking_logs | `trip_location_pings` (011) + `distance_from_start_m`, `stretch_no` |
| 32 Remittances | `remittances`, `rate_pct` = 15.00. Supersedes `cash_remittances` once the money step lands |
| 34–36 | `special_trip_requests`, `remittance_lines`, `data_transfers` (+ `operators.import_batch_id`) |
| 37–38 | `edge_devices`, `device_checkouts`, one open check-out per phone and per van by functional unique index (MySQL 8.0.46 on the container) |
| 39 Disputes | `disputes`; `raised_by` has a foreign key, since all staff are `users` |

The brief's rules that a row can break on its own are CHECK constraints:
exactly one disputed item matching the subject, no withheld share on a
driving flag, a resolved dispute has an outcome and a noted decision, an
adjusted share within the disputed one; a matched event names its booking
and only an unrecorded one is priced or decided; a stored snapshot has its
hash and a deleted one has no URL; gross = fare × count on a line; an
approved special trip has its fee, trip and reviewer; at most 14 on a
request.

Not in 018: **27 Fare_Matrix** stays keyed per route by stop sequence (the
brief keys it by terminal pair; booking reads it, so it changes with the
code). **33 TerminalSettings** is `cooperative_policies` + `effective_from`
in the settings step (key and every read change). The **7.3 edits** (trip
start/review/audit columns, booking and van columns, notification
recipients) are the next migration. No ORM models yet: nothing writes
these tables.

Verified: applied to the 017 dev database, rolled back to an identical
schema and data fingerprint, re-applied; a constraint smoke test (19
refused cases, each by the constraint it targets, 11 accepted) inside a
rolled-back transaction; clean rebuild via `reset-dev.sh`; office journey
47 passed, dispatcher 23 passed, `test_auto_audit.py` all passed (writes
GPS pings).

**Done — step 2c, column edits (migration 019, 13 Oct).** Decisions:
`trips.route_id` may be NULL, for a van rental (decided); booking
origin/destination terminals and payment status are derived, not stored
(decided); `fare_matrix` stays per route by stop sequence (decided). The
last two, and `IsSpecial`, are written up for the paper in
`MANUSCRIPT_CORRECTIONS.md` §11.

| Brief 4.3 / 7.3 | Repo |
|---|---|
| TripSchedules start, review, audit, departure-source, change columns; DriverName, DriverLicenseNo, VanPlateNumber | added to `trips`; start/review/departure stay NULL on trips that ran before 019 (never recorded); the three copies are backfilled from the trip's driver and van |
| IsSpecial; AssignedVanID NULL | `is_special_trip` AND `route_id` NULL; `van_id` was already NULL-able |
| Vans validation, ImportBatchID, photo URLs | added; existing vans `pending`, as operators were in 017. Photo column names (front, rear, left, right) are a guess at the paper's four; rename if Table 9 names them otherwise |
| Dispatchers validation, ImportBatchID | on `staff_profiles` |
| LogBookEntries.LoggedBy | `bookings.logged_by`, written by the walk-in endpoint |
| Notification types | ten added to `notifications.type` |
| Bookings Origin/DestTerminalID, PaymentStatus/Reference; Fare_Matrix by terminal pair | not stored (above) |

CHECKs: a trip without a route must be special; a manual start names its
starter and an automatic one does not; a reviewed start names its
reviewer; unaudited ⇔ reason and time; a change has who, when and a note.
The down script narrows `route_id` and the notification ENUM first, so
it refuses, changing nothing, while a routeless trip or a new-type
notification exists.

Verified: round trip pre-019 → 019 → pre-019 gives an identical schema and
data fingerprint (the backfill keeps `trips.updated_at`); rollback refused
with a routeless trip present, fingerprint unchanged; smoke test 7
refused / 4 accepted; clean rebuild; roadside 10, dispatcher 23, office
47, passenger 40 + the known `--soon` reschedule failure,
`test_notifications` and `test_auto_audit` all passed; walk-ins carry
`logged_by`.

**Done — contraction (migration 020, 13 Oct).** Dropped the `driver`
role value (users, notifications, SOS), `driver_credentials`,
`trips.driver_id`, `schedule_templates.default_driver_id`, the four
roadside/manual-fare booking columns, and `driver_headcounts`. The
Dispatcher's manual headcount is retired with its table (endpoint,
mobile dialog and widget test, journey step, demo-script step): it was a
self-report by the audited person that nothing read, and brief 5.2's
per-stop cabin snapshot is the drift check. The revenue view drops its
two roadside sums and LEFT JOINs routes, so a rental trip (no route)
keeps its fares. Demo data: the two "Roadside - …" walk-ins on completed
trips renamed, and the audit note that told a roadside story reworded.

A preflight (stored procedure + SIGNAL) stops 020 before any change if a
driver account, a 'driver' notification or SOS row, a trip that ran with
a driver but has no copied name, or an uncopied licence exists.

Not dropped, and why: the timetable's default van and Dispatcher
(`generate_trips.py` staffs trips from them until step 4's assignment at
the van's turn); `vans.operator_id` NOT NULL (`POST /fleet/vans` creates a
van with no operator, and nothing creates an operator before step 3);
the legacy ENUM values `driver_issued` and `conductor_driver`.

Verified: preflight refused with a driver account present, fingerprint
unchanged; round trip on a clean 019 database gives identical data and
an identical schema except four CHECK clauses MySQL re-prints with a
`_utf8mb4` instead of `_latin1` literal after any ALTER of their table;
clean rebuild; roadside 10, dispatcher 22 (one headcount check fewer),
office 47, passenger 40 + the known `--soon` failure, notifications and
auto-audit all passed; mobile analyze clean of errors/warnings, 29 widget
tests pass.

Consequence for the paper's sample trip (brief 12.1), which the group
must redraw: E15's cash log can no longer exist, so E15 is an unrecorded
boarding (Sta. Cruz → Digos, ₱30, matched FIFO to Digos with E13 and
E14). Remittance owed ₱189.00 (was ₱193.50), at risk ₱27.00 (was ₱22.50),
if all confirmed ₱216.00 (unchanged); the capacity alert still fires. The
dispute example (T27) becomes: E13 and E14 confirmed, owed ₱211.50; E14
contested, due now ₱200.25. An honest Dispatcher's roadside cash now shows
as an estimate until the Terminal Manager confirms it.

**Done — step 3, settings and roster (migration 021, 14 Oct).**

| Brief | Repo |
|---|---|
| 33 TerminalSettings (SettingKey, EffectiveFrom, SettingValue, UpdatedBy, UpdatedAt) | `cooperative_policies` keyed (`policy_key`, `effective_from`) + `updated_by`; a change is a new row, the value in force is the latest that has taken effect. `GET /config/policies/{key}/history` lists them |
| RemittanceRate 0.15, StartOpensMin, StartGraceMin, HeartbeatGapS | `remittance_rate_pct` 15.00, `start_opens_minutes` 30, `start_grace_minutes` 10, `heartbeat_gap_seconds` 120 |
| RetentionMode, RetentionDays | `retention_mode`, `retention_days`, shipped **unset**: the paper names no default (4.5). The retention job (step 7) must delete nothing while unset |
| Vans.OperatorID NOT NULL UNIQUE | NOT NULL now; UNIQUE since 017 |
| Roster, validation (8) | Operators added and edited by the Terminal Manager; validation of operators, vans and Dispatchers by the Terminal Manager only; a van needs its four photos to validate; an edit or a new photo returns a validated record to Pending |
| Import with preview (8) | Operators and vans, CSV or XLSX template; every row checked (required fields, plate / licence / CPC format, duplicates on file and in the file, one van per operator); preview saves nothing; confirm re-checks and saves passing rows Pending under one batch; rejected rows with a reason column download and re-upload as-is |
| Separation of duties (3) | Whoever imported a record cannot validate it; the Cashier may import, only the Terminal Manager validates |
| Export (8), 36 Data_Transfers | Any list as CSV or PDF; backup columns re-import unchanged; LTFRB cross-check (plate, CPC, operator, validation and date) is vans only; every import and export logged |
| 37–38, phone custody (5.5) | Terminal Manager adds and retires phones; Cashier or Terminal Manager checks one out to a Dispatcher and van and records the return and condition; one open check-out per phone and per van; the last status report comes back as warnings (never sent, silent, camera, GPS), never a refusal |

Decided here, not in the brief: a phone check-out does not require the
van or Dispatcher to be validated (the brief requires validation for trip
assignment, step 4, not for custody). Formats: plate `ABC-1234` (three
letters, three or four digits), licence as printed `N01-23-456789`; the
CPC rule (letters, digits, `-`, `/`, `.`) is a placeholder until A2Z's
binder shows the real layout (brief 14). `van_photos` (003) is unused:
the four photos are the 019 columns. Dispatchers are not imported (each is
a staff login); they are exported.

Verified: 021 round trip on a clean 020 database identical; on the
earlier dev database identical data, and the schema differs only in the
order MySQL prints two `vans` unique keys after the column change; the
down script refuses, leaving the database unchanged, once a policy has
history; clean rebuild; `test_roster.sh` 94 passed; journey suite 157
passed + the known `--soon` reschedule failure (office journey now adds
the operator before the van); `test_group_f` 11, `test_roadside` 10;
console analyze clean of errors and warnings. The console widget test
does not load on the VM (`download.dart` imports `dart:js_interop`), as
before this change.

**Done — step 4, trip lifecycle (migration 022, 14 Oct).** Rules in
`application/operations/trip_lifecycle.py`; endpoints in
`api/v1/operations.py`.

| Brief (4.2) | Repo |
|---|---|
| Rule 1, trips days ahead, no usual van | generator leaves `van_id` / `dispatcher_id` NULL and skips a departure already past; 022 drops `schedule_templates.default_van_id`, `default_conductor_id` |
| Rule 2, assignment at the van's turn | `PUT /trips/{id}/assignment` (Terminal Manager, Cashier); validated van of a validated, active operator, validated Dispatcher, no clash; `assigned_by` / `assigned_at`; the Cashier's raises `assignment_by_cashier` |
| Rule 3, scanning before the start | unchanged: scan and walk-in check the assignment, not the status |
| Rules 4–5, start | `POST /trips/{id}/start` (office), from `start_opens_minutes` before departure; blocked without van and Dispatcher (T8); copies operator name, licence and plate; warnings: expired licence (+ `system_alert` to the Terminal Manager), no phone with the van (Unaudited `no_phone`, `unaudited_trip` to the office and the Dispatcher, T22), the Dispatcher's phone on another van (T10) |
| Rule 7, fallback | `start_overdue_trips` every 60 s (`core/periodic.py`): `auto_assigned`, review `pending`, `unconfirmed_trip_start` (T3, T9); no van → `trip_not_started`, once (T7). Also when a ping leaves stop 1 with a boarding counted |
| Rule 8, review | `POST /trips/{id}/start-review` (Terminal Manager); a changed van needs a reason (T4) |
| Rule 9, departure | `POST /trips/{id}/depart` (office), a started trip only; or a ping leaving stop 1 with a boarding counted; `departure_source` |
| Rule 10, void and change van | `POST /trips/{id}/void` (scheduled or boarding), `POST /trips/{id}/change-van` (started), Terminal Manager only (T11); `change_note` keeps the earlier van and operator |
| 4.1 Completed | `POST /trips/{id}/arrive`, the trip's Dispatcher (T26) |

Decided here, not in the brief: a void cancels nothing else (no refunds)
and tells app ticket holders to see the office. The fallback reaches back
12 hours, so a server back from a weekend does not start Friday's trips.
"Boarding counted" is a `boarded` booking until door events exist. A GPS
fault warns without marking Unaudited (no reason in 4.4 fits). A cash
walk-in is now created `boarded`: as `confirmed` it read "not yet" on the
manifest, and Depart made it a no-show and released its space.

Left for step 5: `auto_detected`, `silent_at_start`, `lens_blocked`,
completion at aboard = 0, events between trips (rule 12). Left for step 6:
the statement leaving out `pending` starts, fare lines at review, the
reopen rule (T5).

Verified: `test_trip_lifecycle.sh` 80 passed; journey suite 331 passed +
the known `--soon` reschedule failure; `test_remittance` 10 passed (its
second section now uses the second fixture trip: one handover per trip
per Dispatcher), `test_roadside` 10, `test_group_f` 11,
`demo_rehearsal.sh` complete; 022 rolled back and re-applied; mobile
analyze clean, widget tests pass; console analyze clean of errors and
warnings.

**Done — step 5, server half (migration 023, 14 Oct).** `api/v1/edge.py`;
rules in `application/edge/` (`ledger.py` which trip, `evidence.py`
Unaudited, `ingestion.py` the uploads).

| Brief | Repo |
|---|---|
| Authenticated upload with DeviceID (13, step 5) | `X-Device-Token`, one per phone, issued when it is added, re-issued by the Terminal Manager (old one revoked), SHA-256 only in `edge_devices.token_hash`, cleared on retire |
| Offline-tolerant, idempotent | every upload a batch of up to 500; events keyed by the phone's `event_id`, reports by (phone, `recorded_at`); a resent batch stores nothing new |
| Clock sync (5.3) | `GET /edge/session` returns server time; a batch more than 2 min in the future is refused whole |
| Heartbeat into Edge_Devices, stored reports after reconnect (4.4) | `device_heartbeats` (new, not in the paper) keeps every report; `edge_devices` shows the newest |
| Rule 11, events by van and time | phone → check-out at that time → van → that van's trip at that time |
| Rule 12, unassigned list | `held_door_events` (new); 'Trip Not Started' per van, once while events wait; moved when a trip of the van starts |
| Unaudited (4.4; T12, T13, T22, T23) | at start: `no_phone`, `silent_at_start`, `lens_blocked`; in the trip: covered lens at once; silence alerted at once, `lost_en_route` only if the stored reports or the trip's end leave it uncovered |
| Snapshot + SnapshotHash (5.1, 4.5) | `PUT /edge/events/{id}/snapshot`, image bytes sniffed, ≤ 2 MB, `storage/snapshots/` (not public), SHA-256 on the event, never replaced |
| GPS 1–2 s from the phone (5.1) | `POST /edge/fixes`, onto the trip by time, through the existing NAHGM path |
| Rule 7 `Auto_Detected` (T6) | held boardings at a terminal, then a fix outside it, no trip: the waiting trip on the van's route, else a new one |

Decided here, for brief 4.6's open question (how a van running outside
the timetable gets a trip): the system creates it. When the phone of a
van with no trip records boardings at a terminal and the van then leaves,
the van gets the trip on its own route from that terminal still waiting
for a van, nearest in time. If there is none, the system creates an
**Unscheduled run** on the van's route from the first boarding. Either
way the trip is started `auto_detected`, departed as detected, and held
for the Terminal Manager's review, who decides what the run was. Nothing
the phone counted is lost, and nothing reaches the statement without a
person. If the van's registered route does not start at that terminal,
the events stay held and the Terminal Manager is alerted. Also decided:
a report covers time only when the camera and the GPS both worked (the
brief's "camera and GPS working through the gap"), and a camera that
reports itself not working at the start counts as `lens_blocked`.

Verified: `test_edge_ingestion.sh` 66 passed; `test_trip_lifecycle.sh`
80 (its audited-start case now has the phone report first); journey
suite 395 passed + the known `--soon` reschedule failure; 023 rolled back
and re-applied.

Left for the phone half: the benchmark on the real phone, then the
Kotlin edge app. Left for step 6: the hash chain over events (with
`SnapshotHash`), matching, nearest-stop and stretch on each event, the
capacity alert, and completion at aboard = 0.

---

## 9. Revision 603 delta (15 Oct)

`docs/SabayGo-Changes-for-Claude-Code (3).md` replaces the rev 514 brief
(`(1).md`). It rebuilds the money and boarding model: **one boarding
point (the starting terminal), a passenger list complete before
departure, and the 15 % paid at the counter before Start.** The return
leg is outside the system. The camera prices nothing. Nothing below has
been changed yet.

### 9.1 Built work that rev 603 reverses

| # | Built (rev 514) | Rev 603 | Where |
|---|---|---|---|
| R1 | Boarding at any terminal stop; a space freed by an alighting is resold | Boarding **only at the starting terminal, before departure**; strictly 14 per van; fare lines by drop-off terminal | `bookings.py` (`boarding_stop ≥ 1`), search, reserve, reschedule, walk-in |
| R2 | Unrecorded boarding priced from the nearest stop, flagged as a side pickup | **No camera pricing.** Before departure: aboard vs listed (fewer = no-show; more = Dispatcher fixes the list or types a reason). After departure: the 14 cap only | step 6 not built; 018 columns |
| R3 | Depart is office-only; the Dispatcher's only action is Arrived | **Dispatcher taps Depart** (primary), Cashier or Terminal Manager may too; refused while an unlisted boarding is pending | `operations.py:254`, `mobile/` |
| R4 | `departure_source` ('confirmed','detected') | ('dispatcher','staff','gps') | 019 |
| R5 | `start_overdue_trips` starts a trip at departure + `start_grace_minutes` | **No grace timer**; `StartGraceMin` removed. The system starts a trip only when the van departs | `trip_lifecycle.py:616`, 021, `core/periodic.py` |
| R6 | GPS departure: one ping outside stop 1's stop zone | **N consecutive readings** outside a **terminal zone** while moving, with a boarding counted; `DepartZoneRadiusM`, `DepartReadings` from a site survey, not invented | `nahgm.record_ping` → `van_left_origin` |
| R7 | No trip for a detected departure → system creates an **Unscheduled run** | "No separate independent-van path": a van outside the timetable runs a **special trip**, from an app request or a counter entry | `trip_lifecycle.py:294` |
| R8 | An event goes to the van's started trip, else its next trip whose start window is open | The trip the van **is assigned to**, by time, started or not | `ledger.py` rule 2 |
| R9 | `retention_mode` + `retention_days`, shipped unset | One `RetentionDays`, **30 assumed**; no mode | 021 |
| R10 | Notification types `unrecorded_boarding`, `side_pickup` | Removed. New: Departed With More Than Listed, Left Unpaid, Payment Block Override, Home Pickup Proof | 019 |
| R11 | `passenger_events`: `side_pickup`, `dest_stop_sequence`, `estimated_fare`; `match_status` 'unrecorded','mismatch'; `resolution_status` ('pending','confirmed','dismissed') | Dropped. `match_status` gains 'unlisted'; `resolution_status` ('not_needed','pending','listed','explained') + `resolved_by`, `resolution_note`; new `pre_departure` | 018 |
| R12 | `remittances.estimated_income`, `amount_at_risk`; `remittance_lines.income_group` 'estimated'; `disputes.subject` 'estimated_fare' + `event_id` | Dropped. New `remittances.held_share`, `handed_over_by`; `remittance_lines.is_top_up` | 018 |

R1 does not touch the allocator. With every boarding at stop 1 the
per-stretch count already equals the per-van count (the busiest stretch
is the first), so `seat_repository.py` and the 0-double-booking result
stand; the restriction belongs at the booking entry points. What goes is
the vocabulary claim in CLAUDE.md that one space carries two paying
passengers on one trip.

Rule 14 (events with no assigned trip wait, 'Trip Not Started') and rule
13 (the phone pauses at arrival, resumes at the next assignment) both
hold. The server's part of the pause is telling the phone, through
`GET /edge/session`, whether its van has an assigned trip that has not
completed.

### 9.2 New in rev 603, not built

- **Payment block.** Start refused until the trip's share is recorded
  (`payment_status` 'paid' or 'overridden'). Assignment refused while the
  van's balance (`owed + held − settled`, less disputed shares) is above
  zero. Terminal Manager override with a written reason; the Cashier
  cannot. GPS auto-start is never blocked: 'left_unpaid', `held_share`,
  'Left Unpaid' alert.
- **Cashier payment record** with the handing Dispatcher; **list lock**
  (`list_locked_at`) at payment or departure, whichever first;
  cancellation removes the seat and its share before the lock, refused
  after; a seat added after payment is a **top-up line** and re-blocks
  Start.
- **Crew toggle** (`trips.crew_aboard`): the Dispatcher is not a
  boarding and not counted toward 14.
- **'Not a passenger trip'** (Table 40 `Non_Passenger_Moves`): nothing
  started, nothing owed, GPS fallback off; a passenger seen aboard starts
  the trip `auto_detected`, pending review.
- **Home pickup** (Table 41 `Assisted_Pickups`, `bookings.booked_for_other`,
  `is_home_pickup_seat`): Book for Someone Else, relative's own seat,
  map pin accepted within `HomePickupMaxRouteM`, digital payment only,
  activation by QR or Dispatcher entry, up to `HomePickupWaitMin` wait,
  close early / no-show, wait subtracted from the stretch time, not an
  unscheduled stop.
- **Messages** (chat, now required): image attachments for the payment
  proof, `ChatImageMaxKb` 10240, `ChatImageRetentionDays` 30, Dispatcher
  confirms the proof to the Terminal Manager.
- **Walk-in special trip** at the counter (`special_trip_requests`:
  `passenger_id` NULL, `customer_name`, `customer_contact`, `entered_by`,
  `fee_note`); fee paid before the van leaves; a van may decline.
- **Trips columns:** `payment_status`, `list_locked_at`, `crew_aboard`,
  `payment_override_by/at/note`.
- **Snapshots: Terminal Manager only**, in the API. No endpoint serves
  them yet; the first one must check the role.
- **Settings:** `depart_zone_radius_m`, `depart_readings` (survey),
  `home_pickup_wait_min` 10, `home_pickup_max_route_m` (to be set),
  `chat_image_max_kb` 10240, `chat_image_retention_days` 30.
- **Van status board:** shows which vans still owe their last trip's
  share.

### 9.3 Unchanged

Roles, roster, import/export, phone pool and check-out (step 3); phone
tokens, upload endpoints, heartbeats, Unaudited rules, held events and
snapshot storage (step 5); assignment rules, void and change-van
(Terminal Manager only), start review, Arrived, expired-licence and
no-phone warnings (step 4). The hash-chain genesis is still [OPEN], and
the brief still advises a value derived from the trip ID. Booking
origin/destination and payment status stay derived, not stored
(`MANUSCRIPT_CORRECTIONS.md` §11); rev 603 still lists them as columns.

### 9.4 Decisions (15 Oct) and roadmap

The owner asked for Claude's recommendations to be applied. Decided:

1. **Boarding at stop 1 only**, refused at search, reserve, reschedule
   and walk-in. `seat_repository.py` is not touched.
2. **One migration (024)** drops the estimate and side-pickup columns and
   adds the rev 603 columns and tables, with its down script.
3. **`retention_days` = 30**, `retention_mode` removed. Nothing deletes
   until the retention job (R8) exists.
4. **Terminal zone and N ship unset**: GPS departure is off until the
   Terminal Manager sets both. Tests and the demo seed set illustrative
   values.
5. **The Unscheduled run is removed.** A detected departure with no
   waiting trip on the van's route leaves the events held and alerts
   the Terminal Manager.
6. **Hash-chain genesis** = SHA-256 of `"sabaygo:" + trip_id` (the
   brief's advice; the owner delegated the choice).
7. **Chat** extends the existing `messages` table (migration 014) with
   the attachment columns; no second table.

Roadmap, in the brief's order (§13), each step tested and committed
before the next:

| Step | Brief | What |
|---|---|---|
| R1 | 2 | Migration 024: columns, Tables 40 and 41, chat attachments, settings |
| R2 | 2.4 | Boarding at the starting terminal only |
| R3 | 4 | Lifecycle rework: statement and fare lines, Cashier payment, list lock, top-ups, payment block and override, Start, Dispatcher Depart, GPS departure (N readings), automatic start at departure, Left Unpaid, crew toggle, Not a passenger trip; grace timer and Unscheduled run removed |
| R4 | 5 | Edge: events to the assigned trip; the session tells the phone to pause |
| R5 | 6 | Checking: pre-departure list match, unlisted fix or reason, capacity alert with general location, hash chain, completion at aboard 0 |
| R6 | 2.6 | Home pickup and chat image proof |
| R7 | 2.1 | Disputes |
| R8 | 4.5 | Retention job |
| R9 | 6.3–6.4 | Driving flags with the home-pickup wait |
| R10 | 9 | Screens |

---

## 10. Revision 721 delta (2 Nov)

`docs/SabayGo-Changes-for-Claude-Code.md` (2026-11-02) replaces the rev
603 brief (`(3).md`). The revised ACM PDF carries the same text — its
filename still says rev 603, its content does not.

One decision drives everything: **A2Z handles only cash.** The study
takes no online payment. A passenger still reserves a seat in the app
and gets a short **booking code**; the fare is paid in cash to the
Dispatcher at the terminal, who **marks the seat Paid**. The gateway,
the QR ticket and the e-ticket are gone, and T60 is an acceptance test
that nothing of them survives.

Two money changes follow. Income groups become **Booked (B)** and
**Walk-up (W)**, so Equation (2) is `ρ × (B + W)`. And A2Z's paper trip
ticket turns out to carry two fixed fees beside the 15 %: a **₱75 DCOTT
ticket for each trip** and a **₱50 parking fee for each van each service
day**, charged even when the van makes no trip. The three together are
the **terminal fees**; what is left of the cash is the **operator's
share**, handed to the operator at the counter and recorded by the
Cashier.

### 10.1 Built work that rev 721 reverses

| # | Built (rev 603) | Rev 721 | Where |
|---|---|---|---|
| S1 | PayMongo checkout, sandbox checkout page, signed webhook settles the booking | **No online payment of any kind.** The Dispatcher takes cash and marks the seat Paid (`paid_at`, `paid_by`), offline and before Start | `clients/paymongo_client.py`, `clients/sandbox_checkout.py`, `booking/payments.py`, `api/v1/payments.py`, `config.py` |
| S2 | `bookings.qr_payload`, QR scanned at the van door | **No QR.** The Dispatcher finds the reservation **by name or booking code**. `Bookings.BookingCode` is new | 005, `operations/boarding.py` (`ScanTicketUseCase`), `mobile/views/dispatcher/qr_scanner_screen.dart`, `mobile/views/ticket/` |
| S3 | `payments` table (provider, method, provider_ref_id, provider_event_id, raw_payload); `v_trip_revenue` reads it for `cash_in_hand` | Dropped. `bookings.payment_status` / `paid_at` / `paid_by` is the only record of a paid seat; the view is rebuilt on it | 005, 013, 020 |
| S4 | Seat held `seat_hold_ttl_seconds`, swept by `sweep_abandoned_holds` | **`HoldReleaseS` removed.** An unpaid reservation holds its seat until **`UnpaidCutoffMin` before departure** (default **30**), then is released: `cancel_reason = 'auto_release'`. A **check-in does not stop the release** | `operations/guards.py`, `main.py:60`, 021 |
| S5 | Reschedule within a cutoff, `reschedule_count`, `rescheduled` status | **Removed.** Rev 721 never mentions it; cancellation of an unpaid reservation replaces it | `booking/reschedule.py`, `api/v1/bookings.py`, `mobile/views/reservations/reschedule_sheet.dart`, `test_reschedule.sh` |
| S6 | Income groups `verified` / `declared` / `estimated`; `verified` meant a gateway reference existed | **`booked` / `walk_up`.** Booked is a seat reserved in the app and marked Paid, including a home-pickup seat and an app-requested special trip. Walk-up is a Dispatcher cash entry or a counter special trip | 018, `finance/statement.py:125`, `api/v1/statements.py` |
| S7 | `remittances.estimated_income`, `amount_at_risk` | Dropped (already listed at R12; rev 721 repeats it) | 018 |
| S8 | A boarding matches a paid seat or cash entry **within `match_window_seconds`** | **No time window.** A boarding is listed while an unmatched paid seat or walk-up entry remains on the list; each matches one boarding only | `edge/checking.py:96`, `domain/policies.py:27`, 021 |
| S9 | Special trip fee paid through the gateway; `Special_Trip_Requests.PaymentReference` | **Cash to the Dispatcher at the terminal**, who marks it paid and hands the 15 % to the Cashier before Start | `api/v1/special_trips.py`, `operations/special_trips.py` |
| S10 | Home pickup activated by a payment screenshot (`ProofMessageID`, `ProofConfirmedBy`) | The relative **pays both seats in cash**; marking the home-pickup seat Paid **is** the activation. The chat image is a **landmark photo** and nothing depends on it (`PhotoMessageID`) | `booking/home_pickup.py`, `api/v1/home_pickups.py`, 024 |
| S11 | Start blocked until the 15 % is recorded | Blocked until the **full terminal fees due** are recorded: the 15 %, the ₱75 of the trip, and the day's ₱50 when unpaid (T66) | `operations/trip_lifecycle.py` |
| S12 | Notification type `home_pickup_proof` | `home_pickup_photo`. New: `paid_after_release` [ADVICE] | 024 |

S6 and S8 are the two that change behaviour quietly rather than loudly:
the group label and the matching rule both used to depend on the gateway
reference and the clock, and neither exists now.

### 10.2 New in rev 721, not built

- **Booking code.** `Bookings.BookingCode` VARCHAR(32) UNIQUE, generated
  at reservation (`SG-4821` shape). It is what the passenger reads out
  at the terminal and what the Dispatcher searches by.
- **Mark as Paid and Cancel Reservation**, both the Dispatcher's, both
  working **offline** and **before Start**. Cancellation closes when the
  Cashier records the payment or the van departs (`list_locked_at`).
  Reasons: `passenger`, `passenger_asked_dispatcher`, `forgot_to_cancel`,
  `auto_release`.
- **Release job** at `unpaid_cutoff_min`, with a pay-at-the-terminal
  reminder before it, and the **restore path**: a Paid mark that syncs
  after the release restores the seat if the trip still has one free,
  otherwise alerts the Terminal Manager (T62, T63).
- **Terminal fees.** `remittances.dcott_fees`, `parking_fee`,
  `terminal_fees_owed`; settings `dcott_ticket_fee` (75.00) and
  `parking_fee` (50.00), dated like the rate. The ₱50 is charged **once
  per van per service day, even with no trip** — a Cashier records a
  **parking-only charge** (T65).
- **Operator's share.** `operator_share_owed` = (B + W) − terminal fees;
  `operator_share_given`, `operator_share_given_at`,
  `operator_share_recorded_by`. An **'Operator share differs'** flag when
  the two disagree once every trip's list is locked. Monitoring only; it
  blocks nothing.

### 10.3 Unchanged

The four roles, `operators` with no login, the phone pool
(`edge_devices`, `device_checkouts`), disputes, `non_passenger_moves`,
`assisted_pickups`, `messages`, `schedule_templates`, `sos_alerts`,
`data_transfers`, the trip lifecycle columns of migration 024, the hash
chain, NAHGM and the driving flags, the retention job, and the console
modules for all of them.

**The allocator is not touched again.** `Segment.from_starting_terminal`
already refuses any boarding stop but 1, so every booking on a trip
consumes leg 1 and the per-leg rows already enforce exactly 14 per trip
— which is what rev 721 §2.3 asks for. The coarse `SELECT ... FOR
UPDATE` and the `UNIQUE (trip_id, seat_number, leg_sequence)` stand.
Only the prose changes.

### 10.4 Decisions (2 Nov) and roadmap

1. **Drop, with down scripts.** `payments`, `qr_payload`, the gateway
   clients and the verified/declared/estimated columns go, per T60. Each
   migration ships `db/migrations/down/` and a preflight that refuses
   rather than silently discards (the 024 pattern).
2. **Reschedule is removed**, not kept unused.
3. **Backend first, frontend last**, one step at a time, each with its
   journey script green and its own commit.
4. The three amounts stay **settings**, never constants:
   `dcott_ticket_fee`, `parking_fee`, `unpaid_cutoff_min`. Whether the
   ₱75 applies to a special trip is [ASSUMED] in the brief — it ships as
   a setting and goes on the list for A2Z.
5. **The reminder to pay is derived from the cutoff, not set separately**
   (S3). Brief §2.1 asks for a reminder "before the cutoff" and gives no
   interval, so it is sent one cutoff-length before the cutoff — 30
   minutes earlier at the default. A2Z sets one number, not two. If they
   want the reminder earlier the second setting is a one-line change, and
   the question is on the list for them.
6. **`cancel_cutoff_hours` is retired** (S3). Rev 721 closes cancellation
   at the passenger list lock, not a number of hours, and the key's
   reader went with the gateway in S2 — it was showing in Rules &
   Settings as a deadline nothing enforced. `refund_enabled`, the other
   setting brief §14 asks A2Z about, went in S2. Both questions stay on
   the list: what A2Z thought those two settings meant is worth knowing
   even though the code no longer has them.
7. **A trip owes its ₱75 once it has a van, with or without paid seats**
   (S5). The DCOTT ticket is bought for the dispatch, not the
   passengers, and the brief blocks Start until "the terminal fees due
   for the trip" are recorded. So an empty list no longer leaves the
   terminal owing nothing — which closes the case of a Dispatcher who
   lists nobody and pockets the fares. A voided trip drops out.
8. **The ₱50 is charged when the statement opens, and stays** (S5),
   which is the brief's own rule: for the van's first trip of the day,
   or by the parking-only charge. A van taken off its only trip of the
   day still owes the parking for being at its turn; the Terminal
   Manager's override lifts the assignment block if that is wrong.
   The assignment block counts statements **up to today**: a rental
   assigned for Friday opens Friday's statement, and its ticket and
   parking fall due on Friday, not as a debt that blocks the van today.
9. **The ₱75 applies to a special trip** [ASSUMED in the brief], with no
   setting of its own; T51 expects it. It stays on the list for A2Z.
10. **A statement opened before 035 carries no fixed fees.** A2Z
    collected them on paper then, and inventing them afterwards would
    reopen settled statements and block vans. `reset-dev.sh` rebuilds
    the demo with them.

| Step | Brief | What |
|---|---|---|
| S1 | 0.2 | This section; CLAUDE.md re-pointed at the rev 721 brief |
| S2 | 2.1, 7.3 | **Done 2 Nov** (`83bdbfd`). Migration 032: booking code, Paid/cancel columns; dropped the gateway, QR, `payments`, `boarding_scans`, the revenue view and reschedule; Mark as Paid, Cancel and search endpoints. Pulled in with it, because the schema change forced them: **S6 matching** (no window), home-pickup **activation by the paid mark** and the **landmark photo** in place of payment proof, and the rental fee's income group by request origin |
| S3 | 2.1, 4.2 r15 | **Done 2 Nov.** Migration 033: `unpaid_cutoff_min` (30), notification type `paid_after_release`; retired `seat_hold_ttl_seconds`, `hold_sweep_interval_seconds`, `cancel_cutoff_hours` and `seat_inventory.hold_expires_at`. `application/booking/unpaid_release.py` replaces the hold sweeper on the same `PeriodicJob`: it reminds, then releases, and a check-in does not stop it. A Paid mark that syncs after a release restores the seat, or alerts the Terminal Manager when a walk-up has taken it. `test_unpaid_release.sh` (T53–T56, T61–T63) |
| S4 | 2.1 | **Done 2 Nov.** Migration 034 renames `remittances.verified_income`/`declared_income` to `booked_income`/`walk_up_income` and maps `remittance_lines.income_group` to `('booked','walk_up')`, one to one: the grouping rule (the seat's origin, not a gateway reference) already changed in S2, so no total moves. `estimated_income` and `amount_at_risk` had gone in 024. The demo seed now builds its lines from paid seats only, the same definition as `PAID_SEAT`. `test_trip_lifecycle.sh` section 9 reads the live trip's own service date, which a run after 22:00 found on tomorrow's board |
| S5 | 2.1 item 13 | **Done 2 Nov.** Migration 035: `remittances` gains `dcott_ticket_fee` (the ticket in force when the statement opened, kept like `rate_pct`), `dcott_fees`, `parking_fee`, `terminal_fees_owed`, `operator_share_owed`, `operator_share_given`, `operator_share_given_at`, `operator_share_recorded_by`; settings `dcott_ticket_fee` (75.00) and `parking_fee` (50.00). `finance/statement.py` counts the van's trips of the day for the ₱75, charges the ₱50 when the statement opens, holds a held trip's ₱75 with its 15 %, and flags an operator's share that differs once every list is locked. The Start and assignment blocks read the full terminal fees. The Cashier records the operator's share with the payment (`operator_share`), or alone for a difference (`POST /statements/{id}/operator-share`), and a parking-only charge (`POST /statements/parking`). `test_terminal_fees.sh` (sample trip ₱217.50 / ₱342.50 / ₱1,107.50; T1, T64–T69) |
| S6 | 5.2, 6.1 | **Done 2 Nov.** The matching rule itself (no time window) landed inside S2: it read the table S2 dropped, so the two could not be separated without an intermediate rule no revision describes. Its tests (T57, T59) are in `test_door_check.sh`. Migration 036 then retired `match_window_seconds` with its history and its bound in `domain/policies.py`; nothing had read it since S2. The console's settings screen still lists it until S9 |
| S7 | 2.5, 2.6 | Special trips: the walk-in fee basis and the counter flow. The **cash mark** (`/special-trips/{id}/cash`, `paid_at`, `paid_by`) and the whole **home-pickup** half landed in S2 |
| S8 | 12.2 T60 | Sweep for gateway, QR, window and estimate remnants; full journey suite |
| S9 | 9 | Operator console: remittance, settings, Start block wording |
| S10 | 9 | Flutter: booking code and pay-at-terminal notice, Mark as Paid, Cancel |
| S11 | — | Progress log, known issues, manuscript corrections, questions for A2Z, demo script |
