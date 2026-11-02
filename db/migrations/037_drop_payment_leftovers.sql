-- =====================================================================
-- 037_drop_payment_leftovers.sql
-- Brief rev 721, T60 and section 7.1: no screen, endpoint, setting or
-- table field for an online payment or a QR ticket remains.
--
-- 032 dropped the gateway, the QR on the booking and the `payments`
-- table. The T60 sweep found what it did not reach:
--
--   operators.payout_ref  where gateway fares would settle to the
--                         operator (017, ASSUMED). Section 7.1 removes
--                         `Operators.PayoutRef` by name; the operator
--                         takes the share in cash at the counter
--   physical_tickets      pre-printed paper tickets carrying a QR, and
--   ticket_booklets       the booklets they were issued in (006). No
--                         model, endpoint or screen ever used them, and
--                         the Dispatcher now lists cash passengers by
--                         hand
--
-- Kept: `cash_remittances` (008). Its `declared_amount` is the crew's
-- count of a cash handover, not the retired income group, and the table
-- stays as history (PROGRESS_LOG, R10).
--
-- Reverse: db/migrations/down/037_drop_payment_leftovers.sql
-- =====================================================================

-- ------------------------------------------------------------ preflight
-- All three are empty in every database built from these migrations. A
-- row in one would be data the drop cannot give back, so 037 stops.
DROP PROCEDURE IF EXISTS m037_preflight;
DELIMITER $$
CREATE PROCEDURE m037_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM operators WHERE payout_ref IS NOT NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '037 stopped: an operator has a payout reference. Export it before dropping the column.';
  END IF;
  IF EXISTS (SELECT 1 FROM physical_tickets) OR EXISTS (SELECT 1 FROM ticket_booklets) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '037 stopped: a paper ticket booklet is recorded. Export it before dropping the tables.';
  END IF;
END$$
DELIMITER ;
CALL m037_preflight();
DROP PROCEDURE m037_preflight;

ALTER TABLE operators DROP COLUMN payout_ref;

DROP TABLE physical_tickets;
DROP TABLE ticket_booklets;

INSERT INTO schema_migrations (version) VALUES ('037_drop_payment_leftovers');
