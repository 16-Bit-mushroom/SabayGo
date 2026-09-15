-- =====================================================================
-- 002_demo_dataset.sql   (DEVELOPMENT / DEMO ONLY)
--
-- A realistic multi-route picture of a Davao UV Express cooperative, on
-- top of the 001 fixture the journey suite depends on. 001 is left
-- untouched: the tests pin TRIP-DEMO-00000001/2 and the four dev users.
--
-- Routes, terminals, fares and crew here are PLACEHOLDERS shaped like the
-- Davao region network; replace them with A2Z's own once they answer.
-- Fares are in the range LTFRB has approved for these corridors but are
-- not the official matrix.
--
-- What this gives the demo that 001 does not:
--   * three more routes, so a terminal (Ecoland) is stop 1 on several and
--     the terminal picker / search has to resolve routes properly
--   * departures today and for the next two days on every route
--   * two days of COMPLETED trips with app bookings, walk-ins, a roadside
--     pickup, a no-show, a cancellation, remittances in every state and
--     YOLOv8 audits in every state -- so Revenue, the audit History view
--     and the spreadsheet export are not empty on stage
--
-- Trip ids here are TRIP-A2Z-*; reset-dev.sh only re-dates TRIP-DEMO-*.
-- =====================================================================

SET @t_ecoland  = 'TERM-ECOLAND-000001';
SET @t_digos    = 'TERM-DIGOS-00000001';
SET @t_panabo   = 'TERM-PANABO-00000001';
SET @t_carmen   = 'TERM-CARMEN-00000001';
SET @t_tagum    = 'TERM-TAGUM-000000001';
SET @t_stacruz  = 'TERM-STACRUZ-0000001';
SET @t_lupon    = 'TERM-LUPON-000000001';
SET @t_mati     = 'TERM-MATI-0000000001';

SET @r_tag = 'ROUTE-ECO-TAG-0001';
SET @r_dig = 'ROUTE-ECO-DIG-0001';
SET @r_mat = 'ROUTE-ECO-MAT-0001';

SET @coop = 'A2Z Transport Cooperative';
-- Placeholder hash; reset-dev.sh sets the real one for every @sabaygo.dev
SET @pw = '$2b$12$REPLACE_ME_WITH_A_REAL_BCRYPT_HASH_000000000000000000000';

-- --------------------------------------------------------------- terminals
INSERT INTO terminals
  (terminal_id, terminal_name, city, latitude, longitude, geofence_radius_m, is_staffed)
VALUES
  (@t_panabo,  'Panabo City Terminal',          'Panabo City', 7.308000, 125.684000, 150, TRUE),
  (@t_carmen,  'Carmen Terminal',               'Carmen',      7.362000, 125.706000, 120, FALSE),
  (@t_tagum,   'Tagum City Overland Terminal',  'Tagum City',  7.447800, 125.807800, 200, TRUE),
  (@t_stacruz, 'Sta. Cruz Terminal',            'Sta. Cruz',   6.832200, 125.414200, 120, FALSE),
  (@t_lupon,   'Lupon Terminal',                'Lupon',       6.897800, 126.010600, 120, FALSE),
  (@t_mati,    'Mati City Terminal',            'Mati City',   6.955000, 126.216600, 150, TRUE);

-- ------------------------------------------------------------------ routes
INSERT INTO routes (route_id, route_code, route_name, is_active) VALUES
  (@r_tag, 'ECO-TAG', 'Ecoland - Tagum City', TRUE),
  (@r_dig, 'ECO-DIG', 'Ecoland - Digos City', TRUE),
  (@r_mat, 'ECO-MAT', 'Ecoland - Mati City',  TRUE);

INSERT INTO route_stops (route_stop_id, route_id, terminal_id, stop_sequence, offset_minutes) VALUES
  ('RS-ECO-TAG-1', @r_tag, @t_ecoland, 1,   0),
  ('RS-ECO-TAG-2', @r_tag, @t_panabo,  2,  45),
  ('RS-ECO-TAG-3', @r_tag, @t_carmen,  3,  60),
  ('RS-ECO-TAG-4', @r_tag, @t_tagum,   4,  90),
  ('RS-ECO-DIG-1', @r_dig, @t_ecoland, 1,   0),
  ('RS-ECO-DIG-2', @r_dig, @t_stacruz, 2,  50),
  ('RS-ECO-DIG-3', @r_dig, @t_digos,   3,  80),
  ('RS-ECO-MAT-1', @r_mat, @t_ecoland, 1,   0),
  ('RS-ECO-MAT-2', @r_mat, @t_lupon,   2, 150),
  ('RS-ECO-MAT-3', @r_mat, @t_mati,    3, 210);

INSERT INTO fare_matrix
  (fare_id, route_id, from_stop_sequence, to_stop_sequence, fare_amount, effective_from)
