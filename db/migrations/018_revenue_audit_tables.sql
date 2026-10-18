-- =====================================================================
-- 018_revenue_audit_tables.sql
--
-- New tables of paper revision 468 (change brief 7.2, Tables 25-39),
-- reconciled with the repo. Paper name -> repo name:
--
--   28 Route_Stretches        route_stretches
--   29 Passenger_Events       passenger_events
--   30 Driving_Events         driving_events
--   31 Nahgm_tracking_logs    trip_location_pings (011), two columns added
--   32 Remittances            remittances (daily, per van; supersedes the
--                             per-trip cash_remittances of 008)
--   34 Special_Trip_Requests  special_trip_requests
--   35 Remittance_Lines       remittance_lines
--   36 Data_Transfers         data_transfers (+ operators.import_batch_id,
--                             deferred from 017)
--   37 Edge_Devices           edge_devices
--   38 Device_Checkouts       device_checkouts
--   39 Disputes               disputes
--
-- Column mapping that holds throughout:
--   ScheduleID                       -> trip_id
--   TerminalStaff / Dispatchers FKs  -> users.user_id (one login table)
--   RouteCode                        -> route_id
--   a stop on a trip's route         -> its stop sequence, as in bookings
--   ENUM values                      -> lower snake case, as everywhere
--
-- Not here, deliberately:
--   25 Operators         017.
--   26 TerminalStaff     users + staff_profiles (decided 13 Oct).
--   27 Fare_Matrix       exists, keyed per route by stop sequence; the
--                        brief keys it by terminal pair. Booking reads it,
--                        so the change goes with the code that uses it.
--   33 TerminalSettings  cooperative_policies gains effective_from in the
--                        settings step: its key changes, and so does
--                        every read of a policy.
--   7.3 edits            trip start/review/audit columns, booking and van
--                        columns, notification recipients: a later
--                        migration.
--
-- Structure only: nothing writes to these tables yet, so no ORM models.
--
-- Reverse: db/migrations/down/018_revenue_audit_tables.sql
-- =====================================================================

-- ------------------------------------------------------ data_transfers
-- Table 36. Every roster import and export, with its row counts.
CREATE TABLE data_transfers (
    transfer_id      CHAR(36)     NOT NULL,
    direction        ENUM('import','export') NOT NULL,
    record_type      ENUM('operators','vans','dispatchers') NOT NULL,
    file_name        VARCHAR(255) NOT NULL,
    file_format      ENUM('csv','xlsx','pdf') NOT NULL,
    -- Exports only: a backup, or the LTFRB cross-check list (brief 8).
    export_purpose   ENUM('backup','ltfrb_check','other') NULL,
    rows_in_file     INT UNSIGNED NOT NULL,
    rows_accepted    INT UNSIGNED NOT NULL DEFAULT 0,
    rows_rejected    INT UNSIGNED NOT NULL DEFAULT 0,
    -- The rejected rows with their reasons, for correction and re-upload.
    error_file_url   VARCHAR(512) NULL,
    performed_by     CHAR(36)     NOT NULL,
    performed_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (transfer_id),
    KEY idx_transfer_time (performed_at),
    CONSTRAINT fk_transfer_performed_by
        FOREIGN KEY (performed_by) REFERENCES users (user_id),
    CONSTRAINT chk_transfer_purpose
        CHECK ((direction = 'export') = (export_purpose IS NOT NULL)),
    -- Import is from the CSV or Excel template; PDF is export only.
    CONSTRAINT chk_transfer_import_format
        CHECK (direction = 'export' OR file_format IN ('csv','xlsx')),
    CONSTRAINT chk_transfer_rows
        CHECK (rows_accepted + rows_rejected <= rows_in_file)
) ENGINE=InnoDB;

-- The column 017 left out until this table existed.
ALTER TABLE operators
    ADD COLUMN import_batch_id CHAR(36) NULL AFTER validated_at,
    ADD CONSTRAINT fk_operator_import_batch
        FOREIGN KEY (import_batch_id) REFERENCES data_transfers (transfer_id);

