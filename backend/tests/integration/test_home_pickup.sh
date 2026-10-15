#!/usr/bin/env bash
# Rev 603 R6: home pickup of a disabled or elderly passenger (change
# brief 2.6; T30, T31, T32, T41 a). Chat image retention (T41 b) is R8.
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_home_pickup.sh
#
# Books on TRIP-DEMO-00000001 (Ecoland -> Digos -> ..., dispatcher@,
# departs in 20 min). The pins sit 150 m and 2 km off the straight
# Ecoland-Digos stretch. Seats are paid with the signed webhook simulator.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP=TRIP-DEMO-00000001
STAMP=$(date +%s)
NEAR='"pickup_latitude":6.900126,"pickup_longitude":125.476224'
FAR='"pickup_latitude":6.889961,"pickup_longitude":125.489467'
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }
field() { j "$1" < /tmp/hp.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/hp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  field "['access_token']"
}
register() {
  curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
    -d "{\"email\":\"hp$1${STAMP}@sabaygo.dev\",\"phone_number\":\"09$1${STAMP: -7}\",\"password\":\"sabaygo123\",\"first_name\":\"Home\",\"last_name\":\"Pickup\"}" \
    | j "['access_token']"
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
pay() { (cd "$BACKEND" && venv/bin/python tests/integration/simulate_webhook.py --booking-id "$1" >/dev/null 2>&1); }
policy() { code PUT /config/policies/home_pickup_max_route_m "{\"policy_value\":\"$1\"}" "$OT" >/dev/null; }
book() {  # book TOKEN PIN -> pickup, relative booking, passenger booking in PK RB SB
  local s
  s=$(code POST /home-pickups "{\"trip_id\":\"$TRIP\",\"alighting_stop\":2,\"beneficiary_name\":\"Lola Remedios\",\"beneficiary_contact\":\"09171234567\",${2},\"pickup_note\":\"Green gate past the chapel\"}" "$1")
  PK=$(field "['pickup']['pickup_id']"); RB=$(field "['relative_booking']['booking_id']")
  SB=$(field "['passenger_booking']['booking_id']")
  RQ=$(field "['relative_booking']['qr_payload']"); SQ=$(field "['passenger_booking']['qr_payload']")
  echo "$s" > /tmp/hp.code
}
scan() { code POST /scans "{\"qr_payload\":\"$1\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$DT" >/dev/null; printf '%s' "$(field "['result']")"; }
pk() { sql "SELECT CONCAT_WS('/', status, COALESCE(activation_mode, '-'), COALESCE(activated_by, '-')) FROM assisted_pickups WHERE pickup_id = '$1'"; }
st() { sql "SELECT status FROM bookings WHERE booking_id = '$1'"; }
upload() {  # upload PICKUP FILE TOKEN
  curl -s -o /tmp/hp.json -w "%{http_code}" -X POST "$API/home-pickups/$1/proof" \
    -H "Authorization: Bearer $3" -F "image=@$2"
}
fetch() { curl -s -o /tmp/hp_got.img -w "%{http_code}" "$API/home-pickups/$1/proof" -H "Authorization: Bearer $2"; }
notes() {
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/hp.json'))['items'] if n['type']=='$2' and n['related_entity_id']=='$TRIP'))"
}
verified() {  # verified seats to Digos on the trip's statement
  code GET /trips/$TRIP/share "" "$CT" >/dev/null
  python3 -c "import json;print(sum(l['passenger_count'] for l in json.load(open('/tmp/hp.json'))['lines'] if l['income_group']=='verified' and (l['dest_terminal_name'] or '').startswith('Digos')))"
}
img() { python3 -c "import sys;sys.stdout.buffer.write(b'\\x89PNG\\r\\n\\x1a\\n'+bytes([$2])*$1)" > "$3"; }

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); D2T=$(login dispatcher2)
PT=$(register 11); QT=$(register 12); RT=$(register 13)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$D2T" ] && [ -n "$PT" ] && [ -n "$QT" ] && [ -n "$RT" ] \
  && ok "signed in" || { bad "login"; exit 1; }
