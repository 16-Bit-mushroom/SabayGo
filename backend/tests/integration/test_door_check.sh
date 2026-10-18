#!/usr/bin/env bash
# Rev 603 R5a: door events checked against the passenger list before
# departure (change brief 2.4, 6.1; T22-T25).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_door_check.sh
#
# Plays the phone in ABC-1234 on TRIP-DEMO-00000001 (dispatcher@, departs
# in 20 min). Times are moved with SQL where a record must sit a known
# distance from a boarding: the match window is 120 s.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP=TRIP-DEMO-00000001
STAMP=$(date +%s)
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }
field() { j "['$1']" < /tmp/dc.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/dc.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
edge() {
  local a=(-s -o /tmp/dc.json -w "%{http_code}" -X "$1" "$API$2" -H "X-Device-Token: $TOK")
  [ -n "${3:-}" ] && a+=(-H "Content-Type: application/json" -d "$3")
  curl "${a[@]}"
}
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  field access_token
}
uuid() { python3 -c "import uuid;print(uuid.uuid4())"; }
# board ID OFFSET_S [alight]: one door event, OFFSET seconds from now
door() {
  python3 -c "
import datetime as d, json, sys
print(json.dumps({'events': [{'event_id': sys.argv[1], 'event_type': sys.argv[3] if len(sys.argv) > 3 else 'board',
  'event_at': (d.datetime.now() + d.timedelta(seconds=int(sys.argv[2]))).isoformat()}]}))" "$@"
}
send() { edge POST /edge/events "$(door "$@")" >/dev/null; }
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
chk() { code GET /trips/$TRIP/door-check "" "$DT" >/dev/null; printf '%s/%s/%s' "$(field aboard)" "$(field listed)" "$(field excess)"; }
ev() { sql "SELECT CONCAT(COALESCE(match_status, '-'), '/', resolution_status) FROM passenger_events WHERE event_id = '$1'"; }
notes() {
  code GET "/notifications?limit=100" "" "$OT" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/dc.json'))['items'] if n['type']=='$1' and n['related_entity_id']=='$TRIP'))"
}
board_status() { sql "SELECT status FROM trips WHERE trip_id = '$TRIP'"; }
walkin() { code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":3${1:+,\"for_event_id\":\"$1\"}}" "${2:-$DT}"; }

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); D2T=$(login dispatcher2)
PT=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" \
  -d "{\"email\":\"dc${STAMP}@sabaygo.dev\",\"phone_number\":\"0918${STAMP: -7}\",\"password\":\"sabaygo123\",\"first_name\":\"Door\",\"last_name\":\"Check\"}" | j "['access_token']")
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$PT" ] && ok "signed in" || { bad "login"; exit 1; }

code POST /devices '{"device_model":"realme 8 5G door check"}' "$OT" >/dev/null
PHONE=$(field device_id); TOK=$(field device_token)
code POST /devices/$PHONE/checkout '{"van_id":"VAN-0001","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT" >/dev/null
sql "UPDATE device_checkouts SET checked_out_at = NOW() - INTERVAL 40 MINUTE WHERE device_id = '$PHONE'"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. The list: a QR ticket and a cash entry"
code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT" >/dev/null
BID=$(field booking_id); QR=$(field qr_payload)
(cd "$BACKEND" && venv/bin/python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1)
is "$(code POST /scans "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$DT")/$(field result)" 200/valid \
   "the Dispatcher scans the ticket"
sql "UPDATE boarding_scans SET scanned_at = scanned_at - INTERVAL 10 MINUTE WHERE booking_id = '$BID'"
is "$(walkin)" 201 "and lists a cash passenger"
is "$(chk)" 0/2/0 "T22 nobody counted aboard yet, 2 listed: fewer aboard is a no-show, nothing to do"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Boardings matched by time (6.1)"
EQ=$(uuid); EL=$(uuid)
send "$EQ" -570; send "$EL" -60
is "$(ev "$EQ")" matched_qr/not_needed "a boarding 30 s after the scan: Matched_QR"
is "$(ev "$EL")" matched_log/not_needed "a boarding 1 min before the cash entry: Matched_Log"
is "$(chk)" 2/2/0 "2 aboard, 2 listed"
U1=$(uuid); send "$U1" -1200
is "$(ev "$U1")" unlisted/pending "a boarding with no scan or entry within 2 min: Unlisted, pending"
is "$(chk)" 3/2/1 "3 aboard against 2 listed"
python3 -c "import json;u=json.load(open('/tmp/dc.json'))['unlisted'];assert [x['event_id'] for x in u]==['$U1']" \
  && ok "the Dispatcher's screen names the boarding" || bad "unlisted list"
