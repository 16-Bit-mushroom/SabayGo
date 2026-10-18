-- =====================================================================
-- 022_timetable_without_crew.sql
--
-- CONTRACTION of paper revision 468, brief step 4. The timetable stores
-- route, time and operating days only; it has no "usual" van and no
-- usual Dispatcher (brief 4.2 rule 1). A trip is created days ahead with
-- van_id and dispatcher_id NULL, and both are assigned at the van's turn
-- (rule 2), which is the only path that writes them since this step.
--
--   schedule_templates.default_van_id
--   schedule_templates.default_conductor_id
--
-- Trips generated before this migration keep the van and Dispatcher the
-- generator copied from these columns: they are assignments made by the
-- old rule, and the lifecycle treats them like any other (the Terminal
-- Manager or the Cashier can change them before the start).
--
-- Reverse: db/migrations/down/022_timetable_without_crew.sql
-- (restores the columns, empty; the dropped defaults do not come back).
-- =====================================================================

ALTER TABLE schedule_templates
    DROP FOREIGN KEY fk_template_van,
    DROP FOREIGN KEY fk_template_conductor;

ALTER TABLE schedule_templates
    DROP COLUMN default_van_id,
    DROP COLUMN default_conductor_id;

INSERT INTO schema_migrations (version)
VALUES ('022_timetable_without_crew');
