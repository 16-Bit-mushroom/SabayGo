-- =====================================================================
-- 007_roadside_and_manual_fare.sql
--
-- Roadside pickup is normal UV Express practice: passengers flag the van
-- down between terminals. The original schema could not express it --
-- every booking had to name a terminal in the route's stop sequence.
--
-- A roadside passenger is recorded from the section they board on, which
-- means anchoring to the PREVIOUS terminal the van passed. Anchoring
-- forward to the next terminal would leave that stretch of road showing
-- as empty while someone physically sits in it, and the YOLOv8 check
-- would then flag a real, paying passenger as revenue leakage.
--
-- Their fare cannot come from the LTFRB pairwise table: they have not
-- travelled a table distance. Neither the previous terminal's price nor
-- the next terminal's price is correct, so the conductor judges it and
-- the system records both the amount and the reason.
-- =====================================================================

ALTER TABLE bookings
    ADD COLUMN is_roadside_pickup BOOLEAN NOT NULL DEFAULT FALSE
        AFTER booking_type,
    -- Free text: "Crossing bridge", "Km 42 waiting shed". Optional --
    -- a conductor loading passengers should not be forced to type.
    ADD COLUMN pickup_landmark VARCHAR(255) NULL
        AFTER is_roadside_pickup,
    -- TRUE when the fare did not come from fare_matrix. Lets the office
    -- see at a glance how often, and by how much, conductors are pricing
    -- by hand.
    ADD COLUMN fare_is_manual BOOLEAN NOT NULL DEFAULT FALSE
        AFTER fare_amount,
    ADD COLUMN fare_note VARCHAR(255) NULL
        AFTER fare_is_manual;

CREATE INDEX idx_booking_roadside
    ON bookings (trip_id, is_roadside_pickup);

-- ---------------------------------------------------------------------
-- All spaces open to both app bookings and walk-ins.
--
-- The earlier design held some spaces back for terminal passengers. The
-- team decided against rationing: whoever claims a space first gets it,
-- app or terminal. Managing passengers who miss out is a terminal matter
-- (signage, announcements, the next departure), not a software one.
--
-- The mechanism is kept rather than deleted -- a future cooperative may
-- want a split, and setting this below 14 restores it with no code change.
-- ---------------------------------------------------------------------
UPDATE cooperative_policies
   SET policy_value = '14',
       description  = 'Spaces sellable in advance. Equal to capacity = all '
                      'open, first come first served.'
 WHERE policy_key = 'advance_booking_seat_cap';

UPDATE trips
   SET advance_booking_seat_cap = seat_capacity
 WHERE status = 'scheduled';

INSERT INTO schema_migrations (version) VALUES ('007_roadside_and_manual_fare');
