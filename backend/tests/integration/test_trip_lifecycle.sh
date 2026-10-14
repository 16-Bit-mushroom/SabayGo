#!/usr/bin/env bash
# Rev 468 step 4: the trip lifecycle (change brief section 4).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_trip_lifecycle.sh
#
# Needs the backend on :8000 and a database just reset with --soon: the
# two fixture trips depart in 20 minutes, inside the 30-minute start
# window. The brief's acceptance tests are named where they apply (T1..).
# The fallback start is driven by calling the job's tick directly; the
# running server's own tick may get there first, which is the same code.
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
tick() {
  (cd "$BACKEND" && "$PY" -c "
import asyncio
from app.core.db import SessionFactory, engine
from app.application.operations.trip_lifecycle import start_overdue_trips
async def m():
    await start_overdue_trips(SessionFactory)
    await engine.dispose()
asyncio.run(m())" 2>&1 | grep -iE "error|traceback" || true)
}
ping() {
  curl -s -o /dev/null -w "%{http_code}" -X POST "$API/tracking/trips/$1/ping" \
       -H "Content-Type: application/json" -d "{\"latitude\":$2,\"longitude\":$3}"
}

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
hdr "3. Boarding before the start (rule 3, T2)"
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP1\",\"boarding_stop\":1,\"alighting_stop\":4}" "$DT")" 201 \
   "the assigned Dispatcher logs a cash fare on the scheduled trip"
is "$(code GET /trips/$TRIP1/manifest "" "$DT")" 200 "and reads its passenger list"
is "$(field status)" scheduled "the trip is still scheduled"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. Manual start (rules 4, 5; T1, T8, T10, T22)"
is "$(code POST /trips/$TAG6/start "" "$CT")" 409 "start is refused before the window opens"
field detail | grep -q "Start opens at" && ok "and says when it opens" || bad "detail: $(field detail)"
is "$(code POST /trips/$TRIP1/start "" "$DT")" 403 "a Dispatcher cannot start a trip"

code POST /devices '{"device_model":"realme 5G lifecycle"}' "$OT" >/dev/null
PHONE=$(field device_id); PHONE_TOKEN=$(field device_token)
is "$(code POST /devices/$PHONE/checkout '{"van_id":"VAN-0002","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT")" 200 \
   "a phone goes out with van XYZ-9876 and dispatcher@"

is "$(code POST /trips/$TRIP1/start "" "$CT")" 200 "T1 cashier starts the trip with the assigned van"
is "$(field start_mode)" manual "StartMode manual"
is "$(field start_review_status)" not_required "no review needed"
is "$(field audit_status)/$(field unaudited_reason)" unaudited/no_phone "T22 no phone with ABC-1234: Unaudited, No_Phone"
field warnings | grep -q "No phone is checked out with ABC-1234" && ok "the starter is warned" || bad "no warning"
field warnings | grep -q "on XYZ-9876, not ABC-1234" && ok "T10 warned the Dispatcher's phone is on another van" \
  || bad "no van-mismatch warning: $(field warnings)"
is "$(board $TRIP1 started_by_name)" "Joy Alcantara" "StartedBy is the cashier (T19)"
is "$(board $TRIP1 operator_name)/$(board $TRIP1 plate_number)" "Juan Dela Cruz/ABC-1234" \
   "operator name and plate copied onto the trip"
is "$(notes "$OT" unaudited_trip $TRIP1)" 1 "manager alerted: Unaudited Trip"
is "$(notes "$DT" unaudited_trip $TRIP1)" 1 "the Dispatcher too"
is "$(notes "$CT" unaudited_trip $TRIP1)" 0 "the cashier who started it sees it on screen instead"
is "$(code POST /trips/$TRIP1/start "" "$OT")" 409 "a trip starts once"

