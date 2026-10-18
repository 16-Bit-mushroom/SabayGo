#!/usr/bin/env bash
# Rev 603 R3b: special trips, a whole van rented (change brief 2.5;
# T49-T52 in 12.2). A fee paid in cash (D) and through the gateway (V).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_special_trips.sh
#
# Needs the backend on :8000. Uses VAN-0006 (LCT-9042) and VAN-0004
# (NBC-7788, free until its 2-hour trip), dispatcher2 and dispatcher3.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }
field() { j "['$1']" < /tmp/st.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/st.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  field access_token
}
at() { date -d "$1" '+%Y-%m-%dT%H:%M:00'; }
# A request body: req MINUTES_AHEAD COUNT
req() {
  printf '{"pickup_at":"%s","pickup":{"address":"Purok 5, Catalunan Grande","latitude":7.0731,"longitude":125.5480},"destination":{"address":"Samal Island ferry, Sasa"},"passenger_count":%s}' \
    "$(at "+$1 min")" "$2"
}
board() {
  code GET /config/trips "" "$OT" >/dev/null
  python3 -c "import json;print({t['trip_id']:t for t in json.load(open('/tmp/st.json'))}['$1']['$2'])"
}
notes() {  # notes TOKEN TYPE ENTITY_ID
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/st.json'))['items'] if n['type']=='$2' and n['related_entity_id']=='$3'))"
}
stmt() {  # stmt PLATE FIELD
  code GET /statements "" "$CT" >/dev/null
  python3 -c "import json;print({s['plate_number']:s for s in json.load(open('/tmp/st.json'))}['$1']['$2'])"
}
sql() {
  (cd "$(dirname "$0")/../.." && venv/bin/python -c "
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

PT=$(login passenger); AT=$(login ana); OT=$(login manager); CT=$(login cashier)
D2T=$(login dispatcher2); D3T=$(login dispatcher3)
[ -n "$PT" ] && [ -n "$AT" ] && [ -n "$OT" ] && [ -n "$CT" ] && [ -n "$D3T" ] \
  && ok "signed in" || { bad "login"; exit 1; }

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. A passenger asks for the whole van in the app (T50)"
is "$(code POST /special-trips "$(req 20 15)" "$PT")" 422 "T50 15 passengers is refused: the van seats 14"
is "$(code POST /special-trips "$(req -10 4)" "$PT")" 409 "a pickup time already past is refused"
is "$(code POST /special-trips "$(req 20 4)" "$OT")" 403 "the office does not ask in the app"
is "$(code POST /special-trips "$(req 20 14)" "$PT")" 201 "T50 with 14 the request is stored"
R1=$(field request_id)
is "$(field status)/$(field entered_by)/$(field rental_fee)" requested/None/None \
   "from the app: no one entered it, no fee yet"
[ "$(field passenger_user_id)" != "None" ] && ok "PassengerID is set" || bad "no passenger on the request"
is "$(notes "$OT" special_trip_request "$R1")/$(notes "$CT" special_trip_request "$R1")" 1/1 \
   "'Special Trip Request' to the Terminal Manager and the Cashier"
code POST /special-trips "$(req 30 6)" "$PT" >/dev/null; R2=$(field request_id)
code POST /special-trips "$(req 40 2)" "$PT" >/dev/null; R3=$(field request_id)
code GET /special-trips/mine "" "$PT" >/dev/null
python3 -c "import json;assert len([r for r in json.load(open('/tmp/st.json')) if r['request_id'] in ('$R1','$R2','$R3')])==3" \
  && ok "the passenger sees their requests" || bad "mine is missing a request"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. The office reviews"
is "$(code GET /special-trips "" "$D2T")" 403 "a Dispatcher cannot read the requests"
is "$(code GET "/special-trips?status=requested" "" "$CT")" 200 "the Cashier reads them"
python3 -c "import json;assert {'$R1','$R2','$R3'} <= {r['request_id'] for r in json.load(open('/tmp/st.json'))}" \
  && ok "all three are waiting" || bad "requested list"
is "$(code POST /special-trips/$R1/approve '{"fee":"3500.00"}' "$OT")" 422 "a fee needs a note on what it is based on"
is "$(code POST /special-trips/$R1/approve '{"fee":"3500.00","fee_note":"Catalunan Grande to Sasa, 14 pax"}' "$PT")" 403 \
   "the passenger cannot approve"
is "$(code POST /special-trips/$R1/approve '{"fee":"3500.00","fee_note":"Catalunan Grande to Sasa, 14 pax"}' "$OT")" 200 \
   "the Terminal Manager agrees the fee and approves"
RT1=$(field trip_id)
is "$(field status)/$(field rental_fee)/$(field payment_status)" approved/3500.00/unpaid "approved, fee ₱3,500, unpaid"
is "$(code POST /special-trips/$R1/approve '{"fee":"1.00","fee_note":"again"}' "$OT")" 409 "approved once only"
is "$(board $RT1 status)/$(sql "SELECT COALESCE(route_id, 'none') FROM trips WHERE trip_id = '$RT1'")/$(board $RT1 van_id)" \
   scheduled/none/None "its trip: no route, no van yet"
is "$(sql "SELECT is_special_trip FROM trips WHERE trip_id = '$RT1'")" 1 "IsSpecial = TRUE"
is "$(notes "$PT" trip_update "$RT1")" 1 "the passenger is told the fee"
is "$(code POST /special-trips/$R2/reject '{"reason":"No van free that afternoon"}' "$CT")" 200 "the Cashier rejects one, with a reason"
code GET "/notifications?limit=100" "" "$PT" >/dev/null
python3 -c "import json;assert any(n['related_entity_id']=='$R2' and 'No van free' in n['message'] for n in json.load(open('/tmp/st.json'))['items'])" \
  && ok "the passenger is told why" || bad "no rejection notice"
is "$(code POST /special-trips/$R3/withdraw "" "$AT")" 404 "another passenger cannot withdraw it"
is "$(code POST /special-trips/$R3/withdraw "" "$PT")" 200 "the passenger withdraws one before approval"
is "$(code POST /special-trips/$R1/withdraw "" "$PT")" 409 "an approved one is not withdrawn in the app"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. A walk-in at the counter (T49)"
W='{"customer_name":"Maria Santos","customer_contact":"09171234567","pickup_at":"'"$(at '+20 min')"'","pickup":{"address":"Ecoland terminal"},"destination":{"address":"Eden Nature Park"},"passenger_count":10,"fee":"2000.00","fee_note":"Ecoland to Eden, half day"}'
is "$(code POST /special-trips/walk-in "$W" "$D3T")" 403 "a Dispatcher cannot enter one"
is "$(code POST /special-trips/walk-in "$W" "$CT")" 201 "T49 the Cashier enters it and agrees the fee"
RW=$(field request_id); TW=$(field trip_id)
is "$(field passenger_user_id)/$(field customer_name)/$(field status)" "None/Maria Santos/approved" \
   "PassengerID NULL, CustomerName set, approved as entered"
[ "$(field entered_by)" = "$(field reviewed_by)" ] && [ "$(field entered_by)" != "None" ] \
  && ok "EnteredBy is the Cashier" || bad "entered_by $(field entered_by)"
is "$(field fee_note)" "Ecoland to Eden, half day" "FeeNote kept"
is "$(sql "SELECT is_special_trip FROM trips WHERE trip_id = '$TW'")" 1 "the trip is created with IsSpecial = TRUE"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. The operator declines a far trip (T52)"
is "$(code PUT /trips/$RT1/assignment '{"van_id":"VAN-0006","dispatcher_id":"USER-DISPATCHER-0002"}' "$CT")" 200 \
   "LCT-9042 and dispatcher2 are assigned at the van's turn"
is "$(code PUT /trips/$RT1/assignment '{"van_id":"VAN-0004","dispatcher_id":"USER-DISPATCHER-0002"}' "$CT")" 200 \
   "T52 its operator declines: the Cashier assigns NBC-7788"
is "$(board $RT1 van_id)" VAN-0004 "the first assignment is cleared"
is "$(sql "SELECT is_special_trip FROM trips WHERE trip_id = '$RT1'")" 1 "still a special trip"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Payment first (T51)"
is "$(code PUT /trips/$TW/assignment '{"van_id":"VAN-0006","dispatcher_id":"USER-DISPATCHER-0003"}' "$CT")" 200 \
   "the walk-in gets LCT-9042 and dispatcher3"
is "$(code POST /trips/$TW/start "" "$CT")" 409 "Start is refused while the fee is unpaid"
field detail | grep -q "rental fee" && ok "and says the fee comes first" || bad "detail: $(field detail)"
is "$(code POST /trips/$TW/payment-override '{"note":"Customer pays later"}' "$OT")" 200 "an override lifts the 15 % block"
is "$(code POST /trips/$TW/start "" "$CT")" 409 "but not the fee: Start still waits"
code GET /trips/assigned "" "$D3T" >/dev/null
is "$(python3 -c "import json;t=next(x for x in json.load(open('/tmp/st.json')) if x['trip_id']=='$TW');r=t['rental'];print(r['request_id']=='$RW', r['rental_fee'], r['payment_status'])")" \
   "True 2000.00 unpaid" "dispatcher3's app shows the rental, its ₱2,000 fee, unpaid"
is "$(code POST /special-trips/$RW/cash "" "$D2T")" 404 "another Dispatcher cannot log its fee"
is "$(code POST /special-trips/$RW/cash "" "$D3T")" 200 "dispatcher3 logs the ₱2,000 received in cash"
is "$(field payment_status)" paid "the fee is paid"
is "$(code POST /special-trips/$RW/cash "" "$D3T")" 409 "logged once only"
code GET /trips/$TW/share "" "$CT" >/dev/null
python3 -c "import json;s=json.load(open('/tmp/st.json'));l=s['lines'];assert len(l)==1 and l[0]['income_group']=='declared' and l[0]['gross_fare']=='2000.00' and l[0]['share_amount']=='300.00' and l[0]['dest_terminal_id'] is None" \
  && ok "T51 one fare line: declared, ₱2,000, share ₱300" || bad "lines: $(cat /tmp/st.json)"
is "$(sql "SELECT request_id FROM remittance_lines WHERE trip_id = '$TW'")" "$RW" "the line names its request"
is "$(stmt LCT-9042 declared_income)/$(stmt LCT-9042 remittance_owed)" 2000.00/300.00 "D = ₱2,000, RemittanceOwed = ₱300"

hdr "   (the override is withdrawn to show the 15 % block too)"
sql "UPDATE trips SET payment_override_by = NULL, payment_override_at = NULL, payment_override_note = NULL, payment_status = 'unpaid' WHERE trip_id = '$TW'"
is "$(code POST /trips/$TW/start "" "$CT")" 409 "T51 Start is blocked until the Cashier records ₱300"
field detail | grep -q "300.00" && ok "and says ₱300 is due" || bad "detail: $(field detail)"
is "$(code POST /trips/$TW/payment '{"amount":"300.00","reference":"OR-RENT"}' "$CT")" 200 "the Cashier records ₱300"
is "$(code POST /trips/$TW/start "" "$CT")" 200 "Start"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5b. The fee through the app: verified (V)"
is "$(code POST /special-trips/$R2/checkout "" "$PT")" 409 "a rejected request is not paid"
is "$(code POST /special-trips/$R1/checkout "" "$AT")" 404 "another passenger cannot pay it"
is "$(code POST /special-trips/$RW/checkout "" "$PT")" 404 "nor a counter customer's"
is "$(code POST /special-trips/$R1/checkout "" "$PT")" 201 "the renter starts the checkout"
URL=$(field checkout_url)
is "$(field amount)" 3500.00 "for the agreed ₱3,500"
UNSIGNED='{"data":{"id":"evt_forged","attributes":{"type":"checkout_session.payment.paid","data":{"id":"cs_forged","attributes":{"metadata":{"request_id":"'"$R1"'"}}}}}}'
code POST /payments/webhook "$UNSIGNED" >/dev/null
is "$(field status)/$(sql "SELECT payment_status FROM special_trip_requests WHERE request_id = '$R1'")" rejected/unpaid \
   "an unsigned webhook is refused: still unpaid"
curl -s -X POST "$URL/pay" | grep -q "Payment received" && ok "paid on the sandbox page: the signed webhook settles it" \
  || bad "sandbox pay"
is "$(sql "SELECT CONCAT(payment_status, '/', LEFT(payment_reference, 11)) FROM special_trip_requests WHERE request_id = '$R1'")" \
   paid/cs_sandbox_ "the fee is paid, with the gateway's reference"
code GET /trips/$RT1/share "" "$CT" >/dev/null
python3 -c "import json;l=json.load(open('/tmp/st.json'))['lines'];assert len(l)==1 and l[0]['income_group']=='verified' and l[0]['share_amount']=='525.00'" \
  && ok "one fare line: verified, share ₱525" || bad "lines: $(cat /tmp/st.json)"
curl -s -X POST "$URL/pay" | grep -q "Nothing to pay" && ok "the page again: nothing to pay" || bad "second pay"
code GET /trips/$RT1/share "" "$CT" >/dev/null
is "$(python3 -c "import json;print(len(json.load(open('/tmp/st.json'))['lines']))")" 1 "still one line"
is "$(code POST /special-trips/$R1/checkout "" "$PT")" 409 "a paid fee is not checked out again"
is "$(code POST /special-trips/$R1/cash "" "$D2T")" 409 "nor logged again in cash"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. A request closes with its trip"
is "$(code POST /trips/$TW/depart "" "$D3T")" 200 "dispatcher3 departs"
# A rental has no route: overspeed only, against the default limit (2.5).
code POST /devices '{"device_model":"realme rental"}' "$OT" >/dev/null
DEV=$(field device_id); TOK=$(field device_token)
code POST /devices/$DEV/checkout '{"van_id":"VAN-0006","dispatcher_id":"USER-DISPATCHER-0003"}' "$CT" >/dev/null
sql "UPDATE device_checkouts SET checked_out_at = NOW() - INTERVAL 5 MINUTE WHERE device_id = '$DEV'"
fixes() {  # fixes FROM_S: seven readings 5 s apart at 90 km/h, FROM_S seconds from now
  python3 -c "
import datetime as d, json, sys
t = d.datetime.now(); f = int(sys.argv[1])
print(json.dumps({'fixes': [{'recorded_at': (t + d.timedelta(seconds=f + 5 * i)).isoformat(),
  'latitude': 7.05 + 0.001 * i, 'longitude': 125.6, 'speed_kph': 90} for i in range(7)]}))" "$1"
}
rflags() { sql "SELECT CONCAT_WS('/', flag_type, IFNULL(stretch_no, '-'), limit_kmh, max_speed_kmh) FROM driving_events WHERE trip_id = '$TW'"; }
curl -s -o /dev/null -X POST "$API/edge/fixes" -H "X-Device-Token: $TOK" -H "Content-Type: application/json" -d "$(fixes 1)"
is "$(rflags)" "" "90 km/h for 30 s: no flag while special_trip_speed_kmh is unset"
is "$(code PUT /config/policies/special_trip_speed_kmh '{"policy_value":"60"}' "$CT")" 403 "only the Terminal Manager sets it"
is "$(code PUT /config/policies/special_trip_speed_kmh '{"policy_value":"60"}' "$OT")" 200 "the Terminal Manager sets 60 km/h"
curl -s -o /dev/null -X POST "$API/edge/fixes" -H "X-Device-Token: $TOK" -H "Content-Type: application/json" -d "$(fixes 40)"
is "$(rflags | sort -u | tr '\n' ' ')" "overspeed/-/60.0/90.0 " "now overspeed is flagged: no stretch, the 60 km/h default"
code PUT /config/policies/special_trip_speed_kmh '{"policy_value":""}' "$OT" >/dev/null
code POST /devices/$DEV/return '{}' "$CT" >/dev/null
is "$(code POST /trips/$TW/arrive "" "$D3T")" 200 "and taps Arrived"
is "$(sql "SELECT status FROM special_trip_requests WHERE request_id = '$RW'")" completed "the walk-in request is completed"
is "$(code POST /trips/$RT1/void '{"reason":"Customer called off the trip"}' "$OT")" 200 "the manager voids the app rental"
is "$(sql "SELECT status FROM special_trip_requests WHERE request_id = '$R1'")" cancelled "its request is cancelled"
is "$(notes "$PT" trip_update "$RT1")" 2 "and the passenger is told"

printf '\n%d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