VALUES
  ('FM-TAG-1-2', @r_tag, 1, 2,  60.00, '2026-01-01'),
  ('FM-TAG-1-3', @r_tag, 1, 3,  75.00, '2026-01-01'),
  ('FM-TAG-1-4', @r_tag, 1, 4, 100.00, '2026-01-01'),
  ('FM-TAG-2-3', @r_tag, 2, 3,  20.00, '2026-01-01'),
  ('FM-TAG-2-4', @r_tag, 2, 4,  45.00, '2026-01-01'),
  ('FM-TAG-3-4', @r_tag, 3, 4,  30.00, '2026-01-01'),
  ('FM-DIG-1-2', @r_dig, 1, 2,  70.00, '2026-01-01'),
  ('FM-DIG-1-3', @r_dig, 1, 3, 110.00, '2026-01-01'),
  ('FM-DIG-2-3', @r_dig, 2, 3,  45.00, '2026-01-01'),
  ('FM-MAT-1-2', @r_mat, 1, 2, 180.00, '2026-01-01'),
  ('FM-MAT-1-3', @r_mat, 1, 3, 250.00, '2026-01-01'),
  ('FM-MAT-2-3', @r_mat, 2, 3,  80.00, '2026-01-01');

-- ------------------------------------------------------------------- crew
INSERT INTO users (user_id, email, phone_number, password_hash, role) VALUES
  ('USER-DRIVER-0002',    'driver2@sabaygo.dev',    '+639170000012', @pw, 'driver'),
  ('USER-DRIVER-0003',    'driver3@sabaygo.dev',    '+639170000013', @pw, 'driver'),
  ('USER-DRIVER-0004',    'driver4@sabaygo.dev',    '+639170000014', @pw, 'driver'),
  ('USER-DRIVER-0005',    'driver5@sabaygo.dev',    '+639170000015', @pw, 'driver'),
  ('USER-CONDUCTOR-0002', 'conductor2@sabaygo.dev', '+639170000022', @pw, 'conductor'),
  ('USER-CONDUCTOR-0003', 'conductor3@sabaygo.dev', '+639170000023', @pw, 'conductor'),
  ('USER-CONDUCTOR-0004', 'conductor4@sabaygo.dev', '+639170000024', @pw, 'conductor'),
  ('USER-CONDUCTOR-0005', 'conductor5@sabaygo.dev', '+639170000025', @pw, 'conductor');

INSERT INTO staff_profiles (user_id, first_name, last_name, cooperative_name, assigned_terminal_id) VALUES
  ('USER-DRIVER-0002',    'Rodel',  'Bacalso',  @coop, @t_ecoland),
  ('USER-DRIVER-0003',    'Nestor', 'Abellana', @coop, @t_ecoland),
  ('USER-DRIVER-0004',    'Ariel',  'Magbanua', @coop, @t_ecoland),
  ('USER-DRIVER-0005',    'Dodong', 'Cabrera',  @coop, @t_ecoland),
  ('USER-CONDUCTOR-0002', 'Jomar',  'Pelayo',   @coop, @t_ecoland),
  ('USER-CONDUCTOR-0003', 'Ricky',  'Tanudra',  @coop, @t_ecoland),
  ('USER-CONDUCTOR-0004', 'Bong',   'Sumagang', @coop, @t_ecoland),
  ('USER-CONDUCTOR-0005', 'Ely',    'Dagohoy',  @coop, @t_ecoland);

-- Magbanua's licence runs out in three weeks -- the E.2 talking point.
INSERT INTO driver_credentials (user_id, license_number, license_expiry_date, cttmo_id_number) VALUES
  ('USER-DRIVER-0002', 'N02-19-338120', '2027-11-15', 'CTTMO-DVO-5102'),
  ('USER-DRIVER-0003', 'N02-17-902271', '2028-02-28', 'CTTMO-DVO-4890'),
  ('USER-DRIVER-0004', 'N02-21-114455', CURRENT_DATE + INTERVAL 21 DAY, 'CTTMO-DVO-5377'),
  ('USER-DRIVER-0005', 'N02-20-667301', '2027-08-09', 'CTTMO-DVO-5210');

-- ------------------------------------------------------------- passengers
INSERT INTO users (user_id, email, phone_number, password_hash, role) VALUES
  ('USER-PAX-DEMO-0001', 'liza@sabaygo.dev',  '+639170000101', @pw, 'passenger'),
  ('USER-PAX-DEMO-0002', 'carlo@sabaygo.dev', '+639170000102', @pw, 'passenger'),
  ('USER-PAX-DEMO-0003', 'ana@sabaygo.dev',   '+639170000103', @pw, 'passenger'),
  ('USER-PAX-DEMO-0004', 'mark@sabaygo.dev',  '+639170000104', @pw, 'passenger'),
  ('USER-PAX-DEMO-0005', 'jenny@sabaygo.dev', '+639170000105', @pw, 'passenger'),
  ('USER-PAX-DEMO-0006', 'paolo@sabaygo.dev', '+639170000106', @pw, 'passenger');

INSERT INTO passenger_profiles (user_id, first_name, last_name, home_address, gender) VALUES
  ('USER-PAX-DEMO-0001', 'Liza',  'Mendoza',  'Buhangin, Davao City',        'female'),
  ('USER-PAX-DEMO-0002', 'Carlo', 'Reyes',    'Toril, Davao City',           'male'),
  ('USER-PAX-DEMO-0003', 'Ana',   'Bautista', 'Panabo City',                 'female'),
  ('USER-PAX-DEMO-0004', 'Mark',  'Villegas', 'Bangkal, Davao City',         'male'),
  ('USER-PAX-DEMO-0005', 'Jenny', 'Ocampo',   'Sta. Cruz, Davao del Sur',    'female'),
  ('USER-PAX-DEMO-0006', 'Paolo', 'Garcia',   'Agdao, Davao City',           'male');