policy ""

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Book for someone else, with a pin (T30)"
book "$PT" "$NEAR"
is "$(cat /tmp/hp.code)" 422 "not offered while home_pickup_max_route_m is unset"
policy 500
book "$DT" "$NEAR"
is "$(cat /tmp/hp.code)" 403 "a Dispatcher does not book a home pickup"
book "$PT" "$FAR"
is "$(cat /tmp/hp.code)" 422 "T30 b a pin 2 km from the route is refused"
is "$(sql "SELECT COUNT(*) FROM bookings b JOIN users u ON u.user_id = b.passenger_user_id WHERE u.email = 'hp11${STAMP}@sabaygo.dev'")" 0 \
   "and neither seat is kept"
code POST /home-pickups "{\"trip_id\":\"$TRIP\",\"alighting_stop\":9,\"beneficiary_name\":\"Lola\",\"beneficiary_contact\":\"09171234567\",$NEAR}" "$PT" >/dev/null
is "$(field "['detail']" | grep -c 'no stop 9')" 1 "a drop-off the route does not have is refused"

# One space left: the pair is refused whole.
HELD=$(sql "SELECT COUNT(*) FROM seat_inventory WHERE trip_id = '$TRIP' AND status = 'held'")
FREE=$(sql "SELECT MIN(seat_number) FROM seat_inventory WHERE trip_id = '$TRIP' AND status = 'available'")
sql "UPDATE seat_inventory SET status = 'booked' WHERE trip_id = '$TRIP' AND status = 'available' AND seat_number <> $FREE"
book "$PT" "$NEAR"
is "$(cat /tmp/hp.code)" 409 "with one space left the pickup is refused"
sql "UPDATE seat_inventory SET status = 'available' WHERE trip_id = '$TRIP' AND status = 'booked' AND booking_id IS NULL"
is "$(sql "SELECT COUNT(*) FROM seat_inventory WHERE trip_id = '$TRIP' AND status = 'held'")" "$HELD" \
   "and the relative's seat is not held"

book "$PT" "$NEAR"; A=$PK; ARB=$RB; ASB=$SB; ARQ=$RQ; ASQ=$SQ
is "$(cat /tmp/hp.code)" 201 "T30 a a pin 150 m from the route is accepted automatically"
D=$(sql "SELECT route_distance_m FROM assisted_pickups WHERE pickup_id = '$A'")
[ "$D" -ge 140 ] && [ "$D" -le 160 ] && ok "RouteDistanceM is stored ($D m)" || bad "route distance $D"
is "$(pk "$A")" "requested/-/-" "Status 'requested'"
is "$(sql "SELECT CONCAT_WS('/', b.booked_for_other, b.is_home_pickup_seat, b.boarding_stop_sequence, b.status) FROM bookings b WHERE b.booking_id = '$ASB'")" 1/1/1/pending \
   "the passenger's seat: booked for someone else, a home-pickup seat, from stop 1"
is "$(sql "SELECT CONCAT_WS('/', booked_for_other, is_home_pickup_seat, status) FROM bookings WHERE booking_id = '$ARB'")" 0/0/pending \
   "the relative's own seat"
is "$(sql "SELECT COUNT(DISTINCT passenger_user_id) * 10 + COUNT(DISTINCT seat_number) FROM bookings WHERE booking_id IN ('$ARB', '$ASB')")" 12 \
   "both are the relative's, on two different spaces"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Paying and activation (T31 a, T32)"
is "$(code POST /home-pickups/$A/activate "" "$DT")" 409 "no activation while the passenger's seat is unpaid"
pay "$ARB"
is "$(scan "$ARQ")" valid "the relative's ticket scans valid"
grep -q "not activated" /tmp/hp.json && ok "and the Dispatcher is told the pickup is not activated" \
  || bad "scan message: $(field "['message']")"
is "$(pk "$A")" "requested/-/-" "the pickup waits"
is "$(code POST /payments/checkout "{\"booking_id\":\"$ASB\"}" "$PT")" 201 \
   "T31 a the relative checks out the passenger's seat through the gateway"
