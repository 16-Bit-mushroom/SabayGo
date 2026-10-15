#!/usr/bin/env bash
# Rev 603 R7: operator disputes (change brief 2.1, Table 39; T9-T11).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_disputes.sh
#
# Fare lines are made by cash walk-ins on TRIP-DEMO-00000001 and -02
# (ABC-1234 and XYZ-9876, dispatcher@, depart in 20 min). Driving flags
# are written with SQL, since R9 computes them: two on a completed trip
# of dispatcher2@ given one GPS reading, one on a trip with none.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP1=TRIP-DEMO-00000001; TRIP2=TRIP-DEMO-00000002
DONE=TRIP-A2Z-TAG-P1-0600   # completed yesterday, VAN-0003, dispatcher2@
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
field() { j "$1" < /tmp/dp.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/dp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
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
add() { python3 -c "from decimal import Decimal as D;import sys;print(sum((D(x) for x in sys.argv[2:]), D(sys.argv[1])))" "$@"; }
sub() { python3 -c "from decimal import Decimal as D;import sys;print(D(sys.argv[1])-D(sys.argv[2]))" "$1" "$2"; }
share() { code GET "/trips/$1/share" "" "$CT" >/dev/null; field "['$2']"; }
stmt() {  # stmt PLATE FIELD [DATE]
  code GET "/statements${3:+?date=$3}" "" "$CT" >/dev/null
  python3 -c "import json;print({s['plate_number']:s for s in json.load(open('/tmp/dp.json'))}['$1']['$2'])"
}
pay() { code POST "/trips/$1/payment" "{\"amount\":\"$2\",\"reference\":\"OR-$RANDOM\"}" "$CT"; }
walkin() { code POST /bookings/walk-in "{\"trip_id\":\"$1\",\"boarding_stop\":1,\"alighting_stop\":$2}" "$DT"; }
lines() { code GET "/trips/$1/share" "" "$CT" >/dev/null; python3 -c "import json;print(' '.join(l['line_id'] for l in json.load(open('/tmp/dp.json'))['lines']))"; }
newline() {  # newline TRIP "IDS BEFORE" -> the one new line in NL, its share NS, seats NC
  code GET "/trips/$1/share" "" "$CT" >/dev/null
  read -r NL NS NC < <(python3 -c "import json,sys;old=set(sys.argv[1].split());n=[l for l in json.load(open('/tmp/dp.json'))['lines'] if l['line_id'] not in old];print(*((n[0]['line_id'],n[0]['share_amount'],n[0]['passenger_count']) if len(n)==1 else ('-','-',len(n))))" "$2")
}
dispute() {  # dispute TOKEN SUBJECT ITEM WORDS
  local key=line_id; [ "$2" = driving_flag ] && key=driving_event_id
  code POST /disputes "{\"subject\":\"$2\",\"$key\":\"$3\",\"operator_statement\":\"$4\"}" "$1"
}
decide() {  # decide TOKEN DISPUTE OUTCOME NOTE [ADJUSTED]
  code POST "/disputes/$2/decide" "{\"outcome\":\"$3\",\"note\":\"$4\"${5:+,\"adjusted_amount\":\"$5\"}}" "$1"
}
notes() {
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/dp.json'))['items'] if n['type']=='$2' and n['related_entity_id']=='$3'))"
}
count() { python3 -c "import json;print(len(json.load(open('/tmp/dp.json'))))"; }

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); D2T=$(login dispatcher2)
PT=$(login passenger)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$D2T" ] && [ -n "$PT" ] \
  && ok "manager, cashier, dispatchers and passenger signed in" || { bad "login"; exit 1; }

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. The operator disputes a fare line at the counter (T9)"
BEFORE=$(lines $TRIP1)
is "$(walkin $TRIP1 2)" 201 "the Dispatcher lists a cash passenger to stop 2"
newline $TRIP1 "$BEFORE"; A=$NL; SA=$NS
DUE0=$(share $TRIP1 amount_due)
is "$(dispute "$D2T" fare_line "$A" "Not mine")" 403 "another trip's Dispatcher cannot record it"
is "$(dispute "$PT" fare_line "$A" "Not mine")" 403 "nor a passenger"
is "$(code POST /disputes '{"subject":"fare_line","operator_statement":"x"}' "$CT")" 422 \
   "a fare-line dispute names its line"
