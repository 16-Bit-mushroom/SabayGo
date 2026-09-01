# SabayGo — Development Roadmap

Last updated: 24 August 2026

---

## Milestones

| Date | Milestone | Status |
|---|---|---|
| Aug 16 | Title, objectives, user requirements agreed | ⚠️ **OVERDUE** — resolve with adviser this week |
| **Sep 11** | Capstone paper revision submitted | |
| **Sep 27** | Development substantially complete | |
| Oct 5 | Testing-ready | |
| Oct 6–12 | Alpha testing | ← **partner needed by here** |
| Oct 13–19 | Beta testing | |
| Oct 19 | Final defense-ready; endorsement letter | |
| Oct 20+ | Final defense | |
| Nov 16–22 | Public presentation | |
| Dec 13 | Print-ready manuscript | |
| Dec 18–19 | Hardbound submission | |

---

## Current state (24 Aug)

**Done**

- MySQL 8.0 schema — 25 tables + revenue reconciliation view, deployed and seeded
- `cooperative_policies` — 11 configurable rows; undecided policy is data, not code
- AI node — YOLOv8 with face blurring, persistent camera, API-key auth, timing metrics
  - Benchmarked: 122 ms warm median inference (12× faster than cold start)
- FastAPI backend — Clean Architecture, JWT auth, async SQLAlchemy 2.0
- **Segment-based seat inventory with pessimistic locking — validated**
  - 50 concurrent requests → 10 created, 0 double-booked, cap respected
  - Controlled comparison: unlocked cap check allowed 14 > 10; moving it inside
    the lock fixed it. Both runs recorded as Results evidence.
- Walk-in logging with optional passenger details (per consultation)

**Not built**

Registration · payment · trip search · reschedule/cancel · check-in ·
QR boarding · manifest · headcount · audit persistence · revenue endpoints ·
notifications · all CRUD · trip generator · every Flutter screen (mock data)

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

### Aug 25–31 — close the passenger loop

- Registration endpoint (passenger self-signup)
- Trip search + detail endpoints
- PayMongo **sandbox** integration + webhook
  - Idempotency via `payments.provider_event_id` UNIQUE
  - Webhook flips `pending → confirmed`, seat `held → booked`
- Reschedule + cancel (`Booking.assert_can_reschedule()` already written)

*Parallel:* finalize objectives with adviser · begin terminal visits

### Sep 1–7 — close the operations loop

- Audit trigger: FastAPI ↔ AI node, persist to `yolov8_audit_logs`
  - Variance computed server-side against the manifest, never client-side
- Geofence check-in (haversine vs. terminal coords, server-validated)
- QR boarding validation
- Trip manifest endpoint
- Driver headcount confirmation

### Sep 8–14 — configuration + paper

- Trip generator (nightly job from `schedule_templates`)
- Fleet / route / fare / policy CRUD
- Revenue reconciliation endpoints
- **Sep 11 paper revision due — protect this time**

### Sep 15–27 — Flutter only

Thirteen days, two apps. Passenger → conductor → operator console.
Most likely block to overrun; nothing else belongs in it.

### Sep 28 – Oct 5 — hardening

Bug bash · seed real cooperative data · prepare test scripts and
evaluation instruments · rehearse the demo end to end

---

## Partner situation

A2Z Transport Cooperative has stopped responding. Assume they are gone.

**Why this costs almost nothing in code:** every undecided policy is a row in
`cooperative_policies`, and seed data is a single route. Swapping partners is
an `UPDATE` and a seed edit, not a redesign.

**What it actually risks:** alpha/beta respondents and the endorsement letter.

**Real deadline: Oct 6**, not Oct 19 — testing needs people before the
signature does.

### Actions

- [ ] Tell the adviser this week (they may have contacts)
- [ ] Request an endorsement letter on department letterhead
- [ ] Approach 3–4 terminals simultaneously, not one at a time
- [ ] **LTFRB Region XI** — holds the franchise register for accredited UV
      Express operators; converts "who do we ask?" into a contact list
- [ ] Ecoland Terminal (southbound: Digos, Kidapawan, GenSan, Cotabato)
- [ ] DCOTT (northbound: Tagum, Mati, Nabunturan)

### Tactics

Show up **in person** — a Facebook message is what just failed. Go **6–8am**
when operations run and the manager is on site. Bring the **laptop** and make
a live booking, then run the YOLOv8 audit on the room. Lead with **their**
problem: undocumented walk-in boardings not showing up in revenue.

### Manuscript edits

- Replace the named cooperative with a placeholder until one is secured
- Reframe scope as *terminal-based UV Express operations in Davao City*,
  with a cooperative as pilot respondent — academically cleaner, and stops
  one company's silence from invalidating the framing
- Existing requirements came from observation and literature; still valid

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