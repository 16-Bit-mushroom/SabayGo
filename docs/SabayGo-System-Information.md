# SabayGo — System Information (as built)

**Status as of 12 November 2026.** This document describes the SabayGo
system *as it is implemented in the code today*, so that it can be read
side by side with the ACM manuscript ("SabayGo", Go, Estil, Fernandez —
Group 4, BSIT, University of Mindanao) and the two can be matched.

How to use it:

- Every statement here was taken from the code, the database or the
  project's own test records, not from the manuscript.
- Where the system and the manuscript differ, §17 lists the difference
  and the replacement wording the team already drafted
  (`docs/MANUSCRIPT_CORRECTIONS.md` in the repository).
- §6 maps each of the manuscript's specific objectives (1.3.2.1–1.3.2.5)
  to what was built.
- Figures (accuracy, latency, frame rates) are quoted with the conditions
  they were measured under. Nothing is quoted that has not been measured.
- **The user interface in the manuscript is the old UI/UX.** The screen
  tables and figures in the paper (and any table of screens read from
  it) show the interface before the November 2026 redesign. The current
  screens are the ones in §7–§9. Match features, rules and data against
  the paper; do not expect its screen layouts, labels or navigation to
  match the system.
- §21 answers the follow-up questions D1–D10.

---

## 1. What SabayGo is

SabayGo is a booking and fleet-management system for **terminal-based UV
Express vans** in Davao City, with **A2Z Transport Cooperative** as the
pilot partner. Passengers reserve a seat on a fixed LTFRB route in a phone
app and receive a **booking code**; they **pay in cash at the terminal**
to the cooperative's **Dispatcher**, who marks the seat Paid. The
cooperative office (a **Terminal Manager** and **Cashiers**) configures
the fleet, routes, fares and trip schedules, records the terminal fees each van
owes, and reconciles revenue. A **phone mounted at the van door** runs
YOLOv8 to count the people getting on and off and compares that count with
the passenger list, to detect boardings that are not on the list — the
project's core contribution.

**Cash only.** The system holds and moves no money. It records which seats
the Dispatcher marked Paid, and the amounts handed to the Cashier and to
the operator. There is no payment gateway, no QR ticket and no refund
flow (an unpaid reservation is released and booked again instead).

The pilot route in the data: **Davao (Ecoland) – Cotabato City** (code
ECO-COT), four stops in order: Cooperative Van Terminal – Ecoland → Digos
City Terminal → Kidapawan City Terminal → Cotabato City Terminal. Fares in
the test data: Digos ₱150, Kidapawan ₱340, Cotabato ₱363 (from A2Z's trip
ticket). Regular departures 05:30, 07:30, 09:30, 13:30, 15:30, 17:30.

---

## 2. Architecture and technology

