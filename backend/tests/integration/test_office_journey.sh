#!/usr/bin/env bash
# Office journeys: the Cashier and the Terminal Manager.
#
#   ./tests/integration/test_office_journey.sh
#
# The Cashier reads what the counter needs and is refused everything that
# decides what is owed. The Terminal Manager does the rest at the desk:
# fleet, staff, routes, fares, schedules, policy, and the rev 603 money
# and checks pages (statements, Boarding Audit, disputes, driving flags).
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
PASS_N=0; FAIL_N=0; GAP_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
gap() { printf '  \033[33mGAP \033[0m  %s\n' "$1"; GAP_N=$((GAP_N+1)); }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}

# ╔═══════════════════════════════════════════════════════════════╗
# ║ CASHIER                                                       ║
# ╚═══════════════════════════════════════════════════════════════╝
hdr "CASHIER — 1. Sign in"

S=$(code POST /auth/login '{"email":"cashier@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
CT=$(j "['access_token']" < /tmp/resp.json)
[ "$(j "['role']" < /tmp/resp.json)" = "cashier" ] && ok "role is cashier" || bad "wrong role"

hdr "CASHIER — 2. What the counter needs"

for ep in "GET /fleet/vans/board" "GET /fleet/vans" "GET /config/trips" "GET /statements"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$CT")
  [ "$S" = "200" ] && ok "$p readable" || bad "$p gave $S"
done

hdr "CASHIER — 3. Separation of duties"

# The person who records a payment does not decide what is owed, set the
# rules, or validate records (brief 3).
S=$(code PUT /config/policies/cancel_cutoff_hours '{"policy_value":"3"}' "$CT")
[ "$S" = "403" ] && ok "cannot change a rule (403)" || bad "policy edit gave $S"
S=$(code POST /fleet/vans '{"plate_number":"CSH-0001","seat_capacity":14}' "$CT")
[ "$S" = "403" ] && ok "cannot add a van (403)" || bad "add van gave $S"
S=$(code GET /boarding-audit "" "$CT")
[ "$S" = "403" ] && ok "cannot open the Boarding Audit (403)" || bad "boarding audit gave $S"
S=$(code POST /fleet/crew '{}' "$CT")
[ "$S" = "403" ] && ok "cannot create staff accounts (403)" || bad "crew create gave $S"

# ╔═══════════════════════════════════════════════════════════════╗
# ║ TERMINAL MANAGER                                              ║
# ╚═══════════════════════════════════════════════════════════════╝
hdr "TERMINAL MANAGER — 1. Sign in"

S=$(code POST /auth/login '{"email":"manager@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
OT=$(j "['access_token']" < /tmp/resp.json)
[ "$(j "['role']" < /tmp/resp.json)" = "terminal_manager" ] && ok "role is terminal_manager" || bad "wrong role"

hdr "TERMINAL MANAGER — 2. Fleet"

S=$(code GET /fleet/vans "" "$OT")
[ "$S" = "200" ] && ok "list vans ($(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))"))" \
                 || bad "vans gave $S"

# One van per operator: the owner goes on the roster first (rev 468).
S=$(code POST /fleet/operators "{\"full_name\":\"Office Journey Owner\",
  \"contact_number\":\"0928${STAMP: -7}\",\"license_number\":\"Q${STAMP: -10}\",
  \"license_expiry\":\"2029-01-31\"}" "$OT")
[ "$S" = "201" ] && ok "operator added to the roster" || bad "add operator gave $S"
OPERATOR=$(j "['operator_id']" < /tmp/resp.json)

S=$(code POST /fleet/vans "{\"plate_number\":\"OPS-${STAMP: -4}\",\"operator_id\":\"$OPERATOR\",
  \"brand\":\"Nissan\",\"model\":\"NV350\",\"seat_capacity\":14,\"has_cabin_camera\":true,
  \"camera_device_id\":\"EDGE-${STAMP: -4}\"}" "$OT")
[ "$S" = "201" ] && ok "van added with camera and its operator" || bad "add van gave $S"
VAN=$(j "['van_id']" < /tmp/resp.json)

S=$(code PATCH "/fleet/vans/$VAN/status" '{"operational_status":"maintenance"}' "$OT")
[ "$S" = "200" ] && ok "van flagged out of service (monitoring only, not a maintenance module)" \
                 || bad "status gave $S"

