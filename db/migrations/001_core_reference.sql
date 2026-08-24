-- =====================================================================
-- 001_core_reference.sql
-- Policy configuration, terminals, routes, ordered stops, fare matrix.
-- =====================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(64) PRIMARY KEY,
    applied_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- cooperative_policies
--
-- Every value A2Z has not decided yet lives HERE as a row, never as a
-- column or a constant. When the pitch produces answers you run an
-- UPDATE, not a migration. This is what keeps the pitch from blocking
-- development.
-- ---------------------------------------------------------------------
CREATE TABLE cooperative_policies (
    policy_key    VARCHAR(64)  NOT NULL,
    policy_value  VARCHAR(255) NOT NULL,
    data_type     ENUM('int','decimal','bool','string') NOT NULL,
    description   VARCHAR(255) NOT NULL,
    updated_at    DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                               ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (policy_key)
) ENGINE=InnoDB;

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('reschedule_cutoff_hours',      '6',     'int',     'Hours before departure after which reschedule is refused'),
    ('max_reschedules_per_booking',  '1',     'int',     'How many times one booking may be moved'),
    ('refund_enabled',               'false', 'bool',    'Cooperative policy: no cash refunds, reschedule only'),
    ('advance_booking_seat_cap',     '10',    'int',     'Seats of the 14 sellable in-app; remainder held for walk-in'),
    ('advance_booking_open_days',    '7',     'int',     'How far ahead passengers may book'),
    ('walkin_info_required',         'false', 'bool',    'Walk-in passenger details optional (receipt purposes only)'),
    ('checkin_window_minutes',       '45',    'int',     'Minutes before departure that geofence check-in opens'),
    ('default_geofence_radius_m',    '150',   'int',     'Default check-in radius when a terminal does not override'),
    ('seat_hold_ttl_seconds',        '600',   'int',     'How long a seat stays held awaiting payment'),
    ('default_seat_capacity',        '14',    'int',     'LTFRB-regulated UV Express capacity'),
    ('variance_alert_threshold',     '1',     'int',     'YOLOv8 headcount variance that triggers an operator alert');

-- ---------------------------------------------------------------------
-- terminals
-- ---------------------------------------------------------------------
CREATE TABLE terminals (
    terminal_id        CHAR(36)     NOT NULL,
    terminal_name      VARCHAR(255) NOT NULL,
    city               VARCHAR(100) NOT NULL,
    location_address   VARCHAR(255) NULL,
    latitude           DECIMAL(8,6) NOT NULL,
    longitude          DECIMAL(9,6) NOT NULL,
    -- Per-terminal override; NULL falls back to default_geofence_radius_m.
    geofence_radius_m  INT          NULL,
    -- Consultation: intermediate stops may be driver-only (no conductor).
    is_staffed         BOOLEAN      NOT NULL DEFAULT TRUE,
    is_active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (terminal_id),
    UNIQUE KEY uq_terminal_name_city (terminal_name, city),
    CONSTRAINT chk_terminal_lat CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_terminal_lng CHECK (longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- routes
-- ---------------------------------------------------------------------
CREATE TABLE routes (
    route_id       CHAR(36)     NOT NULL,
    route_code     VARCHAR(32)  NOT NULL,
    route_name     VARCHAR(255) NOT NULL,
    ltfrb_case_no  VARCHAR(64)  NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (route_id),
    UNIQUE KEY uq_route_code (route_code)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- route_stops
--
-- The ordered stop sequence. This table is what makes segment-based
-- booking possible at all -- your old schema had only origin/destination
-- columns, which cannot express "board at stop 2, alight at stop 4".
--
-- stop_sequence is 1-based and must be contiguous per route.
-- ---------------------------------------------------------------------
CREATE TABLE route_stops (
    route_stop_id   CHAR(36)          NOT NULL,
    route_id        CHAR(36)          NOT NULL,
    terminal_id     CHAR(36)          NOT NULL,
    stop_sequence   SMALLINT UNSIGNED NOT NULL,
    -- Minutes from route origin; used to derive per-stop departure times.
    offset_minutes  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (route_stop_id),
    UNIQUE KEY uq_route_sequence (route_id, stop_sequence),
    UNIQUE KEY uq_route_terminal (route_id, terminal_id),
    KEY idx_route_stops_terminal (terminal_id),
    CONSTRAINT fk_route_stops_route
        FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
    CONSTRAINT fk_route_stops_terminal
        FOREIGN KEY (terminal_id) REFERENCES terminals (terminal_id),
    CONSTRAINT chk_stop_sequence CHECK (stop_sequence >= 1)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- fare_matrix
--
-- The pairwise terminal fare matrix your manuscript claims but your old
-- schema never had (it stored a single StandardFare per trip).
-- effective_from lets you raise fares without destroying trip history.
-- ---------------------------------------------------------------------
CREATE TABLE fare_matrix (
    fare_id             CHAR(36)          NOT NULL,
    route_id            CHAR(36)          NOT NULL,
    from_stop_sequence  SMALLINT UNSIGNED NOT NULL,
    to_stop_sequence    SMALLINT UNSIGNED NOT NULL,
    fare_amount         DECIMAL(10,2)     NOT NULL,
    effective_from      DATE              NOT NULL,
    PRIMARY KEY (fare_id),
    UNIQUE KEY uq_fare_pair (route_id, from_stop_sequence, to_stop_sequence, effective_from),
    CONSTRAINT fk_fare_route
        FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
    CONSTRAINT chk_fare_direction CHECK (to_stop_sequence > from_stop_sequence),
    CONSTRAINT chk_fare_positive  CHECK (fare_amount >= 0)
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('001_core_reference');
