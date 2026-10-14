#!/usr/bin/env bash
# Rev 468 step 3: settings history, the member roster, import and export,
# and the phone pool.
#
#   ./tests/integration/test_roster.sh
#
# Needs the backend on :8000 and a seeded database (./db/reset-dev.sh).
# Every record it makes is new (stamped), so it can run repeatedly.
set -uo pipefail

API="http://127.0.0.1:8000/api/v1"
PY="$(cd "$(dirname "$0")/../.." && pwd)/venv/bin/python"
STAMP=$(date +%s)
N4=${STAMP: -4}
N7=${STAMP: -7}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS_N=0; FAIL_N=0

j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr() { printf '\n\033[1m%s\033[0m\n' "── $* ────────────────────────────────"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS_N=$((PASS_N+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL_N=$((FAIL_N+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1)"; }

code() {
  local m=$1 p=$2 d=${3:-} t=${4:-}
  local args=(-s -o /tmp/resp.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && args+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && args+=(-H "Content-Type: application/json" -d "$d")
  curl "${args[@]}"
}
# multipart upload: up METHOD PATH FIELD FILE TOKEN
up() {
  curl -s -o /tmp/resp.json -w "%{http_code}" -X "$1" "$API$2" \
       -H "Authorization: Bearer $5" -F "$3=@$4"
}
# download to a file: get PATH OUT TOKEN
get() { curl -s -o "$2" -w "%{http_code}" "$API$1" -H "Authorization: Bearer $3"; }
login() {
  code POST /auth/login "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" >/dev/null
  j "['access_token']" < /tmp/resp.json
}
count() { code GET "$1" "" "$OT" >/dev/null; python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))"; }

OT=$(login manager); CT=$(login cashier)
[ -n "$OT" ] && [ -n "$CT" ] && ok "manager and cashier signed in" || { bad "login"; exit 1; }

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Settings keep their history (Table 33)"

is "$(code GET /config/policies "" "$CT")" 200 "cashier reads the rules"
python3 - <<'EOF' && ok "settings keys present (rev 603)" || bad "settings keys"
import json
p = {r["policy_key"]: r for r in json.load(open("/tmp/resp.json"))}
assert p["start_opens_minutes"]["policy_value"] == "30"
assert "start_grace_minutes" not in p and "retention_mode" not in p
assert p["heartbeat_gap_seconds"]["policy_value"] == "120"
assert p["remittance_rate_pct"]["policy_value"] in ("15.00", "15")
assert p["retention_days"]["policy_value"] == "30"
assert p["depart_zone_radius_m"]["policy_value"] == "" and p["depart_readings"]["policy_value"] == ""
assert p["home_pickup_max_route_m"]["policy_value"] == ""
assert p["chat_image_max_kb"]["policy_value"] == "10240" and p["match_window_seconds"]["policy_value"] == "120"
assert all("effective_from" in r for r in p.values())
EOF
is "$(code PUT /config/policies/start_opens_minutes '{"policy_value":"15"}' "$CT")" 403 \
   "cashier cannot change a rule"
is "$(code PUT /config/policies/remittance_rate_pct '{"policy_value":"150"}' "$OT")" 409 \
   "a rate above 100 % is refused"
is "$(code PUT /config/policies/retention_days '{"policy_value":""}' "$OT")" 409 \
   "retention cannot be unset"
is "$(code PUT /config/policies/depart_readings '{"policy_value":"0"}' "$OT")" 409 \
   "zero departure readings is refused"
is "$(code PUT /config/policies/retention_days '{"policy_value":"0"}' "$OT")" 409 \
   "a retention period of 0 days is refused"
is "$(code PUT /config/policies/heartbeat_gap_seconds '{"policy_value":"-5"}' "$OT")" 409 \
   "a negative gap is refused"

code GET /config/policies/start_opens_minutes/history "" "$OT" >/dev/null
BEFORE=$(python3 -c "import json;print(len(json.load(open('/tmp/resp.json'))))")
is "$(code PUT /config/policies/start_opens_minutes '{"policy_value":"15"}' "$OT")" 200 \
   "manager sets the start window to 15"
[ "$(j "['updated_by']" < /tmp/resp.json)" = "USER-MANAGER-0001" ] \
  && ok "the new value names who set it" || bad "updated_by missing"
code PUT /config/policies/start_opens_minutes '{"policy_value":"15"}' "$OT" >/dev/null
code GET /config/policies/start_opens_minutes/history "" "$OT" >/dev/null
python3 - "$BEFORE" <<'EOF' && ok "history: one new row, newest first; re-saving the same value adds none" || bad "history"
import json, sys
h = json.load(open("/tmp/resp.json"))
assert len(h) == int(sys.argv[1]) + 1, len(h)
assert h[0]["policy_value"] == "15" and h[0]["effective_from"] > h[1]["effective_from"]
EOF
code GET /config/policies "" "$OT" >/dev/null
python3 -c "import json;p={r['policy_key']:r for r in json.load(open('/tmp/resp.json'))};assert p['start_opens_minutes']['policy_value']=='15'" \
  && ok "the list shows the value in force" || bad "list shows an old value"
code PUT /config/policies/start_opens_minutes '{"policy_value":"30"}' "$OT" >/dev/null
is "$(code PUT /config/policies/no_such_key '{"policy_value":"1"}' "$OT")" 404 "unknown key 404"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Operators"

LIC1="R${STAMP: -10}"                       # typed without dashes
LIC1_FMT="${LIC1:0:3}-${LIC1:3:2}-${LIC1:5}"
op_json() {  # name phone licence
  echo "{\"full_name\":\"$1\",\"contact_number\":\"$2\",\"license_number\":\"$3\",\"license_expiry\":\"2029-01-31\"}"
}
is "$(code POST /fleet/operators "$(op_json 'Cash Ier' 0918$N7 $LIC1)" "$CT")" 403 \
   "cashier cannot add an operator by hand"
is "$(code POST /fleet/operators "$(op_json 'Bad Licence' 0918$N7 12345)" "$OT")" 422 \
   "a malformed licence is refused"
is "$(code POST /fleet/operators "$(op_json 'Bad Phone' 12345 $LIC1)" "$OT")" 422 \
   "a malformed phone number is refused"
is "$(code POST /fleet/operators "$(op_json 'Ramil Test' 0918$N7 $LIC1)" "$OT")" 201 \
   "manager adds an operator"
OP1=$(j "['operator_id']" < /tmp/resp.json)
[ "$(j "['license_number']" < /tmp/resp.json)" = "$LIC1_FMT" ] \
  && ok "licence kept as printed ($LIC1_FMT)" || bad "licence not normalised"
[ "$(j "['validation_status']" < /tmp/resp.json)" = "pending" ] \
  && ok "a new operator is Pending" || bad "not pending"
is "$(code POST /fleet/operators "$(op_json 'Same Licence' 0919$N7 $LIC1_FMT)" "$OT")" 409 \
   "the same licence typed with dashes is a duplicate"
is "$(code PATCH /fleet/operators/$OP1/validation '{"validation_status":"validated"}' "$CT")" 403 \
   "cashier cannot validate"
is "$(code PATCH /fleet/operators/$OP1/validation '{"validation_status":"validated"}' "$OT")" 200 \
   "manager validates the operator"
code PATCH /fleet/operators/$OP1 '{"license_expiry":"2030-01-31"}' "$OT" >/dev/null
[ "$(j "['validation_status']" < /tmp/resp.json)" = "pending" ] \
  && ok "a renewed licence goes back to Pending for re-validation" || bad "edit kept validated"
code PATCH /fleet/operators/$OP1/validation '{"validation_status":"validated"}' "$OT" >/dev/null
is "$(code PATCH /fleet/operators/$OP1 '{"license_number":null}' "$OT")" 422 \
   "a required field cannot be blanked"

LIC2="S${STAMP: -10}"
code POST /fleet/operators "$(op_json 'Second Owner' 0920$N7 $LIC2)" "$OT" >/dev/null
OP2=$(j "['operator_id']" < /tmp/resp.json)

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Vans"

PLATE1="RSA-$N4"
is "$(code POST /fleet/vans "{\"plate_number\":\"rsa $N4\"}" "$OT")" 422 \
   "a van needs its operator"
is "$(code POST /fleet/vans "{\"plate_number\":\"rsa $N4\",\"operator_id\":\"$OP1\",\"registered_route_id\":\"NOPE\"}" "$OT")" 404 \
   "an unknown route is refused"
is "$(code POST /fleet/vans "{\"plate_number\":\"rsa $N4\",\"operator_id\":\"$OP1\",\"cpc_case_no\":\"2019-0457\"}" "$OT")" 201 \
   "manager adds a van with its operator"
VAN1=$(j "['van_id']" < /tmp/resp.json)
[ "$(j "['plate_number']" < /tmp/resp.json)" = "$PLATE1" ] \
  && ok "plate kept as $PLATE1" || bad "plate not normalised"
is "$(code POST /fleet/vans "{\"plate_number\":\"RSB-$N4\",\"operator_id\":\"$OP1\"}" "$OT")" 409 \
   "one van per operator"
is "$(code POST /fleet/vans "{\"plate_number\":\"$PLATE1\",\"operator_id\":\"$OP2\"}" "$OT")" 409 \
   "duplicate plate refused"
is "$(code PATCH /fleet/vans/$VAN1/validation '{"validation_status":"validated"}' "$OT")" 409 \
   "a van cannot be validated without its four photos"

"$PY" -c "
import struct, zlib, sys
raw = b'\x00\xff\xff\xff'
png = b'\x89PNG\r\n\x1a\n'
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
png += chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)" "$TMP/van.png"
echo "not an image" > "$TMP/fake.png"
is "$(up PUT /fleet/vans/$VAN1/photos/front image "$TMP/fake.png" "$CT")" 422 \
   "a file that is not an image is refused, whatever its name"
for side in front rear left; do
  up PUT /fleet/vans/$VAN1/photos/$side image "$TMP/van.png" "$OT" >/dev/null
done
is "$(up PUT /fleet/vans/$VAN1/photos/right image "$TMP/van.png" "$CT")" 200 \
   "cashier uploads the fourth photo"
URL=$(j "['photo_right_url']" < /tmp/resp.json)
is "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8000$URL")" 200 "photo is served"
is "$(code PATCH /fleet/vans/$VAN1/validation '{"validation_status":"validated"}' "$OT")" 200 \
   "with four photos the van validates"
up PUT /fleet/vans/$VAN1/photos/front image "$TMP/van.png" "$CT" >/dev/null
[ "$(j "['validation_status']" < /tmp/resp.json)" = "pending" ] \
  && ok "a replaced photo returns the van to Pending" || bad "photo change kept validated"
code PATCH /fleet/vans/$VAN1/validation '{"validation_status":"validated"}' "$OT" >/dev/null
is "$(code PATCH /fleet/vans/$VAN1 "{\"operator_id\":\"$OP2\"}" "$OT")" 200 \
   "the van can pass to an operator with no van"
[ "$(j "['operator_name']" < /tmp/resp.json)" = "Second Owner" ] \
  && ok "van now shows its new operator" || bad "operator not changed"
code PATCH /fleet/vans/$VAN1 "{\"operator_id\":\"$OP1\"}" "$OT" >/dev/null
code PATCH /fleet/vans/$VAN1/validation '{"validation_status":"validated"}' "$OT" >/dev/null

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. Dispatchers"

is "$(code PATCH /fleet/crew/USER-DISPATCHER-0001/validation '{"validation_status":"validated"}' "$OT")" 200 \
   "manager validates a Dispatcher"
is "$(code PATCH /fleet/crew/USER-CASHIER-0001/validation '{"validation_status":"validated"}' "$OT")" 409 \
   "office staff are not on the roster"
code GET "/fleet/crew?role=dispatcher" "" "$OT" >/dev/null
python3 -c "import json;d={c['user_id']:c for c in json.load(open('/tmp/resp.json'))};assert d['USER-DISPATCHER-0001']['validation_status']=='validated'" \
  && ok "crew list shows the validation" || bad "crew list"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Import with preview"

is "$(get /roster/templates/operators?format=csv "$TMP/t.csv" "$CT")" 200 "operators CSV template"
head -1 "$TMP/t.csv" | grep -q "full_name,contact_number,email,license_number,license_expiry" \
  && ok "template header is the import's columns" || bad "template header"
is "$(get /roster/templates/vans "$TMP/t.xlsx" "$CT")" 200 "vans Excel template"
[ "$(head -c 2 "$TMP/t.xlsx")" = "PK" ] && ok "template is a real .xlsx" || bad "not xlsx"

LA="T${STAMP: -10}"; LB="U${STAMP: -10}"
cat > "$TMP/ops.csv" <<EOF
Full Name,Contact Number,Email,License Number,License Expiry
Imported Alpha,921$N7,alpha$N4@example.com,$LA,2029-05-31
Imported Beta,0922$N7,,$LB,06/30/2029
Bad Licence,0923$N7,,ABC,2029-01-01
Dup Contact,0921$N7,,V${STAMP: -10},2029-01-01
Seeded Licence,0924$N7,,N01-23-456789,2029-01-01
,,,,
,0925$N7,,W${STAMP: -10},not-a-date
EOF
OPS_BEFORE=$(count /fleet/operators)
is "$(up POST /roster/import/operators/preview file "$TMP/ops.csv" "$CT")" 200 "cashier previews an operators file"
python3 - <<'EOF' && ok "preview: 2 pass, 4 fail, each with its reason; blank row skipped" || bad "preview counts"
import json
d = json.load(open("/tmp/resp.json"))
assert (d["rows_in_file"], d["rows_passing"], d["rows_failing"]) == (6, 2, 4), d
why = {r["row"]: " ".join(r["errors"]) for r in d["rows"]}
assert "license_number" in why[4]
assert "row 2" in why[5]                      # contact repeats row 2 (leading 0 restored)
assert "already on the roster" in why[6]
assert "full_name is required" in why[8] and "license_expiry" in why[8]
EOF
is "$(count /fleet/operators)" "$OPS_BEFORE" "a preview saves nothing"

is "$(up POST /roster/import/operators file "$TMP/ops.csv" "$CT")" 201 "cashier confirms the import"
BATCH=$(j "['transfer']['transfer_id']" < /tmp/resp.json)
python3 - <<'EOF' && ok "logged: 6 rows, 2 accepted, 4 rejected, rejected file linked" || bad "transfer log"
import json
t = json.load(open("/tmp/resp.json"))["transfer"]
assert (t["direction"], t["rows_in_file"], t["rows_accepted"], t["rows_rejected"]) == ("import", 6, 2, 4)
assert t["error_file_url"].endswith("/rejected")
EOF
is "$(count /fleet/operators)" "$((OPS_BEFORE + 2))" "two operators saved"
code GET "/fleet/operators?validation_status=pending" "" "$OT" >/dev/null
python3 - "$BATCH" <<'EOF' && ok "imported operators are Pending under their batch" || bad "batch marking"
import json, sys
mine = [o for o in json.load(open("/tmp/resp.json")) if o["import_batch_id"] == sys.argv[1]]
assert len(mine) == 2 and all(o["validation_status"] == "pending" for o in mine)
EOF
is "$(get /roster/transfers/$BATCH/rejected "$TMP/rejected.csv" "$CT")" 200 "rejected rows download"
python3 - "$TMP/rejected.csv" <<'EOF' && ok "rejected file: template columns plus a reason, 4 rows" || bad "rejected file"
import csv, sys
rows = list(csv.reader(open(sys.argv[1], encoding="utf-8-sig")))
assert rows[0][-1] == "reason" and len(rows) == 5, rows
EOF
is "$(up POST /roster/import/operators/preview file "$TMP/rejected.csv" "$CT")" 200 \
   "the rejected file uploads again as it is"
[ "$(j "['rows_failing']" < /tmp/resp.json)" = "4" ] && ok "its rows still fail until corrected" || bad "re-upload"

ALPHA=$(code GET /fleet/operators "" "$OT" >/dev/null; python3 -c "import json;print([o['operator_id'] for o in json.load(open('/tmp/resp.json')) if o['full_name']=='Imported Alpha' and o['import_batch_id']=='$BATCH'][0])")
is "$(code PATCH /fleet/operators/$ALPHA/validation '{"validation_status":"validated"}' "$OT")" 200 \
   "the manager validates what the cashier imported"

# The manager imports, and may not then be the one who approves it.
LM="X${STAMP: -10}"
printf 'full_name,contact_number,license_number,license_expiry\nSelf Approved,0926%s,%s,2029-01-01\n' "$N7" "$LM" > "$TMP/self.csv"
up POST /roster/import/operators file "$TMP/self.csv" "$OT" >/dev/null
SELF=$(code GET /fleet/operators "" "$OT" >/dev/null; python3 -c "import json;print([o['operator_id'] for o in json.load(open('/tmp/resp.json')) if o['full_name']=='Self Approved' and o['license_number'].replace('-','')=='$LM'][0])")
is "$(code PATCH /fleet/operators/$SELF/validation '{"validation_status":"validated"}' "$OT")" 403 \
   "whoever imported a record cannot validate it themselves"
is "$(code PATCH /fleet/operators/$SELF/validation '{"validation_status":"rejected"}' "$OT")" 200 \
   "they may still reject it"

"$PY" - "$TMP/vans.xlsx" "$LA" "$LB" "$N4" <<'EOF'
import sys
from openpyxl import Workbook
out, la, lb, n4 = sys.argv[1:]
wb = Workbook(); ws = wb.active
ws.append(["plate_number", "operator_license_number", "cpc_case_no", "cpc_number",
           "brand", "model", "color", "seat_capacity", "registered_route"])
ws.append([f"IMA {n4}", la, "2020-1188", "CPC-55021", "Toyota", "HiAce", "White", 14, "ECO-TAG"])
ws.append([f"IMB {n4}", la, None, None, None, None, None, None, None])      # Alpha again
ws.append([f"IMC {n4}", "Z9999999999", None, None, None, None, None, None, None])
ws.append([f"IMD {n4}", lb, None, None, None, None, None, 18, "NOPE-RTE"])
ws.append(["12", lb, None, None, None, None, None, None, None])
wb.save(out)
EOF
is "$(up POST /roster/import/vans file "$TMP/vans.xlsx" "$CT")" 201 "cashier imports a vans .xlsx"
python3 - <<'EOF' && ok "vans: 1 saved; second van for one operator, unknown operator, bad seats/route, bad plate refused" || bad "vans import"
import json
d = json.load(open("/tmp/resp.json"))
assert (d["rows_passing"], d["rows_failing"]) == (1, 4), d
why = {r["row"]: " ".join(r["errors"]) for r in d["rows"]}
assert "one van per operator" in why[3]
assert "import operators first" in why[4]
assert "seat_capacity" in why[5] and "no route" in why[5]
assert "plate_number" in why[6]
EOF
printf 'plate_number\nABC-1111\n' > "$TMP/nocol.csv"
is "$(up POST /roster/import/vans/preview file "$TMP/nocol.csv" "$CT")" 422 "a file missing a required column is refused"
is "$(up POST /roster/import/vans/preview file "$TMP/van.png" "$CT")" 422 "a file that is not CSV or .xlsx is refused"
is "$(up POST /roster/import/dispatchers/preview file "$TMP/ops.csv" "$CT")" 422 "Dispatchers are not imported"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "6. Export, logged"

is "$(get "/roster/export/vans?purpose=ltfrb_check" "$TMP/ltfrb.csv" "$CT")" 200 "cashier exports the LTFRB check list"
head -1 "$TMP/ltfrb.csv" | grep -q "plate_number,cpc_case_no,cpc_number,operator,validation_status,validated_on" \
  && ok "LTFRB list: plate, CPC, operator, validation and date" || bad "ltfrb columns"
grep -q "$PLATE1" "$TMP/ltfrb.csv" && ok "our van is on it" || bad "van missing"
is "$(get "/roster/export/operators?format=pdf" "$TMP/ops.pdf" "$OT")" 200 "operators as PDF"
[ "$(head -c 4 "$TMP/ops.pdf")" = "%PDF" ] && ok "a real PDF" || bad "not a PDF"
is "$(code GET "/roster/export/operators?purpose=ltfrb_check" "" "$CT")" 422 "the LTFRB list is vans only"
is "$(get /roster/export/dispatchers "$TMP/dsp.csv" "$CT")" 200 "Dispatchers export"
is "$(get /roster/export/vans "$TMP/vans_backup.csv" "$CT")" 200 "vans backup"
is "$(up POST /roster/import/vans/preview file "$TMP/vans_backup.csv" "$CT")" 200 "a backup reads as an import file"
python3 -c "import json;d=json.load(open('/tmp/resp.json'));assert d['rows_passing']==0 and all('already on the roster' in ' '.join(r['errors']) for r in d['rows'])" \
  && ok "and every row is recognised as already on the roster" || bad "backup round trip"
code GET /roster/transfers "" "$CT" >/dev/null
python3 - <<'EOF' && ok "the log holds the exports with their purpose and format" || bad "transfer log"
import json
t = json.load(open("/tmp/resp.json"))
assert any(x["direction"] == "export" and x["export_purpose"] == "ltfrb_check" for x in t)
assert any(x["direction"] == "export" and x["file_format"] == "pdf" for x in t)
assert all(x["performed_by_name"] for x in t[:5])
EOF
is "$(code GET /roster/transfers "" "$(login dispatcher)")" 403 "a Dispatcher cannot read the log"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. Phone pool"

is "$(code POST /devices '{"device_model":"realme 5G"}' "$CT")" 403 "only the manager adds a phone"
is "$(code POST /devices '{"device_model":"realme 5G","android_version":"14"}' "$OT")" 201 "manager adds a phone"
PH1=$(j "['device_id']" < /tmp/resp.json)
[ "$(j "['status']" < /tmp/resp.json)" = "in_office" ] && [ "$(j "['silent']" < /tmp/resp.json)" = "True" ] \
  && ok "in the office; silent until the edge app reports" || bad "new phone state"
code POST /devices '{"device_model":"realme spare"}' "$OT" >/dev/null
PH2=$(j "['device_id']" < /tmp/resp.json)

is "$(code POST /devices/$PH1/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-CASHIER-0001\"}" "$CT")" 404 \
   "a phone goes out only with a Dispatcher"
is "$(code POST /devices/$PH1/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-DISPATCHER-0001\"}" "$CT")" 200 \
   "cashier checks the phone out to a Dispatcher and van"
