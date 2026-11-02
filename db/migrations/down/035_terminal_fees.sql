-- Reverses 035: the statement goes back to the 15 % alone. The fixed
-- fees and the operator's share recorded since are lost, and so is the
-- history of the two settings.

ALTER TABLE remittances
    DROP CHECK chk_remittance_share_given,
    DROP CHECK chk_remittance_terminal_fees,
    DROP CHECK chk_remittance_fees,
    DROP FOREIGN KEY fk_remittance_share_recorded_by;

ALTER TABLE remittances
    DROP COLUMN operator_share_recorded_by,
    DROP COLUMN operator_share_given_at,
    DROP COLUMN operator_share_given,
    DROP COLUMN operator_share_owed,
    DROP COLUMN terminal_fees_owed,
    DROP COLUMN parking_fee,
    DROP COLUMN dcott_fees,
    DROP COLUMN dcott_ticket_fee;

DELETE FROM cooperative_policies WHERE policy_key IN ('dcott_ticket_fee', 'parking_fee');

DELETE FROM schema_migrations WHERE version = '035_terminal_fees';
