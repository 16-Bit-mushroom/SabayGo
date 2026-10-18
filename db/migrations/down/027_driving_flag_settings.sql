-- Reverses 027: the driving-flag thresholds.
DELETE FROM cooperative_policies
 WHERE policy_key IN ('overspeed_seconds','stop_seconds','slow_tolerance_pct',
                      'expected_speed_kmh','standstill_kmh');

DELETE FROM schema_migrations WHERE version = '027_driving_flag_settings';
