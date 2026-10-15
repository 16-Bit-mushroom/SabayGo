#!/usr/bin/env bash
# Rev 603 R3: the trip lifecycle and the 15 % before Start (change brief
# sections 2.1 and 4, acceptance tests T1-T21).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_trip_lifecycle.sh
#
# Needs the backend on :8000 and a database just reset with --soon: the
# two fixture trips depart in 20 minutes, inside the 30-minute start
# window. The brief's acceptance tests are named where they apply (T1..).
# The fallback start is called directly in section 6; the GPS departure
# that drives it in service is section 9.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$BACKEND/venv/bin/python"
PASS_N=0; FAIL_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  j "['access_token']" < /tmp/resp.json
}
field() { j "['$1']" < /tmp/resp.json; }
# One trip's row on the office board: board TRIP_ID FIELD [DATE]
board() {
  code GET "/config/trips${3:+?date=$3}" "" "$OT" >/dev/null
  python3 -c "import json;print({t['trip_id']:t for t in json.load(open('/tmp/resp.json'))}['$1']['$2'])"
}
# Notifications of TYPE about TRIP_ID in TOKEN's list
notes() {
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/resp.json'))['items'] if n['type']=='$2' and n['related_entity_id']=='$3'))"
}
sql() {
  (cd "$BACKEND" && "$PY" -c "
import asyncio, sys
from sqlalchemy import text
from app.core.db import engine
async def m():
    async with engine.begin() as c:
        await c.execute(text(sys.argv[1]))
    await engine.dispose()
asyncio.run(m())" "$1")
}
fallback() {
  (cd "$BACKEND" && "$PY" -c "
import asyncio, sys
from app.core.db import SessionFactory, engine
from app.application.operations.trip_lifecycle import TripLifecycle
async def m():
    async with SessionFactory() as s:
        await TripLifecycle(s).fall_back_start(sys.argv[1], why='the van left the terminal')
    await engine.dispose()
asyncio.run(m())" "$1" 2>&1 | grep -iE "error|traceback" || true)
}
ping() {
  curl -s -o /dev/null -w "%{http_code}" -X POST "$API/tracking/trips/$1/ping" \
       -H "Content-Type: application/json" -d "{\"latitude\":$2,\"longitude\":$3}"
}
# The trip's share: share TRIP_ID FIELD
share() { code GET "/trips/$1/share" "" "$CT" >/dev/null; field "$2"; }
# Today's statement of a van: stmt PLATE FIELD
stmt() {
  code GET /statements "" "$CT" >/dev/null
  python3 -c "import json;print({s['plate_number']:s for s in json.load(open('/tmp/resp.json'))}['$1']['$2'])"
}
pay() { code POST "/trips/$1/payment" "{\"amount\":\"$2\",\"reference\":\"OR-$RANDOM\"}" "${3:-$CT}"; }
walkin() { code POST /bookings/walk-in "{\"trip_id\":\"$1\",\"boarding_stop\":1,\"alighting_stop\":${3:-4}}" "${2:-$DT}"; }

STAMP=$(date +%s)
OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher)
D2T=$(login dispatcher2); D5T=$(login dispatcher5)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$D5T" ] \
  && ok "manager, cashier and dispatchers signed in" || { bad "login"; exit 1; }

TRIP1=TRIP-DEMO-00000001   # VAN-0001 ABC-1234, dispatcher@, +20 min
TRIP2=TRIP-DEMO-00000002   # VAN-0002 XYZ-9876, dispatcher@, +20 min
TOMORROW=$(date -d tomorrow +%F)
TAG6=TRIP-A2Z-TAG-D1-0600; TAG9=TRIP-A2Z-TAG-D1-0900; DIG630=TRIP-A2Z-DIG-D1-0630
code GET /config/routes "" "$OT" >/dev/null
MATI=$(python3 -c "import json;print([r['route_id'] for r in json.load(open('/tmp/resp.json')) if 'Mati' in r['route_name']][0])")
SOON=$(date -d '+20 min' '+%Y-%m-%dT%H:%M:00')

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. The timetable creates trips with no crew (rule 1)"
code GET /config/schedule-templates "" "$OT" >/dev/null
python3 -c "import json;t=json.load(open('/tmp/resp.json'));assert t and all('default_van_id' not in x for x in t)" \
  && ok "templates carry route, time and days only" || bad "template still has a usual van"
FAR=$(date -d '+5 days' +%F)
is "$(code POST "/config/trips/generate?service_date=$FAR&days_ahead=1" "" "$OT")" 200 "manager generates trips days ahead"
code GET "/config/trips?date=$FAR" "" "$OT" >/dev/null
python3 -c "import json;t=json.load(open('/tmp/resp.json'));assert t and all(x['van_id'] is None and x['dispatcher_id'] is None for x in t)" \
  && ok "every generated trip waits with no van and no Dispatcher" || bad "generated trip came staffed"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Assignment at the van's turn (rule 2, T24)"
is "$(code PUT /trips/$TAG6/assignment '{"van_id":"VAN-0003","dispatcher_id":"USER-DISPATCHER-0002"}' "$DT")" 403 \
   "a Dispatcher cannot assign"
is "$(code PUT /trips/$TAG6/assignment '{"van_id":"VAN-0007"}' "$OT")" 409 \
   "a van that is not validated cannot be picked (rule 6)"
code PATCH /fleet/crew/USER-DISPATCHER-0005/validation '{"validation_status":"suspended"}' "$OT" >/dev/null
is "$(code PUT /trips/$TAG9/assignment '{"van_id":"VAN-0004","dispatcher_id":"USER-DISPATCHER-0005"}' "$OT")" 409 \
   "nor a Dispatcher who is not validated"
code PATCH /fleet/crew/USER-DISPATCHER-0005/validation '{"validation_status":"validated"}' "$OT" >/dev/null
is "$(code PUT /trips/$TAG6/assignment '{"van_id":"VAN-0003","dispatcher_id":"USER-DISPATCHER-0002"}' "$OT")" 200 \
   "manager assigns a validated van and Dispatcher"
is "$(board $TAG6 assigned_by_name $TOMORROW)" "Maria Santos" "the board names who assigned"
is "$(notes "$OT" assignment_by_cashier $TAG6)" 0 "the manager's own assignment raises no alert"
is "$(code PUT /trips/$DIG630/assignment '{"van_id":"VAN-0003"}' "$OT")" 409 \
   "a van already on an overlapping trip is refused"
is "$(code PUT /trips/$TAG9/assignment '{"van_id":"VAN-0004","dispatcher_id":"USER-DISPATCHER-0005"}' "$CT")" 200 \
   "T24 the cashier's assignment always works"
is "$(board $TAG9 assigned_by_name $TOMORROW)" "Joy Alcantara" "AssignedBy is the cashier"
is "$(notes "$OT" assignment_by_cashier $TAG9)" 1 "the manager gets 'Assignment by Cashier'"
is "$(code PUT /trips/$DIG630/assignment '{"dispatcher_id":"USER-DISPATCHER-0002"}' "$OT")" 409 \
   "nor a Dispatcher already on an overlapping trip"
is "$(code PUT /trips/$TAG9/assignment '{}' "$OT")" 409 "an empty assignment is refused"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. The list is built before the start (rule 3, T2)"
PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"lc${STAMP}@sabaygo.dev\",\"phone_number\":\"0918${STAMP: -7}\",
       \"password\":\"sabaygo123\",\"first_name\":\"Life\",\"last_name\":\"Cycle\"}" | j "['access_token']")