INSERT INTO passenger_settings (user_id)
SELECT user_id FROM users WHERE user_id LIKE 'USER-PAX-DEMO-%';

-- ------------------------------------------------------------------- vans
INSERT INTO vans
  (van_id, plate_number, brand, model, color, seat_capacity,
   operational_status, registered_route_id, has_cabin_camera, camera_device_id)
VALUES
  ('VAN-0003', 'LAB-4521', 'Toyota', 'HiAce GL Grandia',  'White',  14, 'active', @r_tag, TRUE,  'EDGE-PI-0002'),
  ('VAN-0004', 'NBC-7788', 'Nissan', 'NV350 Urvan',       'Grey',   14, 'active', @r_tag, FALSE, NULL),
  ('VAN-0005', 'MDK-3310', 'Toyota', 'HiAce Commuter',    'Silver', 14, 'active', @r_dig, TRUE,  'EDGE-PI-0003'),
  ('VAN-0006', 'LCT-9042', 'Foton',  'View Traveller',    'White',  14, 'active', @r_mat, FALSE, NULL),
  ('VAN-0007', 'GAK-2205', 'Toyota', 'HiAce Commuter',    'White',  14, 'maintenance', @r_tag, FALSE, NULL);

-- ------------------------------------------------------- schedule templates
INSERT INTO schedule_templates
  (template_id, route_id, departure_time, days_of_week,
   default_van_id, default_driver_id, default_conductor_id, trip_label, valid_from)
