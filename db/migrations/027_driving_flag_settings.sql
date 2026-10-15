-- =====================================================================
-- 027: the driving-flag thresholds (rev 603 brief 6.4)
-- =====================================================================
-- "All thresholds are configurable settings of A2Z" (6.4); the sample
-- values are the brief's (TerminalSettings OverspeedSeconds, StopSeconds,
-- SlowTolerance, ExpectedSpeedKmh). The standstill speed is the rule's
-- "2 km/h or less", kept a setting with the rest. Each stretch's speed
-- limit, length and expected time are rows of route_stretches (018).
--
-- Reverse: db/migrations/down/027_driving_flag_settings.sql
-- =====================================================================

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('overspeed_seconds', '10', 'int',
     'Seconds above a stretch''s speed limit that make an overspeed flag'),
    ('stop_seconds', '120', 'int',
     'A standstill away from every stop longer than this is an unscheduled stop; shorter, an en-route stop (recorded, not flagged)'),
    ('slow_tolerance_pct', '25', 'decimal',
     'A stretch taking more than this percent above its expected time, less any home-pickup wait, is a slow stretch'),
    ('expected_speed_kmh', '55', 'int',
     'Average speed behind each stretch''s expected time, applied when the stretch is saved'),
    ('standstill_kmh', '2', 'decimal',
     'At or below this speed the van is standing still');

INSERT INTO schema_migrations (version) VALUES ('027_driving_flag_settings');
