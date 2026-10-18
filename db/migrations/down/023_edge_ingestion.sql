-- Reverse of 023_edge_ingestion.sql. Held door events and the heartbeat
-- history are dropped with their tables; every phone loses its token
-- and must be issued a new one after a re-apply.

DROP TABLE held_door_events;
DROP TABLE device_heartbeats;

ALTER TABLE edge_devices
    DROP INDEX uq_device_token,
    DROP COLUMN token_issued_at,
    DROP COLUMN token_hash;

DELETE FROM schema_migrations WHERE version = '023_edge_ingestion';
