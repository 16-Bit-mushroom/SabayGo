-- Reverses 031: each van's door line and seat mask.
ALTER TABLE vans
    DROP FOREIGN KEY fk_van_door_layout_device,
    DROP COLUMN door_layout_device_id,
    DROP COLUMN door_layout_set_at,
    DROP COLUMN door_layout;

DELETE FROM schema_migrations WHERE version = '031_van_door_layout';