code POST /bookings/reserve "{\"trip_id\":\"$TRIP1\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
KEEP=$(field booking_id)
(cd "$BACKEND" && "$PY" tests/integration/simulate_webhook.py --booking-id "$KEEP" >/dev/null 2>&1)
code POST /bookings/reserve "{\"trip_id\":\"$TRIP1\",\"boarding_stop\":1,\"alighting_stop\":3}" "$PT" >/dev/null
DROP=$(field booking_id)
(cd "$BACKEND" && "$PY" tests/integration/simulate_webhook.py --booking-id "$DROP" >/dev/null 2>&1)
is "$(walkin $TRIP1)" 201 "the assigned Dispatcher lists a cash passenger on the scheduled trip"
is "$(code GET /trips/$TRIP1/manifest "" "$DT")" 200 "and reads its passenger list"
is "$(field status)" scheduled "the trip is still scheduled"
is "$(code GET /trips/$TRIP1/share "" "$D2T")" 403 "another Dispatcher cannot read its share"
code GET /trips/$TRIP1/share "" "$DT" >/dev/null
python3 -c "import json;s=json.load(open('/tmp/resp.json'));g={l['income_group'] for l in s['lines']};assert g=={'verified','declared'} and s['amount_due']!='0.00'" \
  && ok "the share has a verified (QR) and a declared (cash) line" || bad "share: $(cat /tmp/resp.json)"
