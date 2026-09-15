-- =====================================================================
-- 012_check_in_undo.sql
--
-- Group D.2: a passenger may withdraw an accidental "I'm here".
--
-- The check_ins row is never deleted -- it is evidence for the accuracy
-- analysis whether or not the passenger later changed their mind. The
-- undo is recorded on the row it reverses, so the trail reads:
-- accepted -> undone -> (possibly) accepted again as a new row.
-- =====================================================================

ALTER TABLE check_ins
    ADD COLUMN undone_at DATETIME(6) NULL AFTER checked_in_at;

INSERT INTO schema_migrations (version) VALUES ('012_check_in_undo');
