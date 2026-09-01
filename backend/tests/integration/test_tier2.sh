#!/usr/bin/env bash
# Tier 2: policy config, fleet, schedule templates, trip generation.
set -euo pipefail
API="http://127.0.0.1:8000/api/v1"
STAMP=$(date +%s)
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

TOKEN=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"operator@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
AUTH="Authorization: Bearer $TOKEN"
JSON="Content-Type: application/json"

echo "== policies (the configurable ones) ====================="
curl -s "$API/config/policies" -H "$AUTH" | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    print(f\"  {p['policy_key']:<32} {p['policy_value']:<8} {p['description'][:44]}\")"

echo
echo "== change reschedule cutoff 6 -> 12 hours ==============="
curl -s -X PUT "$API/config/policies/reschedule_cutoff_hours" -H "$AUTH" -H "$JSON" \
  -d '{"policy_value":"12"}' | j "['policy_key'] + ' = ' + d['policy_value']"

echo "== reject an invalid value =============================="
curl -s -X PUT "$API/config/policies/reschedule_cutoff_hours" -H "$AUTH" -H "$JSON" \
  -d '{"policy_value":"soon"}'
echo

echo
echo "== fleet =============================================="
curl -s "$API/fleet/vans" -H "$AUTH" | python3 -c "
import json,sys
for v in json.load(sys.stdin):
    cam='camera' if v['has_cabin_camera'] else 'no camera'
    print(f\"  {v['plate_number']:<10} {v['seat_capacity']:>2} seats  {v['operational_status']:<12} {cam}\")"

echo
echo "== add a van ==========================================="
curl -s -X POST "$API/fleet/vans" -H "$AUTH" -H "$JSON" -d "{
  \"plate_number\":\"TST-${STAMP: -4}\",\"brand\":\"Toyota\",\"model\":\"HiAce\",
  \"seat_capacity\":14,\"has_cabin_camera\":true}" | python3 -m json.tool

echo
echo "== reject over-capacity van (LTFRB limit is 14) ========="
curl -s -X POST "$API/fleet/vans" -H "$AUTH" -H "$JSON" \
  -d '{"plate_number":"BIG-0001","seat_capacity":18}' | head -c 200
echo

echo
echo "== provision a conductor ==============================="
curl -s -X POST "$API/fleet/crew" -H "$AUTH" -H "$JSON" -d "{
  \"email\":\"cond${STAMP}@sabaygo.dev\",\"phone_number\":\"0918${STAMP: -7}\",
  \"password\":\"sabaygo123\",\"role\":\"conductor\",
  \"first_name\":\"New\",\"last_name\":\"Conductor\"}" | python3 -m json.tool

echo
echo "== driver without a licence should be rejected ========="
curl -s -X POST "$API/fleet/crew" -H "$AUTH" -H "$JSON" -d "{
  \"email\":\"drv${STAMP}@sabaygo.dev\",\"phone_number\":\"0919${STAMP: -7}\",
  \"password\":\"sabaygo123\",\"role\":\"driver\",
  \"first_name\":\"No\",\"last_name\":\"Licence\"}"
echo

echo
echo "== schedule templates =================================="
curl -s "$API/config/schedule-templates" -H "$AUTH" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    print(f\"  {t['departure_time']}  {t['days_of_week']}  {t['trip_label']}\")"

echo
echo "== generate 7 days of trips ============================"
curl -s -X POST "$API/config/trips/generate?days_ahead=7" -H "$AUTH" | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    print(f\"  {r['service_date']}  created={r['trips_created']:<3} skipped={r['trips_skipped']:<3} seat_legs={r['seat_legs_created']}\")
    for w in r['warnings']: print(f'     warning: {w}')"

echo
echo "== re-run: idempotent, everything skipped =============="
curl -s -X POST "$API/config/trips/generate?days_ahead=7" -H "$AUTH" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f\"  created={sum(r['trips_created'] for r in d)}  skipped={sum(r['trips_skipped'] for r in d)}\")"

echo
echo "== search a generated future trip ======================"
curl -s "$API/trips/search?boarding_stop=1&alighting_stop=4&service_date=$(date -d '+3 days' +%F)" \
  | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    print(f\"  {t['departure_datetime']}  {t['trip_label']:<14} seats={t['seats_available']}  P{t['fare_amount']}\")"
