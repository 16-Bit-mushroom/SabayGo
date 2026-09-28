-- =====================================================================
-- 015_walkin_idempotency.sql
-- Offline conductor manifest (walk-in logging): a queued walk-in may be
-- retried by the mobile sync client after a connectivity drop whose
-- outcome is unknown to the device (request may have already reached
-- the server). client_request_id lets /bookings/walk-in recognise a
-- replay and return the original booking instead of creating a second
-- one. NULL for every other booking path (app, driver-issued, and any
-- walk-in logged online where no retry ever happens) -- MySQL treats
-- multiple NULLs in a unique index as distinct, so they are unaffected.
-- =====================================================================

ALTER TABLE bookings
    ADD COLUMN client_request_id VARCHAR(64) NULL AFTER pickup_landmark,
    ADD UNIQUE KEY uq_bookings_client_request (trip_id, client_request_id);

INSERT INTO schema_migrations (version) VALUES ('015_walkin_idempotency');
