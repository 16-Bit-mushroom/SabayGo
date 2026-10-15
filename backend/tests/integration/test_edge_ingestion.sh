#!/usr/bin/env bash
# Rev 468 step 5, rev 603 rules: what the edge phone sends (change
# brief 4.2 rules 7-12; 4.4; 5.3).
#
#   ./db/reset-dev.sh --soon && ./tests/integration/test_edge_ingestion.sh
#
# Plays four phones against the real API. Needs the backend on :8000 and
# a database just reset with --soon. Time is moved with SQL where a test
# needs a trip that started twenty minutes ago; the silence job is driven
# by calling its tick. Brief acceptance tests are named (T6, T12, ...).
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$BACKEND/venv/bin/python"
PASS_N=0; FAIL_N=0
SNAP=$(mktemp -d); trap 'rm -rf "$SNAP"' EXIT

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }
field() { j "['$1']" < /tmp/resp.json; }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}
# The phone's own calls: edge METHOD PATH DATA TOKEN
edge() {
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$1" "$API$2")
  [ -n "${4:-}" ] && args+=(-H "X-Device-Token: $4")
  [ -n "${3:-}" ] && args+=(-H "Content-Type: application/json" -d "$3")
  curl "${args[@]}"
}
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  j "['access_token']" < /tmp/resp.json
}
uuid() { python3 -c "import uuid;print(uuid.uuid4())"; }
# Status reports from FROM to TO seconds around now, every STEP: reports FROM TO STEP [lens]
reports() {
  python3 -c "
import datetime as d, json, sys
n = d.datetime.now(); f, t, s = map(int, sys.argv[1:4]); lens = len(sys.argv) > 4
print(json.dumps({'reports': [{'recorded_at': (n + d.timedelta(seconds=x)).isoformat(),
  'camera_ok': True, 'gps_ok': True, 'lens_blocked': lens, 'battery_pct': 80,
  'battery_temp_c': 36.5, 'charging': True} for x in range(f, t + 1, s)]}))" "$@"
}
# One door event: event ID TYPE OFFSET_S [LAT LON]
event() {
  python3 -c "
import datetime as d, json, sys
e = {'event_id': sys.argv[1], 'event_type': sys.argv[2],
     'event_at': (d.datetime.now() + d.timedelta(seconds=int(sys.argv[3]))).isoformat()}
if len(sys.argv) > 5: e.update(latitude=float(sys.argv[4]), longitude=float(sys.argv[5]))
print(json.dumps({'events': [e]}))" "$@"
}
# One GPS reading: fix OFFSET_S LAT LON
fix() {
  python3 -c "
import datetime as d, json, sys
print(json.dumps({'fixes': [{'recorded_at': (d.datetime.now() + d.timedelta(seconds=int(sys.argv[1]))).isoformat(),
  'latitude': float(sys.argv[2]), 'longitude': float(sys.argv[3])}]}))" "$@"
}
sql() {
  (cd "$BACKEND" && "$PY" -c "
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
silence_tick() {
  (cd "$BACKEND" && "$PY" -c "
import asyncio
from app.core.db import SessionFactory, engine
from app.application.edge.evidence import alert_silent_phones
async def m():
    await alert_silent_phones(SessionFactory); await engine.dispose()
asyncio.run(m())" 2>&1 | grep -iE "error|traceback" || true)
}
board() {
  code GET "/config/trips" "" "$OT" >/dev/null
  python3 -c "import json;print({t['trip_id']:t for t in json.load(open('/tmp/resp.json'))}['$1']['$2'])"
}
notes() {  # notes TOKEN TYPE ENTITY_ID
  code GET "/notifications?limit=100" "" "$1" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/resp.json'))['items'] if n['type']=='$2' and n['related_entity_id']=='$3'))"
}
# The Cashier records a trip's whole share: pay TRIP_ID
pay() {
  code GET "/trips/$1/share" "" "$CT" >/dev/null
  code POST "/trips/$1/payment" "{\"amount\":\"$(field amount_due)\",\"reference\":\"OR-$RANDOM\"}" "$CT"
}
# The departure rule's site settings (empty = unset): zone RADIUS_M N
zone() {
  code PUT /config/policies/depart_zone_radius_m "{\"policy_value\":\"$1\"}" "$OT" >/dev/null
  code PUT /config/policies/depart_readings "{\"policy_value\":\"$2\"}" "$OT" >/dev/null
}
# The manager's 'Trip Not Started' alerts about the van left with no trip
van_left() {
  code GET "/notifications?limit=100" "" "$OT" >/dev/null
  python3 -c "import json;print(sum(1 for n in json.load(open('/tmp/resp.json'))['items'] if n['type']=='trip_not_started' and n['related_entity_id']=='$1' and 'van left' in n['title']))"
}
events_on() { sql "SELECT COUNT(*) FROM passenger_events WHERE trip_id = '$1'"; }
# Move a started trip and its phone's reports back in time by MIN minutes.
rewind() {
  sql "UPDATE trips SET started_at = started_at - INTERVAL $2 MINUTE WHERE trip_id = '$1'"
  sql "UPDATE device_heartbeats SET recorded_at = recorded_at - INTERVAL $2 MINUTE WHERE device_id = '$3'"
  sql "UPDATE edge_devices SET last_heartbeat_at = last_heartbeat_at - INTERVAL $2 MINUTE WHERE device_id = '$3'"
}

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); D3T=$(login dispatcher3)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$D3T" ] && ok "staff signed in" || { bad "login"; exit 1; }
TRIP1=TRIP-DEMO-00000001   # VAN-0001, dispatcher@, departs in 20 min
TRIP2=TRIP-DEMO-00000002   # VAN-0002, departs in 20 min
LIVE=TRIP-A2Z-LIVE-SOON    # VAN-0004, dispatcher5@, departs in 2 h
code GET /config/routes "" "$OT" >/dev/null
MATI=$(python3 -c "import json;print([r['route_id'] for r in json.load(open('/tmp/resp.json')) if 'Mati' in r['route_name']][0])")
code GET /trips/TRIP-A2Z-MAT-D1-0700/stops "" "$OT" >/dev/null
read -r ELAT ELON < <(python3 -c "import json;s=json.load(open('/tmp/resp.json'))[0];print(s['latitude'],s['longitude'])")
FAR=$(python3 -c "print($ELAT + 0.05)")   # about 5.5 km from the terminal

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Each phone has its own token"
for P in A B C D; do
  code POST /devices "{\"device_model\":\"Realme 5G [model TBC] $P\"}" "$OT" >/dev/null
  eval "ID$P=$(field device_id); T$P=$(field device_token)"
done
[ -n "$TA" ] && [ "${#TA}" -ge 40 ] && ok "adding a phone shows its token once" || bad "no token"
code GET /devices "" "$OT" >/dev/null
grep -q "$TA" /tmp/resp.json && bad "the pool list leaks the token" || ok "the pool list never shows it"
is "$(edge GET /edge/session)" 401 "no token, no upload"
is "$(edge GET /edge/session "" not-a-token)" 401 "a wrong token is refused"
is "$(edge GET /edge/session "" "$TA")" 200 "the phone signs in with its token"
is "$(field status)/$(field van_id)" "in_office/None" "and learns it is in the office, with no van"
OLD=$TA
is "$(code POST /devices/$IDA/token "" "$CT")" 403 "only the manager re-issues a token"
code POST /devices/$IDA/token "" "$OT" >/dev/null; TA=$(field device_token)
is "$(edge GET /edge/session "" "$OLD")" 401 "a re-issued token revokes the old one"
is "$(edge GET /edge/session "" "$TA")" 200 "the new one works"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Status reports: stored once, on the server's clock"
is "$(edge POST /edge/heartbeats "$(reports 600 600 1)" "$TA")" 422 "a report dated 10 min ahead is refused whole"
R=$(reports -60 0 60)
edge POST /edge/heartbeats "$R" "$TA" >/dev/null
is "$(field stored)" 2 "two reports stored"
edge POST /edge/heartbeats "$R" "$TA" >/dev/null
is "$(field stored)/$(field duplicates)" "0/2" "the same batch again stores nothing"
code GET /devices "" "$OT" >/dev/null
python3 -c "import json;d={x['device_id']:x for x in json.load(open('/tmp/resp.json'))}['$IDA'];assert not d['silent'] and d['battery_pct']==80" \
  && ok "the pool shows the phone reporting, battery 80%" || bad "pool not updated"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Door events: by the van the phone is in, by time (rules 11, 12)"
E0=$(uuid)
edge POST /edge/events "$(event "$E0" board 0)" "$TA" >/dev/null
is "$(field ignored)" 1 "an event before the check-out has no van: ignored"
code POST /devices/$IDA/checkout '{"van_id":"VAN-0001","dispatcher_id":"USER-DISPATCHER-0001"}' "$CT" >/dev/null
code POST /devices/$IDB/checkout '{"van_id":"VAN-0002","dispatcher_id":"USER-DISPATCHER-0002"}' "$CT" >/dev/null
edge GET /edge/session "" "$TA" >/dev/null
is "$(field plate_number)" ABC-1234 "after check-out the phone shows its van's plate"
E1=$(uuid)
is "$(edge POST /edge/events "$(event "$E1" board 0 "$ELAT" "$ELON")" "$TA")" 200 "a boarding is uploaded"
is "$(field stored)" 1 "T25a it goes on the van's scheduled trip, inside its start window"
is "$(sql "SELECT trip_id FROM passenger_events WHERE event_id = '$E1'")" $TRIP1 "the trip of ABC-1234"
edge POST /edge/events "$(event "$E1" board 0)" "$TA" >/dev/null
is "$(field duplicates)" 1 "sent again after a dropped connection: not stored twice"

printf '\xff\xd8\xff\xe0snapshot-one' > "$SNAP/one.jpg"; printf '\xff\xd8\xff\xe0snapshot-two' > "$SNAP/two.jpg"
printf 'not an image' > "$SNAP/bad.txt"
up() { curl -s -o /tmp/resp.json -w "%{http_code}" -X PUT "$API/edge/events/$1/snapshot" -H "X-Device-Token: $2" -F "image=@$3"; }
is "$(up "$E1" "$TA" "$SNAP/one.jpg")" 200 "the blurred still is stored"
H=$(field snapshot_hash)
is "$(sql "SELECT snapshot_hash FROM passenger_events WHERE event_id = '$E1'")" "$H" "with its SHA-256 on the event"
is "$(sql "SELECT snapshot_url FROM passenger_events WHERE event_id = '$E1'" | cut -c1-10)" "snapshots/" \
   "kept in storage/, not the public media folder"
is "$(up "$E1" "$TA" "$SNAP/one.jpg")/$(field duplicate)" 200/True "the same still again is accepted as a repeat"
is "$(up "$E1" "$TA" "$SNAP/two.jpg")" 409 "evidence is never replaced"
is "$(up "$E1" "$TA" "$SNAP/bad.txt")" 422 "only an image is accepted"
is "$(up "$E1" "$TB" "$SNAP/one.jpg")" 404 "a phone cannot attach a still to another phone's event"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. The phone at the start (4.4; T12)"
edge POST /edge/heartbeats "$(reports 0 0 1)" "$TA" >/dev/null
is "$(code POST /trips/$TRIP1/start "" "$CT")" 200 "cashier starts ABC-1234's trip"
is "$(field audit_status)/$(field warnings)" "audited/[]" "its phone is reporting: Audited, no warning"
edge POST /edge/heartbeats "$(reports -300 -300 1)" "$TB" >/dev/null
is "$(code POST /trips/$TRIP2/start "" "$CT")" 200 "T12 the trip whose phone last reported 5 min ago still starts"
is "$(field audit_status)/$(field unaudited_reason)" unaudited/silent_at_start "Unaudited, Silent_At_Start"
field warnings | grep -q "has not reported since" && ok "and the starter is told why" || bad "warning: $(field warnings)"
is "$(notes "$OT" unaudited_trip $TRIP2)" 1 "the manager is alerted"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. A silence mid-trip (4.4; T13, T23)"
rewind $TRIP1 20 "$IDA"
edge POST /edge/heartbeats "$(reports -1140 -600 60)" "$TA" >/dev/null
is "$(board $TRIP1 audit_status)" audited "reports through the first ten minutes: still Audited"
silence_tick
code GET "/notifications?limit=100" "" "$OT" >/dev/null
python3 -c "import json;assert any(n['type']=='unaudited_trip' and n['related_entity_id']=='$TRIP1' and 'silent' in n['title'] for n in json.load(open('/tmp/resp.json'))['items'])" \
  && ok "silent ten minutes: the alert goes out at once" || bad "no silence alert"
silence_tick
is "$(notes "$OT" unaudited_trip $TRIP1)" 1 "once per silence, not every minute"
is "$(board $TRIP1 audit_status)" audited "but the trip is not marked yet"
edge POST /edge/heartbeats "$(reports -540 0 60)" "$TA" >/dev/null
is "$(board $TRIP1 audit_status)" audited "T23 the stored reports cover the gap: it stays Audited"
edge POST /edge/heartbeats "$(reports 1 1 1 lens)" "$TA" >/dev/null
is "$(board $TRIP1 audit_status)/$(board $TRIP1 unaudited_reason)" unaudited/lens_blocked \
   "a covered lens is marked at once: Lens_Blocked"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. Events with no trip are held, then claimed (rule 12; T25b, T13)"
code POST /devices/$IDC/checkout '{"van_id":"VAN-0004","dispatcher_id":"USER-DISPATCHER-0005"}' "$CT" >/dev/null
E2=$(uuid); E3=$(uuid)
edge POST /edge/events "$(event "$E2" board 0)" "$TC" >/dev/null
is "$(field held)" 1 "T25b NBC-7788's next trip is 2 h off: the boarding is held"
is "$(sql "SELECT COUNT(*) FROM held_door_events WHERE event_id = '$E2'")" 1 "outside the ledger"
is "$(notes "$OT" trip_not_started VAN-0004)" 1 "'Trip Not Started' about the van"
edge POST /edge/events "$(event "$E3" alight 1)" "$TC" >/dev/null
is "$(notes "$OT" trip_not_started VAN-0004)" 1 "raised once while its events wait"
sql "UPDATE trips SET departure_datetime = NOW() + INTERVAL 10 MINUTE WHERE trip_id = '$LIVE'"
edge POST /edge/heartbeats "$(reports 0 0 1)" "$TC" >/dev/null
is "$(pay $LIVE)" 200 "the cashier records its share"
is "$(code POST /trips/$LIVE/start "" "$CT")" 200 "its trip is started"
is "$(events_on $LIVE)/$(sql "SELECT COUNT(*) FROM held_door_events WHERE van_id = 'VAN-0004'")" "2/0" \
   "the held events move onto it, matched by time"
rewind $LIVE 20 "$IDC"
edge POST /edge/heartbeats "$(reports -1140 -720 60)" "$TC" >/dev/null
is "$(board $LIVE audit_status)" audited "reports through 12 min ago"
edge POST /edge/heartbeats "$(reports -300 0 60)" "$TC" >/dev/null
is "$(board $LIVE audit_status)/$(board $LIVE unaudited_reason)" unaudited/lost_en_route \
   "T13 reconnects, and its stored reports leave a 7-min gap: Lost_En_Route"
GAP_AT=$(sql "SELECT TIMESTAMPDIFF(MINUTE, unaudited_at, NOW()) FROM trips WHERE trip_id = '$LIVE'")
[ "$GAP_AT" -ge 11 ] && [ "$GAP_AT" -le 13 ] && ok "Unaudited from the start of the gap (${GAP_AT} min ago)" \
  || bad "unaudited_at is $GAP_AT min ago"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. GPS from the phone (rules 8, 9, 11)"
zone 300 3
is "$(edge POST /edge/fixes "$(fix 2 "$ELAT" "$ELON")" "$TA")" 200 "a reading at the terminal"
is "$(field recorded)" 1 "goes on ABC-1234's trip"
for S in 3 4 5; do edge POST /edge/fixes "$(fix $S "$FAR" "$ELON")" "$TA" >/dev/null; done
is "$(board $TRIP1 status)/$(board $TRIP1 departure_source)" departed/gps \
   "N readings outside the zone with a boarding counted: departed, GPS"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "8. A van with no trip leaves with passengers (rule 7, 4.6; T6)"
for T in $(sql "SELECT trip_id FROM trips WHERE route_id = '$MATI' AND status = 'scheduled' AND van_id IS NULL AND departure_datetime BETWEEN NOW() - INTERVAL 12 HOUR AND NOW() + INTERVAL 1 HOUR"); do
  code POST /trips/$T/void '{"reason":"Test: clear the slot"}' "$OT" >/dev/null
done
code POST /config/trips/special "{\"route_id\":\"$MATI\",\"departure_datetime\":\"$(date -d '+10 min' '+%Y-%m-%dT%H:%M:00')\",\"trip_label\":\"Edge S6\"}" "$OT" >/dev/null
S6=$(field trip_id)
code POST /devices/$IDD/checkout '{"van_id":"VAN-0006","dispatcher_id":"USER-DISPATCHER-0003"}' "$CT" >/dev/null
edge POST /edge/heartbeats "$(reports 0 0 1)" "$TD" >/dev/null
E4=$(uuid)
edge POST /edge/events "$(event "$E4" board 0 "$ELAT" "$ELON")" "$TD" >/dev/null
is "$(field held)" 1 "LCT-9042 has no trip: its boarding is held"
edge POST /edge/fixes "$(fix 1 "$ELAT" "$ELON")" "$TD" >/dev/null
is "$(field held)/$(board $S6 van_id)" 1/None "still at the terminal: the reading is held, nothing starts"
edge POST /edge/fixes "$(fix 2 "$FAR" "$ELON")" "$TD" >/dev/null
is "$(board $S6 van_id)" None "a single reading out of the zone starts nothing"
for S in 3 4; do edge POST /edge/fixes "$(fix $S "$FAR" "$ELON")" "$TD" >/dev/null; done
is "$(board $S6 van_id)/$(board $S6 start_mode)" "VAN-0006/auto_detected" \
   "T6 it leaves: the Mati trip waiting for a van gets it, Auto_Detected"
is "$(board $S6 start_review_status)/$(board $S6 status)/$(board $S6 departure_source)" pending/departed/gps \
   "held for review, departed, Detected"
is "$(board $S6 dispatcher_id)" USER-DISPATCHER-0003 "the Dispatcher who has the phone is on it"
is "$(events_on $S6)" 1 "the held boarding is on the trip"
is "$(notes "$OT" unconfirmed_trip_start $S6)" 1 "'Unconfirmed Trip Start' to the manager"

rewind $S6 10 "$IDD"
is "$(code POST /trips/$S6/arrive "" "$D3T")" 200 "dispatcher3 taps Arrived"
is "$(board $S6 audit_status)/$(board $S6 unaudited_reason)" unaudited/lost_en_route \
   "the phone fell silent and the trip ended first: Lost_En_Route, final"

E5=$(uuid)
edge POST /edge/events "$(event "$E5" board 5 "$ELAT" "$ELON")" "$TD" >/dev/null
is "$(field held)" 1 "a new boarding after that trip ended is held"
edge POST /edge/fixes "$(fix 6 "$ELAT" "$ELON")" "$TD" >/dev/null
for S in 7 8 9; do edge POST /edge/fixes "$(fix $S "$FAR" "$ELON")" "$TD" >/dev/null; done
is "$(sql "SELECT COUNT(*) FROM trips WHERE van_id = 'VAN-0006' AND status IN ('boarding', 'departed')")" 0 \
   "it leaves again, and no trip on its route waits: no trip is invented (2.5)"
is "$(sql "SELECT COUNT(*) FROM held_door_events WHERE van_id = 'VAN-0006'")" 1 "its boarding stays held"
is "$(van_left VAN-0006)" 1 "'Trip Not Started' tells the manager the van left with passengers and no trip"
edge POST /edge/fixes "$(fix 10 "$FAR" "$ELON")" "$TD" >/dev/null
is "$(van_left VAN-0006)" 1 "once while its events wait, not on every reading"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "9. A retired phone uploads nothing"
code POST /devices/$IDB/return '{}' "$CT" >/dev/null
code POST /devices/$IDB/retire "" "$OT" >/dev/null
is "$(edge GET /edge/session "" "$TB")" 401 "its token stops working"

for P in A C D; do eval "code POST /devices/\$ID$P/return '{}' \"\$CT\" >/dev/null"; done
zone "" ""

printf '\n%d passed, %d failed\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
