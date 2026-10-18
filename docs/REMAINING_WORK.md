# SabayGo — Remaining Work

*Current as of 18 October 2026 (rev 603). The open work is the first
section. Everything after it is the September record, kept as history:
its suite counts, deadlines and "done" rows describe the code as it was
then, and several of those features were retired on 16 Oct (noted where
they appear).*

---

## Open, 18 October

| # | Work | Who | State |
|---|---|---|---|
| 1 | **Phone benchmark** | owner, in a van | Models exported (YOLOv8n TFLite at 320 and 416 px, git-ignored under `edge_app/app/src/main/assets/models/`), debug APK built 14 Oct. Left: plug in the Realme, install, Sweep, one full Run on vehicle power, then the report in `docs/benchmarks/` via `edge_app/tools/summarise_benchmark.py`. No frame rate is quoted before that report exists |
| 2 | **Edge app proper** (brief 5.1–5.3) | Claude, after 1 | Door line and seat mask, ByteTrack, offline queue, heartbeats, clock sync from `GET /edge/session`, blurred still, all against `/edge/*` (built and tested). Then the Realme setup checklist |
| 3 | **A2Z's figures** | owner asks A2Z | These settings ship unset, which turns their feature off: `depart_zone_radius_m` + `depart_readings` (no GPS departure), `home_pickup_max_route_m` (no home pickup), `special_trip_speed_kmh` (no rental flagged), per-stretch speed limits (only stops flagged). Also the real routes, fares, timetable and SOS numbers in place of the `002_demo_dataset.sql` placeholders, and the questions below |
| 4 | **Manuscript** | owner | Paste `MANUSCRIPT_CORRECTIONS.md` into the `.docx` |

Closed on 16 Oct, though older lists still carry them:

- **Rev 468 leftovers** (`d57fd01`): the AI node (`ai_service/app.py`),
  `ai_capture_app/`, `/audits/*` and `/revenue/*` are removed.
  `ai_service/` keeps only the evaluation harness (`inference.py`,
  `eval/`), which measured the weights the phone runs. The
  `cash_remittances` and `yolov8_audit_logs` tables and the revenue view
  stay as history: nothing writes them, and dropping them would lose the
  September records.
- **"Missing" endpoints in the runner** (`1169e7b`): four were built at
  other URLs, three are not in rev 603. See Group G.
- **The YOLOv8 evaluation report exists**:
  `docs/benchmarks/ai_count_2026-10-09_full.txt` (and the 8 Oct run), at
  640 px. The phone runs at 320 or 416 px, so a re-run at its size is
  still worth having.

Journey suite: **922 passed, 0 failed** (16 Oct).

---

## Done

| Group | Work | Status |
|---|---|---|
| **A** | Seat numbers removed everywhere | ✅ shipped with B |
| **B** | Walk-in timing, roadside pickup, manual fares, no-show release | ✅ |
| **C** | Cash remittance, three-bucket revenue view | ✅ |
| **F** | Scheduling conflicts, crew trip restriction, hold sweeper, cancel deadline | ✅ `18b5050`, 4 Sep |
| **Flutter 1–2** | API client, token storage, role routing; full passenger loop | ✅ `8160136`–`b8b731a`, 10–11 Sep |
| **Flutter 3** | Conductor: scan, walk-in/roadside, headcount, depart, remit | ✅ `b66dc5e`, 14 Sep |
| **Flutter 4** | Operator console: six coop_admin modules on the live backend | ✅ `1708ace`, 14 Sep |
| **E.1** | Variance alert → notifications for office, driver, conductor; `/notifications` API; bells in console and conductor app; passenger tab off mock data | ✅ 15 Sep |
| **D** | Check-in decided as heads-up (a). D.1 window against the passenger's own stop; D.2 undo (`DELETE /bookings/{id}/check-in`, migration 012) | ✅ 15 Sep |
| **G.7 / G.2 / G.1** | Single-booking GET; resolved-audit history with a History view in the console; revenue export to `.xlsx`/`.csv` with an Export button | ✅ 15 Sep |

Plus everything before those: schema, auth, booking with locking, payments
with verified webhooks, check-in, QR boarding, manifest, YOLOv8 audit,
revenue, trip generation, fleet/crew/route/fare/policy CRUD, NAHGM live
tracking.

Suite currently at **126 passed, 2 failed** (both fixture self-conflict —
`--soon` makes check-in testable and reschedule untestable at once).

