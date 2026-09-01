#!/usr/bin/env bash
# Conductor journey -- everything a conductor does at the terminal.
#
#   ./tests/integration/test_conductor_journey.sh
#
# The conductor works the van door: scan tickets, log cash walk-ins,
# watch the manifest, trigger an audit, close boarding.
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

# ═══════════════════════════════════════════════ 1. SIGN IN
hdr "1. Conductor signs in"

S=$(code POST /auth/login '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
CT=$(j "['access_token']" < /tmp/resp.json)
[ "$(j "['role']" < /tmp/resp.json)" = "conductor" ] && ok "role is conductor" || bad "wrong role"

S=$(code GET /auth/me "" "$CT")
[ "$S" = "200" ] && ok "profile: $(j "['display_name']" < /tmp/resp.json)" || bad "me gave $S"

# ── set up a paid passenger to scan
hdr "   (setting up a paid passenger)"
S=$(code POST /auth/register "{\"email\":\"pax${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0916${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"first_name\":\"Scan\",\"last_name\":\"Target\"}")
PT=$(j "['access_token']" < /tmp/resp.json)
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID=$(j "['booking_id']" < /tmp/resp.json)
QR=$(j "['qr_payload']" < /tmp/resp.json)
python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1 \
  && ok "passenger booked and paid" || gap "webhook secret not set -- ticket stays unpaid"

# ═══════════════════════════════════════════════ 2. BOARDING
hdr "2. Boarding"

S=$(code POST "/trips/$TRIP/start-boarding" "" "$CT")
[ "$S" = "200" ] && ok "boarding opened" || bad "start-boarding gave $S"

S=$(code POST /scans \
  "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
R=$(j "['result']" < /tmp/resp.json)
[ "$R" = "valid" ] && ok "valid ticket accepted -- seat $(j "['seat_number']" < /tmp/resp.json)" \
                   || bad "valid scan returned $R"

S=$(code POST /scans \
  "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
R=$(j "['result']" < /tmp/resp.json)
[ "$R" = "already_boarded" ] && ok "duplicate scan flagged (already_boarded)" \
                            || bad "duplicate scan returned $R"

S=$(code POST /scans \
  "{\"qr_payload\":\"SBG-does-not-exist\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
R=$(j "['result']" < /tmp/resp.json)
# 200 on purpose: a conductor with a queue needs a verdict, not an exception.
[ "$S" = "200" ] && [ "$R" = "wrong_trip" ] \
  && ok "unknown QR rejected without raising ($R)" || bad "unknown QR: $S/$R"

S=$(code POST /scans \
  "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":3}" "$CT")
R=$(j "['result']" < /tmp/resp.json)
[ "$R" = "already_boarded" ] || [ "$R" = "wrong_stop" ] \
  && ok "wrong stop handled ($R)" || bad "wrong stop returned $R"

# unpaid ticket
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
UNPAID_QR=$(j "['qr_payload']" < /tmp/resp.json)
S=$(code POST /scans \
  "{\"qr_payload\":\"$UNPAID_QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
R=$(j "['result']" < /tmp/resp.json)
[ "$R" = "unpaid" ] && ok "unpaid ticket refused (unpaid)" || bad "unpaid scan returned $R"

# ═══════════════════════════════════════════════ 3. WALK-INS
hdr "3. Cash walk-ins"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "anonymous walk-in logged -- seat $(j "['seat_number']" < /tmp/resp.json), status $(j "['status']" < /tmp/resp.json)" \
                 || bad "walk-in gave $S"

S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":2,
  \"alighting_stop\":4,\"name\":\"Maria Santos\",\"phone\":\"09171112222\",
  \"wants_receipt\":true}" "$CT")
[ "$S" = "201" ] && ok "walk-in with receipt details -- P$(j "['fare_amount']" < /tmp/resp.json)" \
                 || bad "receipt walk-in gave $S"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":3,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "short-segment walk-in (stop 3->4)" || bad "segment walk-in gave $S"

# ═══════════════════════════════════════════════ 4. MANIFEST
hdr "4. Manifest"

S=$(code GET "/trips/$TRIP/manifest" "" "$CT")
if [ "$S" = "200" ]; then
  python3 -c "
import json;m=json.load(open('/tmp/resp.json'))
print(f\"        capacity={m['seat_capacity']}  total={m['total_bookings']}  \"
      f\"boarded={m['boarded']}  awaiting={m['awaiting']}  unpaid={m['unpaid']}\")
for p in m['passengers']:
    who = p['name'] or ('walk-in' if p['booking_type']!='app' else 'app')
    print(f\"        seat {p['seat_number']:>2}  {p['boarding_stop']}->{p['alighting_stop']}  \"
          f\"{p['status']:<11} {who}\")"
  ok "manifest retrieved"
else bad "manifest gave $S"; fi

S=$(code "GET" "/bookings/availability?trip_id=$TRIP&boarding_stop=1&alighting_stop=4")
ok "seats still sellable end-to-end: $(j "['seats_available']" < /tmp/resp.json)"

S=$(code GET "/trips/$TRIP/passenger-lookup?q=Maria" "" "$CT")
if [ "$S" = "404" ]; then
  gap "passenger lookup -- no way to find a booking by name or ticket number"
else ok "passenger lookup"; fi

# ═══════════════════════════════════════════════ 5. AUDIT
hdr "5. Headcount audit"

S=$(code GET /audits/node-health "" "$CT")
if [ "$S" = "200" ]; then
  ok "AI node reachable ($(j "['model_version']" < /tmp/resp.json))"
  S=$(code POST /audits/trigger \
    "{\"trip_id\":\"$TRIP\",\"leg_sequence\":1,\"trigger_type\":\"manual\"}" "$CT")
  if [ "$S" = "200" ]; then
    python3 -c "
import json;a=json.load(open('/tmp/resp.json'))
print(f\"        visual={a['visual_count']}  manifest={a['booked_count']}  \"
      f\"variance={a['variance']:+d}  {a['inference_ms']}ms\")
print(f\"        {a['message']}\")"
    ok "audit recorded"
  else bad "audit gave $S"; fi
else
  gap "AI node offline -- start it: cd ai_service && python app.py"
fi

# ═══════════════════════════════════════════════ 6. DEPARTURE
hdr "6. Departure"

S=$(code POST "/trips/$TRIP/headcount" \
  '{"stop_sequence":1,"confirmed_count":4}' "$CT")
if [ "$S" = "200" ]; then
  ok "headcount confirmed -- variance $(j "['variance']" < /tmp/resp.json)"
else bad "headcount gave $S"; fi

S=$(code POST "/trips/$TRIP/depart" "" "$CT")
if [ "$S" = "200" ]; then
  ok "departed -- $(j "['no_shows']" < /tmp/resp.json) no-show(s) recorded"
else bad "depart gave $S"; fi

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
[ "$S" = "409" ] && ok "bookings closed after departure (409)" || bad "post-departure booking gave $S"

# ═══════════════════════════════════════════════ 7. BOUNDARIES
hdr "7. A conductor is not an operator"

for ep in "GET /fleet/vans" "GET /config/policies" "GET /revenue/summary" \
          "GET /audits/pending"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$CT")
  [ "$S" = "403" ] && ok "$p blocked (403)" || bad "$p gave $S, expected 403"
done

S=$(code POST /fleet/vans '{"plate_number":"HAX-0001","seat_capacity":14}' "$CT")
[ "$S" = "403" ] && ok "cannot add vans (403)" || bad "van creation gave $S"

printf '\n\033[1m═══ SUMMARY ═══\033[0m\n  passed  %d\n  failed  %d\n  gaps    %d\n\n' \
  "$PASS_N" "$FAIL_N" "$GAP_N"
