#!/usr/bin/env bash
# Release of unpaid reservations, and the Paid mark that arrives late
# (brief rev 721, 2.1 and 4.2 rule 15; T53-T56, T61-T63).
#
#   ./tests/integration/test_unpaid_release.sh
#
# A reservation is CONFIRMED and UNPAID from the moment it is made. It
# holds one of the 14 seats but is not on the passenger list and adds
# nothing to what the van owes, so the system releases it a set number of
# minutes before departure (`unpaid_cutoff_min`) and offers the seat to a
# walk-up. Only the Dispatcher's Mark as Paid stops that -- a check-in
# does not (T61).
#
# T57 (a boarding on an unpaid reservation) needs the van's door events
# and lives with them, in test_door_check.sh.
#
# The sweep is the same coroutine the server runs every 60 seconds; the
# script calls it directly rather than waiting for a tick, so a failure
# is a failure and not a clock.
#
# Needs: ./db/reset-dev.sh --soon  (the fixture trip departs in 20 min,
# with the cutoff left at 5 so nothing is released until this script
# raises it), and the backend running.
set -uo pipefail
cd "$(dirname "$0")/../.."

API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
LAT=7.052400; LNG=125.593100          # Ecoland Terminal
PASS_N=0; FAIL_N=0; GAP_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
gap() { printf '  \033[33mGAP \033[0m  %s\n' "$1"; GAP_N=$((GAP_N+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1', wanted '$2')"; }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}

# The release job itself, run once on demand.
sweep() {
  python3 - <<'PY'
import asyncio, sys
sys.path.insert(0, ".")
from app.core.db import SessionFactory
from app.application.booking.unpaid_release import release_unpaid_reservations
asyncio.run(release_unpaid_reservations(SessionFactory))
PY
}

MYSQL_PW=$(grep -m1 '^MYSQL_ROOT_PASSWORD=' ../.env | cut -d= -f2-)
db() {
  ( cd .. && docker compose exec -T -e MYSQL_PWD="$MYSQL_PW" \
      mysql mysql -u root --silent sabaygo -e "$1" 2>/dev/null )
}

curl -sf http://127.0.0.1:8000/health >/dev/null || { echo "API not running"; exit 1; }

# ═══════════════════════════════════════════════ 0. sign in
hdr "0. Accounts"
code POST /auth/login '{"email":"manager@sabaygo.dev","password":"sabaygo123"}' >/dev/null
OT=$(j "['access_token']" < /tmp/resp.json)
code POST /auth/login '{"email":"dispatcher@sabaygo.dev","password":"sabaygo123"}' >/dev/null
DT=$(j "['access_token']" < /tmp/resp.json)
[ -n "$OT" ] && [ -n "$DT" ] && ok "manager@ and dispatcher@ signed in" \
  || { bad "login failed"; exit 1; }

code POST /auth/register "{\"email\":\"rel${STAMP}@sabaygo.dev\",
  \"phone_number\":\"0919${STAMP: -7}\",\"password\":\"sabaygo123\",
  \"first_name\":\"Unpaid\",\"last_name\":\"Rider\"}" >/dev/null
PT=$(j "['access_token']" < /tmp/resp.json)
[ -n "$PT" ] && ok "a passenger registered" || { bad "register failed"; exit 1; }

reserve() {   # -> booking_id, via $BID / $CODE
  code POST /bookings/reserve \
    "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
  BID=$(j "['booking_id']" < /tmp/resp.json)
  CODE=$(j "['booking_code']" < /tmp/resp.json)
}
mine() { code GET "/bookings/$1" "" "$PT" >/dev/null; j "['$2']" < /tmp/resp.json; }
free_seats() { db "SELECT COUNT(DISTINCT seat_number) FROM seat_inventory
                    WHERE trip_id='$TRIP' AND status='available' AND leg_sequence=1"; }
listed() { code GET "/trips/$TRIP/door-check" "" "$DT" >/dev/null; j "['listed']" < /tmp/resp.json; }

# ═══════════════════════════════════════════════ T53 reserve
hdr "T53  a reservation holds a seat but is not on the list"
BEFORE_FREE=$(free_seats); BEFORE_LISTED=$(listed)
reserve; A=$BID; A_CODE=$CODE
echo "$A_CODE" | grep -qE '^SG-[A-HJ-NP-Z2-9]{6}$' \
  && ok "booking code is the short spoken form: $A_CODE" \
  || bad "booking code '$A_CODE' is not the SG-XXXXXX form"
is "$(mine "$A" payment_status)" "unpaid" "the reservation is unpaid"
is "$(mine "$A" status)" "confirmed" "and confirmed -- there is nothing to wait for"
is "$(free_seats)" "$((BEFORE_FREE - 1))" "it took one of the 14 seats"
is "$(listed)" "$BEFORE_LISTED" "but it is not on the passenger list"
S=$(code GET "/bookings/trip/$TRIP/seats?q=$A_CODE" "" "$DT")
is "$S" "200" "the Dispatcher finds it by booking code"
is "$(j "[0]['payment_status']" < /tmp/resp.json)" "unpaid" "shown to them as unpaid"

# ═══════════════════════════════════════════════ T54 the cash
hdr "T54  the Dispatcher takes the cash, with a connection and without"
S=$(code POST "/bookings/$A/mark-paid" '{}' "$DT")
is "$S" "200" "mark paid accepted"
is "$(j "['payment_status']" < /tmp/resp.json)" "paid" "the seat is paid"
is "$(j "['restored']" < /tmp/resp.json)" "False" "nothing to restore -- it was never released"
[ -n "$(mine "$A" paid_at)" ] && ok "paid_at is recorded" || bad "paid_at is empty"
is "$(listed)" "$((BEFORE_LISTED + 1))" "and now it is on the passenger list"

# Offline: the device sends the moment it recorded, not the moment it synced.
reserve; B=$BID; B_CODE=$CODE
WHEN=$(date -d '4 minutes ago' '+%Y-%m-%dT%H:%M:%S')
S=$(code POST "/bookings/$B/mark-paid" "{\"paid_at\":\"$WHEN\"}" "$DT")
is "$S" "200" "a mark queued offline is accepted on sync"
is "$(mine "$B" paid_at | cut -c1-16)" "$(echo "$WHEN" | cut -c1-16)" \
   "and keeps the time the Dispatcher's phone recorded"
S=$(code POST "/bookings/$B/mark-paid" '{}' "$DT")
is "$S" "200" "a replayed mark is accepted and changes nothing"
is "$(mine "$B" paid_at | cut -c1-16)" "$(echo "$WHEN" | cut -c1-16)" \
   "the offline time survives the replay"

# ═══════════════════════════════════════════════ T56 forgot to cancel
hdr "T56  the Dispatcher clears a reservation nobody came for"
reserve; C=$BID
S=$(code POST "/bookings/$C/dispatcher-cancel" '{"reason":"forgot_to_cancel"}' "$DT")
is "$S" "200" "cancelled as forgot_to_cancel"
is "$(mine "$C" cancel_reason)" "forgot_to_cancel" "the reason is on the booking"
is "$(db "SELECT cancelled_by IS NOT NULL FROM bookings WHERE booking_id='$C'")" "1" \
   "with the Dispatcher's name against it"
is "$(listed)" "$((BEFORE_LISTED + 2))" "nothing is owed on it: the list is unchanged"

# ═══════════════════════════════════════════════ T55 the release
hdr "T55  an unpaid reservation reaches the cutoff"
reserve; D=$BID; D_CODE=$CODE
# The fixture trip departs in 20 minutes, so a 60-minute cutoff is past.
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"60"}' "$OT" >/dev/null
BEFORE_SWEEP_FREE=$(free_seats)
sweep
is "$(mine "$D" status)" "cancelled" "the job released it"
is "$(mine "$D" cancel_reason)" "auto_release" "recorded as auto_release"
is "$(db "SELECT cancelled_by IS NULL FROM bookings WHERE booking_id='$D'")" "1" \
   "with nobody's name against it -- no person decided it"
is "$(free_seats)" "$((BEFORE_SWEEP_FREE + 1))" "the seat is free for a walk-up"
N=$(db "SELECT COUNT(*) FROM notifications WHERE related_entity_id='$D'
          AND title='Reservation released'")
is "$N" "1" "the passenger is told"
is "$(mine "$A" payment_status)" "paid" "the seat marked Paid is untouched"
is "$(mine "$A" status)" "confirmed" "and still stands"

sweep
is "$(db "SELECT COUNT(*) FROM notifications WHERE related_entity_id='$D'")" "1" \
   "a second sweep finds nothing left to do"

# ═══════════════════════════════════ the reminder before the cutoff
hdr "Before the cutoff, the passenger is reminded to pay"
# Brief 2.1 asks for a reminder and names no interval, so it is sent one
# cutoff-length before the cutoff. Set the cutoff just inside the trip's
# remaining time and the fixture lands in that window.
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"5"}' "$OT" >/dev/null
reserve; H=$BID
code GET "/bookings/$H" "" "$PT" >/dev/null
LEFT=$(python3 -c "
import datetime as d, json
dep = d.datetime.fromisoformat(json.load(open('/tmp/resp.json'))['departure_datetime'])
print(int((dep.replace(tzinfo=None) - d.datetime.now()).total_seconds() // 60))" 2>/dev/null)
if [ "${LEFT:-0}" -ge 5 ]; then
  code PUT /config/policies/unpaid_cutoff_min "{\"policy_value\":\"$((LEFT - 2))\"}" "$OT" >/dev/null
  sweep
  is "$(mine "$H" status)" "confirmed" "the reservation still stands: the cutoff is not here yet"
  N=$(db "SELECT COUNT(*) FROM notifications WHERE related_entity_id='$H'
            AND type='departure_reminder'")
  is "$N" "1" "but the passenger has been reminded to pay at the terminal"
  sweep
  is "$(db "SELECT COUNT(*) FROM notifications WHERE related_entity_id='$H'
             AND type='departure_reminder'")" "1" \
     "and reminded once, however often the job runs"
else
  gap "the fixture trip departs in ${LEFT:-?} min -- too close to test the reminder window"
fi

# ═══════════════════════════════════════════════ T61 check-in does not save it
hdr "T61  a check-in does not hold the seat"
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"5"}' "$OT" >/dev/null
reserve; E=$BID
S=$(code POST "/bookings/$E/check-in" \
  "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" "$PT")
if [ "$S" = "200" ]; then
  ok "the passenger is at the terminal (checked in)"
  is "$(mine "$E" status)" "checked_in" "the booking says so"
else
  gap "check-in gave $S -- the window may be shut; the release is tested anyway"
fi
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"60"}' "$OT" >/dev/null
sweep
is "$(mine "$E" status)" "cancelled" "released anyway: being there is not paying"
is "$(mine "$E" cancel_reason)" "auto_release" "same reason as any other release"

# ═══════════════════════════════════════════════ T62 paid after the release
hdr "T62  a Paid mark syncs after the release, and the trip has a seat"
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"5"}' "$OT" >/dev/null
reserve; F=$BID; F_CODE=$CODE
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"60"}' "$OT" >/dev/null
sweep
is "$(mine "$F" status)" "cancelled" "the server released it first"
WHEN=$(date -d '8 minutes ago' '+%Y-%m-%dT%H:%M:%S')
S=$(code POST "/bookings/$F/mark-paid" "{\"paid_at\":\"$WHEN\"}" "$DT")
is "$S" "200" "the offline mark is accepted"
is "$(j "['restored']" < /tmp/resp.json)" "True" "and the reservation is restored"
is "$(mine "$F" status)" "confirmed" "the seat stands again"
is "$(mine "$F" payment_status)" "paid" "as paid"
is "$(mine "$F" cancel_reason)" "None" "the cancellation is cleared"
is "$(db "SELECT COUNT(*) FROM seat_inventory
            WHERE booking_id='$F' AND status='booked'")" "3" \
   "and it holds a seat on every leg of its journey again"
N=$(db "SELECT COUNT(*) FROM notifications WHERE related_entity_id='$F'
          AND title='Your seat is back'")
is "$N" "1" "the passenger is told the seat came back"

# ═══════════════════════════════════════════════ T63 ... and the trip is full
hdr "T63  the same, but a walk-up has taken the seat"
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"5"}' "$OT" >/dev/null
reserve; G=$BID; G_CODE=$CODE
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"60"}' "$OT" >/dev/null
sweep
is "$(mine "$G" status)" "cancelled" "released at the cutoff"

# Fill the van with walk-ups, as a terminal would while the list is open.
FILLED=0
while [ "$(free_seats)" -gt 0 ] && [ "$FILLED" -lt 20 ]; do
  S=$(code POST /bookings/walk-in \
    "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$DT")
  [ "$S" = "201" ] || break
  FILLED=$((FILLED + 1))
done
is "$(free_seats)" "0" "the trip is full ($FILLED walk-up(s) listed)"

BEFORE_ALERTS=$(db "SELECT COUNT(*) FROM notifications WHERE type='paid_after_release'")
S=$(code POST "/bookings/$G/mark-paid" '{}' "$DT")
is "$S" "200" "the late mark is still accepted -- the cash is real"
is "$(j "['seat_gone']" < /tmp/resp.json)" "True" "but the seat is gone"
is "$(j "['restored']" < /tmp/resp.json)" "False" "so nothing is restored"
is "$(mine "$G" status)" "cancelled" "the reservation stays cancelled"
is "$(mine "$G" payment_status)" "unpaid" "and nothing is added to what the van owes"
AFTER_ALERTS=$(db "SELECT COUNT(*) FROM notifications WHERE type='paid_after_release'")
is "$AFTER_ALERTS" "$((BEFORE_ALERTS + 1))" \
   "the Terminal Manager is alerted to settle it with the Dispatcher"
is "$(db "SELECT audience FROM notifications WHERE type='paid_after_release'
            AND related_entity_id='$G'")" "terminal_manager" "addressed to the office"

# ═══════════════════════════════════════════════ the setting
hdr "The cutoff is a setting, not a constant"
code GET /config/policies "" "$OT" >/dev/null
grep -q unpaid_cutoff_min /tmp/resp.json \
  && ok "unpaid_cutoff_min is in Rules & Settings" || bad "the setting is missing"
grep -qE 'seat_hold_ttl_seconds|hold_sweep_interval_seconds' /tmp/resp.json \
  && bad "a retired seat-hold setting is still offered" \
  || ok "the gateway-era seat-hold settings are gone (T60)"
code PUT /config/policies/unpaid_cutoff_min '{"policy_value":"30"}' "$OT" >/dev/null
code GET /config/policies "" "$OT" >/dev/null
is "$(python3 -c "
import json
print(next(p['policy_value'] for p in json.load(open('/tmp/resp.json'))
           if p['policy_key'] == 'unpaid_cutoff_min'))" 2>/dev/null)" "30" \
   "and it is back at its shipped 30 minutes"

printf '\n  passed %d   failed %d   gaps %d\n\n' "$PASS_N" "$FAIL_N" "$GAP_N"
