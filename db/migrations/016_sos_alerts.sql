-- SOS emergency alerts (spec section 2.3.5; Scope & Limitations).
--
-- The manuscript has always described SOS as existing infrastructure
-- ("emergency alerts continue to be handled separately through the Twilio
-- API integration"). Nothing implemented it. This migration is that
-- claim, made true.
--
-- Two tables, because an alert and its delivery are different facts:
--
--   sos_alerts            what happened, who raised it, where, and how the
--                         office dispositioned it. This row is the record.
--   sos_alert_dispatches  one row per SMS actually attempted, with the
--                         provider's own message id or the error text.
--
-- They are split for the same reason the YOLOv8 node never fabricates a
-- count: an alert whose SMS silently failed must not look like an alert
-- that was delivered. The alert is committed before any SMS is attempted,
-- so a dead GSM gateway or an expired Twilio balance can lose the text
-- message but can never lose the emergency.
--
-- Recipients are not stored here. They come from the `sos_contact_numbers`
-- cooperative policy, so the office edits them in the existing Policy
-- Editor rather than through a table only a developer can reach.

CREATE TABLE sos_alerts (
    sos_id            CHAR(36)     NOT NULL,
    raised_by_user_id CHAR(36)     NOT NULL,
    -- Denormalized like notifications.audience: the console lists alerts
    -- without joining users, and a crew member who later changes role
    -- does not rewrite the history of an emergency.
    raised_by_role    ENUM('passenger','conductor','driver','coop_admin','admin') NOT NULL,
    -- NULL when the person is not on a trip -- a passenger waiting at the
    -- terminal has an emergency too.
    trip_id           CHAR(36)     NULL,
    category          ENUM('medical','accident','security','breakdown','other')
                                   NOT NULL DEFAULT 'other',
    note              VARCHAR(255) NULL,
    -- Best effort. A denied location permission must not block an SOS,
    -- so these are nullable and the console says "no location" rather
    -- than plotting a zero that reads as the Gulf of Guinea.
    latitude          DECIMAL(8,6) NULL,
    longitude         DECIMAL(9,6) NULL,
    accuracy_m        DECIMAL(7,1) NULL,
    status            ENUM('open','acknowledged','resolved') NOT NULL DEFAULT 'open',
    acknowledged_by_user_id CHAR(36)    NULL,
    acknowledged_at         DATETIME(6) NULL,
    resolved_by_user_id     CHAR(36)    NULL,
    resolved_at             DATETIME(6) NULL,
    resolution_notes        VARCHAR(512) NULL,
    raised_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (sos_id),
    KEY idx_sos_queue (status, raised_at),
    KEY idx_sos_trip (trip_id, raised_at),
    -- The open-alert lookup that keeps a panicked repeat press from
    -- raising a second emergency and a second round of SMS.
    KEY idx_sos_raiser_open (raised_by_user_id, status),
    CONSTRAINT fk_sos_raiser
        FOREIGN KEY (raised_by_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_sos_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id),
    CONSTRAINT fk_sos_ack_by
        FOREIGN KEY (acknowledged_by_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_sos_resolved_by
        FOREIGN KEY (resolved_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB;


CREATE TABLE sos_alert_dispatches (
    dispatch_id  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    sos_id       CHAR(36)     NOT NULL,
    -- 'twilio' or 'android_gateway' today. A plain VARCHAR rather than an
    -- ENUM: which SMS vendor the cooperative signs with is a procurement
    -- decision, not a schema change.
    provider     VARCHAR(32)  NOT NULL,
    recipient    VARCHAR(20)  NOT NULL,
    -- 'skipped' is its own outcome, not a failure: no provider configured,
    -- or no contact numbers set. The office should be able to tell "we
    -- never tried" from "we tried and the network refused".
    status       ENUM('sent','failed','skipped') NOT NULL,
    provider_message_id VARCHAR(128) NULL,
    error        VARCHAR(255) NULL,
    attempted_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (dispatch_id),
    KEY idx_sos_dispatch_alert (sos_id, attempted_at),
    CONSTRAINT fk_sos_dispatch_alert
        FOREIGN KEY (sos_id) REFERENCES sos_alerts (sos_id) ON DELETE CASCADE
) ENGINE=InnoDB;


-- The in-app half of the alert. Office, and the crew of the trip the
-- alert came from, each get a notification row in the same transaction
-- as the alert itself -- the same shape as a YOLOv8 variance.
ALTER TABLE notifications
    MODIFY COLUMN type
        ENUM('trip_update','tailored_schedule','system_alert',
             'terminal_policy','variance_alert','unremitted_fare',
             'departure_reminder','schedule_change','sos_alert')
        NOT NULL;


-- Who gets the SMS. Comma-separated E.164 numbers; the cooperative edits
-- this in the Policy Editor. Empty means no SMS is attempted and every
-- dispatch row says so -- an honest 'skipped', never a silent success.
INSERT INTO cooperative_policies
    (policy_key, policy_value, data_type, description)
VALUES
    ('sos_contact_numbers', '', 'string',
     'Comma-separated E.164 numbers texted when an SOS is raised (e.g. +639171234567)')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO schema_migrations (version) VALUES ('016_sos_alerts');
