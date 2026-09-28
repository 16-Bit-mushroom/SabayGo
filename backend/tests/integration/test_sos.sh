#!/usr/bin/env bash
# SOS emergency alerts (spec 2.3.5).
#
# What this proves, in order:
#   the alert survives a dead SMS gateway; the office is told in-app;
#   a repeat press does not raise a second emergency; a passenger cannot
#   raise an alert against a trip they are not on; the office must write
#   a note to close one; and the person who pressed the button is told
#   when a human has seen it.
set -uo pipefail
API="http://127.0.0.1:8000/api/v1"
TRIP="TRIP-DEMO-00000001"
P=0; F=0
curl -sf http://127.0.0.1:8000/health >/dev/null || { echo "API not running"; exit 1; }

j(){ python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
hdr(){ printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok(){ printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad(){ printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
code(){ local m=$1 p=$2 d=${3:-} t=${4:-}
  local a=(-s -o /tmp/sos.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$d" ] && a+=(-H "Content-Type: application/json" -d "$d")
  curl "${a[@]}"; }
login(){ curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"$1\",\"password\":\"sabaygo123\"}" | j "['access_token']"; }

CT=$(login conductor@sabaygo.dev)
OT=$(login coopadmin@sabaygo.dev)
PT=$(login passenger@sabaygo.dev)

# Re-runnable without a database reset: an alert left open by an earlier
# run would be returned as a duplicate and every count below would read
# zero. Closing them first is setup, not a shortcut -- the office closing
# an emergency is exactly what the endpoint under test does.
for id in $(curl -s -H "Authorization: Bearer $OT" "$API/sos?status=open&limit=200" \
            | python3 -c "import json,sys;print(' '.join(a['sos_id'] for a in json.load(sys.stdin)))"); do
  code POST "/sos/$id/resolve" '{"notes":"Closed by the test harness."}' "$OT" >/dev/null
done

hdr "conductor raises an SOS from the van"
S=$(code POST /sos "{\"trip_id\":\"$TRIP\",\"category\":\"medical\",\"note\":\"Passenger collapsed\",\"latitude\":7.0731,\"longitude\":125.6128,\"accuracy_m\":12}" "$CT")
SOS=$(j "['sos_id']" < /tmp/sos.json)
[ "$S" = "201" ] && [ -n "$SOS" ] \
  && ok "alert recorded ($SOS)" || bad "raise gave $S"
python3 -c "
import json;r=json.load(open('/tmp/sos.json'))
print(f\"        in-app  : {r['notified_in_app']} recipient(s)\")
print(f\"        sms     : attempted {r['sms']['attempted']}, sent {r['sms']['sent']}, skipped {r['sms']['skipped']}\")
print(f\"        told    : {r['message']}\")"

hdr "the alert survives a silent SMS channel"
SENT=$(j "['sms']['sent']" < /tmp/sos.json)
NOTIF=$(j "['notified_in_app']" < /tmp/sos.json)
[ "$NOTIF" -ge 1 ] \
  && ok "office alerted in-app even with $SENT SMS delivered" \
  || bad "nobody was notified in-app"

hdr "a repeat press does not raise a second emergency"
code POST /sos "{\"trip_id\":\"$TRIP\",\"category\":\"medical\"}" "$CT" >/dev/null
DUP=$(j "['duplicate']" < /tmp/sos.json)
SAME=$(j "['sos_id']" < /tmp/sos.json)
[ "$DUP" = "True" ] && [ "$SAME" = "$SOS" ] \
  && ok "second press returned the open alert, not a new one" \
  || bad "duplicate=$DUP id=$SAME"

hdr "a passenger cannot raise an alert against a trip they are not on"
S=$(code POST /sos "{\"trip_id\":\"TRIP-A2Z-DIG-D0-0630\",\"category\":\"security\"}" "$PT")
[ "$S" = "403" ] && ok "refused (403): no booking on that trip" || bad "gave $S, expected 403"

hdr "an SOS with no trip is always allowed"
S=$(code POST /sos '{"category":"security","note":"Followed at the terminal"}' "$PT")
PSOS=$(j "['sos_id']" < /tmp/sos.json)
[ "$S" = "201" ] && ok "terminal-side alert accepted ($PSOS)" || bad "gave $S"

hdr "crew cannot read the office queue"
S=$(code GET /sos "" "$CT")
[ "$S" = "403" ] && ok "queue is office-only (403)" || bad "gave $S, expected 403"

hdr "office sees both alerts, newest first"
code GET "/sos?status=open" "" "$OT" >/dev/null
python3 -c "
import json;d=json.load(open('/tmp/sos.json'))
for a in d[:4]:
    loc = a['map_url'] or 'no location'
    print(f\"        {a['status']:<12} {a['category']:<9} {a['raised_by_role']:<10} {a['raised_by']:<22} {loc}\")"
N=$(python3 -c "import json;print(len(json.load(open('/tmp/sos.json'))))")
[ "$N" -ge 2 ] && ok "$N open alert(s) in the queue" || bad "queue holds $N"

hdr "closing an emergency without a note is refused"
S=$(code POST "/sos/$SOS/resolve" '{}' "$OT")
[ "$S" = "409" ] && ok "a closed emergency must say what happened (409)" || bad "gave $S"

hdr "office acknowledges; the raiser is told a human has it"
S=$(code POST "/sos/$SOS/acknowledge" "" "$OT")
[ "$S" = "200" ] && ok "acknowledged" || bad "acknowledge gave $S"
code GET "/notifications?unread_only=true" "" "$CT" >/dev/null
python3 -c "
import json,sys
d=json.load(open('/tmp/sos.json'))
hit=[n for n in d['items'] if n['type']=='sos_alert' and 'been seen' in n['title']]
print('        conductor inbox:', hit[0]['message'] if hit else 'NOTHING')
sys.exit(0 if hit else 1)" \
  && ok "the person who pressed the button was told" \
  || bad "raiser got no acknowledgement"

hdr "acknowledging twice is refused"
S=$(code POST "/sos/$SOS/acknowledge" "" "$OT")
[ "$S" = "409" ] && ok "already acknowledged (409)" || bad "gave $S"

hdr "office resolves with a note"
S=$(code POST "/sos/$SOS/resolve" '{"notes":"Ambulance met the van at Panabo. Passenger stable."}' "$OT")
[ "$S" = "200" ] && ok "resolved" || bad "resolve gave $S"
code GET "/sos?status=resolved" "" "$OT" >/dev/null
python3 -c "
import json;d=json.load(open('/tmp/sos.json'))
a=[x for x in d if x['sos_id']=='$SOS'][0]
print(f\"        {a['status']}  by {a['acknowledged_by']}  -- {a['resolution_notes']}\")"

hdr "a resolved alert clears the way for the next one"
S=$(code POST /sos "{\"trip_id\":\"$TRIP\",\"category\":\"breakdown\"}" "$CT")
DUP=$(j "['duplicate']" < /tmp/sos.json)
[ "$S" = "201" ] && [ "$DUP" = "False" ] \
  && ok "a new emergency is a new alert once the last is closed" \
  || bad "status $S duplicate=$DUP"

printf '\n\033[1mSOS: %d passed, %d failed\033[0m\n' "$P" "$F"
exit $(( F > 0 ? 1 : 0 ))