# The phone is reporting (step 5): a phone that never reported is silent.
curl -s -o /dev/null -X POST "$API/edge/heartbeats" -H "X-Device-Token: $PHONE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"reports\":[{\"recorded_at\":\"$(date '+%Y-%m-%dT%H:%M:%S')\",\"camera_ok\":true,\"gps_ok\":true}]}"
is "$(code POST /trips/$TRIP2/start "" "$OT")" 200 "manager starts the trip whose van has the phone"
is "$(field audit_status)" audited "with its phone out, the trip is Audited"
is "$(field warnings)" "[]" "and nothing to warn about"

code POST /config/trips/special "{\"route_id\":\"$MATI\",\"departure_datetime\":\"$SOON\",\"van_id\":\"VAN-0006\",\"trip_label\":\"Lifecycle S1\"}" "$OT" >/dev/null
S1=$(field trip_id)
is "$(board $S1 van_id)/$(board $S1 dispatcher_id)" "VAN-0006/None" "special trip S1 assigned a van only"
is "$(code POST /trips/$S1/start "" "$CT")" 409 "T8 manual start is blocked with no Dispatcher"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. The fallback start and its review (rules 7, 8; T3, T4, T7, T9)"
sql "UPDATE trips SET departure_datetime = NOW() - INTERVAL 15 MINUTE WHERE trip_id = '$S1'"
tick
is "$(board $S1 status)" boarding "T3 grace passed: the system starts S1"
is "$(board $S1 start_mode)/$(board $S1 started_by_name)" "auto_assigned/None" "Auto_Assigned, StartedBy NULL"
is "$(board $S1 start_review_status)" pending "held for review, off the statement"
is "$(board $S1 dispatcher_id)" None "T9 started with no Dispatcher"
code GET "/notifications?limit=100" "" "$OT" >/dev/null
python3 -c "import json;n=[x for x in json.load(open('/tmp/resp.json'))['items'] if x['type']=='unconfirmed_trip_start' and x['related_entity_id']=='$S1'];assert len(n)==1 and 'No Dispatcher' in n[0]['title']" \
  && ok "'Unconfirmed Trip Start' alert, flagged No Dispatcher" || bad "unconfirmed-start alert missing"

code POST /config/trips/special "{\"route_id\":\"$MATI\",\"departure_datetime\":\"$SOON\",\"trip_label\":\"Lifecycle S2\"}" "$OT" >/dev/null
S2=$(field trip_id)
sql "UPDATE trips SET departure_datetime = NOW() - INTERVAL 15 MINUTE WHERE trip_id = '$S2'"
tick; tick
is "$(board $S2 status)" scheduled "T7 no van assigned: the trip stays open"
is "$(notes "$OT" trip_not_started $S2)" 1 "'Trip Not Started' raised once, not every tick"

is "$(code POST /trips/$S1/start-review "" "$CT")" 403 "the cashier cannot review a start"
is "$(code POST /trips/$S1/start-review '{"van_id":"VAN-0004"}' "$OT")" 409 "changing the van at review needs a reason"
is "$(code POST /trips/$S1/start-review "" "$OT")" 200 "T4 manager confirms the van"
is "$(field start_review_status)" reviewed "Reviewed"
is "$(code POST /trips/$S1/start-review "" "$OT")" 409 "a start is reviewed once"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. Void and change van: the Terminal Manager only (rule 10, T11)"
is "$(code POST /trips/$S1/void '{"reason":"Wrong trip started"}' "$CT")" 403 "T11 the cashier cannot void"
is "$(code POST /trips/$S1/void '{"reason":"Van went out on a rental"}' "$OT")" 200 "manager voids S1"
is "$(field status)" cancelled "Status cancelled"
field change_note | grep -q "Voided: Van went out on a rental (earlier van LCT-9042, operator Nestor Abellana)" \
  && ok "who, when and why kept, with the earlier van and operator" || bad "note: $(field change_note)"
is "$(code POST /trips/$S2/void '{"reason":"No van free"}' "$OT")" 200 "a scheduled trip can be voided too"

is "$(code POST /trips/$TRIP1/change-van '{"van_id":"VAN-0006","reason":"Engine trouble"}' "$CT")" 403 \
   "T11 the cashier cannot change a started trip's van"
is "$(code POST /trips/$TAG6/change-van '{"van_id":"VAN-0006","reason":"x y z"}' "$OT")" 409 \
   "a trip not yet started is changed through its assignment"
