#!/usr/bin/env bash
# Full operations loop: book -> pay -> check-in -> scan -> audit -> revenue
set -euo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
STAMP=$(date +%s)
j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)"; }

# Ecoland Terminal coordinates from the seed data.
LAT=7.052400; LNG=125.593100

echo "== passenger registers & books =========================="
PTOKEN=$(curl -s -X POST "$API/auth/register" -H "Content-Type: application/json" -d "{
  \"email\":\"ops${STAMP}@sabaygo.dev\",\"phone_number\":\"0917${STAMP: -7}\",
  \"password\":\"sabaygo123\",\"first_name\":\"Ops\",\"last_name\":\"Test\"}" | j "['access_token']")

B=$(curl -s -X POST "$API/bookings/reserve" -H "Authorization: Bearer $PTOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"trip_id\":\"$TRIP\",\"boarding_stop\":1,\"alighting_stop\":4}")
echo "$B" | python3 -m json.tool
BID=$(echo "$B" | j "['booking_id']"); QR=$(echo "$B" | j "['qr_payload']")

echo
echo "== confirm payment via simulated webhook ================"
python tests/integration/simulate_webhook.py --booking-id "$BID" | tail -2

echo
echo "== check-in AT the terminal (should pass) ==============="
curl -s -X POST "$API/bookings/$BID/check-in" -H "Authorization: Bearer $PTOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"latitude\":$LAT,\"longitude\":$LNG,\"gps_accuracy_m\":8.5}" | python3 -m json.tool

echo
echo "== crew login =========================================="
CTOKEN=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"conductor@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")

curl -s -X POST "$API/trips/$TRIP/start-boarding" -H "Authorization: Bearer $CTOKEN" >/dev/null

echo "== scan the QR (valid) ================================="
curl -s -X POST "$API/scans" -H "Authorization: Bearer $CTOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" | python3 -m json.tool

echo
echo "== scan again (already_boarded) ========================"
curl -s -X POST "$API/scans" -H "Authorization: Bearer $CTOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"qr_payload\":\"$QR\",\"trip_id\":\"$TRIP\",\"stop_sequence\":1}" | j "['result']"

echo
echo "== manifest ============================================"
curl -s "$API/trips/$TRIP/manifest" -H "Authorization: Bearer $CTOKEN" \
  | python3 -c "
import json,sys
m=json.load(sys.stdin)
print(f\"  capacity={m['seat_capacity']} bookings={m['total_bookings']} boarded={m['boarded']} awaiting={m['awaiting']}\")
for p in m['passengers']:
    print(f\"    seat {p['seat_number']:>2}  stops {p['boarding_stop']}->{p['alighting_stop']}  {p['status']:<12} {p['booking_type']}\")"

echo
echo "== driver headcount ===================================="
DTOKEN=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"driver@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
curl -s -X POST "$API/trips/$TRIP/headcount" -H "Authorization: Bearer $DTOKEN" \
  -H "Content-Type: application/json" -d '{"stop_sequence":1,"confirmed_count":2}' \
  | python3 -m json.tool

echo
echo "== AI node health ======================================"
curl -s "$API/audits/node-health" -H "Authorization: Bearer $CTOKEN" | python3 -m json.tool || \
  echo "  (start ai_service first: cd ai_service && python app.py)"

echo
echo "== trigger YOLOv8 audit ================================"
curl -s -X POST "$API/audits/trigger" -H "Authorization: Bearer $CTOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"trip_id\":\"$TRIP\",\"leg_sequence\":1,\"trigger_type\":\"manual\"}" | python3 -m json.tool

echo
echo "== revenue summary ====================================="
OTOKEN=$(curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"coopadmin@sabaygo.dev","password":"sabaygo123"}' | j "['access_token']")
curl -s "$API/revenue/summary" -H "Authorization: Bearer $OTOKEN" | python3 -m json.tool