| Part | Technology | What it does |
|---|---|---|
| Database | **MySQL 8.0** (Docker) | 40 migrations define the schema (`db/migrations/001…040`); 42 tables (§15) |
| Backend API | **FastAPI** (Python), async SQLAlchemy 2.0, Clean Architecture | 148 REST endpoints in 19 modules (§16); background jobs (unpaid release every 60 s) |
| Passenger and Dispatcher app | **Flutter** (Android; also builds for the web) | One app, two roles: passenger booking; Dispatcher passenger list, cash, walk-ins, Depart/Arrived |
| Office console | **Flutter Web** | Terminal Manager and Cashier pages (§9) |
| In-van edge app | **Native Android (Kotlin)**, TensorFlow Lite | YOLOv8n + ByteTrack door counting, GPS, status reports, offline outbox (§10) |
| Model evaluation | Python harness (`ai_service/eval/`) | Measures YOLOv8n counting accuracy on held-out images (§10.4) |
| Maps | **OpenStreetMap** tiles via `flutter_map` | Live maps in the console and the app, with ODbL attribution |
| Authentication | **JWT** issued by the backend | Email + password; bcrypt hashes |
| Notifications | **In-app notifications** stored in the database | Read by the apps and the console (polling) |
| SMS (emergencies only) | Provider setting: `disabled`, `android_gateway` (a handset on the cooperative's SIM) or `twilio` | None is required; who is texted is a cooperative setting |

There is **no separate AI server**: the earlier Flask inference service was
retired on 16 Oct 2026; inference now runs on the in-van phone.

---

## 3. Users and roles

| Role (in the system) | Who | Where they work |
|---|---|---|
| `passenger` | The commuting public; self-registers | Phone app |
| `dispatcher` | A2Z staff who rides the van: marks seats Paid, lists walk-ins, departs and arrives the trip | Phone app (Dispatcher mode) |
| `terminal_manager` | Decides what is owed, sets rules, validates records, reviews exceptions | Office console (all pages) |
| `cashier` | Records terminal-fee payments, starts trips | Office console (manager-only pages hidden) |
| `admin` | System administrator (the development team) | — |

- **Operator** means the **van owner, who always drives**: a record in
  `operators` with name, licence and the van — **no login**. The system
  never calls office staff "operator" (under LTFRB usage the operator is
  the franchise holder).
- **Dispatcher** replaced the manuscript's "conductor".
- Separation of duties: only the Cashier records payments; only the
  Terminal Manager lifts a payment block, reviews automatic starts,
  changes a started trip's van, voids a trip and decides disputes; only
  the trip's assigned Dispatcher marks seats Paid, lists walk-ins and
  taps Arrived.

---

## 4. Vocabulary used by the system

| Term | Meaning |
|---|---|
| **Seat** | A passenger's place in the van. UV Express assigns **no seat numbers**; `seat_number` is an internal slot counter, never shown. Capacity is **14** a trip. |
| **Route / stop** | A fixed LTFRB path; a stop is a terminal's position (1…N) on it |
| **Leg** | The stretch between neighbouring stops (a route with N stops has N−1 legs) |
| **Segment / journey** | One passenger's boarding and alighting stops; it uses every leg between them |
| **Booking code** | `SG-XXXXXX`, given at reservation; shown to the Dispatcher at the terminal |
| **Booked (B)** | Income group: a seat reserved in the app and marked Paid |
| **Walk-in (W)** | Income group: a passenger the Dispatcher lists at the van, paying cash as listed |
| **Terminal fees** | A2Z's 15 % of the listed fares + a ₱75 DCOTT ticket per trip + ₱50 parking per van per service day |
| **Operator's share** | What is left of the cash after the terminal fees |
| **Overbooking** | The same seat reserved twice, or more bookings than seats |
| **Reservation lock** | While one reservation is being saved, no other can take that seat (MySQL pessimistic locking) |
| **Bounding box** | The box YOLOv8 draws around a detected person |
| **Unaudited** | A trip the door camera could not check (no phone, phone silent at start or on the road, lens covered) — never counted as zero |

---

## 5. A trip from start to end (the implemented flow)

1. **Trip Schedules** ("Timetable" until 12 Nov). The Terminal Manager keeps regular departures (route,
   time, days) and posts them for 7 days, or posts a one-off trip. A
   posted trip is immediately bookable in the passenger app.
2. **Reservation.** The passenger picks a destination (boarding is always
   at the route's first stop), a day and a departure, and reserves. The
   server allocates a seat under the reservation lock and returns a
   booking code. The seat is **unpaid**.
3. **Reminder and release.** One cutoff-length before the cutoff the
   passenger is reminded to pay. **30 minutes before departure**
   (`unpaid_cutoff_min`) an unpaid reservation is **released**
   (`cancel_reason = auto_release`) and the passenger is told. A Paid mark
   made offline that syncs after the release restores the seat if the
   trip still has one; otherwise the Terminal Manager is alerted.
4. **"I'm here to pay."** At the terminal the passenger presses **I'm here
   to pay** (location-checked within the terminal's geofence, from 45
   minutes before departure). The trip's Dispatcher is notified once:
   "<name> is at <terminal> to pay ₱<fare> for seat <code>".
5. **Paid.** The Dispatcher takes the cash and taps **Mark ₱<fare> paid**
   (with a confirmation showing the amount). The seat becomes Paid and
   the passenger counts as **at the terminal** (paying is the check-in).
   The passenger gets an in-app notice: "Seat SG-… is paid … Show this
   code at the van door before it leaves at <time>."
6. **Walk-ins.** The Dispatcher lists walk-ins (destination and fare;
   name optional), each paid as listed. Only the trip's assigned
   Dispatcher can.
7. **Terminal fees.** The Cashier records the trip's terminal fees (15 %
   of listed fares + ₱75 DCOTT, plus the van's ₱50 parking for the day if
   unpaid) and the operator's share handed over, with a receipt number.
   Recording them **locks the passenger list** (a later cash passenger is a
   top-up).
8. **Start.** Opens **30 minutes before departure** (`start_opens_minutes`)
   and **waits for the terminal fees** — or the Terminal Manager lifts the
   block with a written reason. A van that still owes from an earlier trip
   cannot be assigned its next trip until it pays or is overridden.
9. **Door check.** The door camera's count aboard is compared with the
   passenger list. **Fewer aboard** than listed = no-shows, nothing to do.
   **More aboard** than listed **stops Depart** until each extra boarding is
   listed as a walk-in or given a typed reason (kept for the Boarding
   Audit).
10. **Depart.** The Dispatcher (or the office) taps Depart. **Every paid
    seat becomes `boarded`**; only an unpaid seat still standing is a
    no-show. The passenger's app keeps the trip as current ("On board",
    with live tracking and the SOS button) until arrival. A trip that left
    with fees unrecorded is marked and alerted.
11. **On the road.** The phone sends GPS each second and a status report
    every 30 s; NAHGM gives the nearest stop and ETAs (§11). After
    departure the camera count holds the van to its 14 seats (capacity
    alert).
12. **Arrived.** Only the Dispatcher taps Arrived. The trip is completed;
    its bookings file under the passenger's Past trips.
