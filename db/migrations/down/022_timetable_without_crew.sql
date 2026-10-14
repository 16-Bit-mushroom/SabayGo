-- Reverse of 022_timetable_without_crew.sql: restores the timetable's
-- default van and Dispatcher columns, empty. The values 022 dropped do
-- not come back.

ALTER TABLE schedule_templates
    ADD COLUMN default_van_id       CHAR(36) NULL AFTER days_of_week,
    ADD COLUMN default_conductor_id CHAR(36) NULL AFTER default_van_id,
    ADD CONSTRAINT fk_template_van
        FOREIGN KEY (default_van_id) REFERENCES vans (van_id),
    ADD CONSTRAINT fk_template_conductor
        FOREIGN KEY (default_conductor_id) REFERENCES users (user_id);

DELETE FROM schema_migrations WHERE version = '022_timetable_without_crew';
