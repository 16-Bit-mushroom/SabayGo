#!/usr/bin/env bash
# Exercises the reschedule + cancel policy end to end.
set -euo pipefail
API="http://127.0.0.1:8000/api/v1"
STAMP=$(date +%s)
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

echo "== register =============================================="
TOKEN=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" -d "{
  \"email\":\"resched${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
  \"password\":\"sabaygo123\",\"first_name\":\"Resched\",\"last_name\":\"Test\"
}" | j "['access_token']")
echo "ok (${#TOKEN} chars)"

echo
echo "== trips available on this route =========================="
TRIPS=$(curl -s "$API/trips/search?boarding_stop=1&alighting_stop=4&service_date=$(date -d tomorrow +%F)")
echo "$TRIPS" | python3 -c "
import json,sys
for t in json.load(sys.stdin):
    print(f\"  {t['trip_id']}  {t['departure_datetime']}  seats={t['seats_available']}\")"
TRIP_A=$(echo "$TRIPS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0]['trip_id'] if d else '')")
TRIP_B=$(echo "$TRIPS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d[1]['trip_id'] if len(d)>1 else '')")

[ -z "$TRIP_A" ] && { echo "No trips. Run ./db/reset-dev.sh"; exit 1; }

echo
echo "== book on trip A ========================================"
B=$(curl -s -X POST "$API/bookings/reserve" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"trip_id\":\"$TRIP_A\",\"boarding_stop\":1,\"alighting_stop\":4}")
echo "$B" | python3 -m json.tool
BOOKING=$(echo "$B" | j "['booking_id']")

echo
echo "== my bookings (note can_reschedule + deadline) ==========="
curl -s "$API/bookings/mine" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

if [ -n "$TRIP_B" ]; then
  echo
  echo "== reschedule to trip B =================================="
  curl -s -X POST "$API/bookings/$BOOKING/reschedule" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "{\"new_trip_id\":\"$TRIP_B\"}" | python3 -m json.tool
  echo
  echo "== second reschedule should hit the policy limit ========="
  NEW=$(curl -s "$API/bookings/mine" -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['booking_id'])")
  curl -s -X POST "$API/bookings/$NEW/reschedule" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "{\"new_trip_id\":\"$TRIP_A\"}"
  echo
else
  echo
  echo "(only one trip seeded -- add a second schedule_template to test reschedule)"
fi

echo
echo "== cancel (no refund) ===================================="
LAST=$(curl -s "$API/bookings/mine" -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['booking_id'])")
curl -s -X POST "$API/bookings/$LAST/cancel" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo
echo "== double cancel should 409 =============================="
curl -s -X POST "$API/bookings/$LAST/cancel" -H "Authorization: Bearer $TOKEN"
echo