DUE_ALL=$(share $TRIP1 amount_due)
is "$(code POST /bookings/$DROP/cancel "" "$PT")" 200 "T6a a cancellation before the payment is accepted"
DUE=$(share $TRIP1 amount_due)
python3 -c "assert float('$DUE') < float('$DUE_ALL')" && ok "and takes its share off the amount due (P$DUE_ALL -> P$DUE)" \
  || bad "due did not fall: $DUE_ALL -> $DUE"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. The 15 % before Start (brief 2.1, T1, T3, T6, T7)"
is "$(code POST /trips/$TAG6/start "" "$CT")" 409 "start is refused before the window opens"
field detail | grep -q "Start opens at" && ok "and says when it opens" || bad "detail: $(field detail)"
is "$(code POST /trips/$TRIP1/start "" "$DT")" 403 "a Dispatcher cannot start a trip"
is "$(code POST /trips/$TRIP1/start "" "$CT")" 409 "T3 Start is blocked until the share is recorded"
field detail | grep -q "is due" && ok "and says what is due" || bad "detail: $(field detail)"
is "$(pay $TRIP1 "$DUE" "$OT")" 403 "the Terminal Manager does not record payments (separation of duties)"
is "$(pay $TRIP1 "$DUE" "$DT")" 403 "nor does the Dispatcher"
is "$(pay $TRIP1 9999.00)" 409 "more than is due is refused"
is "$(pay $TRIP1 "$DUE")" 200 "T1 the cashier records the share the Dispatcher handed over"
is "$(field payment_status)/$(field amount_due)" paid/0.00 "PaymentStatus paid, nothing due"
[ "$(field list_locked_at)" != "None" ] && ok "ListLockedAt set" || bad "list not locked"
is "$(stmt ABC-1234 recorded_by)/$(stmt ABC-1234 handed_over_by)" USER-CASHIER-0001/USER-DISPATCHER-0001 \
   "RecordedBy the cashier, HandedOverBy the Dispatcher"
is "$(code POST /bookings/$KEEP/cancel "" "$PT")" 422 "T6b after the payment the list is locked: no cancellation"
is "$(walkin $TRIP1 "$DT" 2)" 201 "T7 a cash passenger is added after the payment"
TOPUP=$(share $TRIP1 amount_due)
code GET /trips/$TRIP1/share "" "$CT" >/dev/null
python3 -c "import json;s=json.load(open('/tmp/resp.json'));t=[l for l in s['lines'] if l['is_top_up']];assert len(t)==1 and t[0]['share_amount']=='$TOPUP' and s['payment_status']=='unpaid'" \
  && ok "a top-up line of P$TOPUP, and the trip is unpaid again" || bad "top-up: $(cat /tmp/resp.json)"
