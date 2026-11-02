#!/usr/bin/env bash
# Terminal fees and the operator's share (brief rev 721, item 13 and
# 2.1; the sample trip of 12.1; T1, T64-T69).
#
#   ./tests/integration/test_terminal_fees.sh
#
# Beside the 15 %, A2Z's trip ticket carries a P75 DCOTT ticket for each
# trip and a P50 parking fee for each van each service day. The three
# are the terminal fees, handed to the Cashier before Start; the rest of
# the cash on the list is the operator's share, handed to the operator in
# the same step. The Cashier records both.
#
# The sample trip, on Ecoland - Sta. Cruz - Digos: 11 booked seats to
# Digos at P110 and 2 to Sta. Cruz at P80 (B = P1,370), one walk-up to
# Sta. Cruz at P80 (W = P80). The brief counts one of the 11 as a home
# pickup; it is booked income either way, and test_home_pickup.sh covers
# the pickup itself.
#
#   remittance      0.15 x 1,450.00          = P217.50
#   terminal fees   217.50 + 75.00 + 50.00   = P342.50
#   operator share  1,450.00 - 342.50        = P1,107.50
#
# Needs: ./db/reset-dev.sh --soon, and the backend running. The script
# voids the two fixture trips, so that the sample is XYZ-9876's first
# trip of the day and ABC-1234 has no trip at all (T65).
set -uo pipefail
cd "$(dirname "$0")/../.."

API="http://127.0.0.1:8000/api/v1"
ROUTE="ROUTE-ECO-DIG-0001"     # 1 Ecoland, 2 Sta. Cruz, 3 Digos
VAN="VAN-0002"; PLATE="XYZ-9876"
IDLE="VAN-0001"                 # ABC-1234: parked, no trip
STAMP=$(date +%s)
PASS_N=0; FAIL_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1', wanted '$2')"; }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}
login() { code POST /auth/login "{\"email\":\"$1\",\"password\":\"sabaygo123\"}" >/dev/null
          j "['access_token']" < /tmp/resp.json; }
field() { j "['$1']" < /tmp/resp.json; }

# The van's statement for the trip's day, one field of it.
stmt() {
  code GET "/statements?date=$DAY" "" "$CT" >/dev/null
  python3 -c "import json;print({s['plate_number']:s for s in json.load(open('/tmp/resp.json'))}['${2:-$PLATE}']['$1'])"
}
share() { code GET "/trips/$1/share" "" "$CT" >/dev/null; field "$2"; }
board() {
  code GET "/config/trips?date=$DAY" "" "$OT" >/dev/null
  python3 -c "import json;print({t['trip_id']:t for t in json.load(open('/tmp/resp.json'))}['$1']['$2'])"
}
pay() {  # TRIP AMOUNT [OPERATOR_SHARE]
  code POST "/trips/$1/payment" \
    "{\"amount\":\"$2\",\"reference\":\"OR-$RANDOM\"${3:+,\"operator_share\":\"$3\"}}" "$CT"
}
reserve_paid() {  # TRIP ALIGHTING_STOP COUNT: reserved in the app, marked Paid
  local i bid
  for i in $(seq 1 "$3"); do
    code POST /bookings/reserve \
      "{\"trip_id\":\"$1\",\"boarding_stop\":1,\"alighting_stop\":$2}" "$PT" >/dev/null
    bid=$(field booking_id)
    [ "$(code POST "/bookings/$bid/mark-paid" '{}' "$DT")" = "200" ] || return 1
  done
}
walk_up() { code POST /bookings/walk-in \
              "{\"trip_id\":\"$1\",\"boarding_stop\":1,\"alighting_stop\":$2}" "$DT"; }
new_trip() {  # MINUTES_FROM_NOW -> $TRIP_ID
  code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
    \"departure_datetime\":\"$(date -d "+$1 minutes" '+%Y-%m-%dT%H:%M:00')\",
    \"trip_label\":\"Terminal fees $STAMP\"}" "$OT" >/dev/null
  TRIP_ID=$(field trip_id)
}

curl -sf http://127.0.0.1:8000/health >/dev/null || { echo "API not running"; exit 1; }

