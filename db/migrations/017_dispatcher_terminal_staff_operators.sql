-- =====================================================================
-- 017_dispatcher_terminal_staff_operators.sql
--
-- Roles of paper revision 468 (change brief, sections 3 and 7.1).
--
--   conductor   -> dispatcher        A2Z staff who rides the van
--   coop_admin  -> terminal_manager  decides what is owed, validates records
--   (new)          cashier           records payments, starts trips
--   driver      -> not a user        the operator: the van owner, who
--                                    always drives. A roster row in
--                                    `operators`, no login.
--
-- EXPAND ONLY. Each driver account becomes an `operators` row and its
-- login is set inactive, but the account itself stays: trips, audits,
-- remittances and SOS history point at it. 'driver' therefore stays in
-- the role ENUMs as a legacy value that no code path writes. Dropping it,
-- together with driver_credentials, trips.driver_id,
-- schedule_templates.default_* and driver_headcounts, is a later
-- contraction migration, approved separately.
--
-- vans.operator_id is NULL here and NOT NULL in the brief. It becomes
-- NOT NULL in that contraction, once every van has its operator; until
-- then UNIQUE already holds one van per operator (MySQL ignores NULLs
-- in a UNIQUE index).
--
-- Reverse: db/migrations/down/017_dispatcher_terminal_staff_operators.sql
-- =====================================================================

-- ------------------------------------------------------------- roles
-- MySQL cannot rename an ENUM member: widen, move the data, narrow
-- (same pattern as 010).
ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','conductor','driver','coop_admin','admin',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;

UPDATE users SET role = 'dispatcher'       WHERE role = 'conductor';
UPDATE users SET role = 'terminal_manager' WHERE role = 'coop_admin';

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin',
             'driver')
        NOT NULL;

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','coop_admin','driver','conductor',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;

UPDATE notifications SET audience = 'dispatcher'       WHERE audience = 'conductor';
UPDATE notifications SET audience = 'terminal_manager' WHERE audience = 'coop_admin';

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','dispatcher','terminal_manager','cashier','driver')
        NOT NULL;

ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','conductor','driver','coop_admin','admin',
             'dispatcher','terminal_manager','cashier')
        NOT NULL;

UPDATE sos_alerts SET raised_by_role = 'dispatcher'       WHERE raised_by_role = 'conductor';
UPDATE sos_alerts SET raised_by_role = 'terminal_manager' WHERE raised_by_role = 'coop_admin';

ALTER TABLE sos_alerts
    MODIFY COLUMN raised_by_role
        ENUM('passenger','dispatcher','terminal_manager','cashier','admin',
             'driver')
        NOT NULL;

-- messages.sender_role is a VARCHAR, so only the data moves.
UPDATE messages SET sender_role = 'dispatcher'       WHERE sender_role = 'conductor';
UPDATE messages SET sender_role = 'terminal_manager' WHERE sender_role = 'coop_admin';

-- 'conductor_driver' stays as a legacy kind: no new thread can be opened
-- with a driver, but the existing ones keep their history.
ALTER TABLE conversations
    MODIFY COLUMN kind
        ENUM('passenger_conductor','conductor_driver','office','passenger_dispatcher')
        NOT NULL;

UPDATE conversations SET kind = 'passenger_dispatcher' WHERE kind = 'passenger_conductor';

ALTER TABLE conversations
    MODIFY COLUMN kind
        ENUM('passenger_dispatcher','office','conductor_driver')
        NOT NULL;

-- ------------------------------------------------------------- trips
-- The foreign key keeps its old name, fk_trip_conductor: MySQL cannot
-- rename a constraint, and dropping and re-adding it is a full table
-- rebuild for a cosmetic gain.
ALTER TABLE trips RENAME COLUMN conductor_id TO dispatcher_id;
ALTER TABLE trips RENAME INDEX idx_trip_conductor_date TO idx_trip_dispatcher_date;

