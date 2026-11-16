-- Down for 039_walk_in: the names back to walk-up. Amounts untouched.

ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('booked','walk_up','walk_in') NOT NULL;
UPDATE remittance_lines SET income_group = 'walk_up' WHERE income_group = 'walk_in';
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('booked','walk_up') NOT NULL;

ALTER TABLE remittances DROP CHECK chk_remittance_amounts;
ALTER TABLE remittances
    RENAME COLUMN walk_in_income TO walk_up_income;
ALTER TABLE remittances
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (booked_income >= 0 AND walk_up_income >= 0 AND remittance_owed >= 0
               AND held_share >= 0 AND settled_amount >= 0);

DELETE FROM schema_migrations WHERE version = '039_walk_in';
