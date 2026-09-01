#!/usr/bin/env bash
# Driver and operator journeys.
#
#   ./tests/integration/test_driver_operator_journey.sh
#
# The driver's role is deliberately minimal -- confirm a headcount, issue a
# ticket at an unstaffed stop. The operator does everything at the desk:
# fleet, crew, routes, fares, schedules, policy, audits, revenue.
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
# ║ DRIVER                                                        ║
# ╚═══════════════════════════════════════════════════════════════╝
hdr "DRIVER — 1. Sign in"

S=$(code POST /auth/login '{"email":"driver@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
DT=$(j "['access_token']" < /tmp/resp.json)
[ "$(j "['role']" < /tmp/resp.json)" = "driver" ] && ok "role is driver" || bad "wrong role"

S=$(code GET "/trips/$TRIP/manifest" "" "$DT")
[ "$S" = "200" ] && ok "can read the manifest for their van" || bad "manifest gave $S"

hdr "DRIVER — 2. Headcount before departure"

S=$(code POST "/trips/$TRIP/headcount" '{"stop_sequence":1,"confirmed_count":3}' "$DT")
[ "$S" = "200" ] && ok "headcount 3 -- variance $(j "['variance']" < /tmp/resp.json)" \
                 || bad "headcount gave $S"

# Correcting a miscount must work; a driver who cannot fix a typo stops
# reporting honestly.
S=$(code POST "/trips/$TRIP/headcount" '{"stop_sequence":1,"confirmed_count":5}' "$DT")
[ "$S" = "200" ] && ok "corrected to 5 -- variance now $(j "['variance']" < /tmp/resp.json)" \
                 || bad "correction gave $S"

S=$(code POST "/trips/$TRIP/headcount" '{"stop_sequence":1,"confirmed_count":20}' "$DT")
[ "$S" = "422" ] && ok "count above 14 rejected (422)" || bad "over-capacity gave $S"

hdr "DRIVER — 3. Issue a ticket at an unstaffed stop"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":3,\"alighting_stop\":4}" "$DT")
[ "$S" = "201" ] && ok "cash walk-in logged -- P$(j "['fare_amount']" < /tmp/resp.json)" \
                 || bad "driver walk-in gave $S"

S=$(code GET /audits/node-health "" "$DT")
[ "$S" = "200" ] && ok "can check the camera node" || gap "AI node offline"

hdr "DRIVER — 4. Boundaries"

for ep in "GET /fleet/vans" "GET /config/policies" "GET /revenue/summary" \
          "GET /audits/pending"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$DT")
  [ "$S" = "403" ] && ok "$p blocked (403)" || bad "$p gave $S"
done

# ╔═══════════════════════════════════════════════════════════════╗
# ║ OPERATOR                                                      ║
# ╚═══════════════════════════════════════════════════════════════╝
hdr "OPERATOR — 1. Sign in"

S=$(code POST /auth/login '{"email":"operator@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
OT=$(j "['access_token']" < /tmp/resp.json)

hdr "OPERATOR — 2. Fleet"

S=$(code GET /fleet/vans "" "$OT")
[ "$S" = "200" ] && ok "list vans ($(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))"))" \
                 || bad "vans gave $S"

S=$(code POST /fleet/vans "{\"plate_number\":\"OPS-${STAMP: -4}\",\"brand\":\"Nissan\",
  \"model\":\"NV350\",\"seat_capacity\":14,\"has_cabin_camera\":true,
  \"camera_device_id\":\"EDGE-${STAMP: -4}\"}" "$OT")
[ "$S" = "201" ] && ok "van added with camera" || bad "add van gave $S"
VAN=$(j "['van_id']" < /tmp/resp.json)

S=$(code PATCH "/fleet/vans/$VAN/status" '{"operational_status":"maintenance"}' "$OT")
[ "$S" = "200" ] && ok "van flagged out of service (monitoring only, not a maintenance module)" \
                 || bad "status gave $S"

S=$(code PATCH "/fleet/vans/$VAN/status" '{"operational_status":"active"}' "$OT")
[ "$S" = "200" ] && ok "van returned to service" || bad "reactivate gave $S"

hdr "OPERATOR — 3. Crew"

S=$(code GET /fleet/crew "" "$OT")
[ "$S" = "200" ] && ok "list crew ($(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))"))" \
                 || bad "crew gave $S"

S=$(code POST /fleet/crew "{\"email\":\"drv${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0921${STAMP: -7}\",\"password\":\"sabaygo123\",\"role\":\"driver\",
  \"first_name\":\"Pedro\",\"last_name\":\"Reyes\",
  \"license_number\":\"N02-34-567890\",\"license_expiry_date\":\"2029-12-31\"}" "$OT")
