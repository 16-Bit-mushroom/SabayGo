-- Reverses 034: the income groups go back to Verified and Declared. Each
-- row maps one to one, so nothing is lost either way.

ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('verified','declared','booked','walk_up') NOT NULL;
UPDATE remittance_lines SET income_group = 'verified' WHERE income_group = 'booked';
UPDATE remittance_lines SET income_group = 'declared' WHERE income_group = 'walk_up';
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('verified','declared') NOT NULL;

ALTER TABLE remittances DROP CHECK chk_remittance_amounts;

ALTER TABLE remittances
    RENAME COLUMN booked_income  TO verified_income,
    RENAME COLUMN walk_up_income TO declared_income;

ALTER TABLE remittances
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (verified_income >= 0 AND declared_income >= 0 AND remittance_owed >= 0
               AND held_share >= 0 AND settled_amount >= 0);

DELETE FROM schema_migrations WHERE version = '034_income_groups';
