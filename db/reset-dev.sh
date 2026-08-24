#!/usr/bin/env bash
# Reset to a clean, bookable dev state. Run before every experiment.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

./db/apply.sh --reset --seed >/dev/null

HASH=$(cd backend && python3 -c \
  "import bcrypt; print(bcrypt.hashpw(b'sabaygo123', bcrypt.gensalt()).decode())")

docker compose exec -T mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}" \
  "${MYSQL_DATABASE}" <<SQL
UPDATE users SET email = REPLACE(email, '@sabaygo.test', '@sabaygo.dev');
UPDATE users SET password_hash = '${HASH}' WHERE email LIKE '%@sabaygo.dev';
UPDATE trips
   SET service_date = CURRENT_DATE + INTERVAL 1 DAY,
       departure_datetime = CONCAT(CURRENT_DATE + INTERVAL 1 DAY, ' 05:30:00');
UPDATE trip_legs l JOIN trips t ON t.trip_id = l.trip_id
   SET l.departs_at = t.departure_datetime
       + INTERVAL (l.leg_sequence - 1) * 90 MINUTE;
SELECT
  (SELECT COUNT(*) FROM seat_inventory WHERE status='available') AS free_seat_legs,
  (SELECT COUNT(*) FROM bookings) AS bookings,
  (SELECT departure_datetime FROM trips LIMIT 1) AS departs;
SQL
