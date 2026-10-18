-- =====================================================================
-- Reverses 019_trip_start_audit_columns.sql.
-- Run with: ./db/rollback.sh 019_trip_start_audit_columns
--
-- The two narrowing steps run first and fail, changing nothing, if data
-- exists that only 019 can hold: a trip with no route (a rental special
-- trip) or a notification of one of the new types. Resolve those rows
-- by hand before rolling back; this script does not delete them.
--
-- Everything else written into the new columns is lost with them.
-- =====================================================================

-- MySQL refuses NULL -> NOT NULL on a foreign-key column while checks
-- are on (error 1832). The type is unchanged, so no reference can break;
-- a NULL row still fails the change (error 1138), which is the guard.
SET foreign_key_checks = 0;
ALTER TABLE trips
    MODIFY COLUMN route_id CHAR(36) NOT NULL;
SET foreign_key_checks = 1;

ALTER TABLE notifications
    MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert')
        NOT NULL;

ALTER TABLE bookings
    DROP FOREIGN KEY fk_booking_logged_by,
    DROP COLUMN logged_by;

ALTER TABLE staff_profiles
    DROP FOREIGN KEY fk_staff_validated_by,
    DROP FOREIGN KEY fk_staff_import_batch,
    DROP COLUMN import_batch_id,
    DROP COLUMN validated_at,
    DROP COLUMN validated_by,
    DROP COLUMN validation_status;

ALTER TABLE vans
    DROP FOREIGN KEY fk_van_validated_by,
    DROP FOREIGN KEY fk_van_import_batch,
    DROP INDEX idx_van_validation,
    DROP COLUMN import_batch_id,
    DROP COLUMN validated_at,
    DROP COLUMN validated_by,
    DROP COLUMN validation_status,
    DROP COLUMN photo_right_url,
    DROP COLUMN photo_left_url,
    DROP COLUMN photo_rear_url,
    DROP COLUMN photo_front_url;

ALTER TABLE trips
    DROP CHECK chk_trip_route,
    DROP CHECK chk_trip_assigned,
    DROP CHECK chk_trip_start_mode,
    DROP CHECK chk_trip_start_review,
    DROP CHECK chk_trip_unaudited,
    DROP CHECK chk_trip_change,
    DROP FOREIGN KEY fk_trip_assigned_by,
    DROP FOREIGN KEY fk_trip_started_by,
    DROP FOREIGN KEY fk_trip_start_reviewed_by,
    DROP FOREIGN KEY fk_trip_changed_by;

ALTER TABLE trips
    DROP COLUMN change_note,
    DROP COLUMN changed_at,
    DROP COLUMN changed_by,
    DROP COLUMN departure_source,
    DROP COLUMN unaudited_reason,
    DROP COLUMN unaudited_at,
    DROP COLUMN audit_status,
    DROP COLUMN start_reviewed_at,
    DROP COLUMN start_reviewed_by,
    DROP COLUMN start_review_status,
    DROP COLUMN started_at,
    DROP COLUMN started_by,
    DROP COLUMN start_mode,
    DROP COLUMN van_plate_number,
    DROP COLUMN driver_license_no,
    DROP COLUMN driver_name,
    DROP COLUMN assigned_at,
    DROP COLUMN assigned_by;

DELETE FROM schema_migrations WHERE version = '019_trip_start_audit_columns';