-- ----------------------------------------------------- route_stretches
-- Table 28. Stretch k runs from stop k to stop k+1, exactly as leg k of
-- a trip does (trip_legs, 004): this is the route's geometry and limits,
-- trip_legs is one trip's capacity. The brief's FromTerminalID and
-- ToTerminalID are the terminals at those two stops in route_stops; both
-- stops must exist, which the two foreign keys enforce, rather than
-- copying terminal ids that could drift from the stop list.
CREATE TABLE route_stretches (
    stretch_id          CHAR(36)          NOT NULL,
    route_id            CHAR(36)          NOT NULL,
    stretch_no          SMALLINT UNSIGNED NOT NULL,
    to_stop_sequence    SMALLINT UNSIGNED AS (stretch_no + 1) STORED,
    -- Along the route line from the starting terminal (NAHGM, brief 6.3).
    from_distance_m     DECIMAL(10,2)     NOT NULL,
    length_m            DECIMAL(10,2)     NOT NULL,
    speed_limit_kmh     SMALLINT UNSIGNED NOT NULL,
    stop_zone_radius_m  SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    -- (length - stop-zone radius at each end) / expected average speed.
    -- Stored, because the speed is a dated setting, not a column here.
    expected_time_s     INT UNSIGNED      NOT NULL,
    created_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                          ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (stretch_id),
    UNIQUE KEY uq_route_stretch (route_id, stretch_no),
    CONSTRAINT fk_stretch_from_stop
        FOREIGN KEY (route_id, stretch_no)
        REFERENCES route_stops (route_id, stop_sequence),
    CONSTRAINT fk_stretch_to_stop
        FOREIGN KEY (route_id, to_stop_sequence)
        REFERENCES route_stops (route_id, stop_sequence),
    CONSTRAINT chk_stretch_length CHECK (length_m > 0),
    CONSTRAINT chk_stretch_zone CHECK (stop_zone_radius_m > 0),
    CONSTRAINT chk_stretch_limit CHECK (speed_limit_kmh > 0)
) ENGINE=InnoDB;

-- ------------------------------------------------- trip_location_pings
-- Table 31 is this table (011). NAHGM snaps each reading to the route
-- line; these hold where that put it. NULL until snapped, and on rows
-- recorded before this migration.
ALTER TABLE trip_location_pings
    ADD COLUMN distance_from_start_m DECIMAL(10,2) NULL AFTER heading_deg,
    ADD COLUMN stretch_no SMALLINT UNSIGNED NULL AFTER distance_from_start_m;

-- -------------------------------------------------------- edge_devices
-- Table 37. The terminal's phone pool. No van_id: which van a phone is
-- in is its open device_checkouts row. No is_active: a retired phone
-- keeps its row with status 'retired', because its events still name it.
CREATE TABLE edge_devices (
    device_id          CHAR(36)          NOT NULL,
    device_model       VARCHAR(100)      NOT NULL,
    android_version    VARCHAR(20)       NULL,
    app_version        VARCHAR(20)       NULL,
    status             ENUM('in_office','checked_out','retired')
                       NOT NULL DEFAULT 'in_office',
    registered_by      CHAR(36)          NOT NULL,
    registered_at      DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    -- The latest status report (brief 4.4). NULL until the first one.
    last_heartbeat_at  DATETIME(6)       NULL,
    battery_pct        TINYINT UNSIGNED  NULL,
    battery_temp_c     DECIMAL(4,1)      NULL,
    camera_ok          BOOLEAN           NULL,
    gps_ok             BOOLEAN           NULL,
    PRIMARY KEY (device_id),
    KEY idx_device_status (status),
    CONSTRAINT fk_device_registered_by
        FOREIGN KEY (registered_by) REFERENCES users (user_id),
    CONSTRAINT chk_device_battery CHECK (battery_pct <= 100)
) ENGINE=InnoDB;

