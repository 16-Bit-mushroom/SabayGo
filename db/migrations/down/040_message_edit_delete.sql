-- Down for 040_message_edit_delete. Edited text stays as last edited;
-- deleted messages keep their erased (empty) text.
ALTER TABLE messages
    DROP COLUMN deleted_at,
    DROP COLUMN edited_at;

DELETE FROM schema_migrations WHERE version = '040_message_edit_delete';
