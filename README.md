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
