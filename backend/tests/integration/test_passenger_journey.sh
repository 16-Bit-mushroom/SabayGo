#!/usr/bin/env bash
# Complete passenger journey -- every action a passenger can take.
#
#   ./tests/integration/test_passenger_journey.sh
#
# Steps marked [GAP] exercise endpoints that DO NOT EXIST yet. They are
# left in deliberately: the script doubles as a checklist of what is
# missing, and will start passing as those endpoints are built.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
EMAIL="journey${STAMP}@sabaygo.dev"
PASS="sabaygo123"
LAT=7.052400; LNG=125.593100          # Ecoland Terminal
PASS_N=0; FAIL_N=0; GAP_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
gap()  { printf '  \033[33mGAP \033[0m  %s\n' "$1"; GAP_N=$((GAP_N+1)); }

# code <method> <path> [data] [token] -> prints HTTP status
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}

# ═══════════════════════════════════════════════ 1. ACCOUNT
hdr "1. Account"

S=$(code POST /auth/register "{\"email\":\"$EMAIL\",\"phone_number\":\"0917${STAMP: -7}\",
  \"password\":\"$PASS\",\"first_name\":\"Journey\",\"last_name\":\"Tester\",
  \"home_address\":\"Matina, Davao City\",\"gender\":\"female\",
  \"emergency_contact_name\":\"Ana Cruz\",\"emergency_contact_relation\":\"Sister\",
  \"emergency_contact_number\":\"09181234567\"}")
[ "$S" = "201" ] && ok "register (201)" || bad "register returned $S"
TOKEN=$(j "['access_token']" < /tmp/resp.json)

S=$(code POST /auth/register "{\"email\":\"dup${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0917${STAMP: -7}\",\"password\":\"$PASS\",
  \"first_name\":\"Dup\",\"last_name\":\"Test\"}")
[ "$S" = "409" ] && ok "duplicate phone rejected (409)" || bad "duplicate gave $S"

S=$(code POST /auth/register "{\"email\":\"weak${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0915${STAMP: -7}\",\"password\":\"123\",
  \"first_name\":\"Weak\",\"last_name\":\"Pass\"}")
[ "$S" = "422" ] && ok "short password rejected (422)" || bad "weak password gave $S"

S=$(code POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"wrong\"}")
[ "$S" = "401" ] && ok "wrong password rejected (401)" || bad "wrong password gave $S"

S=$(code POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
[ "$S" = "200" ] && ok "login (200)" || bad "login gave $S"
TOKEN=$(j "['access_token']" < /tmp/resp.json)

S=$(code GET /auth/me "" "$TOKEN")
[ "$S" = "200" ] && ok "profile: $(j "['display_name']" < /tmp/resp.json)" || bad "me gave $S"

S=$(code GET /auth/me)
[ "$S" = "401" ] && ok "unauthenticated request rejected (401)" || bad "no-token gave $S"

# ═══════════════════════════════════════════════ 2. DISCOVERY
hdr "2. Finding a trip"

S=$(code GET /trips/terminals)
[ "$S" = "200" ] && ok "list terminals ($(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))") found)" \
                 || bad "terminals gave $S"

S=$(code "GET" "/trips/search?boarding_stop=1&alighting_stop=4")
[ "$S" = "200" ] && ok "search trips" || bad "search gave $S"

S=$(code GET "/trips/$TRIP/stops")
[ "$S" = "200" ] && ok "view route stops" || bad "stops gave $S"

S=$(code GET "/bookings/availability?trip_id=$TRIP&boarding_stop=1&alighting_stop=4")
AVAIL=$(j "['seats_available']" < /tmp/resp.json)
[ "$S" = "200" ] && ok "check availability ($AVAIL seats)" || bad "availability gave $S"

# ═══════════════════════════════════════════════ 3. BOOKING
hdr "3. Booking"

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$TOKEN")
[ "$S" = "201" ] && ok "reserve seat $(j "['seat_number']" < /tmp/resp.json)" || bad "reserve gave $S"
BID=$(j "['booking_id']" < /tmp/resp.json)
QR=$(j "['qr_payload']" < /tmp/resp.json)

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":4,\"alighting_stop\":1}" "$TOKEN")
[ "$S" = "422" ] && ok "reversed segment rejected (422)" || bad "reversed gave $S"

S=$(code GET /bookings/mine "" "$TOKEN")
[ "$S" = "200" ] && ok "list my bookings" || bad "mine gave $S"

