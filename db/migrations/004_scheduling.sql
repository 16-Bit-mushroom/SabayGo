-- =====================================================================
-- 004_scheduling.sql
--
-- THIS IS THE MOST IMPORTANT MIGRATION IN THE PROJECT.
-- seat_inventory is the table your entire pessimistic-locking thesis
-- claim runs against. Everything else is supporting cast.
-- =====================================================================

-- ---------------------------------------------------------------------
-- schedule_templates
--
-- Consultation item: "Creating trips should be automatic everyday -
-- set regular schedule."
--
-- The key insight is that a TEMPLATE (recurring pattern) and a TRIP
-- (one dated instance) are different things. Your old schema had only
-- TripSchedules, so every departure had to be hand-created forever.
-- A nightly job reads this table and materializes tomorrow's trips.
-- ---------------------------------------------------------------------
CREATE TABLE schedule_templates (
    template_id          CHAR(36) NOT NULL,
    route_id             CHAR(36) NOT NULL,
    departure_time       TIME     NOT NULL,
    -- 7-char bitmask, Monday first: '1111100' = weekdays only.
    days_of_week         CHAR(7)  NOT NULL DEFAULT '1111111',
    default_van_id       CHAR(36) NULL,
    default_driver_id    CHAR(36) NULL,
    default_conductor_id CHAR(36) NULL,
    trip_label           VARCHAR(64) NULL,   -- 'First Trip', 'Morning Express'
    is_active            BOOLEAN  NOT NULL DEFAULT TRUE,
    valid_from           DATE     NOT NULL,
    valid_until          DATE     NULL,
    created_at           DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (template_id),
    UNIQUE KEY uq_template_slot (route_id, departure_time, valid_from),
    KEY idx_template_active (is_active, valid_from, valid_until),
    CONSTRAINT fk_template_route
        FOREIGN KEY (route_id) REFERENCES routes (route_id),
    CONSTRAINT fk_template_van
        FOREIGN KEY (default_van_id) REFERENCES vans (van_id),
    CONSTRAINT fk_template_driver
        FOREIGN KEY (default_driver_id) REFERENCES users (user_id),
    CONSTRAINT fk_template_conductor
        FOREIGN KEY (default_conductor_id) REFERENCES users (user_id),
    CONSTRAINT chk_days_of_week CHECK (days_of_week REGEXP '^[01]{7}$')
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- trips -- one dated, dispatchable departure
--
-- Note the snapshotted columns (seat_capacity, advance_booking_seat_cap,
-- reschedule_cutoff_hours). These are copied from vans/policies at
-- generation time ON PURPOSE: if the operator later changes a policy,
-- already-sold trips keep the terms they were sold under. A panelist
-- asking "what happens to existing bookings when policy changes?" is a
-- question you now have a good answer to.
-- ---------------------------------------------------------------------
CREATE TABLE trips (
    trip_id                  CHAR(36)          NOT NULL,
    template_id              CHAR(36)          NULL,  -- NULL => special trip
    route_id                 CHAR(36)          NOT NULL,
    service_date             DATE              NOT NULL,
    departure_datetime       DATETIME          NOT NULL,
    van_id                   CHAR(36)          NULL,
    driver_id                CHAR(36)          NULL,
    conductor_id             CHAR(36)          NULL,  -- NULL => driver-only trip
    trip_label               VARCHAR(64)       NULL,

    -- Consultation: "Manage if its Special trip"
    is_special_trip          BOOLEAN           NOT NULL DEFAULT FALSE,

    -- Policy snapshot at generation time.
    seat_capacity            TINYINT UNSIGNED  NOT NULL DEFAULT 14,
    advance_booking_seat_cap TINYINT UNSIGNED  NOT NULL DEFAULT 10,
    reschedule_cutoff_hours  SMALLINT UNSIGNED NOT NULL DEFAULT 6,

    status                   ENUM('scheduled','boarding','departed','completed','cancelled')
                             NOT NULL DEFAULT 'scheduled',
    cancellation_reason      VARCHAR(255)      NULL,
    departed_at              DATETIME(6)       NULL,
    completed_at             DATETIME(6)       NULL,
    created_at               DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at               DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                               ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (trip_id),
    -- Idempotency guard: the nightly generator can run twice without
    -- producing duplicate departures.
    UNIQUE KEY uq_trip_instance (template_id, service_date),
    KEY idx_trip_search (route_id, service_date, status),
    KEY idx_trip_departure (departure_datetime),
    KEY idx_trip_van (van_id, service_date),
    KEY idx_trip_driver (driver_id, service_date),
    CONSTRAINT fk_trip_template
        FOREIGN KEY (template_id) REFERENCES schedule_templates (template_id) ON DELETE SET NULL,
    CONSTRAINT fk_trip_route
        FOREIGN KEY (route_id) REFERENCES routes (route_id),
    CONSTRAINT fk_trip_van
        FOREIGN KEY (van_id) REFERENCES vans (van_id),
    CONSTRAINT fk_trip_driver
        FOREIGN KEY (driver_id) REFERENCES users (user_id),
    CONSTRAINT fk_trip_conductor
        FOREIGN KEY (conductor_id) REFERENCES users (user_id),
    CONSTRAINT chk_trip_capacity CHECK (seat_capacity BETWEEN 1 AND 14),
    CONSTRAINT chk_trip_advance_cap CHECK (advance_booking_seat_cap <= seat_capacity)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- trip_legs -- the gaps BETWEEN consecutive stops
--
-- A route with N stops has N-1 legs. Booking from stop 2 to stop 4
-- consumes legs 2 and 3. This is the unit of seat occupancy.
-- ---------------------------------------------------------------------
CREATE TABLE trip_legs (
    trip_leg_id        BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    trip_id            CHAR(36)          NOT NULL,
    leg_sequence       SMALLINT UNSIGNED NOT NULL,  -- leg k spans stop k -> k+1
    from_stop_sequence SMALLINT UNSIGNED NOT NULL,
    to_stop_sequence   SMALLINT UNSIGNED NOT NULL,
    departs_at         DATETIME          NULL,
    PRIMARY KEY (trip_leg_id),
    UNIQUE KEY uq_trip_leg (trip_id, leg_sequence),
    CONSTRAINT fk_trip_leg_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT chk_leg_direction CHECK (to_stop_sequence = from_stop_sequence + 1)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- seat_inventory  <-- THE LOCKING TABLE
--
-- One row per (trip, seat, leg). A 5-stop route with 14 seats generates
-- 14 x 4 = 56 rows per trip. Cheap, and it makes the booking algorithm
-- trivially expressible:
--
--   START TRANSACTION;
--   SELECT seat_number
--     FROM seat_inventory
--    WHERE trip_id = ?
--      AND leg_sequence BETWEEN ? AND ?      -- boarding .. alighting-1
--      AND status = 'available'
--    GROUP BY seat_number
--   HAVING COUNT(*) = ?                       -- available on EVERY leg
--    ORDER BY seat_number                     -- lowest-indexed seat
--    LIMIT 1
--    FOR UPDATE;                              <-- pessimistic lock
--
--   UPDATE seat_inventory SET status='held', booking_id=?, hold_expires_at=?
--    WHERE trip_id=? AND seat_number=? AND leg_sequence BETWEEN ? AND ?;
--   COMMIT;
--
-- Concurrent requests block on FOR UPDATE rather than reading stale
-- availability, which is precisely the overbooking prevention your
-- Week 2 experiment needs to measure. The UNIQUE key is the backstop:
-- even if the application logic were wrong, the database physically
-- cannot seat two bookings on the same seat-leg.
-- ---------------------------------------------------------------------
CREATE TABLE seat_inventory (
    seat_inventory_id BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    trip_id           CHAR(36)          NOT NULL,
    seat_number       TINYINT UNSIGNED  NOT NULL,
    leg_sequence      SMALLINT UNSIGNED NOT NULL,
    status            ENUM('available','held','booked','blocked') NOT NULL DEFAULT 'available',
    booking_id        CHAR(36)          NULL,
    -- Seats held awaiting PayMongo confirmation; a sweeper releases
    -- expired holds so abandoned checkouts don't strand inventory.
    hold_expires_at   DATETIME(6)       NULL,
    updated_at        DATETIME(6)       NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (seat_inventory_id),
    UNIQUE KEY uq_seat_leg (trip_id, seat_number, leg_sequence),
    -- Composite index ordered for the allocation query above.
    KEY idx_seat_allocation (trip_id, leg_sequence, status, seat_number),
    KEY idx_seat_booking (booking_id),
    KEY idx_seat_hold_sweep (status, hold_expires_at),
    CONSTRAINT fk_seat_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT chk_seat_number CHECK (seat_number BETWEEN 1 AND 14)
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('004_scheduling');
