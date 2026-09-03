-- =====================================================================
-- 006_audit_and_alerts.sql
--
-- The revenue-assurance layer. Your manuscript describes all of this in
-- detail (section 2.3.3) but your old schema contained none of it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- yolov8_audit_logs
-- ---------------------------------------------------------------------
CREATE TABLE yolov8_audit_logs (
    audit_id           CHAR(36)          NOT NULL,
    trip_id            CHAR(36)          NOT NULL,
    leg_sequence       SMALLINT UNSIGNED NULL,   -- where in the route
    triggered_by_user_id CHAR(36)        NULL,   -- NULL => automatic trigger
    trigger_type       ENUM('manual','door_close','gps_node','scheduled') NOT NULL DEFAULT 'manual',

    visual_count       SMALLINT UNSIGNED NOT NULL,   -- C_visual
    booked_count       SMALLINT UNSIGNED NOT NULL,   -- C_booked
    -- Signed on purpose: negative variance (fewer bodies than tickets)
    -- is a different anomaly from positive, and you want to tell them
    -- apart in the Results chapter.
    variance           SMALLINT          NOT NULL,

    model_version      VARCHAR(32)       NULL,       -- e.g. 'yolov8n-1.0'
    inference_ms       INT UNSIGNED      NULL,       -- for your performance table
    confidence_avg     DECIMAL(4,3)      NULL,
    snapshot_url       VARCHAR(512)      NULL,       -- annotated, privacy-blurred

    resolution_status  ENUM('reconciled','pending','resolved','ignored','failed')
                       NOT NULL DEFAULT 'pending',
    resolved_by_user_id CHAR(36)         NULL,
    resolved_at        DATETIME(6)       NULL,
    resolution_notes   VARCHAR(512)      NULL,

    captured_at        DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (audit_id),
    KEY idx_audit_trip (trip_id, captured_at),
    KEY idx_audit_pending (resolution_status, captured_at),
    CONSTRAINT fk_audit_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_audit_trigger_user
        FOREIGN KEY (triggered_by_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_audit_resolver
        FOREIGN KEY (resolved_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ticket_booklets / physical_tickets
--
-- The "self-counting" control: tickets issued must equal tickets
-- scanned plus tickets remaining. Pre-registered serials mean a driver
-- cannot invent a ticket after the fact.
-- ---------------------------------------------------------------------
CREATE TABLE ticket_booklets (
    booklet_id         CHAR(36)     NOT NULL,
    booklet_code       VARCHAR(32)  NOT NULL,
    assigned_to_user_id CHAR(36)    NULL,
    serial_start       INT UNSIGNED NOT NULL,
    serial_end         INT UNSIGNED NOT NULL,
    status             ENUM('unassigned','assigned','exhausted','voided')
                       NOT NULL DEFAULT 'unassigned',
    issued_at          DATETIME(6)  NULL,
    created_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (booklet_id),
    UNIQUE KEY uq_booklet_code (booklet_code),
    CONSTRAINT fk_booklet_user
        FOREIGN KEY (assigned_to_user_id) REFERENCES users (user_id),
    CONSTRAINT chk_booklet_range CHECK (serial_end >= serial_start)
) ENGINE=InnoDB;

CREATE TABLE physical_tickets (
    physical_ticket_id CHAR(36)     NOT NULL,
    booklet_id         CHAR(36)     NOT NULL,
    serial_number      INT UNSIGNED NOT NULL,
    qr_payload         VARCHAR(255) NOT NULL,
    status             ENUM('unissued','issued','scanned','void') NOT NULL DEFAULT 'unissued',
    booking_id         CHAR(36)     NULL,
    issued_at          DATETIME(6)  NULL,
    scanned_at         DATETIME(6)  NULL,
    PRIMARY KEY (physical_ticket_id),
    UNIQUE KEY uq_booklet_serial (booklet_id, serial_number),
    UNIQUE KEY uq_physical_qr (qr_payload),
    KEY idx_physical_status (status),
    CONSTRAINT fk_physical_booklet
        FOREIGN KEY (booklet_id) REFERENCES ticket_booklets (booklet_id) ON DELETE CASCADE,
    CONSTRAINT fk_physical_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- driver_headcounts -- the single-input confirmation before departure
-- ---------------------------------------------------------------------
CREATE TABLE driver_headcounts (
    headcount_id       CHAR(36)          NOT NULL,
    trip_id            CHAR(36)          NOT NULL,
    stop_sequence      SMALLINT UNSIGNED NOT NULL,
    confirmed_count    SMALLINT UNSIGNED NOT NULL,
    manifest_count     SMALLINT UNSIGNED NOT NULL,
    variance           SMALLINT          NOT NULL,
    confirmed_by_user_id CHAR(36)        NOT NULL,
    confirmed_at       DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    client_recorded_at DATETIME(6)       NULL,
    synced_at          DATETIME(6)       NULL,
    PRIMARY KEY (headcount_id),
    UNIQUE KEY uq_headcount_stop (trip_id, stop_sequence),
    CONSTRAINT fk_headcount_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_headcount_user
        FOREIGN KEY (confirmed_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- notifications
--
-- Consultation: "Different objective for notification (alert) -
-- automated alert notif for manager and driver."
--
-- `audience` is what lets one table serve both the passenger inbox and
-- the operational alert stream. Split your objective 1.3.2.6 along this
-- same line when you rewrite it.
-- ---------------------------------------------------------------------
CREATE TABLE notifications (
    notification_id CHAR(36)     NOT NULL,
    user_id         CHAR(36)     NOT NULL,
    audience        ENUM('passenger','operator','driver','conductor') NOT NULL,
    type            ENUM('trip_update','tailored_schedule','system_alert',
                         'terminal_policy','variance_alert','unremitted_fare',
                         'departure_reminder','schedule_change') NOT NULL,
    title           VARCHAR(100) NOT NULL,
    message         VARCHAR(500) NOT NULL,
    -- Loose pointer to whatever triggered it (trip_id, audit_id, ...).
    related_entity_type VARCHAR(32) NULL,
    related_entity_id   CHAR(36)    NULL,
    is_read         BOOLEAN      NOT NULL DEFAULT FALSE,
    fcm_message_id  VARCHAR(128) NULL,
    delivery_status ENUM('queued','sent','failed') NOT NULL DEFAULT 'queued',
    created_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (notification_id),
    KEY idx_notif_user_unread (user_id, is_read, created_at),
    KEY idx_notif_audience (audience, type, created_at),
    CONSTRAINT fk_notif_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Convenience view: per-trip revenue reconciliation.
-- Backs the operator dashboard without hand-writing the join each time.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_trip_revenue_reconciliation AS
SELECT
    t.trip_id,
    t.service_date,
    t.departure_datetime,
    r.route_name,
    v.plate_number,
    t.seat_capacity,
    COUNT(DISTINCT b.booking_id)                                    AS total_bookings,
    COALESCE(SUM(b.booking_type = 'app'), 0)                                     AS app_bookings,
    COALESCE(SUM(b.booking_type IN ('walk_in','driver_issued')), 0)              AS walkin_bookings,
    COALESCE(SUM(CASE WHEN p.status = 'paid' THEN p.amount END), 0) AS collected_fare,
    COALESCE(SUM(b.fare_amount), 0)                                 AS expected_fare,
    COALESCE(SUM(b.fare_amount), 0)
        - COALESCE(SUM(CASE WHEN p.status = 'paid' THEN p.amount END), 0) AS unreconciled_amount,
    COALESCE(MAX(y.variance), 0)                                                 AS max_yolo_variance,
    COALESCE(SUM(y.resolution_status = 'pending'), 0)                            AS pending_audits
FROM trips t
JOIN routes r            ON r.route_id = t.route_id
LEFT JOIN vans v         ON v.van_id   = t.van_id
LEFT JOIN bookings b     ON b.trip_id  = t.trip_id
                        AND b.status NOT IN ('cancelled','rescheduled')
LEFT JOIN payments p     ON p.booking_id = b.booking_id
LEFT JOIN yolov8_audit_logs y ON y.trip_id = t.trip_id
GROUP BY t.trip_id, t.service_date, t.departure_datetime,
         r.route_name, v.plate_number, t.seat_capacity;

INSERT INTO schema_migrations (version) VALUES ('006_audit_and_alerts');
