-- 040_message_edit_delete: a person can edit or delete their own message
-- (12 Nov, the owner's request for CRUD in Messages).
--
--   messages.edited_at   when the text was last changed; shown as "edited"
--   messages.deleted_at  when it was deleted; the text is erased and the
--                        row stays, so the thread shows "Message deleted"
--
-- Only text messages: a home pickup's payment photo is proof and cannot be
-- edited or deleted. Down: db/migrations/down/040_message_edit_delete.sql.

ALTER TABLE messages
    ADD COLUMN edited_at  DATETIME(6) NULL AFTER read_at,
    ADD COLUMN deleted_at DATETIME(6) NULL AFTER edited_at;

INSERT INTO schema_migrations (version) VALUES ('040_message_edit_delete');
