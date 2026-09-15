-- =====================================================================
-- 013_revenue_view_no_fanout.sql
--
-- Hardening (15 Sep): v_trip_revenue_reconciliation joined bookings,
-- payments and audit logs flat and then summed. With one audit row per
-- trip -- all the fixture ever had -- that is invisible. With two audits
-- on a trip every booking count and every peso doubles, and
-- pending_audits becomes (pending x bookings). A booking with two
-- payment rows (a failed attempt then a paid one) does the same to the
-- booking columns.
--
-- Each side is now aggregated on its own key before the join, so the
-- trip row is one row of bookings + one row of audits, whatever either
-- side contains. Column list and order are unchanged; the API reads it
-- with SELECT *.
--
-- Also: a 'pending' booking -- a space held while the passenger is still
-- on the PayMongo page -- is no longer counted. It owes nothing yet; if
-- the hold lapses it never will. Counting it made every abandoned
-- checkout look like uncollected fare.
-- =====================================================================

CREATE OR REPLACE VIEW v_trip_revenue_reconciliation AS
SELECT
    t.trip_id,
    t.service_date,
    t.departure_datetime,
    r.route_name,
    v.plate_number,
    t.seat_capacity,
    COALESCE(bk.total_bookings, 0)        AS total_bookings,
    COALESCE(bk.app_bookings, 0)          AS app_bookings,
    COALESCE(bk.walkin_bookings, 0)       AS walkin_bookings,
    COALESCE(bk.roadside_bookings, 0)     AS roadside_bookings,
    COALESCE(bk.manual_fare_bookings, 0)  AS manual_fare_bookings,
    COALESCE(bk.collected_fare, 0)        AS collected_fare,
    -- Cash the crew has taken but not yet handed over. Money in a
    -- pocket, not money missing -- kept apart from unreconciled.
    COALESCE(bk.cash_in_hand, 0)          AS cash_in_hand,
    COALESCE(bk.expected_fare, 0)         AS expected_fare,
    COALESCE(bk.expected_fare, 0)
      - COALESCE(bk.collected_fare, 0)
      - COALESCE(bk.cash_in_hand, 0)      AS unreconciled_amount,
    COALESCE(au.max_variance, 0)          AS max_yolo_variance,
    COALESCE(au.pending_audits, 0)        AS pending_audits
FROM trips t
JOIN routes r       ON r.route_id = t.route_id
LEFT JOIN vans v    ON v.van_id   = t.van_id
LEFT JOIN (
    SELECT
        b.trip_id,
        COUNT(*)                                            AS total_bookings,
        SUM(b.booking_type = 'app')                         AS app_bookings,
        SUM(b.booking_type IN ('walk_in', 'driver_issued')) AS walkin_bookings,
        SUM(b.is_roadside_pickup)                           AS roadside_bookings,
        SUM(b.fare_is_manual)                               AS manual_fare_bookings,
        SUM(b.fare_amount)                                  AS expected_fare,
        SUM(COALESCE(p.paid_amount, 0))                     AS collected_fare,
        SUM(COALESCE(p.cash_pending, 0))                    AS cash_in_hand
    FROM bookings b
    LEFT JOIN (
        SELECT
            booking_id,
            SUM(CASE WHEN status = 'paid' THEN amount ELSE 0 END)     AS paid_amount,
            SUM(CASE WHEN provider = 'cash' AND status = 'pending'
                     THEN amount ELSE 0 END)                          AS cash_pending
        FROM payments
        GROUP BY booking_id
    ) p ON p.booking_id = b.booking_id
    WHERE b.status NOT IN ('pending', 'cancelled', 'rescheduled')
    GROUP BY b.trip_id
) bk ON bk.trip_id = t.trip_id
LEFT JOIN (
    SELECT
        trip_id,
        MAX(variance)                       AS max_variance,
        SUM(resolution_status = 'pending')  AS pending_audits
    FROM yolov8_audit_logs
    GROUP BY trip_id
) au ON au.trip_id = t.trip_id;

INSERT INTO schema_migrations (version) VALUES ('013_revenue_view_no_fanout');
