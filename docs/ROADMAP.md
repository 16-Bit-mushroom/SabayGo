# SabayGo — Development Roadmap

Last updated: 15 September 2026

---

## Milestones

| Date | Milestone | Status |
|---|---|---|
| Aug 16 | Title, objectives, user requirements agreed | ✅ approved by adviser |
| **Sep 11** | Capstone paper revision submitted | ✅ adviser approved — research coordinator reviewing (week of 15 Sep) |
| **Sep 27** | Development substantially complete | All scheduled code blocks done as of 14 Sep; hardening can start early |
| Oct 5 | Testing-ready | |
| Oct 6–12 | Alpha testing | A2Z reconciled as pilot partner (see below) |
| Oct 13–19 | Beta testing | |
| Oct 19 | Final defense-ready; endorsement letter | |
| Oct 20+ | Final defense | |
| Nov 16–22 | Public presentation | |
| Dec 13 | Print-ready manuscript | |
| Dec 18–19 | Hardbound submission | |

---

## Current state (15 Sep)

**Done**

- MySQL 8.0 schema — 11 migrations, revenue reconciliation view, deployed and seeded
- `cooperative_policies` — configurable rows, snapshotted onto each trip at generation
- AI node — YOLOv8 with face blurring, persistent camera, API-key auth, timing metrics
  - Benchmarked: 122 ms warm median inference (12× faster than cold start)
- FastAPI backend — complete. Auth · registration · trip search · segment
  booking with pessimistic locking · PayMongo checkout + verified webhooks ·
  reschedule/cancel · geofenced check-in · QR boarding · manifest · headcount ·
  YOLOv8 audit persistence · cash remittance and three-bucket revenue view ·
  trip generation · fleet/crew/route/fare/policy CRUD · scheduling conflict
  guards · crew trip restriction · hold sweeper · cancel deadline · NAHGM live
  tracking · `GET /trips/assigned`
- **Segment-based seat inventory with pessimistic locking — validated**
  - 50 concurrent requests → 10 created, 0 double-booked, cap respected
  - Controlled comparison: unlocked cap check allowed 14 > 10; moving it inside
    the lock fixed it. Both runs recorded as Results evidence.
- Flutter mobile — passenger loop (Phase 2) and conductor workflow (Phase 3)
  wired to the live backend, verified on a physical device 11 and 14 Sep
- Flutter Web operator console — all six coop_admin modules wired to the live
  backend (`1708ace`, 14 Sep)
- Journey suite: 126 passed, 2 failed (fixture self-conflict, not defects)

- In-app notifications (E.1, 15 Sep) — variance alerts to office, driver,
  conductor; bells in the console and conductor app
- Check-in decided as a heads-up for dispatch (Group D, 15 Sep) — window
  against the passenger's own stop, undo endpoint, migration 012
- Group G small items (15 Sep) — single-booking GET, audit history with a
  console History view, revenue export to `.xlsx`/`.csv`
- Hardening started (15 Sep) — multi-route demo dataset, rehearsal script
  and talk track, timezone clean-up; multi-route search and the revenue
  view fan-out found and fixed

**Not built**

Remaining notifications (E.2 licence expiry, E.3 departure reminder, E.4
check-in heads-up to crew) · office/passenger self-service (Group G:
crew roster, profile edit, account deletion, abandon checkout, passenger
lookup) · live map · chat · auto-detect "Van is at" on the manifest
screen. See `REMAINING_WORK.md`.

---

## Priority tiers

### Tier 1 — the core loop (must have)x

> register → login → search → book → **pay** → e-ticket → check-in →
> **scan** → board → manifest → **audit** → revenue

This is simultaneously the demo, the alpha test script, and the defense
walkthrough. Every item is load-bearing.

**Payment is blocking, not optional.** Booking currently ends at
`status='pending'` / seat `held` with a 10-minute TTL, and nothing confirms
it. Without payment the hold sweeper releases the seat and the booking
dangles forever. Same for QR: `qr_payload` is generated but nothing scans it.x

### Tier 2 — needed to configure any cooperative

Fleet CRUD · route + fare CRUD · schedule templates · trip generator ·
policy editor. Whoever the partner turns out to be, they need these to enter
their own data.

### Tier 3 — defer or cut

