#!/usr/bin/env bash
# Rev 603 R10a: the Van Status Board (change brief 8 and 9). Each van on
# site, travelling, not on a trip or out of service, from the trip status
# and GPS readings already stored, and what it still owes of A2Z's share.
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_van_board.sh
#
# The demo seed gives every state: TRIP-A2Z-LIVE-DEPART is on the road,
# LIVE-BOARD and the fixture trips are assigned for today, GAK-2205 is in
# maintenance and LCT-9042 has no trip.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP=TRIP-DEMO-00000001
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
field() { j "$1" < /tmp/vb.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/vb.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
edge() { curl -s -o /tmp/vb.json -w "%{http_code}" -X POST "$API$1" -H "X-Device-Token: $TOK" -H "Content-Type: application/json" -d "$2"; }
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  field "['access_token']"
}
sql() {
  (cd "$BACKEND" && venv/bin/python -c "
import asyncio, sys
from sqlalchemy import text
from app.core.db import engine
async def m():
    async with engine.begin() as c:
        r = await c.execute(text(sys.argv[1]))
        if r.returns_rows:
            for row in r: print(row[0])
    await engine.dispose()
asyncio.run(m())" "$1")
}
# van PLATE KEYS -> the board's row for that van, the keys joined by '/'
van() {
  code GET /fleet/vans/board "" "$CT" >/dev/null
  python3 -c "
import json, sys
row = next(v for v in json.load(open('/tmp/vb.json')) if v['plate_number'] == sys.argv[1])
print('/'.join(str(row[k]) for k in sys.argv[2].split(',')))" "$1" "$2"
}

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); PT=$(login passenger)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$PT" ] && ok "signed in" || { bad "login"; exit 1; }

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Who sees the board"
is "$(code GET /fleet/vans/board "" "$CT")" 200 "the Cashier"
is "$(code GET /fleet/vans/board "" "$OT")" 200 "the Terminal Manager"
is "$(code GET /fleet/vans/board "" "$DT")/$(code GET /fleet/vans/board "" "$PT")" 403/403 \
   "not the Dispatcher, not a passenger"
code GET /fleet/vans/board "" "$CT" >/dev/null
is "$(python3 -c "import json;print(len(json.load(open('/tmp/vb.json'))))")" "$(sql "SELECT COUNT(*) FROM vans")" "every van, once"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. The four states, from what is stored (brief 8)"
DEP_VAN=$(sql "SELECT van_plate_number FROM trips WHERE trip_id = 'TRIP-A2Z-LIVE-DEPART'")
DEP_VAN=${DEP_VAN:-$(sql "SELECT v.plate_number FROM trips t JOIN vans v ON v.van_id = t.van_id WHERE t.trip_id = 'TRIP-A2Z-LIVE-DEPART'")}
is "$(van "$DEP_VAN" state,trip_id,trip_status)" "travelling/TRIP-A2Z-LIVE-DEPART/departed" \
   "$DEP_VAN is travelling: its trip departed"
[ "$(van "$DEP_VAN" dispatcher_name,operator_name,route_name | grep -c None)" = 0 ] \
  && ok "with the Dispatcher, the operator and the route: $(van "$DEP_VAN" dispatcher_name,operator_name,route_name)" \
  || bad "travelling row: $(van "$DEP_VAN" dispatcher_name,operator_name,route_name)"
is "$(van "$DEP_VAN" aboard,latitude)" "None/None" "no phone, no readings: nothing aboard or on the map is invented"
is "$(van LAB-4521 state,trip_id)" "on_site/TRIP-A2Z-LIVE-BOARD" "LAB-4521 is on site: its trip is boarding"
is "$(van ABC-1234 state,trip_id)" "on_site/$TRIP" "ABC-1234 is on site: assigned to a trip of today"
is "$(van GAK-2205 state,operational_status,trip_id)" "out_of_service/maintenance/None" "GAK-2205 is out of service"
is "$(van LCT-9042 state,trip_id)" "not_on_trip/None" "LCT-9042 has no trip today"
is "$(van ABC-1234 owes)/$(van "$DEP_VAN" owes)" "0.00/0.00" "and nobody owes: every started trip is paid"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Travelling with a phone: aboard and the last position"
DEP_VAN_ID=$(sql "SELECT van_id FROM trips WHERE trip_id = 'TRIP-A2Z-LIVE-DEPART'")
DEP_DISP=$(sql "SELECT dispatcher_id FROM trips WHERE trip_id = 'TRIP-A2Z-LIVE-DEPART'")
code POST /devices '{"device_model":"realme board"}' "$OT" >/dev/null
DEV=$(field "['device_id']"); TOK=$(field "['device_token']")
is "$(code POST /devices/$DEV/checkout "{\"van_id\":\"$DEP_VAN_ID\",\"dispatcher_id\":\"$DEP_DISP\"}" "$CT")" 200 \
   "a phone checked out with $DEP_VAN"