is "$(code POST /trips/$TRIP1/start "" "$CT")" 409 "Start stays blocked until the top-up is recorded"
is "$(pay $TRIP1 "$TOPUP")" 200 "the cashier records the top-up"

code POST /devices '{"device_model":"realme 5G lifecycle"}' "$OT" >/dev/null
PHONE=$(field device_id); PHONE_TOKEN=$(field device_token)
is "$(code POST /devices/$PHONE/checkout '{"van_id":"VAN-0002","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT")" 200 \
   "a phone goes out with van XYZ-9876 and dispatcher@"

is "$(code POST /trips/$TRIP1/start "" "$CT")" 200 "T1 cashier starts the trip with the assigned van"
is "$(field start_mode)" manual "StartMode manual"
is "$(field start_review_status)" not_required "no review needed"
is "$(field audit_status)/$(field unaudited_reason)" unaudited/no_phone "T19 no phone with ABC-1234: Unaudited, No_Phone"
field warnings | grep -q "No phone is checked out with ABC-1234" && ok "the starter is warned" || bad "no warning"
field warnings | grep -q "on XYZ-9876, not ABC-1234" && ok "T20 warned the Dispatcher's phone is on another van" \
  || bad "no van-mismatch warning: $(field warnings)"
is "$(board $TRIP1 started_by_name)" "Joy Alcantara" "StartedBy is the cashier"
is "$(board $TRIP1 operator_name)/$(board $TRIP1 plate_number)" "Juan Dela Cruz/ABC-1234" \
   "operator name and plate copied onto the trip"
is "$(notes "$OT" unaudited_trip $TRIP1)" 1 "manager alerted: Unaudited Trip"
is "$(notes "$DT" unaudited_trip $TRIP1)" 1 "the Dispatcher too"
is "$(notes "$CT" unaudited_trip $TRIP1)" 0 "the cashier who started it sees it on screen instead"
is "$(code POST /trips/$TRIP1/start "" "$OT")" 409 "a trip starts once"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. The Terminal Manager's override (brief 2.1, T3)"
is "$(walkin $TRIP2)" 201 "a cash passenger is listed on the second trip"
is "$(code POST /trips/$TRIP2/start "" "$OT")" 409 "nothing recorded: even the manager's Start is blocked"
is "$(code POST /trips/$TRIP2/payment-override '{"note":"Cashier away, operator pays at noon"}' "$CT")" 403 \
   "the cashier cannot override"
is "$(code POST /trips/$TRIP2/payment-override '{"note":"x"}' "$OT")" 422 "an override needs a written reason"
is "$(code POST /trips/$TRIP2/payment-override '{"note":"Cashier away, operator pays at noon"}' "$OT")" 200 \
   "the manager overrides with a written reason"
is "$(field payment_status)" overridden "PaymentStatus overridden"
is "$(notes "$CT" payment_block_override $TRIP2)" 1 "the cashier is told"
# The phone is reporting (step 5): a phone that never reported is silent.
curl -s -o /dev/null -X POST "$API/edge/heartbeats" -H "X-Device-Token: $PHONE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"reports\":[{\"recorded_at\":\"$(date '+%Y-%m-%dT%H:%M:%S')\",\"camera_ok\":true,\"gps_ok\":true}]}"
is "$(code POST /trips/$TRIP2/start "" "$CT")" 200 "after the override the cashier starts it"
is "$(field audit_status)" audited "with its phone out, the trip is Audited"
is "$(field warnings)" "[]" "and nothing to warn about"

