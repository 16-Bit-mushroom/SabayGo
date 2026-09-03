-- =====================================================================
-- 008_cash_remittance.sql
--
-- THE FALSE-LEAKAGE FIX.
--
-- Until now a cash walk-in created a booking with a fare but no payment
-- record. The revenue view read that as money owed and never received --
-- so the system built to detect revenue leakage was manufacturing it,
-- accusing conductors who had done nothing wrong.
--
-- Two changes fix it:
--
--   1. Every cash booking now creates a payment row immediately, marked
--      'pending'. The money exists; it is simply still in the conductor's
--      pocket. That is a different state from missing.
--
--   2. A remittance record tracks the handover at the end of each trip:
--      what the system expected, what the crew declared, and what the
--      office actually counted. The gap between declared and received is
--      the only number that should ever be called a shortage.
--
-- Remittance happens per trip, at the end of the trip, per crew member --
-- matching how the cooperative already works.
-- =====================================================================

CREATE TABLE cash_remittances (
    remittance_id       CHAR(36)      NOT NULL,
    trip_id             CHAR(36)      NOT NULL,
    -- The conductor or driver who took the cash.
    collected_by_user_id CHAR(36)     NOT NULL,

    -- What the system's own records say they should be holding: the sum
    -- of every cash booking they logged on this trip. Computed, never
    -- typed -- this is the figure the crew is measured against.
    expected_amount     DECIMAL(10,2) NOT NULL,
    -- What the crew says they are handing over.
    declared_amount     DECIMAL(10,2) NULL,
    -- What the office actually counted.
    received_amount     DECIMAL(10,2) NULL,
    -- received - expected. Negative is a shortage.
    variance            DECIMAL(10,2) NULL,

    status              ENUM('pending','submitted','received','disputed')
                        NOT NULL DEFAULT 'pending',
    submitted_at        DATETIME(6)   NULL,
    received_at         DATETIME(6)   NULL,
    received_by_user_id CHAR(36)      NULL,
    notes               VARCHAR(512)  NULL,
    created_at          DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at          DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                      ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (remittance_id),
    -- One remittance per crew member per trip. A conductor and a driver
    -- who both took cash on the same run each hand over separately.
    UNIQUE KEY uq_remittance_trip_crew (trip_id, collected_by_user_id),
    KEY idx_remittance_status (status, created_at),
    KEY idx_remittance_crew (collected_by_user_id, created_at),
    CONSTRAINT fk_remittance_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_remittance_collector
        FOREIGN KEY (collected_by_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_remittance_receiver
        FOREIGN KEY (received_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;

-- Which bookings a remittance covers. Without this the office cannot
-- answer "which fares are in this handover?" -- and a conductor disputing
-- a shortage has nothing to point at.
ALTER TABLE payments
    ADD COLUMN remittance_id CHAR(36) NULL AFTER booking_id,
    ADD CONSTRAINT fk_payment_remittance
        FOREIGN KEY (remittance_id) REFERENCES cash_remittances (remittance_id)
        ON DELETE SET NULL;

CREATE INDEX idx_payment_remittance ON payments (remittance_id);

-- ---------------------------------------------------------------------
-- Backfill: existing cash bookings have no payment row at all.
-- ---------------------------------------------------------------------
INSERT INTO payments
    (payment_id, booking_id, provider, method, amount, status, created_at)
SELECT
    UUID(), b.booking_id, 'cash', 'cash', b.fare_amount, 'pending', NOW(6)
FROM bookings b
LEFT JOIN payments p ON p.booking_id = b.booking_id
WHERE b.booking_type IN ('walk_in', 'driver_issued')
  AND p.payment_id IS NULL;

-- ---------------------------------------------------------------------
-- Revenue view, corrected.
--
-- The old view had one bucket for money in and one for money owed, so
-- cash-in-hand fell into "unreconciled" alongside genuine shortfalls.
-- Three buckets are needed:
--
--   collected_fare    settled -- online payments, plus remitted cash
--   cash_in_hand      collected but not yet handed over. NOT a problem
--   unreconciled      expected minus both of the above. THIS is the
--                     number worth investigating
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_trip_revenue_reconciliation AS
SELECT
    t.trip_id,
    t.service_date,
    t.departure_datetime,
    r.route_name,
    v.plate_number,
    t.seat_capacity,
    COUNT(DISTINCT b.booking_id)                       AS total_bookings,
    COALESCE(SUM(b.booking_type = 'app'), 0)           AS app_bookings,
    COALESCE(SUM(b.booking_type IN ('walk_in','driver_issued')), 0)
                                                       AS walkin_bookings,
    COALESCE(SUM(b.is_roadside_pickup), 0)             AS roadside_bookings,
    COALESCE(SUM(b.fare_is_manual), 0)                 AS manual_fare_bookings,

    COALESCE(SUM(CASE WHEN p.status = 'paid' THEN p.amount END), 0)
                                                       AS collected_fare,
    COALESCE(SUM(CASE WHEN p.provider = 'cash' AND p.status = 'pending'
                      THEN p.amount END), 0)           AS cash_in_hand,
    COALESCE(SUM(b.fare_amount), 0)                    AS expected_fare,
    COALESCE(SUM(b.fare_amount), 0)
      - COALESCE(SUM(CASE WHEN p.status = 'paid' THEN p.amount END), 0)
      - COALESCE(SUM(CASE WHEN p.provider = 'cash' AND p.status = 'pending'
                          THEN p.amount END), 0)       AS unreconciled_amount,

    COALESCE(MAX(y.variance), 0)                       AS max_yolo_variance,
    COALESCE(SUM(y.resolution_status = 'pending'), 0)  AS pending_audits
FROM trips t
JOIN routes r        ON r.route_id = t.route_id
LEFT JOIN vans v     ON v.van_id   = t.van_id
LEFT JOIN bookings b ON b.trip_id  = t.trip_id
                    AND b.status NOT IN ('cancelled','rescheduled')
LEFT JOIN payments p ON p.booking_id = b.booking_id
LEFT JOIN yolov8_audit_logs y ON y.trip_id = t.trip_id
GROUP BY t.trip_id, t.service_date, t.departure_datetime,
         r.route_name, v.plate_number, t.seat_capacity;

INSERT INTO schema_migrations (version) VALUES ('008_cash_remittance');
