-- =====================================================================
-- 032_cash_only_booking.sql
-- Brief rev 721 (2 Nov), sections 2.1 and 7.3: A2Z handles only cash.
--
-- The study takes no online payment. A passenger reserves a seat in the
-- app and gets a short BOOKING CODE; the fare is paid in cash to the
-- Dispatcher at the terminal, who marks the seat Paid. There is no
-- gateway, no QR ticket and no e-ticket (acceptance test T60).
--
-- Removed:
--   payments                       the whole table. bookings.payment_status
--                                  is now the only record of a paid seat
--   boarding_scans                 the QR scan log at the van door
--   bookings.qr_payload            no QR to scan
--   bookings.rescheduled_from_booking_id, reschedule_count, and the
--                                  'rescheduled' status -- rev 721 drops
--                                  reschedule; an unpaid reservation is
--                                  cancelled and booked again instead
--   trips.reschedule_cutoff_hours  and the policies reschedule_cutoff_
--                                  hours, max_reschedules_per_booking
--                                  and refund_enabled, which went with it
--   special_trip_requests.payment_reference
--   assisted_pickups.activation_mode, proof_confirmed_by,
--                                  proof_confirmed_at; proof_message_id
--                                  becomes photo_message_id, a landmark
--                                  photo that nothing depends on
--   v_trip_revenue_reconciliation  it split gateway money from cash in
--                                  hand, a distinction that no longer
--                                  exists. Nothing reads it: the money
--                                  model has been remittances +
--                                  remittance_lines since 018
--
-- Renamed:
--   bookings.ticket_number -> booking_code. One short unique string the
--   passenger gives the Dispatcher, not two. "Ticket" is the wrong word
--   now that there is no ticket.
--
-- Added (brief 7.3, Table 16):
--   bookings  payment_status, paid_at, paid_by, cancelled_by,
--             cancel_reason
--
-- Existing codes keep their old SBG-yymmdd-XXXXXX shape; only new
-- bookings get the short SG-XXXXXX form. Both are unique and under 32
-- characters, and a demo database is reset before it is shown.
--
-- Reverse: db/migrations/down/032_cash_only_booking.sql
-- =====================================================================

-- ------------------------------------------------------------ preflight
-- Neither the sandbox nor the demo seed is money: `cs_sandbox_` comes
-- from the backend's own development checkout and `cs_demo_` from
-- 002_demo_dataset.sql, and both are safe to drop. A reference from the
-- real PayMongo would not be, so 032 stops rather than discard it.
DROP PROCEDURE IF EXISTS m032_preflight;
DELIMITER $$
CREATE PROCEDURE m032_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM payments
              WHERE provider = 'paymongo'
                AND COALESCE(provider_event_id, '') NOT LIKE 'evt_sandbox_%'
                AND COALESCE(provider_ref_id, '')   NOT LIKE 'cs_sandbox_%'
                AND COALESCE(provider_ref_id, '')   NOT LIKE 'cs_demo_%') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '032 stopped: a real PayMongo payment exists. Export it before dropping the table.';
  END IF;
  IF EXISTS (SELECT 1 FROM payments WHERE status = 'refunded') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '032 stopped: a refunded payment exists, and rev 721 has no refund.';
  END IF;
END$$
DELIMITER ;
CALL m032_preflight();
DROP PROCEDURE m032_preflight;

-- ------------------------------------------------------------- bookings
ALTER TABLE bookings
    CHANGE COLUMN ticket_number booking_code VARCHAR(32) NOT NULL,
    ADD COLUMN payment_status ENUM('unpaid','paid') NOT NULL DEFAULT 'unpaid'
        AFTER fare_amount,
    ADD COLUMN paid_at        DATETIME(6) NULL AFTER payment_status,
    -- The Dispatcher who took the cash. NULL on a seat carried over from
    -- the gateway era, which no person marked.
    ADD COLUMN paid_by        CHAR(36)    NULL AFTER paid_at,
    ADD COLUMN cancelled_by   CHAR(36)    NULL AFTER cancelled_at,
    -- NULL while the booking stands. 'passenger': cancelled in the app,
    -- only ever an unpaid reservation. 'passenger_asked_dispatcher': the
    -- passenger asked in the chat and the Dispatcher returned the cash.
    -- 'forgot_to_cancel': the Dispatcher cleared a reservation whose
    -- passenger never came. 'auto_release': the cutoff job (033).
    ADD COLUMN cancel_reason  ENUM('passenger','passenger_asked_dispatcher',
                                   'forgot_to_cancel','auto_release') NULL
        AFTER cancelled_by;

ALTER TABLE bookings
    ADD CONSTRAINT fk_booking_paid_by
        FOREIGN KEY (paid_by) REFERENCES users (user_id),
    ADD CONSTRAINT fk_booking_cancelled_by
        FOREIGN KEY (cancelled_by) REFERENCES users (user_id);

ALTER TABLE bookings
    DROP INDEX uq_ticket_number,
    ADD UNIQUE KEY uq_booking_code (booking_code),
    -- The Dispatcher searches the list by code at the van door.
    ADD KEY idx_booking_code_trip (trip_id, payment_status);

