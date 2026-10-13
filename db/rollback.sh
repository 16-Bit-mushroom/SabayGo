#!/usr/bin/env bash
# Reverse one applied migration: ./db/rollback.sh 017_dispatcher_terminal_staff_operators
#
# Runs db/migrations/down/<version>.sql, which also removes the version
# from schema_migrations so ./db/apply.sh would re-apply it. Only
# migrations from 017 on have a down script; 001-016 are forward-only.
# Roll back newest first.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

version="${1:?usage: db/rollback.sh <migration version, e.g. 017_dispatcher_terminal_staff_operators>}"
down="db/migrations/down/${version}.sql"
[[ -f "$down" ]] || { echo "no down script: $down" >&2; exit 1; }

MYSQL="docker compose exec -T -e MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql mysql -u root --silent"
applied=$($MYSQL -D "${MYSQL_DATABASE}" -e \
  "SELECT COUNT(*) FROM schema_migrations WHERE version = '${version}';")
[[ "$applied" == "1" ]] || { echo "${version} is not applied" >&2; exit 1; }

echo "==> rollback ${version}"
$MYSQL "${MYSQL_DATABASE}" < "$down"
echo "==> done"