# ═══════════════════════════════════════════════ 0. setup
hdr "0. Accounts, fares, and the sample trip"
OT=$(login manager@sabaygo.dev); CT=$(login cashier@sabaygo.dev)
[ -n "$OT" ] && [ -n "$CT" ] && ok "manager@ and cashier@ signed in" || { bad "login failed"; exit 1; }
code POST /auth/register "{\"email\":\"fees${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0918${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"first_name\":\"Sample\",\"last_name\":\"Rider\"}" >/dev/null
PT=$(field access_token)
[ -n "$PT" ] && ok "a passenger registered" || { bad "register failed"; exit 1; }

# The brief's sample fares. The fixture's Sta. Cruz fare is P70; a fare
# dated today replaces it for today's trips.
is "$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":1,\"to_stop_sequence\":2,\"fare_amount\":\"80.00\"}]}" "$OT")" 201 \
   "Sta. Cruz at P80 from today, Digos stays P110"
is "$(code POST /trips/TRIP-DEMO-00000002/void '{"reason":"Fixture: frees XYZ-9876"}' "$OT")/$(
      code POST /trips/TRIP-DEMO-00000001/void '{"reason":"Fixture: frees ABC-1234"}' "$OT")" \
   200/200 "the fixture trips are voided: XYZ-9876 and ABC-1234 have no trip today"

new_trip 25; TRIP=$TRIP_ID
[ -n "$TRIP" ] && ok "a departure on Ecoland - Digos in 25 min" || { bad "trip: $(cat /tmp/resp.json)"; exit 1; }
DAY=$(date -d "+25 minutes" +%F)

# Any Dispatcher free for the next two hours; the fixture's are busy at
# different times of day.
DT=""
for n in 3 2 4 5; do
  S=$(code PUT "/trips/$TRIP/assignment" \
        "{\"van_id\":\"$VAN\",\"dispatcher_id\":\"USER-DISPATCHER-000$n\"}" "$OT")
  if [ "$S" = "200" ]; then DT=$(login "dispatcher$n@sabaygo.dev"); DISP=$n; break; fi
done
[ -n "$DT" ] && ok "$PLATE and dispatcher$DISP@ assigned at the van's turn" \
  || { bad "no Dispatcher could be assigned: $(cat /tmp/resp.json)"; exit 1; }

# ═══════════════════════════════════════════════ the list
hdr "12.1  the sample trip's list"
reserve_paid "$TRIP" 3 11 && ok "11 seats to Digos reserved in the app and marked Paid" \
  || bad "a Digos seat: $(cat /tmp/resp.json)"
reserve_paid "$TRIP" 2 2 && ok "2 seats to Sta. Cruz reserved and marked Paid" \
  || bad "a Sta. Cruz seat: $(cat /tmp/resp.json)"
is "$(walk_up "$TRIP" 2)" 201 "one walk-up to Sta. Cruz, paid in cash as it is listed"

is "$(stmt booked_income)/$(stmt walk_up_income)" 1370.00/80.00 "B = P1,370.00, W = P80.00"
is "$(stmt remittance_owed)" 217.50 "remittance owed = 0.15 x 1,450.00 = P217.50"
is "$(stmt dcott_fees)/$(stmt parking_fee)" 75.00/50.00 \
   "the van's first trip of the day: one P75 DCOTT ticket and the day's P50 parking"
is "$(stmt terminal_fees_owed)" 342.50 "terminal fees = 217.50 + 75.00 + 50.00 = P342.50"
is "$(stmt operator_share_owed)" 1107.50 "operator's share = 1,450.00 - 342.50 = P1,107.50"
is "$(share "$TRIP" amount_due)/$(field operator_share_owed)" 342.50/1107.50 \
   "the trip's share screen: P342.50 to the Cashier, P1,107.50 to the operator"
is "$(stmt operator_share_difference)" None "no share flag while the list is still open"
is "$(code POST /trips/$TRIP/start "" "$CT")" 409 "Start is blocked until the fees are recorded"
field detail | grep -q "terminal fees" && ok "and says the terminal fees are due" \
  || bad "block wording: $(field detail)"

