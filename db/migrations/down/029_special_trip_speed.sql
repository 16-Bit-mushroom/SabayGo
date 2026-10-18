-- Reverses 029: the default speed limit for special trips.
DELETE FROM cooperative_policies WHERE policy_key = 'special_trip_speed_kmh';

DELETE FROM schema_migrations WHERE version = '029_special_trip_speed';
