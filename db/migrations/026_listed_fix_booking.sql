-- =====================================================================
-- 026: a boarding the Dispatcher listed names the booking that listed it
-- =====================================================================
-- Rev 603 brief 2.4, 6.1: more aboard than listed is fixed by listing the
-- person (destination, fare, the 15 % on it) -- ResolutionStatus
-- 'listed'. 018 let only a boarding matched by time carry a booking, so
-- the fix could not say which entry was its own: the audit trail lost it,
-- and the entry stayed free to be matched to a different boarding. Now a
-- listed boarding carries its fix too.
--
-- Reverse: db/migrations/down/026_listed_fix_booking.sql
-- =====================================================================

ALTER TABLE passenger_events
    DROP CHECK chk_event_booking_only_if_matched,
    ADD CONSTRAINT chk_event_booking_only_if_matched
        CHECK (matched_booking_id IS NULL
               OR match_status IN ('matched_qr','matched_log')
               OR resolution_status = 'listed');

INSERT INTO schema_migrations (version) VALUES ('026_listed_fix_booking');
