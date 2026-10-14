-- Reverse of 024_rev603_payment_before_start.
--
-- Stops, before any change, when a row holds a value the rev 514 schema
-- cannot carry: an unlisted or resolved door event, a top-up line, a
-- walk-in special trip, a home pickup, a non-passenger move, a chat
-- image, a held share, a notification of a new type, or a trip with a
-- payment recorded or overridden. Those are rev 603 records; dropping
-- them silently is not a rollback.

DROP PROCEDURE IF EXISTS m024_down_preflight;
DELIMITER $$
CREATE PROCEDURE m024_down_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM passenger_events
              WHERE match_status = 'unlisted' OR resolution_status <> 'not_needed')
     OR EXISTS (SELECT 1 FROM remittance_lines WHERE is_top_up)
     OR EXISTS (SELECT 1 FROM remittances WHERE held_share <> 0 OR handed_over_by IS NOT NULL)
     OR EXISTS (SELECT 1 FROM special_trip_requests WHERE passenger_user_id IS NULL)
     OR EXISTS (SELECT 1 FROM assisted_pickups)
     OR EXISTS (SELECT 1 FROM non_passenger_moves)
     OR EXISTS (SELECT 1 FROM messages WHERE attachment_type IS NOT NULL)
     OR EXISTS (SELECT 1 FROM bookings WHERE booked_for_other OR is_home_pickup_seat)
     OR EXISTS (SELECT 1 FROM trips
                 WHERE payment_status <> 'unpaid' OR payment_override_by IS NOT NULL)
     OR EXISTS (SELECT 1 FROM notifications
                 WHERE type IN ('departed_more_than_listed','left_unpaid',
                                'payment_block_override','home_pickup_proof')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      'down 024 stopped: rev 603 records exist that the rev 514 schema cannot hold.';
  END IF;
END$$
DELIMITER ;
CALL m024_down_preflight();
DROP PROCEDURE m024_down_preflight;

-- -------------------------------------------------------------- policies
DELETE FROM cooperative_policies
 WHERE policy_key IN ('match_window_seconds','depart_zone_radius_m','depart_readings',
                      'home_pickup_wait_minutes','home_pickup_max_route_m',
                      'chat_image_max_kb','chat_image_retention_days');
-- 021 shipped retention_days unset; keep only that first row.
DELETE p FROM cooperative_policies p
  JOIN (SELECT MIN(effective_from) AS first FROM cooperative_policies
         WHERE policy_key = 'retention_days') f
 WHERE p.policy_key = 'retention_days' AND p.effective_from > f.first;
INSERT INTO cooperative_policies (policy_key, policy_value, data_type, description)
VALUES
    ('start_grace_minutes', '10', 'int',
     'Minutes after departure before the system starts an unstarted trip itself (assumed 10)'),
    ('retention_mode', '', 'string',
     'Keep snapshots and GPS logs: fixed_days or until_settled. Unset keeps everything');

-- -------------------------------------------------------- notifications
ALTER TABLE notifications
    MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','unrecorded_boarding','side_pickup','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised')
        NOT NULL;

-- ---------------------------------------------------------- new tables
DROP TABLE assisted_pickups;
DROP TABLE non_passenger_moves;

-- ------------------------------------------------------------- messages
ALTER TABLE messages
    DROP CHECK chk_msg_attachment,
    DROP COLUMN attachment_url,
    DROP COLUMN attachment_type,
    DROP COLUMN attachment_size_kb,
    DROP COLUMN retain_until;

-- ------------------------------------------------------------- bookings
ALTER TABLE bookings
    DROP COLUMN booked_for_other,
    DROP COLUMN is_home_pickup_seat;

-- ------------------------------------------------ special_trip_requests
ALTER TABLE special_trip_requests
    DROP CHECK chk_request_source,
    DROP FOREIGN KEY fk_request_entered_by,
    DROP COLUMN customer_name,
    DROP COLUMN customer_contact,
    DROP COLUMN entered_by,
    DROP COLUMN fee_note;
SET foreign_key_checks = 0;
ALTER TABLE special_trip_requests MODIFY COLUMN passenger_user_id CHAR(36) NOT NULL;
SET foreign_key_checks = 1;

-- ------------------------------------------------------------- disputes
ALTER TABLE disputes
    DROP CHECK chk_dispute_subject,
    MODIFY COLUMN subject ENUM('estimated_fare','fare_line','driving_flag') NOT NULL,
    ADD COLUMN event_id CHAR(36) NULL AFTER subject,
    ADD CONSTRAINT fk_dispute_event
        FOREIGN KEY (event_id) REFERENCES passenger_events (event_id),
    ADD CONSTRAINT chk_dispute_subject
        CHECK ((subject = 'estimated_fare' AND event_id IS NOT NULL
                AND line_id IS NULL AND driving_event_id IS NULL)
            OR (subject = 'fare_line' AND line_id IS NOT NULL
                AND event_id IS NULL AND driving_event_id IS NULL)
            OR (subject = 'driving_flag' AND driving_event_id IS NOT NULL
                AND event_id IS NULL AND line_id IS NULL));

-- ------------------------------------------------------ remittance_lines
ALTER TABLE remittance_lines
    DROP COLUMN is_top_up,
    MODIFY COLUMN income_group ENUM('verified','declared','estimated') NOT NULL;

-- ---------------------------------------------------------- remittances
ALTER TABLE remittances
    DROP CHECK chk_remittance_amounts,
    DROP FOREIGN KEY fk_remittance_handed_over_by,
    DROP COLUMN handed_over_by,
    DROP COLUMN held_share,
    ADD COLUMN estimated_income DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER declared_income,
    ADD COLUMN amount_at_risk   DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER remittance_owed,
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (verified_income >= 0 AND declared_income >= 0
               AND estimated_income >= 0 AND remittance_owed >= 0
               AND amount_at_risk >= 0 AND settled_amount >= 0);

-- ------------------------------------------------------ passenger_events
ALTER TABLE passenger_events
    DROP CHECK chk_event_resolution,
    DROP CHECK chk_event_resolved_by,
    DROP CHECK chk_event_explained,
    DROP CHECK chk_event_chain,
    DROP INDEX uq_event_chain,
    DROP COLUMN chain_seq,
    DROP COLUMN resolution_note,
    DROP COLUMN pre_departure,
    MODIFY COLUMN resolution_status ENUM('not_needed','pending','confirmed','dismissed') NULL;
UPDATE passenger_events SET resolution_status = NULL;
ALTER TABLE passenger_events
    MODIFY COLUMN resolution_status ENUM('pending','confirmed','dismissed') NULL,
    MODIFY COLUMN match_status ENUM('matched_qr','matched_log','unrecorded','mismatch') NULL,
    ADD COLUMN side_pickup        BOOLEAN           NOT NULL DEFAULT FALSE AFTER nearest_stop_dist_m,
    ADD COLUMN dest_stop_sequence SMALLINT UNSIGNED NULL AFTER matched_booking_id,
    ADD COLUMN estimated_fare     DECIMAL(10,2)     NULL AFTER dest_stop_sequence,
    ADD CONSTRAINT chk_event_estimate
        CHECK (estimated_fare IS NULL
               OR (match_status = 'unrecorded' AND estimated_fare >= 0)),
    ADD CONSTRAINT chk_event_resolution
        CHECK (resolution_status IS NULL OR match_status = 'unrecorded'),
    ADD CONSTRAINT chk_event_resolved_by
        CHECK (resolution_status NOT IN ('confirmed','dismissed')
               OR (resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    ADD CONSTRAINT chk_event_resolved_state
        CHECK (resolved_at IS NULL
               OR resolution_status IN ('confirmed','dismissed'));

-- --------------------------------------------------------------- trips
ALTER TABLE trips
    DROP CHECK chk_trip_overridden,
    DROP CHECK chk_trip_payment_override,
    DROP CHECK chk_trip_crew,
    DROP FOREIGN KEY fk_trip_payment_override_by,
    DROP COLUMN payment_override_note,
    DROP COLUMN payment_override_at,
    DROP COLUMN payment_override_by,
    DROP COLUMN crew_aboard,
    DROP COLUMN list_locked_at,
    DROP COLUMN payment_status,
    MODIFY COLUMN departure_source
        ENUM('confirmed','detected','dispatcher','staff','gps') NULL;
UPDATE trips
   SET departure_source = IF(departure_source = 'gps', 'detected', 'confirmed'),
       updated_at = updated_at
 WHERE departure_source IS NOT NULL;
ALTER TABLE trips
    MODIFY COLUMN departure_source ENUM('confirmed','detected') NULL;

DELETE FROM schema_migrations WHERE version = '024_rev603_payment_before_start';
