#!/usr/bin/env bash
# Rev 603 R8: evidence retention (change brief 4.5; T36-T41 b).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_retention.sh
#
# Two phones count on TRIP-DEMO-00000001 and -02 (ABC-1234, XYZ-9876,
# dispatcher@). GPS readings, a driving flag (R9 computes them) and chat
# images are written with SQL. The job is called directly, with "now"
# moved 31 days ahead, so nothing hashed into the chain is backdated.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TRIP1=TRIP-DEMO-00000001; TRIP2=TRIP-DEMO-00000002
DONE=TRIP-A2Z-TAG-P1-0600   # completed yesterday, VAN-0003
SNAP=$(mktemp -d); trap 'rm -rf "$SNAP"' EXIT
P=0; F=0
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
field() { j "$1" < /tmp/rt.json; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/rt.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"
}
edge() { curl -s -o /tmp/rt.json -w "%{http_code}" -X POST "$API$1" -H "X-Device-Token: $3" -H "Content-Type: application/json" -d "$2"; }
up() { curl -s -o /tmp/rt.json -w "%{http_code}" -X PUT "$API/edge/events/$1/snapshot" -H "X-Device-Token: $2" -F "image=@$3"; }
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  field "['access_token']"
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
retention() {  # retention DAYS_AHEAD -> "stills readings chat_images"
  (cd "$BACKEND" && venv/bin/python -c "
import asyncio, sys, datetime as dt
from app.core.db import SessionFactory, engine
from app.core import timezone as tz
from app.application.edge.retention import Retention
async def m():
    async with SessionFactory() as s:
        p = await Retention(s).run(tz.now().replace(tzinfo=None) + dt.timedelta(days=int(sys.argv[1])))
        print(p.stills, p.readings, p.chat_images)
    await engine.dispose()
asyncio.run(m())" "$1")
}
uuid() { python3 -c "import uuid;print(uuid.uuid4())"; }
event() {  # event ID SHA256 -> one boarding now, declaring its still
  python3 -c "
import datetime as d, json, sys
print(json.dumps({'events': [{'event_id': sys.argv[1], 'event_type': 'board',
  'event_at': d.datetime.now().isoformat(), 'snapshot_hash': sys.argv[2]}]}))" "$1" "$2"
}
still() { printf '\xff\xd8\xff\xe0still-%s' "$1" > "$SNAP/$1.jpg"; sha256sum "$SNAP/$1.jpg" | cut -d' ' -f1; }
ev() { sql "SELECT CONCAT_WS('/', COALESCE(snapshot_url, '-'), IF(snapshot_deleted_at IS NULL, 'kept', 'deleted'), IF(snapshot_hash = '$2', 'hash', 'nohash')) FROM passenger_events WHERE event_id = '$1'"; }
file() { ls "$BACKEND"/storage/snapshots/"$1".* >/dev/null 2>&1 && echo present || echo gone; }
pings() { sql "SELECT COUNT(*) FROM trip_location_pings WHERE ${1}"; }
ping_sql() { sql "INSERT INTO trip_location_pings (trip_id, van_id, latitude, longitude, recorded_at) VALUES ($1, '$2', 7.0731, 125.6128, NOW())"; }

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); PT=$(login passenger)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$PT" ] && ok "signed in" || { bad "login"; exit 1; }
is "$(sql "SELECT policy_value FROM cooperative_policies WHERE policy_key = 'retention_days' ORDER BY effective_from DESC LIMIT 1")" 30 \
   "RetentionDays is 30 (assumed)"
code GET /trips/privacy-notice "" "$PT" >/dev/null
is "$(python3 -c "import json;d=json.load(open('/tmp/rt.json'));print(d['retention_days'], d['chat_image_retention_days'], d['chat_image_max_kb'], '[name' in d['privacy_contact'])")" \
   "30 30 10240 True" "the booking screen's camera notice reads the period in force, and the contact placeholder"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Evidence: stills, GPS readings, a flag, a dispute, chat images"