-- Carry the gateway era forward rather than marking every past seat
-- unpaid: a booking that had a settled payment row was paid.
UPDATE bookings b
   JOIN (SELECT booking_id, MAX(paid_at) AS paid_at
           FROM payments WHERE status = 'paid' GROUP BY booking_id) p
     ON p.booking_id = b.booking_id
   SET b.payment_status = 'paid',
       b.paid_at = COALESCE(p.paid_at, b.booked_at);

-- A cash walk-in wrote a 'pending' payment row at the moment the
-- Dispatcher logged it, which under rev 721 is exactly a seat paid in
-- cash. logged_by is the Dispatcher who took it.
UPDATE bookings b
   JOIN (SELECT DISTINCT booking_id FROM payments
          WHERE provider = 'cash' AND status = 'pending') p
     ON p.booking_id = b.booking_id
   SET b.payment_status = 'paid',
       b.paid_at = b.booked_at,
       b.paid_by = b.logged_by;

-- A superseded booking ends cancelled; nothing else fits once the
-- reschedule chain is gone.
UPDATE bookings SET status = 'cancelled' WHERE status = 'rescheduled';

ALTER TABLE bookings
    DROP FOREIGN KEY fk_booking_reschedule_src;

ALTER TABLE bookings
    DROP COLUMN qr_payload,
    DROP COLUMN rescheduled_from_booking_id,
    DROP COLUMN reschedule_count,
    MODIFY COLUMN status ENUM('pending','confirmed','checked_in','boarded',
                              'completed','cancelled','no_show')
           NOT NULL DEFAULT 'pending';

-- --------------------------------------------------------- door events
-- A boarding used to match a QR scan; it now matches a seat the
-- Dispatcher marked as paid. Only the name of the value changes.
ALTER TABLE passenger_events
    MODIFY COLUMN match_status
        ENUM('matched_qr','matched_booking','matched_log','unlisted') NULL;
UPDATE passenger_events SET match_status = 'matched_booking'
 WHERE match_status = 'matched_qr';
ALTER TABLE passenger_events
    MODIFY COLUMN match_status
        ENUM('matched_booking','matched_log','unlisted') NULL;

-- The constraint that says a booking is only named on a matched event
-- was written against the old value name (026).
ALTER TABLE passenger_events
    DROP CHECK chk_event_booking_only_if_matched,
    ADD CONSTRAINT chk_event_booking_only_if_matched
        CHECK (matched_booking_id IS NULL
               OR match_status IN ('matched_booking','matched_log')
               OR resolution_status = 'listed');

-- ------------------------------------------------- special trips
-- Brief 2.5 and 7.1: the renter pays the Dispatcher in cash at the
-- terminal, who marks the fee paid. There is no gateway reference, and
-- `paid_by` records who took it (the paper's Table 34 has only PaidAt).
ALTER TABLE special_trip_requests
    DROP COLUMN payment_reference,
    ADD COLUMN paid_at DATETIME(6) NULL AFTER payment_status,
    ADD COLUMN paid_by CHAR(36)    NULL AFTER paid_at,
    ADD CONSTRAINT fk_request_paid_by
        FOREIGN KEY (paid_by) REFERENCES users (user_id);

-- -------------------------------------------------- home pickups
-- Brief 2.6 and 7.1: the relative pays both seats in cash at the
-- terminal, and marking the home-pickup seat Paid is what activates the
-- pickup. There is no QR scan, so no ActivationMode, and the chat image
-- is a photo of a landmark rather than proof of a payment -- nothing
-- depends on it, so there is nothing to confirm.
ALTER TABLE assisted_pickups
    DROP FOREIGN KEY fk_pickup_proof,
    DROP FOREIGN KEY fk_pickup_proof_by;

ALTER TABLE assisted_pickups
    DROP CHECK chk_pickup_activated,
    DROP CHECK chk_pickup_proof,
    CHANGE COLUMN proof_message_id photo_message_id CHAR(36) NULL,
    DROP COLUMN activation_mode,
    DROP COLUMN proof_confirmed_by,
    DROP COLUMN proof_confirmed_at,
    ADD CONSTRAINT fk_pickup_photo
        FOREIGN KEY (photo_message_id) REFERENCES messages (message_id),
    ADD CONSTRAINT chk_pickup_activated
        CHECK ((activated_at IS NULL) = (activated_by IS NULL));

-- Widen, map, narrow: the type is a rename (brief 7.3).
ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_proof','home_pickup_photo')
        NOT NULL;
UPDATE notifications SET type = 'home_pickup_photo' WHERE type = 'home_pickup_proof';
ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_photo')
        NOT NULL;

-- ------------------------------------------- reschedule, and its rules
-- A trip snapshotted the reschedule cutoff in force on the day it was
-- generated. With no reschedule there is nothing to snapshot.
ALTER TABLE trips DROP COLUMN reschedule_cutoff_hours;

DELETE FROM cooperative_policies
 WHERE policy_key IN ('reschedule_cutoff_hours',
                      'max_reschedules_per_booking',
                      'refund_enabled');

-- ------------------------------------------------------ what is dropped
DROP VIEW  IF EXISTS v_trip_revenue_reconciliation;
DROP TABLE IF EXISTS boarding_scans;
DROP TABLE IF EXISTS payments;

INSERT INTO schema_migrations (version) VALUES ('032_cash_only_booking');