F.4's cancel-deadline hour value is still a placeholder — it comes from
terminal question 2 below.

---

## Group E — notifications and warnings

*Estimated half a day.*

| # | Task | Rule | Notes |
|---|---|---|---|
| ~~E.1~~ | ~~Alert office, driver, and dashboard when a headcount difference is flagged~~ | E7 | ✅ 15 Sep. `NotificationService.notify_variance` in the audit transaction |
| E.2 | Warn the office before a driver's licence expires | F8 | Confirmed |
| E.3 | Notify a passenger when their trip is about to depart | — | From the earlier review |
| E.4 | Notify driver and conductor when a booked passenger checks in | — | Unblocked by D (a). Same `NotificationService`; the manifest already shows "AT TERMINAL", so this is optional polish |

---

## Group D — arrival confirmation ✅ decided 15 Sep: heads-up, not a gate

Your comment: *"boarding suggests arrival naman gud, so it's redundant."*
That held. The conductor looking at a passenger is better proof of presence
than a phone reading, so check-in is kept as **option (a)**: a heads-up for
dispatch. The passenger taps "I'm here", the conductor's manifest shows
"AT TERMINAL", unclaimed spaces can be released closer to departure. It
never blocks a scan. The objective in the manuscript stands as written.

| # | Task | Rule | Notes |
|---|---|---|---|
| ~~D.1~~ | ~~Time confirmation against the passenger's own boarding stop~~ | K2 | ✅ Window is `departure + route_stops.offset_minutes` for the boarding stop. `/bookings/mine` now carries `boarding_due_at` and `checkin_opens_at`; the ticket screen shows "Check-in opens 8:59 AM at Digos" |
| ~~D.2~~ | ~~Allow a confirmation to be undone~~ | K4 | ✅ `DELETE /bookings/{id}/check-in` while `checked_in`; 409 once boarded. The `check_ins` row is kept and stamped `undone_at` (migration 012). "Undo check-in" button on the ticket |
| D.3 | ~~Require confirmation before scanning~~ | D8 | ✂️ Dropped — follows from (a). Rule D8 should be reworded in the manuscript to "check-in is advisory" |

Terminal question 3 still goes to A2Z — it now confirms whether dispatch
uses the heads-up rather than deciding whether it exists.

---

## Group G — office and passenger self-service

*Estimated a day. Can run alongside Flutter work.*

| # | Task | Notes |
|---|---|---|
| ~~G.1~~ | ~~Export reports to spreadsheet~~ | ✅ 15 Sep, **retired 16 Oct** with `/revenue/*`. Rev 603's record is the Remittance statements; Member Records exports CSV/PDF |
| ~~G.2~~ | ~~View resolved audit history~~ | ✅ 15 Sep, **retired 16 Oct** with `/audits/*`. Rev 603: Boarding Audit, Disputes (decided / withdrawn) |
| ~~G.3~~ | ~~Crew roster: who drives what, when~~ | ✅ rev 603. `GET /config/trips?date=` carries each trip's van, operator and Dispatcher; console Trips page. The office journey checks it |
| ~~G.4~~ | ~~Passenger edits own name, phone, password~~ | ✅ `PATCH /auth/me` (password needs `current_password`) |
| ~~G.5~~ | ~~Passenger closes own account~~ | ✅ `POST /auth/me/close` with the password; soft close, the token and sign-in stop working |
| ~~G.6~~ | ~~Abandon a checkout and release the space immediately~~ | ✅ `POST /bookings/{id}/cancel` releases an unpaid hold at once |
| ~~G.7~~ | ~~Single-booking detail endpoint~~ | ✅ 15 Sep. `GET /bookings/{id}`, same shape as `/mine`; 404 for anyone else's. Ticket screen now polls this instead of the whole list |
| ~~G.8~~ | ~~Notifications~~ and saved-destinations endpoints | Notifications done with E.1. Saved destinations: **not in rev 603, not built** (16 Oct); the table and ORM model stay unread |
| ~~G.9~~ | ~~Passenger lookup by name or ticket number~~ | **Not in rev 603, not built** (16 Oct). The Dispatcher works from the list and the scan |
| — | Passenger notification settings (`passenger_settings`) | **Not in rev 603, not built** (16 Oct) |

The journey scripts probed G.3–G.6 at URLs that were never built, so they
reported them as gaps after they were done; the probes now call the real
endpoints (16 Oct).

---

## Flutter — done

