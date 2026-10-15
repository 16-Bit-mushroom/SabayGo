-- Reverse of 025_held_gps_readings. Stops while held readings exist:
-- they would have nowhere to go under a NOT NULL trip_id.
DROP PROCEDURE IF EXISTS m025_down_preflight;
DELIMITER $$
CREATE PROCEDURE m025_down_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM trip_location_pings WHERE trip_id IS NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      'down 025 stopped: held GPS readings exist (trip_id NULL).';
  END IF;
END$$
DELIMITER ;
CALL m025_down_preflight();
DROP PROCEDURE m025_down_preflight;

ALTER TABLE trip_location_pings DROP CHECK chk_ping_owner;
SET foreign_key_checks = 0;
ALTER TABLE trip_location_pings MODIFY COLUMN trip_id CHAR(36) NOT NULL;
SET foreign_key_checks = 1;

DELETE FROM schema_migrations WHERE version = '025_held_gps_readings';
