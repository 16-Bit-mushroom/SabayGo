-- =====================================================================
-- 031: each van's door line and driver's seat mask (rev 603 brief 5.5)
-- =====================================================================
-- The phone counts a boarding when a tracked person crosses a line
-- across the doorway, and leaves the driver's seat out with a mask
-- (brief 5.2). Phones rotate between vans, so the line and the mask
-- belong to the van, not the phone: "store the door line and the seat
-- mask per van and load them when the check-out names the van" (5.5).
-- The Dispatcher draws them on the phone at mounting; the phone sends
-- them here and any phone checked out to the van loads them from
-- GET /edge/session.
--
-- door_layout is JSON, coordinates as fractions of the camera frame:
--   {"door_line": [[x1,y1],[x2,y2]], "inside": 1 | -1,
--    "seat_mask": [[x1,y1],[x2,y2]] | null}
-- `inside` is the side of the line (p1 -> p2) the cabin is on. Which
-- phone set it and when are kept; a new layout replaces the old one.
-- Not a registration detail: setting it does not return a validated van
-- to Pending.
--
-- Reverse: db/migrations/down/031_van_door_layout.sql
-- =====================================================================

ALTER TABLE vans
    ADD COLUMN door_layout            JSON         NULL,
    ADD COLUMN door_layout_set_at     DATETIME(6)  NULL AFTER door_layout,
    ADD COLUMN door_layout_device_id  CHAR(36)     NULL AFTER door_layout_set_at,
    ADD CONSTRAINT fk_van_door_layout_device
        FOREIGN KEY (door_layout_device_id) REFERENCES edge_devices (device_id);

INSERT INTO schema_migrations (version) VALUES ('031_van_door_layout');
