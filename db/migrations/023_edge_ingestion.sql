-- =====================================================================
-- 023_edge_ingestion.sql
--
-- Paper revision 468, brief step 5: what the edge phone sends the
-- server. Three additions the paper's data dictionary does not model
-- (decided 14 Oct; the ERD redraw, Figure 7, should show them):
--
--   edge_devices.token_hash   Each phone authenticates with its own
--                             token, issued when the Terminal Manager adds
--                             it to the pool and stored as a SHA-256. A
--                             lost phone is revoked alone, not by
--                             re-keying every unit (the shared tracker
--                             key's weakness, 011).
--   device_heartbeats         Every status report, not only the latest on
--                             edge_devices. The Unaudited rule (brief 4.4)
--                             is decided from them: a gap the phone's
--                             stored reports cover after it reconnects is
--                             a gap in mobile data, not a camera off.
--   held_door_events          A door event from a van with no trip it can
--                             belong to (brief 4.2 rule 12) waits here,
--                             outside the ledger: passenger_events.trip_id
--                             is NOT NULL. It moves, keeping its event_id,
--                             when a trip of that van is started.
--
-- event_id is generated on the phone, so an upload the phone retries
-- after a dropped connection is recognised and not stored twice.
--
-- Reverse: db/migrations/down/023_edge_ingestion.sql (drops the tables
-- and the token; held events and heartbeat history are lost).
-- =====================================================================

ALTER TABLE edge_devices
    ADD COLUMN token_hash      CHAR(64)    NULL AFTER app_version,
    ADD COLUMN token_issued_at DATETIME(6) NULL AFTER token_hash,
    ADD UNIQUE KEY uq_device_token (token_hash);

CREATE TABLE device_heartbeats (
    heartbeat_id       BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    device_id          CHAR(36)          NOT NULL,
    -- The phone's clock, synchronised to the server's (GET /edge/session).
    recorded_at        DATETIME(6)       NOT NULL,
    received_at        DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    battery_pct        TINYINT UNSIGNED  NULL,
    battery_temp_c     DECIMAL(4,1)      NULL,
    charging           BOOLEAN           NULL,
    camera_ok          BOOLEAN           NOT NULL,
    gps_ok             BOOLEAN           NOT NULL,
    -- The camera works but sees nothing: a frame that stays dark or still.
    lens_blocked       BOOLEAN           NOT NULL DEFAULT FALSE,
    -- Measured on the phone; no rate is assumed anywhere else.
    detection_rate_hz  DECIMAL(5,2)      NULL,
    PRIMARY KEY (heartbeat_id),
    -- A stored report sent again after a reconnect is the same report.
    UNIQUE KEY uq_heartbeat (device_id, recorded_at),
    CONSTRAINT fk_heartbeat_device
        FOREIGN KEY (device_id) REFERENCES edge_devices (device_id),
    CONSTRAINT chk_heartbeat_battery CHECK (battery_pct <= 100)
);

CREATE TABLE held_door_events (
    event_id         CHAR(36)          NOT NULL,
    device_id        CHAR(36)          NOT NULL,
    -- The van the phone was checked out with at event_at.
    van_id           CHAR(36)          NOT NULL,
    event_type       ENUM('board','alight') NOT NULL,
    event_at         DATETIME(6)       NOT NULL,
    latitude         DECIMAL(8,6)      NULL,
    longitude        DECIMAL(9,6)      NULL,
    occupancy_after  TINYINT UNSIGNED  NULL,
    track_id         INT UNSIGNED      NULL,
    snapshot_url     VARCHAR(512)      NULL,
    snapshot_hash    CHAR(64)          NULL,
    received_at      DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (event_id),
    KEY idx_held_van_time (van_id, event_at),
    CONSTRAINT fk_held_device
        FOREIGN KEY (device_id) REFERENCES edge_devices (device_id),
    CONSTRAINT fk_held_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id)
);

INSERT INTO schema_migrations (version)
VALUES ('023_edge_ingestion');