is "$(code GET /trips/$TRIP/door-check "" "$D2T")" 403 "another Dispatcher cannot read it"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. More aboard than listed stops Depart (T23)"
code GET /trips/$TRIP/share "" "$CT" >/dev/null
code POST /trips/$TRIP/payment "{\"amount\":\"$(field amount_due)\"}" "$CT" >/dev/null
is "$(code POST /trips/$TRIP/start "" "$CT")" 200 "share recorded, trip started"
is "$(code POST /trips/$TRIP/depart "" "$DT")" 409 "T23 Depart is refused"
field detail | grep -q "3 aboard and 2 listed" && ok "and says 3 aboard, 2 listed" || bad "detail: $(field detail)"
is "$(code POST /trips/$TRIP/depart "" "$CT")" 409 "the office's Depart too"
is "$(walkin "$EQ")" 409 "a matched boarding needs no fix"
is "$(walkin "$U1")" 201 "the Dispatcher lists the person, with a destination"
is "$(ev "$U1")" unlisted/listed "ResolutionStatus Listed"
is "$(chk)" 3/3/0 "3 aboard, 3 listed"
code GET /trips/$TRIP/share "" "$CT" >/dev/null
python3 -c "import json;s=json.load(open('/tmp/dc.json'));assert any(l['is_top_up'] for l in s['lines'])" \
  && ok "a seat added after the payment is a top-up (T7)" || bad "no top-up line"

U2=$(uuid); send "$U2" -1500
is "$(chk)" 4/3/1 "another boarding nobody listed"
is "$(code POST /door-events/$U2/explain '{"note":"x"}' "$DT")" 422 "a reason needs words"
is "$(code POST /door-events/$U2/explain '{"note":"Operator'"'"'s son, rides free to Toril"}' "$D2T")" 404 \
   "another Dispatcher cannot explain it"
is "$(code POST /door-events/$U2/explain '{"note":"Operator'"'"'s son, rides free to Toril"}' "$DT")" 200 \
   "the Dispatcher types a reason"
is "$(ev "$U2")" unlisted/explained "ResolutionStatus Explained"
[ "$(sql "SELECT resolved_by FROM passenger_events WHERE event_id = '$U2'")" = USER-DISPATCHER-0001 ] \
  && ok "with who" || bad "resolved_by"
is "$(chk)" 4/3/0 "nothing left to resolve"
is "$(code POST /door-events/$U2/explain '{"note":"again"}' "$DT")" 409 "a resolved boarding is not resolved twice"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. The crew is not a passenger (2.3)"
code PUT /trips/$TRIP/crew '{"aboard":true}' "$DT" >/dev/null
CR=$(uuid); send "$CR" -30
is "$(chk)" 4/3/0 "the Dispatcher climbs in as crew: still 4 aboard"
OUT=$(uuid); send "$OUT" -20 alight
is "$(chk)" 3/3/0 "someone steps out before departure: 3 aboard"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Depart, and after"
is "$(code POST /trips/$TRIP/depart "" "$DT")" 200 "the Dispatcher departs"
is "$(notes departed_more_than_listed)" 0 "the list was right: no alert"
ROAD=$(uuid); send "$ROAD" 5
is "$(ev "$ROAD")/$(sql "SELECT pre_departure FROM passenger_events WHERE event_id = '$ROAD'")" "-/not_needed/0" \
   "T25 a boarding by the road after departure: not matched, not flagged"
is "$(chk)" 3/3/0 "and the before-departure count is unchanged"

hdr "6. A phone that was offline shows the van left with more (T24)"
LATE=$(uuid); send "$LATE" -1700
is "$(ev "$LATE")" unlisted/pending "a boarding from before departure, uploaded now: Unlisted"
is "$(chk)/$(notes departed_more_than_listed)" 4/3/0/0 \
   "the count rules, not the event: 4 aboard = 3 listed + 1 explained, no alert"