is "$(dispute "$CT" fare_line "$A" "   ")" 422 "the operator's own words are required"
is "$(dispute "$DT" fare_line "$A" "That seat was my nephew. He rode free.")" 201 \
   "the trip's Dispatcher records the operator's dispute of the cash seat"
DA=$(field "['dispute_id']")
is "$(field "['subject']")/$(field "['amount_disputed']")/$(field "['status']")/$(field "['raised_by_role']")" \
   "fare_line/$SA/open/dispatcher" "Fare_Line, AmountDisputed = the line's share (P$SA), open, by the Dispatcher"
is "$(dispute "$CT" fare_line "$A" "Again")" 409 "one line carries one dispute"
is "$(share $TRIP1 disputed)/$(field "['amount_due']")" "$SA/$(sub "$DUE0" "$SA")" \
   "the disputed share is shown apart and left out of the amount due"
is "$(notes "$OT" dispute_raised $TRIP1)" 1 "the Terminal Manager is alerted: Dispute Raised"

BEFORE=$(lines $TRIP1)
is "$(walkin $TRIP1 2)" 201 "a second cash passenger to stop 2"
newline $TRIP1 "$BEFORE"
is "$NC" 1 "goes on a line of its own"
is "$(sql "SELECT passenger_count FROM remittance_lines WHERE line_id = '$A'")" 1 \
   "the contested line stays as it was contested"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. The undisputed part is paid; the line is closed to disputes (T9, T11)"
DUE=$(share $TRIP1 amount_due)
is "$(pay $TRIP1 "$DUE")" 200 "T9 the operator pays the undisputed part (P$DUE)"
is "$(field "['payment_status']")/$(field "['amount_due']")/$(field "['disputed']")" "paid/0.00/$SA" \
   "paid, nothing due, P$SA waits"
OTHER=$(python3 -c "import json;print([l['line_id'] for l in json.load(open('/tmp/dp.json'))['lines'] if l['line_id']!='$A'][0])")
is "$(dispute "$CT" fare_line "$OTHER" "Wrong fare")" 409 "T11 a line cannot be disputed after the payment is recorded"
field "['detail']" | grep -q "not after" && ok "and the Cashier is told why" || bad "detail: $(field "['detail']")"
BEFORE=$(lines $TRIP1)
is "$(walkin $TRIP1 3)" 201 "a cash passenger is added after the payment"
newline $TRIP1 "$BEFORE"; T=$NL; ST=$NS
is "$(sql "SELECT is_top_up FROM remittance_lines WHERE line_id = '$T'")" 1 "as a top-up line"
is "$(dispute "$CT" fare_line "$T" "He is a barker. He paid nothing.")" 201 \
   "a top-up can be disputed until it is paid"
DT1=$(field "['dispute_id']")
is "$(field "['raised_by_role']")" cashier "raised by the Cashier"
is "$(share $TRIP1 amount_due)" 0.00 "so nothing is due"
is "$(code POST /trips/$TRIP1/start "" "$CT")" 200 \
   "T9 Start is allowed: the block checks the undisputed amount only"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Only the Terminal Manager decides (T9 a, b)"
is "$(decide "$CT" "$DA" upheld "ok")" 403 "a Cashier who tries to decide is refused"
is "$(decide "$DT" "$DA" upheld "ok")" 403 "so is a Dispatcher"
is "$(decide "$OT" "$DA" upheld "  ")" 422 "a decision needs its reason"
is "$(decide "$OT" "$DA" upheld "ok" 1.00)" 422 "only an adjusted decision sets an amount"
OWED=$(stmt ABC-1234 remittance_owed); DECL=$(stmt ABC-1234 declared_income)
GA=$(sql "SELECT gross_fare FROM remittance_lines WHERE line_id = '$A'")
is "$(decide "$OT" "$DA" upheld "The nephew rides free, as A2Z agreed.")" 200 "T9 a the Terminal Manager upholds it"
is "$(field "['status']")/$(field "['outcome']")/$(field "['decided_by']")/$(field "['decision_note']")" \
   "resolved/upheld/USER-MANAGER-0001/The nephew rides free, as A2Z agreed." "DecidedBy and DecisionNote stored"
[ "$(field "['decided_at']")" != "None" ] && ok "and DecidedAt" || bad "no decided_at"
is "$(stmt ABC-1234 remittance_owed)/$(stmt ABC-1234 declared_income)" \
   "$(sub "$OWED" "$SA")/$(sub "$DECL" "$GA")" "the line leaves the amount owed, and its fare the declared income"
