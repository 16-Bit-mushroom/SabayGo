-- Reverses 037_drop_payment_leftovers.sql: restores the empty column and
-- tables as 017 and 006 created them.
-- Run with: ./db/rollback.sh 037_drop_payment_leftovers

ALTER TABLE operators
    ADD COLUMN payout_ref VARCHAR(64) NULL AFTER email;

CREATE TABLE ticket_booklets (
    booklet_id         CHAR(36)     NOT NULL,
    booklet_code       VARCHAR(32)  NOT NULL,
    assigned_to_user_id CHAR(36)    NULL,
    serial_start       INT UNSIGNED NOT NULL,
    serial_end         INT UNSIGNED NOT NULL,
    status             ENUM('unassigned','assigned','exhausted','voided')
                       NOT NULL DEFAULT 'unassigned',
    issued_at          DATETIME(6)  NULL,
    created_at         DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (booklet_id),
    UNIQUE KEY uq_booklet_code (booklet_code),
    CONSTRAINT fk_booklet_user
        FOREIGN KEY (assigned_to_user_id) REFERENCES users (user_id),
    CONSTRAINT chk_booklet_range CHECK (serial_end >= serial_start)
) ENGINE=InnoDB;

CREATE TABLE physical_tickets (
    physical_ticket_id CHAR(36)     NOT NULL,
    booklet_id         CHAR(36)     NOT NULL,
    serial_number      INT UNSIGNED NOT NULL,
    qr_payload         VARCHAR(255) NOT NULL,
    status             ENUM('unissued','issued','scanned','void') NOT NULL DEFAULT 'unissued',
    booking_id         CHAR(36)     NULL,
    issued_at          DATETIME(6)  NULL,
    scanned_at         DATETIME(6)  NULL,
    PRIMARY KEY (physical_ticket_id),
    UNIQUE KEY uq_booklet_serial (booklet_id, serial_number),
    UNIQUE KEY uq_physical_qr (qr_payload),
    KEY idx_physical_status (status),
    CONSTRAINT fk_physical_booklet
        FOREIGN KEY (booklet_id) REFERENCES ticket_booklets (booklet_id) ON DELETE CASCADE,
    CONSTRAINT fk_physical_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE SET NULL
) ENGINE=InnoDB;

DELETE FROM schema_migrations WHERE version = '037_drop_payment_leftovers';