13. **Statement.** Each van has a statement per day (fare lines by trip,
    drop-off and group; terminal fees owed, paid, due; operator's share).
    The operator may dispute a fare line or a driving flag; the Terminal
    Manager decides (§12).

---

## 6. The manuscript's objectives, matched to the system

| Objective (manuscript 1.3.2) | Status | What the system does | Difference from the wording |
|---|---|---|---|
| **1.3.2.1** Location-based check-in, backed by a database locking mechanism, preventing double-booking, confirming presence, removing unfair no-show penalties | **Built, reshaped** | Reservation under a **reservation lock** (pessimistic `SELECT … FOR UPDATE` over the seat-inventory window) — 0 overbookings at 10/25/50 concurrent requests (§14). **I'm here to pay** is the location-checked presence step (geofence, 45-min window) and tells the Dispatcher; the **Paid mark** confirms payment and presence. No penalty exists: an unpaid seat is released 30 min before departure; a paid seat is recorded as boarded at Depart, never as a no-show. | "Check-in" is now "I'm here to pay"; paying is the check-in. "Double-booking" → "overbooking". Suggested replacement in MANUSCRIPT_CORRECTIONS §14. |
| **1.3.2.2** Live GPS tracking (NAHGM) with stop-by-stop ETA for passengers and operators | **Built** | GPS from the in-van phone (1 s); NAHGM nearest-node + haversine, ETA per stop (§11); live map in the console (Overview) and "Track the van" in the passenger app; since 12 Nov (C5) a passenger sees only the van of a trip they hold a seat on, while it is boarding or on the road; the office and crew see every van | Operators have no login, so "operators" see it through the office console. Maps are OpenStreetMap, not Google Maps. |
| **1.3.2.3** YOLOv8 passenger headcount from cabin footage, flagging differences from the manifest | **Built differently** | The phone at the **door** runs YOLOv8n + ByteTrack and counts **door-line crossings** (boardings/alightings), not a cabin headcount from footage. Its count aboard is compared with the passenger list before Depart (more aboard blocks Depart until listed/explained) and against the 14 seats after. No video is kept: one still per event, people pixelated, hash-chained. | Headcount → door counting. The accuracy figures measured so far are for still-image people counting (§10.4); door-crossing accuracy in a van is not yet measured. |
| **1.3.2.4** Revenue dashboard comparing booked seats with collected fares, highlighting mismatches, alerting to possible loss | **Built** | **Money**: per-van daily statements (B/W fares, terminal fees owed/paid/due, operator's share given/returned, disputes), a 7-day/30-day/1-year fee chart; **Boarding Audit** (door events vs list, unlisted boardings, chain verified); **Review Starts**; alerts (left unpaid, departed with more aboard than listed, capacity, unaudited) | Named "Money" and "Reviews" in the console. Cash is recorded, not collected by the system. |
| **1.3.2.5** Real-time notifications to passengers, conductors, drivers and the operator (delays, cancellations, boarding confirmations) | **Built, narrower audience** | In-app notifications to passengers (paid, pay reminder, released, cancelled, trip updates), Dispatchers (here to pay, assignments, alerts) and office staff (alerts, disputes, SOS). SMS only for emergencies. | "Conductors" → Dispatchers. **Drivers/operators have no account**, so they receive nothing in-app. Not push (FCM); stored in-app notifications read by polling. |

---

## 7. The passenger app

- **Sign up / sign in** (email, mobile number, password ≥ 8 characters,
  terms accepted).
- **Home — search:** From is pre-filled with the route's starting terminal
  (everyone boards there) or the last journey; choosing the destination
  loads departures at once (no search button); day as Today / Tomorrow /
  Other day; time-of-day filter. Each departure: time, fare, seats left,
  van plate.
- **Trip details → Reserve a seat** (cash to the Dispatcher at the
  terminal). Also: book a seat with a **home pickup** for an elderly or
  disabled relative (two seats, within a route distance set by policy).
- **Reservation:** booking code (copy), journey, fare, payment state,
  "pay before" time; **I'm here to pay**; **Track the van**; cancel while
  unpaid (a paid seat is cancelled through the Dispatcher, who returns
  the cash). The screen refreshes from the server on opening and every
  30 s.
- **My trips:** the current trip as a ticket stub (large booking code,
  fare, what to do next), upcoming, past and cancelled.
- **Live map** with the van's position and ETA, and an **SOS** button.
- **Chat** with the trip's Dispatcher or the A2Z office; **Updates**
  (notifications); **Profile** (saved destinations); **Rent a van**
  (special trip request).

## 8. The Dispatcher app (same app, Dispatcher role)

- **Trip list:** Next (large card, countdown, Open), Later, Done.
- **Trip screen:** status, van and operator (name + licence + plate), counts
  (Paid, Unpaid, At terminal, Seats left) and a seats-taken bar; a
  **Next** line saying what to do now ("Collect ₱450 in cash from 3
  passengers…", "Everyone has paid. When all are aboard, tap Depart",
  "On the road. Tap Arrived at …"); the door camera's count against the
  list with crew toggle; **Reservations and walk-ins** with filters
  (To collect / Paid / All), search by code or name, HERE TO PAY first,
  **Mark ₱… paid**, cancel; terminal fees to hand to the Cashier; the
  operator's dispute; home pickups; driving flags.
- **Bottom bar:** Add walk-in · Depart (once started) · Arrived (on the road).
- "Not a passenger trip" (refuel, repair…) in the menu; **SOS**; chat;
  notifications.
- **Offline:** walk-ins and Paid marks made without signal are queued on
  the phone and synced later (shown as "not synced" meanwhile).

## 9. The office console (Flutter Web)

*(This is the redesigned console of November 2026. The manuscript's
screen tables and figures show the older UI/UX.)*

Menu: **Overview · Trips · Reviews · Money · Messages · Setup ·
Emergencies (SOS)**; a top bar with live figures (vans on the road and
without signal, trips today and under way, boardings to review or vans
owing, open emergencies) and how fresh they are.

| Page | Contents |
|---|---|
| **Overview** | Today panel (trips by status, what needs the person, terminal fees today), live map of the vans, live vans list (door count vs seats, GPS, flags) |
| **Overview › Door cameras** (Terminal Manager) | One card per in-van phone in everyday words: a verdict ("Working: counting passengers at the door" / "Not counting: the phone stopped sending at …" + what to do), camera/location/camera view/charger, battery, phone heat (Normal/Warm/Too hot), camera Counting/Stopped and how often it looks, passengers inside now vs the list, the last 2 hours on request, today's door counts. From `GET /devices/live`. |
| **Trips** | Post a trip (route, day, time, optional van and Dispatcher, "Passengers will see …"), the daily **trip sheet** (time and route, van and operator, Dispatcher, listed vs aboard, fares, terminal fees, status, next step: assign, record payment, start, depart), trip detail panel |
| **Trips › Trip Schedules** | Trips that repeat weekly (route, time, days, in use / off), each with Edit and Delete; "Add a new route…" opens Setup › Route |
| **Trips › Van Status Board** | Each van: travelling / on site / not on a trip / out of service, its trip, Dispatcher, door camera, GPS, fees owed, whether it can be dispatched |
| **Trips › Special Trips** | Van rental requests (app or walk-in at the counter): agree the fee, assign, start, void |
| **Reviews** | **Review Starts** (started by the system, left unpaid, more aboard than listed, unaudited), **Boarding Audit** (door events, chain verification, unlisted boardings and their explanations, capacity alerts), **Driving Flags** (overspeed, long stop, slow, standstill — indicators for review, not proof), **Disputes** |
| **Money** | The selected van's statement (fare lines, terminal fees, operator's share, receipts) and the daily statements ledger with Record payment; terminal-fee chart; parking-only charge |
| **Messages** | Conversations with passengers and Dispatchers |
| **Setup** | Terminals (geofence radius), Route (stops in order, LTFRB case number), Fares (pairwise matrix), Operators & vans (four photos, validation), Staff (validation), Phones (add, token, check out to a van and Dispatcher, return), Rules & Settings; Import / Export of records |
| **Emergencies (SOS)** | Open and past alerts; Mark as responding; Close with a note |

---

## 10. The door camera (YOLOv8) — edge app and evaluation

### 10.1 Hardware and model

- Phone: **realme 8 5G** (RMX3241), Android 13, MediaTek Dimensity 700.
- Model: **YOLOv8n**, COCO-pretrained (Ultralytics), TensorFlow Lite,
  person class, confidence **0.45**, NMS IoU **0.50**; on the phone at
  320 px or 416 px input, **CPU FP16** (fastest on the bench, §10.5).
  The model is not fine-tuned on van footage.

### 10.2 How it counts (implemented in `edge_app/`)

- The Dispatcher draws a **door line** across the doorway, a **driver's
  seat mask** and the cabin direction once per van (saved on the van).
- **ByteTrack** follows each person's bounding box. A confirmed track whose
  box centre crosses the line inward (past a margin, within the drawn
  segment) is a **boarding**; outward an **alighting**. Someone first seen
  inside did not board; a box centred in the seat mask is never tracked.
- Each event carries an id, the server-clock time, the count after it, the
  tracker id, the last GPS fix and the **SHA-256 of its still** (every
  person box pixelated, the line drawn). Events form a **hash chain** on
  the server (genesis: SHA-256 of `"sabaygo:" + ScheduleID`), so a still
  deleted under retention leaves the chain verifiable.
- **Status reports** every 30 s: camera working, GPS fix, lens blocked (a
  dark, uniform frame for 15 s), battery %, battery temperature,
  charging, detection rate (frames checked per second). A phone silent
  for over 120 s (`heartbeat_gap_seconds`) is silent.
- An **outbox** (SQLite on the phone) sends events, GPS, reports and
  stills in order every 5 s, so nothing is lost in a dead zone.
- Counting runs from assignment until arrival (`GET /edge/session`).

### 10.3 What the server does with it

- Before Depart: aboard vs listed — more aboard blocks Depart until
  listed or explained; fewer = no-shows.
- After Depart: aboard vs the van's 14 seats (capacity alert to the
  Terminal Manager, the Cashier and the Dispatcher).
