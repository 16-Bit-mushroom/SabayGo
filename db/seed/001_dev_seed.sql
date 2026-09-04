-- =====================================================================
-- 001_dev_seed.sql   (DEVELOPMENT ONLY -- never load in production)
--
-- One real 4-stop Davao route so you have something to book against
-- today. Replace with the actual A2Z routes/fares after the pitch.
--
-- 4 stops => 3 legs => 14 seats x 3 legs = 42 seat_inventory rows/trip.
-- =====================================================================

SET @route      = 'ROUTE-ECO-COT-0001';
SET @t_ecoland  = 'TERM-ECOLAND-000001';
SET @t_digos    = 'TERM-DIGOS-00000001';
SET @t_kidapawan= 'TERM-KIDAPAWAN-0001';
SET @t_cotabato = 'TERM-COTABATO-00001';

-- --------------------------------------------------------------- terminals
INSERT INTO terminals
  (terminal_id, terminal_name, city, latitude, longitude, geofence_radius_m, is_staffed)
VALUES
  (@t_ecoland,   'Ecoland Terminal',       'Davao City',    7.052400, 125.593100, 200, TRUE),
  (@t_digos,     'Digos City Terminal',    'Digos City',    6.749500, 125.357200, 150, TRUE),
  (@t_kidapawan, 'Kidapawan City Terminal','Kidapawan City',7.008300, 125.089700, 150, FALSE),
  (@t_cotabato,  'Cotabato City Terminal', 'Cotabato City', 7.221700, 124.246700, 150, TRUE);

-- ------------------------------------------------------------------ route
INSERT INTO routes (route_id, route_code, route_name, is_active)
VALUES (@route, 'ECO-COT', 'Ecoland - Cotabato City', TRUE);

INSERT INTO route_stops (route_stop_id, route_id, terminal_id, stop_sequence, offset_minutes)
VALUES
  ('RS-ECO-COT-1', @route, @t_ecoland,   1,   0),
  ('RS-ECO-COT-2', @route, @t_digos,     2,  90),
  ('RS-ECO-COT-3', @route, @t_kidapawan, 3, 195),
  ('RS-ECO-COT-4', @route, @t_cotabato,  4, 300);

-- ------------------------------------------------------- pairwise fare matrix
-- Every boarding/alighting combination along the route (6 pairs for 4 stops).
INSERT INTO fare_matrix
  (fare_id, route_id, from_stop_sequence, to_stop_sequence, fare_amount, effective_from)
VALUES
  ('FM-1-2', @route, 1, 2, 180.00, '2026-01-01'),
  ('FM-1-3', @route, 1, 3, 340.00, '2026-01-01'),
  ('FM-1-4', @route, 1, 4, 500.00, '2026-01-01'),
  ('FM-2-3', @route, 2, 3, 170.00, '2026-01-01'),
  ('FM-2-4', @route, 2, 4, 330.00, '2026-01-01'),
  ('FM-3-4', @route, 3, 4, 175.00, '2026-01-01');

-- ------------------------------------------------------------------ users
-- password_hash below is a PLACEHOLDER. Generate real ones with:
--   python3 -c "import bcrypt;print(bcrypt.hashpw(b'sabaygo123',bcrypt.gensalt()).decode())"
SET @pw = '$2b$12$REPLACE_ME_WITH_A_REAL_BCRYPT_HASH_000000000000000000000';

INSERT INTO users (user_id, email, phone_number, password_hash, role) VALUES
  ('USER-COOPADMIN-0001',  'coopadmin@sabaygo.test',  '+639170000001', @pw, 'coop_admin'),
  ('USER-CONDUCTOR-0001', 'conductor@sabaygo.test', '+639170000002', @pw, 'conductor'),
  ('USER-DRIVER-0001',    'driver@sabaygo.test',    '+639170000003', @pw, 'driver'),
  ('USER-PASSENGER-0001', 'passenger@sabaygo.test', '+639170000004', @pw, 'passenger');

INSERT INTO staff_profiles (user_id, first_name, last_name, cooperative_name, assigned_terminal_id) VALUES
  ('USER-COOPADMIN-0001',  'Maria',  'Santos',     'A2Z Transport Cooperative', @t_ecoland),
  ('USER-CONDUCTOR-0001', 'Ramon',  'Villanueva', 'A2Z Transport Cooperative', @t_ecoland),
  ('USER-DRIVER-0001',    'Juan',   'Dela Cruz',  'A2Z Transport Cooperative', @t_ecoland);

INSERT INTO driver_credentials (user_id, license_number, license_expiry_date, cttmo_id_number)
VALUES ('USER-DRIVER-0001', 'N01-23-456789', '2028-06-30', 'CTTMO-DVO-4471');

INSERT INTO passenger_profiles (user_id, first_name, last_name, home_address, gender)
VALUES ('USER-PASSENGER-0001', 'Sarah', 'Kalaw', 'Matina Crossing, Davao City', 'female');

INSERT INTO passenger_settings (user_id) VALUES ('USER-PASSENGER-0001');

-- ------------------------------------------------------------------- van
INSERT INTO vans
  (van_id, plate_number, brand, model, color, seat_capacity,
   operational_status, registered_route_id, has_cabin_camera, camera_device_id)
