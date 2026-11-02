-- Reverses 032: puts back the online-payment and QR structures.
--
-- Structure only. The rows of `payments` and `boarding_scans` are gone,
-- and bookings.qr_payload comes back empty, so a booking restored this
-- way has no scannable ticket until the application regenerates one.
-- What survives the round trip is which seats were paid: 032 copied that
-- into bookings.payment_status before dropping the table, and the
-- rebuild below copies it back as a cash payment row.

CREATE TABLE payments (
    payment_id        CHAR(36)      NOT NULL,
    booking_id        CHAR(36)      NOT NULL,
    provider          ENUM('paymongo','cash','physical_ticket') NOT NULL,
    method            ENUM('gcash','maya','card','cash') NULL,
    remittance_id     CHAR(36)      NULL,
    provider_ref_id   VARCHAR(128)  NULL,
    provider_event_id VARCHAR(128)  NULL,
    amount            DECIMAL(10,2) NOT NULL,
    status            ENUM('pending','paid','failed','refunded','voided')
                      NOT NULL DEFAULT 'pending',
    paid_at           DATETIME(6)   NULL,
    raw_payload       JSON          NULL,
    created_at        DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (payment_id),
    UNIQUE KEY uq_provider_event (provider_event_id),
    KEY idx_payment_booking (booking_id),
    KEY idx_payment_status (status, paid_at),
    CONSTRAINT fk_payment_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE boarding_scans (
    scan_id            CHAR(36)          NOT NULL,
    booking_id         CHAR(36)          NOT NULL,
    scanned_by_user_id CHAR(36)          NOT NULL,
    stop_sequence      SMALLINT UNSIGNED NOT NULL,
    result             VARCHAR(24)       NOT NULL,
    scanned_at         DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    client_recorded_at DATETIME(6)       NULL,
    synced_at          DATETIME(6)       NULL,
    PRIMARY KEY (scan_id),
    KEY idx_scan_booking (booking_id),
    CONSTRAINT fk_scan_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id),
    CONSTRAINT fk_scan_user
        FOREIGN KEY (scanned_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

ALTER TABLE special_trip_requests
    DROP FOREIGN KEY fk_request_paid_by;

ALTER TABLE special_trip_requests
    DROP COLUMN paid_by,
    DROP COLUMN paid_at,
    ADD COLUMN payment_reference VARCHAR(64) NULL AFTER payment_status;

ALTER TABLE assisted_pickups
    DROP FOREIGN KEY fk_pickup_photo;

ALTER TABLE assisted_pickups
    DROP CHECK chk_pickup_activated,
    CHANGE COLUMN photo_message_id proof_message_id CHAR(36) NULL,
    ADD COLUMN activation_mode    ENUM('qr_scan','dispatcher_entry') NULL AFTER status,
    ADD COLUMN proof_confirmed_by CHAR(36)    NULL AFTER proof_message_id,
    ADD COLUMN proof_confirmed_at DATETIME(6) NULL AFTER proof_confirmed_by,
    ADD CONSTRAINT fk_pickup_proof
        FOREIGN KEY (proof_message_id) REFERENCES messages (message_id),
    ADD CONSTRAINT fk_pickup_proof_by
        FOREIGN KEY (proof_confirmed_by) REFERENCES users (user_id),
    ADD CONSTRAINT chk_pickup_proof
        CHECK ((proof_confirmed_by IS NULL) = (proof_confirmed_at IS NULL));

UPDATE assisted_pickups SET activation_mode = 'dispatcher_entry'
 WHERE activated_at IS NOT NULL;

ALTER TABLE assisted_pickups
    ADD CONSTRAINT chk_pickup_activated
        CHECK ((activated_at IS NULL) = (activation_mode IS NULL));

ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_proof','home_pickup_photo')
        NOT NULL;
UPDATE notifications SET type = 'home_pickup_proof' WHERE type = 'home_pickup_photo';
ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_proof')
        NOT NULL;

ALTER TABLE trips
    ADD COLUMN reschedule_cutoff_hours SMALLINT NOT NULL DEFAULT 6;

INSERT INTO cooperative_policies (policy_key, policy_value, data_type, description)
VALUES ('reschedule_cutoff_hours', '6', 'integer',
        'Hours before departure after which a booking can no longer be moved'),
       ('max_reschedules_per_booking', '2', 'integer',
        'How many times one booking may be moved to another trip'),
       ('refund_enabled', 'false', 'boolean',
        'Whether a cancelled booking is refunded')
ON DUPLICATE KEY UPDATE policy_value = VALUES(policy_value);

ALTER TABLE bookings
    ADD COLUMN qr_payload                  VARCHAR(255)     NULL AFTER status,
    ADD COLUMN rescheduled_from_booking_id CHAR(36)         NULL AFTER qr_payload,
    ADD COLUMN reschedule_count            TINYINT UNSIGNED NOT NULL DEFAULT 0
        AFTER rescheduled_from_booking_id,
    MODIFY COLUMN status ENUM('pending','confirmed','checked_in','boarded',
                              'completed','cancelled','no_show','rescheduled')
           NOT NULL DEFAULT 'pending';

ALTER TABLE bookings
    ADD UNIQUE KEY uq_qr_payload (qr_payload),
    ADD CONSTRAINT fk_booking_reschedule_src
        FOREIGN KEY (rescheduled_from_booking_id) REFERENCES bookings (booking_id);

INSERT INTO payments (payment_id, booking_id, provider, method, amount,
                      status, paid_at, created_at)
SELECT UUID(), booking_id, 'cash', 'cash', fare_amount,
       'pending', NULL, booked_at
  FROM bookings WHERE payment_status = 'paid';

ALTER TABLE bookings
    DROP FOREIGN KEY fk_booking_paid_by,
    DROP FOREIGN KEY fk_booking_cancelled_by;

ALTER TABLE bookings
    DROP INDEX idx_booking_code_trip,
    DROP INDEX uq_booking_code,
    DROP COLUMN cancel_reason,
    DROP COLUMN cancelled_by,
    DROP COLUMN paid_by,
    DROP COLUMN paid_at,
    DROP COLUMN payment_status,
    CHANGE COLUMN booking_code ticket_number VARCHAR(32) NOT NULL,
    ADD UNIQUE KEY uq_ticket_number (ticket_number);

ALTER TABLE passenger_events
    MODIFY COLUMN match_status
        ENUM('matched_qr','matched_booking','matched_log','unlisted') NULL;
UPDATE passenger_events SET match_status = 'matched_qr'
 WHERE match_status = 'matched_booking';
ALTER TABLE passenger_events
    MODIFY COLUMN match_status ENUM('matched_qr','matched_log','unlisted') NULL;

ALTER TABLE passenger_events
    DROP CHECK chk_event_booking_only_if_matched,
    ADD CONSTRAINT chk_event_booking_only_if_matched
        CHECK (matched_booking_id IS NULL
               OR match_status IN ('matched_qr','matched_log')
               OR resolution_status = 'listed');

-- The view as 020 left it.
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

DELETE FROM schema_migrations WHERE version = '032_cash_only_booking';
