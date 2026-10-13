-- =====================================================================
-- 020_contract_driver_and_roadside.sql
--
-- CONTRACTION of paper revision 468, approved 13 Oct. Drops what 017,
-- 019 and the roadside block left behind for history:
--
--   driver role        the 'driver' value of users.role,
--                      notifications.audience, sos_alerts.raised_by_role
--   driver_credentials copied into operators by 017
--   trips.driver_id    the operator name and licence were copied onto
--                      each trip that ran (019); the van gives the operator
--   schedule_templates.default_driver_id
--   driver_headcounts  the Dispatcher's manual headcount, retired: a
--                      self-report by the person being audited, read by
--                      nothing. The camera's per-stop snapshot is the
--                      drift check (brief 5.2)
--   bookings roadside  is_roadside_pickup, pickup_landmark, fare_is_manual,
--                      fare_note: no path writes them since the roadside
--                      block; the revenue view stops summing them
--
-- Deliberately NOT here:
--   schedule_templates default van and Dispatcher: generate_trips staffs
--     every timetable trip from them until assignment at the van's turn
--     exists (brief step 4).
--   vans.operator_id NOT NULL: POST /fleet/vans creates a van with no
--     operator, and nothing creates an operator until the roster step.
--   bookings.booking_type 'driver_issued' and conversations.kind
--     'conductor_driver': legacy values, not part of this approval.
--
-- The preflight stops the migration, before any change, on a database
-- whose data these drops would lose: a driver account (its trips, audits
-- and SOS history point at it), a 'driver' notification or SOS row, a
-- trip that ran with a driver but has no copied name, or a licence that
-- 017 did not copy into operators. A rebuilt dev or demo database passes.
--
-- The revenue view joins routes with LEFT JOIN: since 019 a van rental
-- has no route, and an inner join would drop its fares from the view.
--
-- Reverse: db/migrations/down/020_contract_driver_and_roadside.sql
-- (restores the structure; the dropped data does not come back).
-- =====================================================================

-- ------------------------------------------------------------ preflight
DROP PROCEDURE IF EXISTS m020_preflight;
DELIMITER $$
CREATE PROCEDURE m020_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM users WHERE role = 'driver') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '020 stopped: driver accounts exist. Their history needs a decision before the driver role can go.';
  END IF;
  IF EXISTS (SELECT 1 FROM notifications WHERE audience = 'driver')
     OR EXISTS (SELECT 1 FROM sos_alerts WHERE raised_by_role = 'driver') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '020 stopped: notifications or SOS alerts still name the driver role.';
  END IF;
  IF EXISTS (SELECT 1 FROM trips
              WHERE driver_id IS NOT NULL AND driver_name IS NULL
                AND status IN ('boarding','departed','completed')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '020 stopped: a trip that ran with a driver has no copied driver name.';
  END IF;
  IF EXISTS (SELECT 1 FROM driver_credentials dc
              WHERE NOT EXISTS (SELECT 1 FROM operators o
                                 WHERE o.license_number = dc.license_number)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '020 stopped: a driver licence was not copied into operators.';
  END IF;
END$$
DELIMITER ;
CALL m020_preflight();
DROP PROCEDURE m020_preflight;

-- ------------------------------------------------------- revenue view
CREATE OR REPLACE VIEW v_trip_revenue_reconciliation AS
SELECT
    t.trip_id,
    t.service_date,
    t.departure_datetime,
    r.route_name,
    v.plate_number,
    t.seat_capacity,
    COALESCE(bk.total_bookings, 0)        AS total_bookings,
    COALESCE(bk.app_bookings, 0)          AS app_bookings,
    COALESCE(bk.walkin_bookings, 0)       AS walkin_bookings,
    COALESCE(bk.collected_fare, 0)        AS collected_fare,
    -- Cash a conductor holds but has not handed over. Not missing money.
    COALESCE(bk.cash_in_hand, 0)          AS cash_in_hand,
    COALESCE(bk.expected_fare, 0)         AS expected_fare,
    COALESCE(bk.expected_fare, 0)
      - COALESCE(bk.collected_fare, 0)
      - COALESCE(bk.cash_in_hand, 0)      AS unreconciled_amount,
    COALESCE(au.max_variance, 0)          AS max_yolo_variance,
    COALESCE(au.pending_audits, 0)        AS pending_audits
FROM trips t
LEFT JOIN routes r  ON r.route_id = t.route_id
LEFT JOIN vans v    ON v.van_id   = t.van_id
LEFT JOIN (
    SELECT
        b.trip_id,
        COUNT(*)                                            AS total_bookings,
        SUM(b.booking_type = 'app')                         AS app_bookings,
        SUM(b.booking_type IN ('walk_in', 'driver_issued')) AS walkin_bookings,
        SUM(b.fare_amount)                                  AS expected_fare,
        SUM(COALESCE(p.paid_amount, 0))                     AS collected_fare,
        SUM(COALESCE(p.cash_pending, 0))                    AS cash_in_hand
    FROM bookings b
    LEFT JOIN (
        SELECT
            booking_id,
            SUM(CASE WHEN status = 'paid' THEN amount ELSE 0 END)     AS paid_amount,
            SUM(CASE WHEN provider = 'cash' AND status = 'pending'
                     THEN amount ELSE 0 END)                          AS cash_pending
        FROM payments
        GROUP BY booking_id
    ) p ON p.booking_id = b.booking_id
    WHERE b.status NOT IN ('pending', 'cancelled', 'rescheduled')
    GROUP BY b.trip_id
) bk ON bk.trip_id = t.trip_id
LEFT JOIN (
    SELECT
        trip_id,
        MAX(variance)                       AS max_variance,
        SUM(resolution_status = 'pending')  AS pending_audits
    FROM yolov8_audit_logs
    GROUP BY trip_id
) au ON au.trip_id = t.trip_id;

-- ------------------------------------------------------------ bookings
ALTER TABLE bookings
    DROP INDEX idx_booking_roadside,
    DROP COLUMN is_roadside_pickup,
    DROP COLUMN pickup_landmark,
    DROP COLUMN fare_is_manual,
    DROP COLUMN fare_note;

-- ---------------------------------------------------------- the driver
DROP TABLE driver_headcounts;
DROP TABLE driver_credentials;

ALTER TABLE trips
    DROP FOREIGN KEY fk_trip_driver,
    DROP INDEX idx_trip_driver,
    DROP INDEX idx_trip_driver_date,
    DROP COLUMN driver_id;

ALTER TABLE schedule_templates
    DROP FOREIGN KEY fk_template_driver,
    DROP COLUMN default_driver_id;

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin')
        NOT NULL;

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','dispatcher','terminal_manager','cashier')
        NOT NULL;

ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin')
        NOT NULL;

INSERT INTO schema_migrations (version)
VALUES ('020_contract_driver_and_roadside');