-- --------------------------------------------------------- operators
-- Paper Table 25. import_batch_id and its FK to data_transfers arrive
-- with that table (roster migration).
CREATE TABLE operators (
    operator_id        CHAR(36)     NOT NULL,
    full_name          VARCHAR(255) NOT NULL,
    contact_number     VARCHAR(20)  NOT NULL,
    email              VARCHAR(255) NULL,
    -- Where gateway fares settle (brief 2.1, ASSUMED). Free text until
    -- A2Z says what the reference looks like.
    payout_ref         VARCHAR(64)  NULL,
    license_number     VARCHAR(64)  NOT NULL,
    license_expiry     DATE         NOT NULL,
    membership_status  ENUM('active','suspended','inactive')
                       NOT NULL DEFAULT 'active',
    validation_status  ENUM('pending','validated','rejected','suspended')
                       NOT NULL DEFAULT 'pending',
    validated_by       CHAR(36)     NULL,
    validated_at       DATETIME(6)  NULL,
    -- The driver account this record was made from, by this migration.
    -- NULL for every operator entered after it. Lets the later
    -- contraction re-point trips.driver_id history at the operator.
    former_driver_user_id CHAR(36)  NULL,
    created_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                    ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (operator_id),
    UNIQUE KEY uq_operator_contact (contact_number),
    UNIQUE KEY uq_operator_license (license_number),
    UNIQUE KEY uq_operator_former_driver (former_driver_user_id),
    KEY idx_operator_validation (validation_status),
    CONSTRAINT fk_operator_validated_by
        FOREIGN KEY (validated_by) REFERENCES users (user_id),
    CONSTRAINT fk_operator_former_driver
        FOREIGN KEY (former_driver_user_id) REFERENCES users (user_id)
        ON DELETE SET NULL
) ENGINE=InnoDB;

-- One van per operator (brief 3): UNIQUE.
ALTER TABLE vans
    ADD COLUMN operator_id CHAR(36) NULL AFTER plate_number,
    ADD UNIQUE KEY uq_van_operator (operator_id),
    ADD CONSTRAINT fk_van_operator
        FOREIGN KEY (operator_id) REFERENCES operators (operator_id);

-- ----------------------------------------- drivers become operators
-- Pending, not validated: the Terminal Manager validates every roster
-- record (brief 8), and nobody has yet for these.
INSERT INTO operators
    (operator_id, full_name, contact_number, email,
     license_number, license_expiry, former_driver_user_id)
SELECT UUID(),
       CONCAT_WS(' ', sp.first_name, sp.middle_name, sp.last_name),
       u.phone_number,
       u.email,
       dc.license_number,
       dc.license_expiry_date,
       u.user_id
  FROM users u
  JOIN driver_credentials dc ON dc.user_id = u.user_id
  JOIN staff_profiles     sp ON sp.user_id = u.user_id
 WHERE u.role = 'driver';

-- Give a van its operator only where the history names exactly one
-- driver for that van and exactly one van for that driver. Anything else
-- is left NULL for the Terminal Manager: guessing an owner from who drove
-- most often would put a wrong name on the remittance statement.
-- (Temporary tables, because MySQL cannot open one twice in a query.)
CREATE TEMPORARY TABLE tmp_van_driver AS
SELECT DISTINCT van_id, driver_id FROM (
    SELECT van_id, driver_id FROM trips
     WHERE van_id IS NOT NULL AND driver_id IS NOT NULL
    UNION
    SELECT default_van_id, default_driver_id FROM schedule_templates
     WHERE default_van_id IS NOT NULL AND default_driver_id IS NOT NULL
) pairs;

CREATE TEMPORARY TABLE tmp_van_one_driver AS
SELECT van_id, MIN(driver_id) AS driver_id
  FROM tmp_van_driver GROUP BY van_id HAVING COUNT(*) = 1;

CREATE TEMPORARY TABLE tmp_driver_one_van AS
SELECT driver_id
  FROM tmp_van_driver GROUP BY driver_id HAVING COUNT(*) = 1;

UPDATE vans v
  JOIN tmp_van_one_driver d ON d.van_id    = v.van_id
  JOIN tmp_driver_one_van o ON o.driver_id = d.driver_id
  JOIN operators         op ON op.former_driver_user_id = d.driver_id
   SET v.operator_id = op.operator_id;

DROP TEMPORARY TABLE tmp_van_driver, tmp_van_one_driver, tmp_driver_one_van;

-- The operator has no login (brief 3). get_current_user already refuses
-- an inactive account, so a token issued before this migration stops
-- working too.
UPDATE staff_profiles sp
  JOIN users u ON u.user_id = sp.user_id
   SET sp.employment_status = 'inactive'
 WHERE u.role = 'driver';

UPDATE users SET account_status = 'inactive' WHERE role = 'driver';

-- Dev accounts follow the vocabulary, as in 010.
UPDATE users SET email = REPLACE(email, 'conductor', 'dispatcher')
 WHERE email LIKE 'conductor%@sabaygo.%';
UPDATE users SET email = REPLACE(email, 'coopadmin@', 'manager@')
 WHERE email LIKE 'coopadmin@sabaygo.%';

INSERT INTO schema_migrations (version)
VALUES ('017_dispatcher_terminal_staff_operators');
