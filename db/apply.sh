#!/usr/bin/env bash
# Apply all migrations in order against the Dockerised MySQL.
#   ./db/apply.sh          -> run pending migrations
#   ./db/apply.sh --seed   -> also load development seed data
#   ./db/apply.sh --reset  -> DROP the database and rebuild from scratch
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a

MYSQL="docker compose exec -T -e MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql mysql -u root --silent"

echo "==> waiting for MySQL to become healthy"
until docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql \
      mysqladmin ping -h 127.0.0.1 -u root --silent >/dev/null 2>&1; do
  sleep 2
done

if [[ "${1:-}" == "--reset" ]]; then
  echo "==> DROPPING database ${MYSQL_DATABASE}"
  $MYSQL -e "DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`;
             CREATE DATABASE \`${MYSQL_DATABASE}\`
               CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
             GRANT ALL ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
             FLUSH PRIVILEGES;"
  shift
fi

applied=$($MYSQL -D "${MYSQL_DATABASE}" \
  -e "SELECT version FROM schema_migrations;" 2>/dev/null || echo "")

for f in db/migrations/*.sql; do
  version=$(basename "$f" .sql)
  if grep -qx "$version" <<< "$applied"; then
    echo "==> skip   $version (already applied)"
    continue
  fi
  echo "==> apply  $version"
  docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql mysql -u root \
    "${MYSQL_DATABASE}" < "$f"
done

if [[ "${1:-}" == "--seed" ]]; then
  for f in db/seed/*.sql; do
    echo "==> seed   $(basename "$f")"
    docker compose exec -T -e MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql mysql -u root \
      "${MYSQL_DATABASE}" < "$f"
  done
fi

echo "==> done"
$MYSQL -D "${MYSQL_DATABASE}" -e \
  "SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES
    WHERE TABLE_SCHEMA='${MYSQL_DATABASE}' ORDER BY TABLE_NAME;"
