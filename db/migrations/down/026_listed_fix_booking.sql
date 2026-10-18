-- Reverse of 026_listed_fix_booking. Stops while a listed boarding names
-- its fix: 018's rule has no place for that link.
DROP PROCEDURE IF EXISTS m026_down_preflight;
DELIMITER $$
CREATE PROCEDURE m026_down_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM passenger_events
              WHERE matched_booking_id IS NOT NULL
                AND (match_status IS NULL OR match_status NOT IN ('matched_qr','matched_log'))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      'down 026 stopped: listed boardings name their fix booking.';
  END IF;
END$$
DELIMITER ;
CALL m026_down_preflight();
DROP PROCEDURE m026_down_preflight;

ALTER TABLE passenger_events
    DROP CHECK chk_event_booking_only_if_matched,
    ADD CONSTRAINT chk_event_booking_only_if_matched
        CHECK (matched_booking_id IS NULL OR match_status IN ('matched_qr','matched_log'));

DELETE FROM schema_migrations WHERE version = '026_listed_fix_booking';
