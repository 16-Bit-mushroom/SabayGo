-- =====================================================================
-- 038_operator_share_returned.sql
-- Alpha finding 35 (10 Nov): an operator's share given over what is owed.
--
-- The operator's share given adds up (035), and what is owed is worked out
-- again whenever the statement changes. A dispute decided Upheld takes its
-- line's fares off the statement, so a share already handed over can end
-- up above the share now owed: the operator holds cash that is not theirs.
-- Until now that showed only as "Differs by" once every list was locked,
-- and nothing could record the operator handing it back, because the
-- amounts only add.
--
--   operator_share_returned     what the operator handed back to the
--                               Cashier; never above what was given
--   operator_share_returned_at  when, and
--   operator_share_returned_by  who recorded it
--
-- Given is kept as it was handed over, so the record shows both moves;
-- the share held by the operator is given - returned.
--
-- notifications.type gains 'share_over_given': the Cashier is told when a
-- decision leaves the operator holding more than the share.
-- =====================================================================

ALTER TABLE remittances
    ADD COLUMN operator_share_returned DECIMAL(12,2) NOT NULL DEFAULT 0.00
        AFTER operator_share_recorded_by,
    ADD COLUMN operator_share_returned_at DATETIME(6) NULL AFTER operator_share_returned,
    ADD COLUMN operator_share_returned_by CHAR(36) NULL AFTER operator_share_returned_at;

ALTER TABLE remittances
    ADD CONSTRAINT fk_remittance_share_returned_by
        FOREIGN KEY (operator_share_returned_by) REFERENCES users (user_id),
    ADD CONSTRAINT chk_remittance_share_returned
        CHECK (operator_share_returned >= 0
               AND operator_share_returned <= operator_share_given),
    ADD CONSTRAINT chk_remittance_share_returned_by
        CHECK ((operator_share_returned_at IS NULL) = (operator_share_returned_by IS NULL));

ALTER TABLE notifications MODIFY COLUMN type
    ENUM('trip_update','tailored_schedule','system_alert','terminal_policy','variance_alert','unremitted_fare','departure_reminder','schedule_change','sos_alert','capacity_alert','driving_flag','special_trip_request','unconfirmed_trip_start','unaudited_trip','trip_not_started','assignment_by_cashier','dispute_raised','departed_more_than_listed','left_unpaid','payment_block_override','home_pickup_photo','paid_after_release','share_over_given') NOT NULL;

INSERT INTO schema_migrations (version) VALUES ('038_operator_share_returned');
