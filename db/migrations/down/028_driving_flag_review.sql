-- Reverses 028: who reviewed a driving flag.
ALTER TABLE driving_events
    DROP FOREIGN KEY fk_driving_reviewed_by,
    DROP COLUMN review_note,
    DROP COLUMN reviewed_at,
    DROP COLUMN reviewed_by;

DELETE FROM schema_migrations WHERE version = '028_driving_flag_review';