code POST /config/trips/special "{\"route_id\":\"$MATI\",\"departure_datetime\":\"$SOON\",\"van_id\":\"VAN-0006\",\"trip_label\":\"Lifecycle S1\"}" "$OT" >/dev/null
S1=$(field trip_id)
is "$(board $S1 van_id)/$(board $S1 dispatcher_id)" "VAN-0006/None" "special trip S1 assigned a van only"
is "$(code POST /trips/$S1/start "" "$CT")" 409 "T4 manual start is blocked with no Dispatcher"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. The automatic start and its review (rules 9, 11; T14, T16)"
fallback $S1
is "$(board $S1 status)" boarding "T14 the van left: the system starts S1"
is "$(board $S1 start_mode)/$(board $S1 started_by_name)" "auto_assigned/None" "Auto_Assigned, StartedBy NULL"
is "$(board $S1 start_review_status)" pending "held for review, off the statement"
is "$(board $S1 dispatcher_id)" None "started with no Dispatcher"
code GET "/notifications?limit=100" "" "$OT" >/dev/null
python3 -c "import json;n=[x for x in json.load(open('/tmp/resp.json'))['items'] if x['type']=='unconfirmed_trip_start' and x['related_entity_id']=='$S1'];assert len(n)==1 and 'No Dispatcher' in n[0]['title']" \
  && ok "'Unconfirmed Trip Start' alert, flagged No Dispatcher" || bad "unconfirmed-start alert missing"

code POST /config/trips/special "{\"route_id\":\"$MATI\",\"departure_datetime\":\"$SOON\",\"trip_label\":\"Lifecycle S2\"}" "$OT" >/dev/null
S2=$(field trip_id)
fallback $S2; fallback $S2
is "$(board $S2 status)" scheduled "no van assigned: the trip stays open"
is "$(notes "$OT" trip_not_started $S2)" 1 "'Trip Not Started' raised once, not every time"

is "$(code POST /trips/$S1/start-review "" "$CT")" 403 "the cashier cannot review a start"
is "$(code POST /trips/$S1/start-review '{"van_id":"VAN-0004"}' "$OT")" 409 "changing the van at review needs a reason"
is "$(code POST /trips/$S1/start-review "" "$OT")" 200 "manager confirms the van"
is "$(field start_review_status)" reviewed "Reviewed"
is "$(code POST /trips/$S1/start-review "" "$OT")" 409 "a start is reviewed once"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. Void and change van: the Terminal Manager only (rule 12, T21)"
is "$(code POST /trips/$S1/void '{"reason":"Wrong trip started"}' "$CT")" 403 "T21 the cashier cannot void"
is "$(code POST /trips/$S1/void '{"reason":"Van went out on a rental"}' "$OT")" 200 "manager voids S1"
is "$(field status)" cancelled "Status cancelled"
field change_note | grep -q "Voided: Van went out on a rental (earlier van LCT-9042, operator Nestor Abellana)" \
  && ok "who, when and why kept, with the earlier van and operator" || bad "note: $(field change_note)"
is "$(code POST /trips/$S2/void '{"reason":"No van free"}' "$OT")" 200 "a scheduled trip can be voided too"

is "$(code POST /trips/$TRIP1/change-van '{"van_id":"VAN-0006","reason":"Engine trouble"}' "$CT")" 403 \
   "T21 the cashier cannot change a started trip's van"
is "$(code POST /trips/$TAG6/change-van '{"van_id":"VAN-0006","reason":"x y z"}' "$OT")" 409 \
   "a trip not yet started is changed through its assignment"
is "$(code POST /trips/$TRIP1/change-van '{"van_id":"VAN-0006","reason":"Engine trouble"}' "$OT")" 200 \
   "manager changes the van of the started trip"
is "$(field plate_number)" LCT-9042 "the new plate is on the trip"
field change_note | grep -q "earlier van ABC-1234, operator Juan Dela Cruz" \
  && ok "the earlier van and operator are in the note" || bad "note: $(field change_note)"