-- ---------------------------------------------------- device_checkouts
-- Table 38. Each time a phone leaves the office with a Dispatcher for a
-- van, and comes back. Open = returned_at IS NULL.
CREATE TABLE device_checkouts (
    checkout_id     CHAR(36)     NOT NULL,
    device_id       CHAR(36)     NOT NULL,
    van_id          CHAR(36)     NOT NULL,
    dispatcher_id   CHAR(36)     NOT NULL,
    checked_out_by  CHAR(36)     NOT NULL,
    checked_out_at  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    returned_by     CHAR(36)     NULL,
    returned_at     DATETIME(6)  NULL,
    -- The phone's condition on return.
    return_note     VARCHAR(255) NULL,
    PRIMARY KEY (checkout_id),
    KEY idx_checkout_device_time (device_id, checked_out_at),
    KEY idx_checkout_van_time (van_id, checked_out_at),
    CONSTRAINT fk_checkout_device
        FOREIGN KEY (device_id) REFERENCES edge_devices (device_id),
    CONSTRAINT fk_checkout_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id),
    CONSTRAINT fk_checkout_dispatcher
        FOREIGN KEY (dispatcher_id) REFERENCES users (user_id),
    CONSTRAINT fk_checkout_by
        FOREIGN KEY (checked_out_by) REFERENCES users (user_id),
    CONSTRAINT fk_checkout_returned_by
        FOREIGN KEY (returned_by) REFERENCES users (user_id),
    CONSTRAINT chk_checkout_return
        CHECK ((returned_at IS NULL) = (returned_by IS NULL)),
    CONSTRAINT chk_checkout_return_time
        CHECK (returned_at IS NULL OR returned_at >= checked_out_at)
) ENGINE=InnoDB;

-- One open check-out per phone and per van (brief 5.3). MySQL has no
-- partial index; a closed row maps to NULL, which a UNIQUE index
-- ignores. Needs 8.0.13+. The server matches each door event to a van
-- through this row, so two open rows would make that match ambiguous.
CREATE UNIQUE INDEX uq_open_checkout_device
    ON device_checkouts ((CASE WHEN returned_at IS NULL THEN device_id END));
CREATE UNIQUE INDEX uq_open_checkout_van
    ON device_checkouts ((CASE WHEN returned_at IS NULL THEN van_id END));

