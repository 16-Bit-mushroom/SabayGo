-- Reverses 030: restores the rev 468 camera-variance setting at its
-- shipped value (001). Its earlier history is not restored.
INSERT INTO cooperative_policies (policy_key, policy_value, data_type, description)
VALUES
    ('variance_alert_threshold', '1', 'int',
     'YOLOv8 headcount variance that triggers an operator alert');

DELETE FROM schema_migrations WHERE version = '030_retire_variance_threshold';