is "$(code POST /trips/$TRIP1/change-van '{"van_id":"VAN-0006","reason":"Engine trouble"}' "$OT")" 200 \
   "manager changes the van of the started trip"
is "$(field plate_number)" LCT-9042 "the new plate is on the trip"
field change_note | grep -q "earlier van ABC-1234, operator Juan Dela Cruz" \
  && ok "the earlier van and operator are in the note" || bad "note: $(field change_note)"
is "$(board $TRIP1 operator_name)" "Nestor Abellana" "the new operator is copied"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. Depart and arrive (rule 9, 4.1, T26)"
is "$(code POST /trips/$TRIP1/depart "" "$DT")" 403 "the Dispatcher no longer departs the trip"
is "$(code POST /trips/$TAG6/depart "" "$OT")" 409 "a trip that has not started cannot depart"
is "$(code POST /trips/$TRIP1/depart "" "$CT")" 200 "cashier taps Depart"
is "$(field departure_source)" confirmed "DepartureSource confirmed"
is "$(code POST /trips/$TRIP1/depart "" "$OT")" 409 "a trip departs once"
is "$(code POST /trips/$TRIP1/arrive "" "$D2T")" 403 "another Dispatcher cannot tap Arrived"
is "$(code POST /trips/$TRIP2/arrive "" "$DT")" 409 "a trip still boarding cannot arrive"
is "$(code POST /trips/$TRIP1/arrive "" "$DT")" 200 "T26 the Dispatcher taps Arrived"
is "$(field status)" completed "Completed"
is "$(code POST /trips/$TRIP1/void '{"reason":"too late"}' "$OT")" 409 "a completed trip cannot be voided"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "8. The van's GPS leaves the terminal (rules 7, 9)"
LIVE=TRIP-A2Z-LIVE-SOON    # scheduled in 2 h, VAN-0004, dispatcher5@, nobody aboard
code GET /trips/$LIVE/stops "" "$OT" >/dev/null
read -r LAT LON < <(python3 -c "import json;s=json.load(open('/tmp/resp.json'))[0];print(s['latitude'],s['longitude'])")
FARLAT=$(python3 -c "print($LAT + 0.05)")
ping $LIVE "$LAT" "$LON" >/dev/null; ping $LIVE "$FARLAT" "$LON" >/dev/null
is "$(board $LIVE status)" scheduled "leaving with nobody boarded changes nothing"
is "$(code POST /bookings/walk-in "{\"trip_id\":\"$LIVE\",\"boarding_stop\":1,\"alighting_stop\":2}" "$D5T")" 201 \
   "dispatcher5 logs a fare before anyone started the trip"
ping $LIVE "$LAT" "$LON" >/dev/null
is "$(ping $LIVE "$FARLAT" "$LON")" 201 "the ping itself is accepted"
is "$(board $LIVE start_mode)" auto_assigned "the van leaving starts the trip (Auto_Assigned)"
is "$(board $LIVE start_review_status)" pending "held for review"
is "$(board $LIVE status)/$(board $LIVE departure_source)" departed/detected "and it departs, Detected"

code POST /bookings/walk-in "{\"trip_id\":\"$TRIP2\",\"boarding_stop\":1,\"alighting_stop\":2}" "$DT" >/dev/null
code GET /trips/$TRIP2/stops "" "$OT" >/dev/null
read -r LAT LON < <(python3 -c "import json;s=json.load(open('/tmp/resp.json'))[0];print(s['latitude'],s['longitude'])")
ping $TRIP2 "$LAT" "$LON" >/dev/null; ping $TRIP2 "$(python3 -c "print($LAT + 0.05)")" "$LON" >/dev/null
is "$(board $TRIP2 status)/$(board $TRIP2 departure_source)/$(board $TRIP2 start_mode)" departed/detected/manual \
   "a started trip departs when its van leaves with a boarding counted"

code POST /devices/$PHONE/return '{}' "$OT" >/dev/null

printf '\n%d passed, %d failed\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
