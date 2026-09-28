# SabayGo 🚗🌱

SabayGo is a modern, dual-role carpooling and ride-sharing application built with Flutter. Designed to make urban transit more eco-friendly and community-driven, the platform seamlessly connects daily commuters with drivers heading the same way. It features an integrated gamification system to reward users for reducing their carbon footprint.

## 🌟 Key Features

### 🛣️ Dual-Role Architecture
* **Single App, Two Experiences:** Users can seamlessly toggle between "Commuter" and "Driver" modes from the unified login screen.
* **Role-Based Dashboards:** Dedicated UIs and state management for passengers seeking rides and drivers managing their routes.

### 💬 Unified Communications Engine
* **Real-time Chat:** A fully featured in-app messaging system supporting read receipts, editing, and unsending messages.
* **Dynamic Role Tagging:** Messages dynamically display user roles (e.g., "SabayGo · Support", "Sarah K. · Passenger").
* **Secure VoIP Simulation:** Built-in UI for secure, masked voice calls between drivers and commuters.

### 🗺️ Driver State Machine & Navigation
* **Interactive HUD:** A step-by-step state machine guiding drivers through the trip lifecycle (Heading to Pickup ➔ Arrived ➔ In Ride ➔ Completed).
* **Smart Bottom Sheets:** Context-aware slide-up menus for managing co-passengers, accepting payments, and initiating communication.
* **Trip Summaries:** Post-ride breakdowns showing fare collection and CO₂ offset metrics.

### 🏆 Gamification & Eco-Tracking
* **Hero Association Leaderboard:** A gamified system rewarding users for urban service and consistent carpooling.
* **Eco-Receipts:** Commuters and Drivers can see the exact amount of CO₂ saved compared to taking a solo trip.

---

## 🛠️ Tech Stack & Architecture

* **Framework:** Flutter (Dart) for UI, FastAPI for backend.
* **Architecture:** Feature-First / Clean Architecture / Domain Driven Design
* **State Management:** Provider
* **Local Storage:** SQLite(temporary), MySQL(production)
* **UI/UX:** Custom minimalist design system with high-contrast aesthetics and fluid modal animations.

---

## 📂 Project Structure

The codebase is organized using a feature-first approach to maintain modularity and scalability:

```text
lib/
 ├── core/                 # App-wide themes, constants, and shared widgets
 ├── features/
 │    ├── booking/         # Matchmaking, location search, and ride selection
 │    ├── communications/  # Unified chat engine, VoIP dialogues, and inbox
 │    ├── dashboard/       # Commuter and Driver main hub screens
 │    ├── identity/        # Auth, Role Selection, and User Profiles
 │    └── trip/            # Live map state, navigation steps, and trip history
 └── main.dart             # App entry point
```

---

## Running and testing the system

The system is four independently-run pieces: a MySQL database (Docker), a
FastAPI backend, a Flask/YOLOv8 AI node, and one or more Flutter clients
(`mobile/`, `operator_console/`, `ai_capture_app/`). Start them in this
order — each later piece depends on the one before it being up.

The dev shell is **fish**. `set VAR (cmd)` not `VAR=$(cmd)`; wrap heredocs
in `bash -c '...'`.

### 1. Database

```fish
cd SabayGo_VS
docker compose up -d                # starts sabaygo-mysql + adminer
./db/reset-dev.sh                   # clean state, demo trip departs tomorrow 05:30
# or, to make check-in testable right away:
./db/reset-dev.sh --soon            # demo trip departs in ~20 min
```

Adminer (DB browser) is on the port `docker-compose.yml` publishes it on;
MySQL itself is host port 3307.

### 2. AI node (`ai_service/`)

```fish
cd ai_service
source venv/bin/activate.fish
export (grep -v '^#' .env | xargs -L1)   # loads AI_NODE_API_KEY
python app.py                             # listens on 0.0.0.0:5000
```

Sanity check it came up:

```fish
curl http://127.0.0.1:5000/health
```