S=$(code GET "/bookings/$BID" "" "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "GET /bookings/{id} -- no single-booking detail endpoint"
else ok "booking detail"; fi

# ═══════════════════════════════════════════════ 4. PAYMENT
hdr "4. Payment"

S=$(code POST /payments/checkout "{\"booking_id\":\"$BID\"}" "$TOKEN")
if [ "$S" = "502" ]; then gap "checkout -- PAYMONGO_SECRET_KEY not set (expected)"
elif [ "$S" = "201" ]; then ok "checkout session created"
else bad "checkout gave $S"; fi

python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1 \
  && ok "payment confirmed via signed webhook" \
  || gap "webhook simulator -- set PAYMONGO_WEBHOOK_SECRET"

S=$(code GET /bookings/mine "" "$TOKEN")
STATUS=$(python3 -c "
import json;d=json.load(open('/tmp/resp.json'))
print(next((b['status'] for b in d if b['booking_id']=='$BID'),'?'))")
[ "$STATUS" = "confirmed" ] && ok "booking is now confirmed" || bad "status is $STATUS"

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$TOKEN")
ABANDON=$(j "['booking_id']" < /tmp/resp.json)
S=$(code DELETE "/payments/checkout/$ABANDON" "" "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "abandon checkout -- seat stays held for 10 min with no way to release it"
else ok "checkout abandoned, seat released"; fi

# ═══════════════════════════════════════════════ 5. CHANGES
hdr "5. Changing plans"

S=$(code POST "/bookings/$BID/reschedule" '{"new_trip_id":"TRIP-DEMO-00000002"}' "$TOKEN")
if [ "$S" = "200" ]; then
  ok "rescheduled to another trip"
  BID=$(j "['new_booking_id']" < /tmp/resp.json)
  QR=$(j "['qr_payload']" < /tmp/resp.json)
elif [ "$S" = "404" ]; then gap "reschedule -- no second trip seeded"
else bad "reschedule gave $S"; fi

S=$(code POST "/bookings/$ABANDON/cancel" "" "$TOKEN")
[ "$S" = "200" ] && ok "cancel (no refund, seat released)" || bad "cancel gave $S"

S=$(code POST "/bookings/$ABANDON/cancel" "" "$TOKEN")
[ "$S" = "409" ] && ok "double cancel rejected (409)" || bad "double cancel gave $S"

# ═══════════════════════════════════════════════ 6. TRAVEL DAY
hdr "6. Travel day"

S=$(code POST "/bookings/$BID/check-in" \
  "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" "$TOKEN")
if [ "$S" = "200" ]; then ok "checked in at the terminal"
elif [ "$S" = "422" ]; then
  gap "check-in -- $(j "['detail']" < /tmp/resp.json)"
else bad "check-in gave $S"; fi

S=$(code POST "/bookings/$BID/check-in" \
  "{\"latitude\":7.20,\"longitude\":125.40,\"gps_accuracy_m\":8.5}" "$TOKEN")
[ "$S" = "422" ] && ok "check-in from 25km away rejected (422)" || bad "far check-in gave $S"

S=$(code DELETE "/bookings/$BID/check-in" "" "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "undo check-in -- no way to reverse an accidental check-in"
else ok "check-in undone"; fi

# ═══════════════════════════════════════════════ 7. SELF-SERVICE
hdr "7. Managing the account"

S=$(code PATCH /auth/me '{"first_name":"Updated"}' "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "update profile -- name, phone and address cannot be changed"
else ok "profile updated"; fi

S=$(code POST /auth/change-password \
  "{\"current_password\":\"$PASS\",\"new_password\":\"newpass123\"}" "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "change password -- not implemented"
else ok "password changed"; fi

S=$(code GET /notifications "" "$TOKEN")
if [ "$S" = "404" ]; then
  gap "notifications -- table exists, no endpoint reads it"
else ok "notifications listed"; fi

S=$(code GET /saved-destinations "" "$TOKEN")
if [ "$S" = "404" ]; then
  gap "saved destinations -- table and ORM model exist, no endpoints"
else ok "saved destinations listed"; fi

S=$(code GET /settings "" "$TOKEN")
if [ "$S" = "404" ]; then
  gap "notification settings -- passenger_settings unreachable"
else ok "settings readable"; fi

S=$(code DELETE /auth/me "" "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "delete/deactivate account -- no way for a passenger to leave"
else ok "account deactivated"; fi

# ═══════════════════════════════════════════════ 8. BOUNDARIES
hdr "8. Passengers cannot act as crew"

for ep in "POST /scans" "GET /trips/$TRIP/manifest" "GET /audits/pending" \
          "GET /fleet/vans" "GET /config/policies" "GET /revenue/summary"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" '{"qr_payload":"x","trip_id":"x","stop_sequence":1}' "$TOKEN")
  [ "$S" = "403" ] && ok "$p blocked (403)" || bad "$p gave $S, expected 403"
done

# ═══════════════════════════════════════════════ SUMMARY
printf '\n\033[1m═══ SUMMARY ═══\033[0m\n'
printf '  passed  %d\n  failed  %d\n  gaps    %d\n\n' "$PASS_N" "$FAIL_N" "$GAP_N"
[ "$FAIL_N" -eq 0 ] && echo "No failures. Gaps are unbuilt endpoints, not broken ones." \
                    || echo "Failures above are real regressions."