S=$(code PATCH "/fleet/vans/$VAN/status" '{"operational_status":"active"}' "$OT")
[ "$S" = "200" ] && ok "van returned to service" || bad "reactivate gave $S"

hdr "TERMINAL MANAGER — 3. Staff"

S=$(code GET /fleet/crew "" "$OT")
[ "$S" = "200" ] && ok "list staff ($(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))"))" \
                 || bad "crew gave $S"

S=$(code POST /fleet/crew "{\"email\":\"dsp${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0921${STAMP: -7}\",\"password\":\"sabaygo123\",\"role\":\"dispatcher\",
  \"first_name\":\"Pedro\",\"last_name\":\"Reyes\"}" "$OT")
[ "$S" = "201" ] && ok "Dispatcher provisioned" || bad "provision gave $S"
NEW_DISPATCHER=$(j "['user_id']" < /tmp/resp.json)

# The operator (van owner) is a roster record, never an account.
S=$(code POST /fleet/crew "{\"email\":\"drv${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0922${STAMP: -7}\",\"password\":\"sabaygo123\",\"role\":\"driver\",
  \"first_name\":\"No\",\"last_name\":\"Login\"}" "$OT")
[ "$S" = "422" ] && ok "driver account refused (422)" || bad "driver account gave $S"

S=$(code PATCH "/fleet/crew/$NEW_DISPATCHER/status?status=suspended" "" "$OT")
[ "$S" = "200" ] && ok "Dispatcher suspended (deactivated, not deleted)" || bad "suspend gave $S"

S=$(code POST /auth/login "{\"email\":\"dsp${STAMP}@sabaygo.dev\",\"password\":\"sabaygo123\"}")
[ "$S" = "401" ] && ok "suspended account cannot log in (401)" || bad "suspended login gave $S"

hdr "TERMINAL MANAGER — 4. Configuration"

S=$(code GET /config/policies "" "$OT")
[ "$S" = "200" ] && ok "read all policies" || bad "policies gave $S"

S=$(code PUT /config/policies/home_pickup_wait_minutes '{"policy_value":"15"}' "$OT")
[ "$S" = "200" ] && ok "home-pickup wait set to 15 min" || bad "policy update gave $S"
code PUT /config/policies/home_pickup_wait_minutes '{"policy_value":"10"}' "$OT" >/dev/null
S=$(code GET /config/policies/home_pickup_wait_minutes/history "" "$CT")
python3 -c "import json;h=json.load(open('/tmp/resp.json'));assert [p['policy_value'] for p in h[:2]]==['10','15'] and h[0]['updated_by_name']=='Maria Santos'" \
  && ok "the history keeps each value, newest first, with who set it (the Cashier may read it)" \
  || bad "policy history gave $S: $(head -c 300 /tmp/resp.json)"

S=$(code PUT /config/policies/does_not_exist '{"policy_value":"x"}' "$OT")
[ "$S" = "404" ] && ok "unknown policy key rejected (404)" || bad "bad key gave $S"

S=$(code POST /config/terminals "{\"terminal_name\":\"Test Terminal ${STAMP: -4}\",
  \"city\":\"Tagum City\",\"latitude\":7.4478,\"longitude\":125.8078,
  \"geofence_radius_m\":180}" "$OT")
[ "$S" = "201" ] && ok "terminal created" || bad "terminal gave $S"
T1=$(j "['terminal_id']" < /tmp/resp.json)

S=$(code POST /config/terminals "{\"terminal_name\":\"Test Terminal B ${STAMP: -4}\",
  \"city\":\"Panabo City\",\"latitude\":7.3081,\"longitude\":125.6839}" "$OT")
T2=$(j "['terminal_id']" < /tmp/resp.json)