python3 - "$PLATE1" <<'EOF' && ok "checked out, showing van and Dispatcher, warned it never reported" || bad "checkout body"
import json, sys
d = json.load(open("/tmp/resp.json"))
assert d["device"]["status"] == "checked_out"
assert d["device"]["checkout"]["plate_number"] == sys.argv[1]
assert any("never sent" in w for w in d["warnings"])
EOF
is "$(code POST /devices/$PH1/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-DISPATCHER-0001\"}" "$CT")" 409 \
   "a phone cannot go out twice"
is "$(code POST /devices/$PH2/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-DISPATCHER-0001\"}" "$CT")" 409 \
   "a van cannot have two phones out"
is "$(code POST /devices/$PH1/retire "" "$OT")" 409 "a phone that is out cannot be retired"
is "$(code POST /devices/$PH1/return '{"return_note":"Screen fine, charger cable frayed"}' "$CT")" 200 \
   "cashier records the return and its condition"
[ "$(j "['status']" < /tmp/resp.json)" = "in_office" ] && ok "back in the office" || bad "status after return"
is "$(code POST /devices/$PH1/return '{}' "$CT")" 409 "a phone already in cannot be returned again"
is "$(code POST /devices/$PH2/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-DISPATCHER-0001\"}" "$OT")" 200 \
   "the van can take another phone once the first is back"
code POST /devices/$PH2/return '{}' "$OT" >/dev/null
is "$(code POST /devices/$PH1/retire "" "$CT")" 403 "only the manager retires a phone"
is "$(code POST /devices/$PH1/retire "" "$OT")" 200 "manager retires the phone"
is "$(code POST /devices/$PH1/checkout "{\"van_id\":\"$VAN1\",\"dispatcher_id\":\"USER-DISPATCHER-0001\"}" "$OT")" 409 \
   "a retired phone cannot go out"
code GET /devices "" "$CT" >/dev/null
python3 -c "import json;assert '$PH1' not in [d['device_id'] for d in json.load(open('/tmp/resp.json'))]" \
  && ok "retired phones are left off the pool list" || bad "retired listed"
code GET "/devices?include_retired=true" "" "$CT" >/dev/null
python3 -c "import json;assert '$PH1' in [d['device_id'] for d in json.load(open('/tmp/resp.json'))]" \
  && ok "but kept on record" || bad "retired row lost"

printf '\n%d passed, %d failed\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
