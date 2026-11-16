-- Reverses 038_operator_share_returned.sql. A share returned is folded
-- back into what was given (given - returned), so the operator's share
-- held stays the same after the rollback.
-- Run with: ./db/rollback.sh 038_operator_share_returned

UPDATE remittances SET operator_share_given = operator_share_given - operator_share_returned;

ALTER TABLE remittances
    DROP CHECK chk_remittance_share_returned_by,
    DROP CHECK chk_remittance_share_returned,
    DROP FOREIGN KEY fk_remittance_share_returned_by;

ALTER TABLE remittances
    DROP COLUMN operator_share_returned_by,
    DROP COLUMN operator_share_returned_at,
    DROP COLUMN operator_share_returned;

UPDATE notifications SET type = 'system_alert' WHERE type = 'share_over_given';
ALTER TABLE notifications MODIFY COLUMN type
    ENUM('trip_update','tailored_schedule','system_alert','terminal_policy','variance_alert','unremitted_fare','departure_reminder','schedule_change','sos_alert','capacity_alert','driving_flag','special_trip_request','unconfirmed_trip_start','unaudited_trip','trip_not_started','assignment_by_cashier','dispute_raised','departed_more_than_listed','left_unpaid','payment_block_override','home_pickup_photo','paid_after_release') NOT NULL;

DELETE FROM schema_migrations WHERE version = '038_operator_share_returned';