- **Unaudited** when there is no evidence: `no_phone`, `silent_at_start`,
  `lens_blocked`, `lost_en_route`. The system never substitutes a count.
- Stills are kept 30 days (`retention_days`) unless a review is open.

### 10.4 Measured accuracy (model evaluation, 9 Oct 2026)

Method (`ai_service/eval/`): held-out images with people from **COCO
val2017** (the model was trained on COCO train, not val), each also
degraded six ways; the count is the number of people detected in one
still frame, against the annotated number. **11,501 frames / 57,505
inferences**, at Ultralytics' default **640 px**, on a laptop CPU.

Counting accuracy by condition (confidence 0.45):

| Condition | MAE | RMSE | Bias | Exact | Within ±1 |
|---|---|---|---|---|---|
| Original | 0.339 | 0.793 | −0.278 | 74.7 % | 94.3 % |
| Dim 60 % | 0.343 | 0.812 | −0.295 | 75.0 % | 93.9 % |
| Half resolution | 0.355 | 0.821 | −0.302 | 74.1 % | 93.9 % |
| JPEG 70 | 0.369 | 0.854 | −0.321 | 73.6 % | 93.4 % |
| Dim 35 % | 0.378 | 0.863 | −0.335 | 73.3 % | 93.1 % |
| Motion blur | 0.452 | 0.990 | −0.386 | 69.2 % | 91.8 % |
| Quarter resolution | 0.491 | 1.039 | −0.441 | 66.6 % | 91.5 % |

By occupancy (original images): empty 0.000 MAE (no invented passenger in
50 frames); 1–3 people MAE 0.249 (78.3 % exact); 4–7 MAE 0.914 (43.2 %);
8–11 MAE 2.607 (10.7 %). Negative bias = the detector counts fewer people
than present (the direction that hides a passenger); accuracy falls as
the scene fills.

Leakage detection simulated from these errors (original, 0.45): false
alarm on an honest crew 25.3 % under the strict rule (δ ≠ 0) and 2.7 %
under the leakage rule (δ > 0); one hidden passenger detected 82.9 % /
77.5 %; two 96.2 % / 94.6 %; three 98.8 % / 98.4 %.

**Limits to state with these figures:** they measure *still-image people
counting* at 640 px on COCO scenes, not the deployed *door-line crossing*
count in a van, and not at the phone's 320/416 px. Door counting with
people and in a van is still to be tested by the team.

### 10.5 Phone benchmark, part 1 (bench sweep, 18 Oct 2026)

On a desk, powered over USB, back camera 640 × 480, 60 s per step:

