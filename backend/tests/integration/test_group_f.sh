#!/usr/bin/env bash
# Group F: scheduling conflicts, crew restriction, who may cancel a seat,
# and the release of unpaid reservations (rev 721).
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
P=0; F=0; G=0
curl -sf http://127.0.0.1:8000/health >/dev/null || { echo "API not running"; exit 1; }

j(){ python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr(){ printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
gap(){ printf '  \033[33mGAP \033[0m  %s\n' "$1"; G=$((G+1)); }
code(){ local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/r.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"; }

OT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"manager@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
CT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"dispatcher@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
# Only the Cashier records the share handed over at the counter.
KT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"cashier@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")

hdr "F.4  who may cancel a seat"
# Rev 721 has no cancellation deadline in hours: an unpaid reservation
# can be cancelled in the app until the trip's list locks, and a paid
# seat only through the Dispatcher, who hands the cash back. The
# cancel_cutoff_hours setting went with migration 033.
code GET /config/policies "" "$OT" >/dev/null
grep -q cancel_cutoff_hours /tmp/r.json \
  && bad "the retired cancel_cutoff_hours setting is still offered" \
  || ok "no cancellation deadline is offered as a setting"

PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"f${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
       \"password\":\"sabaygo123\",\"first_name\":\"Group\",\"last_name\":\"F\"}" \
  | j "['access_token']")

code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID=$(j "['booking_id']" < /tmp/r.json)
S=$(code POST "/bookings/$BID/cancel" "" "$PT")
[ "$S" = "200" ] && ok "the passenger cancels their own unpaid reservation" \
                 || bad "cancel gave $S"

code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID2=$(j "['booking_id']" < /tmp/r.json)
code POST "/bookings/$BID2/mark-paid" '{}' "$CT" >/dev/null
S=$(code POST "/bookings/$BID2/cancel" "" "$PT")
[ "$S" = "422" ] && ok "a paid seat is refused in the app (422): the cash is in a pocket" \
                 || bad "cancel of a paid seat gave $S"

hdr "F.2  Dispatcher restricted to their own trip"
code POST /fleet/crew "{\"email\":\"other${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0928${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"role\":\"dispatcher\",\"first_name\":\"Other\",\"last_name\":\"Dispatcher\"}" "$OT" >/dev/null
OTHER=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"other${STAMP}@sabaygo.dev\",\"password\":\"sabaygo123\"}" | j "['access_token']")

# F.4 took cash for a seat, so A2Z's share is now due and Start is
# blocked until the Cashier records it (brief 2.1).
code GET "/trips/$TRIP/share" "" "$KT" >/dev/null
DUE=$(j "['amount_due']" < /tmp/r.json)
code POST "/trips/$TRIP/payment" "{\"amount\":\"$DUE\",\"reference\":\"OR-GROUPF\"}" "$KT" >/dev/null
S=$(code POST "/trips/$TRIP/start" "" "$OT")
[ "$S" = "200" ] && ok "the office records the share (P$DUE) and starts the trip" \
                 || bad "start gave $S: $(j "['detail']" < /tmp/r.json)"

S=$(code GET "/bookings/trip/$TRIP/seats" "" "$OTHER")
[ "$S" = "403" ] && ok "unassigned Dispatcher cannot read the seat list (403)" || bad "seat list gave $S"

S=$(code GET "/bookings/trip/$TRIP/seats" "" "$CT")
[ "$S" = "200" ] && ok "assigned Dispatcher can scan" || bad "assigned scan gave $S"

S=$(code GET "/bookings/trip/$TRIP/seats" "" "$OT")
[ "$S" = "200" ] && ok "Terminal Manager can act on any trip (override)" || bad "Terminal Manager gave $S"

hdr "F.1  a van cannot run overlapping trips"
code GET /config/schedule-templates "" "$OT" >/dev/null
ROUTE=$(python3 -c "
import json;d=json.load(open('/tmp/r.json'));print(d[0]['route_id'] if d else '')")

S=$(code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
  \"departure_datetime\":\"$(date -d '+3 days 08:00' '+%Y-%m-%dT%H:%M:%S')\",
  \"van_id\":\"VAN-0001\",\"trip_label\":\"Conflict A\"}" "$OT")
[ "$S" = "201" ] && ok "first special trip created" || bad "gave $S"

S=$(code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
  \"departure_datetime\":\"$(date -d '+3 days 09:00' '+%Y-%m-%dT%H:%M:%S')\",
  \"van_id\":\"VAN-0001\",\"trip_label\":\"Conflict B\"}" "$OT")
if [ "$S" = "409" ]; then
  ok "overlapping van assignment refused: $(j "['detail']" < /tmp/r.json)"
else bad "overlap gave $S"; fi

S=$(code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
  \"departure_datetime\":\"$(date -d '+3 days 20:00' '+%Y-%m-%dT%H:%M:%S')\",
  \"van_id\":\"VAN-0001\",\"trip_label\":\"Later, no clash\"}" "$OT")
[ "$S" = "201" ] && ok "same van accepted well after the first run" || bad "gave $S"

hdr "F.3  unpaid reservations are released at the cutoff"
# The rule itself, with its restore path, is test_unpaid_release.sh. This
# only proves the job is wired to the running server and reads its
# setting (rev 721 replaced the seat-hold sweeper with it).
code GET /config/policies "" "$OT" >/dev/null
grep -q unpaid_cutoff_min /tmp/r.json && ok "unpaid_cutoff_min is a setting" \
                                      || bad "unpaid_cutoff_min missing"
grep -qE 'seat_hold_ttl_seconds|hold_sweep_interval_seconds' /tmp/r.json \
  && bad "a retired seat-hold setting is still offered" \
  || ok "the gateway-era seat-hold settings are gone"
grep -q "Unpaid release started" ../logs/backend*.log 2>/dev/null \
  && ok "the release job is running on the server" \
  || gap "no backend log to read: check the uvicorn output for 'Unpaid release started'"

printf '\n  passed %d   failed %d   gaps %d\n\n' "$P" "$F" "$G"
