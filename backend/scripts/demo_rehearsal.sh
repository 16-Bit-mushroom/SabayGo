#!/usr/bin/env bash
# Demo rehearsal -- walks the Tier 1 loop on the live backend in the order
# the defence will show it, narrating each step, and STOPS at the first
# thing that would embarrass you on stage.
#
#   register -> login -> search -> book -> pay -> e-ticket -> check-in
#   -> scan -> board -> manifest -> audit -> revenue
#
# Run it the morning of the demo, after:
#   ./db/reset-dev.sh --soon          # fixture trip departs in 20 min
#   uvicorn app.main:app ...          # backend
#   (optional) ai_service python app.py
#
# The live loop runs on the fixture trip (Ecoland - Cotabato, "First
# Trip") because --soon puts it inside the check-in window. The A2Z demo
# dataset (routes, yesterday's revenue, audit history) is the backdrop
# the console screens show while you talk.
#
# Needs the venv and .env exported (the webhook simulator signs with
# PAYMONGO_WEBHOOK_SECRET):
#   source venv/bin/activate; set -a; source .env; set +a
set -uo pipefail
cd "$(dirname "$0")/.."

API="${API:-http://127.0.0.1:8000/api/v1}"
TRIP="TRIP-DEMO-00000001"
PW="sabaygo123"
LAT=7.052400; LNG=125.593100          # Ecoland Terminal

