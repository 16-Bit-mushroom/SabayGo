#!/usr/bin/env bash
# Dispatcher journey -- everything a Dispatcher does at the terminal.
#
#   ./tests/integration/test_dispatcher_journey.sh
#
# The Dispatcher works the van door: scan tickets, log cash walk-ins,
# watch the manifest, close boarding.
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

S=$(code POST /auth/login '{"email":"dispatcher@sabaygo.dev","password":"sabaygo123"}')
[ "$S" = "200" ] && ok "login" || { bad "login gave $S"; exit 1; }
CT=$(j "['access_token']" < /tmp/resp.json)
[ "$(j "['role']" < /tmp/resp.json)" = "dispatcher" ] && ok "role is dispatcher" || bad "wrong role"
# The office takes the share, starts and departs the trip (rev 603,
# brief 2.1, 4.2).
code POST /auth/login '{"email":"cashier@sabaygo.dev","password":"sabaygo123"}' >/dev/null
OFF=$(j "['access_token']" < /tmp/resp.json)

S=$(code GET /auth/me "" "$CT")
[ "$S" = "200" ] && ok "profile: $(j "['display_name']" < /tmp/resp.json)" || bad "me gave $S"

# ── set up a passenger whose cash the Dispatcher will take
hdr "   (setting up a reservation to collect)"
S=$(code POST /auth/register "{\"email\":\"pax${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0916${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"first_name\":\"Scan\",\"last_name\":\"Target\"}")
PT=$(j "['access_token']" < /tmp/resp.json)
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID=$(j "['booking_id']" < /tmp/resp.json)
CODE=$(j "['booking_code']" < /tmp/resp.json)
[ -n "$CODE" ] && ok "passenger reserved a seat ($CODE), unpaid" \
  || bad "reservation carried no booking code"

# A second reservation, deliberately left unpaid to the end. Reserved
# here rather than later because APP_BOOKABLE is {scheduled}: once
# boarding opens, reserve is correctly refused.
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
UNPAID_BID=$(j "['booking_id']" < /tmp/resp.json)
UNPAID_CODE=$(j "['booking_code']" < /tmp/resp.json)

# Two more, reserved now because APP_BOOKABLE is {scheduled}: one to
# cancel after its cash is taken, one for the offline-time mark.
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
SPARE=$(j "['booking_id']" < /tmp/resp.json)
code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
OFFLINE_BID=$(j "['booking_id']" < /tmp/resp.json)

# ═══════════════════════════════════════════════ 2. BOARDING
hdr "2. Boarding"

# Cancellation closes when the Cashier records the payment or the van
# departs (brief 2.1), so the Dispatcher's two cancellations are
# exercised first, while the list is still open.
S=$(code POST "/bookings/$UNPAID_BID/dispatcher-cancel" \
  '{"reason":"forgot_to_cancel"}' "$CT")
[ "$S" = "200" ] && ok "Dispatcher cleared an unpaid reservation nobody came for" \
  || bad "forgot_to_cancel gave $S"

code POST "/bookings/$SPARE/mark-paid" '{}' "$CT" >/dev/null
S=$(code POST "/bookings/$SPARE/dispatcher-cancel" '{"reason":"forgot_to_cancel"}' "$CT")
[ "$S" = "409" ] && ok "a paid seat cannot be cleared as forgotten (409)" \
  || bad "forgot_to_cancel on a paid seat gave $S"

S=$(code POST "/bookings/$SPARE/dispatcher-cancel" \
  '{"reason":"passenger_asked_dispatcher"}' "$CT")
[ "$S" = "200" ] && ok "Dispatcher cancelled a paid seat, cash returned" \
  || bad "dispatcher-cancel gave $S"

# The Dispatcher takes the cash at the door. There is no QR to scan:
# the seat is found by name or booking code and marked Paid (brief 2.1).
S=$(code GET "/bookings/trip/$TRIP/seats" "" "$CT")
if [ "$S" = "200" ]; then
  ok "the Dispatcher reads the trip's seat list ($(j "[0]['payment_status']" < /tmp/resp.json) first)"
else bad "seat list gave $S"; fi

