# SabayGo — Database

MySQL 8.0 (InnoDB) running in Docker. Host port **3307** to avoid colliding
with any locally installed MariaDB.

## Quick start

```bash
cp .env.example .env      # then edit the passwords
docker compose up -d
chmod +x db/apply.sh
./db/apply.sh --seed
```

Adminer GUI: <http://127.0.0.1:8080> (server `mysql`, user `sabaygo_app`).

Rebuild from scratch: `./db/apply.sh --reset --seed`

## Migration order

| File | Contents |
|---|---|
| `001_core_reference` | policy config, terminals, routes, route_stops, fare_matrix |
| `002_identity` | users, passenger/staff profiles, driver credentials, settings |
| `003_fleet` | vans, van_photos |
| `004_scheduling` | schedule_templates, trips, trip_legs, **seat_inventory** |
| `005_transactions` | bookings, payments, check_ins, boarding_scans |
| `006_audit_and_alerts` | yolov8_audit_logs, ticket booklets, headcounts, notifications |

## Six decisions worth knowing before you redraw the ERD

**1. Naming is `snake_case`.** MySQL on Linux is case-sensitive for table
names by default, so PascalCase invites bugs that never reproduce on
Windows. Update the Data Dictionary to match — consistency between docs
and schema is graded.

**2. Undecided policy lives in rows, not columns.** `cooperative_policies`
holds reschedule cutoff, advance-booking cap, geofence radius, and the
rest. When A2Z answers at the pitch you run `UPDATE`, not a migration.
This is what stops the pitch from blocking development.

**3. One `users` table.** The old schema had credentials on Passengers and
TerminalStaff but none on Drivers or Conductors — yet both must log in to
do their jobs. Identity is now unified; role-specific fields live in
`passenger_profiles`, `staff_profiles`, `driver_credentials`.

**4. Templates and trips are different things.** `schedule_templates` is
the recurring pattern; `trips` are dated instances a nightly job creates
from it. `UNIQUE (template_id, service_date)` makes that job safely
re-runnable. Special trips are rows with `template_id IS NULL` and
`is_special_trip = TRUE`.

**5. `seat_inventory` is one row per (trip, seat, leg).** This is what
makes segment booking and pessimistic locking expressible. The unique key
`(trip_id, seat_number, leg_sequence)` is a hard backstop: even with buggy
application code the database physically cannot double-seat a passenger.
The allocation query is documented in `004_scheduling.sql`.

**6. Policy values are snapshotted onto each trip.** `seat_capacity`,
`advance_booking_seat_cap`, and `reschedule_cutoff_hours` are copied at
generation time so a later policy change never retroactively alters terms
on already-sold seats.

## Deliberately out of scope

Per the consultation, fleet management is **monitoring only** — there is no
maintenance scheduling, service history, or cost tracking. `operational_status`
on `vans` is a flag, not a module. State this explicitly in Scope and
Limitations.

## Still open — bring to the pitch

Every one of these is a row in `cooperative_policies`, so answering them
costs an `UPDATE` and nothing more.

- `reschedule_cutoff_hours` — currently 6
- `max_reschedules_per_booking` — currently 1
- `advance_booking_seat_cap` — currently 10 of 14
- `advance_booking_open_days` — currently 7
- `checkin_window_minutes` — currently 45
- Do A2Z vans **already** have cabin cameras? (`vans.has_cabin_camera`)
- Which routes are in the pilot? Who authorizes special trips?
