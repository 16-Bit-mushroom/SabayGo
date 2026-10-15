-- =====================================================================
-- 029: the default speed limit for special trips (rev 603 brief 2.5)
-- =====================================================================
-- A special trip (a van rental) has no fixed route, so no stretches with
-- limits and no stop zones. "Overspeed uses a default limit set by the
-- Terminal Manager (SpecialTripSpeedKmh)" (2.5). The brief gives no
-- value, so it ships unset: no rental is flagged until A2Z sets one.
-- Only overspeed applies to a rental; stops need stop zones.
--
-- Reverse: db/migrations/down/029_special_trip_speed.sql
-- =====================================================================

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('special_trip_speed_kmh', '', 'int',
     'Speed limit for a special trip, which has no route of its own. Unset: rentals are not flagged for overspeed');

INSERT INTO schema_migrations (version) VALUES ('029_special_trip_speed');
