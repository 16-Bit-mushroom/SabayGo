# SabayGo — Remaining Work

*Current as of 3 September 2026. Development deadline: **27 September** — 24 days.*

---

## Done

| Group | Work | Status |
|---|---|---|
| **A** | Seat numbers removed everywhere | ✅ shipped with B |
| **B** | Walk-in timing, roadside pickup, manual fares, no-show release | ✅ |
| **C** | Cash remittance, three-bucket revenue view | ✅ |

Plus everything before those: schema, auth, booking with locking, payments
with verified webhooks, check-in, QR boarding, manifest, YOLOv8 audit,
revenue, trip generation, fleet/crew/route/fare/policy CRUD.

Suite currently at **90 passed, 3 failed** (all three are test-script
ordering, not code).

---

## Group F — guards and fixes

*Estimated 2–3 hours. Closes three of the ten revised rules.*

| # | Task | Rule | Notes |
|---|---|---|---|
| F.1 | Prevent the same van or driver being scheduled on overlapping trips | F9 | Confirmed. A 5-hour route currently generates 05:30 and 06:00 on one unit without complaint |
| F.2 | Restrict a conductor to the trip they are assigned to | F10 | Confirmed. Any conductor can currently scan any trip |
| F.3 | Sweep expired payment holds on a schedule | I4 | `sweep_expired_holds()` exists; nothing calls it |
| F.4 | Enforce a cancellation deadline | C7 | New policy row, in hours. ❓ number from terminal |

---

## Group E — notifications and warnings

*Estimated half a day.*

| # | Task | Rule | Notes |
|---|---|---|---|
| E.1 | Alert office, driver, and dashboard when a headcount difference is flagged | E7 | Confirmed a must. The `notifications` table exists and nothing writes to it |
| E.2 | Warn the office before a driver's licence expires | F8 | Confirmed |
| E.3 | Notify a passenger when their trip is about to depart | — | From the earlier review |
| E.4 | Notify driver and conductor when a booked passenger checks in | — | Depends on what D becomes |

---

## Group D — arrival confirmation ⚠️ scope in question

*Estimated half a day — but read the note first.*

Your comment: *"boarding suggests arrival naman gud, so it's redundant."*
That is a fair challenge, and it holds. The conductor looking at a passenger
is better proof of presence than a phone reading.

So check-in needs a purpose or it should be cut:

| Option | Consequence |
|---|---|
| **(a) Heads-up, not a gate** | Passenger taps "I'm here", conductor sees them coming, unclaimed spaces can be released closer to departure. Useful, blocks nobody. **Recommended.** |
| **(b) Cut it** | It is an objective in the manuscript, so this means rewriting that objective — defensible as a finding from operational review |

| # | Task | Rule | Notes |
|---|---|---|---|
| D.1 | Time confirmation against the passenger's own boarding stop | K2 | Needed for either option. Someone boarding at Kidapawan is not at Ecoland when the van leaves |
| D.2 | Allow a confirmation to be undone | K4 | Confirmed |
| D.3 | ~~Require confirmation before scanning~~ | D8 | ❓ **on hold pending your decision** |

---

## Group G — office and passenger self-service

*Estimated a day. Can run alongside Flutter work.*

| # | Task | Notes |
|---|---|---|
| G.1 | Export reports to spreadsheet | Cooperatives keep books; JSON is not usable |
| G.2 | View resolved audit history | Only the pending queue is readable — that defeats the *trail* part of audit trail |
| G.3 | Crew roster: who drives what, when | Arguably a Tier 2 miss; "fleet management" implies seeing assignments |
| G.4 | Passenger edits own name, phone, password | |
| G.5 | Passenger closes own account | Data Privacy Act right to erasure |
| G.6 | Abandon a checkout and release the space immediately | Currently must wait 10 minutes |
| G.7 | Single-booking detail endpoint | |
| G.8 | Notifications and saved-destinations endpoints | Tables and models exist, nothing reads them |
| G.9 | Passenger lookup by name or ticket number | For the conductor |

---

## Flutter — the real constraint

*13 days in the original plan. Both apps still run entirely on mock data.*

| Phase | Work |
|---|---|
| Passenger app | Register, search, book, pay, e-ticket, check-in, notifications |
| Conductor app | QR scan, manifest, walk-in and roadside logging, remittance |
| Operator console | Fleet, crew, schedules, policy editor, audit queue, revenue |

Everything else on this page is optional. **This is not.**

---

## Recommended order

1. **Group F** — 2–3 hours, closes three confirmed rules
2. **Flutter** — start this week, not Sep 15
3. **Groups E, D, G** — build alongside the UI work

Nothing in E, D, or G blocks Flutter. Doing F first means the backend is
settled before two clients start depending on it.

---

## Questions for a terminal visit

None of these need a signed partner. Any conductor at Ecoland can answer
them in five minutes.

1. **Do passengers GCash conductors directly?** If so it behaves like cash —
   crew holds it, crew remits it — but the office counts a handover of
   banknotes differently from one that is partly already in an e-wallet
2. **Is a cancellation deadline useful, and how many hours?**
3. **Would knowing in advance who has arrived help you dispatch?** This
   decides whether check-in survives
4. **How far across your compound might a waiting passenger be?** A terminal
   is not a point — too tight a radius fails honest passengers, too loose
   lets someone confirm from a nearby mall

---

## Also outstanding, not code

| | Status |
|---|---|
| Objectives sign-off | **Overdue since 16 August** |
| Paper revision | Due **11 September** |
| Pilot partner | Needed by **6 October** for alpha testing |

The backend is ahead of schedule. These three are not, and none of them
gets fixed by writing more code.