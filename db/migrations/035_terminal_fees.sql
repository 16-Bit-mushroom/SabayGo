-- =====================================================================
-- 035_terminal_fees.sql
-- Brief rev 721, item 13 and section 2.1 (DECIDED 2026-11-02): the
-- terminal fees and the operator's share.
--
-- A2Z's paper trip ticket carries two fixed fees beside the 15 %:
--
--   terminal fees owed    = rate x (B + W)
--                         + dcott_ticket_fee x trips      (P75 each)
--                         + parking_fee once per van per service day (P50)
--   operator's share owed = (B + W) - terminal fees owed, never below 0
--
-- The Dispatcher hands the terminal fees to the Cashier before Start and
-- the rest of the cash to the operator, at the counter, in the same
-- step; the Cashier records both. The system records amounts only and
-- never holds the money. The two fees are settings, dated like the rate,
-- are not fare lines, do not depend on the number of passengers and
-- cannot be disputed [ASSUMED].
--
-- Added to remittances (brief Table 32):
--   dcott_ticket_fee        the DCOTT ticket in force when the statement
--                           opened, kept like rate_pct so that a later
--                           change does not alter a statement already
--                           running
--   dcott_fees              dcott_ticket_fee x the van's trips of the
--                           day that count on the statement
--   parking_fee             the P50, charged once when the statement
--                           opens: for the van's first trip of the day,
--                           or by the Cashier's parking-only charge for
--                           a van with no trip (T65)
--   terminal_fees_owed      remittance_owed + dcott_fees + parking_fee
--   operator_share_owed     (B + W) - terminal_fees_owed, never below 0
--   operator_share_given    what the Dispatcher handed to the operator,
--   operator_share_given_at entered by the Cashier; adds up like
--   operator_share_recorded_by
--                           settled_amount. The operator has no account
--                           and does not sign [ASSUMED]
--
-- held_share now holds the P75 of a held trip beside its 15 %.
-- settled_amount adds up the terminal fees paid.
--
-- Settings: dcott_ticket_fee (75.00) and parking_fee (50.00). [OPEN]
-- A2Z confirms both, and whether the P75 applies to a special trip.
--
-- A statement opened before this migration charged neither fee: A2Z
-- collected them on paper. Its fixed fees stay 0 rather than be
-- invented, and its operator's share was never recorded.
--
-- Reverse: db/migrations/down/035_terminal_fees.sql
-- =====================================================================

ALTER TABLE remittances
    ADD COLUMN dcott_ticket_fee    DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER held_share,
    ADD COLUMN dcott_fees          DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER dcott_ticket_fee,
    ADD COLUMN parking_fee         DECIMAL(10,2) NOT NULL DEFAULT 0.00 AFTER dcott_fees,
    ADD COLUMN terminal_fees_owed  DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER parking_fee,
    ADD COLUMN operator_share_owed DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER terminal_fees_owed,
    ADD COLUMN operator_share_given DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER operator_share_owed,
    ADD COLUMN operator_share_given_at DATETIME(6) NULL AFTER operator_share_given,
    ADD COLUMN operator_share_recorded_by CHAR(36) NULL AFTER operator_share_given_at;

UPDATE remittances
   SET terminal_fees_owed  = remittance_owed,
       operator_share_owed = GREATEST(booked_income + walk_up_income - remittance_owed, 0);

ALTER TABLE remittances
    ADD CONSTRAINT fk_remittance_share_recorded_by
        FOREIGN KEY (operator_share_recorded_by) REFERENCES users (user_id),
    ADD CONSTRAINT chk_remittance_fees
        CHECK (dcott_ticket_fee >= 0 AND dcott_fees >= 0 AND parking_fee >= 0
               AND operator_share_owed >= 0 AND operator_share_given >= 0),
    ADD CONSTRAINT chk_remittance_terminal_fees
        CHECK (terminal_fees_owed = remittance_owed + dcott_fees + parking_fee),
    ADD CONSTRAINT chk_remittance_share_given
        CHECK ((operator_share_given_at IS NULL) = (operator_share_recorded_by IS NULL));

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('dcott_ticket_fee', '75.00', 'decimal',
     'The DCOTT ticket charged for each trip, in pesos, beside the 15 % remittance'),
    ('parking_fee', '50.00', 'decimal',
     'The parking fee charged once for each van each service day, in pesos, even when the van makes no trip');

INSERT INTO schema_migrations (version) VALUES ('035_terminal_fees');
