-- =====================================================================
-- 010_rename_operator_to_coop_admin.sql
--
-- WHY THIS RENAME
--
-- In Philippine transport regulation an "operator" is the franchise
-- holder -- the person or entity holding the Certificate of Public
-- Convenience from LTFRB, usually the van owner. LTFRB's own complaint
-- guidance treats driver, conductor, dispatcher and operator as four
-- distinct parties.
--
-- Our `operator` role does none of what a franchise holder does. It
-- configures fleet, provisions crew, sets fares and schedules, resolves
-- audits and reads revenue -- that is cooperative office staff.
--
-- Leaving it named `operator` invites a reader from a transport
-- background to conclude the system grants a van owner cooperative-wide
-- authority, which is both wrong and a poor thing to have to explain at
-- defence. Renamed to `coop_admin`.
--
-- A future `franchise_operator` role -- a van owner seeing revenue for
-- their own units only -- is left to Future Work.
-- =====================================================================

-- MySQL cannot rename an ENUM member, so the column is widened to hold
-- both values, the data is moved, then the old value is dropped. Doing
-- it in one ALTER would fail: every existing row would violate the new
-- definition at the moment it is applied.

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','conductor','driver','operator','coop_admin','admin')
        NOT NULL;

UPDATE users SET role = 'coop_admin' WHERE role = 'operator';

ALTER TABLE users
    MODIFY COLUMN role
        ENUM('passenger','conductor','driver','coop_admin','admin')
        NOT NULL;

-- Notification audiences follow the same rename.
ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','operator','coop_admin','driver','conductor')
        NOT NULL;

UPDATE notifications SET audience = 'coop_admin' WHERE audience = 'operator';

ALTER TABLE notifications
    MODIFY COLUMN audience
        ENUM('passenger','coop_admin','driver','conductor')
        NOT NULL;

-- Seed accounts, so the dev login matches the new vocabulary.
UPDATE users
   SET email = REPLACE(email, 'operator@', 'coopadmin@')
 WHERE email LIKE 'operator@%';

INSERT INTO schema_migrations (version)
VALUES ('010_rename_operator_to_coop_admin');