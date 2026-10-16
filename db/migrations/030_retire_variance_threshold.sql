-- =====================================================================
-- 030: retire the rev 468 camera-variance setting (16 Oct)
-- =====================================================================
-- variance_alert_threshold was read only by the rev 468 YOLOv8 audit
-- (`/audits/trigger`), which is retired with the AI node and the capture
-- app. Under rev 603 the phone's door events are checked against the
-- list instead (application/edge/checking.py), with no threshold, so
-- nothing reads this key. Left in place it would still show in Rules &
-- Settings as a setting that does nothing.
--
-- Removed keys go with their history, as in 024. The audit and
-- remittance tables of rev 468 / 514 stay: they hold history.
--
-- Reverse: db/migrations/down/030_retire_variance_threshold.sql
-- =====================================================================

DELETE FROM cooperative_policies WHERE policy_key = 'variance_alert_threshold';

INSERT INTO schema_migrations (version) VALUES ('030_retire_variance_threshold');