VALUES
  ('TMPL-ECO-TAG-0600', @r_tag, '06:00:00', '1111111', 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', '2026-01-01'),
  ('TMPL-ECO-TAG-0900', @r_tag, '09:00:00', '1111111', 'VAN-0004', 'USER-DRIVER-0005', 'USER-CONDUCTOR-0005', 'Mid-morning',     '2026-01-01'),
  ('TMPL-ECO-TAG-1400', @r_tag, '14:00:00', '1111100', 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Afternoon',       '2026-01-01'),
  ('TMPL-ECO-DIG-0630', @r_dig, '06:30:00', '1111111', 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      '2026-01-01'),
  ('TMPL-ECO-DIG-1230', @r_dig, '12:30:00', '1111111', 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'Noon Trip',       '2026-01-01'),
  ('TMPL-ECO-MAT-0700', @r_mat, '07:00:00', '1111111', 'VAN-0006', 'USER-DRIVER-0003', 'USER-CONDUCTOR-0003', 'Daily Mati',      '2026-01-01');

-- ===================================================== helper procedures
-- Materialise a trip the way the nightly generator does: trip row, one
-- trip_legs row per leg, 14 seats x every leg in seat_inventory.
DROP PROCEDURE IF EXISTS seed_trip;
DROP PROCEDURE IF EXISTS seed_booking;
DELIMITER $$
CREATE PROCEDURE seed_trip(
  IN p_trip_id  CHAR(36),  IN p_tmpl CHAR(36),  IN p_route CHAR(36),
  IN p_departs  DATETIME,  IN p_van  CHAR(36),  IN p_driver CHAR(36),
  IN p_conductor CHAR(36), IN p_label VARCHAR(64), IN p_status VARCHAR(16))
BEGIN
  DECLARE v_last_offset INT;
  SELECT MAX(offset_minutes) INTO v_last_offset FROM route_stops WHERE route_id = p_route;

  INSERT INTO trips
    (trip_id, template_id, route_id, service_date, departure_datetime,
     van_id, driver_id, conductor_id, trip_label,
     seat_capacity, advance_booking_seat_cap, reschedule_cutoff_hours, status,
     departed_at, completed_at)
  VALUES
    (p_trip_id, p_tmpl, p_route, DATE(p_departs), p_departs,
     p_van, p_driver, p_conductor, p_label, 14, 10, 6, p_status,
     IF(p_status IN ('departed','completed'), p_departs + INTERVAL 4 MINUTE, NULL),
     IF(p_status = 'completed', p_departs + INTERVAL (v_last_offset + 12) MINUTE, NULL));

  INSERT INTO trip_legs (trip_id, leg_sequence, from_stop_sequence, to_stop_sequence, departs_at)
  SELECT p_trip_id, rs.stop_sequence, rs.stop_sequence, rs.stop_sequence + 1,
         p_departs + INTERVAL rs.offset_minutes MINUTE
  FROM route_stops rs
  WHERE rs.route_id = p_route
    AND rs.stop_sequence < (SELECT MAX(stop_sequence) FROM route_stops WHERE route_id = p_route);

  INSERT INTO seat_inventory (trip_id, seat_number, leg_sequence)
  WITH RECURSIVE seats AS (
      SELECT 1 AS seat_number UNION ALL SELECT seat_number + 1 FROM seats WHERE seat_number < 14)
  SELECT l.trip_id, s.seat_number, l.leg_sequence
  FROM trip_legs l CROSS JOIN seats s
  WHERE l.trip_id = p_trip_id;
END$$

-- A booking with its seat legs and payment row, as the API would have
-- left them. p_provider 'paymongo' => app payment (paid at booking);
-- 'cash' => walk-in, payment stays pending until the remittance is received.
CREATE PROCEDURE seed_booking(
  IN p_booking_id CHAR(36), IN p_trip_id CHAR(36),
  IN p_pax CHAR(36), IN p_walkin_name VARCHAR(150), IN p_type VARCHAR(16),
  IN p_from SMALLINT, IN p_to SMALLINT, IN p_seat TINYINT, IN p_fare DECIMAL(10,2),
  IN p_status VARCHAR(16), IN p_provider VARCHAR(16), IN p_method VARCHAR(8),
  IN p_roadside BOOLEAN, IN p_landmark VARCHAR(255), IN p_booked_at DATETIME)
BEGIN
  INSERT INTO bookings
    (booking_id, ticket_number, trip_id, passenger_user_id, walkin_name, booking_type,
     boarding_stop_sequence, alighting_stop_sequence, seat_number, fare_amount, status,
     qr_payload, is_roadside_pickup, pickup_landmark, fare_is_manual, fare_note,
     booked_at, cancelled_at, created_at, updated_at)
  VALUES
    (p_booking_id,
     CONCAT('SBG-', DATE_FORMAT(p_booked_at, '%Y%m%d'), '-', UPPER(LEFT(MD5(p_booking_id), 6))),
     p_trip_id, p_pax, p_walkin_name, p_type, p_from, p_to, p_seat, p_fare, p_status,
     CONCAT('SBG-', p_booking_id), p_roadside, p_landmark, p_roadside,
     IF(p_roadside, 'Conductor-set fare, roadside pickup', NULL),
     p_booked_at,
     IF(p_status = 'cancelled', p_booked_at + INTERVAL 40 MINUTE, NULL),
     p_booked_at, p_booked_at);

  IF p_status NOT IN ('cancelled', 'rescheduled') THEN
    UPDATE seat_inventory
       SET status = 'booked', booking_id = p_booking_id
     WHERE trip_id = p_trip_id AND seat_number = p_seat
       AND leg_sequence BETWEEN p_from AND p_to - 1;
  END IF;

  INSERT INTO payments (payment_id, booking_id, provider, method, provider_ref_id, amount, status, paid_at, created_at)
  VALUES
    (UUID(), p_booking_id, p_provider, p_method,
     IF(p_provider = 'paymongo', CONCAT('cs_demo_', LEFT(MD5(p_booking_id), 12)), NULL),
     p_fare,
     CASE WHEN p_status = 'cancelled' THEN 'voided'
          WHEN p_provider = 'paymongo' THEN 'paid'
          ELSE 'pending' END,
     IF(p_provider = 'paymongo' AND p_status <> 'cancelled', p_booked_at + INTERVAL 2 MINUTE, NULL),
     p_booked_at);
END$$
DELIMITER ;

-- ============================================================ upcoming trips
-- Today and the next two days, every template. Today's early ones may
-- already be in the past at seed time; search hides them, which is right.
SET @d0 = CURRENT_DATE;
SET @d1 = CURRENT_DATE + INTERVAL 1 DAY;
SET @d2 = CURRENT_DATE + INTERVAL 2 DAY;

CALL seed_trip('TRIP-A2Z-TAG-D0-0600', 'TMPL-ECO-TAG-0600', @r_tag, TIMESTAMP(@d0, '06:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', 'scheduled');
CALL seed_trip('TRIP-A2Z-TAG-D0-0900', 'TMPL-ECO-TAG-0900', @r_tag, TIMESTAMP(@d0, '09:00:00'), 'VAN-0004', 'USER-DRIVER-0005', 'USER-CONDUCTOR-0005', 'Mid-morning',     'scheduled');
CALL seed_trip('TRIP-A2Z-TAG-D0-1400', 'TMPL-ECO-TAG-1400', @r_tag, TIMESTAMP(@d0, '14:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Afternoon',       'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D0-0630', 'TMPL-ECO-DIG-0630', @r_dig, TIMESTAMP(@d0, '06:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D0-1230', 'TMPL-ECO-DIG-1230', @r_dig, TIMESTAMP(@d0, '12:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'Noon Trip',       'scheduled');
CALL seed_trip('TRIP-A2Z-MAT-D0-0700', 'TMPL-ECO-MAT-0700', @r_mat, TIMESTAMP(@d0, '07:00:00'), 'VAN-0006', 'USER-DRIVER-0003', 'USER-CONDUCTOR-0003', 'Daily Mati',      'scheduled');

CALL seed_trip('TRIP-A2Z-TAG-D1-0600', 'TMPL-ECO-TAG-0600', @r_tag, TIMESTAMP(@d1, '06:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', 'scheduled');
CALL seed_trip('TRIP-A2Z-TAG-D1-0900', 'TMPL-ECO-TAG-0900', @r_tag, TIMESTAMP(@d1, '09:00:00'), 'VAN-0004', 'USER-DRIVER-0005', 'USER-CONDUCTOR-0005', 'Mid-morning',     'scheduled');
CALL seed_trip('TRIP-A2Z-TAG-D1-1400', 'TMPL-ECO-TAG-1400', @r_tag, TIMESTAMP(@d1, '14:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Afternoon',       'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D1-0630', 'TMPL-ECO-DIG-0630', @r_dig, TIMESTAMP(@d1, '06:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D1-1230', 'TMPL-ECO-DIG-1230', @r_dig, TIMESTAMP(@d1, '12:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'Noon Trip',       'scheduled');
CALL seed_trip('TRIP-A2Z-MAT-D1-0700', 'TMPL-ECO-MAT-0700', @r_mat, TIMESTAMP(@d1, '07:00:00'), 'VAN-0006', 'USER-DRIVER-0003', 'USER-CONDUCTOR-0003', 'Daily Mati',      'scheduled');

CALL seed_trip('TRIP-A2Z-TAG-D2-0600', 'TMPL-ECO-TAG-0600', @r_tag, TIMESTAMP(@d2, '06:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', 'scheduled');
CALL seed_trip('TRIP-A2Z-TAG-D2-0900', 'TMPL-ECO-TAG-0900', @r_tag, TIMESTAMP(@d2, '09:00:00'), 'VAN-0004', 'USER-DRIVER-0005', 'USER-CONDUCTOR-0005', 'Mid-morning',     'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D2-0630', 'TMPL-ECO-DIG-0630', @r_dig, TIMESTAMP(@d2, '06:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      'scheduled');
CALL seed_trip('TRIP-A2Z-DIG-D2-1230', 'TMPL-ECO-DIG-1230', @r_dig, TIMESTAMP(@d2, '12:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'Noon Trip',       'scheduled');
CALL seed_trip('TRIP-A2Z-MAT-D2-0700', 'TMPL-ECO-MAT-0700', @r_mat, TIMESTAMP(@d2, '07:00:00'), 'VAN-0006', 'USER-DRIVER-0003', 'USER-CONDUCTOR-0003', 'Daily Mati',      'scheduled');

-- A few advance bookings on tomorrow's trips so the dispatcher is not blank.
CALL seed_booking('BKG-A2Z-U001', 'TRIP-A2Z-TAG-D1-0600', 'USER-PAX-DEMO-0001', NULL, 'app', 1, 4, 1, 100.00, 'confirmed', 'paymongo', 'gcash', FALSE, NULL, NOW() - INTERVAL 3 HOUR);
CALL seed_booking('BKG-A2Z-U002', 'TRIP-A2Z-TAG-D1-0600', 'USER-PAX-DEMO-0003', NULL, 'app', 2, 4, 2,  45.00, 'confirmed', 'paymongo', 'maya',  FALSE, NULL, NOW() - INTERVAL 2 HOUR);
CALL seed_booking('BKG-A2Z-U003', 'TRIP-A2Z-DIG-D1-0630', 'USER-PAX-DEMO-0005', NULL, 'app', 1, 3, 1, 110.00, 'confirmed', 'paymongo', 'gcash', FALSE, NULL, NOW() - INTERVAL 5 HOUR);
CALL seed_booking('BKG-A2Z-U004', 'TRIP-A2Z-MAT-D1-0700', 'USER-PAX-DEMO-0002', NULL, 'app', 1, 3, 1, 250.00, 'confirmed', 'paymongo', 'card',  FALSE, NULL, NOW() - INTERVAL 1 HOUR);
CALL seed_booking('BKG-A2Z-U005', 'TRIP-A2Z-MAT-D1-0700', 'USER-PAX-DEMO-0006', NULL, 'app', 1, 3, 2, 250.00, 'pending',   'paymongo', NULL,    FALSE, NULL, NOW() - INTERVAL 4 MINUTE);
-- U005 is mid-checkout: hold the seat the way reserve() does.
UPDATE seat_inventory SET status = 'held', hold_expires_at = NOW() + INTERVAL 6 MINUTE
 WHERE booking_id = 'BKG-A2Z-U005';
UPDATE payments SET status = 'pending', paid_at = NULL WHERE booking_id = 'BKG-A2Z-U005';

-- =========================================================== completed trips
SET @p1 = CURRENT_DATE - INTERVAL 1 DAY;
SET @p2 = CURRENT_DATE - INTERVAL 2 DAY;

CALL seed_trip('TRIP-A2Z-TAG-P1-0600', 'TMPL-ECO-TAG-0600', @r_tag, TIMESTAMP(@p1, '06:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', 'completed');
CALL seed_trip('TRIP-A2Z-TAG-P1-0900', 'TMPL-ECO-TAG-0900', @r_tag, TIMESTAMP(@p1, '09:00:00'), 'VAN-0004', 'USER-DRIVER-0005', 'USER-CONDUCTOR-0005', 'Mid-morning',     'completed');
CALL seed_trip('TRIP-A2Z-DIG-P1-0630', 'TMPL-ECO-DIG-0630', @r_dig, TIMESTAMP(@p1, '06:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      'completed');
CALL seed_trip('TRIP-A2Z-MAT-P1-0700', 'TMPL-ECO-MAT-0700', @r_mat, TIMESTAMP(@p1, '07:00:00'), 'VAN-0006', 'USER-DRIVER-0003', 'USER-CONDUCTOR-0003', 'Daily Mati',      'completed');
CALL seed_trip('TRIP-A2Z-TAG-P2-0600', 'TMPL-ECO-TAG-0600', @r_tag, TIMESTAMP(@p2, '06:00:00'), 'VAN-0003', 'USER-DRIVER-0002', 'USER-CONDUCTOR-0002', 'Morning Express', 'completed');
CALL seed_trip('TRIP-A2Z-DIG-P2-0630', 'TMPL-ECO-DIG-0630', @r_dig, TIMESTAMP(@p2, '06:30:00'), 'VAN-0005', 'USER-DRIVER-0004', 'USER-CONDUCTOR-0004', 'First Trip',      'completed');

-- --- Yesterday, Ecoland-Tagum 06:00 (camera van). Full picture:
--     app bookings, walk-ins, a roadside pickup, one no-show, one cancel,
--     one seat sold twice on non-overlapping legs (seat 3: 1->2 then 2->4).
SET @t = 'TRIP-A2Z-TAG-P1-0600'; SET @dep = TIMESTAMP(@p1, '06:00:00');
CALL seed_booking('BKG-A2Z-P101', @t, 'USER-PAX-DEMO-0001', NULL, 'app', 1, 4, 1, 100.00, 'boarded',   'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 14 HOUR);
CALL seed_booking('BKG-A2Z-P102', @t, 'USER-PAX-DEMO-0002', NULL, 'app', 1, 4, 2, 100.00, 'boarded',   'paymongo', 'maya',  FALSE, NULL, @dep - INTERVAL 9 HOUR);
CALL seed_booking('BKG-A2Z-P103', @t, 'USER-PAX-DEMO-0003', NULL, 'app', 1, 2, 3,  60.00, 'boarded',   'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 20 HOUR);
CALL seed_booking('BKG-A2Z-P104', @t, 'USER-PAX-DEMO-0004', NULL, 'app', 2, 4, 3,  45.00, 'boarded',   'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 3 HOUR);
CALL seed_booking('BKG-A2Z-P105', @t, 'USER-PAX-DEMO-0006', NULL, 'app', 1, 4, 4, 100.00, 'no_show',   'paymongo', 'card',  FALSE, NULL, @dep - INTERVAL 30 HOUR);
CALL seed_booking('BKG-A2Z-P106', @t, 'USER-PAX-DEMO-0005', NULL, 'app', 1, 3, 5,  75.00, 'cancelled', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 26 HOUR);
CALL seed_booking('BKG-A2Z-P107', @t, NULL, 'Rosa Alcantara', 'walk_in', 1, 4, 5, 100.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 12 MINUTE);
CALL seed_booking('BKG-A2Z-P108', @t, NULL, 'Dennis Uy',      'walk_in', 1, 4, 6, 100.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 9 MINUTE);
CALL seed_booking('BKG-A2Z-P109', @t, NULL, 'Mae Lumbao',     'walk_in', 1, 3, 7,  75.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 5 MINUTE);
CALL seed_booking('BKG-A2Z-P110', @t, NULL, 'Roadside - Tibungco', 'walk_in', 1, 4, 8, 90.00, 'boarded', 'cash', 'cash', TRUE, 'Tibungco crossing, waiting shed', @dep + INTERVAL 25 MINUTE);
CALL seed_booking('BKG-A2Z-P111', @t, NULL, 'Junjun Sarabia', 'walk_in', 2, 4, 9,  45.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep + INTERVAL 44 MINUTE);
-- Remittance received in full: cash 100+100+75+90+45 = 410
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P1-TAG0600', @t, 'USER-CONDUCTOR-0002', 410.00, 410.00, 410.00, 0.00, 'received', @dep + INTERVAL 140 MINUTE, @dep + INTERVAL 150 MINUTE, 'USER-COOPADMIN-0001', NULL, @dep + INTERVAL 140 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P1-TAG0600', p.status = 'paid', p.paid_at = @dep + INTERVAL 150 MINUTE
 WHERE b.trip_id = @t AND p.provider = 'cash';
-- Audits: reconciled at the door, then a +1 on leg 2 the office already resolved.
INSERT INTO yolov8_audit_logs (audit_id, trip_id, leg_sequence, triggered_by_user_id, trigger_type, visual_count, booked_count, variance, model_version, inference_ms, confidence_avg, resolution_status, resolved_by_user_id, resolved_at, resolution_notes, captured_at) VALUES
  ('AUD-A2Z-P1-TAG-01', @t, 1, 'USER-DRIVER-0002', 'door_close', 8, 8, 0, 'yolov8n-1.0', 131, 0.912, 'reconciled', NULL, NULL, NULL, @dep + INTERVAL 3 MINUTE),
  ('AUD-A2Z-P1-TAG-02', @t, 2, NULL, 'gps_node', 9, 8, 1, 'yolov8n-1.0', 118, 0.887, 'resolved', 'USER-COOPADMIN-0001', @dep + INTERVAL 160 MINUTE, 'Roadside pickup at Tibungco was logged 12 minutes after the frame. Fare recorded; no leakage.', @dep + INTERVAL 20 MINUTE);

-- --- Yesterday, Ecoland-Tagum 09:00 (no camera). Cash still in hand: the
--     conductor has not remitted yet, so the office sees cash_in_hand, not
--     unreconciled.
SET @t = 'TRIP-A2Z-TAG-P1-0900'; SET @dep = TIMESTAMP(@p1, '09:00:00');
CALL seed_booking('BKG-A2Z-P121', @t, 'USER-PAX-DEMO-0005', NULL, 'app', 1, 4, 1, 100.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 6 HOUR);
CALL seed_booking('BKG-A2Z-P122', @t, NULL, 'Teodoro Mahinay', 'walk_in', 1, 4, 2, 100.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 8 MINUTE);
CALL seed_booking('BKG-A2Z-P123', @t, NULL, 'Cristy Bael',     'walk_in', 1, 2, 3,  60.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 6 MINUTE);
CALL seed_booking('BKG-A2Z-P124', @t, NULL, 'Arnel Dizon',     'walk_in', 1, 4, 4, 100.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 2 MINUTE);
CALL seed_booking('BKG-A2Z-P125', @t, NULL, 'Roadside - Carmen bypass', 'walk_in', 3, 4, 3, 30.00, 'boarded', 'cash', 'cash', TRUE, 'Carmen bypass, near the rice mill', @dep + INTERVAL 62 MINUTE);
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P1-TAG0900', @t, 'USER-CONDUCTOR-0005', 290.00, NULL, NULL, NULL, 'pending', NULL, NULL, NULL, NULL, @dep + INTERVAL 100 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P1-TAG0900'
 WHERE b.trip_id = @t AND p.provider = 'cash';

-- --- Yesterday, Ecoland-Digos 06:30 (camera van). Remittance SHORT by 45:
--     disputed. Plus an audit the model got wrong (ignored) and one still
--     waiting in the queue.
SET @t = 'TRIP-A2Z-DIG-P1-0630'; SET @dep = TIMESTAMP(@p1, '06:30:00');
CALL seed_booking('BKG-A2Z-P131', @t, 'USER-PAX-DEMO-0005', NULL, 'app', 1, 3, 1, 110.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 15 HOUR);
CALL seed_booking('BKG-A2Z-P132', @t, 'USER-PAX-DEMO-0004', NULL, 'app', 1, 3, 2, 110.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 2 HOUR);
CALL seed_booking('BKG-A2Z-P133', @t, NULL, 'Lorna Quijano',  'walk_in', 1, 3, 3, 110.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 10 MINUTE);
CALL seed_booking('BKG-A2Z-P134', @t, NULL, 'Rey Bantilan',   'walk_in', 1, 3, 4, 110.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 7 MINUTE);
CALL seed_booking('BKG-A2Z-P135', @t, NULL, 'Nina Cagas',     'walk_in', 1, 2, 5,  70.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 4 MINUTE);
CALL seed_booking('BKG-A2Z-P136', @t, NULL, 'Bebot Ledesma',  'walk_in', 2, 3, 5,  45.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep + INTERVAL 52 MINUTE);
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P1-DIG0630', @t, 'USER-CONDUCTOR-0004', 335.00, 335.00, 290.00, -45.00, 'disputed', @dep + INTERVAL 110 MINUTE, @dep + INTERVAL 125 MINUTE, 'USER-COOPADMIN-0001', 'Sta. Cruz walk-in fare missing from the envelope. Conductor to explain.', @dep + INTERVAL 110 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P1-DIG0630', p.status = 'paid', p.paid_at = @dep + INTERVAL 125 MINUTE
 WHERE b.trip_id = @t AND p.provider = 'cash';
INSERT INTO yolov8_audit_logs (audit_id, trip_id, leg_sequence, triggered_by_user_id, trigger_type, visual_count, booked_count, variance, model_version, inference_ms, confidence_avg, resolution_status, resolved_by_user_id, resolved_at, resolution_notes, captured_at) VALUES
  ('AUD-A2Z-P1-DIG-01', @t, 1, 'USER-DRIVER-0004', 'door_close', 6, 5, 1, 'yolov8n-1.0', 124, 0.731, 'ignored', 'USER-COOPADMIN-0001', @dep + INTERVAL 130 MINUTE, 'Child on a parent''s lap counted as a passenger. Model, not a stowaway.', @dep + INTERVAL 2 MINUTE),
  ('AUD-A2Z-P1-DIG-02', @t, 2, NULL, 'gps_node', 7, 5, 2, 'yolov8n-1.0', 119, 0.902, 'pending', NULL, NULL, NULL, @dep + INTERVAL 55 MINUTE);

-- --- Yesterday, Ecoland-Mati 07:00 (no camera). Quiet, fully reconciled.
SET @t = 'TRIP-A2Z-MAT-P1-0700'; SET @dep = TIMESTAMP(@p1, '07:00:00');
CALL seed_booking('BKG-A2Z-P141', @t, 'USER-PAX-DEMO-0002', NULL, 'app', 1, 3, 1, 250.00, 'boarded', 'paymongo', 'card',  FALSE, NULL, @dep - INTERVAL 40 HOUR);
CALL seed_booking('BKG-A2Z-P142', @t, 'USER-PAX-DEMO-0006', NULL, 'app', 1, 3, 2, 250.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 18 HOUR);
CALL seed_booking('BKG-A2Z-P143', @t, NULL, 'Ismael Baguio',   'walk_in', 1, 3, 3, 250.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 11 MINUTE);
CALL seed_booking('BKG-A2Z-P144', @t, NULL, 'Perla Manriquez', 'walk_in', 1, 2, 4, 180.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 3 MINUTE);
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P1-MAT0700', @t, 'USER-CONDUCTOR-0003', 430.00, 430.00, 430.00, 0.00, 'received', @dep + INTERVAL 260 MINUTE, @dep + INTERVAL 275 MINUTE, 'USER-COOPADMIN-0001', NULL, @dep + INTERVAL 260 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P1-MAT0700', p.status = 'paid', p.paid_at = @dep + INTERVAL 275 MINUTE
 WHERE b.trip_id = @t AND p.provider = 'cash';

-- --- Two days ago, Ecoland-Tagum 06:00. Camera unreachable at the door
--     (failed audit -- the node refused to invent a number), then fine.
SET @t = 'TRIP-A2Z-TAG-P2-0600'; SET @dep = TIMESTAMP(@p2, '06:00:00');
CALL seed_booking('BKG-A2Z-P151', @t, 'USER-PAX-DEMO-0001', NULL, 'app', 1, 4, 1, 100.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 10 HOUR);
CALL seed_booking('BKG-A2Z-P152', @t, 'USER-PAX-DEMO-0003', NULL, 'app', 2, 4, 2,  45.00, 'boarded', 'paymongo', 'maya',  FALSE, NULL, @dep - INTERVAL 5 HOUR);
CALL seed_booking('BKG-A2Z-P153', @t, NULL, 'Gina Pardillo',  'walk_in', 1, 4, 3, 100.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 9 MINUTE);
CALL seed_booking('BKG-A2Z-P154', @t, NULL, 'Boyet Lacson',   'walk_in', 1, 3, 4,  75.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 4 MINUTE);
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P2-TAG0600', @t, 'USER-CONDUCTOR-0002', 175.00, 175.00, 175.00, 0.00, 'received', @dep + INTERVAL 130 MINUTE, @dep + INTERVAL 140 MINUTE, 'USER-COOPADMIN-0001', NULL, @dep + INTERVAL 130 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P2-TAG0600', p.status = 'paid', p.paid_at = @dep + INTERVAL 140 MINUTE
 WHERE b.trip_id = @t AND p.provider = 'cash';
INSERT INTO yolov8_audit_logs (audit_id, trip_id, leg_sequence, triggered_by_user_id, trigger_type, visual_count, booked_count, variance, model_version, inference_ms, confidence_avg, resolution_status, resolved_by_user_id, resolved_at, resolution_notes, captured_at) VALUES
  ('AUD-A2Z-P2-TAG-01', @t, 1, 'USER-DRIVER-0002', 'door_close', 0, 3, 0, NULL, NULL, NULL, 'failed', NULL, NULL, 'Camera node unreachable (502). No count recorded.', @dep + INTERVAL 2 MINUTE),
  ('AUD-A2Z-P2-TAG-02', @t, 2, NULL, 'gps_node', 4, 4, 0, 'yolov8n-1.0', 127, 0.934, 'reconciled', NULL, NULL, NULL, @dep + INTERVAL 48 MINUTE);

-- --- Two days ago, Ecoland-Digos 06:30. Reconciled.
SET @t = 'TRIP-A2Z-DIG-P2-0630'; SET @dep = TIMESTAMP(@p2, '06:30:00');
CALL seed_booking('BKG-A2Z-P161', @t, 'USER-PAX-DEMO-0004', NULL, 'app', 1, 3, 1, 110.00, 'boarded', 'paymongo', 'gcash', FALSE, NULL, @dep - INTERVAL 7 HOUR);
CALL seed_booking('BKG-A2Z-P162', @t, NULL, 'Vilma Sarmiento', 'walk_in', 1, 3, 2, 110.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 6 MINUTE);
CALL seed_booking('BKG-A2Z-P163', @t, NULL, 'Oscar Tumulak',   'walk_in', 1, 2, 3,  70.00, 'boarded', 'cash', 'cash', FALSE, NULL, @dep - INTERVAL 2 MINUTE);
INSERT INTO cash_remittances (remittance_id, trip_id, collected_by_user_id, expected_amount, declared_amount, received_amount, variance, status, submitted_at, received_at, received_by_user_id, notes, created_at)
VALUES ('REM-A2Z-P2-DIG0630', @t, 'USER-CONDUCTOR-0004', 180.00, 180.00, 180.00, 0.00, 'received', @dep + INTERVAL 100 MINUTE, @dep + INTERVAL 110 MINUTE, 'USER-COOPADMIN-0001', NULL, @dep + INTERVAL 100 MINUTE);
UPDATE payments p JOIN bookings b ON b.booking_id = p.booking_id
   SET p.remittance_id = 'REM-A2Z-P2-DIG0630', p.status = 'paid', p.paid_at = @dep + INTERVAL 110 MINUTE
 WHERE b.trip_id = @t AND p.provider = 'cash';
INSERT INTO yolov8_audit_logs (audit_id, trip_id, leg_sequence, triggered_by_user_id, trigger_type, visual_count, booked_count, variance, model_version, inference_ms, confidence_avg, resolution_status, resolved_by_user_id, resolved_at, resolution_notes, captured_at) VALUES
  ('AUD-A2Z-P2-DIG-01', @t, 1, 'USER-DRIVER-0004', 'door_close', 3, 3, 0, 'yolov8n-1.0', 122, 0.951, 'reconciled', NULL, NULL, NULL, @dep + INTERVAL 3 MINUTE);

DROP PROCEDURE seed_trip;
DROP PROCEDURE seed_booking;

SELECT CONCAT('demo dataset: ',
  (SELECT COUNT(*) FROM routes), ' routes, ',
  (SELECT COUNT(*) FROM trips WHERE trip_id LIKE 'TRIP-A2Z-%'), ' A2Z trips, ',
  (SELECT COUNT(*) FROM bookings WHERE booking_id LIKE 'BKG-A2Z-%'), ' bookings, ',
  (SELECT COUNT(*) FROM cash_remittances), ' remittances, ',
  (SELECT COUNT(*) FROM yolov8_audit_logs), ' audits') AS result;
