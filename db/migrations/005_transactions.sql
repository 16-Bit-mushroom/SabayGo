-- =====================================================================
-- 005_transactions.sql
-- Bookings, payments, geofenced check-in, boarding validation.
-- =====================================================================

CREATE TABLE bookings (
    booking_id                 CHAR(36)          NOT NULL,
    ticket_number              VARCHAR(32)       NOT NULL,
    trip_id                    CHAR(36)          NOT NULL,

    -- NULL for anonymous walk-ins. Consultation: "If walk-in: no need
    -- information (optional if passenger wants to give info for receipt
    -- purposes)." Your old LogBookEntries forced name/phone/address --
    -- that requirement is now removed at the schema level.
    passenger_user_id          CHAR(36)          NULL,
    walkin_name                VARCHAR(150)      NULL,
    walkin_phone               VARCHAR(20)       NULL,
    walkin_wants_receipt       BOOLEAN           NOT NULL DEFAULT FALSE,

    booking_type               ENUM('app','walk_in','driver_issued') NOT NULL,
    boarding_stop_sequence     SMALLINT UNSIGNED NOT NULL,
    alighting_stop_sequence    SMALLINT UNSIGNED NOT NULL,
    seat_number                TINYINT UNSIGNED  NOT NULL,
    fare_amount                DECIMAL(10,2)     NOT NULL,

    status                     ENUM('pending','confirmed','checked_in','boarded',
                                    'completed','cancelled','no_show','rescheduled')
                               NOT NULL DEFAULT 'pending',
    qr_payload                 VARCHAR(255)      NULL,

    -- Reschedule chain. Consultation: no refunds, reschedule allowed
    -- within the cutoff window. The old booking becomes 'rescheduled'
    -- and points forward to its replacement, preserving the audit trail.
    rescheduled_from_booking_id CHAR(36)         NULL,
    reschedule_count           TINYINT UNSIGNED  NOT NULL DEFAULT 0,

    booked_at                  DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    cancelled_at               DATETIME(6)       NULL,
    created_at                 DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                 DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                                 ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (booking_id),
    UNIQUE KEY uq_ticket_number (ticket_number),
    UNIQUE KEY uq_qr_payload (qr_payload),
    KEY idx_booking_trip_status (trip_id, status),
    KEY idx_booking_passenger (passenger_user_id, booked_at),
    CONSTRAINT fk_booking_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_booking_passenger
        FOREIGN KEY (passenger_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_booking_reschedule_src
        FOREIGN KEY (rescheduled_from_booking_id) REFERENCES bookings (booking_id),
    CONSTRAINT chk_booking_segment CHECK (alighting_stop_sequence > boarding_stop_sequence),
    CONSTRAINT chk_booking_fare CHECK (fare_amount >= 0),
    CONSTRAINT chk_booking_seat CHECK (seat_number BETWEEN 1 AND 14)
) ENGINE=InnoDB;

ALTER TABLE seat_inventory
    ADD CONSTRAINT fk_seat_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------
-- payments
--
-- provider_event_id is UNIQUE for idempotency: PayMongo retries
-- webhooks, and without this you will double-credit fares. This is the
-- single most common integration bug in student payment work.
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    payment_id        CHAR(36)      NOT NULL,
    booking_id        CHAR(36)      NOT NULL,
    provider          ENUM('paymongo','cash','physical_ticket') NOT NULL,
    method            ENUM('gcash','maya','card','cash') NULL,
    provider_ref_id   VARCHAR(128)  NULL,   -- PayMongo payment intent id
    provider_event_id VARCHAR(128)  NULL,   -- webhook event id (idempotency key)
    amount            DECIMAL(10,2) NOT NULL,
    status            ENUM('pending','paid','failed','refunded','voided')
                      NOT NULL DEFAULT 'pending',
    paid_at           DATETIME(6)   NULL,
    raw_payload       JSON          NULL,   -- keep the webhook body for audit
    created_at        DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (payment_id),
    UNIQUE KEY uq_provider_event (provider_event_id),
    KEY idx_payment_booking (booking_id),
    KEY idx_payment_status (status, paid_at),
    CONSTRAINT fk_payment_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- check_ins -- geofenced presence validation
--
-- Store the raw coordinate AND the computed distance AND the verdict.
-- You need all three: the verdict for business logic, the distance for
-- your accuracy analysis in the Results chapter.
-- ---------------------------------------------------------------------
CREATE TABLE check_ins (
    check_in_id        CHAR(36)     NOT NULL,
    booking_id         CHAR(36)     NOT NULL,
    terminal_id        CHAR(36)     NOT NULL,
    latitude           DECIMAL(8,6) NOT NULL,
    longitude          DECIMAL(9,6) NOT NULL,
    gps_accuracy_m     DECIMAL(6,2) NULL,
    distance_m         DECIMAL(10,2) NOT NULL,
    geofence_radius_m  INT          NOT NULL,
    is_within_geofence BOOLEAN      NOT NULL,
    is_within_window   BOOLEAN      NOT NULL,
    rejection_reason   VARCHAR(255) NULL,
    checked_in_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (check_in_id),
    KEY idx_checkin_booking (booking_id),
    CONSTRAINT fk_checkin_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_checkin_terminal
        FOREIGN KEY (terminal_id) REFERENCES terminals (terminal_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- boarding_scans -- conductor QR validation at each stop
-- ---------------------------------------------------------------------
CREATE TABLE boarding_scans (
    scan_id           CHAR(36)          NOT NULL,
    booking_id        CHAR(36)          NOT NULL,
    scanned_by_user_id CHAR(36)         NOT NULL,
    stop_sequence     SMALLINT UNSIGNED NOT NULL,
    result            ENUM('valid','already_boarded','wrong_trip','wrong_stop',
                           'cancelled','unpaid') NOT NULL,
    scanned_at        DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    -- Set by the offline client; lets you detect and order queued
    -- mutations replayed after a dead zone.
    client_recorded_at DATETIME(6)      NULL,
    synced_at         DATETIME(6)       NULL,
    PRIMARY KEY (scan_id),
    KEY idx_scan_booking (booking_id),
    KEY idx_scan_sync (synced_at),
    CONSTRAINT fk_scan_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_scan_user
        FOREIGN KEY (scanned_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('005_transactions');
