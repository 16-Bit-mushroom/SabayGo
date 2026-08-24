#!/usr/bin/env bash
# End-to-end smoke test of the passenger core loop.
#   ./tests/integration/test_core_loop.sh
set -euo pipefail

API="http://127.0.0.1:8000/api/v1"
STAMP=$(date +%s)
EMAIL="test${STAMP}@sabaygo.dev"

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

echo "== 1. register =========================================="
TOKEN=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" -d "{
  \"email\":\"$EMAIL\",
  \"phone_number\":\"09171234567\",
  \"password\":\"sabaygo123\",
  \"first_name\":\"Test\",
  \"last_name\":\"Passenger\"
}" | j "['access_token']")
echo "registered $EMAIL  (token ${#TOKEN} chars)"

echo
echo "== 2. duplicate phone should 409 ========================"
curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" -d "{
  \"email\":\"other${STAMP}@sabaygo.dev\",
  \"phone_number\":\"09171234567\",
  \"password\":\"sabaygo123\",
  \"first_name\":\"Dup\",\"last_name\":\"Test\"
}"
echo

echo
echo "== 3. terminals ========================================="
curl -s "$API/trips/terminals" | python3 -m json.tool

echo
echo "== 4. search trips (stop 1 -> 4) ========================"
TRIP=$(curl -s "$API/trips/search?boarding_stop=1&alighting_stop=4&service_date=$(date -d tomorrow +%F)")
echo "$TRIP" | python3 -m json.tool
TRIP_ID=$(echo "$TRIP" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0]['trip_id'] if d else '')")
[ -z "$TRIP_ID" ] && { echo "No bookable trip found. Run db/reset-dev.sh"; exit 1; }

echo
echo "== 5. reserve ==========================================="
BOOKING=$(curl -s -X POST "$API/bookings/reserve" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"trip_id\":\"$TRIP_ID\",\"boarding_stop\":1,\"alighting_stop\":4}")
echo "$BOOKING" | python3 -m json.tool
BOOKING_ID=$(echo "$BOOKING" | j "['booking_id']")

echo
echo "== 6. checkout (needs PAYMONGO_SECRET_KEY) =============="
curl -s -X POST "$API/payments/checkout" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"booking_id\":\"$BOOKING_ID\"}" | python3 -m json.tool

echo
echo "== 7. unsigned webhook must be rejected ================="
curl -s -X POST "$API/payments/webhook" -H "Content-Type: application/json" \
  -d '{"data":{"id":"evt_fake","attributes":{"type":"checkout_session.payment.paid"}}}'
echo
