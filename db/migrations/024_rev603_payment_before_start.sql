-- =====================================================================
-- 024: change brief rev 603 -- one boarding point, payment before Start
-- =====================================================================
-- Rev 603 replaces the rev 514 money model. Passengers board only at
-- the starting terminal, so the passenger list is complete before the
-- van leaves; the Dispatcher hands 15 % of it to the Cashier before
-- Start; the camera prices nothing (brief 1, 2.1, 2.4).
--
-- Removed with the old model (brief 7.1):
--   passenger_events  side_pickup, dest_stop_sequence, estimated_fare;
--                     match_status 'unrecorded', 'mismatch';
--                     resolution_status 'confirmed', 'dismissed'
--   remittances       estimated_income, amount_at_risk
--   remittance_lines  income_group 'estimated'
--   disputes          subject 'estimated_fare', event_id
--   notifications     'unrecorded_boarding', 'side_pickup'
--   policies          start_grace_minutes, retention_mode
--
-- Added (brief 4.3, 7.2, 7.3):
--   trips             payment_status, list_locked_at, crew_aboard,
--                     payment_override_by/at/note; departure_source is
--                     now 'dispatcher', 'staff', 'gps'
--   passenger_events  pre_departure, match_status 'unlisted',
--                     resolution_status 'not_needed','pending','listed',
--                     'explained' + resolution_note, chain_seq
--   remittances       held_share, handed_over_by
--   remittance_lines  is_top_up
--   special_trip_requests  walk-in entry: customer_name,
--                     customer_contact, entered_by, fee_note; the
--                     passenger may be NULL
--   bookings          booked_for_other, is_home_pickup_seat
--   messages          image attachment and retain_until (the chat of
--                     014 is the paper's Messages table)
--   non_passenger_moves  Table 40
--   assisted_pickups     Table 41
--   notifications     'departed_more_than_listed', 'left_unpaid',
--                     'payment_block_override', 'home_pickup_proof'
--   policies          match_window_seconds, depart_zone_radius_m and
--                     depart_readings (unset: a site survey sets them),
--                     home_pickup_wait_minutes, home_pickup_max_route_m
--                     (unset), chat_image_max_kb, chat_image_retention_days,
--                     retention_days = 30
--
-- Paper -> repo names:
--   TripSchedules.PaymentStatus        trips.payment_status
--   Passenger_Events.ResolvedBy        passenger_events.resolved_by (users)
--   Passenger_Events.MatchedLogEntryID passenger_events.matched_booking_id
--                                      (a cash entry is a walk-in booking)
--   Remittances.HandedOverBy           remittances.handed_over_by (users)
--   Non_Passenger_Moves.ScheduleID     non_passenger_moves.trip_id
--   Assisted_Pickups.ScheduleID        assisted_pickups.trip_id
--   Messages.ScheduleID                conversations.trip_id
--   TerminalSettings.<Key>             cooperative_policies, snake_case
--
-- chain_seq is not in the paper: the hash chain links each event to the
-- one entered before it on the same trip, and a phone that was offline
-- uploads late, so arrival order is not event_at order. The chain's
-- order has to be stored for it to be recomputed.
--
-- The preflight stops 024, before any change, when a removed column or
-- value holds data. No code wrote any of them (the matching of step 6
-- was never built), so on this project's databases it passes.
--
-- Reverse: db/migrations/down/024_rev603_payment_before_start.sql
-- =====================================================================

-- ------------------------------------------------------------ preflight
DROP PROCEDURE IF EXISTS m024_preflight;
DELIMITER $$
CREATE PROCEDURE m024_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM passenger_events
              WHERE side_pickup OR dest_stop_sequence IS NOT NULL
                 OR estimated_fare IS NOT NULL
                 OR match_status IN ('unrecorded','mismatch')
                 OR resolution_status IS NOT NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '024 stopped: door events carry side-pickup, estimate or resolution values rev 603 removes.';
  END IF;
  IF EXISTS (SELECT 1 FROM remittances
              WHERE estimated_income <> 0 OR amount_at_risk <> 0)
     OR EXISTS (SELECT 1 FROM remittance_lines WHERE income_group = 'estimated')
     OR EXISTS (SELECT 1 FROM disputes WHERE subject = 'estimated_fare') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '024 stopped: statements, lines or disputes hold estimated income.';
  END IF;
  IF EXISTS (SELECT 1 FROM notifications
              WHERE type IN ('unrecorded_boarding','side_pickup')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '024 stopped: notifications of a removed type exist.';
  END IF;
END$$
DELIMITER ;
CALL m024_preflight();
DROP PROCEDURE m024_preflight;

-- --------------------------------------------------------------- trips
-- departure_source: the office's Depart becomes 'staff', a detected
-- departure 'gps'. Widen, map, then narrow.
ALTER TABLE trips
    MODIFY COLUMN departure_source
        ENUM('confirmed','detected','dispatcher','staff','gps') NULL;
UPDATE trips
   SET departure_source = IF(departure_source = 'confirmed', 'staff', 'gps'),
       updated_at = updated_at
 WHERE departure_source IN ('confirmed','detected');
ALTER TABLE trips
    MODIFY COLUMN departure_source ENUM('dispatcher','staff','gps') NULL,
    -- Brief 2.1 / 4.3. 'paid' when the Cashier records the share,
    -- 'overridden' after the Terminal Manager's written override,
    -- 'left_unpaid' when the system started a trip nobody paid for.
    ADD COLUMN payment_status       ENUM('unpaid','paid','left_unpaid','overridden')
                                    NOT NULL DEFAULT 'unpaid' AFTER audit_status,
    -- The list stops taking cancellations at the payment or the
    -- departure, whichever is first. It may still grow before Start.
    ADD COLUMN list_locked_at       DATETIME(6)   NULL AFTER payment_status,
    -- 1 once the assigned Dispatcher has added themselves as crew: the
    -- door count less this is the number aboard, never above 14 for it.
    ADD COLUMN crew_aboard          TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER list_locked_at,
    ADD COLUMN payment_override_by  CHAR(36)      NULL AFTER crew_aboard,
    ADD COLUMN payment_override_at  DATETIME(6)   NULL AFTER payment_override_by,
    ADD COLUMN payment_override_note VARCHAR(255) NULL AFTER payment_override_at,
    ADD CONSTRAINT fk_trip_payment_override_by
        FOREIGN KEY (payment_override_by) REFERENCES users (user_id),
    ADD CONSTRAINT chk_trip_crew CHECK (crew_aboard IN (0, 1)),
    -- An override names who, when and why.
    ADD CONSTRAINT chk_trip_payment_override
        CHECK ((payment_override_by IS NULL) = (payment_override_at IS NULL)
               AND (payment_override_at IS NULL OR payment_override_note IS NOT NULL)),
    ADD CONSTRAINT chk_trip_overridden
        CHECK (payment_status <> 'overridden' OR payment_override_by IS NOT NULL);

-- ------------------------------------------------------ passenger_events
ALTER TABLE passenger_events
    DROP CHECK chk_event_estimate,
    DROP CHECK chk_event_resolution,
    DROP CHECK chk_event_resolved_by,
    DROP CHECK chk_event_resolved_state,
    DROP COLUMN side_pickup,
    DROP COLUMN dest_stop_sequence,
    DROP COLUMN estimated_fare,
    MODIFY COLUMN resolution_status
        ENUM('pending','confirmed','dismissed','not_needed') NULL;
UPDATE passenger_events SET resolution_status = 'not_needed';

-- No row holds a removed value (preflight), so these narrow in place.
ALTER TABLE passenger_events
    MODIFY COLUMN match_status ENUM('matched_qr','matched_log','unlisted') NULL,
    MODIFY COLUMN resolution_status ENUM('not_needed','pending','listed','explained')
                  NOT NULL DEFAULT 'not_needed',
    -- TRUE before the trip departed, when the door count is checked
    -- against the list; FALSE after, when it only holds the van to 14.
    ADD COLUMN pre_departure    BOOLEAN       NOT NULL DEFAULT FALSE AFTER nearest_stop_dist_m,
    ADD COLUMN resolution_note  VARCHAR(255)  NULL AFTER resolved_at,
    -- Position in the trip's hash chain, from 1, in the order events
    -- entered the ledger.
    ADD COLUMN chain_seq        INT UNSIGNED  NULL AFTER event_hash,
    ADD UNIQUE KEY uq_event_chain (trip_id, chain_seq),
    -- Only an unlisted boarding is resolved, and only before departure.
    ADD CONSTRAINT chk_event_resolution
        CHECK (resolution_status = 'not_needed'
               OR (match_status = 'unlisted' AND pre_departure)),
    -- The Dispatcher's fix or reason, logged with who and when.
    ADD CONSTRAINT chk_event_resolved_by
        CHECK ((resolution_status IN ('listed','explained'))
               = (resolved_by IS NOT NULL AND resolved_at IS NOT NULL)),
    ADD CONSTRAINT chk_event_explained
        CHECK (resolution_status <> 'explained' OR resolution_note IS NOT NULL),
    ADD CONSTRAINT chk_event_chain
        CHECK ((event_hash IS NULL) = (chain_seq IS NULL));

-- ---------------------------------------------------------- remittances
ALTER TABLE remittances
    DROP CHECK chk_remittance_amounts,
    DROP COLUMN estimated_income,
    DROP COLUMN amount_at_risk,
    -- The share of trips the system started and the Terminal Manager has
    -- not reviewed: off the lines and remittance_owed, but counted in the
    -- van's balance for the payment block (brief 2.1).
    ADD COLUMN held_share      DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER remittance_owed,
    -- The Dispatcher who handed over the latest payment.
    ADD COLUMN handed_over_by  CHAR(36)      NULL AFTER recorded_by,
    ADD CONSTRAINT fk_remittance_handed_over_by
        FOREIGN KEY (handed_over_by) REFERENCES users (user_id),
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (verified_income >= 0 AND declared_income >= 0
               AND remittance_owed >= 0 AND held_share >= 0
               AND settled_amount >= 0);

-- ------------------------------------------------------ remittance_lines
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('verified','declared') NOT NULL,
    -- A seat added after the Cashier recorded the payment, before Start.
    ADD COLUMN is_top_up BOOLEAN NOT NULL DEFAULT FALSE AFTER share_amount;

-- ------------------------------------------------------------- disputes
ALTER TABLE disputes
    DROP CHECK chk_dispute_subject,
    DROP FOREIGN KEY fk_dispute_event,
    DROP COLUMN event_id,
    MODIFY COLUMN subject ENUM('fare_line','driving_flag') NOT NULL,
    ADD CONSTRAINT chk_dispute_subject
        CHECK ((subject = 'fare_line' AND line_id IS NOT NULL AND driving_event_id IS NULL)
            OR (subject = 'driving_flag' AND driving_event_id IS NOT NULL AND line_id IS NULL));

-- ------------------------------------------------ special_trip_requests
-- A walk-in asks at the counter; the Terminal Manager or the Cashier
-- enters it, and agrees the fee on the spot (brief 2.5).
ALTER TABLE special_trip_requests
    MODIFY COLUMN passenger_user_id CHAR(36) NULL,
    ADD COLUMN customer_name     VARCHAR(100) NULL AFTER passenger_user_id,
    ADD COLUMN customer_contact  VARCHAR(20)  NULL AFTER customer_name,
    ADD COLUMN entered_by        CHAR(36)     NULL AFTER customer_contact,
    ADD COLUMN fee_note          VARCHAR(255) NULL AFTER rental_fee,
    ADD CONSTRAINT fk_request_entered_by
        FOREIGN KEY (entered_by) REFERENCES users (user_id),
    -- From the app (a passenger) or from the counter (a name and who
    -- entered it).
    ADD CONSTRAINT chk_request_source
        CHECK (passenger_user_id IS NOT NULL
               OR (customer_name IS NOT NULL AND entered_by IS NOT NULL));

-- ------------------------------------------------------------- bookings
-- Home pickup (brief 2.6): the relative books and pays both seats. The
-- details of the pickup are in assisted_pickups.
ALTER TABLE bookings
    ADD COLUMN booked_for_other     BOOLEAN NOT NULL DEFAULT FALSE AFTER logged_by,
    ADD COLUMN is_home_pickup_seat  BOOLEAN NOT NULL DEFAULT FALSE AFTER booked_for_other;

-- ------------------------------------------------------------- messages
-- An image, for the payment proof of a home pickup only. The file is
-- deleted on retain_until; the row stays.
ALTER TABLE messages
    ADD COLUMN attachment_url      VARCHAR(255) NULL AFTER body,
    ADD COLUMN attachment_type     ENUM('image') NULL AFTER attachment_url,
    ADD COLUMN attachment_size_kb  INT UNSIGNED NULL AFTER attachment_type,
    ADD COLUMN retain_until        DATE NULL AFTER attachment_size_kb,
    ADD CONSTRAINT chk_msg_attachment
        CHECK ((attachment_type IS NULL)
               = (attachment_size_kb IS NULL AND retain_until IS NULL));

-- -------------------------------------------------- non_passenger_moves
-- Table 40. The Dispatcher pressed 'Not a passenger trip' before the van
-- left: nothing is started, nothing is owed, and the GPS fallback does
-- not start a trip -- unless the camera sees a passenger aboard, which
-- starts the trip 'auto_detected' (brief 4.2 rule 10).
CREATE TABLE non_passenger_moves (
    move_id                 CHAR(36)      NOT NULL,
    van_id                  CHAR(36)      NOT NULL,
    device_id               CHAR(36)      NOT NULL,
    dispatcher_id           CHAR(36)      NOT NULL,
    trip_id                 CHAR(36)      NULL,
    reason                  ENUM('errand','fuel_or_repair','other') NOT NULL,
    reason_note             VARCHAR(255)  NULL,
    started_at              DATETIME(6)   NOT NULL,
    -- The Dispatcher turned it off, or the van came back into the
    -- terminal zone.
    ended_at                DATETIME(6)   NULL,
    auto_started_trip_id    CHAR(36)      NULL,
    PRIMARY KEY (move_id),
    KEY idx_move_van_time (van_id, started_at),
    -- One open move per van: the same functional-index pattern as 018.
    UNIQUE KEY uq_move_open_van ((CASE WHEN ended_at IS NULL THEN van_id END)),
    CONSTRAINT fk_move_van FOREIGN KEY (van_id) REFERENCES vans (van_id),
    CONSTRAINT fk_move_device FOREIGN KEY (device_id) REFERENCES edge_devices (device_id),
    CONSTRAINT fk_move_dispatcher FOREIGN KEY (dispatcher_id) REFERENCES users (user_id),
    CONSTRAINT fk_move_trip FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_move_auto_trip
        FOREIGN KEY (auto_started_trip_id) REFERENCES trips (trip_id),
    CONSTRAINT chk_move_other CHECK (reason <> 'other' OR reason_note IS NOT NULL),
    CONSTRAINT chk_move_end CHECK (ended_at IS NULL OR ended_at >= started_at)
) ENGINE=InnoDB;

-- ----------------------------------------------------- assisted_pickups
-- Table 41. Home pickup of a disabled or elderly passenger, booked and
-- paid by a relative who rides from the terminal (brief 2.6).
CREATE TABLE assisted_pickups (
    pickup_id             CHAR(36)       NOT NULL,
    booking_id            CHAR(36)       NOT NULL,
    relative_booking_id   CHAR(36)       NOT NULL,
    trip_id               CHAR(36)       NOT NULL,
    pickup_latitude       DECIMAL(8,6)   NOT NULL,
    pickup_longitude      DECIMAL(9,6)   NOT NULL,
    pickup_note           VARCHAR(255)   NULL,
    -- Distance from the route line, checked against home_pickup_max_route_m.
    route_distance_m      INT UNSIGNED   NOT NULL,
    beneficiary_name      VARCHAR(150)   NOT NULL,
    beneficiary_contact   VARCHAR(20)    NOT NULL,
    status                ENUM('requested','activated','arrived','boarded','no_show','cancelled')
                          NOT NULL DEFAULT 'requested',
    activation_mode       ENUM('qr_scan','dispatcher_entry') NULL,
    activated_by          CHAR(36)       NULL,
    activated_at          DATETIME(6)    NULL,
    -- The payment screenshot in the trip chat, when the gateway was down.
    proof_message_id      CHAR(36)       NULL,
    proof_confirmed_by    CHAR(36)       NULL,
    proof_confirmed_at    DATETIME(6)    NULL,
    -- The wait between them is taken out of the stretch time (6.3).
    arrived_at            DATETIME(6)    NULL,
    left_at               DATETIME(6)    NULL,
    closed_early          BOOLEAN        NOT NULL DEFAULT FALSE,
    closed_by             CHAR(36)       NULL,
    created_at            DATETIME(6)    NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at            DATETIME(6)    NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                         ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (pickup_id),
    UNIQUE KEY uq_pickup_booking (booking_id),
    KEY idx_pickup_trip (trip_id, status),
    CONSTRAINT fk_pickup_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id),
    CONSTRAINT fk_pickup_relative
        FOREIGN KEY (relative_booking_id) REFERENCES bookings (booking_id),
    CONSTRAINT fk_pickup_trip FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_pickup_activated_by FOREIGN KEY (activated_by) REFERENCES users (user_id),
    CONSTRAINT fk_pickup_proof FOREIGN KEY (proof_message_id) REFERENCES messages (message_id),
    CONSTRAINT fk_pickup_proof_by FOREIGN KEY (proof_confirmed_by) REFERENCES users (user_id),
    CONSTRAINT fk_pickup_closed_by FOREIGN KEY (closed_by) REFERENCES users (user_id),
    CONSTRAINT chk_pickup_two_seats CHECK (booking_id <> relative_booking_id),
    CONSTRAINT chk_pickup_activated
        CHECK ((activated_at IS NULL) = (activation_mode IS NULL)
               AND (activation_mode IS NULL OR activation_mode = 'qr_scan'
                    OR activated_by IS NOT NULL)),
    CONSTRAINT chk_pickup_proof
        CHECK ((proof_confirmed_by IS NULL) = (proof_confirmed_at IS NULL)),
    CONSTRAINT chk_pickup_wait CHECK (left_at IS NULL OR (arrived_at IS NOT NULL AND left_at >= arrived_at)),
    CONSTRAINT chk_pickup_closed CHECK (NOT closed_early OR closed_by IS NOT NULL)
) ENGINE=InnoDB;

-- -------------------------------------------------------- notifications
ALTER TABLE notifications
    MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_proof')
        NOT NULL;

-- -------------------------------------------------------------- policies
-- Removed keys go with their history: nothing reads them any more.
DELETE FROM cooperative_policies
 WHERE policy_key IN ('start_grace_minutes', 'retention_mode');

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('retention_days', '30', 'int',
     'Days to keep blurred snapshots and GPS logs (assumed 30, to confirm with A2Z)'),
    ('match_window_seconds', '120', 'int',
     'A boarding is listed if a QR scan or cash entry was made this many seconds before or after it'),
    ('depart_zone_radius_m', '', 'int',
     'Terminal zone radius covering the queue and loading area, from a site survey. Unset: no GPS departure'),
    ('depart_readings', '', 'int',
     'Consecutive GPS readings outside the terminal zone, while moving, that count as a departure. Unset: no GPS departure'),
    ('home_pickup_wait_minutes', '10', 'int',
     'Longest wait at a home-pickup pin (assumed 10)'),
    ('home_pickup_max_route_m', '', 'int',
     'Farthest a home-pickup pin may be from the route. Unset: home pickup is not offered'),
    ('chat_image_max_kb', '10240', 'int',
     'Largest chat image, in KB (10 MB)'),
    ('chat_image_retention_days', '30', 'int',
     'Days to keep a chat image (assumed 30)');

INSERT INTO schema_migrations (version)
VALUES ('024_rev603_payment_before_start');
