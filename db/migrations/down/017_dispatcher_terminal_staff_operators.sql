-- =====================================================================
-- Reverses 017_dispatcher_terminal_staff_operators.sql.
-- Run with: ./db/rollback.sh 017_dispatcher_terminal_staff_operators
--
-- Two things do not come back exactly:
--   * cashier has no old equivalent and returns as coop_admin, the old
--     word for office staff;
--   * every driver account is reactivated, including one that was
--     already suspended or inactive before 017 ran.
-- Operator records entered after 017 are deleted with the table.
-- =====================================================================

UPDATE users SET email = REPLACE(email, 'manager@', 'coopadmin@')
 WHERE email LIKE 'manager@sabaygo.%';
UPDATE users SET email = REPLACE(email, 'dispatcher', 'conductor')
 WHERE email LIKE 'dispatcher%@sabaygo.%';

UPDATE users SET account_status = 'active' WHERE role = 'driver';
UPDATE staff_profiles sp
  JOIN users u ON u.user_id = sp.user_id
   SET sp.employment_status = 'active'
 WHERE u.role = 'driver';

ALTER TABLE vans
    DROP FOREIGN KEY fk_van_operator,
    DROP INDEX uq_van_operator,
    DROP COLUMN operator_id;

DROP TABLE operators;

ALTER TABLE trips RENAME INDEX idx_trip_dispatcher_date TO idx_trip_conductor_date;
ALTER TABLE trips RENAME COLUMN dispatcher_id TO conductor_id;

ALTER TABLE conversations
    MODIFY COLUMN kind
        ENUM('passenger_conductor','conductor_driver','office','passenger_dispatcher')
        NOT NULL;
UPDATE conversations SET kind = 'passenger_conductor' WHERE kind = 'passenger_dispatcher';
ALTER TABLE conversations
    MODIFY COLUMN kind ENUM('passenger_conductor','conductor_driver','office') NOT NULL;

UPDATE messages SET sender_role = 'conductor'  WHERE sender_role = 'dispatcher';
UPDATE messages SET sender_role = 'coop_admin' WHERE sender_role IN ('terminal_manager','cashier');

ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','conductor','driver','coop_admin','admin',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;
UPDATE sos_alerts SET raised_by_role = 'conductor'  WHERE raised_by_role = 'dispatcher';
UPDATE sos_alerts SET raised_by_role = 'coop_admin' WHERE raised_by_role IN ('terminal_manager','cashier');
ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','conductor','driver','coop_admin','admin') NOT NULL;

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','coop_admin','driver','conductor',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;
UPDATE notifications SET audience = 'conductor'  WHERE audience = 'dispatcher';
UPDATE notifications SET audience = 'coop_admin' WHERE audience IN ('terminal_manager','cashier');
ALTER TABLE notifications
    MODIFY COLUMN audience ENUM('passenger','coop_admin','driver','conductor') NOT NULL;

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','conductor','driver','coop_admin','admin',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;
UPDATE users SET role = 'conductor'  WHERE role = 'dispatcher';
UPDATE users SET role = 'coop_admin' WHERE role IN ('terminal_manager','cashier');
ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','conductor','driver','coop_admin','admin') NOT NULL;

DELETE FROM schema_migrations WHERE version = '017_dispatcher_terminal_staff_operators';