sql "UPDATE device_checkouts SET checked_out_at = NOW() - INTERVAL 1 MINUTE WHERE device_id = '$DEV'"
EV=$(python3 -c "
import datetime as d, json, uuid
t = d.datetime.now()
ev = [(-30, 'board'), (-29, 'board'), (-28, 'board'), (-10, 'alight')]
print(json.dumps({'events': [{'event_id': str(uuid.uuid4()), 'event_type': k,
  'event_at': (t + d.timedelta(seconds=s)).isoformat()} for s, k in ev]}))")
is "$(edge /edge/events "$EV")" 200 "it counts three boardings and one alighting"
NOW=$(date '+%Y-%m-%dT%H:%M:%S')
is "$(edge /edge/fixes "{\"fixes\":[{\"recorded_at\":\"$NOW\",\"latitude\":7.1,\"longitude\":125.6,\"speed_kph\":40}]}")" 200 \
   "and sends a GPS reading"
is "$(van "$DEP_VAN" aboard,latitude,longitude,position_stale)" "2/7.1/125.6/False" \
   "the board shows 2 aboard and the van's last position"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. Out of service, but on the road"
VID=$(sql "SELECT van_id FROM vans WHERE plate_number = 'XYZ-9876'")
is "$(code PATCH /fleet/vans/$VID/status '{"operational_status":"maintenance"}' "$OT")" 200 "XYZ-9876 goes into maintenance"
is "$(van XYZ-9876 state,trip_id)" "out_of_service/None" "out of service, though a trip of today names it"
code PATCH /fleet/vans/$DEP_VAN_ID/status '{"operational_status":"maintenance"}' "$OT" >/dev/null
is "$(van "$DEP_VAN" state)" travelling "a van on the road stays travelling until it arrives"
code PATCH /fleet/vans/$DEP_VAN_ID/status '{"operational_status":"active"}' "$OT" >/dev/null
code PATCH /fleet/vans/$VID/status '{"operational_status":"active"}' "$OT" >/dev/null

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. A van that left unpaid owes, until the Cashier records it"
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":3}" "$DT")" 201 \
   "a cash passenger on ABC-1234's trip"
code GET /trips/$TRIP/share "" "$CT" >/dev/null; DUE=$(field "['amount_due']")
is "$(code POST /trips/$TRIP/payment-override '{"note":"Cashier away, paying on return"}' "$OT")" 200 \
   "the Terminal Manager lifts the payment block (₱$DUE due)"
is "$(code POST /trips/$TRIP/start "" "$CT")/$(code POST /trips/$TRIP/depart "" "$DT")" 200/200 "started and departed"
is "$(van ABC-1234 state,owes)" "travelling/$DUE" "travelling, and owes ₱$DUE"
is "$(code POST /trips/$TRIP/arrive "" "$DT")" 200 "it arrives"
is "$(van ABC-1234 state,owes)" "not_on_trip/$DUE" "back with no trip, still owing for its last one"
code GET "/statements?date=$(date +%F)" "" "$CT" >/dev/null
SID=$(python3 -c "import json;print(next(s['remittance_id'] for s in json.load(open('/tmp/vb.json')) if s['plate_number']=='ABC-1234'))")
is "$(code POST /statements/$SID/payments "{\"amount\":\"$DUE\",\"reference\":\"OR-VB\"}" "$CT")" 200 \
   "the Cashier records the payment"
is "$(van ABC-1234 owes)" "0.00" "and the van owes nothing"

code POST /devices/$DEV/return '{}' "$CT" >/dev/null
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