is "$(board $TRIP1 operator_name)" "Nestor Abellana" "the new operator is copied"
is "$(stmt LCT-9042 amount_due)" "$(python3 -c "print(f'{float("$DUE")+float("$TOPUP"):.2f}')")"    "its fare lines move to the new van's statement; the payment stays where it was recorded"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "8. Depart, the assignment block, arrive (rules 2, 7; T5, T12)"
is "$(code PUT /trips/TRIP-A2Z-LIVE-BOARD/crew '{"aboard":true}' "$D2T")" 409 "only the assigned Dispatcher is crew"
is "$(code PUT /trips/TRIP-A2Z-LIVE-BOARD/crew '{"aboard":true}' "$DT")" 200 "T26 the Dispatcher adds themselves as crew"
is "$(field crew_aboard)" True "CrewAboard set"
is "$(code POST /trips/$TRIP1/depart "" "$D2T")" 403 "another Dispatcher cannot tap Depart"
is "$(code POST /trips/$TAG6/depart "" "$OT")" 409 "a trip that has not started cannot depart"
is "$(code POST /trips/$TRIP1/depart "" "$DT")" 200 "T12 the Dispatcher taps Depart"
is "$(field departure_source)" dispatcher "DepartureSource dispatcher"
is "$(code POST /trips/$TRIP1/depart "" "$OT")" 409 "a trip departs once"
is "$(code POST /trips/$TRIP2/depart "" "$CT")" 200 "on the other trip the cashier taps it"
is "$(field departure_source)" staff "DepartureSource staff"
is "$(board $TRIP2 payment_status)" overridden "an overridden trip did not leave unpaid"
OWED=$(stmt XYZ-9876 amount_due)
python3 -c "assert float('$OWED') > 0" && ok "its share stays owed on the van's statement (P$OWED)" || bad "nothing owed"
is "$(code PUT /trips/$DIG630/assignment '{"van_id":"VAN-0002"}' "$OT")" 409 \
   "T5 the van with an unpaid trip is refused its next assignment"
field detail | grep -q "still owes" && ok "and the detail says what it owes" || bad "detail: $(field detail)"
is "$(code PUT /trips/$DIG630/assignment '{"van_id":"VAN-0002"}' "$CT")" 409 "the cashier is refused too"
SID=$(stmt XYZ-9876 remittance_id)
is "$(code POST /statements/$SID/payments "{\"amount\":\"$OWED\",\"reference\":\"OR-NOON\"}" "$CT")" 200 \
   "the cashier records the payment on the van's statement"
is "$(field status)/$(field amount_due)" settled/0.00 "the statement is settled"
is "$(code PUT /trips/$DIG630/assignment '{"van_id":"VAN-0002"}' "$OT")" 200 "and the van can be assigned again"
is "$(code POST /trips/$TRIP1/arrive "" "$D2T")" 403 "another Dispatcher cannot tap Arrived"
is "$(code POST /trips/$TRIP1/arrive "" "$DT")" 200 "the Dispatcher taps Arrived"
is "$(field status)" completed "Completed"
is "$(code POST /trips/$TRIP1/void '{"reason":"too late"}' "$OT")" 409 "a completed trip cannot be voided"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "9. GPS departure, Not a passenger trip, Left Unpaid (rules 8-11; T13-T18)"
LIVE=TRIP-A2Z-LIVE-SOON    # VAN-0004, dispatcher5@, two QR seats, nothing recorded
code GET /trips/$LIVE/stops "" "$OT" >/dev/null
read -r LAT LON < <(python3 -c "import json;s=json.load(open('/tmp/resp.json'))[0];print(s['latitude'],s['longitude'])")
FARLAT=$(python3 -c "print($LAT + 0.05)")
out3() { ping $LIVE "$FARLAT" "$LON" >/dev/null; ping $LIVE "$FARLAT" "$LON" >/dev/null; ping $LIVE "$FARLAT" "$LON" >/dev/null; }
ping $LIVE "$LAT" "$LON" >/dev/null; out3
is "$(board $LIVE status)" scheduled "zone radius and N unset: no GPS departure"
code PUT /config/policies/depart_zone_radius_m '{"policy_value":"300"}' "$OT" >/dev/null
code PUT /config/policies/depart_readings '{"policy_value":"3"}' "$OT" >/dev/null
ping $LIVE "$LAT" "$LON" >/dev/null

