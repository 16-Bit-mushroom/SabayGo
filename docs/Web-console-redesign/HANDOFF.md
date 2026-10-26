# Handoff: console redesign v3, the three passes

Written 25 Oct 2026 at the end of the session that built the redesign, for
the session that runs **critique, then harden, then polish** on it, in that
order. Critique can still change structure, so it goes first.

## What is built (read these, do not re-derive)

- `docs/PROGRESS_LOG.md`, entry "Console redesign v3": what changed and
  where.
- `DESIGN.md` and `.impeccable/design.json`: the new system ("The Pila
  Board"), written from the build.
- `.impeccable/surfaces/operator-console-lib.md`: the direction contract.
  The world is fixed; the passes refine it and must not replace it.
- `PRODUCT.md`: product truth. It records the owner's 25 Oct decisions:
  - white / green / black-red, 60-30-10;
  - light only;
  - seven menu hubs;
  - no system or table names on screen.
- The owner's brief: `docs/Web-console-redesign/UI-UX-redesign-v3.txt`,
  plus the three annotated screenshots beside it.

The code lives under `operator_console/lib/`:

- shell: `core/layout/operator_shell.dart`;
- tokens and theme: `core/design/`;
- Setup: `modules/setup/`;
- validation panel: `modules/fleet_management/roster_parts.dart`.

## State of review

The finish review passed (ship), but only for the eight fixes it scored:

- the head of the queue versus the open step;
- no blue;
- subtitles that wrap;
- one filled button per view;
- the Overview empty note;
- the title chips removed;
- and two evidence fixes.

Captures live in `.impeccable/review/`. The review did **not** cover the
whole surface.

**Never captured or reviewed:** Van Status Board, Special Trips, Money
(Remittance), Messages, Emergencies (SOS), Review Starts and Boarding
Audit with real rows, Timetable, Phones, Rules & Settings, and the
Operators list.

## What each pass should take on

**Critique.** The brief says the old console had poor learnability and
usability. Nothing has scored the new one against usability heuristics yet.
Cover:
- the menu and tabs;
- Setup's queue and its inline forms;
- the role differences (Terminal Manager vs Cashier);
- the pages listed above that nobody has looked at.

**Harden.** Known untested paths:
- a truly empty database: every capture so far was a nearly set-up copy;
- long names and many records in the Setup lists;
- slow or failed requests in the middle of a form;
- a server refusal shown inside a form (`FormProblem`, refused);
- keyboard-only use and focus order;
- the narrow layout, where the content area is under 980 px and the queue
  becomes a horizontal strip, which nobody has captured.

**Polish.** Older drift the documenter found and left alone:
- the notification sheet has `elevation: 12`
  (`core/layout/notification_bell.dart:66`), against the map-only-shadow
  rule;
- the SOS card's category label is uppercase at weight 900
  (`modules/emergency/screens/sos_console_screen.dart:215`), and 900 is
  not bundled;
- the theme asks for weights 600 and 800, but only Roboto 400, 500 and 700
  are bundled;
- theme buttons are 40 px high, against the 48 px `minTouchTarget` rule in
  the tokens.

Also the gaps the review noted against the contract:
- a done step loses its number, so the order cannot be read once the
  queue is finished;
- the pila strip is not yet used where order is real (a van's turn on the
  Van Status Board).

## How to see it running (proven in the last session)

The commands below are written for Claude's **bash** tool. The owner's own
shell is fish.

**Never write to `sabaygo_field`**: it is the owner's real set-up. Work on a
copy instead:

```bash
# 1. a scratch copy of the field database, with access for the app user
docker exec sabaygo-mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE sabaygo_redesign; GRANT ALL PRIVILEGES ON sabaygo_redesign.* TO '"'"'sabaygo_app'"'"'@'"'"'%'"'"'" 2>&1 | grep -v Warning; mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --routines --triggers sabaygo_field 2>/dev/null | mysql -uroot -p"$MYSQL_ROOT_PASSWORD" sabaygo_redesign 2>&1 | grep -v Warning'

# 2. the backend on the copy (logs/backend-redesign.log)
cd backend && set -a && . ./.env && set +a && export DATABASE_URL="${DATABASE_URL%/sabaygo}/sabaygo_redesign" && nohup ./venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 > ../logs/backend-redesign.log 2>&1 &

# 3. build the console (about 3.5 min) and serve it on 3001
cd operator_console && $HOME/flutter/bin/flutter build web --release --pwa-strategy=none --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 > ../logs/console-build-redesign.log 2>&1
nohup python3 -m http.server 3001 --bind 127.0.0.1 --directory operator_console/build/web > logs/console-redesign.log 2>&1 &

# 4. headless Chromium, driven over CDP
nohup /usr/bin/chromium --headless=new --remote-debugging-port=9333 --user-data-dir=<scratchpad>/chrome --window-size=1440,900 --no-first-run --disable-gpu about:blank > /dev/null 2>&1 &
node .impeccable/tools/shoot.mjs steps.json
```

**The driver.** `shoot.mjs` takes a JSON list of steps:

```
{"size":[w,h]}  {"go":url}  {"wait":ms}  {"click":[x,y]}  {"type":"text"}
{"key":"Enter"}  {"shot":"/path.png"}
```

Flutter draws to a canvas, so you click by coordinates. Take a shot first
to find positions.

**Known positions at 1440 × 900:**
- sign-in: email field (720,474), password field (700,530), then press
  Enter;
- sidebar entries at x=120: Overview y=132, Trips 180, Reviews 228,
  Money 276, Messages 324, Setup 372; Emergencies at y=810;
- account menu (1340,31), then Sign out (1320,140);
- Setup queue slots move as the queue's state changes, so take a shot
  first.

**Gotchas.**
- A reload sometimes signs the session out.
- The scratch copy is nearly set up (7 of 7). To get a queue that is
  part-way through, take the route out of service in Setup > Route, or
  suspend the Cashiers in the copy with SQL.
- For a truly empty database (a harden item), build one from the
  migrations without the demo seed. Do not empty `sabaygo_field`.

**Accounts in the copy:**
- `manager@sabaygo.dev` / `sabaygo123`;
- `test.cashier@sabaygo.dev` and `second.cashier@sabaygo.dev` /
  `sabaygo123`. These two exist only in the copy; the last session made
  them through the Add staff form.

**Clean up when done.** Kill the three processes, then drop the copy:
`REVOKE ALL ... ON sabaygo_redesign.*` and `DROP DATABASE
sabaygo_redesign`.

**Checks.**
- `$HOME/flutter/bin/flutter analyze | grep -E "error|warning"` must be
  empty.
- The widget test passes only with
  `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome`.
  On the VM it cannot load `package:web`; that was already true before
  the redesign.

## Housekeeping

- Nothing from the redesign is committed.
- `modules/routes_fares/routes_fares_screen.dart` was never committed and
  was removed, because its forms now live in the Setup steps. A copy is in
  `.impeccable/tools/removed-routes-fares/`.
- After any edit, record the step at the end of `docs/PROGRESS_LOG.md`.
  If the system itself changes, update `DESIGN.md`.
