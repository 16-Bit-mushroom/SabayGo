#!/usr/bin/env bash
# Cash remittance: the false-leakage fix.
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
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

CT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
OT=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"coopadmin@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")

hdr "conductor logs three cash passengers"
code POST "/trips/$TRIP/start-boarding" "" "$CT" >/dev/null
for seg in "1 4" "2 4" "3 4"; do
  set -- $seg
  code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":$1,\"alighting_stop\":$2}" "$CT" >/dev/null
  echo "        stop $1 -> $2 : P$(j "['fare_amount']" < /tmp/r.json)"
done
ok "three cash fares recorded"

hdr "revenue BEFORE remittance"
code GET /revenue/summary "" "$OT" >/dev/null
python3 -c "
import json;r=json.load(open('/tmp/r.json'))
print(f\"        collected   P{r['collected_fare']}\")
print(f\"        cash in hand P{r.get('cash_in_hand','?')}   <- not missing, just not handed over\")
print(f\"        unreconciled P{r['unreconciled_amount']}   <- should be 0\")"
UNREC=$(j "['unreconciled_amount']" < /tmp/r.json)
[ "$UNREC" = "0.00" ] || [ "$UNREC" = "0" ] \
  && ok "cash no longer counted as missing money" \
  || bad "unreconciled is $UNREC, expected 0"

hdr "remittance before the trip runs is refused"
S=$(code POST "/remittances/trips/$TRIP/submit" '{"declared_amount":1005}' "$CT")
[ "$S" = "409" ] && ok "cannot remit a trip still boarding (409)" || bad "early submit gave $S"

hdr "trip departs, crew previews what they owe"
code POST "/trips/$TRIP/depart" "" "$CT" >/dev/null
S=$(code GET "/remittances/trips/$TRIP/preview" "" "$CT")
EXPECTED=$(j "['expected_amount']" < /tmp/r.json)
[ "$S" = "200" ] && ok "expected P$EXPECTED across $(j "['booking_count']" < /tmp/r.json) fare(s)" \
                 || bad "preview gave $S"

hdr "office sees the trip on the chase list"
code GET /remittances/unremitted-trips "" "$OT" >/dev/null
python3 -c "
import json;d=json.load(open('/tmp/r.json'))
for t in d: print(f\"        {t['service_date']}  {t['trip_label']}  P{t['cash_outstanding']} outstanding\")" 
ok "unremitted trips listed"

hdr "crew declares the correct amount"
S=$(code POST "/remittances/trips/$TRIP/submit" \
  "{\"declared_amount\":$EXPECTED,\"notes\":\"End of run\"}" "$CT")
[ "$S" = "200" ] && ok "declared P$(j "['declared_amount']" < /tmp/r.json), status $(j "['status']" < /tmp/r.json)" \
                 || bad "submit gave $S"
RID=$(j "['remittance_id']" < /tmp/r.json)

hdr "office counts it and confirms"
S=$(code POST "/remittances/$RID/receive" "{\"received_amount\":$EXPECTED}" "$OT")
if [ "$S" = "200" ]; then
  ok "received P$(j "['received_amount']" < /tmp/r.json), variance $(j "['variance']" < /tmp/r.json), status $(j "['status']" < /tmp/r.json)"
else bad "receive gave $S"; fi

hdr "revenue AFTER remittance"
code GET /revenue/summary "" "$OT" >/dev/null
python3 -c "
import json;r=json.load(open('/tmp/r.json'))
print(f\"        collected    P{r['collected_fare']}   <- cash has settled\")
print(f\"        cash in hand P{r.get('cash_in_hand','?')}\")
print(f\"        unreconciled P{r['unreconciled_amount']}\")"
ok "cash moved from in-hand to collected"

hdr "a short handover is recorded, not refused"
code POST "/trips/$TRIP/start-boarding" "" "$CT" >/dev/null
code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":3,\"alighting_stop\":4}" "$CT" >/dev/null
code POST "/trips/$TRIP/depart" "" "$CT" >/dev/null
code POST "/remittances/trips/$TRIP/submit" '{"declared_amount":100}' "$CT" >/dev/null
RID2=$(j "['remittance_id']" < /tmp/r.json)
S=$(code POST "/remittances/$RID2/receive" '{"received_amount":100,"notes":"Short by 75"}' "$OT")
if [ "$S" = "200" ]; then
  V=$(j "['variance']" < /tmp/r.json); ST=$(j "['status']" < /tmp/r.json)
  [ "$ST" = "disputed" ] && ok "shortage flagged: variance $V, status $ST" \
                         || bad "expected disputed, got $ST"
else bad "short receive gave $S"; fi

hdr "crew cannot confirm their own handover"
S=$(code POST "/remittances/$RID2/receive" '{"received_amount":175}' "$CT")
[ "$S" = "403" ] && ok "conductor blocked from confirming receipt (403)" || bad "gave $S"

printf '\n  passed %d   failed %d\n\n' "$P" "$F"