| Item | Decision |
|---|---|
| Offline sync | Walk-in logging only; declare the rest a limitation |
| FCM push | In-app notification list is enough for testing |
| Google Maps | Static terminal list, or cut |
| iOS build | Android only — state in Scope |
| Ticket booklet inventory | Defer |
| Twilio SOS | **Remove from architecture diagram** — not in any objective |
| Live PayMongo account | Sandbox only; KYC takes weeks |

---

## Schedule

### Aug 25–31 — close the passenger loop ✅ (done 24 Aug, `663a769`)

- Registration endpoint (passenger self-signup)
- Trip search + detail endpoints
- PayMongo **sandbox** integration + webhook
  - Idempotency via `payments.provider_event_id` UNIQUE
  - Webhook flips `pending → confirmed`, seat `held → booked`
- Reschedule + cancel (`Booking.assert_can_reschedule()` already written)

### Sep 1–7 — close the operations loop ✅ (done 25 Aug, `686ccde`)

- Audit trigger: FastAPI ↔ AI node, persist to `yolov8_audit_logs`
  - Variance computed server-side against the manifest, never client-side
- Geofence check-in (haversine vs. terminal coords, server-validated)
- QR boarding validation
- Trip manifest endpoint
- Driver headcount confirmation

### Sep 8–14 — configuration + paper ✅ (code done 25 Aug–4 Sep; paper approved)

- Trip generator (nightly job from `schedule_templates`)
- Fleet / route / fare / policy CRUD
- Revenue reconciliation endpoints
- Group F guards — scheduling conflicts, crew restriction, hold sweeper,
  cancel deadline (`18b5050`, 4 Sep)
- Sep 11 paper revision — submitted and adviser-approved

### Sep 15–27 — Flutter only ✅ (done 10–14 Sep, `8160136` → `1708ace`)

Planned as thirteen days; took five. Phase 1 foundation → Phase 2 passenger
→ Phase 3 conductor → Phase 4 operator console, all on the live backend.
The block that was expected to overrun finished before it was due to start.

**Sep 15–27 is now free.** Use it for Group E (headcount alerts), the
Group D decision, the small Group G items, and an early start on hardening.

### Sep 28 – Oct 5 — hardening ✅ started 15 Sep

Demo dataset seeded (placeholder routes until A2Z answers) · rehearsal
script green end to end · two defects found by the dataset and fixed.
Left: real A2Z data · evaluation instruments · rehearsal on the demo
machine with the camera

---

## Partner situation

**A2Z Transport Cooperative is reconciled as pilot partner** (September
2026). The earlier silence is resolved; alpha testing from Oct 6 proceeds
with them.

**Why a partner change would cost almost nothing in code, should it recur:**
every undecided policy is a row in `cooperative_policies`, and seed data is
a single route. Swapping partners is an `UPDATE` and a seed edit, not a
redesign. What a partner actually provides is alpha/beta respondents and
the endorsement letter.

**Real deadline: Oct 6** — testing needs people before the signature does.

### Next with A2Z

- [ ] Ask the four terminal questions — `QUESTIONS_FOR_COOPERATIVE.md`
      (plain English, Tagalog and Bisaya, printable)
- [ ] Seed their real routes, fares and schedule templates
- [ ] Line up alpha respondents: passengers, one conductor, one office staff
- [ ] Endorsement letter on department letterhead

---

## Standing decisions

| Decision | Rationale |
|---|---|
| Keep Flutter Web for operator console | 3 modules already built; rewriting costs a week and buys a faster page load nobody grades |
| `mobile/` = passenger + conductor + driver | Field roles, phone-shaped |
| `operator_console/` = operator only | Desk-shaped, browser |
| Rich entities only where invariants exist | `Booking` yes; `Terminal` is CRUD. Uniform DDD ceremony is cargo-culting |
| Coarse seat lock (whole candidate window) | Plan-independent and provably correct; right trade-off at 14 seats, wrong at 400 |
| Policy snapshotted onto each trip | A later policy change never alters terms already sold under |

## Known issues

- `ticket_number` uses a 6-hex suffix — collision surfaces as IntegrityError,
  not a retry. Widen to 8 or add a retry loop before production.
- Seed emails and departure date need fixing after every `--reset --seed`;
  `db/reset-dev.sh` handles it.
- ORM models missing for: `passenger_settings`, `saved_destinations`,
  `van_photos`, `ticket_booklets`, `physical_tickets`, `driver_headcounts`.
  Add when the features that touch them get built.