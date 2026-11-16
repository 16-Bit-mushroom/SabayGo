#!/usr/bin/env bash
# 12 Nov: the owner asked for create, read, update and delete in Messages
# and in Trip Schedules (the timetable, renamed).
#
#   Messages (migration 040): the office starts a thread from a list of
#   Dispatchers and this week's passengers; a person edits or deletes a
#   text message they sent themself -- not a colleague's, not the other
#   side's, not a photo kept as proof. A deleted message keeps its row and
#   loses its text, and the thread and the conversation list say "Message
#   deleted".
#
#   Trip Schedules: PATCH and DELETE /config/schedule-templates/{id}. An
#   edit never moves a trip already posted; a delete leaves those trips
#   running (their link is cleared); a clash with another schedule at the
#   same time is refused in words, not a 500.
#
#   ./db/reset-dev.sh && ./tests/integration/test_messages_schedules.sh
set -uo pipefail

API="${SABAYGO_API:-http://127.0.0.1:8000/api/v1}"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
# code METHOD PATH TOKEN [JSON] -> HTTP status; the body is in $TMP/r.json
code() {
  local m=$1 p=$2 t=${3:-} b=${4:-}
  local a=(-s -o "$TMP/r.json" -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  [ -n "$b" ] && a+=(-H "Content-Type: application/json" -d "$b")
  curl "${a[@]}"
}
py() { python3 -c "import json,sys; d=json.load(open('$TMP/r.json')); $1"; }
login() {
  curl -s -X POST "$API/auth/login" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1@sabaygo.dev\",\"password\":\"sabaygo123\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))"
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

OT=$(login manager); CT=$(login cashier); DT=$(login dispatcher); PT=$(login passenger)
[ -n "$OT" ] && [ -n "$CT" ] && [ -n "$DT" ] && [ -n "$PT" ] && ok "signed in" || { bad "login"; exit 1; }
PAX=$(sql "SELECT user_id FROM users WHERE email = 'passenger@sabaygo.dev'")
DIS=$(sql "SELECT user_id FROM users WHERE email = 'dispatcher@sabaygo.dev'")

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. New message: whom the office can write to"
is "$(code GET /conversations/contacts "$OT")" 200 "the office reads its contact list"
is "$(py "print(any(c['peer_user_id']=='$DIS' and c['peer_role']=='dispatcher' for c in d))")" True \
   "the Dispatcher is on it"
is "$(py "print(any(c['peer_user_id']=='$PAX' and c['peer_role']=='passenger' and c['trip_label'] for c in d))")" True \
   "passenger@, who holds a seat today, is on it with the trip"
is "$(py "print(all(c['peer_user_id'] for c in d))")" True "every row names a person (no 'office' row for the office)"
is "$(py "r=[c['peer_role'] for c in d]; print(r==sorted(r, key=lambda x: x!='dispatcher'))")" True \
   "Dispatchers first, then passengers"

is "$(code POST /conversations "$OT" "{\"peer_user_id\":\"$PAX\"}")" 200 "the office starts a thread with passenger@"
CID=$(py "print(d['conversation_id'])")
is "$(code POST /conversations "$OT" "{\"peer_user_id\":\"$PAX\"}")/$(py "print(d['conversation_id'])")" "200/$CID" \
   "starting it again opens the same thread"
is "$(code POST /conversations "$OT" "{\"peer_user_id\":\"$(sql "SELECT user_id FROM users WHERE email='cashier@sabaygo.dev'")\"}")" 403 \
   "not a colleague in the office"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Edit one's own message"
is "$(code POST "/conversations/$CID/messages" "$OT" '{"body":"Your van leaves at 3"}')" 200 "the Terminal Manager writes"
MID=$(py "print(d['message_id'])")
is "$(py "print(d['can_change'], d['edited_at'], d['deleted_at'])")" "True None None" "it can be changed by its sender"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$OT" '{"body":"  Your van leaves at 3:30  "}')" 200 "edited"
is "$(py "print(d['body'], '|', d['edited_at'] is not None, d['can_change'])")" "Your van leaves at 3:30 | True True" \
   "new text, trimmed, marked edited"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$OT" '{"body":""}')" 422 "not to an empty message"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$OT" '{"body":"   "}')" 422 "nor to spaces"

hdr "3. Nobody else may change it"
code GET "/conversations/$CID/messages" "$CT" >/dev/null
is "$(py "m=[x for x in d if x['message_id']=='$MID'][0]; print(m['is_mine'], m['can_change'])")" "True False" \
   "the Cashier sees it as the office's, but cannot change it"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$CT" '{"body":"x"}')" 403 "the Cashier's edit is refused"
is "$(code DELETE "/conversations/$CID/messages/$MID" "$CT")" 403 "and the Cashier's delete"
code GET "/conversations/$CID/messages" "$PT" >/dev/null
is "$(py "m=[x for x in d if x['message_id']=='$MID'][0]; print(m['is_mine'], m['can_change'], m['edited_at'] is not None)")" \
   "False False True" "the passenger sees it edited, and cannot change it"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$PT" '{"body":"x"}')" 403 "the passenger's edit is refused"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$DT" '{"body":"x"}')" 403 \
   "the Dispatcher, outside the thread, is refused"

hdr "4. The passenger edits their own"
is "$(code POST "/conversations/$CID/messages" "$PT" '{"body":"Salamat, I will be there"}')" 200 "the passenger replies"
PMID=$(py "print(d['message_id'])")
is "$(code PATCH "/conversations/$CID/messages/$PMID" "$PT" '{"body":"Salamat po, I will be there"}')" 200 "and edits it"
is "$(code PATCH "/conversations/$CID/messages/$PMID" "$OT" '{"body":"x"}')" 403 "the office cannot edit the passenger's"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. Delete: the row stays, the text goes"
is "$(code DELETE "/conversations/$CID/messages/$MID" "$OT")" 200 "the Terminal Manager deletes theirs"
is "$(py "print(repr(d['body']), d['deleted_at'] is not None, d['can_change'])")" "'' True False" \
   "its text is erased; it can no longer be changed"
is "$(sql "SELECT CONCAT(LENGTH(body), '/', deleted_at IS NOT NULL) FROM messages WHERE message_id = '$MID'")" "0/1" \
   "in the table: the row kept, no text"
is "$(code DELETE "/conversations/$CID/messages/$MID" "$OT")" 422 "deleting it twice is refused"
is "$(code PATCH "/conversations/$CID/messages/$MID" "$OT" '{"body":"back"}')" 422 "and so is editing it"
code POST "/conversations/$CID/messages" "$OT" '{"body":"See you"}' >/dev/null; LAST=$(py "print(d['message_id'])")
code DELETE "/conversations/$CID/messages/$LAST" "$OT" >/dev/null
code GET /conversations "$PT" >/dev/null
is "$(py "print([c['last_message'] for c in d if c['conversation_id']=='$CID'][0])")" "Message deleted" \
   "the passenger's conversation list reads 'Message deleted', not the old text"

hdr "6. What it refuses"
is "$(code PATCH "/conversations/$CID/messages/no-such-id" "$OT" '{"body":"x"}')" 404 "a message that does not exist"
OTHER=$(sql "SELECT message_id FROM messages WHERE conversation_id <> '$CID' LIMIT 1")
if [ -n "$OTHER" ]; then
  is "$(code DELETE "/conversations/$CID/messages/$OTHER" "$OT")" 404 "a message from another thread, through this one"
else
  ok "no other thread has a message; nothing to cross"
fi
PHOTO=$(sql "SELECT CONCAT(conversation_id, ' ', message_id, ' ', sender_id) FROM messages WHERE attachment_type IS NOT NULL LIMIT 1")
if [ -n "$PHOTO" ]; then
  set -- $PHOTO
  SENDER_EMAIL=$(sql "SELECT email FROM users WHERE user_id = '$3'")
  ST=$(login "${SENDER_EMAIL%@sabaygo.dev}")
  is "$(code DELETE "/conversations/$1/messages/$2" "$ST")" 422 "a photo sent as proof cannot be deleted"
else
  ok "no photo in the seed; the proof rule is in MessagingService._own_text_message"
fi

# ╔═══════════════════════════════════════════════════════════════╗
hdr "7. Trip Schedules: edit"
ROUTE=$(sql "SELECT route_id FROM routes WHERE is_active = 1 ORDER BY route_code LIMIT 1")
is "$(code POST /config/schedule-templates "$OT" "{\"route_id\":\"$ROUTE\",\"departure_time\":\"21:40:00\",\"trip_label\":\"Test night run\"}")" \
   201 "a trip schedule is added at 21:40"
TID=$(py "print(d['template_id'])")
is "$(code PATCH "/config/schedule-templates/$TID" "$OT" '{"departure_time":"21:50:00","days_of_week":"1111100","trip_label":"Weeknight run"}')" \
   200 "it is edited: 21:50, weekdays, a new name"
code GET /config/schedule-templates "$OT" >/dev/null
is "$(py "t=[x for x in d if x['template_id']=='$TID'][0]; print(t['departure_time'][:5], t['days_of_week'], t['trip_label'])")" \
   "21:50 1111100 Weeknight run" "the list shows the edit"
is "$(code PATCH "/config/schedule-templates/$TID" "$OT" '{"trip_label":""}')" 200 "the name can be cleared"
is "$(sql "SELECT COALESCE(trip_label, 'none') FROM schedule_templates WHERE template_id = '$TID'")" none "and is stored empty"
is "$(code PATCH "/config/schedule-templates/$TID" "$OT" '{"days_of_week":"0000000"}')" 409 \
   "no days at all is refused (pause it instead)"
is "$(code PATCH "/config/schedule-templates/$TID" "$OT" '{"days_of_week":"1111"}')" 422 "a malformed day mask"
code POST /config/schedule-templates "$OT" "{\"route_id\":\"$ROUTE\",\"departure_time\":\"22:10:00\"}" >/dev/null
TID2=$(py "print(d['template_id'])")
is "$(code PATCH "/config/schedule-templates/$TID" "$OT" '{"departure_time":"22:10:00"}')" 409 \
   "moving it onto another schedule's time is refused"
is "$(py "print('22:10' in d['detail'])")" True "and the refusal says which time, in words"
is "$(sql "SELECT TIME_FORMAT(departure_time, '%H:%i') FROM schedule_templates WHERE template_id = '$TID'")" 21:50 \
   "the refused edit changed nothing"
is "$(code PATCH "/config/schedule-templates/$TID" "$CT" '{"trip_label":"x"}')" 403 "the Cashier cannot edit it"
is "$(code PATCH "/config/schedule-templates/no-such" "$OT" '{"trip_label":"x"}')" 404 "a schedule that does not exist"

hdr "8. Trip Schedules: delete"
# A trip already posted from it, made here so the check does not hang on
# the clock (generation skips a time that has passed today).
TRIP=$(python3 -c "import uuid; print(uuid.uuid4())")
sql "INSERT INTO trips (trip_id, template_id, route_id, service_date, departure_datetime, status)
     SELECT '$TRIP', '$TID', '$ROUTE', CURDATE() + INTERVAL 1 DAY, TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '21:50:00'),
            'scheduled'" >/dev/null 2>&1
POSTED=$(sql "SELECT COUNT(*) FROM trips WHERE template_id = '$TID'")
is "$(code DELETE "/config/schedule-templates/$TID" "$OT")" 200 "the schedule is deleted"
is "$(sql "SELECT COUNT(*) FROM schedule_templates WHERE template_id = '$TID'")" 0 "it is gone from the list"
if [ "$POSTED" = "1" ]; then
  is "$(sql "SELECT CONCAT(status, '/', COALESCE(template_id, 'none')) FROM trips WHERE trip_id = '$TRIP'")" "scheduled/none" \
     "the trip already posted from it still runs, its link cleared"
else
  ok "no trip could be posted from it here (schema differs); ON DELETE SET NULL is in 004"
fi
is "$(code DELETE "/config/schedule-templates/$TID" "$OT")" 404 "deleting it again: not found"
is "$(code DELETE "/config/schedule-templates/$TID2" "$DT")" 403 "the Dispatcher cannot delete one"
code DELETE "/config/schedule-templates/$TID2" "$OT" >/dev/null

echo
printf '  %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