LATE2=$(uuid); send "$LATE2" -1750
is "$(chk)" 5/3/1 "a second one: 5 aboard"
is "$(notes departed_more_than_listed)" 1 "T24 'Departed With More Than Listed' to the Terminal Manager"
LATE3=$(uuid); send "$LATE3" -1780
is "$(notes departed_more_than_listed)" 1 "once per trip"
is "$(code POST /door-events/$LATE/explain '{"note":"too late"}' "$DT")" 409 "after departure it is no longer resolved"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. The van held to 14 (2.3; T25)"
# many TYPE COUNT FROM_S [LAT LON]: COUNT door events a second apart
many() {
  python3 -c "
import datetime as d, json, sys, uuid
t, n, f = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ev = [{'event_id': str(uuid.uuid4()), 'event_type': t,
       'event_at': (d.datetime.now() + d.timedelta(seconds=f + i)).isoformat()} for i in range(n)]
if len(sys.argv) > 5: ev[-1].update(latitude=float(sys.argv[4]), longitude=float(sys.argv[5]))
print(json.dumps({'events': ev}))" "$@"
}
aboard() { sql "SELECT SUM(IF(event_type = 'board', 1, -1)) - 1 FROM passenger_events WHERE trip_id = '$TRIP'"; }
caps() {  # caps TOKEN: the capacity alerts this person has about the trip, one message per line
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;[print(n['message']) for n in json.load(open('/tmp/dc.json'))['items'] if n['type']=='capacity_alert' and '$TRIP_LABEL' in n['message']]"
}
code GET /trips/$TRIP/stops "" "$OT" >/dev/null
read -r S2 S3 MLAT MLON LAT3 LON3 < <(python3 -c "
import json;s=json.load(open('/tmp/dc.json'));a,b=s[1],s[2]
print(a['terminal_name'].replace(' ','_'),b['terminal_name'].replace(' ','_'),(a['latitude']+b['latitude'])/2,(a['longitude']+b['longitude'])/2,b['latitude'],b['longitude'])")
S2=${S2//_/ }; S3=${S3//_/ }
TRIP_LABEL=$(sql "SELECT plate_number FROM vans WHERE van_id = 'VAN-0001'")
FILL=$(( 14 - $(aboard) ))
edge POST /edge/events "$(many board $FILL 6)" >/dev/null
is "$(aboard)/$(caps "$OT" | wc -l)" 14/0 "14 aboard: no alert"
edge POST /edge/events "$(many board 1 30 "$MLAT" "$MLON")" >/dev/null
is "$(aboard)" 15 "a 15th boards between $S2 and $S3"
caps "$OT" | grep -q "15 aboard.*between $S2 and $S3" && ok "T25 'Capacity Alert' with the time and the place: between $S2 and $S3" \
  || bad "alert: $(caps "$OT")"
is "$(caps "$CT" | wc -l)/$(caps "$DT" | wc -l)" 1/1 "to the Cashier and the Dispatcher too"
is "$(sql "SELECT CONCAT(stretch_no, '/', nearest_stop_sequence IS NOT NULL, '/', distance_from_start_m > 0) FROM passenger_events WHERE trip_id = '$TRIP' ORDER BY event_at DESC LIMIT 1")" 2/1/1 \
   "the event is geotagged: stretch 2, nearest stop, distance from the start"
edge POST /edge/events "$(many board 1 31)" >/dev/null
is "$(aboard)/$(caps "$OT" | wc -l)" 16/1 "still above 14: no second alert"
edge POST /edge/events "$(many alight 2 32)" >/dev/null
edge POST /edge/fixes "{\"fixes\":[{\"recorded_at\":\"$(date -d '+35 sec' '+%Y-%m-%dT%H:%M:%S')\",\"latitude\":$LAT3,\"longitude\":$LON3},{\"recorded_at\":\"$(date -d '+39 sec' '+%Y-%m-%dT%H:%M:%S')\",\"latitude\":$LAT3,\"longitude\":$LON3}]}" >/dev/null
edge POST /edge/events "$(many board 1 37)" >/dev/null
is "$(aboard)" 15 "two step out, one boards: 15 again"
caps "$OT" | grep -q "15 aboard.*at $S3" && ok "a new crossing, a new alert: placed from the GPS readings, at $S3" \
  || bad "second alert: $(caps "$OT")"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "8. Nobody left aboard (4.1; T47)"
edge POST /edge/events "$(many alight 13 40)" >/dev/null
is "$(aboard)/$(board_status)" 2/departed "T47 two still aboard: the trip stays open"
edge POST /edge/events "$(many alight 2 60)" >/dev/null
is "$(board_status)" completed "the last one steps out: Completed"
is "$(sql "SELECT TIMESTAMPDIFF(SECOND, NOW(), completed_at) BETWEEN 55 AND 65 FROM trips WHERE trip_id = '$TRIP'")" 1 \
   "dated by that alighting"
# This test dates its events up to a minute ahead; once that minute is past:
sql "UPDATE trips SET completed_at = NOW() - INTERVAL 1 SECOND WHERE trip_id = '$TRIP'"
edge GET /edge/session >/dev/null
is "$(field counting)" False "and once it has passed, the phone pauses"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "9. The Terminal Manager's Boarding Audit (brief 9)"
audit() {  # audit EXPR [DATE] -> EXPR evaluated on this trip's row (t), or NONE
  code GET "/boarding-audit${2:+?date=$2}" "" "$OT" >/dev/null
  python3 -c "
import json, sys
t = next((x for x in json.load(open('/tmp/dc.json')) if x['trip_id'] == '$TRIP'), None)
print('NONE' if t is None else eval(sys.argv[1]))" "$1"
}
is "$(code GET /boarding-audit "" "$CT")/$(code GET /boarding-audit "" "$DT")" 403/403 \
   "the Terminal Manager's alone: not the Cashier, not the Dispatcher"
is "$(audit "'/'.join(u['resolution_status'] for u in t['unlisted'])")" "pending/pending/pending/explained/listed/pending" \
   "every unlisted boarding before departure, in time order: 3 uploaded late, 1 reason, 1 fix, the crew"
is "$(audit "t['crew_aboard']")" True "the Dispatcher marked themselves crew: the last boarding is theirs"
is "$(audit "[u for u in t['unlisted'] if u['event_id']=='$U1'][0]['listed_destination']")" "$S3" \
   "the fix names the person's destination: $S3"
is "$(audit "[u for u in t['unlisted'] if u['event_id']=='$U2'][0]['resolution_note']")" "Operator's son, rides free to Toril" \
   "the reason is kept"
[ "$(audit "[u for u in t['unlisted'] if u['event_id']=='$U2'][0]['resolved_by']")" != None ] \
  && ok "with the Dispatcher who gave it" || bad "resolved_by"
is "$(audit "' | '.join(f\"{c['aboard']} of {c['seat_capacity']} {c['place']}\" for c in t['capacity_alerts'])")" \
   "15 of 14 between $S2 and $S3 | 15 of 14 at $S3" "both capacity alerts, with the number aboard and the general place"
audit "t['departed_with_more']" | grep -q "more aboard than its passenger list" \
  && ok "the departure with more aboard than listed" || bad "departed: $(audit "t['departed_with_more']")"
is "$(audit "f\"{t['chain_verified']}/{t['chain_events']}\"")" "True/$(sql "SELECT COUNT(*) FROM passenger_events WHERE trip_id = '$TRIP'")" \
   "the hash chain holds over every event"
is "$(audit "f\"{t['operator_name'] is not None}/{t['plate_number']}/{t['dispatcher_name'] is not None}\"")" "True/$TRIP_LABEL/True" \
   "the operator, the van and the Dispatcher"
is "$(audit "t['unlisted'][0]['has_snapshot']")" False "no still was sent, and none is pretended"
is "$(audit "t" "$(date -d yesterday +%F)")" NONE "another day's audit does not show it"
code GET "/config/trips?date=$(date +%F)" "" "$CT" >/dev/null
is "$(python3 -c "import json;t=next(x for x in json.load(open('/tmp/dc.json')) if x['trip_id']=='$TRIP');print(t['door_aboard'], t['phone_silent'], t['phone_last_report_at'])")" \
   "0 True None" "Trip Monitoring: the camera's count (0, everyone off) and the phone out with the van, silent (no report yet)"

code POST /devices/$PHONE/return '{}' "$CT" >/dev/null
printf '\n%d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
