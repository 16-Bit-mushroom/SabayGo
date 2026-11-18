#!/usr/bin/env bash
# 17 Nov: delete a terminal added by mistake (Setup, Terminals).
#
#   DELETE /config/terminals/{id} (api/v1/config.py, delete_terminal):
#   the Terminal Manager only. Refused in plain words while a route stops
#   there (active or not), a staff member is assigned to it, or a
#   passenger's "I'm here to pay" or a statement line names it: a terminal
#   that has been used is closed instead. A passenger's saved destination
#   there is cleared, not deleted.
#
#   ./db/reset-dev.sh && ./tests/integration/test_terminal_delete.sh
#   On a scratch database, against a backend started on it:
#   SABAYGO_DB=sabaygo_t SABAYGO_API=http://127.0.0.1:8001/api/v1 ./tests/integration/test_terminal_delete.sh
set -uo pipefail

API="${SABAYGO_API:-http://127.0.0.1:8000/api/v1}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
set -a; source "$ROOT/.env"; set +a
DB="${SABAYGO_DB:-$MYSQL_DATABASE}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1', wanted '$2')"; }
# code METHOD PATH [BODY] [TOKEN] -> HTTP status; the body is in $TMP/r.json
code() {
  local a=(-s -o "$TMP/r.json" -w "%{http_code}" -X "$1" "$API$2")
  [ -n "${3:-}" ] && a+=(-H "Content-Type: application/json" -d "$3")
  [ -n "${4:-}" ] && a+=(-H "Authorization: Bearer $4")
  curl "${a[@]}"
}
py()  { python3 -c "import json; d=json.load(open('$TMP/r.json')); $1"; }
has() { py "import sys; sys.exit(0 if '$1' in d.get('detail', '') else 1)" && ok "$2" || bad "$2 (said: $(py "print(d.get('detail'))"))"; }
sql() { docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" sabaygo-mysql mysql -u root -D "$DB" -N -B -e "$1"; }
login() { code POST /auth/login "{\"email\":\"$1\",\"password\":\"sabaygo123\"}" >/dev/null
          py "print(d['access_token'])"; }

MT=$(login manager@sabaygo.dev); CT=$(login cashier@sabaygo.dev)
[ -n "$MT" ] && [ -n "$CT" ] && ok "manager@ and cashier@ signed in" || { bad "login failed"; exit 1; }

is "$(code POST /config/terminals '{"terminal_name":"Mistake Terminal","city":"Davao City","latitude":7.1,"longitude":125.6}' "$MT")" 201 \
   "a terminal added by mistake"
NEW=$(py "print(d['terminal_id'])")

hdr "Who may delete"
is "$(code DELETE "/config/terminals/$NEW")" 401 "signed out: 401"
is "$(code DELETE "/config/terminals/$NEW" "" "$CT")" 403 "the Cashier: 403 (Terminal Manager only)"
is "$(code DELETE /config/terminals/no-such-terminal "" "$MT")" 404 "an unknown terminal: 404"

hdr "A terminal that has been used is closed instead"
read -r ON ONCODE < <(sql "SELECT s.terminal_id, r.route_code FROM route_stops s
                           JOIN routes r ON r.route_id = s.route_id ORDER BY r.route_code LIMIT 1")
is "$(code DELETE "/config/terminals/$ON" "" "$MT")" 409 "a stop on a route: 409"
has "$ONCODE" "the refusal names the route ($ONCODE)"
has "close the terminal instead" "and says to close it instead"
is "$(sql "SELECT COUNT(*) FROM terminals WHERE terminal_id = '$ON'")" 1 "the terminal is still there"

read -r STAFF FIRST WAS < <(sql "SELECT user_id, first_name, IFNULL(assigned_terminal_id, 'NULL')
                                 FROM staff_profiles ORDER BY user_id LIMIT 1")
sql "UPDATE staff_profiles SET assigned_terminal_id = '$NEW' WHERE user_id = '$STAFF'"
is "$(code DELETE "/config/terminals/$NEW" "" "$MT")" 409 "a staff member assigned to it: 409"
has "$FIRST" "the refusal names them ($FIRST)"
if [ "$WAS" = NULL ]; then
  sql "UPDATE staff_profiles SET assigned_terminal_id = NULL WHERE user_id = '$STAFF'"
else
  sql "UPDATE staff_profiles SET assigned_terminal_id = '$WAS' WHERE user_id = '$STAFF'"
fi

CI=$(python3 -c "import uuid; print(uuid.uuid4())")
sql "INSERT INTO check_ins (check_in_id, booking_id, terminal_id, latitude, longitude, distance_m,
       geofence_radius_m, is_within_geofence, is_within_window, checked_in_at)
     SELECT '$CI', booking_id, '$NEW', 7.1, 125.6, 0, 150, 1, 1, NOW(6) FROM bookings LIMIT 1"
is "$(code DELETE "/config/terminals/$NEW" "" "$MT")" 409 "a passenger's \"I'm here to pay\" names it: 409"
has "records" "the refusal says records name it"
sql "DELETE FROM check_ins WHERE check_in_id = '$CI'"

hdr "A terminal nothing uses is deleted"
SD=$(python3 -c "import uuid; print(uuid.uuid4())")
sql "INSERT INTO saved_destinations (destination_id, user_id, label, terminal_id, created_at)
     SELECT '$SD', user_id, 'Test', '$NEW', NOW(6) FROM users WHERE email = 'passenger@sabaygo.dev'"
is "$(code DELETE "/config/terminals/$NEW" "" "$MT")" 200 "deleted: 200"
is "$(sql "SELECT COUNT(*) FROM terminals WHERE terminal_id = '$NEW'")" 0 "gone from the database"
code GET /config/terminals "" "$MT" >/dev/null
is "$(py "print(any(t['terminal_id'] == '$NEW' for t in d))")" False "gone from Setup's list"
is "$(sql "SELECT IFNULL(terminal_id, 'NULL') FROM saved_destinations WHERE destination_id = '$SD'")" NULL \
   "a passenger's saved destination there is cleared, not deleted"
sql "DELETE FROM saved_destinations WHERE destination_id = '$SD'"
is "$(code DELETE "/config/terminals/$NEW" "" "$MT")" 404 "deleting it again: 404"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
