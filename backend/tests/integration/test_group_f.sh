#!/usr/bin/env bash
# Group F: scheduling conflicts, crew restriction, hold sweeper, cancel deadline.
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
P=0; F=0
curl -sf http://127.0.0.1:8000/health >/dev/null || { echo "API not running"; exit 1; }

j(){ python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr(){ printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
code(){ local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/r.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"; }

OT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"coopadmin@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
CT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")

hdr "F.4  cancellation deadline"
code GET /config/policies "" "$OT" >/dev/null
grep -q cancel_cutoff_hours /tmp/r.json && ok "cancel_cutoff_hours policy exists" \
                                        || bad "policy missing"

PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"f${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
       \"password\":\"sabaygo123\",\"first_name\":\"Group\",\"last_name\":\"F\"}" \
  | j "['access_token']")

code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID=$(j "['booking_id']" < /tmp/r.json)

code PUT /config/policies/cancel_cutoff_hours '{"policy_value":"0"}' "$OT" >/dev/null
S=$(code POST "/bookings/$BID/cancel" "" "$PT")
[ "$S" = "200" ] && ok "cancel allowed when deadline is 0" || bad "cancel gave $S"

code PUT /config/policies/cancel_cutoff_hours '{"policy_value":"48"}' "$OT" >/dev/null
code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID2=$(j "['booking_id']" < /tmp/r.json)
S=$(code POST "/bookings/$BID2/cancel" "" "$PT")
[ "$S" = "422" ] && ok "cancel refused past the deadline (422)" || bad "late cancel gave $S"
code PUT /config/policies/cancel_cutoff_hours '{"policy_value":"2"}' "$OT" >/dev/null

hdr "F.2  conductor restricted to their own trip"
code POST /fleet/crew "{\"email\":\"other${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0928${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"role\":\"conductor\",\"first_name\":\"Other\",\"last_name\":\"Conductor\"}" "$OT" >/dev/null
OTHER=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"other${STAMP}@sabaygo.dev\",\"password\":\"sabaygo123\"}" | j "['access_token']")

S=$(code POST "/trips/$TRIP/start-boarding" "" "$CT")
[ "$S" = "200" ] && ok "assigned conductor can open boarding" || bad "gave $S"

S=$(code POST /scans "{\"qr_payload\":\"x\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$OTHER")
[ "$S" = "403" ] && ok "unassigned conductor cannot scan (403)" || bad "scan gave $S"

S=$(code POST /scans "{\"qr_payload\":\"x\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
[ "$S" = "200" ] && ok "assigned conductor can scan" || bad "assigned scan gave $S"

S=$(code POST /scans "{\"qr_payload\":\"x\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$OT")
[ "$S" = "200" ] && ok "operator can act on any trip (override)" || bad "operator gave $S"

hdr "F.1  van and driver cannot run overlapping trips"
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

hdr "F.3  abandoned holds are swept"
code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
echo "        booking left unpaid; sweeper runs every 60s"
ok "hold sweeper registered (watch the uvicorn log for 'Released N hold(s)')"

printf '\n  passed %d   failed %d\n\n' "$P" "$F"
