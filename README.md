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

The system is three independently-run pieces: a MySQL database (Docker),
a FastAPI backend, and the Flutter clients (`mobile/`, `operator_console/`).
Start them in this order — each later piece depends on the one before it
being up. `./run.sh` does all three in one command. The in-van phone app
is `edge_app/` (native Kotlin, see its README). `ai_service/` is now only
the YOLOv8 evaluation harness (`ai_service/eval/README.md`); the rev 468
AI node and capture app were retired on 16 Oct.

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

### 2. Backend (`backend/`)

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

### 3. Passenger / Dispatcher app and the office console

```fish
cd mobile
flutter run -d 192.168.1.2:5555 --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
```

```fish
cd operator_console
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
```

Dev accounts (password `sabaygo123`): `passenger@sabaygo.dev`,
`dispatcher@sabaygo.dev`, `manager@sabaygo.dev` (Terminal Manager),
`cashier@sabaygo.dev`. The operator (van owner, who drives) has no account.

### 4. Backend test scripts

```fish
cd backend
./tests/integration/run_all_journeys.sh                        # full journey suite
python tests/integration/test_concurrency.py --requests 50     # booking race test
python scripts/tracking_simulator.py --trip TRIP-DEMO-00000001 --speed 30
./scripts/demo_rehearsal.sh                                     # Tier 1 demo loop, stops at first failure
```

### 5. Flutter static checks

```fish
cd mobile && flutter analyze          # or operator_console/
```