### 3. Backend (`backend/`)

```fish
cd backend
source venv/bin/activate.fish
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Bind to `0.0.0.0`, not `localhost` — otherwise a phone on the same LAN
cannot reach it. Sanity check:

```fish
curl -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/docs
```

### 4. Testing the AI capture path

**Without a phone** — hit the AI node's upload endpoint directly with any
JPEG:

```fish
curl -X POST http://127.0.0.1:5000/api/audit/capture-upload \
  -H "X-API-Key: (grep AI_NODE_API_KEY ai_service/.env | cut -d= -f2)" \
  -F "image=@/path/to/some.jpg"
```

A healthy response is JSON with `visual_count`, `confidence_avg`,
`model_version`, timings, and a base64 `snapshot_b64`. A wrong or missing
`X-API-Key` returns 401; a missing/undecodable file returns 400. The node
never invents a count — a failure is always an error response, never a
placeholder number.

**With a phone** (`ai_capture_app/` — a proof of concept standing in for
the Orange Pi until that hardware is in hand):

```fish
adb connect 192.168.1.2:5555        # wireless adb, once the phone is paired
cd ai_capture_app
flutter run -d 192.168.1.2:5555 \
  --dart-define=AI_NODE_URL=http://192.168.1.8:5000 \
  --dart-define=AI_NODE_API_KEY=(grep AI_NODE_API_KEY ../ai_service/.env | cut -d= -f2) \
  --dart-define=BACKEND_URL=http://192.168.1.8:8000/api/v1 \
  --dart-define=PHONE_DEVICE_KEY=(grep PHONE_CAPTURE_API_KEY ../backend/.env | cut -d= -f2)
```

Replace `192.168.1.2:5555` with the phone's adb address and
`192.168.1.8` with the server PC's LAN IP (`ip -4 addr` on the machine
running `ai_service`/`backend`). The app has two independent capture
modes:

- **Direct** — tap **Take photo & send to AI node**. Goes straight to the
  AI node, proves the camera + inference pipeline works, but bypasses the
  backend entirely: no trip, no variance, nothing written to
  `yolov8_audit_logs`.
- **Dispatched** — mimics how the Orange Pi will be triggered (backend
  decides *when* to capture; only the shutter press stays manual). Toggle
  **Listen for a dispatch trigger** on the phone (polls the backend every
  5s), then ask for a capture from the operator console's **Audits**
  screen → **Trigger phone capture** — pick a trip in `boarding` or
  `departed` status, set the leg, submit. Or the same call directly:

  ```fish
  set TOKEN (curl -s -X POST http://127.0.0.1:8000/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}' \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
  curl -X POST http://127.0.0.1:8000/api/v1/audits/trigger-phone \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"trip_id":"TRIP-DEMO-00000001","leg_sequence":1}'
  ```

  The phone opens its camera automatically once it sees the pending
  request — no extra tap to reveal it, just the shutter. The upload goes
  through the backend instead of the AI node directly, so it reconciles
  against the manifest, writes a real `yolov8_audit_logs` row, and
  reappears in the console's Audit Queue/History a few seconds later.

### 5. Passenger / conductor / driver app and the coop console

```fish
cd mobile
flutter run -d 192.168.1.2:5555 --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
```

```fish
cd operator_console
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
```

Dev accounts (password `sabaygo123`): `passenger@sabaygo.dev`,
`conductor@sabaygo.dev`, `driver@sabaygo.dev`, `coopadmin@sabaygo.dev`.

### 6. Backend test scripts

```fish
cd backend
./tests/integration/run_all_journeys.sh                        # full journey suite
python tests/integration/test_concurrency.py --requests 50     # booking race test
python scripts/tracking_simulator.py --trip TRIP-DEMO-00000001 --speed 30
./scripts/demo_rehearsal.sh                                     # Tier 1 demo loop, stops at first failure
```

### 7. Flutter static checks

```fish
cd mobile && flutter analyze          # or operator_console/, ai_capture_app/
```
