-- =====================================================================
-- 025: GPS readings of a van with no trip are held, not dropped
-- =====================================================================
-- Rev 603 brief 4.2 rule 8: a departure is N consecutive readings outside
-- the terminal zone. A van whose phone has boarded passengers but which
-- has no trip (nobody assigned one, rule 9 'Auto_Detected') still needs
-- its readings counted, so they are kept against the van with no trip,
-- the way held_door_events keeps its door events, and move to the trip
-- that claims them. Paper Table 31 has ScheduleID NOT NULL; the held
-- readings are the GPS half of the unassigned list the paper leaves out
-- of the data dictionary (brief 7.4).
--
-- Reverse: db/migrations/down/025_held_gps_readings.sql
-- =====================================================================

ALTER TABLE trip_location_pings
    MODIFY COLUMN trip_id CHAR(36) NULL,
    -- A held reading names its van.
    ADD CONSTRAINT chk_ping_owner CHECK (trip_id IS NOT NULL OR van_id IS NOT NULL);

INSERT INTO schema_migrations (version) VALUES ('025_held_gps_readings');
