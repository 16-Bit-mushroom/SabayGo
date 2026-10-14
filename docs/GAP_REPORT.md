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
| Native Kotlin edge app, YOLOv8n at 320–416 px, foreground services, Realme setup checklist | Yes for the final design. Not buildable this week: model, Android version and RAM are [OPEN], and no figure may be stated before benchmarking |
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
