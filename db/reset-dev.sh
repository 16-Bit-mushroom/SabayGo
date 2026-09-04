#!/usr/bin/env bash
# Reset to a clean, bookable dev state. Run before every experiment.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

# --soon puts departure 20 min out so the check-in window is open.
if [ "${1:-}" = "--soon" ]; then
  DATE_SQL="CURRENT_DATE"
  DEPART_SQL="NOW() + INTERVAL 20 MINUTE"
else
  DATE_SQL="CURRENT_DATE + INTERVAL 1 DAY"
  DEPART_SQL="CONCAT(CURRENT_DATE + INTERVAL 1 DAY, ' 05:30:00')"
fi

./db/apply.sh --reset --seed >/dev/null

HASH=$(cd backend && venv/bin/python -c \
  "import bcrypt; print(bcrypt.hashpw(b'sabaygo123', bcrypt.gensalt()).decode())")

docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql mysql -u root \
  "${MYSQL_DATABASE}" <<SQL
UPDATE users SET email = REPLACE(email, '@sabaygo.test', '@sabaygo.dev');
UPDATE users SET password_hash = '${HASH}' WHERE email LIKE '%@sabaygo.dev';
UPDATE trips
   SET service_date = ${DATE_SQL},
       departure_datetime = ${DEPART_SQL},
       status = 'scheduled',
       departed_at = NULL,
       completed_at = NULL;
-- The seeded trip departs 20 min out with --soon, so a 2-hour
-- cancellation deadline would refuse everything. The fixture starts
-- permissive; test_group_f.sh sets its own value to exercise the rule.
UPDATE cooperative_policies SET policy_value = '0'
 WHERE policy_key IN ('cancel_cutoff_hours', 'reschedule_cutoff_hours');
UPDATE trip_legs l JOIN trips t ON t.trip_id = l.trip_id
   SET l.departs_at = t.departure_datetime
       + INTERVAL (l.leg_sequence - 1) * 90 MINUTE;
SELECT
  (SELECT COUNT(*) FROM seat_inventory WHERE status='available') AS free_seat_legs,
  (SELECT COUNT(*) FROM bookings) AS bookings,
  (SELECT COUNT(*) FROM users WHERE email LIKE '%@sabaygo.dev') AS dev_users,
  (SELECT departure_datetime FROM trips LIMIT 1) AS departs;
SQL
