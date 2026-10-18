-- =====================================================================
-- Reverses 021_terminal_settings_and_roster.sql.
-- Run with: ./db/rollback.sh 021_terminal_settings_and_roster
--
-- The guard stops the rollback, changing nothing, if any policy has
-- more than one value on record: the pre-021 table holds one value per
-- key, and choosing which to keep is a decision, not a rollback. Delete
-- the rows you do not want by hand first.
--
-- Lost with the columns: who set each value (updated_by) and since when
-- (effective_from).
-- =====================================================================

-- The guard: a temporary table (gone with the session, so a refusal
-- leaves nothing behind) whose CHECK fails while history exists:
-- "Check constraint 'one_value_per_policy_key' is violated."
CREATE TEMPORARY TABLE m021_down_guard (
    extra_values INT NOT NULL,
    CONSTRAINT one_value_per_policy_key CHECK (extra_values = 0)
);
INSERT INTO m021_down_guard
SELECT COUNT(*) - COUNT(DISTINCT policy_key) FROM cooperative_policies;
DROP TEMPORARY TABLE m021_down_guard;

DELETE FROM cooperative_policies
 WHERE policy_key IN ('remittance_rate_pct', 'start_opens_minutes',
                      'start_grace_minutes', 'heartbeat_gap_seconds',
                      'retention_mode', 'retention_days');

ALTER TABLE cooperative_policies
    DROP FOREIGN KEY fk_policy_updated_by;
ALTER TABLE cooperative_policies
    DROP COLUMN updated_by,
    DROP PRIMARY KEY,
    ADD PRIMARY KEY (policy_key),
    DROP COLUMN effective_from;

SET foreign_key_checks = 0;
ALTER TABLE vans
    MODIFY COLUMN operator_id CHAR(36) NULL;
SET foreign_key_checks = 1;

DELETE FROM schema_migrations WHERE version = '021_terminal_settings_and_roster';