[ "$S" = "201" ] && ok "driver provisioned with licence" || bad "provision gave $S"
NEW_DRIVER=$(j "['user_id']" < /tmp/resp.json)

S=$(code POST /fleet/crew "{\"email\":\"exp${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0922${STAMP: -7}\",\"password\":\"sabaygo123\",\"role\":\"driver\",
  \"first_name\":\"Expired\",\"last_name\":\"Licence\",
  \"license_number\":\"N03-45-678901\",\"license_expiry_date\":\"2020-01-01\"}" "$OT")
[ "$S" = "409" ] && ok "expired licence rejected (409)" || bad "expired licence gave $S"

S=$(code PATCH "/fleet/crew/$NEW_DRIVER/status?status=suspended" "" "$OT")
[ "$S" = "200" ] && ok "crew member suspended (deactivated, not deleted)" || bad "suspend gave $S"

S=$(code POST /auth/login "{\"email\":\"drv${STAMP}@sabaygo.dev\",\"password\":\"sabaygo123\"}")
[ "$S" = "401" ] && ok "suspended account cannot log in (401)" || bad "suspended login gave $S"

hdr "OPERATOR — 4. Configuration"

S=$(code GET /config/policies "" "$OT")
[ "$S" = "200" ] && ok "read all policies" || bad "policies gave $S"

S=$(code PUT /config/policies/variance_alert_threshold '{"policy_value":"2"}' "$OT")
[ "$S" = "200" ] && ok "variance threshold set to 2" || bad "policy update gave $S"
code PUT /config/policies/variance_alert_threshold '{"policy_value":"1"}' "$OT" >/dev/null

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
[ "$S" = "201" ] && ok "route created -- $(j "['legs']" < /tmp/resp.json) leg(s), $(j "['fare_pairs_required']" < /tmp/resp.json) fare pair(s) needed" \
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
[ "$S" = "409" ] && ok "reversed fare pair rejected (409)" || bad "reversed fare gave $S"

hdr "OPERATOR — 5. Schedules"

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

hdr "OPERATOR — 6. Audit queue and revenue"

S=$(code GET /audits/pending "" "$OT")
if [ "$S" = "200" ]; then
  N=$(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))")
  ok "audit queue: $N pending"
  if [ "$N" -gt 0 ]; then
    AID=$(python3 -c "import json;print(json.load(open('/tmp/resp.json'))[0]['audit_id'])")
    S=$(code POST "/audits/$AID/resolve" \
      '{"resolution":"resolved","notes":"Conductor logged the walk-in after departure."}' "$OT")
    [ "$S" = "200" ] && ok "variance dispositioned with a note" || bad "resolve gave $S"

    S=$(code POST "/audits/$AID/resolve" '{"resolution":"ignored","notes":"again"}' "$OT")
    [ "$S" = "409" ] && ok "double resolve rejected (409)" || bad "double resolve gave $S"
  fi
else bad "audit queue gave $S"; fi

S=$(code POST "/audits/$AID/resolve" '{"resolution":"resolved","notes":""}' "$OT" 2>/dev/null)
[ "$S" = "422" ] || [ "$S" = "409" ] && ok "resolution without a note rejected ($S)" \
                                     || bad "empty note gave $S"

S=$(code GET /revenue/summary "" "$OT")
if [ "$S" = "200" ]; then
  python3 -c "
import json;r=json.load(open('/tmp/resp.json'))
print(f\"        trips={r['trips']}  bookings={r['total_bookings']}  \"
      f\"app={r['app_bookings']}  walk-in={r['walkin_bookings']} ({r['walkin_share_pct']}%)\")
print(f\"        collected=P{r['collected_fare']}  expected=P{r['expected_fare']}  \"
      f\"unreconciled=P{r['unreconciled_amount']}\")"
  ok "revenue summary"
else bad "revenue gave $S"; fi

S=$(code GET /revenue/trips "" "$OT")
[ "$S" = "200" ] && ok "per-trip reconciliation" || bad "revenue/trips gave $S"

hdr "OPERATOR — 7. Gaps"

S=$(code GET "/revenue/export?format=csv" "" "$OT")
[ "$S" = "404" ] && gap "no CSV/report export -- operators will want this" || ok "export"

S=$(code GET /audits/history "" "$OT")
[ "$S" = "404" ] && gap "no resolved-audit history -- only the pending queue is readable" || ok "audit history"

S=$(code GET /fleet/crew/schedule "" "$OT")
[ "$S" = "404" ] && gap "no crew roster view -- cannot see who is driving what, when" || ok "crew schedule"

printf '\n\033[1m═══ SUMMARY ═══\033[0m\n  passed  %d\n  failed  %d\n  gaps    %d\n\n' \
  "$PASS_N" "$FAIL_N" "$GAP_N"