is "$(decide "$OT" "$DA" rejected "Changed my mind")" 409 "a decision is final"
is "$(decide "$OT" "$DT1" rejected "Your own Dispatcher listed him.")" 200 "T9 b the top-up dispute is rejected"
is "$(share $TRIP1 amount_due)/$(field "['payment_status']")" "$ST/unpaid" \
   "its share becomes due, and the trip is unpaid again"
is "$(pay $TRIP1 "$ST")" 200 "the Cashier records it"
is "$(stmt ABC-1234 status)/$(stmt ABC-1234 amount_due)/$(stmt ABC-1234 disputed)" settled/0.00/0.00 \
   "the statement is settled"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. Adjusted and withdrawn (T9 c)"
BEFORE=$(lines $TRIP2)
walkin $TRIP2 2 >/dev/null; newline $TRIP2 "$BEFORE"; B=$NL; SB=$NS; BEFORE="$BEFORE $B"
walkin $TRIP2 3 >/dev/null; newline $TRIP2 "$BEFORE"; C=$NL; SC=$NS; BEFORE="$BEFORE $C"
walkin $TRIP2 4 >/dev/null; newline $TRIP2 "$BEFORE"; W=$NL; SW=$NS
[ "$B" != - ] && [ "$C" != - ] && [ "$W" != - ] && ok "three cash lines on XYZ-9876's trip" || bad "lines $B $C $W"
TOTAL=$(share $TRIP2 amount_due)
dispute "$CT" fare_line "$B" "That fare was for a child." >/dev/null; DB=$(field "['dispute_id']")
dispute "$OT" fare_line "$C" "He got off early, at the market." >/dev/null; DC=$(field "['dispute_id']")
is "$(field "['raised_by_role']")" terminal_manager "the Terminal Manager records one too"
dispute "$DT" fare_line "$W" "No such passenger." >/dev/null; DW=$(field "['dispute_id']")
is "$(share $TRIP2 disputed)" "$(add "$SB" "$SC" "$SW")" "three shares wait"
is "$(code POST /disputes/$DW/withdraw '{"note":"The operator found the receipt."}' "$D2T")" 403 \
   "another trip's Dispatcher cannot withdraw it"
is "$(code POST /disputes/$DW/withdraw '{"note":"The operator found the receipt."}' "$DT")" 200 \
   "the operator withdraws one"
is "$(field "['status']")/$(field "['outcome']")/$(field "['decided_by']")" withdrawn/None/USER-DISPATCHER-0001 \
   "Withdrawn, no outcome, who recorded it"
is "$(share $TRIP2 amount_due)" "$(sub "$TOTAL" "$(add "$SB" "$SC")")" "its share is due again"
is "$(decide "$OT" "$DW" upheld "ok")" 409 "a withdrawn dispute is not decided"
is "$(dispute "$CT" fare_line "$W" "Second thoughts.")" 201 "a withdrawn dispute does not block a new one"
DW2=$(field "['dispute_id']")
is "$(code POST /disputes/$DW2/withdraw '{}' "$CT")" 200 "and the Cashier records its withdrawal"
HALF=$(python3 -c "from decimal import Decimal as D;print((D('$SC')/2).quantize(D('0.01')))")
is "$(decide "$OT" "$DC" adjusted "Half fare to the market." "$(add "$SC" 0.01)")" 422 \
   "an adjusted share above the disputed one is refused"
is "$(decide "$OT" "$DC" adjusted "Half fare to the market.")" 422 "an adjusted decision names the share due"
OWED=$(stmt XYZ-9876 remittance_owed); DECL=$(stmt XYZ-9876 declared_income)
is "$(decide "$OT" "$DC" adjusted "Half fare to the market." "$HALF")" 200 "T9 c adjusted"
is "$(field "['outcome']")/$(field "['adjusted_amount']")" "adjusted/$HALF" "AdjustedAmount stored"
is "$(stmt XYZ-9876 remittance_owed)/$(stmt XYZ-9876 declared_income)" "$(sub "$OWED" "$(sub "$SC" "$HALF")")/$DECL" \
   "the share due is the adjusted amount; the fares stay"