-- ---------------------------------------------------- passenger_events
-- Table 29. One row per door event, the ledger the revenue audit reads.
-- No cascade from trips: evidence in a hash chain is never deleted with
-- its parent. Retention deletes the snapshot file only (brief 4.5).
CREATE TABLE passenger_events (
    -- Generated on the phone, so a batch re-sent after a lost response
    -- lands on the same key instead of a second event.
    event_id               CHAR(36)          NOT NULL,
    trip_id                CHAR(36)          NOT NULL,
    device_id              CHAR(36)          NOT NULL,
    event_type             ENUM('board','alight') NOT NULL,
    event_at               DATETIME(6)       NOT NULL,
    -- NAHGM geotag (brief 6.3): interpolated between GPS readings and
    -- snapped to the route. NULL until geotagged.
    latitude               DECIMAL(8,6)      NULL,
    longitude              DECIMAL(9,6)      NULL,
    distance_from_start_m  DECIMAL(10,2)     NULL,
    stretch_no             SMALLINT UNSIGNED NULL,
    nearest_stop_sequence  SMALLINT UNSIGNED NULL,
    nearest_stop_dist_m    DECIMAL(10,2)     NULL,
    -- Boarded outside every stop zone (brief 2.4). Separate from matching.
    side_pickup            BOOLEAN           NOT NULL DEFAULT FALSE,
    -- Not capped at capacity: above 14 is the capacity alert.
    occupancy_after        TINYINT UNSIGNED  NULL,
    -- Tracker id within the trip. Not a passenger identity.
    track_id               INT UNSIGNED      NULL,
    -- Brief 6.1. NULL until matched. The paper's MatchedBookingID and
    -- MatchedLogEntryID are one column here: a Dispatcher's cash log is a
    -- walk-in booking, so both point at bookings.
    match_status           ENUM('matched_qr','matched_log','unrecorded','mismatch') NULL,
    matched_booking_id     CHAR(36)          NULL,
    -- Where an unrecorded boarding was matched to have got off (FIFO).
    dest_stop_sequence     SMALLINT UNSIGNED NULL,
    estimated_fare         DECIMAL(10,2)     NULL,
    -- Blurred still. The URL goes NULL when retention deletes the file;
    -- the hash stays, so the chain still verifies (brief 4.5).
    snapshot_url           VARCHAR(512)      NULL,
    snapshot_hash          CHAR(64)          NULL,
    snapshot_deleted_at    DATETIME(6)       NULL,
    -- SHA-256 over this event's fields (incl. snapshot_hash) and the
    -- previous event's hash on the same trip. Computed by the server.
    event_hash             CHAR(64)          NULL,
    -- The Terminal Manager's decision on an unrecorded boarding.
    resolution_status      ENUM('pending','confirmed','dismissed') NULL,
    resolved_by            CHAR(36)          NULL,
    resolved_at            DATETIME(6)       NULL,
    created_at             DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (event_id),
    UNIQUE KEY uq_event_hash (event_hash),
    KEY idx_event_trip_time (trip_id, event_at),
    KEY idx_event_device_time (device_id, event_at),
    KEY idx_event_resolution (resolution_status),
    CONSTRAINT fk_event_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_event_device
        FOREIGN KEY (device_id) REFERENCES edge_devices (device_id),
    CONSTRAINT fk_event_booking
        FOREIGN KEY (matched_booking_id) REFERENCES bookings (booking_id),
    CONSTRAINT fk_event_resolved_by
        FOREIGN KEY (resolved_by) REFERENCES users (user_id),
    -- A matched event names its record; nothing else does.
    CONSTRAINT chk_event_matched_has_booking
        CHECK (match_status NOT IN ('matched_qr','matched_log')
               OR matched_booking_id IS NOT NULL),
    CONSTRAINT chk_event_booking_only_if_matched
        CHECK (matched_booking_id IS NULL
               OR match_status IN ('matched_qr','matched_log')),
    -- Only an unrecorded boarding is priced, and only it is decided.
    CONSTRAINT chk_event_estimate
        CHECK (estimated_fare IS NULL
               OR (match_status = 'unrecorded' AND estimated_fare >= 0)),
    CONSTRAINT chk_event_resolution
        CHECK (resolution_status IS NULL OR match_status = 'unrecorded'),
    -- Both decisions are logged with the user and the time (brief 2.1).
    CONSTRAINT chk_event_resolved_by
        CHECK (resolution_status NOT IN ('confirmed','dismissed')
               OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    CONSTRAINT chk_event_resolved_state
        CHECK (resolved_at IS NULL
               OR resolution_status IN ('confirmed','dismissed')),
    CONSTRAINT chk_event_snapshot_hash
        CHECK (snapshot_url IS NULL OR snapshot_hash IS NOT NULL),
    CONSTRAINT chk_event_snapshot_deleted
        CHECK (snapshot_deleted_at IS NULL OR snapshot_url IS NULL)
) ENGINE=InnoDB;

-- ------------------------------------------------------ driving_events
-- Table 30. Indicators for review, not proof of misconduct (brief 6.4).
-- Kept when retention deletes the GPS readings they came from.
CREATE TABLE driving_events (
    driving_event_id       CHAR(36)          NOT NULL,
    trip_id                CHAR(36)          NOT NULL,
    flag_type              ENUM('overspeed','slow_stretch','unscheduled_stop','en_route_stop')
                           NOT NULL,
    start_at               DATETIME(6)       NOT NULL,
    end_at                 DATETIME(6)       NULL,
    distance_from_start_m  DECIMAL(10,2)     NULL,
    stretch_no             SMALLINT UNSIGNED NULL,
    -- Overspeed.
    max_speed_kmh          DECIMAL(5,1)      NULL,
    limit_kmh              DECIMAL(5,1)      NULL,
    -- Slow stretch: actual over expected time (1.45 in the sample trip).
    time_ratio             DECIMAL(5,2)      NULL,
    -- Unscheduled and en-route stops.
    nearest_stop_dist_m    DECIMAL(10,2)     NULL,
    duration_s             INT UNSIGNED      NULL,
    review_status          ENUM('open','reviewed','dismissed') NOT NULL DEFAULT 'open',
    created_at             DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (driving_event_id),
    KEY idx_driving_trip_time (trip_id, start_at),
    KEY idx_driving_review (review_status),
    CONSTRAINT fk_driving_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT chk_driving_span
        CHECK (end_at IS NULL OR end_at >= start_at)
) ENGINE=InnoDB;

-- ----------------------------------------------- special_trip_requests
-- Table 34. A passenger rents the whole van (brief 2.5). The trip is
-- created when the Terminal Manager approves and sets the fee.
CREATE TABLE special_trip_requests (
    request_id             CHAR(36)          NOT NULL,
    passenger_user_id      CHAR(36)          NOT NULL,
    pickup_at              DATETIME(6)       NOT NULL,
    pickup_address         VARCHAR(255)      NOT NULL,
    pickup_latitude        DECIMAL(8,6)      NULL,
    pickup_longitude       DECIMAL(9,6)      NULL,
    destination_address    VARCHAR(255)      NOT NULL,
    destination_latitude   DECIMAL(8,6)      NULL,
    destination_longitude  DECIMAL(9,6)      NULL,
    passenger_count        TINYINT UNSIGNED  NOT NULL,
    -- Set by the Terminal Manager on approval.
    rental_fee             DECIMAL(10,2)     NULL,
    payment_status         ENUM('unpaid','paid') NOT NULL DEFAULT 'unpaid',
    payment_reference      VARCHAR(64)       NULL,
    status                 ENUM('requested','approved','rejected','completed','cancelled')
                           NOT NULL DEFAULT 'requested',
    trip_id                CHAR(36)          NULL,
    reviewed_by            CHAR(36)          NULL,
    reviewed_at            DATETIME(6)       NULL,
    created_at             DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at             DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                             ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (request_id),
    UNIQUE KEY uq_request_trip (trip_id),
    KEY idx_request_status_pickup (status, pickup_at),
    KEY idx_request_passenger (passenger_user_id, created_at),
    CONSTRAINT fk_request_passenger
        FOREIGN KEY (passenger_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_request_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_request_reviewed_by
        FOREIGN KEY (reviewed_by) REFERENCES users (user_id),
    CONSTRAINT chk_request_count CHECK (passenger_count BETWEEN 1 AND 14),
    CONSTRAINT chk_request_fee CHECK (rental_fee IS NULL OR rental_fee >= 0),
    -- An approved request has its fee, its trip and its reviewer.
    CONSTRAINT chk_request_approved
        CHECK (status NOT IN ('approved','completed')
               OR (rental_fee IS NOT NULL AND trip_id IS NOT NULL
                   AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
    CONSTRAINT chk_request_rejected
        CHECK (status <> 'rejected'
               OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
) ENGINE=InnoDB;

-- --------------------------------------------------------- remittances
-- Table 32. The daily statement per van (brief 2.1): the operator keeps
-- the fares and remits rate_pct of gross. Equation (2):
--   remittance_owed = rate x (verified + declared)
--   amount_at_risk  = rate x estimated
-- Stored, not derived: a statement records what was owed when it was
-- issued, and the rate is the one in force on service_date.
CREATE TABLE remittances (
    remittance_id      CHAR(36)       NOT NULL,
    operator_id        CHAR(36)       NOT NULL,
    van_id             CHAR(36)       NOT NULL,
    service_date       DATE           NOT NULL,
    verified_income    DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    declared_income    DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    estimated_income   DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    -- Percent: 15.00 for the brief's rho = 0.15.
    rate_pct           DECIMAL(5,2)   NOT NULL,
    remittance_owed    DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    amount_at_risk     DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    -- Reopened ('settled' -> 'open') when lines arrive after payment;
    -- the later payment adds to settled_amount and its reference is
    -- appended to settlement_ref. One payment slot per statement.
    status             ENUM('open','settled') NOT NULL DEFAULT 'open',
    settled_amount     DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    settled_at         DATETIME(6)    NULL,
    settlement_ref     VARCHAR(255)   NULL,
    -- The Cashier who recorded the payment.
    recorded_by        CHAR(36)       NULL,
    created_at         DATETIME(6)    NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at         DATETIME(6)    NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                      ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (remittance_id),
    UNIQUE KEY uq_remittance_van_day (van_id, service_date),
    KEY idx_remittance_day_status (service_date, status),
    KEY idx_remittance_operator (operator_id, service_date),
    CONSTRAINT fk_remittance_operator
        FOREIGN KEY (operator_id) REFERENCES operators (operator_id),
    CONSTRAINT fk_remittance_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id),
    CONSTRAINT fk_remittance_recorded_by
        FOREIGN KEY (recorded_by) REFERENCES users (user_id),
    CONSTRAINT chk_remittance_amounts
        CHECK (verified_income >= 0 AND declared_income >= 0
               AND estimated_income >= 0 AND remittance_owed >= 0
               AND amount_at_risk >= 0 AND settled_amount >= 0),
    CONSTRAINT chk_remittance_rate CHECK (rate_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_remittance_settled
        CHECK (status = 'open'
               OR (settled_at IS NOT NULL AND recorded_by IS NOT NULL))
) ENGINE=InnoDB;

-- ---------------------------------------------------- remittance_lines
-- Table 35. Fare lines behind a statement: passengers of one trip who
-- boarded at the same terminal, got off at the same terminal and paid
-- the same fare, in one income group (brief 2.2). A rental fee is a line
-- of its own, naming its request.
CREATE TABLE remittance_lines (
    line_id             CHAR(36)          NOT NULL,
    remittance_id       CHAR(36)          NOT NULL,
    trip_id             CHAR(36)          NOT NULL,
    origin_terminal_id  CHAR(36)          NULL,
    dest_terminal_id    CHAR(36)          NULL,
    request_id          CHAR(36)          NULL,
    income_group        ENUM('verified','declared','estimated') NOT NULL,
    fare_per_passenger  DECIMAL(10,2)     NOT NULL,
    passenger_count     SMALLINT UNSIGNED NOT NULL,
    gross_fare          DECIMAL(12,2)     NOT NULL,
    share_amount        DECIMAL(12,2)     NOT NULL,
    created_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (line_id),
    KEY idx_line_remittance (remittance_id, income_group),
    KEY idx_line_trip (trip_id),
    CONSTRAINT fk_line_remittance
        FOREIGN KEY (remittance_id) REFERENCES remittances (remittance_id),
    CONSTRAINT fk_line_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_line_origin
        FOREIGN KEY (origin_terminal_id) REFERENCES terminals (terminal_id),
    CONSTRAINT fk_line_dest
        FOREIGN KEY (dest_terminal_id) REFERENCES terminals (terminal_id),
    CONSTRAINT fk_line_request
        FOREIGN KEY (request_id) REFERENCES special_trip_requests (request_id),
    -- A fixed-route line names both terminals; a rental line its request.
    CONSTRAINT chk_line_kind
        CHECK (request_id IS NOT NULL
               OR (origin_terminal_id IS NOT NULL AND dest_terminal_id IS NOT NULL)),
    CONSTRAINT chk_line_gross
        CHECK (gross_fare = fare_per_passenger * passenger_count),
    CONSTRAINT chk_line_amounts
        CHECK (fare_per_passenger >= 0 AND passenger_count > 0 AND share_amount >= 0)
) ENGINE=InnoDB;

-- ------------------------------------------------------------ disputes
-- Table 39. An operator's contest of one item, raised at the counter
-- before the statement is fully paid (brief 2.1). The brief's
-- RaisedByID has no foreign key because it names one of two staff
-- tables; here both are users, so it has one.
CREATE TABLE disputes (
    dispute_id          CHAR(36)       NOT NULL,
    remittance_id       CHAR(36)       NOT NULL,
    trip_id             CHAR(36)       NOT NULL,
    subject             ENUM('estimated_fare','fare_line','driving_flag') NOT NULL,
    event_id            CHAR(36)       NULL,
    line_id             CHAR(36)       NULL,
    driving_event_id    CHAR(36)       NULL,
    operator_statement  VARCHAR(500)   NOT NULL,
    -- The share that waits: rate x the item's fare. 0.00 for a driving
    -- flag, which withholds nothing.
    amount_disputed     DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    raised_by_role      ENUM('dispatcher','cashier','terminal_manager') NOT NULL,
    raised_by           CHAR(36)       NOT NULL,
    raised_at           DATETIME(6)    NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    status              ENUM('open','resolved','withdrawn') NOT NULL DEFAULT 'open',
    outcome             ENUM('upheld','rejected','adjusted') NULL,
    -- The share due when the outcome is 'adjusted'.
    adjusted_amount     DECIMAL(10,2)  NULL,
    decided_by          CHAR(36)       NULL,
    decided_at          DATETIME(6)    NULL,
    decision_note       VARCHAR(255)   NULL,
    PRIMARY KEY (dispute_id),
    KEY idx_dispute_remittance (remittance_id, status),
    -- Retention skips a trip with an open dispute (brief 4.5).
    KEY idx_dispute_trip_status (trip_id, status),
    CONSTRAINT fk_dispute_remittance
        FOREIGN KEY (remittance_id) REFERENCES remittances (remittance_id),
    CONSTRAINT fk_dispute_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_dispute_event
        FOREIGN KEY (event_id) REFERENCES passenger_events (event_id),
    CONSTRAINT fk_dispute_line
        FOREIGN KEY (line_id) REFERENCES remittance_lines (line_id),
    CONSTRAINT fk_dispute_driving_event
        FOREIGN KEY (driving_event_id) REFERENCES driving_events (driving_event_id),
    CONSTRAINT fk_dispute_raised_by
        FOREIGN KEY (raised_by) REFERENCES users (user_id),
    CONSTRAINT fk_dispute_decided_by
        FOREIGN KEY (decided_by) REFERENCES users (user_id),
    -- Exactly one item, the one the subject names.
    CONSTRAINT chk_dispute_subject
        CHECK ((subject = 'estimated_fare' AND event_id IS NOT NULL
                AND line_id IS NULL AND driving_event_id IS NULL)
            OR (subject = 'fare_line' AND line_id IS NOT NULL
                AND event_id IS NULL AND driving_event_id IS NULL)
            OR (subject = 'driving_flag' AND driving_event_id IS NOT NULL
                AND event_id IS NULL AND line_id IS NULL)),
    CONSTRAINT chk_dispute_amount
        CHECK (amount_disputed >= 0
               AND (subject <> 'driving_flag' OR amount_disputed = 0)),
    CONSTRAINT chk_dispute_outcome
        CHECK ((status = 'resolved') = (outcome IS NOT NULL)),
    -- Only the Terminal Manager decides, with a note, logged who and when.
    CONSTRAINT chk_dispute_decision
        CHECK (status <> 'resolved'
               OR (decided_by IS NOT NULL AND decided_at IS NOT NULL
                   AND decision_note IS NOT NULL)),
    CONSTRAINT chk_dispute_adjusted
        CHECK ((adjusted_amount IS NOT NULL) = (outcome IS NOT NULL AND outcome = 'adjusted')),
    CONSTRAINT chk_dispute_adjusted_range
        CHECK (adjusted_amount IS NULL
               OR adjusted_amount BETWEEN 0 AND amount_disputed)
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version)
VALUES ('018_revenue_audit_tables');