curl -s -X POST "$(field "['checkout_url']")/pay" | grep -q "Payment received" \
  && ok "and pays on the sandbox page: the signed webhook settles it" || bad "sandbox pay"
is "$(st "$ASB")" confirmed "the passenger's seat is paid (V)"
is "$(scan "$ASQ")" wrong_stop "the passenger's ticket is refused at the terminal door"
grep -q "board at the pin" /tmp/hp.json && ok "they board at the pin" || bad "scan message: $(field "['message']")"
is "$(code POST /home-pickups/$A/activate "" "$D2T")" 403 "another Dispatcher cannot activate it"
is "$(code POST /home-pickups/$A/activate "" "$DT")" 200 "T32 b the trip's Dispatcher activates it by hand"
is "$(pk "$A")" "activated/dispatcher_entry/USER-DISPATCHER-0001" \
   "ActivationMode 'dispatcher_entry', ActivatedBy the Dispatcher"
is "$(code POST /home-pickups/$A/activate "" "$DT")" 409 "not twice"

book "$QT" "$NEAR"; B=$PK; BRB=$RB; BSB=$SB; BRQ=$RQ
pay "$BRB"; pay "$BSB"
is "$(scan "$BRQ")" valid "a second relative, both seats paid, scans their ticket"
grep -q "activated\." /tmp/hp.json && ok "the scan says the pickup is activated" || bad "scan message: $(field "['message']")"
is "$(pk "$B")" "activated/qr_scan/-" "T32 a ActivationMode 'qr_scan'"

is "$(code GET "/home-pickups?trip_id=$TRIP" "" "$PT")" 403 "a passenger cannot list the trip's pickups"
is "$(code GET "/home-pickups?trip_id=$TRIP" "" "$DT")" 200 "the Dispatcher lists them"
python3 -c "import json;p={x['pickup_id']:x for x in json.load(open('/tmp/hp.json'))};assert p['$A']['beneficiary_name']=='Lola Remedios' and p['$A']['pickup_note'].startswith('Green gate') and '$B' in p" \
  && ok "with the passenger's name, the pin's note" || bad "pickup list"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Gateway down: a payment screenshot in the trip chat (T31 b, T41 a)"
book "$RT" "$NEAR"; H=$PK; HRB=$RB; HSB=$SB
img 64 1 /tmp/hp_proof1.png; img 96 2 /tmp/hp_proof2.png
img $((10 * 1024 * 1024)) 0 /tmp/hp_big.png; printf 'not an image' > /tmp/hp_text.png
V0=$(verified)
is "$(code POST /home-pickups/$H/proof/confirm "" "$DT")" 409 "nothing to confirm before a screenshot is sent"
is "$(upload "$H" /tmp/hp_proof1.png "$PT")" 404 "another passenger cannot send the proof"
is "$(upload "$H" /tmp/hp_proof1.png "$DT")" 403 "nor the Dispatcher"
is "$(upload "$H" /tmp/hp_big.png "$RT")" 422 "T41 a an image over ChatImageMaxKb (10,240 KB) is refused"
is "$(upload "$H" /tmp/hp_text.png "$RT")" 422 "a file that is not an image is refused"
is "$(sql "SELECT COALESCE(proof_message_id, '-') FROM assisted_pickups WHERE pickup_id = '$H'")" - "neither becomes the proof"
# The relative took longer than the ten-minute hold: the sweep released both seats.
sql "UPDATE seat_inventory SET status = 'available', booking_id = NULL, hold_expires_at = NULL WHERE booking_id IN ('$HRB', '$HSB')"
is "$(upload "$H" /tmp/hp_proof1.png "$RT")" 201 "T31 b the relative sends the screenshot"
M1=$(field "['proof_message_id']")
[ -n "$M1" ] && [ "$M1" != None ] && ok "it is the pickup's ProofMessageID" || bad "no proof message"
is "$(sql "SELECT CONCAT(COUNT(*), '/', MIN(status), '/', MIN(TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), hold_expires_at)) > 11) FROM seat_inventory WHERE booking_id IN ('$HRB', '$HSB')")" 2/held/1 \
   "both unpaid seats are taken again and held until departure, not ten minutes"
