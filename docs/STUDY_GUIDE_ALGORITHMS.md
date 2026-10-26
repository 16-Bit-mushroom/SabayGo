# SabayGo — Study Guide: The Two Algorithms

> How **YOLOv8 passenger reconciliation** and **NAHGM live tracking** work,
> traced through the actual source code. Written to study from before the
> defence. Every claim here points to a file and line you can open.

---

## Contents

1. [The one-minute version](#1-the-one-minute-version)
2. [Where the code lives](#2-where-the-code-lives)
3. [Algorithm 1 — YOLOv8 passenger reconciliation](#3-algorithm-1--yolov8-passenger-reconciliation)
4. [Inside `ai_service/app.py`, top to bottom](#4-inside-ai_serviceapppy-top-to-bottom)
5. [Algorithm 2 — NAHGM live tracking](#5-algorithm-2--nahgm-live-tracking)
6. [Where the two algorithms meet](#6-where-the-two-algorithms-meet)
7. [Rules the code refuses to break](#7-rules-the-code-refuses-to-break)
8. [Questions the panel may ask](#8-questions-the-panel-may-ask)
9. [Glossary](#9-glossary)

---

## 1. The one-minute version

SabayGo has **two independent intelligence layers**. Neither is part of
booking — booking stays a plain reservation system.

| | **YOLOv8 reconciliation** | **NAHGM tracking** |
|---|---|---|
| **Closes which gap?** | Revenue leakage — passengers who ride but never get recorded | Visibility — nobody outside the van knows where it is |
| **Input** | One photo of the van cabin | A stream of GPS positions |
| **Core idea** | `variance = people the camera sees − people the manifest says` | Haversine distance to every route node → nearest node → ETA |
| **Is it AI?** | Yes — a pretrained object detector | **No** — pure geometry |
| **Output** | An audit row: match / more / fewer than the manifest | Van position, nearest stop, ETA to each stop ahead |
| **Runs where?** | Counting in `ai_service/` (Flask), comparison in `backend/` (FastAPI) | Entirely in `backend/` |

**The sentence to remember:**
> *The camera reports what it saw. The server decides what it means.*
> The AI node never sees a manifest, and NAHGM never guesses a position it
> was not given.

---

## 2. Where the code lives

```
ai_service/
├── app.py          ← HTTP service: camera, routes, error handling     (§4)
├── inference.py    ← the model, the count, face blur, box drawing      (§3.2)
└── eval/           ← measures the model's accuracy (separate topic)

backend/app/
├── application/
│   ├── tracking/
│   │   └── nahgm.py               ← ★ NAHGM: map matching, ETA, node departure   (§5)
│   ├── audit/
│   │   ├── trigger_audit.py       ← ★ YOLOv8 reconciliation: variance, alert, save (§3.3)
│   │   └── auto_trigger.py        ← automatic captures (door close, GPS node)    (§6)
│   └── operations/
│       ├── check_in.py            ← haversine_m()  — the distance formula        (§5.2)
│       └── boarding.py            ← booked_count_on_leg(), occupies_leg()        (§3.3)
├── domain/
│   └── audit_reading.py           ← turns two numbers into plain words           (§3.4)
├── infrastructure/clients/
│   └── ai_node_client.py          ← backend → AI node HTTP client               (§3.3)
└── api/v1/
    ├── tracking.py                ← NAHGM endpoints  (/tracking/...)
    └── audits.py                  ← audit endpoints  (/audits/...)

backend/scripts/tracking_simulator.py  ← replays a GPS trip for demos
db/migrations/011_trip_location_pings.sql ← the table NAHGM writes to
```

**NAHGM is one file:** [backend/app/application/tracking/nahgm.py](../backend/app/application/tracking/nahgm.py).
Its HTTP face is [backend/app/api/v1/tracking.py](../backend/app/api/v1/tracking.py),
and it borrows one function, `haversine_m`, from
[check_in.py](../backend/app/application/operations/check_in.py#L50).

---

## 3. Algorithm 1 — YOLOv8 passenger reconciliation

### 3.1 The idea in one picture

```
   ┌──────────────┐                         ┌──────────────────────┐
   │ Cabin camera │ ── photo ──►  YOLOv8 ──►│ C_visual = 5 people  │
   └──────────────┘                         └──────────┬───────────┘
                                                       │
   ┌──────────────┐                         ┌──────────▼───────────┐
   │ MySQL        │ ── manifest for leg ──► │ C_booked = 4 tickets │
   └──────────────┘                         └──────────┬───────────┘
                                                       │
                                            Δ = C_visual − C_booked = +1
                                                       │
                                     ┌─────────────────▼─────────────────┐
                                     │ |Δ| ≥ threshold (1)?  → FLAG      │
                                     │ otherwise             → reconciled│
                                     └───────────────────────────────────┘
```

A paper logbook can be falsified by leaving a name out. The camera count
exists **outside** the manifest, so leaving someone out of the manifest
makes the two numbers disagree. That disagreement is the evidence.

### 3.2 Step 1 — Counting people (`ai_service/inference.py`)

[`count_people()`](../ai_service/inference.py#L107) is the single function
that turns a frame into a number.

```python
results = model(frame,
                classes=[PERSON_CLASS_ID],   # 0 = "person" in COCO
                conf=CONF_THRESHOLD,         # 0.45
                iou=IOU_THRESHOLD)           # 0.50
```

| Setting | Value | What it means |
|---|---|---|
| Model | `yolov8n.pt` | YOLOv8 *nano*, pretrained on COCO, **not retrained** |
| `classes=[0]` | person only | Bags, seats, cars are ignored |
| `conf` | **0.45** | A box under 45 % confidence is discarded |
| `iou` | 0.50 | Two boxes overlapping > 50 % are merged (one person, not two) |

The result is a `Detections` object. **`count` is simply the number of
boxes** — that number is `C_visual`.

**Why 0.45 and not the default 0.25?** Measured, not guessed
([inference.py:37-57](../ai_service/inference.py#L37-L57)). A higher
threshold means fewer false accusations but fewer catches:

| Threshold | False accusation of an honest crew | Catches one hidden passenger |
|---|---|---|
| 0.25 | 9.6 % | 87.7 % |
| 0.35 | 4.6 % | 82.8 % |
| **0.45** | **2.7 %** | **77.5 %** |
| 0.65 | 0.7 % | 65.6 % |

> These come from COCO street photographs, not a real van cabin
> (`docs/benchmarks/ai_count_2026-10-09_full.txt`). Say so if asked.

**Two image treatments** happen after counting:

- [`blur_faces()`](../ai_service/inference.py#L152) — blurs the **top 28 %**
  of each person box (where the head usually is). Required by **RA 10173**
  (Data Privacy Act): the snapshot is kept as evidence, so faces must not be
  readable. Cheap heuristic on purpose — a second face model would double
  inference time on an Orange Pi.
- [`draw_boxes()`](../ai_service/inference.py#L170) — draws a green box and
  the confidence score on each person, so a human can check the count.

### 3.3 Step 2 — Comparing against the manifest (`backend/.../trigger_audit.py`)

The backend is the only place that knows about trips and tickets.
[`TriggerAuditUseCase`](../backend/app/application/audit/trigger_audit.py#L67)
runs this sequence:

```
1. ensure_auditable()      trip exists and is "boarding" or "departed"
2. booked_count_on_leg()   C_booked — read BEFORE the photo, so both
                           numbers describe the same moment
3. ai.capture()            ask the AI node for C_visual   (fails → 502, no row)
4. variance = C_visual − C_booked
5. alert = |variance| ≥ variance_alert_threshold   (policy, default 1)
6. save the blurred snapshot to media/audits/
7. INSERT yolov8_audit_logs  — "pending" if alert, else "reconciled"
8. if alert: notify office, driver, conductor   ← same transaction as step 7
9. COMMIT
10. read_audit() → plain-language verdict for the screen
```

**Who counts as "on the manifest" for leg *k*?**
[`occupies_leg()`](../backend/app/application/operations/boarding.py#L25):

```
boarding_stop ≤ k   AND   alighting_stop > k
```

and the booking's status is `confirmed`, `checked_in` or `boarded`.

**Worked example** — 4-stop route, three passengers:

| Passenger | Rides | Leg 1 (stop 1→2) | Leg 2 (2→3) | Leg 3 (3→4) |
|---|---|---|---|---|
| A | 1 → 2 | ✅ | ❌ *got off at 2* | ❌ |
| B | 2 → 4 | ❌ | ✅ | ✅ |
| C | 1 → 4 | ✅ | ✅ | ✅ |
| **C_booked** | | **2** | **2** | **2** |

If the code counted A on leg 2, the manifest would say 3 while the camera
correctly sees 2 — and every honest trip would look wrong. That is why the
`>` (not `≥`) on alighting matters.

### 3.4 Step 3 — Reading the result (`backend/app/domain/audit_reading.py`)

The **direction** of the difference changes its meaning completely.
[`read_audit()`](../backend/app/domain/audit_reading.py#L45):

| Variance | Verdict | What it means | Is it lost money? |
|---|---|---|---|
| **Δ > 0** | `more_than_manifest` | Possible unrecorded passengers | **Possibly — this is the case the system exists for** |
| **Δ = 0** | `match` | All passengers accounted for | No |
| **Δ < 0** | `fewer_than_manifest` | Someone out of camera view, or an unmarked no-show | **No** — those fares were already paid or logged |

It also adds a **caution** when:
- the camera saw 0 people but tickets exist → *lens blocked or aimed away*
- average confidence is below 0.60 → *count is approximate*

The reading is **computed every time it is displayed, never stored.** The
stored numbers are the audit trail; the wording can improve without
rewriting history.

### 3.5 Step 4 — A human closes it

A flagged audit sits in the console's **Passenger Count Checks** queue.
[`ResolveAuditUseCase`](../backend/app/application/audit/trigger_audit.py#L265)
lets office staff mark it `resolved` or `ignored` — **a note is required**,
and who closed it and when are recorded. The system raises the question; a
person answers it.

---

## 4. Inside `ai_service/app.py`, top to bottom

[ai_service/app.py](../ai_service/app.py) is a small Flask web service.
Its job is deliberately narrow:

> **capture a frame → count people → blur faces → report.**
> It knows nothing about trips, manifests or variance.

### 4.1 The full request flow

```
 Console / Conductor app
        │  POST /api/v1/audits/trigger
        ▼
 FastAPI backend ──────────────── POST /api/audit/capture ─────────────► AI node (app.py :5000)
   reads C_booked                                                           camera.capture()
                                                                            count_people()
                                                                            blur_faces() + draw_boxes()
   ◄───────────── { visual_count, confidence_avg, snapshot_b64, timings } ──┘
   computes variance, saves audit row
        │
        ▼
 audit result (with verdict) back to the screen
```

### 4.2 Section by section

| Lines | Section | What it does | Why it is built that way |
|---|---|---|---|
| [1-34](../ai_service/app.py#L1-L34) | Docstring | Draws the flow above | — |
| [49-58](../ai_service/app.py#L49-L58) | Imports from `inference.py` | Model, thresholds, count, blur, draw | The **evaluation harness** uses the same `count_people()`, so published accuracy numbers are the deployed system's numbers |
| [67-69](../ai_service/app.py#L67-L69) | Config | `CAMERA_INDEX`, `API_KEY`, `WARMUP_FRAMES = 5` | From environment variables — no hard-coded IPs |
| [82](../ai_service/app.py#L82) | `load_model()` | Loads YOLOv8 once at startup | Loading inside an audit would add seconds to it |
| [93-124](../ai_service/app.py#L93-L124) | `class Camera` | Keeps the webcam **open** behind a **lock** | Opening per request cost 1–3 s; two audits at once fought over `/dev/video0` |
| [106-107](../ai_service/app.py#L106-L107) | Warm-up | Reads 5 throwaway frames on open | Lets auto-exposure settle |
| [114-115](../ai_service/app.py#L114-L115) | Drain | Reads one stale frame, keeps the next | The buffered frame may be seconds old |
| [130-139](../ai_service/app.py#L130-L139) | `AuditResult` | The JSON shape returned | Count, confidence, model version, timings, snapshot |
| [142-146](../ai_service/app.py#L142-L146) | `require_api_key()` | Checks the `X-API-Key` header | Only the backend may trigger a capture |
| [155-183](../ai_service/app.py#L155-L183) | `_infer_and_package()` | Count → blur → draw → JPEG → base64 → JSON | **Shared** by both capture routes; one place for the error rules |
| [189-197](../ai_service/app.py#L189-L197) | `GET /health` | Reports model and camera settings | The console's node-health check |
| [201-220](../ai_service/app.py#L201-L220) | `POST /api/audit/capture` | Grabs a frame from the **server-attached camera** | POST, not GET — it activates hardware |
| [226-249](../ai_service/app.py#L226-L249) | `POST /api/audit/capture-upload` | Accepts a **photo uploaded from a phone** | Same model and rules; only the frame's origin differs |
| [252-261](../ai_service/app.py#L252-L261) | `__main__` | Runs on `0.0.0.0:5000`, `threaded=False` | One camera, one consumer — serialising requests is correct |

### 4.3 How it fails — and why that matters

| Situation | Response | Never returns |
|---|---|---|
| Camera will not open / gives no frame | **503** `camera_unavailable` | a count |
| Model crashes | **500** `inference_failed` | a count |
| JPEG encoding fails | **500** `encode_failed` | a count |
| Upload missing or not an image | **400** `no_image` / `decode_failed` | a count |
| Wrong API key | **401** `unauthorized` | — |

The backend turns any of these into **502** and writes **no audit row**.

> **Why so strict?** An earlier prototype returned `visual_count = 1` when
> the camera failed. A fake number *looks* real, and could flag an innocent
> driver. A missing audit is honest; an invented one is an accusation.

---

## 5. Algorithm 2 — NAHGM live tracking

**NAHGM = Node-Aligned Haversine Geofenced Monitoring.**
File: [backend/app/application/tracking/nahgm.py](../backend/app/application/tracking/nahgm.py)

It answers two questions from a stream of GPS pings:

1. **Where on the route is this van?** → *node-aligned map matching*
2. **When will it reach the stops ahead?** → *node-based ETA*

Each word of the name maps to a piece of code:

| Word | Means | Code |
|---|---|---|
| **Node-Aligned** | Position is expressed as "nearest terminal", not raw lat/lng | `_match_to_node()` |
| **Haversine** | Distance over the Earth's curved surface | `haversine_m()` |
| **Geofenced** | Each terminal has a radius; inside it = "at the terminal" | `_node_radius()`, `_leg_just_entered()` |
| **Monitoring** | Runs on every ping for the whole trip | `record_ping()`, `current_position()` |

> **Not machine learning.** Haversine and nearest-node selection are
> textbook. The claim is their *application* to fixed-route cooperative
> vans, not the mathematics ([nahgm.py:21-23](../backend/app/application/tracking/nahgm.py#L21-L23)).

### 5.1 The data flow

```
 In-van phone (POST /api/v1/edge/fixes) / simulator (POST .../tracking/trips/{id}/ping, dev only)
        │  {lat, lng, speed, heading, recorded_at}
        ▼
 record_ping()
   ├─ _match_to_node()      → nearest stop + distance
   ├─ INSERT trip_location_pings
   └─ _leg_just_entered()?  → if the van just left a terminal, schedule a gps_node audit (§6)

 Passenger app / Console
        │  GET /api/v1/tracking/trips/{id}/position   (every 10–15 s)
        ▼
 current_position()
   ├─ last 5 pings
   ├─ _estimate_speed()
   ├─ _compute_etas()       → ETA for each stop ahead
   └─ is_stale?             → older than 120 s = "last known position"
```

### 5.2 The Haversine formula

[`haversine_m()`](../backend/app/application/operations/check_in.py#L50)
— the straight-line distance between two points on a sphere:

```
a = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)
d = 2 · R · asin(√a)          R = 6,371,000 m (Earth's radius)

φ = latitude, λ = longitude, both in radians
```

It is the **same function** passenger check-in uses, so "is the passenger
at the terminal" and "is the van at the terminal" are measured identically.

### 5.3 Step 1 — Map matching: `_match_to_node()`

[nahgm.py:361-370](../backend/app/application/tracking/nahgm.py#L361-L370)

```
for every stop on the route:
    d = haversine(van, stop)
    keep the stop with the smallest d
return (that stop's sequence number, d)
```

Greedy nearest-node selection. It turns `(6.80, 125.40)` into
*"7.3 km from Digos, stop 2"*. Both values are stored on the ping row.

### 5.4 Step 2 — Speed: `_estimate_speed()`

[nahgm.py:373-402](../backend/app/application/tracking/nahgm.py#L373-L402)
— three tiers, best first:

| Tier | Source | Used when |
|---|---|---|
| 1 | **Average of reported speed** over the last 5 pings | Device sends speed and the average is ≥ 5 km/h |
| 2 | **Planned pace** = total route km ÷ total scheduled minutes | No usable reported speed |
| 3 | **40 km/h** | Route has no usable schedule (last resort) |

Tier 2 uses the cooperative's own timetable (`route_stops.offset_minutes`),
which is a better default than a guessed constant.

### 5.5 Step 3 — ETA: `_compute_etas()`

[nahgm.py:404-450](../backend/app/application/tracking/nahgm.py#L404-L450)

```
cursor = van's position;  total = 0
for each stop AFTER the nearest one:
    total += haversine(cursor, stop)      ← add one hop
    cursor = stop
    ETA = now + total ÷ speed
```

Distances **accumulate** hop by hop, terminal to terminal. If speed is
below 5 km/h the van is treated as stopped: distance is shown, **ETA is left
blank** rather than "arrives in 9 hours" from GPS jitter.

### 5.6 Worked example (seed route ECO-COT)

Route from `db/seed/001`, with real coordinates:

| Stop | Terminal | Lat, Lng | Radius | Scheduled at |
|---|---|---|---|---|
| 1 | Ecoland | 7.0524, 125.5931 | 200 m | +0 min |
| 2 | Digos | 6.7495, 125.3572 | 150 m | +90 min |
| 3 | Kidapawan | 7.0083, 125.0897 | 150 m | +195 min |
| 4 | Cotabato | 7.2217, 124.2467 | 150 m | +300 min |

**A ping arrives at (6.80, 125.40)**, no speed reported.

1. **Map match** — distance to every stop:
   Ecoland 35.2 km · **Digos 7.3 km** · Kidapawan 41.3 km · Cotabato 135.6 km
   → nearest is **stop 2, Digos**.
2. **Speed** — no reported speed, so tier 2:
   route length 42.6 + 41.2 + 96.0 = **179.8 km** over **300 min** → **36.0 km/h**.
   *(If the device had reported, say, 50 km/h, tier 1 would win.)*
3. **ETA** — only stops *after* stop 2, at 36 km/h:

   | Stop | Cumulative distance | Minutes away |
   |---|---|---|
   | 3 Kidapawan | 41.3 km *(van → Kidapawan)* | ~69 min |
   | 4 Cotabato | 41.3 + 96.0 = 137.3 km | ~229 min |

### 5.7 Staleness — honesty about old data

`tracking_stale_after_seconds` (policy, default **120 s**). A position older
than that is returned with `is_stale = true` and the map labels it *last
known position*. Reason, from the code: *a passenger would walk to a
terminal on the strength of a van that stopped reporting twenty minutes
ago.*

### 5.8 The NAHGM endpoints

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/edge/fixes` | The in-van phone (`X-Device-Token`) | Report a batch of positions |
| POST | `/tracking/trips/{id}/ping` | The simulator, **development only** (404 elsewhere) | Report one simulated position |
| GET | `/tracking/trips/{id}/position` | **Anyone** | Current position + ETAs |
| GET | `/tracking/trips/{id}/history` | Anyone | Breadcrumb trail for the map |
| GET | `/tracking/fleet` | Crew, office | Every van currently reporting |

Both endpoints end in the same `record_ping()`. In a van the phone sends
`/edge/fixes`; the ping endpoint exists only in development, for
`scripts/tracking_simulator.py`, because an unauthenticated position
could depart a trip or raise driving flags. The device's own
`recorded_at` wins, so readings buffered through a dead zone keep their
real times.

---

## 6. Where the two algorithms meet

The two layers are independent, **except at one point:** NAHGM tells
YOLOv8 *when* to look.

### 6.1 Why automatic triggers matter

If only the conductor can start an audit, the person being audited decides
when the audit happens — the weakest possible check. Two **system events**
fire captures with no one asking
([auto_trigger.py](../backend/app/application/audit/auto_trigger.py)):

| Trigger | Fired by | Leg audited | Why then |
|---|---|---|---|
| `door_close` | `DepartTripUseCase` — conductor closes boarding | **Leg 1** | No-shows released, everyone who boarded is aboard |
| `gps_node` | NAHGM `record_ping` — van leaves a terminal's geofence | **Leg *k*** after leaving stop *k* | Anyone who boarded at stop *k* is now riding leg *k* |

Both fire on **leaving** a stop, never arriving — an undocumented passenger
boards *at* a terminal, so the count is meaningful once the van pulls away.

### 6.2 How NAHGM detects "just left a terminal"

[`_leg_just_entered()`](../backend/app/application/tracking/nahgm.py#L292)
compares **two consecutive pings**:

```
previous ping:  inside stop k's geofence       (distance ≤ radius)
this ping:      NOT inside stop k's geofence   (moved away, or nearer another stop)
k is not the final stop
                ─────────────────────────────
                → the van just entered leg k  → schedule a gps_node audit
```

**Example at Digos (radius 150 m):**

| Ping | Nearest | Distance | Event? |
|---|---|---|---|
| 1 | Digos | 40 m | first ping — no |
| 2 | Digos | 90 m | still inside — no |
| 3 | Digos | 400 m | **left the fence → audit leg 2** |
| 4 | Digos | 900 m | already outside — no |

It is a *transition*, not a state — so a 10-second ping interval does not
fire ten audits a minute.

### 6.3 Three safety rules in `auto_trigger.py`

1. **One automatic audit per leg, counting automatic rows only.** A
   conductor's manual spot check cannot "use up" the leg and pre-empt the
   systematic check.
2. **Never block, never fail the real operation.** The capture runs as a
   detached background task. A departure never waits at the door for a
   camera; a GPS ping is never rejected because the camera is down.
3. **Nothing fabricated.** A failed capture writes **no row** — just a
   log line.

`triggered_by_user_id` is `NULL` for these: the record that no person asked.
The manual endpoint does **not** accept a `trigger_type` from the client —
otherwise the audited party could label its own check `gps_node`.

---

## 7. Rules the code refuses to break

| Rule | Where | Reason |
|---|---|---|
| The AI node never computes variance | `app.py` docstring | A client-side variance is forgeable by the person being audited |
| Never return an invented count | `app.py` `_infer_and_package`, `ai_node_client.py` | A fake number looks authoritative and accuses an innocent driver |
| `C_booked` read *before* the capture | `trigger_audit.py:143` | Both numbers describe the same moment |
| Variance alert + notifications in **one transaction** | `trigger_audit.py:194` | A flag without its alert is a silent failure |
| A failed snapshot save keeps the counts | `trigger_audit.py:258` | The numbers are the audit; the image is corroboration |
| Faces blurred before the image leaves the AI node | `inference.py:152` | RA 10173 — the image is evidence about a person |
| Stale positions are labelled stale | `nahgm.py:226` | An old position shown as current misleads a passenger |
| ETA blank when stopped | `nahgm.py:436` | Near-zero speed gives absurd arrival times |
| One geofence radius for check-in and tracking | `nahgm.py:310` | Same compound, same question; two radii would drift apart |

---

## 8. Questions the panel may ask

**"Did you train YOLOv8?"**
No. It is pretrained on COCO and unmodified. We measured *counting accuracy*
and *leakage-detection rates* on held-out COCO val2017 images — not training
curves, because no training happened.

**"Why is the threshold 0.45?"**
It trades false accusations against catches — 2.7 % false accusation, 77.5 %
of single hidden passengers caught. Where to sit on that curve is the
cooperative's call; it is one environment variable.

**"What if fewer people are seen than booked?"**
That is not lost revenue — those fares were paid. It is usually someone out
of frame. The system says so in words and does not treat it as theft.

**"What happens when the camera is down?"**
No audit is written. The backend returns 502 for manual checks and logs a
line for automatic ones. The departure or GPS ping still succeeds.

**"Is NAHGM AI?"**
No. It is geometry — Haversine distance plus nearest-node selection. The
contribution is applying it to node-based fixed routes so position becomes
"between Digos and Kidapawan" instead of a coordinate.

**"Why Haversine and not flat distance?"**
At Davao's latitude the flat error is small, but Haversine costs nothing
and removes a caveat you would otherwise have to defend.

**"Why are route lines straight, not on roads?"**
NAHGM measures straight hops node to node. A road-following line would
show a path the ETAs were never computed from.

**"What are NAHGM's known limits?"**
- Nearest-node matching does not know direction: a van approaching Digos
  and one just past it both match Digos, so the ETA list starts at the
  stop after it.
- ETAs use straight-line distance, so they run optimistic on winding roads
  unless the planned-pace fallback is in use.
- It needs a data connection; there is no live tracking through dead
  zones. The ping endpoint does accept the device's own `recorded_at`, so a
  unit that buffers and uploads later keeps the real times.

**"Why does `door_close` exist if there is no door sensor?"**
It is the conductor closing boarding and departing — the closest event the
system genuinely observes. There is no reed switch on the door; say it that
way.

---

## 9. Glossary

| Term | Meaning |
|---|---|
| **Route** | A fixed LTFRB path: an ordered list of terminals, stops 1..N |
| **Stop / node** | A terminal's *position* on a route |
| **Leg / section** | The stretch from stop *k* to stop *k+1*; N stops → N−1 legs |
| **Segment / journey** | One passenger's boarding → alighting pair |
| **Manifest** | The list of passengers aboard a leg (`C_booked`) |
| **C_visual** | People the camera counted |
| **C_booked** | People the manifest says are aboard that leg |
| **Variance (Δ)** | `C_visual − C_booked` |
| **Geofence** | A radius around a terminal (default 150 m) inside which a van or passenger counts as "at" it |
| **Haversine** | Formula for distance between two lat/lng points on a sphere |
| **Map matching** | Turning a raw coordinate into "nearest stop on the route" |
| **Stale** | A position older than 120 s |
| **IoU** | Intersection over Union — how much two boxes overlap |
| **Confidence threshold** | Minimum score for YOLOv8 to keep a detection (0.45) |
