-- =====================================================================
-- 019_trip_start_audit_columns.sql
--
-- Column edits of paper revision 468 (change brief 4.3 and 7.3).
-- EXPAND ONLY: nothing is dropped or renamed, and no code path changes
-- except that a walk-in now records who logged it.
--
--   trips           route_id may be NULL (a rental special trip has no
--                   fixed route, brief 2.5); assignment, start, review,
--                   audit, departure-source and change columns (4.3);
--                   operator name, licence and plate copied at start.
--   vans            validation (brief 8), import batch, four photographs.
--   staff_profiles  validation and import batch: a Dispatcher's roster
--                   record (the brief's Dispatchers table).
--   bookings        logged_by: who recorded a cash walk-in.
--   notifications   the brief's ten new types.
--
-- Paper -> repo, for what is NOT a new column:
--   TripSchedules.IsSpecial    trips.is_special_trip AND route_id IS NULL.
--                              is_special_trip alone also covers the
--                              office's extra departures on a fixed route.
--   TripSchedules.Status       'en_route' is the existing 'departed'.
--   AssignedVanID / DispatcherID   trips.van_id / dispatcher_id, already
--                              NULL-able.
--   Vans.RouteCode             vans.registered_route_id.
--   Bookings.ScheduleID        bookings.trip_id.
--   Bookings.Origin/DestTerminalID   the terminals at boarding_stop_sequence
--                              and alighting_stop_sequence in route_stops.
--   Bookings.PaymentStatus/Reference payments.status / provider_ref_id.
--   LogBookEntries             walk-in bookings; DestStopID =
--                              alighting_stop_sequence, FareAmount =
--                              fare_amount, LoggedBy = logged_by (new).
--   Notifications.RecipientType/ID   notifications.audience / user_id.
--   Fare_Matrix                fare_matrix, per route by stop sequence.
--   (See docs/MANUSCRIPT_CORRECTIONS.md section 11.)
--
-- Start, review and departure columns stay NULL on trips that ran before
-- this migration: who started them and how was never recorded, and
-- writing a guess would put an invented name on the trail. The operator
-- copies ARE filled for those trips, from the driver the trip recorded,
-- so the history survives the contraction that drops trips.driver_id.
--
-- Reverse: db/migrations/down/019_trip_start_audit_columns.sql
-- =====================================================================

-- --------------------------------------------------------------- trips
ALTER TABLE trips
    MODIFY COLUMN route_id CHAR(36) NULL,
    -- Who assigned the van and the Dispatcher at the van's turn
    -- (Terminal Manager, or the Cashier as backup).
    ADD COLUMN assigned_by          CHAR(36)      NULL AFTER dispatcher_id,
    ADD COLUMN assigned_at          DATETIME(6)   NULL AFTER assigned_by,
    -- Copied when the trip is started, so the record stays fixed if the
    -- roster changes later (brief 4.2 rule 5).
    ADD COLUMN driver_name          VARCHAR(255)  NULL AFTER assigned_at,
    ADD COLUMN driver_license_no    VARCHAR(64)   NULL AFTER driver_name,
    ADD COLUMN van_plate_number     VARCHAR(20)   NULL AFTER driver_license_no,
    ADD COLUMN start_mode           ENUM('manual','auto_assigned','auto_detected')
                                    NULL AFTER status,
    -- NULL when the system started the trip.
    ADD COLUMN started_by           CHAR(36)      NULL AFTER start_mode,
    ADD COLUMN started_at           DATETIME(6)   NULL AFTER started_by,
    -- 'pending' (an automatic start) keeps the trip off the statement
    -- until the Terminal Manager reviews it.
    ADD COLUMN start_review_status  ENUM('not_required','pending','reviewed')
                                    NOT NULL DEFAULT 'not_required' AFTER started_at,
    ADD COLUMN start_reviewed_by    CHAR(36)      NULL AFTER start_review_status,
    ADD COLUMN start_reviewed_at    DATETIME(6)   NULL AFTER start_reviewed_by,
    -- 'unaudited' when the phone gave no camera evidence (brief 4.4).
    ADD COLUMN audit_status         ENUM('audited','unaudited')
                                    NOT NULL DEFAULT 'audited' AFTER start_reviewed_at,
    ADD COLUMN unaudited_at         DATETIME(6)   NULL AFTER audit_status,
    ADD COLUMN unaudited_reason     ENUM('no_phone','silent_at_start','lost_en_route','lens_blocked')
                                    NULL AFTER unaudited_at,
    ADD COLUMN departure_source     ENUM('confirmed','detected') NULL AFTER departed_at,
    -- A started trip is not edited quietly: only the Terminal Manager
    -- voids it or changes its van, with the earlier van and operator in
    -- the note (brief 4.2 rule 10).
    ADD COLUMN changed_by           CHAR(36)      NULL AFTER completed_at,
    ADD COLUMN changed_at           DATETIME(6)   NULL AFTER changed_by,
    ADD COLUMN change_note          VARCHAR(255)  NULL AFTER changed_at,
    ADD CONSTRAINT fk_trip_assigned_by
        FOREIGN KEY (assigned_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_trip_started_by
        FOREIGN KEY (started_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_trip_start_reviewed_by
        FOREIGN KEY (start_reviewed_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_trip_changed_by
        FOREIGN KEY (changed_by) REFERENCES users (user_id),
    -- A timetable trip always has its route; only a special trip may not.
    ADD CONSTRAINT chk_trip_route
        CHECK (route_id IS NOT NULL OR is_special_trip),
    ADD CONSTRAINT chk_trip_assigned
        CHECK ((assigned_by IS NULL) = (assigned_at IS NULL)),
    -- A person starts a trip manually; the system starts it otherwise.
    ADD CONSTRAINT chk_trip_start_mode
        CHECK (start_mode IS NULL
               OR ((start_mode = 'manual') = (started_by IS NOT NULL))),
    ADD CONSTRAINT chk_trip_start_review
        CHECK (start_review_status <> 'reviewed'
               OR (start_reviewed_by IS NOT NULL AND start_reviewed_at IS NOT NULL)),
    ADD CONSTRAINT chk_trip_unaudited
        CHECK ((audit_status = 'unaudited')
               = (unaudited_at IS NOT NULL AND unaudited_reason IS NOT NULL)),
    -- Who, when and why.
    ADD CONSTRAINT chk_trip_change
        CHECK ((changed_by IS NULL) = (changed_at IS NULL)
               AND (changed_at IS NULL OR change_note IS NOT NULL));

-- The operator copies for trips that already ran. The operator row made
-- from the trip's driver (017) carries that driver's name and licence.
-- updated_at is assigned to itself so the copy does not read as an edit
-- of the trip (and a rollback leaves the rows exactly as they were).
UPDATE trips t
  JOIN operators o ON o.former_driver_user_id = t.driver_id
   SET t.driver_name       = o.full_name,
       t.driver_license_no = o.license_number,
       t.updated_at        = t.updated_at
 WHERE t.status IN ('boarding','departed','completed');

UPDATE trips t
  JOIN vans v ON v.van_id = t.van_id
   SET t.van_plate_number = v.plate_number,
       t.updated_at       = t.updated_at
 WHERE t.status IN ('boarding','departed','completed');

-- ---------------------------------------------------------------- vans
-- Only a validated van can be assigned to a trip (brief 8), and it
-- cannot be validated until its four photographs are present. Existing
-- vans start 'pending', as operators did in 017: nobody has validated
-- them. Nothing reads validation yet.
ALTER TABLE vans
    ADD COLUMN photo_front_url    VARCHAR(512) NULL AFTER camera_device_id,
    ADD COLUMN photo_rear_url     VARCHAR(512) NULL AFTER photo_front_url,
    ADD COLUMN photo_left_url     VARCHAR(512) NULL AFTER photo_rear_url,
    ADD COLUMN photo_right_url    VARCHAR(512) NULL AFTER photo_left_url,
    ADD COLUMN validation_status  ENUM('pending','validated','rejected','suspended')
                                  NOT NULL DEFAULT 'pending' AFTER photo_right_url,
    ADD COLUMN validated_by       CHAR(36)     NULL AFTER validation_status,
    ADD COLUMN validated_at       DATETIME(6)  NULL AFTER validated_by,
    ADD COLUMN import_batch_id    CHAR(36)     NULL AFTER validated_at,
    ADD KEY idx_van_validation (validation_status),
    ADD CONSTRAINT fk_van_validated_by
        FOREIGN KEY (validated_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_van_import_batch
        FOREIGN KEY (import_batch_id) REFERENCES data_transfers (transfer_id);

-- ------------------------------------------------------ staff_profiles
-- The brief's Dispatchers roster record. staff_profiles also holds the
-- office staff, who are not on the roster; the columns are read for
-- Dispatchers only.
ALTER TABLE staff_profiles
    ADD COLUMN validation_status  ENUM('pending','validated','rejected','suspended')
                                  NOT NULL DEFAULT 'pending' AFTER employment_status,
    ADD COLUMN validated_by       CHAR(36)     NULL AFTER validation_status,
    ADD COLUMN validated_at       DATETIME(6)  NULL AFTER validated_by,
    ADD COLUMN import_batch_id    CHAR(36)     NULL AFTER validated_at,
    ADD CONSTRAINT fk_staff_validated_by
        FOREIGN KEY (validated_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_staff_import_batch
        FOREIGN KEY (import_batch_id) REFERENCES data_transfers (transfer_id);

-- ------------------------------------------------------------ bookings
-- Who recorded a cash walk-in: the Declared income is theirs to answer
-- for. NULL on app bookings, and on walk-ins logged before this
-- migration, whose logger was not recorded.
ALTER TABLE bookings
    ADD COLUMN logged_by CHAR(36) NULL AFTER booking_type,
    ADD CONSTRAINT fk_booking_logged_by
        FOREIGN KEY (logged_by) REFERENCES users (user_id);

-- ------------------------------------------------------- notifications
-- Appended, so no existing row moves.
ALTER TABLE notifications
    MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','unrecorded_boarding','side_pickup','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised')
        NOT NULL;

INSERT INTO schema_migrations (version)
VALUES ('019_trip_start_audit_columns');
