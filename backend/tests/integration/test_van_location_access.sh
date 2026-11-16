#!/usr/bin/env bash
# 12 Nov, the group's decision C5: who may see where a van is.
#
#   A van's position is its driver's (the operator always drives, and the
#   plate is on every trip). Until today GET /tracking/trips/{id}/position
#   and /history were open to anyone, and the open trip search hands out
#   every trip id. Now (application/tracking/access.py):
#
#   - nobody signed out sees any van              -> 401
#   - a passenger sees only a trip they hold a seat on (confirmed, checked
#     in or boarded), and only while it is boarding or on the road:
#       no seat, a cancelled seat or a no-show    -> 403, in plain words
#       the trip has not started boarding         -> 404 with a sentence
#       the trip has ended (no trail afterwards)  -> 404 with a sentence
#   - the office and the crew see every van, live and afterwards.
#
#   Uses the demo's live trips: LIVE-BOARD (passenger@ confirmed, ana
#   confirmed), LIVE-DEPART (jenny boarded, ana a no-show), LIVE-SOON
#   (jenny confirmed, scheduled), and yesterday's TAG-P1-0600 (liza
#   boarded, completed). Positions are written straight to the table, so
#   no ping can depart a trip or raise a driving flag.
#
#   ./db/reset-dev.sh && ./tests/integration/test_van_location_access.sh
set -uo pipefail

API="${SABAYGO_API:-http://127.0.0.1:8000/api/v1}"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
# code PATH TOKEN -> HTTP status of a GET; the body is in $TMP/r.json
code() {
  local a=(-s -o "$TMP/r.json" -w "%{http_code}" "$API$1")
  [ -n "${2:-}" ] && a+=(-H "Authorization: Bearer $2")
  curl "${a[@]}"
}
py() { python3 -c "import json,sys; d=json.load(open('$TMP/r.json')); $1"; }
login() {
  curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))"
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

BOARD=TRIP-A2Z-LIVE-BOARD; DEPART=TRIP-A2Z-LIVE-DEPART
SOON=TRIP-A2Z-LIVE-SOON;   DONE=TRIP-A2Z-TAG-P1-0600

hdr "Set-up"
PT=$(login passenger); LT=$(login liza); AT=$(login ana); JT=$(login jenny)
DT=$(login dispatcher); MT=$(login manager); CT=$(login cashier)
for t in "$PT" "$LT" "$AT" "$JT" "$DT" "$MT" "$CT"; do [ -n "$t" ] || { bad "login"; exit 1; }; done
ok "signed in: three passengers, a fourth, the Dispatcher, the office"
S=$(sql "SELECT GROUP_CONCAT(status ORDER BY trip_id) FROM trips WHERE trip_id IN ('$BOARD','$DEPART','$SOON','$DONE')")
is "$S" "boarding,departed,scheduled,completed" "the four trips are boarding, on the road, scheduled and completed"
sql "DELETE FROM trip_location_pings WHERE trip_id IN ('$BOARD','$DEPART','$DONE')"
sql "INSERT INTO trip_location_pings (trip_id, van_id, latitude, longitude, speed_kph,
       nearest_stop_sequence, distance_to_stop_m, recorded_at, received_at) VALUES
     ('$BOARD',  'VAN-0003', 7.052600, 125.593300,  0, 1,   0, NOW(6) - INTERVAL 20 SECOND, NOW(6)),
     ('$BOARD',  'VAN-0003', 7.052610, 125.593310,  0, 1,   0, NOW(6) - INTERVAL 5 SECOND,  NOW(6)),
     ('$DEPART', 'VAN-0005', 7.010000, 125.500000, 40, 1, 900, NOW(6) - INTERVAL 10 SECOND, NOW(6)),
     ('$DONE',   'VAN-0003', 7.200000, 125.700000, 50, 2, 300, NOW(6) - INTERVAL 30 HOUR,   NOW(6) - INTERVAL 30 HOUR),
     ('$DONE',   'VAN-0003', 7.300000, 125.750000, 45, 3, 200, NOW(6) - INTERVAL 29 HOUR,   NOW(6) - INTERVAL 29 HOUR)" >/dev/null
