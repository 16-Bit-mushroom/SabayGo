-- =====================================================================
-- Reverses 020_contract_driver_and_roadside.sql.
-- Run with: ./db/rollback.sh 020_contract_driver_and_roadside
--
-- Restores the structure exactly (013's revenue view, the two tables,
-- the columns in their old places, the 'driver' ENUM values). The data
-- dropped by 020 does not come back: the roadside flags and hand-set
-- fares on old bookings, driver_credentials, driver_headcounts and
-- trips.driver_id are empty / FALSE after this runs.
-- =====================================================================

ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin',
             'driver')
        NOT NULL;

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','dispatcher','terminal_manager','cashier','driver')
        NOT NULL;

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin',
             'driver')
        NOT NULL;

ALTER TABLE schedule_templates
    ADD COLUMN default_driver_id CHAR(36) NULL AFTER default_van_id,
    ADD CONSTRAINT fk_template_driver
        FOREIGN KEY (default_driver_id) REFERENCES users (user_id);

ALTER TABLE trips
    ADD COLUMN driver_id CHAR(36) NULL AFTER van_id,
    ADD KEY idx_trip_driver (driver_id, service_date),
    ADD KEY idx_trip_driver_date (driver_id, service_date, status),
    ADD CONSTRAINT fk_trip_driver
        FOREIGN KEY (driver_id) REFERENCES users (user_id);

CREATE TABLE driver_credentials (
    user_id             CHAR(36)     NOT NULL,
    license_number      VARCHAR(64)  NOT NULL,
    license_expiry_date DATE         NOT NULL,
    cttmo_id_number     VARCHAR(64)  NULL,
    cttmo_id_photo_url  VARCHAR(512) NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_license_number (license_number),
    CONSTRAINT fk_driver_cred_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE driver_headcounts (
    headcount_id          CHAR(36)          NOT NULL,
    trip_id               CHAR(36)          NOT NULL,
    stop_sequence         SMALLINT UNSIGNED NOT NULL,
    confirmed_count       SMALLINT UNSIGNED NOT NULL,
    manifest_count        SMALLINT UNSIGNED NOT NULL,
    variance              SMALLINT          NOT NULL,
    confirmed_by_user_id  CHAR(36)          NOT NULL,
    confirmed_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    client_recorded_at    DATETIME(6)       NULL,
    synced_at             DATETIME(6)       NULL,
    PRIMARY KEY (headcount_id),
    UNIQUE KEY uq_headcount_stop (trip_id, stop_sequence),
    KEY fk_headcount_user (confirmed_by_user_id),
    CONSTRAINT fk_headcount_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_headcount_user
        FOREIGN KEY (confirmed_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

ALTER TABLE bookings
    ADD COLUMN is_roadside_pickup BOOLEAN NOT NULL DEFAULT FALSE AFTER logged_by,
    ADD COLUMN pickup_landmark VARCHAR(255) NULL AFTER is_roadside_pickup,
    ADD COLUMN fare_is_manual BOOLEAN NOT NULL DEFAULT FALSE AFTER fare_amount,
    ADD COLUMN fare_note VARCHAR(255) NULL AFTER fare_is_manual,
    ADD KEY idx_booking_roadside (trip_id, is_roadside_pickup);

-- 013's view, verbatim.
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
    COALESCE(bk.roadside_bookings, 0)     AS roadside_bookings,
    COALESCE(bk.manual_fare_bookings, 0)  AS manual_fare_bookings,
    COALESCE(bk.collected_fare, 0)        AS collected_fare,
    -- Cash the crew has taken but not yet handed over. Money in a
    -- pocket, not money missing -- kept apart from unreconciled.
    COALESCE(bk.cash_in_hand, 0)          AS cash_in_hand,
    COALESCE(bk.expected_fare, 0)         AS expected_fare,
    COALESCE(bk.expected_fare, 0)
      - COALESCE(bk.collected_fare, 0)
      - COALESCE(bk.cash_in_hand, 0)      AS unreconciled_amount,
    COALESCE(au.max_variance, 0)          AS max_yolo_variance,
    COALESCE(au.pending_audits, 0)        AS pending_audits
FROM trips t
JOIN routes r       ON r.route_id = t.route_id
LEFT JOIN vans v    ON v.van_id   = t.van_id
LEFT JOIN (
    SELECT
        b.trip_id,
        COUNT(*)                                            AS total_bookings,
        SUM(b.booking_type = 'app')                         AS app_bookings,
        SUM(b.booking_type IN ('walk_in', 'driver_issued')) AS walkin_bookings,
        SUM(b.is_roadside_pickup)                           AS roadside_bookings,
        SUM(b.fare_is_manual)                               AS manual_fare_bookings,
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

DELETE FROM schema_migrations WHERE version = '020_contract_driver_and_roadside';
