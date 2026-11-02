-- =====================================================================
-- 034_income_groups.sql
-- Brief rev 721, item 3 and section 2.1: the income groups are Booked
-- (B) and Walk-up (W), so Equation (2) reads
--
--     remittance owed = rate x (B + W)
--
-- B is the seats reserved in the app that the Dispatcher marked as paid,
-- including a home-pickup seat and a special trip requested in the app.
-- W is the cash walk-ups the Dispatcher listed, and a special trip
-- entered at the counter. They replace Verified (V) and Declared (D),
-- whose names said whether a gateway reference existed -- and since 032
-- there is no gateway. Every fare is cash handed to the Dispatcher; the
-- group says only where the seat came from.
--
-- A rename, not a rule change: the backend has grouped by the seat's
-- origin since 032, so each row maps one to one (verified -> booked,
-- declared -> walk_up) and every total stays as it was.
--
-- Renamed:
--   remittances.verified_income  -> booked_income
--   remittances.declared_income  -> walk_up_income
--   remittance_lines.income_group  ENUM('verified','declared')
--                               -> ENUM('booked','walk_up')
--
-- estimated_income and amount_at_risk, which rev 721 also removes, went
-- in 024.
--
-- Reverse: db/migrations/down/034_income_groups.sql
-- =====================================================================

-- MySQL refuses to rename a column a CHECK constraint names.
ALTER TABLE remittances DROP CHECK chk_remittance_amounts;

ALTER TABLE remittances
    RENAME COLUMN verified_income TO booked_income,
    RENAME COLUMN declared_income TO walk_up_income;

ALTER TABLE remittances
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (booked_income >= 0 AND walk_up_income >= 0 AND remittance_owed >= 0
               AND held_share >= 0 AND settled_amount >= 0);

-- Widen, map, narrow.
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('verified','declared','booked','walk_up') NOT NULL;
UPDATE remittance_lines SET income_group = 'booked'  WHERE income_group = 'verified';
UPDATE remittance_lines SET income_group = 'walk_up' WHERE income_group = 'declared';
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('booked','walk_up') NOT NULL;

INSERT INTO schema_migrations (version) VALUES ('034_income_groups');
