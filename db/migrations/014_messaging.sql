-- Two-way in-app messaging (spec section 2.2.3.1; ERD Conversations/Messages).
--
-- A conversation always has exactly two sides. Which roles may pair is
-- fixed by the cooperative's own scoping rule (§2.3.5: "preventing
-- passengers from messaging drivers directly"):
--   passenger  <-> conductor   (trip_id required: the passenger's booked trip)
--   conductor  <-> driver      (trip_id required: the trip they're crewed on)
--   anyone     <-> coop_admin  ("office" kind: trip_id NULL, a shared inbox)
--
-- The office kind is a shared inbox, not a 1:1 thread with one employee:
-- participant_two_id is left NULL and any active coop_admin may read and
-- reply, matching the real cooperative office where more than one staff
-- member picks up the desk. participant_one_id is always the non-admin
-- party in that case. messages.sender_role is denormalized so "unread by
-- the other side" can be computed without joining users for every row --
-- the same shape as notifications.audience.

CREATE TABLE conversations (
    conversation_id    CHAR(36)     NOT NULL,
    kind                ENUM('passenger_conductor','conductor_driver','office') NOT NULL,
    trip_id             CHAR(36)    NULL,
    participant_one_id  CHAR(36)    NOT NULL,
    participant_two_id  CHAR(36)    NULL,
    last_message_at     DATETIME(6) NULL,
    created_at          DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (conversation_id),
    KEY idx_conv_participant_one (participant_one_id, last_message_at),
    KEY idx_conv_participant_two (participant_two_id, last_message_at),
    KEY idx_conv_trip (trip_id),
    CONSTRAINT fk_conv_trip
        FOREIGN KEY (trip_id) REFERENCES trips (trip_id) ON DELETE SET NULL,
    CONSTRAINT fk_conv_p1
        FOREIGN KEY (participant_one_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_conv_p2
        FOREIGN KEY (participant_two_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE messages (
    message_id      CHAR(36)     NOT NULL,
    conversation_id CHAR(36)     NOT NULL,
    sender_id       CHAR(36)     NOT NULL,
    sender_role     VARCHAR(16)  NOT NULL,
    body            VARCHAR(1000) NOT NULL,
    read_at         DATETIME(6)  NULL,
    created_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (message_id),
    KEY idx_msg_conversation (conversation_id, created_at),
    CONSTRAINT fk_msg_conversation
        FOREIGN KEY (conversation_id) REFERENCES conversations (conversation_id) ON DELETE CASCADE,
    CONSTRAINT fk_msg_sender
        FOREIGN KEY (sender_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

INSERT INTO schema_migrations (version) VALUES ('014_messaging');
