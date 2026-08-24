-- =====================================================================
-- 002_identity.sql
--
-- CHANGE FROM YOUR OLD SCHEMA -- read this before you redraw the ERD.
--
-- The old design had credentials scattered across Passengers and
-- TerminalStaff, and NONE at all on Drivers or Conductors. But your own
-- functional requirements say drivers confirm headcounts and conductors
-- scan QR codes -- both of which require logging in. The old schema
-- literally could not authenticate two of your four roles.
--
-- Fix: one `users` table owns identity and credentials for everybody;
-- role-specific attributes live in profile tables keyed 1:1 on user_id.
-- This is textbook single-table-inheritance-with-extension and is easy
-- to defend to a panel.
-- =====================================================================

CREATE TABLE users (
    user_id         CHAR(36)     NOT NULL,
    email           VARCHAR(255) NOT NULL,
    phone_number    VARCHAR(20)  NULL,
    password_hash   VARCHAR(255) NOT NULL,   -- bcrypt / argon2, never plaintext
    role            ENUM('passenger','conductor','driver','operator','admin') NOT NULL,
    account_status  ENUM('active','suspended','inactive') NOT NULL DEFAULT 'active',
    -- Firebase Cloud Messaging registration token for push delivery.
    fcm_token       VARCHAR(512) NULL,
    last_login_at   DATETIME(6)  NULL,
    created_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                 ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email (email),
    UNIQUE KEY uq_users_phone (phone_number),
    KEY idx_users_role_status (role, account_status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- passenger_profiles
-- ---------------------------------------------------------------------
CREATE TABLE passenger_profiles (
    user_id                    CHAR(36)     NOT NULL,
    first_name                 VARCHAR(70)  NOT NULL,
    middle_name                VARCHAR(70)  NULL,
    last_name                  VARCHAR(100) NOT NULL,
    home_address               VARCHAR(255) NULL,
    gender                     ENUM('male','female','other','undisclosed') NULL,
    emergency_contact_name     VARCHAR(150) NULL,
    emergency_contact_relation VARCHAR(50)  NULL,
    emergency_contact_number   VARCHAR(20)  NULL,
    avatar_url                 VARCHAR(512) NULL,
    trust_rating               DECIMAL(2,1) NOT NULL DEFAULT 5.0,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_passenger_profile_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT chk_trust_rating CHECK (trust_rating BETWEEN 0.0 AND 5.0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- staff_profiles -- operators, conductors, drivers
-- ---------------------------------------------------------------------
CREATE TABLE staff_profiles (
    user_id              CHAR(36)     NOT NULL,
    first_name           VARCHAR(70)  NOT NULL,
    middle_name          VARCHAR(70)  NULL,
    last_name            VARCHAR(100) NOT NULL,
    birth_date           DATE         NULL,
    gender               ENUM('male','female','other','undisclosed') NULL,
    home_address         VARCHAR(255) NULL,
    profile_pic_url      VARCHAR(512) NULL,
    cooperative_name     VARCHAR(255) NULL,
    assigned_terminal_id CHAR(36)     NULL,
    employment_status    ENUM('active','suspended','inactive') NOT NULL DEFAULT 'active',
    PRIMARY KEY (user_id),
    KEY idx_staff_terminal (assigned_terminal_id),
    CONSTRAINT fk_staff_profile_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_staff_profile_terminal
        FOREIGN KEY (assigned_terminal_id) REFERENCES terminals (terminal_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- driver_credentials -- only rows for users whose role = 'driver'
-- ---------------------------------------------------------------------
CREATE TABLE driver_credentials (
    user_id              CHAR(36)     NOT NULL,
    license_number       VARCHAR(64)  NOT NULL,
    license_expiry_date  DATE         NOT NULL,
    cttmo_id_number      VARCHAR(64)  NULL,
    cttmo_id_photo_url   VARCHAR(512) NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_license_number (license_number),
    CONSTRAINT fk_driver_cred_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- passenger_settings
-- ---------------------------------------------------------------------
CREATE TABLE passenger_settings (
    user_id            CHAR(36) NOT NULL,
    push_enabled       BOOLEAN  NOT NULL DEFAULT TRUE,
    tailored_schedules BOOLEAN  NOT NULL DEFAULT TRUE,
    trip_updates       BOOLEAN  NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_passenger_settings_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- saved_destinations
-- ---------------------------------------------------------------------
CREATE TABLE saved_destinations (
    destination_id CHAR(36)     NOT NULL,
    user_id        CHAR(36)     NOT NULL,
    label          VARCHAR(255) NOT NULL,
    terminal_id    CHAR(36)     NULL,
    address        VARCHAR(255) NULL,
    created_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (destination_id),
    KEY idx_saved_dest_user (user_id),
    CONSTRAINT fk_saved_dest_user
        FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_saved_dest_terminal
        FOREIGN KEY (terminal_id) REFERENCES terminals (terminal_id) ON DELETE SET NULL
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('002_identity');