ok "positions written for the boarding, departed and completed trips"

hdr "Signed out: no van at all"
is "$(code /tracking/trips/$BOARD/position)"  401 "a boarding van's position needs a sign-in"
is "$(code /tracking/trips/$DEPART/position)" 401 "a van on the road needs a sign-in"
is "$(code /tracking/trips/$DONE/history)"    401 "a finished trip's trail needs a sign-in"
is "$(code /tracking/trips/$BOARD/history)"   401 "a live trail needs a sign-in"
is "$(code /trips/terminals)" 200 "finding terminals and trips still needs no account"

hdr "A passenger with a seat, while the trip runs"
is "$(code /tracking/trips/$BOARD/position "$PT")" 200 "passenger@ (confirmed) sees the boarding van"
is "$(py 'print(d["plate_number"] is not None and d["trip_id"])')" "$BOARD" "  with its plate, to find it at the terminal"
is "$(code /tracking/trips/$BOARD/history "$PT")" 200 "  and the trail so far"
is "$(py 'print(len(d))')" 2 "  both points of it"
is "$(code /tracking/trips/$DEPART/position "$JT")" 200 "jenny (boarded) sees the van on the road"
is "$(code /tracking/trips/$DEPART/history "$JT")" 200 "  and its trail"
is "$(code /tracking/trips/$BOARD/position "$LT")" 200 "liza (checked in) sees the boarding van"

hdr "A passenger without a seat on that trip"
is "$(code /tracking/trips/$DEPART/position "$PT")" 403 "passenger@ cannot see a van they have no seat on"
is "$(py 'print("seat on this trip" in json.dumps(d))')" True "  told why, in plain words"
is "$(code /tracking/trips/$DEPART/history "$PT")" 403 "  nor its trail"
is "$(code /tracking/trips/$DEPART/position "$AT")" 403 "ana, a no-show on that trip, cannot follow it"
sql "UPDATE bookings SET status = 'cancelled' WHERE booking_id = 'BKG-A2Z-L104'" >/dev/null
is "$(code /tracking/trips/$BOARD/position "$AT")" 403 "ana, with the seat cancelled, cannot see the boarding van"
sql "UPDATE bookings SET status = 'confirmed' WHERE booking_id = 'BKG-A2Z-L104'" >/dev/null
is "$(code /tracking/trips/$BOARD/position "$AT")" 200 "  and can again with the seat back"
is "$(code /tracking/trips/TRIP-NO-SUCH-TRIP/position "$PT")" 404 "a trip that does not exist is not found"

hdr "Before boarding and after arrival"
is "$(code /tracking/trips/$SOON/position "$JT")" 404 "jenny's later trip: nothing shown before boarding"
is "$(py 'print("starts boarding" in json.dumps(d))')" True "  said as when it will show"
is "$(code /tracking/trips/$DONE/position "$LT")" 404 "liza's trip of yesterday: the van is no longer shown"
is "$(py 'print("has ended" in json.dumps(d))')" True "  said as the trip having ended"
is "$(code /tracking/trips/$DONE/history "$LT")" 404 "  and no trail of where it went"

hdr "The office and the crew see every van"
is "$(code /tracking/trips/$DEPART/position "$DT")" 200 "the Dispatcher sees a van not on their own trip"
is "$(code /tracking/trips/$DEPART/position "$CT")" 200 "the Cashier sees the van on the road"
is "$(code /tracking/trips/$DONE/history "$MT")" 200 "the Terminal Manager reads a finished trip's trail (flags, disputes)"
is "$(py 'print(len(d))')" 2 "  all of it"
is "$(code /tracking/trips/$SOON/position "$MT")" 404 "a trip with no report yet is not found, never an invented position"
is "$(code /tracking/fleet "$PT")" 403 "the fleet map stays the office's and crew's"

sql "DELETE FROM trip_location_pings WHERE trip_id IN ('$BOARD','$DEPART','$DONE')" >/dev/null

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
