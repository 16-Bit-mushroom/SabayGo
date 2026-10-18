#!/usr/bin/env bash
# Rev 603 R9: driving flags from the phone's GPS readings (change brief
# 6.3-6.4). The rules themselves are replayed on the paper's sample trip
# in tests/test_driving_flags.py; this plays the pipeline end to end.
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_driving_flags.sh
#
# TRIP-DEMO-00000001 (ABC-1234, dispatcher@) is paid, started and departed,
# then dated 45 minutes back with its phone's check-out, so the phone can
# upload a drive along Ecoland -> Digos one reading every 5 s: a burst at
# 90 km/h against 60, a 180 s stop and a 30 s stop away from every stop.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP=TRIP-DEMO-00000001; ROUTE=ROUTE-ECO-COT-0001
STATE=$(mktemp); trap 'rm -f "$STATE"' EXIT
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
field() { j "$1" < /tmp/df.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/df.json -w "%{http_code}" -X "$m" "$API$p")
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
# drive PLAN -> one batch of readings every 5 s along Ecoland -> Digos,
# continuing from the time and distance kept in $STATE. PLAN is JSON:
# [["stand", SECONDS], ["drive", SECONDS, KMH], ...]
drive() {
  python3 - "$STATE" "$1" <<'PY'
import datetime as dt, json, sys
state, plan = sys.argv[1], json.loads(sys.argv[2])
base, t, d = open(state).read().split()
base, t, d = dt.datetime.fromisoformat(base), float(t), float(d)
A, B, L = (7.052400, 125.593100), (6.749500, 125.357200), 42_000.0
fixes = []
for phase in plan:
    kmh = phase[2] if phase[0] == "drive" else 0.0
    for _ in range(int(phase[1] // 5)):
        t += 5
        d += kmh / 3.6 * 5
        f = d / L
        fixes.append({"recorded_at": (base + dt.timedelta(seconds=t)).isoformat(),
                      "latitude": round(A[0] + f * (B[0] - A[0]), 6),
                      "longitude": round(A[1] + f * (B[1] - A[1]), 6), "speed_kph": kmh})
open(state, "w").write(f"{base.isoformat()} {t} {d}")
print(json.dumps({"fixes": fixes}))
PY
}
upload() { curl -s -o /tmp/df.json -w "%{http_code}" -X POST "$API/edge/fixes" -H "X-Device-Token: $PHONE" -H "Content-Type: application/json" -d "$1"; }
flag() {  # flag TYPE FIELDS -> the trip's flags of that type, one line each
  sql "SELECT CONCAT_WS('/', $2) FROM driving_events WHERE trip_id = '$TRIP' AND flag_type = '$1' ORDER BY start_at"
}
notes() {
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/df.json'))['items'] if n['type']=='driving_flag' and n['related_entity_id']=='$TRIP'))"
}

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && ok "signed in" || { bad "login"; exit 1; }

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. A2Z's speed limits, stretch by stretch (brief 6.3)"
code GET /config/routes/$ROUTE/stretches "" "$CT" >/dev/null
is "$(python3 -c "import json;print(len(json.load(open('/tmp/df.json'))))")" 0 "none until the Terminal Manager sets them"
is "$(code PUT /config/routes/$ROUTE/stretches '{"speed_limits_kmh":[60,80,80]}' "$CT")" 403 "the Cashier cannot set them"
is "$(code PUT /config/routes/$ROUTE/stretches '{"speed_limits_kmh":[60,80]}' "$OT")" 422 "one limit for each stretch"
is "$(code PUT /config/routes/$ROUTE/stretches '{"speed_limits_kmh":[60,80,80],"stop_zone_radius_m":100}' "$OT")" 200 \
   "the Terminal Manager sets 60, 80 and 80 km/h, 100 m stop zones"
python3 - <<'PY' && ok "lengths stop to stop, each expected time (length - 2 x 100 m) / 55 km/h" || bad "stretches: $(cat /tmp/df.json)"
import json
s = json.load(open('/tmp/df.json'))
assert [x['stretch_no'] for x in s] == [1, 2, 3] and s[0]['from_stop'] == 'Ecoland Terminal'
assert float(s[1]['from_distance_m']) == float(s[0]['length_m'])
assert s[0]['expected_time_s'] == round((float(s[0]['length_m']) - 200) / (55 / 3.6))
assert [x['speed_limit_kmh'] for x in s] == [60, 80, 80]
PY

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. The trip on the road"
DUE=$(code GET /trips/$TRIP/share "" "$CT" >/dev/null; field "['amount_due']")
[ "$DUE" = "0.00" ] || code POST /trips/$TRIP/payment "{\"amount\":\"$DUE\",\"reference\":\"OR-DF\"}" "$CT" >/dev/null
is "$(code POST /trips/$TRIP/start "" "$CT")" 200 "started"
is "$(code POST /trips/$TRIP/depart "" "$DT")" 200 "and departed"
code POST /devices '{"device_model":"realme flags"}' "$OT" >/dev/null
DEV=$(field "['device_id']"); PHONE=$(field "['device_token']")
code POST /devices/$DEV/checkout '{"van_id":"VAN-0001","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT" >/dev/null
BASE=$(python3 -c "import datetime as d;print((d.datetime.now()-d.timedelta(minutes=45)).replace(microsecond=0).isoformat())")
sql "UPDATE trips SET started_at = '$BASE' - INTERVAL 5 MINUTE, departed_at = '$BASE' WHERE trip_id = '$TRIP'"
sql "UPDATE device_checkouts SET checked_out_at = '$BASE' - INTERVAL 10 MINUTE WHERE device_id = '$DEV'"
echo "$BASE 0 0" > "$STATE"
ok "dated 45 minutes back, with its phone"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Overspeed, and a stop still under way"
is "$(upload "$(drive '[["stand",30],["drive",300,50],["drive",20,90],["drive",120,50],["stand",140]]')")" 200 \
   "the phone uploads its readings"
is "$(field "['recorded']")" 122 "all 122 on the trip"
is "$(flag overspeed "stretch_no, limit_kmh, max_speed_kmh, duration_s")" "1/60.0/90.0/15" \
   "Overspeed: 90 km/h against 60 on the first stretch, 15 s"
is "$(flag unscheduled_stop "IFNULL(end_at, 'open'), duration_s")" "open/135" \
   "Unscheduled stop: past 120 s away from every stop, still under way"
D=$(flag unscheduled_stop "ROUND(distance_from_start_m), ROUND(nearest_stop_dist_m)")
python3 -c "a,b='$D'.split('/');assert 6000<float(a)<6800 and abs(float(a)-float(b))<300" \
  && ok "placed on the route, ${D%%/*} m from the start" || bad "place $D"
is "$(flag en_route_stop "duration_s")" "" "standing in the terminal's zone is no stop"
is "$(notes "$OT")/$(notes "$DT")/$(notes "$CT")" 2/2/0 "the Terminal Manager and the Dispatcher are alerted, not the Cashier"
code GET "/notifications?limit=100" "" "$OT" >/dev/null
python3 -c "import json;m=[n['message'] for n in json.load(open('/tmp/df.json'))['items'] if n['type']=='driving_flag'];assert any('between Ecoland Terminal and Digos City Terminal' in x for x in m) and all('not proof' in x for x in m)" \
  && ok "the alert says where, generally, and that it is for review" || bad "messages"
STOP=$(flag unscheduled_stop "driving_event_id")

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. The stop ends; a short stop is recorded, not flagged"
upload "$(drive '[["stand",40],["drive",120,50],["stand",30],["drive",120,50]]')" >/dev/null
is "$(flag unscheduled_stop "driving_event_id, IF(end_at IS NULL, 'open', 'ended'), duration_s")" "$STOP/ended/180" \
   "the same flag now has its end: 180 s"
is "$(flag en_route_stop "duration_s, IF(end_at IS NULL, 'open', 'ended')")" "30/ended" "En-route stop: 30 s, recorded"
is "$(notes "$OT")" 2 "and neither alerts again"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. A flag no longer found goes, unless someone has looked"
for g in 1 2 3; do
  sql "INSERT INTO driving_events (driving_event_id, trip_id, flag_type, start_at, review_status) VALUES ('FLAG-GHOST-$g', '$TRIP', 'overspeed', '$BASE' + INTERVAL $g SECOND, IF($g = 2, 'reviewed', 'open'))"
done
is "$(code POST /disputes '{"subject":"driving_flag","driving_event_id":"FLAG-GHOST-3","operator_statement":"I was overtaking a truck."}' "$DT")" 201 \
   "the operator disputes one of them"
upload "$(drive '[["drive",60,50]]')" >/dev/null
is "$(sql "SELECT GROUP_CONCAT(driving_event_id ORDER BY driving_event_id) FROM driving_events WHERE driving_event_id LIKE 'FLAG-GHOST-%'")" \
   "FLAG-GHOST-2,FLAG-GHOST-3" "the open one is deleted; the reviewed and the disputed stay"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. Readings uploaded after the trip completed"
is "$(code POST /trips/$TRIP/arrive "" "$DT")" 200 "the Dispatcher taps Arrived"
is "$(upload "$(drive '[["drive",20,95],["drive",30,50]]')")/$(field "['recorded']")" 200/10 \
   "readings from before the arrival, uploaded late, go on the trip"
is "$(flag overspeed "max_speed_kmh" | tail -n 1)" 95.0 "and their overspeed is flagged"
is "$(notes "$OT")" 3 "and alerted"
AFTER=$(python3 -c "import datetime as d,json;print(json.dumps({'fixes':[{'recorded_at':(d.datetime.now()+d.timedelta(seconds=60)).isoformat(),'latitude':6.9,'longitude':125.5,'speed_kph':50}]}))")
upload "$AFTER" >/dev/null
is "$(field "['recorded']")" 0 "a reading from after the arrival does not"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. The Terminal Manager's list and review (6.4)"
# flags KEYS [QUERY] -> one line per flag of the trip, the keys joined by '/'
flags() {
  code GET "/driving-flags?trip_id=$TRIP${2:-}" "" "$OT" >/dev/null
  python3 -c "
import json, sys
for f in json.load(open('/tmp/df.json')): print('/'.join(str(f[k]) for k in sys.argv[1].split(',')))" "$1"
}
is "$(code GET "/driving-flags?trip_id=$TRIP" "" "$CT")" 200 "the Cashier reads them, to record a dispute"
is "$(python3 -c "import json;print(len(json.load(open('/tmp/df.json'))))")" \
   "$(sql "SELECT COUNT(*) FROM driving_events WHERE trip_id = '$TRIP'")" "every flag of the trip"
is "$(code GET /driving-flags "" "$DT")" 422 "a Dispatcher names the trip"
is "$(code GET "/driving-flags?trip_id=$TRIP" "" "$DT")" 200 "their own trip's"
is "$(code GET /driving-flags "" "$(login passenger)")" 403 "not a passenger"
OP=$(sql "SELECT CONCAT_WS('/', driver_name, driver_license_no, van_plate_number) FROM trips WHERE trip_id = '$TRIP'")
is "$(flags operator_name,operator_licence,plate_number | sort -u)" "$OP" "each names the operator and van copied at the start: $OP"
flags flag_type,stretch_no,place | grep -q "^overspeed/1/between Ecoland Terminal and " \
  && ok "the overspeed is placed on its stretch, generally" || bad "place: $(flags flag_type,stretch_no,place)"
is "$(flags flag_type,flagged | grep en_route_stop | sort -u)" "en_route_stop/False" "the en-route stop is listed as recorded, not flagged"
is "$(flags driving_event_id,dispute_status | grep FLAG-GHOST-3)" "FLAG-GHOST-3/open" "the disputed flag shows its dispute"

OVER=$(flag overspeed "driving_event_id" | grep -v FLAG-GHOST | head -n 1)
ENR=$(flag en_route_stop "driving_event_id")
is "$(code POST /driving-flags/$STOP/review '{"status":"reviewed"}' "$CT")" 403 "the Cashier cannot review"
is "$(code POST /driving-flags/FLAG-GHOST-3/review '{"status":"dismissed","note":"x"}' "$OT")" 409 \
   "a disputed flag is reviewed by deciding its dispute"
is "$(code POST /driving-flags/$ENR/review '{"status":"reviewed"}' "$OT")" 409 "an en-route stop has nothing to review"
is "$(code POST /driving-flags/$OVER/review '{"status":"dismissed"}' "$OT")" 422 "dismissing needs a reason"
is "$(code POST /driving-flags/$STOP/review '{"status":"reviewed","note":"Called the operator."}' "$OT")" 200 \
   "the Terminal Manager marks the stop reviewed"
is "$(field "['review_status']")/$(field "['reviewed_by']")/$(field "['review_note']")" "reviewed/Maria Santos/Called the operator." \
   "with who and the note"
[ "$(field "['reviewed_at']")" != None ] && ok "and when" || bad "reviewed_at"
is "$(code POST /driving-flags/$STOP/review '{"status":"dismissed","note":"changed my mind"}' "$OT")" 409 \
   "a reviewed flag is not reviewed again"
is "$(code POST /driving-flags/$OVER/review '{"status":"dismissed","note":"Ambulance behind, gave way."}' "$OT")" 200 \
   "an overspeed dismissed, with the reason"
is "$(flags driving_event_id "\&status=open" | grep -cE "^($STOP|$OVER)$")" 0 "neither is open any more"
upload "$(drive '[["drive",5,50]]')" >/dev/null
is "$(sql "SELECT COUNT(*) FROM driving_events WHERE driving_event_id IN ('$STOP', '$OVER')")" 2 "and new readings delete neither"

DIS=$(sql "SELECT dispute_id FROM disputes WHERE driving_event_id = 'FLAG-GHOST-3' AND status = 'open'")
code POST /disputes/$DIS/decide '{"outcome":"rejected","note":"No truck in the readings."}' "$OT" >/dev/null
is "$(flags driving_event_id,review_status,reviewed_by,review_note | grep FLAG-GHOST-3)" \
   "FLAG-GHOST-3/reviewed/Maria Santos/Dispute rejected: No truck in the readings." \
   "deciding the dispute reviews the flag, with who and why"
is "$(flags driving_event_id "\&date=$(date -d yesterday +%F)" | wc -l)" 0 "by service date: none yesterday"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