code POST /devices '{"device_model":"realme retention A"}' "$OT" >/dev/null; IDA=$(field "['device_id']"); TA=$(field "['device_token']")
code POST /devices '{"device_model":"realme retention B"}' "$OT" >/dev/null; IDB=$(field "['device_id']"); TB=$(field "['device_token']")
code POST /devices/$IDA/checkout '{"van_id":"VAN-0001","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT" >/dev/null
code POST /devices/$IDB/checkout '{"van_id":"VAN-0002","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT" >/dev/null
E1=$(uuid); H1=$(still one); E2=$(uuid); H2=$(still two); E3=$(uuid); H3=$(still three)
edge /edge/events "$(event "$E1" "$H1")" "$TA" >/dev/null; up "$E1" "$TA" "$SNAP/one.jpg" >/dev/null
edge /edge/events "$(event "$E2" "$H2")" "$TA" >/dev/null; up "$E2" "$TA" "$SNAP/two.jpg" >/dev/null
is "$(sql "SELECT GROUP_CONCAT(resolution_status ORDER BY chain_seq) FROM passenger_events WHERE event_id IN ('$E1', '$E2')")" \
   pending,pending "two unlisted boardings on ABC-1234's trip, each with its still"
is "$(code POST /door-events/$E1/explain '{"note":"The operator'"'"'s son, riding to school."}' "$DT")" 200 \
   "the Dispatcher explains the first; the second stays pending"
code POST /bookings/walk-in "{\"trip_id\":\"$TRIP2\",\"boarding_stop\":1,\"alighting_stop\":2}" "$DT" >/dev/null
edge /edge/events "$(event "$E3" "$H3")" "$TB" >/dev/null; up "$E3" "$TB" "$SNAP/three.jpg" >/dev/null
is "$(sql "SELECT CONCAT_WS('/', trip_id, match_status, resolution_status) FROM passenger_events WHERE event_id = '$E3'")" \
   "$TRIP2/matched_log/not_needed" "a listed boarding on XYZ-9876's trip, with its still"
code GET /trips/$TRIP2/share "" "$CT" >/dev/null
LINE=$(python3 -c "import json;print([l['line_id'] for l in json.load(open('/tmp/rt.json'))['lines'] if l['income_group']=='declared'][0])")
is "$(code POST /disputes "{\"subject\":\"fare_line\",\"line_id\":\"$LINE\",\"operator_statement\":\"No such passenger.\"}" "$CT")" 201 \
   "the operator disputes a line on XYZ-9876's trip"
DSP=$(field "['dispute_id']")
ping_sql "'$TRIP1'" VAN-0001; ping_sql "'$TRIP2'" VAN-0002; ping_sql "'$DONE'" VAN-0003; ping_sql NULL VAN-0005
sql "INSERT INTO driving_events (driving_event_id, trip_id, flag_type, start_at, max_speed_kmh, limit_kmh) VALUES ('FLAG-RET-1', '$DONE', 'overspeed', NOW(), 95.0, 80.0)"
ok "GPS readings on both trips, a completed trip with an open flag, and one held"
CONV=$(uuid); M1=$(uuid); M2=$(uuid)
sql "INSERT INTO conversations (conversation_id, kind, trip_id, participant_one_id, participant_two_id) VALUES ('$CONV', 'passenger_dispatcher', '$TRIP1', 'USER-PASSENGER-0001', 'USER-DISPATCHER-0001')"
mkdir -p "$BACKEND/storage/chat"
for m in "$M1" "$M2"; do
  printf '\x89PNG\r\n\x1a\nproof' > "$BACKEND/storage/chat/$m.png"
  sql "INSERT INTO messages (message_id, conversation_id, sender_id, sender_role, body, attachment_url, attachment_type, attachment_size_kb, retain_until) VALUES ('$m', '$CONV', 'USER-PASSENGER-0001', 'passenger', 'Payment screenshot', 'chat/$m.png', 'image', 1, CURDATE() + INTERVAL $([ "$m" = "$M1" ] && echo 0 || echo 1) DAY)"
done
ok "two payment screenshots: one due today, one tomorrow"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Only the Terminal Manager sees a still (T38)"
is "$(curl -s -o "$SNAP/got.jpg" -w "%{http_code}" "$API/door-events/$E1/snapshot" -H "Authorization: Bearer $OT")" 200 \
   "the Terminal Manager receives it"
cmp -s "$SNAP/got.jpg" "$SNAP/one.jpg" && ok "the very still the phone sent" || bad "different bytes"
is "$(code GET /door-events/$E1/snapshot "" "$CT")/$(code GET /door-events/$E1/snapshot "" "$DT")/$(code GET /door-events/$E1/snapshot "" "$PT")" \
   403/403/403 "refused to the Cashier, the Dispatcher and a passenger"