| Input | Backend | Inference ms (mean) | Frames/s |
|---|---|---|---|
| 320 px | CPU FP32 | 42.3 | 20.5 |
| 320 px | **CPU FP16** | **26.2** | **29.9** |
| 320 px | GPU FP16 | 47.0 | 15.6 |
| 416 px | CPU FP32 | 72.0 | 12.4 |
| 416 px | **CPU FP16** | **45.4** | **18.4** |
| 416 px | GPU FP16 | 49.8 | 13.8 |

No thermal throttling in 9.5 min (battery 40.6 → 43.3 °C). **Part 2 — one
full run on vehicle power over a real trip — is still to come; until then
no operating frame rate is claimed.** The rates above are bench rates for
choosing a configuration.

---

## 11. Live tracking — NAHGM

**Node-Aligned Haversine Geofenced Monitoring** (`backend/app/application/tracking/nahgm.py`):

- From each GPS fix, the haversine distance to every terminal node in the
  route's ordered sequence; the nearest node places the van along the
  sequence ("just left Digos").
- ETA to each remaining stop from recent speed when available, otherwise
  from the route's planned stop offsets.
- Geofences: each terminal has a radius (default 150 m) used for the
  "I'm here to pay" presence check and, once A2Z sets
  `depart_zone_radius_m` and `depart_readings`, for detecting a van leaving
  the terminal (a GPS fallback start/depart). Those two settings ship
  unset, so the GPS fallback is off.
- A position older than 120 s is stale ("last seen …").
- Honest framing kept in the code: haversine distance and nearest-node
  selection are textbook; the claim is their application to fixed-route
  cooperative operations.

---

## 12. Money: statements, fees, disputes

- **Statement** per van per service day: fare lines (by trip, drop-off,
  income group B/W), terminal fees (15 % of fares, ₱75 per trip, ₱50
  parking per day), owed / paid / due, the operator's share owed / given /
  returned, receipts and who recorded them.
- A van that **still owes** cannot be assigned its next trip; a trip's
  Start waits for its fees (Terminal Manager override with a reason).
- **Disputes:** the operator contests a fare line or a driving flag (the
  Cashier records the statement); the disputed 15 % is withheld until the
  Terminal Manager decides — **Uphold** (removed from what is owed),
  **Adjust** (part due), **Reject** (due again) — with a preview of what
  the decision changes, a required reason, and a notice to the Cashier
  when an upheld dispute leaves the operator over-paid (the excess is
  recorded as returned).
- **Policy snapshot:** the policy values in force when a trip was generated
  are kept on the trip; changing a rule does not alter terms already
  booked.

---

## 13. Notifications, messaging, emergencies

- **In-app notifications** (types in the database include: trip_update,
  departure_reminder, schedule_change, sos_alert, capacity_alert,
  driving_flag, special_trip_request, unconfirmed_trip_start,
  unaudited_trip, trip_not_started, assignment_by_cashier, dispute_raised,
  departed_more_than_listed, left_unpaid, payment_block_override,
  home_pickup_photo, paid_after_release, share_over_given).
- **Chat:** passenger ↔ trip Dispatcher, passenger ↔ A2Z office, staff;
  images up to 10 MB, kept 30 days.
- **SOS** (passenger or Dispatcher; categories medical, accident,
  security, breakdown, other): the alert and its in-app notifications are
  **committed before any SMS is attempted**, and a text is reported as sent
  only if the gateway accepted it; a dead gateway loses the text, never
  the emergency. The office marks it responding and closes it with a note.
  The SOS numbers (`sos_contact_numbers`) are not yet set, so no SMS is
  sent.

---

## 14. Concurrency: the reservation lock

`seat_repository.allocate_seat()` locks the whole candidate window of the
seat inventory (rather than one `GROUP BY … FOR UPDATE`, whose locking
depends on the query plan) and allocates the lowest-indexed seat free on
every leg of the journey. Experiment (`test_concurrency.py`, 24 Aug 2026,
trip capacity 10, all requests for the same journey):

| Simultaneous requests | Booked | Rejected | Seats sold twice | Median latency |
|---|---|---|---|---|
| 10 | 10 | 0 | **0** | 172 ms |
| 25 | 10 | 15 | **0** | 411 ms |
| 50 | 10 | 40 | **0** | 809 ms |

A comparison run with the capacity check outside the lock let 14 bookings
through a limit of 10.

---

## 15. Data model (MySQL, 39 migrations)

Tables (42): `users`, `passenger_profiles`, `staff_profiles`,
`passenger_settings`, `saved_destinations` · `operators`, `vans`,
`van_photos` · `terminals`, `routes`, `route_stops`, `route_stretches`,
`fare_matrix`, `schedule_templates`, `trips`, `trip_legs`,
`seat_inventory` · `bookings`, `check_ins`, `assisted_pickups`,
`special_trip_requests` · `remittances`, `remittance_lines`,
`cash_remittances`, `disputes` · `edge_devices`, `device_checkouts`,
`device_heartbeats`, `passenger_events`, `held_door_events`,
`trip_location_pings`, `driving_events`, `non_passenger_moves`,
`yolov8_audit_logs` (from the retired AI service) · `notifications`,
`conversations`, `messages`, `sos_alerts`, `sos_alert_dispatches` ·
`cooperative_policies`, `data_transfers`, `schema_migrations`.

Key points:

- Fares are a **pairwise matrix per route by stop position**:
  UNIQUE (route_id, from_stop_sequence, to_stop_sequence, effective_from) —
  the manuscript keys them by terminal pair.
- `bookings.status`: pending, confirmed, checked_in, boarded, completed,
  cancelled, no_show; `payment_status`: unpaid / paid with `paid_at`,
  `paid_by`; `booking_type`: app / walk_in.