# ═══════════════════════════════════════════════ T1, T67
hdr "T1 T67  the Cashier records the fees and the operator's share in one step"
is "$(pay "$TRIP" 342.50 1107.50)" 200 "P342.50 and P1,107.50 recorded"
is "$(field payment_status)/$(field amount_due)" paid/0.00 "PaymentStatus 'Paid', nothing due"
[ "$(field list_locked_at)" != "None" ] && ok "ListLockedAt set" || bad "list not locked"
is "$(stmt settled_amount)/$(stmt operator_share_given)" 342.50/1107.50 \
   "SettledAmount = 342.50, OperatorShareGiven = 1,107.50"
[ "$(stmt operator_share_given_at)" != "None" ] && [ "$(stmt operator_share_recorded_by_name)" != "None" ] \
  && ok "OperatorShareGivenAt and OperatorShareRecordedBy set" || bad "who and when not recorded"
[ "$(stmt recorded_by_name)" != "None" ] && [ "$(stmt handed_over_by_name)" != "None" ] \
  && ok "RecordedBy (the Cashier) and HandedOverBy (the Dispatcher) set" || bad "handover not recorded"
is "$(stmt operator_share_differs)/$(stmt operator_share_difference)" False/0.00 "no flag"
is "$(stmt status)" settled "the statement is settled"
is "$(code POST /trips/$TRIP/start "" "$CT")" 200 "the Cashier taps Start"
is "$(field start_mode)/$(field start_review_status)" manual/not_required \
   "StartMode 'Manual', StartReviewStatus 'Not_Required'"
is "$(board "$TRIP" plate_number)" "$PLATE" "the plate is copied onto the trip"
is "$(code POST /trips/$TRIP/depart "" "$DT")/$(code POST /trips/$TRIP/arrive "" "$DT")" 200/200 \
   "the van departs and arrives"
is "$(stmt terminal_fees_owed)" 342.50 "T8 a paid seat counts whether or not its passenger came"

# ═══════════════════════════════════════════════ T64, T66, T68, T69
hdr "T64  the same van's second trip that day"
new_trip 28; TRIP2=$TRIP_ID
is "$(code PUT "/trips/$TRIP2/assignment" \
       "{\"van_id\":\"$VAN\",\"dispatcher_id\":\"USER-DISPATCHER-000$DISP\"}" "$OT")" 200 \
   "assigned: its last trip is paid"
reserve_paid "$TRIP2" 3 2 && ok "2 seats to Digos marked Paid (P220.00, 15 % P33.00)" \
  || bad "seat: $(cat /tmp/resp.json)"
is "$(stmt dcott_fees)/$(stmt parking_fee)" 150.00/50.00 \
   "a P75 DCOTT ticket for each trip (P150.00), the P50 parking once"
is "$(share "$TRIP2" amount_due)" 108.00 "due before Start: the 15 % and the second ticket, P108.00"
is "$(field operator_share_owed)" 1219.50 "the day's operator's share: 1,670.00 - 450.50"

hdr "T66  the 15 % recorded, the DCOTT ticket not"
is "$(pay "$TRIP2" 33.00)" 200 "the Cashier records P33.00"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 409 "Start is blocked: all the terminal fees are due"
field detail | grep -q "₱75.00 of terminal fees" && ok "with P75.00 still due" \
  || bad "block: $(field detail)"

hdr "T68  the operator gets less than the share owed"
is "$(pay "$TRIP2" 75.00 100.00)" 200 "the P75 is recorded, with an operator's share of P100.00"
is "$(stmt operator_share_differs)/$(stmt operator_share_difference)" True/12.00 \
   "every list is locked: 'Operator share differs', P12.00 short (P112.00 owed for this trip)"
is "$(stmt amount_due)" 0.00 "the flag is not money owed to A2Z"
SID=$(stmt remittance_id)
is "$(code POST /statements/$SID/operator-share '{"amount":"12.00"}' "$OT")" 403 \
   "the Terminal Manager does not record it: the Cashier does"
is "$(code POST /statements/$SID/operator-share '{"amount":"12.00"}' "$CT")" 200 \
   "the Cashier records the P12.00 handed over"
is "$(field operator_share_differs)/$(field operator_share_given)" False/1219.50 "the flag clears"