S=$(code POST /config/routes "{\"route_code\":\"TST${STAMP: -4}\",
  \"route_name\":\"Test Route\",\"stops\":[
    {\"terminal_id\":\"$T1\",\"stop_sequence\":1,\"offset_minutes\":0},
    {\"terminal_id\":\"$T2\",\"stop_sequence\":2,\"offset_minutes\":60}]}" "$OT")
[ "$S" = "201" ] && ok "route created -- $(j "['legs']" < /tmp/resp.json) leg(s), $(j "['fares_required']" < /tmp/resp.json) fare(s) needed" \
                 || bad "route gave $S"
ROUTE=$(j "['route_id']" < /tmp/resp.json)

S=$(code POST /config/routes "{\"route_code\":\"BAD${STAMP: -4}\",
  \"route_name\":\"Gapped Route\",\"stops\":[
    {\"terminal_id\":\"$T1\",\"stop_sequence\":1},
    {\"terminal_id\":\"$T2\",\"stop_sequence\":3}]}" "$OT")
[ "$S" = "409" ] && ok "non-contiguous stop sequence rejected (409)" || bad "gapped route gave $S"

S=$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":1,\"to_stop_sequence\":2,\"fare_amount\":120.00}]}" "$OT")
[ "$S" = "201" ] && ok "fare matrix set" || bad "fares gave $S"

S=$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":2,\"to_stop_sequence\":1,\"fare_amount\":120.00}]}" "$OT")
{ [ "$S" = "409" ] || [ "$S" = "422" ]; } && ok "reversed fare pair rejected ($S)" || bad "reversed fare gave $S"

S=$(code POST /config/terminals "{\"terminal_name\":\"Test Terminal ${STAMP: -4}\",
  \"city\":\"Tagum City\",\"latitude\":7.4,\"longitude\":125.8}" "$OT")
[ "$S" = "409" ] && ok "same terminal name in the same city refused (409, not a 500)" || bad "duplicate terminal gave $S"

S=$(code PUT "/config/terminals/$T1" "{\"terminal_name\":\"Test Terminal ${STAMP: -4}\",
  \"city\":\"Tagum City\",\"latitude\":7.4478,\"longitude\":125.8078,\"geofence_radius_m\":200,
  \"location_address\":\"Rizal St\",\"is_staffed\":true,\"is_active\":false}" "$OT")
[ "$S" = "409" ] && ok "a terminal on an active route cannot close (409)" || bad "closing T1 gave $S"

S=$(code GET /config/terminals "" "$CT")
python3 -c "
import json;t={x['terminal_id']:x for x in json.load(open('/tmp/resp.json'))}['$T1']
assert t['routes']==['TST${STAMP: -4}'] and t['geofence_radius_m']==180 and t['is_active']" \
  && ok "terminal list carries the routes through it (the Cashier may read it)" \
  || bad "terminal list gave $S: $(head -c 300 /tmp/resp.json)"
S=$(code PUT "/config/terminals/$T1" '{}' "$CT")
[ "$S" = "403" ] && ok "the Cashier cannot edit a terminal (403)" || bad "cashier terminal edit gave $S"

S=$(code GET /config/routes "" "$OT")
python3 -c "
import json;r=[x for x in json.load(open('/tmp/resp.json')) if x['route_id']=='$ROUTE'][0]
assert [(s['stop_sequence'],s['terminal_id'],s['offset_minutes']) for s in r['stops']]==[(1,'$T1',0),(2,'$T2',60)]
assert r['stops'][0]['terminal_name'].startswith('Test Terminal')" \
  && ok "route list carries the stops in order, by name" || bad "route list gave $S: $(head -c 300 /tmp/resp.json)"

S=$(code POST /config/routes "{\"route_code\":\"OFS${STAMP: -4}\",\"route_name\":\"Backwards\",\"stops\":[
    {\"terminal_id\":\"$T1\",\"stop_sequence\":1,\"offset_minutes\":0},
    {\"terminal_id\":\"$T2\",\"stop_sequence\":2,\"offset_minutes\":-5}]}" "$OT")
[ "$S" = "422" ] && ok "a stop reached before departure refused (422)" || bad "negative offset gave $S"

S=$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":1,\"to_stop_sequence\":2,\"fare_amount\":125.00}]}" "$OT")
S2=$(code GET "/config/routes/$ROUTE/fares" "" "$OT")
python3 -c "
import json;f=json.load(open('/tmp/resp.json'))
assert len(f)==1 and float(f[0]['fare_amount'])==125 and f[0]['status']=='in_force'" \
  && ok "the same day's fare saved again corrects it ($S, one row)" || bad "same-day fare gave $S: $(head -c 300 /tmp/resp.json)"

S=$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":1,\"to_stop_sequence\":2,\"fare_amount\":90,\"effective_from\":\"$(date -d yesterday +%F)\"}]}" "$OT")
[ "$S" = "422" ] && ok "a fare dated in the past refused (422)" || bad "backdated fare gave $S"

hdr "TERMINAL MANAGER — 5. Schedules"

S=$(code POST /config/schedule-templates "{\"route_id\":\"$ROUTE\",
  \"departure_time\":\"06:00:00\",\"days_of_week\":\"1111100\",
  \"trip_label\":\"Test Morning\"}" "$OT")
[ "$S" = "201" ] && ok "weekday template created" || bad "template gave $S"

S=$(code POST /config/schedule-templates "{\"route_id\":\"$ROUTE\",
  \"departure_time\":\"06:00:00\",\"days_of_week\":\"11111\"}" "$OT")
[ "$S" = "422" ] && ok "malformed day mask rejected (422)" || bad "bad mask gave $S"

S=$(code POST "/config/trips/generate?days_ahead=3" "" "$OT")
if [ "$S" = "200" ]; then
  python3 -c "
import json
for r in json.load(open('/tmp/resp.json')):
    print(f\"        {r['service_date']}  created={r['trips_created']}  skipped={r['trips_skipped']}\")"
  ok "trips generated"
else bad "generate gave $S"; fi

S=$(code POST "/config/trips/generate?days_ahead=3" "" "$OT")
TOTAL=$(python3 -c "import json;print(sum(r['trips_created'] for r in json.load(open('/tmp/resp.json'))))")
[ "$TOTAL" = "0" ] && ok "re-run is idempotent (created=0)" || bad "re-run created $TOTAL"

S=$(code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
  \"departure_datetime\":\"$(date -d '+2 days 14:00' '+%Y-%m-%dT%H:%M:%S')\",
  \"trip_label\":\"Fiesta Special\"}" "$OT")
[ "$S" = "201" ] && ok "special trip created -- $(j "['seat_legs_created']" < /tmp/resp.json) seat-legs" \
                 || bad "special trip gave $S"

S=$(code POST /config/trips/special "{\"route_id\":\"$ROUTE\",
  \"departure_datetime\":\"2020-01-01T08:00:00\"}" "$OT")
[ "$S" = "409" ] && ok "special trip in the past rejected (409)" || bad "past trip gave $S"

hdr "TERMINAL MANAGER — 5b. Dated fares, a route out of service, a terminal moved"

# A fare set ahead waits for its date: a trip before it keeps today's fare.
D1=$(date -d '+1 day' +%F); D3=$(date -d '+3 days' +%F)
for d in "$D1" "$D3"; do
  code POST /config/trips/special "{\"route_id\":\"$ROUTE\",\"departure_datetime\":\"${d}T15:00:00\",
    \"trip_label\":\"Fare check\"}" "$OT" >/dev/null
done
S=$(code POST /config/fares "{\"route_id\":\"$ROUTE\",\"fares\":[
  {\"from_stop_sequence\":1,\"to_stop_sequence\":2,\"fare_amount\":140,\"effective_from\":\"$D3\"}]}" "$OT")
[ "$S" = "201" ] && ok "fare increase set for $D3" || bad "scheduled fare gave $S"
S=$(code GET "/config/routes/$ROUTE/fares" "" "$OT")
python3 -c "
import json;assert sorted(f['status'] for f in json.load(open('/tmp/resp.json')))==['in_force','scheduled']" \
  && ok "fares list it as scheduled beside the one in force" || bad "fare statuses: $(head -c 300 /tmp/resp.json)"
fare_on() { code GET "/trips/search?origin_terminal_id=$T1&destination_terminal_id=$T2&service_date=$1" "" "$OT" >/dev/null
  python3 -c "import json;print(sorted({float(t['fare_amount']) for t in json.load(open('/tmp/resp.json'))}))"; }
F1=$(fare_on "$D1"); F3=$(fare_on "$D3")
[ "$F1" = "[125.0]" ] && [ "$F3" = "[140.0]" ] && ok "search quotes 125 on $D1 and 140 on $D3" \
  || bad "search fares: $D1 $F1, $D3 $F3"

S=$(code PUT "/config/routes/$ROUTE/stretches" '{"speed_limits_kmh":[60]}' "$OT")
LEN0=$(j "[0]['length_m']" < /tmp/resp.json)
S=$(code PUT "/config/terminals/$T2" "{\"terminal_name\":\"Test Terminal B ${STAMP: -4}\",
  \"city\":\"Panabo City\",\"latitude\":7.3200,\"longitude\":125.6839,\"is_active\":true}" "$OT")
S=$(code GET "/config/routes/$ROUTE/stretches" "" "$OT")
python3 -c "
import json;s=json.load(open('/tmp/resp.json'))[0]
assert float(s['length_m'])!=float('$LEN0') and s['speed_limit_kmh']==60" \
  && ok "moving a terminal re-measures its route's stretch ($LEN0 m -> $(j "[0]['length_m']" < /tmp/resp.json) m), limit kept" \
  || bad "stretch after the move: $(head -c 300 /tmp/resp.json)"

S=$(code PUT "/config/routes/$ROUTE" '{"route_name":"Test Route (old)","ltfrb_case_no":"2026-TEST","is_active":false}' "$OT")
[ "$S" = "200" ] && [ "$(j "['ltfrb_case_no']" < /tmp/resp.json)" = "2026-TEST" ] \
  && ok "route renamed and taken out of service" || bad "route edit gave $S"
S=$(code POST /config/schedule-templates "{\"route_id\":\"$ROUTE\",\"departure_time\":\"07:00:00\"}" "$OT")
[ "$S" = "409" ] && ok "no new timetable entry on a route out of service (409)" || bad "template on inactive route gave $S"
code POST "/config/trips/generate?days_ahead=8" "" "$OT" >/dev/null
S=$(code GET "/config/trips?date=$(date -d '+7 days' +%F)" "" "$OT")
N=$(python3 -c "import json;print(sum(1 for t in json.load(open('/tmp/resp.json')) if t['route_name']=='Test Route (old)'))")
[ "$N" = "0" ] && ok "the timetable generates no trips on it" || bad "$N trips generated on the inactive route"
S=$(code GET "/trips/search?origin_terminal_id=$T1&destination_terminal_id=$T2&service_date=$D1" "" "$OT")
[ "$(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))")" = "0" ] \
  && ok "passengers no longer find it" || bad "search still finds the inactive route"

T1_BODY="{\"terminal_name\":\"Test Terminal ${STAMP: -4}\",\"city\":\"Tagum City\",
  \"latitude\":7.4478,\"longitude\":125.8078,\"geofence_radius_m\":180"
S=$(code PUT "/config/terminals/$T1" "$T1_BODY,\"is_active\":false}" "$OT")
[ "$S" = "200" ] && ok "with its route out of service, the terminal closes" || bad "closing T1 gave $S"
S=$(code PUT "/config/routes/$ROUTE" '{"route_name":"Test Route","is_active":true}' "$OT")
[ "$S" = "409" ] && ok "the route cannot return while a terminal of it is closed (409)" || bad "reactivation gave $S"
code PUT "/config/terminals/$T1" "$T1_BODY,\"is_active\":true}" "$OT" >/dev/null
S=$(code PUT "/config/routes/$ROUTE" '{"route_name":"Test Route","is_active":true}' "$OT")
[ "$S" = "200" ] && ok "terminal reopened, route back in service" || bad "reactivation gave $S"

hdr "TERMINAL MANAGER — 6. Money, checks and who is on what"

# Readable here; each page's rules have their own test script
# (test_trip_lifecycle, test_door_check, test_disputes, test_driving_flags,
# test_van_board).
for ep in "GET /statements?date=$(date -d yesterday +%F)" "GET /boarding-audit?date=$(date +%F)" \
          "GET /disputes" "GET /driving-flags" "GET /fleet/vans/board"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$OT")
  [ "$S" = "200" ] && ok "${p%%\?*} readable" || bad "$p gave $S"
done

# Who is driving what, when: the day's trip board carries each trip's van,
# operator and Dispatcher (the seed assigns today's live trips).
S=$(code GET "/config/trips?date=$(date +%F)" "" "$OT")
CREWED=$(python3 -c "import json;print(sum(1 for t in json.load(open('/tmp/resp.json')) if t['plate_number'] and t['operator_name'] and t['dispatcher_name']))" 2>/dev/null)
[ "$S" = "200" ] && [ "${CREWED:-0}" -ge 1 ] && ok "trip board shows van, operator and Dispatcher ($CREWED trips)" \
                 || bad "trip board gave $S, $CREWED crewed trips"

printf '\n\033[1m═══ SUMMARY ═══\033[0m\n  passed  %d\n  failed  %d\n  gaps    %d\n\n' \
  "$PASS_N" "$FAIL_N" "$GAP_N"