code GET /conversations "" "$RT" >/dev/null
CONV=$(python3 -c "import json;print([c['conversation_id'] for c in json.load(open('/tmp/hp.json')) if c['trip_id']=='$TRIP'][0])")
code GET /conversations/$CONV/messages "" "$RT" >/dev/null
python3 -c "
import json, datetime as d
m = json.load(open('/tmp/hp.json'))[-1]
assert m['message_id'] == '$M1' and m['attachment_type'] == 'image' and m['attachment_size_kb'] == 1, m
assert m['retain_until'] == str(d.date.today() + d.timedelta(days=30)), m['retain_until']
" && ok "an image message in their chat with the Dispatcher, kept 30 days (RetainUntil)" || bad "chat message"
code GET /conversations "" "$DT" >/dev/null
python3 -c "import json;assert [c for c in json.load(open('/tmp/hp.json')) if c['conversation_id']=='$CONV' and c['unread_count']>=1]" \
  && ok "the Dispatcher has it unread" || bad "Dispatcher's chat"
is "$(upload "$H" /tmp/hp_proof2.png "$RT")" 201 "a second screenshot, before confirmation"
M2=$(field "['proof_message_id']")
[ "$M2" != "$M1" ] && ok "replaces the first as the proof" || bad "proof not replaced"
is "$(fetch "$H" "$DT")" 200 "the trip's Dispatcher opens it"
cmp -s /tmp/hp_got.img /tmp/hp_proof2.png && ok "the same bytes the relative sent" || bad "image bytes differ"
is "$(fetch "$H" "$OT")/$(fetch "$H" "$RT")" 200/200 "so do the Terminal Manager and the relative"
is "$(fetch "$H" "$PT")/$(fetch "$H" "$D2T")" 404/403 "not another passenger or another Dispatcher"
! find "$BACKEND/media" -name "$M2*" 2>/dev/null | grep -q . && [ -f "$BACKEND/storage/chat/$M2.png" ] \
  && ok "stored in storage/chat, not the public media folder" || bad "image location"
is "$(code POST /home-pickups/$H/proof/confirm "" "$OT")" 403 "the Terminal Manager does not confirm it: the Dispatcher confirms to them"
is "$(code POST /home-pickups/$H/proof/confirm "" "$D2T")" 403 "nor another Dispatcher"
is "$(code POST /home-pickups/$H/proof/confirm "" "$DT")" 200 "the trip's Dispatcher confirms it"
is "$(st "$HRB")/$(st "$HSB")/$(sql "SELECT CONCAT_WS('/', proof_confirmed_by, proof_message_id = '$M2') FROM assisted_pickups WHERE pickup_id = '$H'")" \
   "confirmed/confirmed/USER-DISPATCHER-0001/1" "both seats are paid; ProofConfirmedBy the Dispatcher"
is "$(sql "SELECT CONCAT(MIN(status), '/', COUNT(hold_expires_at)) FROM seat_inventory WHERE booking_id IN ('$HRB', '$HSB')")" booked/0 \
   "their spaces are booked, no longer on hold"