hdr "T69  a walk-up added after the payment, before Start"
is "$(walk_up "$TRIP2" 2)" 201 "a P80 walk-up to Sta. Cruz is listed"
is "$(share "$TRIP2" amount_due)/$(field payment_status)" 12.00/unpaid "a P12.00 top-up, and the trip is unpaid again"
python3 -c "import json;l=json.load(open('/tmp/resp.json'))['lines'];assert any(x['is_top_up'] and x['gross_fare']=='80.00' and x['share_amount']=='12.00' for x in l)" \
  && ok "the top-up line: P80.00, share P12.00" || bad "lines: $(cat /tmp/resp.json)"
is "$(field operator_share_owed)" 1287.50 "P68.00 more is the operator's"
is "$(stmt dcott_fees)/$(stmt parking_fee)" 150.00/50.00 "the P75 and the P50 do not repeat"
is "$(stmt operator_share_difference)" 68.00 "the operator's P68.00 is not handed over yet"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 409 "the top-up blocks Start"
is "$(pay "$TRIP2" 12.00 68.00)" 200 "the Cashier records P12.00 and the operator's P68.00"
is "$(stmt settled_amount)/$(stmt operator_share_differs)" 462.50/False \
   "settled 342.50 + 33.00 + 75.00 + 12.00, and no flag"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 200 "Start"

# ═══════════════════════════════════════════════ T65
hdr "T65  a van parked at the terminal with no trip"
is "$(code POST /statements/parking "{\"van_id\":\"$IDLE\"}" "$OT")" 403 \
   "the Terminal Manager does not record the charge: the Cashier does"
is "$(code POST /statements/parking "{\"van_id\":\"$IDLE\",\"service_date\":\"$(date -d tomorrow +%F)\"}" "$CT")" 409 \
   "not for a day still to come"
is "$(code POST /statements/parking '{"van_id":"VAN-NOPE"}' "$CT")" 404 "not for a van that does not exist"
is "$(code POST /statements/parking "{\"van_id\":\"$IDLE\",\"service_date\":\"$(date +%F)\"}" "$CT")" 201 \
   "the Cashier records a parking-only charge"
PSID=$(field remittance_id)
is "$(field parking_fee)/$(field terminal_fees_owed)/$(field dcott_fees)" 50.00/50.00/0.00 \
   "ParkingFee = 50.00, the only amount on it"
is "$(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))['lines']))")/$(field operator_share_owed)" \
   0/0.00 "no trip, no fare line, OperatorShareOwed = 0.00"
is "$(field status)/$(field amount_due)" open/50.00 "open, P50.00 due"
is "$(code POST /statements/parking "{\"van_id\":\"$IDLE\",\"service_date\":\"$(date +%F)\"}" "$CT")" 409 \
   "the parking is charged once a day"
new_trip 40; TRIP3=$TRIP_ID
is "$(code PUT "/trips/$TRIP3/assignment" "{\"van_id\":\"$IDLE\"}" "$OT")" 409 \
   "unpaid, it refuses the van's next assignment [ASSUMED]"
field detail | grep -q "₱50.00 of terminal fees" && ok "the block names the P50" || bad "block: $(field detail)"
is "$(code POST /statements/$PSID/payments '{"amount":"50.00","reference":"OR-PARK"}' "$CT")" 200 \
   "the Cashier records the P50"
is "$(field status)/$(field amount_due)" settled/0.00 "settled once the P50 is recorded"
is "$(code PUT "/trips/$TRIP3/assignment" "{\"van_id\":\"$IDLE\"}" "$OT")" 200 "and the van can be assigned"

# ═══════════════════════════════════════════════ settings
hdr "Settings"
code GET /config/policies "" "$OT" >/dev/null
is "$(python3 -c "import json;p={x['policy_key']:x['policy_value'] for x in json.load(open('/tmp/resp.json'))};print(p.get('dcott_ticket_fee'),p.get('parking_fee'))")" \
   "75.00 50.00" "dcott_ticket_fee 75.00 and parking_fee 50.00, both settings"

echo
printf '\033[1m%s passed, %s failed\033[0m\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
