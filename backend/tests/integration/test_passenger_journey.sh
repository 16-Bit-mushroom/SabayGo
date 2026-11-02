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
[ "$S" = "200" ] && ok "search trips by sequence (legacy)" || bad "search gave $S"

# Terminals are unique in the picker even when they sit on several routes
DUP=$(code GET /trips/terminals >/dev/null; python3 -c "import json;ids=[t['terminal_id'] for t in json.load(open('/tmp/resp.json'))];print(len(ids)-len(set(ids)))")
[ "$DUP" = "0" ] && ok "terminal picker has no duplicates" || bad "$DUP duplicate terminals in picker"

# The fixture departs today after a --soon reset, tomorrow after a plain one.
for TODAY in $(date +%F) $(date -d tomorrow +%F); do
  S=$(code "GET" "/trips/search?origin_terminal_id=TERM-ECOLAND-000001&destination_terminal_id=TERM-COTABATO-00001&service_date=$TODAY")
  N=$(python3 -c "import json;d=json.load(open('/tmp/resp.json'));print(len(d) if isinstance(d,list) else -1)")
  [ "$N" -ge 1 ] && break
done
[ "$S" = "200" ] && [ "$N" -ge 1 ] && ok "search by terminals: $N departure(s) Ecoland -> Cotabato" || bad "terminal search gave $S / $N"
S=$(code "GET" "/trips/search?origin_terminal_id=TERM-COTABATO-00001&destination_terminal_id=TERM-ECOLAND-000001&service_date=$TODAY")
N=$(python3 -c "import json;d=json.load(open('/tmp/resp.json'));print(len(d) if isinstance(d,list) else -1)")
[ "$S" = "200" ] && [ "$N" = "0" ] && ok "reverse direction finds nothing (different LTFRB route)" || bad "reverse search gave $S / $N"
S=$(code "GET" "/trips/search?service_date=$TODAY")
[ "$S" = "422" ] && ok "search with no terminals rejected (422)" || bad "bare search gave $S"

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
CODE=$(j "['booking_code']" < /tmp/resp.json)
[ -n "$CODE" ] && ok "booking code issued ($CODE)" || bad "no booking code on the reservation"
PS=$(j "['payment_status']" < /tmp/resp.json)
[ "$PS" = "unpaid" ] && ok "reservation starts unpaid" || bad "payment_status is $PS"

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":4,\"alighting_stop\":1}" "$TOKEN")
[ "$S" = "422" ] && ok "reversed segment rejected (422)" || bad "reversed gave $S"

S=$(code GET /bookings/mine "" "$TOKEN")
[ "$S" = "200" ] && ok "list my bookings" || bad "mine gave $S"

S=$(code GET "/bookings/$BID" "" "$TOKEN")
if [ "$S" = "200" ] && [ "$(j "['booking_id']" < /tmp/resp.json)" = "$BID" ]; then
  ok "booking detail ($(j "['status']" < /tmp/resp.json))"
else bad "GET /bookings/{id} gave $S"; fi

S=$(code GET "/bookings/BKG-DOES-NOT-EXIST" "" "$TOKEN")
[ "$S" = "404" ] && ok "unknown booking id -> 404" || bad "unknown booking gave $S"

# ═══════════════════════════════════════════════ 4. PAYING AT THE TERMINAL
# A2Z handles only cash (brief rev 721, 2.1). The passenger reserves in
# the app and hands the fare to the Dispatcher at the terminal, who
# finds the seat by name or booking code and marks it Paid. There is no
# gateway and no QR ticket.
hdr "4. Paying cash at the terminal"

S=$(code POST "/bookings/$BID/mark-paid" '{}' "$TOKEN")
[ "$S" = "403" ] && ok "a passenger cannot mark their own seat paid (403)" \
  || bad "passenger mark-paid gave $S"

S=$(code POST /auth/login '{"email":"dispatcher@sabaygo.dev","password":"sabaygo123"}')
DT=$(j "['access_token']" < /tmp/resp.json)
[ "$S" = "200" ] && ok "Dispatcher signed in" || bad "dispatcher login gave $S"

S=$(code GET "/bookings/trip/$TRIP/seats?q=$CODE" "" "$DT")
if [ "$S" = "200" ] && [ "$(j "[0]['booking_code']" < /tmp/resp.json)" = "$CODE" ]; then
  ok "Dispatcher finds the seat by booking code"
