-- =====================================================================
-- 011_trip_location_pings.sql
--
-- NAHGM: continuous van position reporting.
--
-- Pings arrive from an in-vehicle tracking unit -- a GPS dongle on the
-- same edge computer that runs the YOLOv8 inference. Deliberately NOT
-- the driver's phone: the subject is the van, and a phone-sourced feed
-- stops when the driver takes a break, swaps handsets, or Android kills
-- the background service.
--
-- The table is append-only and will grow quickly: one row every ten
-- seconds per active van is ~360 rows per van-hour. Fine at pilot scale;
-- a production deployment would partition by service_date and prune.
-- Worth stating in Limitations.
-- =====================================================================

CREATE TABLE trip_location_pings (
    ping_id        BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    trip_id        CHAR(36)          NOT NULL,
    van_id         CHAR(36)          NULL,

    latitude       DECIMAL(8,6)      NOT NULL,
    longitude      DECIMAL(9,6)      NOT NULL,
    -- Straight from the GNSS receiver when available. Kept because a
    -- ping with 200m accuracy should not be treated like one with 5m.
    accuracy_m     DECIMAL(6,2)      NULL,
    speed_kph      DECIMAL(6,2)      NULL,
    heading_deg    DECIMAL(5,2)      NULL,

    -- Map-matching result, computed on ingest so the live map does not
    -- have to recalculate it on every read.
    nearest_stop_sequence SMALLINT UNSIGNED NULL,
    distance_to_stop_m    DECIMAL(10,2)     NULL,

    -- When the device took the reading, versus when the server stored
    -- it. A unit that buffers through a dead zone and uploads later
    -- must not have its history collapsed to the moment of upload.
    recorded_at    DATETIME(6)       NOT NULL,
    received_at    DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    PRIMARY KEY (ping_id),
    KEY idx_ping_trip_time (trip_id, recorded_at DESC),
    KEY idx_ping_van_time (van_id, recorded_at DESC),
    CONSTRAINT fk_ping_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_ping_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id),
    CONSTRAINT chk_ping_lat CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_ping_lng CHECK (longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

-- How stale a position may be before the map shows it as unknown rather
-- than pretending the last known point is current.
INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('tracking_stale_after_seconds', '120', 'int',
     'Seconds after which a van position is treated as stale, not live.'),
    ('tracking_ping_interval_seconds', '10', 'int',
     'How often an in-vehicle unit should report its position.')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO schema_migrations (version) VALUES ('011_trip_location_pings');