*Planned as 13 days; took five (10–14 Sep). All three clients run on the
live backend.*

| Phase | Work | Verified |
|---|---|---|
| Passenger app | Register, search, book, pay, e-ticket, check-in, my bookings, reschedule, cancel | Physical device, 11 Sep |
| Conductor app | Assigned trips, manifest, QR scan verdicts, walk-in and roadside, headcount, depart, remittance | Physical device, 14 Sep |
| Operator console | Fleet & crew, dispatcher, schedules, policy editor, audit queue, revenue | CDP click-through, 14 Sep |

Still missing on the clients: live map, chat, auto-detect "Van is at" on
the manifest screen. The notification list is live (E.1); E.2–E.4 would
reuse the same `NotificationService` and appear in it without client work.

---

## Recommended order

1. ~~E.1~~ done 15 Sep
2. ~~Group D~~ decided (a) and built, 15 Sep
3. ~~G.7, G.2, G.1~~ done 15 Sep
4. **Hardening** — started 15 Sep. Done: multi-route demo dataset
   (`002_demo_dataset.sql`), demo rehearsal script and talk track
   (`DEMO_SCRIPT.md`), timezone fix in `payments.py` and three other
   files, and two defects the dataset exposed — single-route search and a
   fan-out in the revenue view (migration 013). Left: A2Z's real data in
   place of the placeholders; rehearsal on the demo machine with the AI
   node; release-build check for the dev chips. `seat_repository.py`
   keeps its own review

### Van kit stand-in — verified 16 Sep, no kit needed to keep building

Neither piece of the physical van kit (camera, GPS) blocks development.
Both are designed to run as an HTTP client against the same production
endpoints a real kit would hit, so nothing changes on the backend when
the real hardware shows up — only where the phone and the GPS device
point.

- **Camera** (rev 603, 16 Oct): the in-van phone is the camera and runs
  the model itself (`edge_app/`); the rev 468 AI node and its laptop-webcam
  stand-in are retired. Without a phone, a test plays one over HTTP
  against `/edge/*`, as `tests/integration/test_edge_ingestion.sh` does:
  add a phone (`POST /devices`), check it out to a van, then post door
  events, fixes and heartbeats.
- **GPS**: `backend/scripts/tracking_simulator.py` posts to the real
  production `POST /tracking/trips/{trip}/ping` endpoint (not a mock
  table) — confirmed end to end: a simulated run against
  `TRIP-DEMO-00000001` produced 49 pings and `GET
  .../position` correctly reflected the van's final location. A real GPS
  unit authenticates the same way, with the same `X-Tracker-Key` header.
  **When the kit arrives:** point it at the same ping endpoint with the
  same header — no backend change needed.
  **Open decision:** `TRACKER_API_KEY` is unset in `backend/.env`, so
  `verify_tracker` currently accepts pings with no auth at all. Fine for
  a laptop simulator on localhost; worth setting before a real device
  pings the endpoint over a real network. Auth is also one shared secret
  for every van, not per-device (`vans.camera_device_id` exists but isn't
  wired to tracking auth) — flagged in `tracking.py` as its own future
  work, not blocking.

---

## Questions for A2Z

The partner is reconciled, so these go to A2Z directly. Any dispatcher or
conductor can answer them in five minutes. A printable version in plain
English, Tagalog and Bisaya is in `QUESTIONS_FOR_COOPERATIVE.md`.

1. **Do passengers GCash conductors directly?** If so it behaves like cash —
   crew holds it, crew remits it — but the office counts a handover of
   banknotes differently from one that is partly already in an e-wallet
2. **Is a cancellation deadline useful, and how many hours?** Sets F.4's
   `cancel_cutoff_hours`
3. **Would knowing in advance who has arrived help you dispatch?** Group D
   is built as a heads-up; this confirms whether dispatch will use it
4. **How far across your compound might a waiting passenger be?** A terminal
   is not a point — too tight a radius fails honest passengers, too loose
   lets someone confirm from a nearby mall. Sets `default_geofence_radius_m`

---

## Also outstanding, not code

| | Status |
|---|---|
| Objectives sign-off | ✅ approved by adviser |
| Paper revision | ✅ adviser approved; research coordinator reviewing week of 15 Sep |
| Pilot partner | ✅ A2Z reconciled. Alpha testing from **6 October** |

All three non-code milestones are now clear. What remains before alpha is
A2Z's answers to the four questions above, their real route and schedule
data seeded, and respondents lined up.