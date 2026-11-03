#!/usr/bin/env bash
# Load the Day 1 test data instead of the demo seed.
#   ./db/load-day1.sh
#
# The data is what A2Z's setup looked like at the end of the Day 1 test
# (3 Nov 2026, docs/DAY1_TEST_GUIDE.md): the system started empty and
# everything was entered through the console and the apps -- terminals,
# the Ecoland - Cotabato route and fares, two operators and their vans,
# the staff, the timetable, the settings, and one trip run end to end.
#
# It drops the database, rebuilds it from the migrations (no demo seed)
# and loads db/day1/day1_a2z.sql, a data-only dump whose rows REPLACE the
# ones the migrations insert (the default settings). Its trips are dated
# 3-5 Nov 2026: sign in as manager@a2z.dev and press Create upcoming
# trips on the Timetable for trips from today. Passwords are sabaygo123.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

./db/apply.sh --reset >/dev/null
echo "==> load   db/day1/day1_a2z.sql"
docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql mysql -u root \
  --default-character-set=utf8mb4 "${MYSQL_DATABASE}" < db/day1/day1_a2z.sql

docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql mysql -u root \
  --default-character-set=utf8mb4 "${MYSQL_DATABASE}" -e \
  "SELECT u.email, u.role FROM users u ORDER BY u.role, u.email;"
echo "==> done: sign in to the console as manager@a2z.dev (sabaygo123)"