code GET /trips/$TRIP1/door-check "" "$DT" >/dev/null
grep -q "snapshots/" /tmp/rt.json && bad "the door check carries a still's address" \
  || ok "the Dispatcher's door check says a still exists, never where"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Today: only what is due goes (T41 b)"
is "$(retention 0)" "0 0 1" "nothing within 30 days is deleted; the screenshot due today is"
is "$(sql "SELECT CONCAT_WS('/', COALESCE(attachment_url, '-'), attachment_type, retain_until <= CURDATE()) FROM messages WHERE message_id = '$M1'")" "-/image/1" \
   "its message stays, with no attachment"
[ -e "$BACKEND/storage/chat/$M1.png" ] && bad "the file is still there" || ok "and the file is gone"
[ -e "$BACKEND/storage/chat/$M2.png" ] && ok "the one due tomorrow is kept" || bad "deleted early"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. 31 days on: what nobody needs goes (T36, T37, T39, T40)"
OUT=$(retention 31)
is "$(ev "$E1" "$H1")/$(file "$E1")" "-/deleted/hash/gone" \
   "T36 a reviewed still: file deleted, SnapshotURL NULL, SnapshotDeletedAt set, SnapshotHash kept"
is "$(ev "$E2" "$H2" | cut -d/ -f3-)/$(file "$E2")" "kept/hash/present" "T37 an unresolved over-list boarding keeps its still"
is "$(ev "$E3" "$H3" | cut -d/ -f3-)/$(file "$E3")" "kept/hash/present" "T40 a trip with an open dispute keeps its still"
is "$(pings "trip_id = '$TRIP2'")" 1 "T40 and its GPS readings"
is "$(pings "trip_id = '$TRIP1'")" 0 "ABC-1234's readings are deleted"
is "$(pings "trip_id = '$DONE'")/$(sql "SELECT COUNT(*) FROM driving_events WHERE driving_event_id = 'FLAG-RET-1'")" 1/1 \
   "a trip with a flag not yet reviewed keeps its readings"
is "$(pings "trip_id IS NULL AND van_id = 'VAN-0005'")" 0 "a held reading is deleted"
is "$(echo "$OUT" | cut -d' ' -f3)" 1 "and the screenshot due tomorrow"
code GET /trips/$TRIP1/chain "" "$OT" >/dev/null
is "$(field "['verified']")/$(field "['events']")" True/2 "T39 the chain still verifies without the image"
is "$(code GET /door-events/$E1/snapshot "" "$OT")" 404 "the Terminal Manager is told it is no longer kept"
field "['detail']" | grep -q "retention" && ok "because of retention" || bad "detail: $(field "['detail']")"
is "$(up "$E1" "$TA" "$SNAP/one.jpg")/$(field "['duplicate']")" 200/True "the phone sending it again changes nothing"
is "$(ev "$E1" "$H1" | cut -d/ -f1)/$(file "$E1")" "-/gone" "the still stays deleted"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Once decided and reviewed, the rest goes"
code POST /disputes/$DSP/decide '{"outcome":"rejected","note":"The walk-in was seen boarding."}' "$OT" >/dev/null
sql "UPDATE driving_events SET review_status = 'reviewed' WHERE driving_event_id = 'FLAG-RET-1'"
code POST /door-events/$E2/explain '{"note":"A barker, off before departure."}' "$DT" >/dev/null
is "$(retention 31 | cut -d' ' -f1-2)" "2 2" "the two stills and the two readings left are deleted"
is "$(file "$E2")/$(file "$E3")/$(pings "trip_id IN ('$TRIP2', '$DONE')")" gone/gone/0 "nothing is left past the period"
is "$(sql "SELECT COUNT(*) FROM driving_events WHERE driving_event_id = 'FLAG-RET-1'")" 1 "the driving flag itself stays"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. A still sent after its period is not kept"
E4=$(uuid); H4=$(still four)
edge /edge/events "$(event "$E4" "$H4")" "$TA" >/dev/null
sql "UPDATE passenger_events SET event_at = event_at - INTERVAL 31 DAY WHERE event_id = '$E4'"
is "$(up "$E4" "$TA" "$SNAP/four.jpg")" 409 "refused: past the retention period"
is "$(file "$E4")" gone "nothing is written"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$P" "$F"
[ "$F" -eq 0 ]