S=$(code GET "/bookings/trip/$TRIP/seats?q=Scan" "" "$CT")
FOUND=$(python3 -c "
import json;d=json.load(open('/tmp/resp.json'))
print(sum(1 for b in d if b['booking_id']=='$BID'))" 2>/dev/null)
[ "$S" = "200" ] && [ "$FOUND" = "1" ] && ok "found by passenger name" \
  || bad "search by name gave $S, matched $FOUND"

S=$(code POST "/bookings/$BID/mark-paid" '{}' "$CT")
R=$(j "['payment_status']" < /tmp/resp.json)
[ "$S" = "200" ] && [ "$R" = "paid" ] && ok "cash taken, seat marked paid" \
  || bad "mark-paid gave $S/$R"

# The offline queue on the Dispatcher's phone may send the same mark
# twice; the second is not an error.
S=$(code POST "/bookings/$BID/mark-paid" '{}' "$CT")
[ "$S" = "200" ] && ok "a replayed paid mark changes nothing" \
  || bad "replayed mark-paid gave $S"

S=$(code POST "/bookings/BKG-DOES-NOT-EXIST/mark-paid" '{}' "$CT")
[ "$S" = "404" ] && ok "unknown booking -> 404" || bad "unknown booking gave $S"

# A mark recorded on the device while it was offline keeps its own time.
S=$(code POST "/bookings/$OFFLINE_BID/mark-paid" \
  '{"paid_at":"2026-11-02T05:10:00"}' "$CT")
PAID_AT=$(j "['paid_at']" < /tmp/resp.json)
if [ "$S" = "200" ] && [ "${PAID_AT:0:10}" = "2026-11-02" ]; then
  ok "an offline mark keeps the time the device recorded"
else bad "offline mark gave $S, paid_at $PAID_AT"; fi

# ── the Dispatcher has built the list; now the money moves
hdr "   (handing the share to the Cashier)"

code GET "/trips/$TRIP/share" "" "$OFF" >/dev/null
DUE=$(j "['amount_due']" < /tmp/resp.json)
[ "$DUE" != "0.00" ] && ok "the share is computed from the paid seats (P$DUE)" \
  || bad "amount due is $DUE with paid seats on the list"
S=$(code POST "/trips/$TRIP/payment" "{\"amount\":\"$DUE\",\"reference\":\"OR-$STAMP\"}" "$OFF")
[ "$S" = "200" ] && ok "the cashier records the share" || bad "payment gave $S"

# The list locks when the payment is recorded (brief 2.1).
S=$(code POST "/bookings/$BID/dispatcher-cancel" \
  '{"reason":"passenger_asked_dispatcher"}' "$CT")
[ "$S" = "422" ] && ok "no cancellation once the list is locked (422)" \
  || bad "cancel after the lock gave $S"

S=$(code POST "/trips/$TRIP/start" "" "$OFF")
[ "$S" = "200" ] && ok "the cashier starts the trip" || bad "start gave $S"

# ═══════════════════════════════════════════════ 3. WALK-INS
hdr "3. Cash walk-ins"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "anonymous walk-in logged -- status $(j "['status']" < /tmp/resp.json)" \
                 || bad "walk-in gave $S"

S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,
  \"alighting_stop\":4,\"name\":\"Maria Santos\",\"phone\":\"09171112222\",
  \"wants_receipt\":true}" "$CT")
[ "$S" = "201" ] && ok "walk-in with receipt details -- P$(j "['fare_amount']" < /tmp/resp.json)" \
                 || bad "receipt walk-in gave $S"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":3}" "$CT")
[ "$S" = "201" ] && ok "walk-in to an intermediate terminal (stop 1->3)" || bad "walk-in to stop 3 gave $S"

S=$(code POST /bookings/walk-in \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":3,\"alighting_stop\":4}" "$CT")
[ "$S" = "422" ] && ok "a walk-in from a later terminal is refused (rev 603)" || bad "stop-3 walk-in gave $S"

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
    print(f\"        {p['boarding_stop']}->{p['alighting_stop']}  \"
          f\"{p['status']:<11} {who}\")"
  ok "manifest retrieved"
else bad "manifest gave $S"; fi

S=$(code "GET" "/bookings/availability?trip_id=$TRIP&boarding_stop=1&alighting_stop=4")
ok "seats still sellable end-to-end: $(j "['seats_available']" < /tmp/resp.json)"

# ═══════════════════════════════════════════════ 5. DEPARTURE
hdr "5. Departure"

S=$(code POST "/trips/$TRIP/depart" "" "$OFF")
if [ "$S" = "200" ]; then
  ok "departed -- $(j "['no_shows']" < /tmp/resp.json) no-show(s) recorded"
else bad "depart gave $S"; fi

S=$(code POST /bookings/reserve \
  "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
[ "$S" = "409" ] && ok "bookings closed after departure (409)" || bad "post-departure booking gave $S"

# ═══════════════════════════════════════════════ 6. BOUNDARIES
hdr "6. A Dispatcher is not the Terminal Manager"

for ep in "GET /fleet/vans" "GET /config/policies" "GET /statements" \
          "GET /boarding-audit"; do
  m=${ep%% *}; p=${ep#* }
  S=$(code "$m" "$p" "" "$CT")
  [ "$S" = "403" ] && ok "$p blocked (403)" || bad "$p gave $S, expected 403"
done

S=$(code POST /fleet/vans '{"plate_number":"HAX-0001","seat_capacity":14}' "$CT")
[ "$S" = "403" ] && ok "cannot add vans (403)" || bad "van creation gave $S"

printf '\n\033[1m═══ SUMMARY ═══\033[0m\n  passed  %d\n  failed  %d\n  gaps    %d\n\n' \
  "$PASS_N" "$FAIL_N" "$GAP_N"
