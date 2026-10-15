-- =====================================================================
-- 028: who reviewed a driving flag, when, and why (rev 603 brief 6.4)
-- =====================================================================
-- Table 30 keeps ReviewStatus ('Open', 'Reviewed', 'Dismissed'). Every
-- other decision a person takes on the record names them (StartedBy,
-- AssignedBy, ChangedBy, StartReviewedBy, a dispute's DecidedBy), and
-- brief 3 asks for one login per staff member so that it can. A flag
-- marked Reviewed or Dismissed does the same: by whom, at what time, and
-- the note (required to dismiss). A dispute's decision fills them too.
--
-- Reverse: db/migrations/down/028_driving_flag_review.sql
-- =====================================================================

ALTER TABLE driving_events
    ADD COLUMN reviewed_by  CHAR(36)     NULL AFTER review_status,
    ADD COLUMN reviewed_at  DATETIME(6)  NULL AFTER reviewed_by,
    ADD COLUMN review_note  VARCHAR(255) NULL AFTER reviewed_at,
    ADD CONSTRAINT fk_driving_reviewed_by
        FOREIGN KEY (reviewed_by) REFERENCES users (user_id);

INSERT INTO schema_migrations (version) VALUES ('028_driving_flag_review');
