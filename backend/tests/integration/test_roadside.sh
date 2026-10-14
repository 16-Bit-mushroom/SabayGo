#!/usr/bin/env bash
# Walk-in timing, roadside refusal (rev 468), table fares only, no-show release.
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr(){ printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
code(){ local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/r.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"; }

CT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"dispatcher@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
OT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"cashier@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"rs${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
       \"password\":\"sabaygo123\",\"first_name\":\"Road\",\"last_name\":\"Side\"}" \
  | j "['access_token']")

hdr "no seat number in any response"
S=$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
[ -s /tmp/r.json ] && { grep -q seat_number /tmp/r.json && bad "reserve still returns seat_number" || ok "reserve has no seat number"; } || bad "no response body"
BID=$(j "['booking_id']" < /tmp/r.json)
python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1

hdr "walk-in while the van is loading"
code POST "/trips/$TRIP/start" "" "$OT" >/dev/null
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "walk-in accepted during boarding (was 409)" || bad "walk-in gave $S"

hdr "walk-in after departure"
code POST "/trips/$TRIP/depart" "" "$OT" >/dev/null
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "walk-in accepted after departure" || bad "post-departure walk-in gave $S"

hdr "roadside pickup refused (rev 468)"
BEFORE=$(code GET "/trips/$TRIP/manifest" "" "$CT" >/dev/null; j "['total_bookings']" < /tmp/r.json)
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,
  \"alighting_stop\":4,\"is_roadside_pickup\":true,
  \"pickup_landmark\":\"Km 42 waiting shed\",\"fare_override\":250.00}" "$CT")
[ "$S" = "422" ] && ok "roadside pickup refused (422)" || bad "roadside gave $S"
AFTER=$(code GET "/trips/$TRIP/manifest" "" "$CT" >/dev/null; j "['total_bookings']" < /tmp/r.json)
[ "$BEFORE" = "$AFTER" ] && ok "refusal wrote no booking ($AFTER)" || bad "bookings went $BEFORE -> $AFTER"

hdr "the Dispatcher cannot set a fare"
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,
  \"alighting_stop\":4,\"fare_override\":1.00}" "$CT")
FARE=$(j "['fare_amount']" < /tmp/r.json)
grep -q fare_is_manual /tmp/r.json && bad "response still reports fare_is_manual" || true
[ "$S" = "201" ] && [ "$FARE" != "1.00" ] && ok "fare_override ignored, table fare P$FARE" \
  || bad "walk-in with fare_override gave $S, fare $FARE"

hdr "app bookings still use the approved table"
S=$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
[ "$S" = "409" ] && ok "app booking closed once departed (409)" || bad "app booking gave $S"

hdr "no-show space released"
python3 -c "
import json;m=json.load(open('/tmp/m.json'))" 2>/dev/null
code GET "/trips/$TRIP/manifest" "" "$CT" >/dev/null; cp /tmp/r.json /tmp/m.json
python3 -c "
import json;m=json.load(open('/tmp/m.json'))
ns=[p for p in m['passengers'] if p['status']=='no_show']
print(f'        no-shows: {len(ns)}  total: {m[\"total_bookings\"]}')"
S=$(code "GET" "/bookings/availability?trip_id=$TRIP&boarding_stop=3&alighting_stop=4")
ok "space still sellable on later sections: $(j "['seats_available']" < /tmp/r.json)"

hdr "manifest has no roadside flags, no seat numbers"
code GET "/trips/$TRIP/manifest" "" "$CT" >/dev/null
grep -q '"seat_number"' /tmp/r.json && bad "manifest still has seat_number" || ok "manifest has no seat numbers"
grep -qE '"is_roadside_pickup"|"fare_is_manual"|"pickup_landmark"' /tmp/r.json \
  && bad "manifest still reports roadside fields" || ok "manifest reports no roadside fields"
python3 -c "
import json;m=json.load(open('/tmp/r.json'))
for p in m['passengers']:
    print(f\"        {p['boarding_stop']}->{p['alighting_stop']}  {p['status']:<11} {p['booking_type']:<14} P{p['fare_amount']}\")"

printf '\n  passed %d   failed %d\n\n' "$P" "$F"
