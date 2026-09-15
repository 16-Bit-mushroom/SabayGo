# SabayGo — Remaining Work

*Current as of 15 September 2026. Development deadline: **27 September** — 12 days.*

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
| ~~G.1~~ | ~~Export reports to spreadsheet~~ | ✅ 15 Sep. `GET /revenue/export?format=xlsx|csv&date_from&date_to` — workbook has a totals row and an About sheet explaining *cash in hand* vs *unreconciled*. Console Revenue tab: Export menu |
| ~~G.2~~ | ~~View resolved audit history~~ | ✅ 15 Sep. `GET /audits/history?status=&trip_id=` with resolver and notes. Console Audits tab: Queue / History switch; closed audits show their disposition instead of the buttons |
| G.3 | Crew roster: who drives what, when | Arguably a Tier 2 miss; "fleet management" implies seeing assignments |
| G.4 | Passenger edits own name, phone, password | |
| G.5 | Passenger closes own account | Data Privacy Act right to erasure |
| G.6 | Abandon a checkout and release the space immediately | Currently must wait 10 minutes |
| ~~G.7~~ | ~~Single-booking detail endpoint~~ | ✅ 15 Sep. `GET /bookings/{id}`, same shape as `/mine`; 404 for anyone else's. Ticket screen now polls this instead of the whole list |
| G.8 | ~~Notifications~~ and saved-destinations endpoints | Notifications done with E.1; saved destinations still unread |
| G.9 | Passenger lookup by name or ticket number | For the conductor |

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