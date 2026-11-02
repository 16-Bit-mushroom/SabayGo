-- =====================================================================
-- 036_drop_match_window.sql
-- Brief rev 721, sections 5.2 and 6.1: a boarding is matched to the
-- passenger list with no time window.
--
-- A boarding is listed while an unmatched paid seat or walk-up entry
-- remains on the trip's list, and each matches one boarding only (T57,
-- T59). That rule replaced the window in 032, because the window was
-- measured from a QR scan or a payment row, and 032 dropped both. Since
-- then nothing has read `match_window_seconds`: it has been showing in
-- Rules & Settings as a rule that does nothing.
--
-- Removed:
--   match_window_seconds  with its whole history, as in 030 and 033
--
-- Reverse: db/migrations/down/036_drop_match_window.sql
-- =====================================================================

DELETE FROM cooperative_policies WHERE policy_key = 'match_window_seconds';

INSERT INTO schema_migrations (version) VALUES ('036_drop_match_window');
