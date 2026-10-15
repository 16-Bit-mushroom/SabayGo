#!/usr/bin/env bash
# Rev 603 R2: boarding only at the starting terminal, before departure
# (change brief 2.4). Roadside refusal, table fares only, no seat numbers.
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_roadside.sh
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"     # VAN-0001, dispatcher@, departs in 20 min
STAMP=$(date +%s)
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr(){ printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is() { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }
code(){ local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/r.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"; }
login() { curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" | j "['access_token']"; }
total() { code GET "/trips/$TRIP/manifest" "" "$DT" >/dev/null; j "['total_bookings']" < /tmp/r.json; }

DT=$(login dispatcher); CT=$(login cashier); AT=$(login ana)
PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"rs${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
       \"password\":\"sabaygo123\",\"first_name\":\"Road\",\"last_name\":\"Side\"}" \
  | j "['access_token']")
[ -n "$DT" ] && [ -n "$CT" ] && [ -n "$PT" ] && [ -n "$AT" ] && ok "signed in" || { bad "login"; exit 1; }

code GET "/trips/$TRIP/stops" >/dev/null
read -r FIRST SECOND LAST < <(python3 -c "
import json;s=json.load(open('/tmp/r.json'));print(s[0]['terminal_id'],s[1]['terminal_id'],s[-1]['terminal_id'])")
TODAY=$(date +%F)

hdr "search offers the starting terminal only"
code GET "/trips/search?origin_terminal_id=$FIRST&destination_terminal_id=$LAST&service_date=$TODAY" >/dev/null
python3 -c "import json;assert any(t['trip_id']=='$TRIP' for t in json.load(open('/tmp/r.json')))" \
  && ok "from the starting terminal the trip is offered" || bad "trip not offered from stop 1"
code GET "/trips/search?origin_terminal_id=$SECOND&destination_terminal_id=$LAST&service_date=$TODAY" >/dev/null
is "$(python3 -c "import json;print(len(json.load(open('/tmp/r.json'))))")" 0 \
   "from a later terminal nothing is offered"
is "$(code GET "/trips/search?boarding_stop=2&alighting_stop=4&service_date=$TODAY")" 422 \
   "the stop-sequence search refuses a later boarding stop"
is "$(code GET "/bookings/availability?trip_id=$TRIP&boarding_stop=3&alighting_stop=4")" 422 \
   "no space is advertised from a later stop"
is "$(code GET "/bookings/availability?trip_id=$TRIP&boarding_stop=1&alighting_stop=4")" 200 \
   "space from stop 1 is advertised"

hdr "app bookings board at stop 1"
is "$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,\"alighting_stop\":4}" "$PT")" 422 \
   "a booking from stop 2 is refused"
grep -q "starting terminal" /tmp/r.json && ok "and says why" || bad "detail: $(cat /tmp/r.json)"
S=$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
is "$S" 201 "a booking from stop 1 is taken"
grep -q seat_number /tmp/r.json && bad "reserve still returns seat_number" || ok "reserve has no seat number"
BID=$(j "['booking_id']" < /tmp/r.json)
python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1
is "$(code POST /bookings/BKG-A2Z-U002/reschedule '{"new_trip_id":"TRIP-A2Z-TAG-D1-0900"}' "$AT")" 422 \
   "a stored stop-2 booking cannot be moved to another trip"

hdr "the Dispatcher lists cash passengers at stop 1"
BEFORE=$(total)
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,\"alighting_stop\":4}" "$DT")" 422 \
   "a cash passenger from stop 2 is refused"
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4,
  \"is_roadside_pickup\":true,\"pickup_landmark\":\"Km 42 waiting shed\",\"fare_override\":250.00}" "$DT")" 422 \
   "a roadside pickup is refused"
is "$(total)" "$BEFORE" "the refusals wrote no booking"
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":3,\"fare_override\":1.00}" "$DT")
FARE=$(j "['fare_amount']" < /tmp/r.json)
[ "$S" = "201" ] && [ "$FARE" != "1.00" ] && ok "listed on the scheduled trip at the table fare P$FARE" \
  || bad "walk-in gave $S, fare $FARE"
grep -q fare_is_manual /tmp/r.json && bad "response still reports fare_is_manual" || ok "no manual-fare flag"

hdr "nothing is listed after departure"
code POST "/trips/$TRIP/start" "" "$CT" >/dev/null
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$DT")" 201 \
   "listed while the trip boards"
code POST "/trips/$TRIP/depart" "" "$CT" >/dev/null
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$DT")" 409 \
   "a cash passenger after departure is refused"
is "$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")" 409 \
   "and so is an app booking"

hdr "the passenger list has no seat numbers or roadside fields"
code GET "/trips/$TRIP/manifest" "" "$DT" >/dev/null
grep -q '"seat_number"' /tmp/r.json && bad "manifest still has seat_number" || ok "no seat numbers"
grep -qE '"is_roadside_pickup"|"fare_is_manual"|"pickup_landmark"' /tmp/r.json \
  && bad "manifest still reports roadside fields" || ok "no roadside fields"

printf '\n%d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
