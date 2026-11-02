-- Reverses 033: restores the gateway-era seat hold and its two settings
-- at their shipped values (001, 009), and removes unpaid_cutoff_min with
-- its history. Earlier history of the restored keys is not recovered.
--
-- hold_expires_at comes back empty. Nothing was in it: since 032 a
-- seat-leg has been claimed and bound in one transaction, so no row
-- could be left held for a sweeper to find.

ALTER TABLE notifications MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert','terminal_policy',
             'variance_alert','unremitted_fare','departure_reminder',
             'schedule_change','sos_alert',
             'capacity_alert','driving_flag',
             'special_trip_request','unconfirmed_trip_start','unaudited_trip',
             'trip_not_started','assignment_by_cashier','dispute_raised',
             'departed_more_than_listed','left_unpaid','payment_block_override',
             'home_pickup_photo')
        NOT NULL;

ALTER TABLE seat_inventory
    ADD COLUMN hold_expires_at DATETIME(6) NULL AFTER booking_id,
    ADD KEY idx_seat_hold_sweep (status, hold_expires_at);

DELETE FROM cooperative_policies WHERE policy_key = 'unpaid_cutoff_min';

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('seat_hold_ttl_seconds', '600', 'int',
     'How long a seat stays held awaiting payment'),
    ('hold_sweep_interval_seconds', '60', 'int',
     'How often the background sweeper releases expired seat holds'),
    ('cancel_cutoff_hours', '2', 'int',
     'Hours before departure after which cancellation is refused');

DELETE FROM schema_migrations WHERE version = '033_unpaid_cutoff';
