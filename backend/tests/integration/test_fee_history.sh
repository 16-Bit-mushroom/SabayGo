#!/usr/bin/env bash
# 10 Nov: GET /statements/history, the Money chart's data. What the
# statements recorded over the last N days, by day or by month: the fares
# on the passenger lists (B + W), the terminal fees owed (with any share
# held from a trip that left unpaid) and the amount paid. Recorded sums,
# never estimates; a day with no statement is a recorded zero.
#
#   ./db/reset-dev.sh && ./tests/integration/test_fee_history.sh
#
# The demo seed puts statements on today (TRIP-A2Z-LIVE-BOARD and its
# neighbours), which is what section 3 adds up.
set -uo pipefail

API="${SABAYGO_API:-http://127.0.0.1:8000/api/v1}"
BACKEND="$(cd "$(dirname "$0")/../.." && pwd)"
P=0; F=0
hdr() { printf '\n\033[1m── %s ─────────────────────\033[0m\n' "$1"; }
ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; P=$((P+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; F=$((F+1)); }
is()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got $1, wanted $2)"; }
code() {
  local m=$1 p=$2 t=${3:-}
  local a=(-s -o /tmp/fh.json -w "%{http_code}" -X "$m" "$API$p")
  [ -n "$t" ] && a+=(-H "Authorization: Bearer $t")
  curl "${a[@]}"
}
py() { python3 -c "import json,sys; d=json.load(open('/tmp/fh.json')); $1"; }
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
TODAY=$(sql "SELECT CURDATE()")

# ╔═══════════════════════════════════════════════════════════════╗
hdr "1. Who reads it: the office, as for the day's statements"
is "$(code GET "/statements/history?days=7" "$CT")" 200 "the Cashier"
is "$(code GET "/statements/history?days=7" "$OT")" 200 "the Terminal Manager"
is "$(code GET "/statements/history?days=7" "$DT")/$(code GET "/statements/history?days=7" "$PT")" 403/403 \
   "not the Dispatcher, not a passenger"
is "$(code GET "/statements/history?days=7")" 401 "not without signing in"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "2. Its shape: one entry per day, or per month, ending today"
code GET "/statements/history?days=7" "$CT" >/dev/null
is "$(py "print(len(d))")" 7 "7 days give 7 entries"
is "$(py "print(d[-1]['period'])")" "$TODAY" "the last is today"
is "$(py "
import datetime as t
p=[t.date.fromisoformat(x['period']) for x in d]
print(all((b-a).days==1 for a,b in zip(p,p[1:])))")" True "consecutive days, no holes"
code GET "/statements/history?days=30" "$CT" >/dev/null
is "$(py "print(len(d))")" 30 "30 days give 30 entries"
code GET "/statements/history?days=365&by=month" "$CT" >/dev/null
is "$(py "print(all(x['period'][-2:]=='01' for x in d), 12 <= len(d) <= 13)")" "True True" \
   "a year by month: 12 or 13 months, each keyed by its first day"
is "$(py "print(d[-1]['period'][:7])")" "${TODAY:0:7}" "the last month is this month"

# ╔═══════════════════════════════════════════════════════════════╗
hdr "3. Today's figures are today's statements, added up"
code GET "/statements?date=$TODAY" "$CT" >/dev/null
WANT=$(py "
from decimal import Decimal as D
f=sum(D(s['booked_income'])+D(s['walk_in_income']) for s in d)
t=sum(D(s['terminal_fees_owed'])+D(s['held_share']) for s in d)
p=sum(D(s['settled_amount']) for s in d)
print(f'{f:.2f}/{t:.2f}/{p:.2f}')")
code GET "/statements/history?days=7" "$CT" >/dev/null
GOT=$(py "
from decimal import Decimal as D
x=d[-1]; print(f\"{D(x['fares']):.2f}/{D(x['terminal_fees']):.2f}/{D(x['paid']):.2f}\")")
is "$GOT" "$WANT" "fares / terminal fees / paid for today ($WANT)"
[ "${WANT%%/*}" != "0.00" ] && ok "the seed records fares today, so the sum is not trivially zero" \
  || bad "no fares on today's statements: the check above proves nothing"

# The month adds up its days.
code GET "/statements/history?days=30" "$CT" >/dev/null
DAYSUM=$(py "
from decimal import Decimal as D
m='${TODAY:0:7}'
print(f\"{sum(D(x['terminal_fees']) for x in d if x['period'].startswith(m)):.2f}\")")
DOM=$(date +%d | sed 's/^0//')
if [ "$DOM" -le 30 ]; then
  code GET "/statements/history?days=$DOM&by=month" "$CT" >/dev/null
  is "$(py "
from decimal import Decimal as D
print(f\"{D(d[-1]['terminal_fees']):.2f}\")")" "$DAYSUM" "this month's terminal fees are the sum of its days"
fi

# ╔═══════════════════════════════════════════════════════════════╗
hdr "4. A day with no statement recorded nothing: a true zero"
EMPTY=$(sql "SELECT d FROM (SELECT CURDATE() - INTERVAL n DAY AS d FROM
  (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) k) days
  WHERE d NOT IN (SELECT service_date FROM remittances) ORDER BY d LIMIT 1")
if [ -n "$EMPTY" ]; then
  code GET "/statements/history?days=7" "$CT" >/dev/null
  is "$(py "x=next(x for x in d if x['period']=='$EMPTY'); print(x['fares'],x['terminal_fees'],x['paid'])")" \
     "0.00 0.00 0.00" "$EMPTY has no statement and shows 0.00 throughout"
else
  ok "every one of the last six days has a statement; nothing to check here"
fi

# ╔═══════════════════════════════════════════════════════════════╗
hdr "5. What it refuses"
is "$(code GET "/statements/history?days=0" "$CT")" 422 "days=0"
is "$(code GET "/statements/history?days=400" "$CT")" 422 "more than a year"
is "$(code GET "/statements/history?days=7&by=week" "$CT")" 422 "a bucket other than day or month"

echo
printf '  %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
