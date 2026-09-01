#!/usr/bin/env bash
# Walk-in timing, roadside pickup, manual fares, no-show release.
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
  -d '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
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
code POST "/trips/$TRIP/start-boarding" "" "$CT" >/dev/null
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "walk-in accepted during boarding (was 409)" || bad "walk-in gave $S"

hdr "walk-in after departure"
code POST "/trips/$TRIP/depart" "" "$CT" >/dev/null
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "walk-in accepted after departure" || bad "post-departure walk-in gave $S"

hdr "roadside pickup"
S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,
  \"alighting_stop\":4,\"is_roadside_pickup\":true,
  \"pickup_landmark\":\"Km 42 waiting shed\",\"fare_override\":250.00,
  \"fare_note\":\"Boarded past Digos\"}" "$CT")
if [ "$S" = "201" ]; then
  ok "roadside recorded — P$(j "['fare_amount']" < /tmp/r.json), manual=$(j "['fare_is_manual']" < /tmp/r.json)"
else bad "roadside gave $S"; fi

S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,
  \"alighting_stop\":4,\"is_roadside_pickup\":true}" "$CT")
[ "$S" = "409" ] && ok "roadside without a fare rejected (409)" || bad "no-fare roadside gave $S"

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

hdr "manifest shows roadside flags, no seat numbers"
code GET "/trips/$TRIP/manifest" "" "$CT" >/dev/null
grep -q '"seat_number"' /tmp/r.json && bad "manifest still has seat_number" || ok "manifest has no seat numbers"
python3 -c "
import json;m=json.load(open('/tmp/r.json'))
for p in m['passengers']:
    tag = 'roadside' if p.get('is_roadside_pickup') else p['booking_type']
    fare = f\"P{p['fare_amount']}\" + ('*' if p.get('fare_is_manual') else '')
    print(f\"        {p['boarding_stop']}->{p['alighting_stop']}  {p['status']:<11} {tag:<14} {fare}\")
print('        (* = fare set by hand)')"

printf '\n  passed %d   failed %d\n\n' "$P" "$F"
