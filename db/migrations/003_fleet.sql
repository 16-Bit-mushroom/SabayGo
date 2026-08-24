-- =====================================================================
-- 003_fleet.sql
--
-- Scope note from the consultation: fleet management is driver + van +
-- route/schedule + MONITORING ONLY. There is deliberately no maintenance
-- scheduling, no service history, no parts or cost tracking here.
-- `operational_status` is a flag, not a module. Say this explicitly in
-- your Scope and Limitations section.
-- =====================================================================

CREATE TABLE vans (
    van_id              CHAR(36)          NOT NULL,
    plate_number        VARCHAR(20)       NOT NULL,
    cpc_case_no         VARCHAR(64)       NULL,
    cpc_number          VARCHAR(64)       NULL,
    brand               VARCHAR(64)       NULL,
    model               VARCHAR(64)       NULL,
    color               VARCHAR(32)       NULL,
    seat_capacity       TINYINT UNSIGNED  NOT NULL DEFAULT 14,
    operational_status  ENUM('active','maintenance','inactive') NOT NULL DEFAULT 'active',
    registered_route_id CHAR(36)          NULL,

    -- Consultation item: "Van has camera for headcount purposes."
    -- Ask A2Z at the pitch whether cameras are ALREADY installed --
    -- if yes, your feasibility argument and hardware cost both improve
    -- dramatically. Track it per unit, not as a blanket assumption.
    has_cabin_camera    BOOLEAN           NOT NULL DEFAULT FALSE,
    camera_installed_at DATE              NULL,
    camera_device_id    VARCHAR(64)       NULL,

    created_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at          DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                          ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (van_id),
    UNIQUE KEY uq_van_plate (plate_number),
    UNIQUE KEY uq_van_camera_device (camera_device_id),
    KEY idx_van_status (operational_status),
    CONSTRAINT fk_van_route
        FOREIGN KEY (registered_route_id) REFERENCES routes (route_id),
    -- Hard LTFRB capacity ceiling. Your mock data used 18 in places;
    -- this constraint makes that impossible to reintroduce by accident.
    CONSTRAINT chk_van_capacity CHECK (seat_capacity BETWEEN 1 AND 14)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- van_photos
-- Normalizes the four photo_front/back/left/right columns from the old
-- schema, so adding a fifth angle is a row not a migration.
-- ---------------------------------------------------------------------
CREATE TABLE van_photos (
    photo_id    CHAR(36)     NOT NULL,
    van_id      CHAR(36)     NOT NULL,
    position    ENUM('front','back','left','right','interior') NOT NULL,
    photo_url   VARCHAR(512) NOT NULL,
    uploaded_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (photo_id),
    UNIQUE KEY uq_van_position (van_id, position),
    CONSTRAINT fk_van_photo_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id) ON DELETE CASCADE
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('003_fleet');
