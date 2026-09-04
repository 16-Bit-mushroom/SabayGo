Architecture — three layers
Screen  →  ViewModel  →  Repository  →  ApiClient  →  FastAPI

ApiClient — base URL from config, attaches the bearer token, maps HTTP status to typed exceptions. One place that knows about HTTP.

Repository — one per domain (BookingRepository, TripRepository). Returns typed models, never raw JSON.

ViewModel — already exists. Just swap the mock list for a repository call and add isLoading / error state.

Your archived v1 prototype had exactly this shape — i_booking_repository.dart plus an implementation. Right pattern, wrong backing store.

The part people underestimate

Every screen currently renders instantly because the data is a local variable. With a real API each one needs four states: loading, loaded, empty, error. That's the bulk of the 13 days, not the API calls themselves.

Sequencing

Phase 1 (1–2 days) — foundation. Packages, ApiClient, AuthRepository, secure token storage, login wired end to end. Nothing else until login works against your FastAPI.

Phase 2 (4–5 days) — passenger. Register → search → book → pay → e-ticket → check-in → my bookings → reschedule/cancel.

Phase 3 (3 days) — conductor. QR scan, manifest, walk-in and roadside logging, remittance.

Phase 4 (3 days) — operator console. Fleet, crew, schedules, policy editor, audit queue, revenue.

Passenger first because alpha testers touch it first, and if anything gets cut you'd rather lose operator-console polish — that one you can demo from a seeded database.