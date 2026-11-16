-- 039_walk_in: the second income group is Walk-in (W), not Walk-up.
--
-- The owner's decision (12 Nov 2026): a passenger the Dispatcher lists at
-- the van is a walk-in, before departure and after, on every screen and
-- in the data, matching the booking type that was already 'walk_in'.
-- The letter W and every amount stay as they are; only names change.
--
--   remittances.walk_up_income      -> walk_in_income
--   remittance_lines.income_group   ENUM('booked','walk_up')
--                                -> ENUM('booked','walk_in')
--
-- The amounts check names the column, so it is dropped and made again.
-- Down: db/migrations/down/039_walk_in.sql.

ALTER TABLE remittances DROP CHECK chk_remittance_amounts;
ALTER TABLE remittances
    RENAME COLUMN walk_up_income TO walk_in_income;
ALTER TABLE remittances
    ADD CONSTRAINT chk_remittance_amounts
        CHECK (booked_income >= 0 AND walk_in_income >= 0 AND remittance_owed >= 0
               AND held_share >= 0 AND settled_amount >= 0);

ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('booked','walk_up','walk_in') NOT NULL;
UPDATE remittance_lines SET income_group = 'walk_in' WHERE income_group = 'walk_up';
ALTER TABLE remittance_lines
    MODIFY COLUMN income_group ENUM('booked','walk_in') NOT NULL;

INSERT INTO schema_migrations (version) VALUES ('039_walk_in');