is "$(decide "$OT" "$DB" rejected "A child pays full fare on this route.")" 200 "the child's fare is rejected"
DUE=$(share $TRIP2 amount_due)
is "$DUE" "$(add "$(sub "$TOTAL" "$SC")" "$HALF")" "due: everything but the adjusted part"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 409 "Start waits for it"
is "$(pay $TRIP2 "$DUE")" 200 "the Cashier records it"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 200 "and Start is allowed"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. A driving flag, after the trip (T10)"
YDAY=$(sql "SELECT service_date FROM trips WHERE trip_id = '$DONE'")
sql "INSERT INTO trip_location_pings (trip_id, van_id, latitude, longitude, recorded_at) SELECT trip_id, van_id, 7.0731, 125.6128, departure_datetime FROM trips WHERE trip_id = '$DONE'"
for n in 1 2; do
  sql "INSERT INTO driving_events (driving_event_id, trip_id, flag_type, start_at, end_at, duration_s) SELECT 'FLAG-DSP-$n', trip_id, 'unscheduled_stop', departure_datetime + INTERVAL 20 MINUTE, departure_datetime + INTERVAL 24 MINUTE, 240 FROM trips WHERE trip_id = '$DONE'"
done
sql "INSERT INTO driving_events (driving_event_id, trip_id, flag_type, start_at, max_speed_kmh, limit_kmh) SELECT 'FLAG-DSP-3', trip_id, 'overspeed', departure_datetime, 92.0, 80.0 FROM trips WHERE trip_id = '$TRIP1'"
is "$(dispute "$DT" driving_flag FLAG-DSP-1 "A child ran across.")" 403 "only that trip's Dispatcher records it"
is "$(code POST /disputes "{\"subject\":\"driving_flag\",\"line_id\":\"$A\",\"driving_event_id\":\"FLAG-DSP-1\",\"operator_statement\":\"x\"}" "$CT")" 422 \
   "a dispute names one item"
is "$(dispute "$D2T" driving_flag FLAG-DSP-1 "A child ran across the road at Toril.")" 201 \
   "T10 the operator disputes a driving flag after the trip"
DF1=$(field "['dispute_id']")
is "$(field "['subject']")/$(field "['amount_disputed']")" driving_flag/0.00 \
   "Driving_Flag, AmountDisputed 0.00"
is "$(sql "SELECT CONCAT_WS('/', r.van_id, r.service_date) FROM disputes d JOIN remittances r ON r.remittance_id = d.remittance_id WHERE d.dispute_id = '$DF1'")" \
   "VAN-0003/$YDAY" "on the van's statement for that day"
is "$(sql "SELECT CONCAT_WS('/', status, remittance_owed - settled_amount) FROM remittances r WHERE van_id = 'VAN-0003' AND service_date = '$YDAY'")" \
   "settled/0.00" "nothing is withheld: the statement stays settled"
is "$(dispute "$CT" driving_flag FLAG-DSP-1 "Again")" 409 "one flag carries one dispute"
is "$(decide "$OT" "$DF1" adjusted "Half" 0.00)" 409 "a driving flag cannot be adjusted"
is "$(decide "$D2T" "$DF1" upheld "ok")" 403 "the Dispatcher cannot decide it"
is "$(decide "$OT" "$DF1" upheld "Stopping for a child is safe driving.")" 200 "the Terminal Manager upholds it"
is "$(sql "SELECT review_status FROM driving_events WHERE driving_event_id = 'FLAG-DSP-1'")" dismissed \
   "the flag is dismissed"
is "$(dispute "$CT" driving_flag FLAG-DSP-2 "I was waiting for my cousin.")" 201 "the Cashier records another"
DF2=$(field "['dispute_id']")
is "$(decide "$OT" "$DF2" rejected "A stop for a relative is not a passenger stop.")" 200 "it is rejected"
is "$(sql "SELECT review_status FROM driving_events WHERE driving_event_id = 'FLAG-DSP-2'")" reviewed \
   "the flag stands, reviewed"
is "$(dispute "$DT" driving_flag FLAG-DSP-3 "I was not speeding.")" 409 \
   "a flag whose trip has no GPS readings kept cannot be disputed"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. Reading disputes"
is "$(code GET "/disputes?trip_id=$TRIP1" "" "$DT")" 200 "the Dispatcher lists their trip's disputes"
is "$(count)" 2 "both of them"
is "$(code GET /disputes "" "$DT")" 422 "a Dispatcher names the trip"
is "$(code GET "/disputes?trip_id=$TRIP1" "" "$D2T")" 403 "not another Dispatcher's trip"
code GET "/disputes?trip_id=$TRIP2&status=withdrawn" "" "$OT" >/dev/null
is "$(count)" 2 "the office filters by trip and status"
code GET "/disputes?status=open" "" "$CT" >/dev/null
is "$(count)" 0 "nothing is left open"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
