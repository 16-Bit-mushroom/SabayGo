-- =====================================================================
-- 009_group_f_guards.sql
--
-- Adds the cancellation deadline, and an index supporting the van/driver
-- overlap check.
-- =====================================================================

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    -- Hours, not days: a 05:30 departure needs finer resolution than a
    -- day boundary can express. 0 means cancellation stays open until
    -- departure, which is the current behaviour.
    ('cancel_cutoff_hours', '2', 'int',
     'Hours before departure after which cancelling is refused. 0 = no deadline.'),
    ('hold_sweep_interval_seconds', '60', 'int',
     'How often abandoned payment holds are returned to the pool.'),
    ('licence_expiry_warning_days', '30', 'int',
     'Days before a driver licence expires that the office is warned.')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- The overlap check queries trips by van or driver on a service date.
-- Without these it scans every trip ever generated.
CREATE INDEX idx_trip_van_date    ON trips (van_id, service_date, status);
CREATE INDEX idx_trip_driver_date ON trips (driver_id, service_date, status);
CREATE INDEX idx_trip_conductor_date ON trips (conductor_id, service_date, status);

INSERT INTO schema_migrations (version) VALUES ('009_group_f_guards');
