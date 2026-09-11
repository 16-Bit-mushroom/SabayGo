# SabayGo

Capstone project: a booking and fleet-management system for terminal-based
UV Express vans in Davao City, with A2Z Transport Cooperative as pilot
partner. BSIT, University of Mindanao.

**Development deadline 27 September 2026. Final defence 20 October.**

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

| File | Why |
|---|---|
| `docs/RULES.md` | Business rules vs application rules, in plain language |
| `docs/HOW_IT_WORKS.md` | Same, written for the cooperative and the panel |
| `docs/REMAINING_WORK.md` | What is left, grouped |
| `docs/FLUTTER_PHASE1_ISSUES.md` | 20 documented setup failures and fixes |
| `backend/app/infrastructure/repositories/seat_repository.py` | The thesis. Read its docstring before touching it |

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
| `conductor` | Crew aboard. Scans, logs cash passengers, remits |
| `driver` | Same as conductor plus a licence record |
| `coop_admin` | Cooperative office staff. Web console only |
| `admin` | System administrator — the development team |

**Never call `coop_admin` "operator."** Under LTFRB usage an *operator* is
the franchise holder — the CPC holder, usually the van owner — which is a
different party from office staff. This was renamed deliberately in
migration 010.

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

# tests
cd backend && ./tests/integration/run_all_journeys.sh
python tests/integration/test_concurrency.py --requests 50
python scripts/tracking_simulator.py --trip TRIP-DEMO-00000001 --speed 30
```

Dev accounts: `passenger@` `conductor@` `driver@` `coopadmin@sabaygo.dev`,
password `sabaygo123`.

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
  passed, with a conductor-set fare. Anchoring forward would leave that
  stretch of road looking empty while someone sits in it, and the camera
  check would flag a real passenger as leakage.

Changing any of these is a schema migration, not a config change.

---

## State as of 10 September 2026

### Backend — complete

Schema (11 migrations) · JWT auth · segment booking with pessimistic
locking · PayMongo checkout and verified webhooks · cash remittance ·
geofenced check-in · QR boarding · manifest · driver headcount · YOLOv8
audit · revenue reconciliation · trip generation · fleet/crew/route/fare/
policy CRUD · scheduling conflict detection · NAHGM live tracking.

Journey suite: **90 passed, 2 failed** — both fixture self-conflict, not
defects.

Concurrency experiment: 50 simultaneous bookings, **0 double-bookings**,
advance cap respected. A controlled comparison is recorded — with the cap
checked *outside* the lock, 14 bookings passed a limit of 10.

### Mobile — Phase 1 and part of Phase 2

Done: `ApiClient` with typed exceptions · `flutter_secure_storage` for the
JWT · Provider · role-based routing from the server · conductor shell ·
registration · **trip search live against the API**.

Not done: ticket screen (pay, QR, check-in) · my-bookings · reschedule and
cancel · conductor scanning · walk-in and roadside logging · remittance ·
live map · chat.

### Operator console — untouched

Three Flutter Web modules on mock data.

---

## Next

1. **Ticket screen** — `startCheckout()` → open PayMongo URL · real QR
   from `qr_payload` via `qr_flutter` · check-in via `geolocator`. Status
   must come from the server, not the local `_isAtTerminal` bool.
2. **My bookings** — `GET /bookings/mine`, reschedule, cancel. Replaces
   the mocks in `reservations_viewmodel.dart`.
3. **Conductor** — scanning, walk-in and roadside, remittance.
4. **Operator console** — wire the three modules.
5. **Chat** — messages in MySQL, delivered via FCM. Not Firestore: the
   ERD would have a hole where the data model should be.

---

## Known issues

- `TimeoutException` in `api_exception.dart` collides with `dart:async`,
  so `ApiClient`'s catch matches the wrong type and the error reaches the
  UI unhandled. Rename the local class.
- Two journey-test failures are fixture self-conflict: `--soon` makes
  check-in testable and reschedule untestable at the same time.
- `reservations_viewmodel.dart` still holds mock bookings.
- Passenger avatar hits `i.pravatar.cc` on every build; fails offline.
- AGP 8.11.1 and Kotlin 2.2.20 are below what Flutter will soon require.
  Deferred deliberately.
- Dev-account chips on the sign-in screen are guarded by
  `AppConfig.isDebug`. Confirm they are absent from a release build.

---

## Open questions for the cooperative

Answerable in ten minutes by any dispatcher at Ecoland:

1. Do passengers GCash conductors directly? It behaves like cash, but the
   office counts a handover of banknotes differently from one partly in
   an e-wallet.
2. Cancellation deadline — useful, and how many hours?
3. Would knowing in advance who has arrived help dispatch? This decides
   whether check-in survives as more than advisory.
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
