-- Reverses 036: restores match_window_seconds at its shipped value (024).
-- Its earlier history is not recovered, and nothing reads it.

INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('match_window_seconds', '120', 'int',
     'A boarding is listed if a QR scan or cash entry was made this many seconds before or after it');

DELETE FROM schema_migrations WHERE version = '036_drop_match_window';