- `remittance_lines.income_group`: booked / walk_in;
  `remittances.walk_in_income` (renamed in migration 039).
- The payment tables of the online-payment era were removed (migration
  032); the seat hold with a TTL was retired (033).
- Migrations define the schema; every migration has a down script.
- Times are stored as naive local time (Asia/Manila).

---

## 16. API (FastAPI, 148 endpoints)

| Module | Endpoints | Covers |
|---|---|---|
| auth | 5 | register, login, profile |
| bookings | 9 | reserve, walk-in, mark paid, cancel, my bookings |
| operations | 20 | check-in ("I'm here to pay"), assignment, start, depart, arrive, door check, boarding audit, review starts, overrides |
| config | 21 | terminals, routes, fares, trip schedules (with edit and delete), trip posting and generation, policies |
| fleet | 15 | operators, vans, photos, staff, validation, van status board |
| statements | 8 | trip share, payments, statements, history, operator's share returned |
| special_trips | 8 | rental requests |
| devices | 7 | in-van phones, tokens, checkout/return, live door-camera readings |
| home_pickups | 7 | assisted pickups |
| edge | 6 | phone session, door events, GPS, status reports, door layout |
| roster | 6 | import / export of records |
| trips | 6 | terminals for the pickers, departure search, trip details and stops, the camera privacy notice |
| disputes | 5 | raise, preview, decide |
| messaging | 7 | conversations, messages; edit and delete one's own text message (12 Nov, migration 040) |
| users | 5 | own settings, saved destinations |
| sos | 4 | raise, list, acknowledge, resolve |
| tracking | 4 | position (public), history, fleet |
| notifications | 3 | list, read |
| driving_flags | 2 | list, review |

Guards: role-based (`MANAGER`, `OFFICE`, `CASHIER`, `CREW`); phones use a
device token (`X-Device-Token`).

---

## 17. Known differences from the ACM manuscript

Each has drafted replacement wording in `docs/MANUSCRIPT_CORRECTIONS.md`
(section numbers in brackets).

1. **Maps:** Google Maps SDK → **OpenStreetMap** via flutter_map, with ODbL
   attribution [§1, §2].
2. **What the camera observes:** "door closures" → door-line crossings by
   tracked people [§3]; and **cabin headcount → door counting** (§6
   above).
3. **Authentication:** Firebase Authentication → **JWT** from the backend
   [§4].