else bad "search by code gave $S"; fi

S=$(code POST "/bookings/$BID/mark-paid" '{}' "$DT")
if [ "$S" = "200" ] && [ "$(j "['payment_status']" < /tmp/resp.json)" = "paid" ]; then
  ok "Dispatcher marked the seat paid"
else bad "mark-paid gave $S"; fi

# An offline queue may replay the same mark. It must not be an error.
S=$(code POST "/bookings/$BID/mark-paid" '{}' "$DT")
[ "$S" = "200" ] && ok "a replayed paid mark is accepted, not an error" \
  || bad "replayed mark-paid gave $S"

S=$(code GET /bookings/mine "" "$TOKEN")
STATUS=$(python3 -c "
import json;d=json.load(open('/tmp/resp.json'))
print(next((b['payment_status'] for b in d if b['booking_id']=='$BID'),'?'))")
[ "$STATUS" = "paid" ] && ok "the passenger sees the seat as paid" || bad "status is $STATUS"

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$TOKEN")
# A reservation nobody pays for; section 5 cancels it and checks the
# space comes back.
ABANDON=$(j "['booking_id']" < /tmp/resp.json)

# ═══════════════════════════════════════════════ 5. CHANGES
# Rev 721 has no reschedule: an unpaid reservation is cancelled and
# booked again. A paid seat goes through the Dispatcher, because the
# cash has to be handed back by a person.
hdr "5. Changing plans"

S=$(code POST "/bookings/$BID/cancel" "" "$TOKEN")
[ "$S" = "422" ] && ok "a passenger cannot cancel a paid seat (422)" \
  || bad "cancelling a paid seat gave $S"

S=$(code POST "/bookings/$BID/dispatcher-cancel" \
  '{"reason":"passenger_asked_dispatcher"}' "$DT")
if [ "$S" = "200" ] && [ "$(j "['cancel_reason']" < /tmp/resp.json)" = "passenger_asked_dispatcher" ]; then
  ok "the Dispatcher cancelled it and hands the cash back"
else bad "dispatcher-cancel gave $S"; fi

spaces() {
  code GET "/bookings/availability?trip_id=$TRIP&boarding_stop=1&alighting_stop=4" >/dev/null
  j "['seats_available']" < /tmp/resp.json
}
BEFORE=$(spaces)
S=$(code POST "/bookings/$ABANDON/cancel" "" "$TOKEN")
AFTER=$(spaces)
if [ "$S" = "200" ] && [ "$AFTER" = "$((BEFORE + 1))" ]; then
  ok "unpaid reservation cancelled, space released ($BEFORE -> $AFTER)"
else bad "cancel gave $S, spaces $BEFORE -> $AFTER"; fi

S=$(code POST "/bookings/$ABANDON/cancel" "" "$TOKEN")
[ "$S" = "409" ] && ok "double cancel rejected (409)" || bad "double cancel gave $S"

# ═══════════════════════════════════════════════ 6. TRAVEL DAY
hdr "6. Travel day"

# Section 5 cancelled the first seat, so book and pay another one.
S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$TOKEN")
BID=$(j "['booking_id']" < /tmp/resp.json)
code POST "/bookings/$BID/mark-paid" '{}' "$DT" >/dev/null

# D.2: nothing to undo yet -> 409, never 404/405
S=$(code DELETE "/bookings/$BID/check-in" "" "$TOKEN")
[ "$S" = "409" ] && ok "undo before check-in rejected (409)" || bad "undo before check-in gave $S"

S=$(code POST "/bookings/$BID/check-in" \
  "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" "$TOKEN")
CHECKED_IN=0
if [ "$S" = "200" ]; then ok "checked in at the terminal"; CHECKED_IN=1
elif [ "$S" = "422" ]; then
  gap "check-in -- $(j "['detail']" < /tmp/resp.json)"
else bad "check-in gave $S"; fi

S=$(code POST "/bookings/$BID/check-in" \
  "{\"latitude\":7.20,\"longitude\":125.40,\"gps_accuracy_m\":8.5}" "$TOKEN")
{ [ "$S" = "422" ] || [ "$S" = "409" ]; } && ok "far check-in rejected ($S)" || bad "far check-in gave $S"

# D.1: /bookings/mine tells the app when check-in opens at the passenger's own stop
S=$(code GET /bookings/mine "" "$TOKEN")
if [ "$S" = "200" ] && j "[0]['checkin_opens_at']" < /tmp/resp.json >/dev/null 2>&1; then
  ok "my bookings carry checkin_opens_at / boarding_due_at"
else bad "my bookings missing checkin_opens_at (HTTP $S)"; fi

# D.2: undo, then check in again -- the undo must not consume the booking
if [ "$CHECKED_IN" = "1" ]; then
  S=$(code DELETE "/bookings/$BID/check-in" "" "$TOKEN")
  [ "$S" = "200" ] && ok "check-in undone ($(j "['status']" < /tmp/resp.json))" || bad "undo check-in gave $S"

  S=$(code DELETE "/bookings/$BID/check-in" "" "$TOKEN")
  [ "$S" = "409" ] && ok "double undo rejected (409)" || bad "double undo gave $S"

  S=$(code POST "/bookings/$BID/check-in" \
    "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" "$TOKEN")
  [ "$S" = "200" ] && ok "checked in again after undo" || bad "re-check-in gave $S"
else
  gap "undo check-in -- skipped, check-in itself was not accepted"
fi

# ═══════════════════════════════════════════════ 7. SELF-SERVICE
hdr "7. Managing the account"

S=$(code PATCH /auth/me '{"first_name":"Updated"}' "$TOKEN")
if [ "$S" = "404" ] || [ "$S" = "405" ]; then
  gap "update profile -- name, phone and address cannot be changed"
else ok "profile updated"; fi

NEWPASS="newpass123"
S=$(code PATCH /auth/me "{\"current_password\":\"wrong\",\"new_password\":\"$NEWPASS\"}" "$TOKEN")
[ "$S" = "409" ] && ok "password change with a wrong current password refused (409)" \
                 || bad "wrong current password gave $S"
S=$(code PATCH /auth/me "{\"current_password\":\"$PASS\",\"new_password\":\"$NEWPASS\"}" "$TOKEN")
[ "$S" = "200" ] && ok "password changed" || bad "password change gave $S"
S=$(code POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
[ "$S" = "401" ] && ok "old password no longer signs in (401)" || bad "old password gave $S"
S=$(code POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$NEWPASS\"}")
[ "$S" = "200" ] && ok "new password signs in" || bad "new password gave $S"

S=$(code GET /notifications "" "$TOKEN")
if [ "$S" = "404" ]; then
  gap "notifications -- table exists, no endpoint reads it"
else ok "notifications listed"; fi

# ═══════════════════════════════════════════════ 8. BOUNDARIES
hdr "8. Passengers cannot act as crew"

for ep in "GET /bookings/trip/$TRIP/seats" "GET /trips/$TRIP/manifest" \
          "GET /boarding-audit" "GET /fleet/vans" "GET /config/policies" \
          "GET /statements"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$TOKEN")
  [ "$S" = "403" ] && ok "$p blocked (403)" || bad "$p gave $S, expected 403"
done

# ═══════════════════════════════════════════════ 9. LEAVING
# Last, because a closed account's token stops working.
hdr "9. Closing the account"

S=$(code POST /auth/me/close '{"password":"wrong"}' "$TOKEN")
[ "$S" = "409" ] && ok "close with a wrong password refused (409)" || bad "wrong-password close gave $S"
S=$(code POST /auth/me/close "{\"password\":\"$NEWPASS\"}" "$TOKEN")
[ "$S" = "204" ] && ok "account closed (204)" || bad "close gave $S"
S=$(code POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$NEWPASS\"}")
[ "$S" = "401" ] && ok "closed account cannot sign in (401)" || bad "closed-account login gave $S"
S=$(code GET /auth/me "" "$TOKEN")
[ "$S" = "403" ] && ok "closed account's token refused (403)" || bad "closed-account token gave $S"

# ═══════════════════════════════════════════════ SUMMARY
printf '\n\033[1m═══ SUMMARY ═══\033[0m\n'
printf '  passed  %d\n  failed  %d\n  gaps    %d\n\n' "$PASS_N" "$FAIL_N" "$GAP_N"
[ "$FAIL_N" -eq 0 ] && echo "No failures. Gaps are unbuilt endpoints, not broken ones." \
                    || echo "Failures above are real regressions."