VALUES
  ('VAN-0001', 'ABC-1234', 'Toyota', 'HiAce Commuter', 'White', 14,
   'active', @route, TRUE, 'EDGE-PI-0001'),
  ('VAN-0002', 'XYZ-9876', 'Nissan', 'NV350 Urvan',    'Silver', 14,
   'active', @route, FALSE, NULL);

-- -------------------------------------------------------- schedule template
INSERT INTO schedule_templates
  (template_id, route_id, departure_time, days_of_week,
   default_van_id, default_driver_id, default_conductor_id,
   trip_label, valid_from)
VALUES
  ('TMPL-ECO-COT-0530', @route, '05:30:00', '1111111',
   'VAN-0001', 'USER-DRIVER-0001', 'USER-CONDUCTOR-0001', 'First Trip', '2026-01-01'),
  ('TMPL-ECO-COT-0730', @route, '07:30:00', '1111100',
   'VAN-0002', 'USER-DRIVER-0001', NULL, 'Second Trip', '2026-01-01');

-- ------------------------------------------------- one materialized trip
-- In production the nightly generator creates these. Seeded here so you
-- have something to hammer with the Week 2 concurrency test today.
INSERT INTO trips
  (trip_id, template_id, route_id, service_date, departure_datetime,
   van_id, driver_id, conductor_id, trip_label,
   seat_capacity, advance_booking_seat_cap, reschedule_cutoff_hours, status)
VALUES
  ('TRIP-DEMO-00000001', 'TMPL-ECO-COT-0530', @route,
   CURRENT_DATE, CONCAT(CURRENT_DATE, ' 05:30:00'),
   'VAN-0001', 'USER-DRIVER-0001', 'USER-CONDUCTOR-0001', 'First Trip',
   14, 10, 6, 'scheduled');

-- trip_legs: derived from the route's stop sequence (4 stops -> 3 legs)
INSERT INTO trip_legs (trip_id, leg_sequence, from_stop_sequence, to_stop_sequence, departs_at)
SELECT 'TRIP-DEMO-00000001', rs.stop_sequence, rs.stop_sequence, rs.stop_sequence + 1,
       CONCAT(CURRENT_DATE, ' 05:30:00') + INTERVAL rs.offset_minutes MINUTE
FROM route_stops rs
WHERE rs.route_id = @route
  AND rs.stop_sequence < (SELECT MAX(stop_sequence) FROM route_stops WHERE route_id = @route);

-- seat_inventory: 14 seats x every leg. This cross join is exactly what
-- your trip generator will run for each new trip.
INSERT INTO seat_inventory (trip_id, seat_number, leg_sequence)
WITH RECURSIVE seats AS (
    SELECT 1 AS seat_number
    UNION ALL
    SELECT seat_number + 1 FROM seats WHERE seat_number < 14
)
SELECT l.trip_id, s.seat_number, l.leg_sequence
FROM trip_legs l
CROSS JOIN seats s
WHERE l.trip_id = 'TRIP-DEMO-00000001';

-- ------------------------------------------------- a second trip
-- Needed so reschedule has a target: a booking can only move to another
-- trip on the same route, and with one seeded trip there is nowhere to
-- move it to. Uses the 07:30 template and the second van, which also
-- keeps the van/driver overlap check from firing.
INSERT INTO trips
  (trip_id, template_id, route_id, service_date, departure_datetime,
   van_id, driver_id, conductor_id, trip_label,
   seat_capacity, advance_booking_seat_cap, reschedule_cutoff_hours, status)
VALUES
  ('TRIP-DEMO-00000002', 'TMPL-ECO-COT-0730', @route,
   CURRENT_DATE, CONCAT(CURRENT_DATE, ' 07:30:00'),
   'VAN-0002', 'USER-DRIVER-0001', 'USER-CONDUCTOR-0001', 'Second Trip',
   14, 14, 6, 'scheduled');

INSERT INTO trip_legs (trip_id, leg_sequence, from_stop_sequence, to_stop_sequence, departs_at)
SELECT 'TRIP-DEMO-00000002', rs.stop_sequence, rs.stop_sequence, rs.stop_sequence + 1,
       CONCAT(CURRENT_DATE, ' 07:30:00') + INTERVAL rs.offset_minutes MINUTE
FROM route_stops rs
WHERE rs.route_id = @route
  AND rs.stop_sequence < (SELECT MAX(stop_sequence) FROM route_stops WHERE route_id = @route);

INSERT INTO seat_inventory (trip_id, seat_number, leg_sequence)
WITH RECURSIVE seats AS (
    SELECT 1 AS seat_number
    UNION ALL
    SELECT seat_number + 1 FROM seats WHERE seat_number < 14
)
SELECT l.trip_id, s.seat_number, l.leg_sequence
FROM trip_legs l
CROSS JOIN seats s
WHERE l.trip_id = 'TRIP-DEMO-00000002';

-- Expect 84 rows across both trips.
SELECT CONCAT('seat_inventory rows seeded: ', COUNT(*)) AS result
FROM seat_inventory;