4. **Notifications:** FCM push → **in-app notifications** [§5].
5. **SMS:** Twilio as *the* mechanism → a **pluggable SMS gateway**
   (Android handset on the cooperative's SIM, or Twilio), used only for
   emergencies [§6].
6. **Scope and limitations:** a new paragraph (cash only; roadside
   pickups after the van leaves the terminal are neither flagged nor
   priced; the evaluation's limits) [§7, §10].
7. **Role naming:** the manuscript's office "Operator" is the system's
   **Terminal Manager / Cashier**; "operator" is the van owner who drives
   (no login); "conductor" → **Dispatcher** [§8].
8. **Alert rule:** the manuscript states two formulas (δ ≠ 0 in §2.3.2.1,
   δ > 0 in §2.3.4). Implemented: before departure, more aboard than
   listed blocks Depart until listed or explained; fewer is a no-show;
   after departure the count only holds the van to 14 [§9].
9. **Data dictionary:** the schema keeps its own names; fares keyed by
   route and stop position; other mappings listed [§11].
10. **Revision 603 open points, as decided:** hash-chain genesis, ordering,
    retention and others [§12].
11. **Cash only (brief rev 721):** no online payment, no QR ticket; the
    Dispatcher marks seats Paid; the income groups are Booked (B) and
    **Walk-in (W)** (the brief said "Walk-up") [§13].
12. **Who rode:** with no ticket scan, a paid seat is boarded at
    departure; only an unpaid one is a no-show (replacement for T8) [§13].
13. **One word, seat;** check-in → **"I'm here to pay"**, paying is the
    check-in; objective 1.3.2.1 reworded; **overbooking** (not
    double-booking), **reservation lock** (not seat lock), **bounding box**
    (not hitbox) [§14].
14. **Notifications audience (objective 1.3.2.5):** drivers/operators
    receive nothing in-app (no account).
15. **Evaluation scope (objective 1.3.2.3):** the reported accuracy is
    still-image counting on COCO at 640 px; door counting in a van and at
    the phone's input size is not yet measured; no operating frame rate is
    claimed before the in-van benchmark run.

---

## 18. Limitations and open items (as of 12 Nov 2026)

- **Door counting with people, in a van,** is still to be tested by the
  team; the phone benchmark's part 2 (a full trip on vehicle power) is
  still to be run.
- **A2Z's numbers not yet set:** `depart_zone_radius_m`,
  `depart_readings` (GPS departure detection is off), special-trip speed
  limit, per-stretch speed limits, SOS numbers, the data-privacy contact
  shown in the camera notice (a placeholder until A2Z names one).
- **Roadside pickups** after the van leaves the terminal zone are neither
  flagged nor priced — a disclosed limitation: the camera's count sets no
  fare.
- **Model** is COCO-pretrained YOLOv8n, not fine-tuned; accuracy falls as
  the van fills (§10.4).
- Two legacy test scripts outside the journey suite are out of date.

---

## 19. Testing and evidence

- **Journey test suite** (shell/Python scripts against the running API,
  `backend/tests/integration/`): the full suite passed **1,070 checks, 0
  failures** on 9 Nov 2026; after the 12 Nov changes the affected
  journeys passed again on a scratch database — trip lifecycle 139,
  terminal fees 79, disputes 80, unpaid release 57, special trips 74,
  door check 65, home pickup 68, edge ingestion 95, Dispatcher 30,
  passenger journey and notifications with no failures, trip ticket 75.
- **Mobile layout and accessibility tests** (Flutter): 32 pass (320 dp at
  200 % text; WCAG tap-target, label and contrast checks).
- **End-to-end UI run, 11 Nov 2026:** every role driven through the real
  screens in a browser (post a trip, reserve, mark paid, walk-in, record
  fees, start, depart, arrive, dispute, sign-up, add staff, SOS) — report
  and screenshots in `docs/test-reports/ui-run-2026-11-11/`.
- **Day 1 test with A2Z's setup** (3 Nov 2026): the system set up from
  empty as the cooperative would, then one cash trip end to end
  (`docs/DAY1_TEST_GUIDE.md`, `docs/DAY1_FINDINGS.md`).
- **Concurrency experiment** (§14) and **model evaluation** (§10.4);
  raw outputs in `docs/benchmarks/`.

---

## 20. Where things are in the repository

| Path | Contents |
|---|---|
| `backend/app/` | FastAPI app: `api/v1/` (endpoints), `application/` (use cases: booking, operations, finance, tracking, edge, safety), `infrastructure/` (models, repositories) |
| `backend/app/infrastructure/repositories/seat_repository.py` | The reservation lock (module docstring explains the method) |
| `backend/app/application/tracking/nahgm.py` | NAHGM |
| `db/migrations/` | The schema, 001–040, with down scripts |
| `mobile/` | Flutter passenger and Dispatcher app |
| `operator_console/` | Flutter Web office console |
| `edge_app/` | Kotlin in-van phone app (README explains the counting) |
| `ai_service/eval/` | Model evaluation harness (README explains the metrics) |
| `docs/benchmarks/` | Evaluation, phone benchmark and locking results |
| `docs/MANUSCRIPT_CORRECTIONS.md` | Every manuscript/system difference with replacement wording |
| `docs/PROGRESS_LOG.md` | What was built, step by step, and why |
| `docs/SabayGo-Changes-for-Claude-Code.md` | The specification (brief rev 721) |

---

## 21. Answers to the follow-up questions (D1–D10)

Answered from the code and the live database on 12 Nov 2026.
**Reminder: any table of screens taken from the manuscript describes the
old UI/UX** (see the note at the top); these answers describe the system
as it runs now.

**D1. Which driving flags ship, and with what definitions?**
Four kinds, computed from the in-van phone's GPS readings
(`backend/app/application/tracking/driving.py`). A flag is an indicator
for the Terminal Manager's review, never proof of misconduct.

| Kind | Definition | Setting (current value) |
|---|---|---|
| `overspeed` | Speed stays above the speed limit of the stretch the van is on for the set time or longer | `overspeed_seconds` (10 s); the limit is per stretch (`route_stretches.speed_limit_kmh`) |
| `unscheduled_stop` | A standstill (at or below `standstill_kmh`) longer than `stop_seconds`, away from every stop zone, not counting the allowed wait at a declared home pickup | `standstill_kmh` (2 km/h), `stop_seconds` (120 s), `home_pickup_wait_minutes` (10 min) |
| `slow_stretch` | Leaving one stop zone to entering the next took more than the stretch's expected time by the set percentage, less any declared home-pickup wait | `slow_tolerance_pct` (25 %); the expected time is per stretch (`route_stretches.expected_time_s`, derived from `expected_speed_kmh`, 55 km/h, when the stretch is saved) |
| `en_route_stop` | A standstill of `stop_seconds` or shorter away from the stop zones: **recorded, not flagged** | — |

Readings further apart than the silent-phone gap break an episode
(nothing is assumed about the gap). A special trip (rental) has no route:
only overspeed applies, against `special_trip_speed_kmh`, which is unset,
so rentals are not flagged yet. **Overspeed and slow stretch need the
route's stretches (speed limit, expected time) entered by the Terminal
Manager; the live data has none yet, so today only unscheduled stops are
flagged.** A new flag alerts the Terminal Manager and the trip's
Dispatcher once; the Terminal Manager marks it reviewed or dismissed (with
a note); the operator may dispute it (decided in Disputes).

**D2. Do the passenger trust rating and trip history exist?**
- **Trip history: yes.** My trips shows the current trip, upcoming,
  **Past trips** and **Cancelled** (from `GET /bookings/mine`), each with
  its booking code, fare and status ("Completed", "Released, unpaid",
  "Cancelled"…).
- **Trust rating: only as a stored field, not as a feature.**
  `passenger_profiles.trust_rating` exists (default 5.0, set at
  registration) and is returned in the profile API, but **no rule ever
  changes it and no screen shows it.** There are no no-show penalties
  (§6, objective 1.3.2.1), so nothing would lower it.

**D3. Is `yolov8_audit_logs` still written to?**
**No.** The table and its model class remain from the retired Flask AI
service (headcount audits, retired 16 Oct 2026); no code writes to it
and it has **0 rows**. Door evidence is now stored in
`passenger_events` (one row per boarding/alighting, hash-chained, with
the still's SHA-256) and `held_door_events` (events received while a van
had no trip).

**D4. Is there a separate walk-in ledger?**
**No.** A walk-in is a **booking** (`booking_type = walk_in`), paid as it
is listed (`paid_at` set at creation) and recorded as `boarded`. On the
van's statement walk-ins are fare lines with income group `walk_in`
(`remittance_lines`), totalled in `remittances.walk_in_income` beside
`booked_income`. The older `cash_remittances` table (from the rev 468
cash-remittance design) is not written to and has 0 rows.

**D5. What are the real status values?** (database ENUMs and code enums)

| Field | Values |
|---|---|
| `trips.status` | scheduled, boarding, departed, completed, cancelled |
| `trips.payment_status` (terminal fees) | unpaid, paid, left_unpaid, overridden |
| `trips.start_review_status` | not_required, pending, reviewed |
| `trips.audit_status` | audited, unaudited (reason: no_phone, silent_at_start, lost_en_route, lens_blocked) |
| `trips.departure_source` | dispatcher, staff, gps |
| `bookings.status` | pending\*, confirmed, checked_in, boarded, completed, cancelled, no_show |
| `bookings.payment_status` | unpaid, paid |
| `bookings.booking_type` | app, walk_in, driver_issued\* |
| `bookings.cancel_reason` | passenger, passenger_asked_dispatcher, forgot_to_cancel, auto_release |
| `seat_inventory.status` | available, held (only for the instant inside a reservation, before the booking row exists), booked, blocked |
| `remittances.status` (daily statement) | open, settled |
| `disputes.status` / `outcome` | open, resolved, withdrawn / upheld, rejected, adjusted |
| `driving_events.review_status` | open, reviewed, dismissed |
| `passenger_events.event_type` | board, alight |
| `passenger_events.match_status` | matched_booking, matched_log, unlisted |
| `passenger_events.resolution_status` | not_needed, pending, listed, explained |
| `special_trip_requests.status` / `payment_status` | requested, approved, rejected, completed, cancelled / unpaid, paid |
| `assisted_pickups.status` (home pickup) | requested, activated, arrived, boarded, no_show, cancelled |
| `sos_alerts.status` | open, acknowledged, resolved |
| `edge_devices.status` (in-van phone) | in_office, checked_out, retired |
| `vans.validation_status` / `operational_status` | pending, validated, rejected, suspended / active, maintenance, inactive |
| `operators` / `staff_profiles` validation | pending, validated, rejected, suspended |
| `users.account_status` | active, suspended, inactive |

\* Kept for older records, no longer created: `pending` (a reservation
is `confirmed` the moment it is made since cash-only), `driver_issued`
(rev 468 roadside entries). In the live data both have 0 rows.
Since 12 Nov a paid seat becomes `checked_in` when marked Paid (paying
is the check-in) and `boarded` at Depart.

**D6. Is a statement flagged when the share handed to the operator is too
low?**
**Yes, as a warning that blocks nothing.** Once every trip's passenger
list on the van's statement is locked, a share held by the operator
(given − returned) that differs from the share owed is flagged
(`share_difference`, positive = short, negative = over); the Money page
shows a warning badge "Differs by ₱…". It blocks no payment, start or
assignment: the share passes between the Dispatcher and the operator,
outside the cooperative's cash (rule T68). A share held **over** what is
owed is reported at once, lists locked or not (`share_over`), the
Cashier and the Terminal Manager are notified when an upheld dispute
causes it, and the Cashier records the excess coming back.

**D7. What camera resolution runs on the road, and how much RAM does the
phone have?**
The counting service asks the camera for **640 × 480** frames (CameraX,
closest size at or above, else below). The model input is **320 px** by
default (`yolov8n_320.tflite`); **416 px** (`yolov8n_416.tflite`) can be
chosen in the app's settings. Inference runs on the **CPU with FP16**
(fastest on the 18 Oct bench sweep). The phone, a realme 8 5G
(RMX3241, MediaTek Dimensity 700), reports **7.5 GiB RAM** (sold as
8 GB). No operating frame rate on the road is claimed until the in-van
benchmark run (part 2) exists.

**D8. Should the van position stay public by trip id?**
*No, decided 12 Nov (the group's decision C5).* Until then
`GET /tracking/trips/{trip_id}/position` and `.../history` needed no
sign-in, and the ids were no protection: `GET /trips/search` (open, so a
passenger can look before signing up) returns each bookable trip's id and
van plate, so anyone could follow any van and pull the full GPS trail of
a trip that had already arrived. The plate leads to the operator, who
always drives, so this was location data about a person (RA 10173:
legitimate purpose, proportionality).
*Now* (`backend/app/application/tracking/access.py`):
- signed out: no van at all (401);
- a passenger: only the van of a trip they hold a seat on (confirmed,
  checked in or boarded), and only while it is boarding or on the road.
  No seat, a cancelled seat or a no-show is refused in plain words (403);
  before boarding and after arrival the van is "not shown" (404), so there
  is no trail afterwards;
- the office and the crew: every van, live and afterwards (the trail is
  what a driving flag or a dispute is checked against).
The app already sends the passenger's sign-in, so riders lose nothing.
A share link for family that ends at arrival is not built. Proof:
`backend/tests/integration/test_van_location_access.sh` (33 checks).

**D9. How often does the console map refresh?**
The Overview map and the live-vans panel beside it re-read positions
every **15 seconds**; the Today panel and the top bar every **30
seconds**; the trip detail panel every 15 seconds. The phone sends GPS
**every second** while out with a van (sent in batches through its
outbox every 5 s). A position older than **120 s** is shown as stale
("last seen …").

**D10. Does the matching window exist?**
**No.** The time window that matched a door boarding to a ticket scan or
payment within a few minutes was dropped from the logic in migration 032
(cash only: no scan, no payment row to measure from) and its setting
`match_window_seconds` removed in migration **036**. The rule now: a
boarding is **listed** while an unmatched paid seat or walk-in remains on
the trip's list, and each list entry matches one boarding only (rules
T57, T59); a boarding beyond the list is **unlisted** and must be listed
as a walk-in or explained before Depart. (A stale comment in the edge
app that still mentioned the two-minute window was corrected on 12 Nov.)