G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[1m'; N='\033[0m'
step() { printf "\n${B}%s${N}\n" "$*"; }
ok()   { printf "  ${G}✔${N}  %s\n" "$*"; }
warn() { printf "  ${Y}!${N}  %s\n" "$*"; }
die()  { printf "  ${R}✘  %s${N}\n" "$*"; printf "\n${R}Stop here and fix this before the demo.${N}\n"; exit 1; }
j()    { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}
login() { code POST /auth/login "{\"email\":\"$1\",\"password\":\"$PW\"}" >/dev/null; j "['access_token']" < /tmp/resp.json; }

# ─────────────────────────────────────────────────────────── 0. pre-flight
step "0. Pre-flight"
curl -s -o /dev/null -w '%{http_code}' "$API/../../docs" | grep -q 200 && ok "backend answering at $API" \
  || die "backend not reachable at $API -- uvicorn app.main:app --host 0.0.0.0 --port 8000"
[ -n "${PAYMONGO_WEBHOOK_SECRET:-}" ] && ok "PAYMONGO_WEBHOOK_SECRET exported (webhook simulator will sign)" \
  || die "PAYMONGO_WEBHOOK_SECRET not in the environment -- set -a; source .env; set +a"

PT=$(login passenger@sabaygo.dev); [ -n "$PT" ] && ok "passenger@ logs in" || die "passenger@ login failed -- did reset-dev.sh run?"
CT=$(login conductor@sabaygo.dev); [ -n "$CT" ] && ok "conductor@ logs in" || die "conductor@ login failed"
DT=$(login driver@sabaygo.dev);    [ -n "$DT" ] && ok "driver@ logs in"    || die "driver@ login failed"
OT=$(login coopadmin@sabaygo.dev); [ -n "$OT" ] && ok "coopadmin@ logs in" || die "coopadmin@ login failed"

TODAY=$(date +%F)
S=$(code GET "/trips/search?origin_terminal_id=TERM-ECOLAND-000001&destination_terminal_id=TERM-COTABATO-00001&service_date=$TODAY" "" "$PT")
DEP=$(python3 -c "
import json,datetime as d
for t in json.load(open('/tmp/resp.json')):
    if t['trip_id']=='$TRIP':
        dep=d.datetime.fromisoformat(t['departure_datetime']); m=(dep-d.datetime.now()).total_seconds()/60
        print(f'{m:.0f}'); break" 2>/dev/null)
if [ -z "$DEP" ]; then die "fixture trip $TRIP is not bookable today -- run ./db/reset-dev.sh --soon"
elif [ "$DEP" -gt 45 ]; then warn "fixture trip departs in $DEP min -- check-in opens 45 min before; use --soon for the live loop"
else ok "fixture trip departs in $DEP min (check-in window open)"; fi

S=$(code GET /audits/node-health "" "$CT")
if [ "$S" = "200" ] && [ "$(j "['reachable']" < /tmp/resp.json)" = "True" ]; then ok "AI node reachable -- audit step will show a real count"
else warn "AI node offline -- audit step will return 502. Either start ai_service, or say on stage: 'the node never invents a count'"; fi

S=$(code GET /revenue/summary?date_from=$(date -d '-2 days' +%F) "" "$OT")
T=$(j "['trips']" < /tmp/resp.json)
[ "${T:-0}" -ge 6 ] && ok "A2Z backdrop present: $T trips in the last three days, ₱$(j "['collected_fare']" < /tmp/resp.json) collected" \
  || warn "revenue backdrop thin ($T trips) -- 002_demo_dataset.sql may not have loaded"

# ─────────────────────────────────────────────────────── 1. passenger books
step "1. Passenger: search Ecoland → Cotabato, reserve, pay, e-ticket"
S=$(code GET /trips/terminals "" "$PT")
ok "terminal picker: $(python3 -c "import json;print(', '.join(t['terminal_name'].replace(' Terminal','') for t in json.load(open('/tmp/resp.json'))))")"

S=$(code POST /bookings/reserve "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$PT")
[ "$S" = "201" ] || die "reserve gave $S: $(j "['detail']" < /tmp/resp.json)"
BID=$(j "['booking_id']" < /tmp/resp.json); QR=$(j "['qr_payload']" < /tmp/resp.json)
ok "reserved -- ticket $(j "['ticket_number']" < /tmp/resp.json), ₱$(j "['fare_amount']" < /tmp/resp.json), status pending (space held 10 min)"

S=$(code POST /payments/checkout "{\"booking_id\":\"$BID\"}" "$PT")
if [ "$S" = "200" ]; then ok "PayMongo checkout URL issued -- on stage, open it on the phone"
else warn "checkout gave $S (no live PayMongo key) -- simulating the signed webhook instead"; fi
python tests/integration/simulate_webhook.py --booking-id "$BID" >/dev/null 2>&1 || die "webhook simulator failed -- venv active? .env exported?"

S=$(code GET "/bookings/$BID" "" "$PT")
ST=$(j "['status']" < /tmp/resp.json)
[ "$ST" = "confirmed" ] && ok "e-ticket: status confirmed, QR $QR, check-in opens $(j "['checkin_opens_at']" < /tmp/resp.json | cut -c12-16)" \
  || die "booking is '$ST' after the webhook, expected confirmed"

# ──────────────────────────────────────────────────────── 2. I'm here
step "2. Passenger taps 'I'm here' at Ecoland"
S=$(code POST "/bookings/$BID/check-in" "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" "$PT")
if [ "$S" = "200" ]; then ok "checked in -- manifest will show AT TERMINAL"
else warn "check-in refused ($S): $(j "['detail']" < /tmp/resp.json) -- fine to show as the 'too early' rejection, then continue"; fi

# ──────────────────────────────────────────────────────── 3. conductor
step "3. Conductor: open boarding, scan, walk-in, manifest"
S=$(code GET /trips/assigned "" "$CT")
grep -q "$TRIP" /tmp/resp.json && ok "trip is on conductor@'s assigned list" || die "fixture trip not in /trips/assigned for conductor@"

S=$(code POST "/trips/$TRIP/start-boarding" "" "$CT")
[ "$S" = "200" ] && ok "boarding opened" || die "start-boarding gave $S: $(j "['detail']" < /tmp/resp.json)"

S=$(code POST /scans "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
RES=$(j "['result']" < /tmp/resp.json)
[ "$RES" = "valid" ] && ok "scan: valid -- passenger boarded" || die "scan result '$RES', expected valid"
S=$(code POST /scans "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" "$CT")
[ "$(j "['result']" < /tmp/resp.json)" = "already_boarded" ] && ok "second scan: already_boarded (show this -- it is the anti-fraud beat)" \
  || warn "second scan gave $(j "['result']" < /tmp/resp.json)"

S=$(code POST /bookings/walk-in "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}" "$CT")
[ "$S" = "201" ] && ok "cash walk-in logged -- ₱$(j "['fare_amount']" < /tmp/resp.json) pending in the conductor's hand" \
  || die "walk-in gave $S: $(j "['detail']" < /tmp/resp.json)"

S=$(code GET "/trips/$TRIP/manifest" "" "$CT")
ok "manifest: $(python3 -c "
import json;m=json.load(open('/tmp/resp.json'))
ps=m.get('passengers',m if isinstance(m,list) else [])
print(f\"{len(ps)} passengers, {sum(1 for p in ps if p.get('status')=='boarded')} boarded\")")"

# ──────────────────────────────────────────────────────── 4. audit
step "4. Driver: headcount, then the camera audit"
S=$(code POST "/trips/$TRIP/headcount" '{"stop_sequence":1,"confirmed_count":2}' "$DT")
[ "$S" = "200" ] && ok "driver headcount 2 -- variance $(j "['variance']" < /tmp/resp.json)" || warn "headcount gave $S: $(j "['detail']" < /tmp/resp.json)"

S=$(code POST /audits/trigger "{\"trip_id\":\"$TRIP\",\"leg_sequence\":1,\"trigger_type\":\"manual\"}" "$DT")
if [ "$S" = "200" ]; then
  ok "YOLOv8: visual $(j "['visual_count']" < /tmp/resp.json) vs manifest $(j "['booked_count']" < /tmp/resp.json) -- $(j "['resolution_status']" < /tmp/resp.json)"
elif [ "$S" = "502" ]; then warn "AI node unreachable -> 502. The line: 'it refuses to invent a number'. Yesterday's audits are in the console History tab"
else warn "audit gave $S: $(j "['detail']" < /tmp/resp.json)"; fi

# ──────────────────────────────────────────────────────── 5. office
step "5. Office console: queue, history, revenue, export"
S=$(code GET /audits/pending "" "$OT");  ok "audit queue: $(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))") pending (one is yesterday's Digos +2)"
S=$(code GET /audits/history "" "$OT");  ok "audit history: $(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))") closed -- resolved, ignored, reconciled, failed"
S=$(code GET "/revenue/summary?date_from=$(date -d '-2 days' +%F)" "" "$OT")
ok "revenue, last 3 days: collected ₱$(j "['collected_fare']" < /tmp/resp.json), cash in hand ₱$(j "['cash_in_hand']" < /tmp/resp.json), unreconciled ₱$(j "['unreconciled_amount']" < /tmp/resp.json)"
S=$(curl -s -o /tmp/rehearsal.xlsx -w '%{http_code}' -H "Authorization: Bearer $OT" "$API/revenue/export?date_from=$(date -d '-2 days' +%F)")
[ "$S" = "200" ] && ok "export: $(du -h /tmp/rehearsal.xlsx | cut -f1) workbook at /tmp/rehearsal.xlsx" || warn "export gave $S"

printf "\n${G}${B}Rehearsal complete.${N} Reset before the real run: ./db/reset-dev.sh --soon\n"
