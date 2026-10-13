-- =====================================================================
-- Reverses 018_revenue_audit_tables.sql.
-- Run with: ./db/rollback.sh 018_revenue_audit_tables
--
-- Every row in the new tables is deleted with them, and so are the
-- snapped positions on trip_location_pings and each operator's import
-- batch. Children first, so no foreign key blocks a drop.
-- =====================================================================

DROP TABLE disputes;
DROP TABLE remittance_lines;
DROP TABLE remittances;
DROP TABLE special_trip_requests;
DROP TABLE driving_events;
DROP TABLE passenger_events;
DROP TABLE device_checkouts;
DROP TABLE edge_devices;

ALTER TABLE trip_location_pings
    DROP COLUMN stretch_no,
    DROP COLUMN distance_from_start_m;

DROP TABLE route_stretches;

ALTER TABLE operators
    DROP FOREIGN KEY fk_operator_import_batch,
    DROP COLUMN import_batch_id;

DROP TABLE data_transfers;

DELETE FROM schema_migrations WHERE version = '018_revenue_audit_tables';
