-- =====================================================================
-- 021_terminal_settings_and_roster.sql
--
-- Paper revision 468, step 3 (settings and roster).
--
--   vans.operator_id   NOT NULL. POST /fleet/vans now names the operator
--                      (one van each, UNIQUE since 017), so every van has
--                      one. Runs first: on a database with an operator-less
--                      van it fails (error 1138) before anything changes.
--
--   cooperative_policies -> the brief's Table 33 TerminalSettings. One row
--                      per value a key has held, keyed (policy_key,
--                      effective_from). The value in force is the latest
--                      row whose effective_from has passed. A change is a
--                      NEW row, never an UPDATE, so the rate a statement
--                      was computed under stays on record; updated_by
--                      names the Terminal Manager who set it. data_type
--                      and description describe the key and are copied
--                      onto each new row by the application.
--                      Existing rows take effective_from = updated_at:
--                      when that value was last set, the earliest moment
--                      the record can vouch for it.
--
--   new keys           brief 4.2, 4.4, 4.5 and 7.3: start window, grace,
--                      silent-phone gap, retention mode and days, and the
--                      remittance rate. retention_mode and retention_days
--                      ship UNSET (''): the paper names no default and the
--                      brief forbids inventing one. While unset, nothing
--                      may delete evidence (the retention job, step 7).
--
-- Paper -> repo: TerminalSettings = cooperative_policies; SettingKey,
-- SettingValue, EffectiveFrom, UpdatedBy, UpdatedAt = policy_key,
-- policy_value, effective_from, updated_by, updated_at. RemittanceRate
-- 0.15 = remittance_rate_pct 15.00 (as remittances.rate_pct, 018);
-- StartOpensMin, StartGraceMin, HeartbeatGapS = start_opens_minutes,
-- start_grace_minutes, heartbeat_gap_seconds.
--
-- Reverse: db/migrations/down/021_terminal_settings_and_roster.sql
-- =====================================================================

-- --------------------------------------------------------- vans operator
-- MySQL refuses NULL -> NOT NULL on a foreign-key column while checks
-- are on (error 1832). The type is unchanged, so no reference can break;
-- a NULL row still fails the change (error 1138), which is the guard.
SET foreign_key_checks = 0;
ALTER TABLE vans
    MODIFY COLUMN operator_id CHAR(36) NOT NULL;
SET foreign_key_checks = 1;

-- --------------------------------------------------- settings history
ALTER TABLE cooperative_policies
    ADD COLUMN effective_from DATETIME(6) NOT NULL
               DEFAULT CURRENT_TIMESTAMP(6) AFTER policy_key,
    ADD COLUMN updated_by     CHAR(36)    NULL AFTER description,
    DROP PRIMARY KEY,
    ADD PRIMARY KEY (policy_key, effective_from),
    ADD CONSTRAINT fk_policy_updated_by
        FOREIGN KEY (updated_by) REFERENCES users (user_id);

-- updated_at = updated_at keeps ON UPDATE from restamping it.
UPDATE cooperative_policies
   SET effective_from = updated_at,
       updated_at     = updated_at;

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('remittance_rate_pct', '15.00', 'decimal',
     'Share of a van''s daily gross fares remitted to the cooperative, in percent'),
    ('start_opens_minutes', '30', 'int',
     'Minutes before departure that Start appears (assumed 30, to confirm with A2Z)'),
    ('start_grace_minutes', '10', 'int',
     'Minutes after departure before the system starts an unstarted trip itself (assumed 10)'),
    ('heartbeat_gap_seconds', '120', 'int',
     'Seconds without a status report before an edge phone counts as silent (placeholder)'),
    ('retention_mode', '', 'string',
     'Keep snapshots and GPS logs: fixed_days or until_settled. Unset keeps everything'),
    ('retention_days', '', 'int',
     'Days to keep snapshots and GPS logs when retention_mode is fixed_days. Unset keeps everything');

INSERT INTO schema_migrations (version)
VALUES ('021_terminal_settings_and_roster');