is "$(verified)" "$((V0 + 2))" "both seats count in V on the statement"
is "$(notes "$OT" home_pickup_proof)/$(notes "$CT" home_pickup_proof)" 1/0 "'Home Pickup Proof' to the Terminal Manager"
is "$(code POST /home-pickups/$H/proof/confirm "" "$DT")" 409 "not confirmed twice"
is "$(upload "$H" /tmp/hp_proof1.png "$RT")" 409 "no screenshot once both seats are paid"
is "$(code POST /home-pickups/$H/activate "" "$DT")" 200 "and the pickup can be activated"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. Cancelling and moving"
book "$PT" "$NEAR"; C=$PK; CRB=$RB; CSB=$SB
is "$(code POST /bookings/$CRB/cancel "" "$PT")" 200 "the relative cancels their own seat"
is "$(pk "$C")/$(st "$CSB")" "cancelled/-/-/cancelled" "the passenger's seat and the pickup go with it"
book "$PT" "$NEAR"; E=$PK; ERB=$RB; ESB=$SB
is "$(code POST /bookings/$ESB/cancel "" "$PT")" 200 "the relative cancels the passenger's seat"
is "$(pk "$E")/$(st "$ERB")" "cancelled/-/-/pending" "the pickup goes; the relative's seat stays theirs"
is "$(code POST /bookings/$ASB/reschedule '{"new_trip_id":"TRIP-A2Z-LIVE-SOON"}' "$PT")" 422 \
   "a home-pickup seat is not moved to another trip"
is "$(code POST /bookings/$ARB/reschedule '{"new_trip_id":"TRIP-A2Z-LIVE-SOON"}' "$PT")" 422 "nor the relative's"

book "$QT" "$NEAR"; G=$PK; GRB=$RB; GSB=$SB
pay "$GRB"; pay "$GSB"
ok "a third pickup is paid but never activated (the relative does not come)"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Departure and the stop at the pin"
is "$(code POST /home-pickups/$A/arrived "" "$DT")" 409 "the van goes to the pin only after it leaves"
code GET /trips/$TRIP/share "" "$CT" >/dev/null
code POST /trips/$TRIP/payment "{\"amount\":\"$(field "['amount_due']")\"}" "$CT" >/dev/null
is "$(code POST /trips/$TRIP/start "" "$CT")" 200 "share recorded, trip started"
is "$(code POST /trips/$TRIP/depart "" "$DT")" 200 "the Dispatcher departs"
is "$(st "$ASB")/$(st "$BSB")" confirmed/confirmed "activated pickups' seats are kept: they board after departure"
is "$(pk "$G")/$(st "$GSB")" "no_show/-/-/no_show" "a pickup never activated is a no-show, its seat owed"
is "$(code POST /home-pickups/$A/close '{"outcome":"boarded"}' "$DT")" 409 "the stop closes only once the van is at the pin"
is "$(code POST /home-pickups/$A/arrived "" "$D2T")" 403 "another Dispatcher cannot mark it"
is "$(code POST /home-pickups/$A/arrived "" "$DT")" 200 "the van is at the pin"
is "$(field "['status']")" arrived "Status 'arrived', ArrivedAt set"
is "$(code POST /home-pickups/$A/close '{"outcome":"aboard"}' "$DT")" 422 "an outcome other than boarded or no-show is refused"
is "$(code POST /home-pickups/$A/close '{"outcome":"boarded"}' "$DT")" 200 "the Dispatcher marks the passenger boarded"
is "$(sql "SELECT CONCAT_WS('/', status, closed_early, closed_by, left_at >= arrived_at) FROM assisted_pickups WHERE pickup_id = '$A'")/$(st "$ASB")" \
   "boarded/1/USER-DISPATCHER-0001/1/boarded" "inside the 10-minute wait: ClosedEarly, ClosedBy; the seat is boarded"

code POST /home-pickups/$B/arrived "" "$DT" >/dev/null
sql "UPDATE assisted_pickups SET arrived_at = arrived_at - INTERVAL 11 MINUTE WHERE pickup_id = '$B'"
is "$(code POST /home-pickups/$B/close '{"outcome":"no_show"}' "$DT")" 200 "after the wait, the passenger was not found"
is "$(sql "SELECT CONCAT_WS('/', status, closed_early) FROM assisted_pickups WHERE pickup_id = '$B'")/$(st "$BSB")" \
   "no_show/0/no_show" "not an early end; the seat is a no-show and still owed"
is "$(sql "SELECT COUNT(*) FROM seat_inventory WHERE booking_id = '$BSB'")" 0 "its space is released"
is "$(code POST /home-pickups/$B/close '{"outcome":"boarded"}' "$DT")" 409 "a closed stop is not closed again"

policy ""
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
