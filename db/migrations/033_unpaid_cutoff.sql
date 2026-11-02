-- =====================================================================
-- 033_unpaid_cutoff.sql
-- Brief rev 721, sections 2.1 and 4.2 rule 15: an unpaid reservation is
-- released at a cutoff before departure.
--
-- 032 made the seat cash-only: a reservation is CONFIRMED and UNPAID
-- from the moment it is made, and the Dispatcher's Mark as Paid is what
-- puts it on the passenger list. This migration retires what is left of
-- the gateway-era seat hold and gives the release job its setting.
--
-- Added:
--   unpaid_cutoff_min          minutes before departure at which an
--                              unpaid reservation is released. Default
--                              30, the same as the start window, so the
--                              list is settled when Start opens
--                              (DECIDED 2026-11-02, brief item 12a)
--   notifications 'paid_after_release'
--                              the Terminal Manager's alert when an
--                              offline Mark as Paid arrives after the
--                              seat was released and taken (T63)
--
-- Removed:
--   cancel_cutoff_hours        cancellation no longer closes a set
--                              number of hours before departure: a paid
--                              seat can be cancelled until the
--                              passenger list locks, and an unpaid one
--                              until the van leaves (brief 7.3). Its
--                              reader went with the gateway in 032, so
--                              the key has been showing in Rules &
--                              Settings as a deadline that nothing
--                              enforces. `refund_enabled`, the other
--                              setting brief 14 asks A2Z about, went in
--                              032
--   seat_hold_ttl_seconds      a reservation no longer waits on a
--   hold_sweep_interval_seconds
--                              gateway, so no hold lapses in seconds.
--                              `HoldReleaseS` is replaced by
--                              `UnpaidCutoffMin` (brief 2.1, 7.3)
--   seat_inventory.hold_expires_at and idx_seat_hold_sweep
--                              since 032 a seat-leg is claimed and
--                              bound inside one transaction, so no row
--                              can outlive it as 'held' and the column
--                              was always NULL. A sweeper that can
--                              never find anything, and a column that
--                              is never set, read in the console as
--                              machinery that does something (T60)
--
-- The seat of an unpaid reservation is held by the booking, not by a
-- timer on the inventory row: releasing it is a decision about the
-- booking (status, cancel_reason, who is notified), which is why it
-- lives in the release job and not in the allocator.
--
-- Reverse: db/migrations/down/033_unpaid_cutoff.sql
-- =====================================================================

-- ------------------------------------------------------------ preflight
-- After this migration nothing releases a 'held' seat-leg: the sweeper
-- is gone and the column it swept on with it. A row left held would be
-- a seat lost from the 14 for good, so 033 stops rather than strand it.
-- (Under 032 this cannot happen -- allocate, bind and confirm are one
-- transaction -- but a database upgraded from an older revision mid-
-- checkout could still carry one.)
DROP PROCEDURE IF EXISTS m033_preflight;
DELIMITER $$
CREATE PROCEDURE m033_preflight()
BEGIN
  IF EXISTS (SELECT 1 FROM seat_inventory WHERE status = 'held') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
      '033 stopped: a seat-leg is still held. Run the hold sweep on the old code, or release it by hand, before dropping hold_expires_at.';
  END IF;
END$$
DELIMITER ;
CALL m033_preflight();
DROP PROCEDURE m033_preflight;

-- ------------------------------------------------------------ the setting
INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('unpaid_cutoff_min', '30', 'int',
     'Minutes before departure at which an unpaid reservation is released and its seat freed for a walk-up');

-- A key is deleted with its whole history (as in 030): a retired setting
-- left behind still shows in Rules & Settings as a rule that does
-- nothing.
DELETE FROM cooperative_policies
 WHERE policy_key IN ('seat_hold_ttl_seconds', 'hold_sweep_interval_seconds',
                      'cancel_cutoff_hours');

-- ---------------------------------------------------- the gateway-era hold
ALTER TABLE seat_inventory
    DROP INDEX idx_seat_hold_sweep,
    DROP COLUMN hold_expires_at;

-- ------------------------------------------------------- notifications
-- Widen only: no existing row changes type.
ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_photo','paid_after_release')
        NOT NULL;

INSERT INTO schema_migrations (version) VALUES ('033_unpaid_cutoff');