is "$(walkin $LIVE "$D5T" 2)" 201 "dispatcher5 lists a cash passenger: a boarding is counted"
code POST /devices '{"device_model":"realme 5G lifecycle 2"}' "$OT" >/dev/null
PHONE2=$(field device_id)
code POST /devices/$PHONE2/checkout '{"van_id":"VAN-0004","dispatcher_id":"USER-DISPATCHER-0005"}' "$CT" >/dev/null
is "$(code POST /non-passenger-moves '{"reason":"other"}' "$D5T")" 409 "'Other' needs a note"
is "$(code POST /non-passenger-moves '{"reason":"errand"}' "$D5T")" 201 "T17 dispatcher5 presses Not a passenger trip (Errand)"
MOVE=$(field move_id)
is "$(code POST /non-passenger-moves '{"reason":"errand"}' "$D5T")" 409 "one open move per van"
out3
is "$(board $LIVE status)" scheduled "T17 the van leaves on the errand: nothing starts"
ping $LIVE "$LAT" "$LON" >/dev/null
is "$(code POST /non-passenger-moves/$MOVE/end "" "$D5T")" 409 "back inside the terminal zone, the move has ended"

ping $LIVE "$FARLAT" "$LON" >/dev/null
is "$(board $LIVE status)" scheduled "T13 a single stray reading departs nothing"
ping $LIVE "$FARLAT" "$LON" >/dev/null; ping $LIVE "$FARLAT" "$LON" >/dev/null
is "$(board $LIVE status)/$(board $LIVE departure_source)" departed/gps "N readings outside the zone: departed, GPS"
is "$(board $LIVE start_mode)/$(board $LIVE start_review_status)" auto_assigned/pending \
   "T15 nobody started it: Auto_Assigned, held for review"
is "$(board $LIVE payment_status)" left_unpaid "nothing was recorded: Left_Unpaid"
is "$(notes "$OT" left_unpaid $LIVE)/$(notes "$CT" left_unpaid $LIVE)" 1/1 "'Left Unpaid' to the manager and the cashier"
is "$(stmt NBC-7788 held_share)/$(stmt NBC-7788 remittance_owed)" 33.00/0.00 \
   "the share is held, off the statement: 15 % of P100 + P60 + P60"
is "$(code PUT /trips/$TAG6/assignment '{"van_id":"VAN-0004"}' "$OT")" 409 "the held share still refuses the van's next assignment"
is "$(code POST /trips/$LIVE/start-review "" "$OT")" 200 "T16 the manager reviews it"
is "$(stmt NBC-7788 held_share)/$(stmt NBC-7788 remittance_owed)" 0.00/33.00 "its lines join the statement: held moves into owed"

BOARD=TRIP-A2Z-LIVE-BOARD  # started and paid in the seed, VAN-0003
code GET /trips/$BOARD/stops "" "$OT" >/dev/null
read -r LAT LON < <(python3 -c "import json;s=json.load(open('/tmp/resp.json'))[0];print(s['latitude'],s['longitude'])")
FARLAT=$(python3 -c "print($LAT + 0.05)")
ping $BOARD "$LAT" "$LON" >/dev/null
for _ in 1 2 3; do ping $BOARD "$FARLAT" "$LON" >/dev/null; done
is "$(board $BOARD status)/$(board $BOARD departure_source)/$(board $BOARD start_mode)" departed/gps/manual \
   "a started trip nobody departed departs when its van leaves"
is "$(board $BOARD payment_status)" paid "its share was recorded: not Left_Unpaid"

code PUT /config/policies/depart_zone_radius_m '{"policy_value":""}' "$OT" >/dev/null
code PUT /config/policies/depart_readings '{"policy_value":""}' "$OT" >/dev/null
code POST /devices/$PHONE/return '{}' "$OT" >/dev/null
code POST /devices/$PHONE2/return '{}' "$OT" >/dev/null

printf '\n%d passed, %d failed\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
