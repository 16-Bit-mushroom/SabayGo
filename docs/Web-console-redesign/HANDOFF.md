# Handoff: the operator console after redesign v3

Updated 26 Oct 2026, for the teammate taking over the console. Read this
first, then `docs/PROGRESS_LOG.md`: the entries "Console redesign v3" and
"Console v3: critique, harden, polish" say what was built and why.

## Where the work is

Everything is on the branch **`console-v3`**, in four commits on top of
`main`:

| Commit | What |
|---|---|
| `feat(edge)` | The phone app: the door layout drawn one step at a time |
| `feat(backend)` | Routes & Fares endpoints; the tracking ping for development only |
| `feat(console)` | Redesign v3, with critique, harden and polish |
| `docs` | Progress log and known issues moved out of `CLAUDE.md` |

The branch goes to `main` through a pull request. Check whether it has been
merged before you start; if not, work on top of `console-v3`.

## Run it

```fish
./run.sh                      # database, backend, console at http://localhost:3001
```

That runs on the **dev database** (`sabaygo`, demo data). Two things to
know about that database:

- Its live trips are dated from the last reset.
- After a day or two, Trips and the journey tests find no trips for
  today. Run `./run.sh --reset-db` to fix that; it rebuilds the demo
  data.

To see the **real set-up** the owner entered, run it on the field
database. Never run tests or a reset against it:

```fish
set -x DATABASE_URL (string replace -r '/sabaygo$' /sabaygo_field (grep '^DATABASE_URL=' backend/.env | cut -d= -f2-))
./run.sh --no-gps
```

In bash: `DATABASE_URL=…/sabaygo_field ./run.sh --no-gps`. Use `--no-gps`
because the GPS simulator reads trips from the dev database.

**Accounts:**
- Dev database: `manager@`, `cashier@`, `dispatcher@` and `passenger@sabaygo.dev`, password `sabaygo123`.
- Field database: `manager@sabaygo.dev` (password `sabaygo123`) and the Cashier `chris@gmail.com`.

## What the console is now

The design system is **`DESIGN.md`** ("The Pila Board"). Product truth is
**`PRODUCT.md`**: the owner's decisions, the words to use, and the rules
the screens must keep. In short:

- One light palette:
  - white page;
  - terminal-green sidebar and buttons;
  - black text;
  - red only for SOS, danger and route pins.
- Seven menu entries, with related pages as tabs: Overview, Trips, Reviews,
  Money, Messages, Setup, and Emergencies at the foot.
- Setup is one page.
  - On the left, a queue of steps in the order the system needs them. The
    first unfinished step is raised and marked **Now**.
  - Each step's records are added and edited beside its list, never in a
    dialog.
- **The code:**
  - shell: `operator_console/lib/core/layout/operator_shell.dart`;
  - tokens and theme: `core/design/`;
  - Setup: `modules/setup/`;
  - shared pieces: `core/design/components/`.

**Rules that are easy to break** (the full list is in `PRODUCT.md`):

- Never show a number nobody measured. Missing evidence shows as missing:
  Unaudited, Not set, last known. Boarding Audit's empty day was saying
  "every boarding matched" on days with no trips. That is fixed; don't
  bring it back.
- No system or table names on screen. Settings show a title in A2Z's
  words, not `refund_enabled`.
- Say **Dispatcher**, never Conductor. Say **spaces**, never seats. Say
  **passenger list**, never manifest.
- One filled (green) button per view, and it is the next step. A disabled
  button is never the filled one.
- Red means an alarm. Money owed is ochre (cash in hand is not missing
  money).
- Roboto is bundled at 400, 500 and 700 only. Do not ask for 600 or 800;
  the browser draws them as 700.
- Anything clickable that is not a standard button wraps its `InkWell` in
  `FocusRing` (`core/design/components/focus_ring.dart`). Otherwise a
  keyboard user cannot see where they are.

## What was checked, and what was not

**Checked on 25–26 Oct:**
- `flutter analyze` is clean, and the widget test passes.
- `test_office_journey.sh` passed 61 of 62. The one failure is the stale
  dev seed described above.
- A live build was used:
  - as the Terminal Manager and as a Cashier;
  - at 1440 and 1000 px wide;
  - with the keyboard only;
  - on a database built from the migrations alone;
  - with 39 long-named terminals;
  - with the server stopped in the middle of a form.

**Not checked:**
- A real screen reader. Only Flutter's accessibility tree was read.
- Any browser other than Chromium.
- A projector.
- The edge app's unit tests (`edge_app`, `./gradlew test`). They were
  not run for the edge commit.

## What is left, in order

1. **Merge `console-v3`** once someone has looked at it.
2. **The date resets on every tab.** Trips, Review Starts, Boarding Audit
   and Remittance each start at today. A day picked on one page should
   carry to the next. Share one selected day in the shell
   (`operator_shell.dart`) and pass it to these pages.
3. **Pointers to other pages are plain text.** Examples: "Trips come from
   the Timetable", the Disputes and Driving Flags hints. Make each one a
   button that opens that page. The shell's `_show()` already finds a page
   by its screen type.
4. **The validation panel never says who validated a record, or when.**
   The server does not send it yet. This needs a field from
   `api/v1/fleet.py` before the console can show it
   (`modules/fleet_management/roster_parts.dart`).
5. **The Van Status Board is not yet the pila.** The design wants vans in
   turn order there, but the server stores no turn order. Ask the owner
   whether A2Z keeps one. Don't invent an order.
6. **Small ones:**
   - The Staff form's Save buttons are enabled before the form is valid,
     unlike the other steps.
   - Speed limits shows "Stretch 1" with an empty box and no unit.
   - A terminal name longer than two lines still cuts its end off.
   - The Cashier's Setup says "3 of 3 done", though they set nothing up.
   - There is no search on long lists, and no keyboard shortcuts.

**Open questions for the owner (not decided):**
- Should the Cashier land on today's Trips instead of the map?
- Should the four development settings under Rules & Settings > Advanced
  be hidden from the Terminal Manager altogether?
- A2Z's real SOS numbers. Until they are set, Setup warns that emergency
  texts are off.

## Seeing the console in a script (for screenshots and checks)

Flutter draws to a canvas, so you click by coordinates. A headless
Chromium can be driven with `.impeccable/tools/shoot.mjs`:

```bash
/usr/bin/chromium --headless=new --remote-debugging-port=9333 \
  --user-data-dir=/tmp/sg-chrome --window-size=1440,900 about:blank &
CDP_PORT=9333 node .impeccable/tools/shoot.mjs steps.json
```

A steps file is a JSON list. The step types:
`{"size":[w,h]}`, `{"go":url}`, `{"wait":ms}`, `{"click":[x,y]}`,
`{"type":"text"}`, `{"key":"Tab"}`, `{"wheel":[x,y,dy]}`,
`{"eval":"js"}`, `{"shot":"/path.png"}`.

**Positions at 1440 × 900:**
- sign-in: email (720,474), password (700,530), then Enter;
- sidebar entries at x=120: Overview y=132, Trips 180, Reviews 228,
  Money 276, Messages 324, Setup 372; Emergencies y=810;
- account menu (1340,31), then Sign out (1320,140).

**Traps, each of which cost time:**
- **Start every steps file with `{"size":[1440,900]}`.** The size resets
  each time the script reconnects. Without it the page is 813 px tall
  and every click lands in the wrong place.
- **After a rebuild the browser keeps the old `main.dart.js`.** Before
  looking, run
  `{"eval":"fetch('main.dart.js',{cache:'reload'})"}`, then `{"go":…}`
  again.
- **A reload sometimes signs the session out.**
- **Never write to `sabaygo_field`.** Make a scratch copy (bash, from
  the repo root):
  ```bash
  set -a; . ./.env; set +a
  docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" sabaygo-mysql sh -c \
    'mysql -uroot -e "CREATE DATABASE sabaygo_scratch; GRANT ALL ON sabaygo_scratch.* TO '"'"'sabaygo_app'"'"'@'"'"'%'"'"'" && mysqldump -uroot --routines --triggers sabaygo_field | mysql -uroot sabaygo_scratch'
  ```
  Then run the backend with `DATABASE_URL=…/sabaygo_scratch`. When you
  are done, revoke the grant and `DROP DATABASE sabaygo_scratch`.
- **In a script, `pkill -f "uvicorn …"` also matches the shell running
  it.** Kill by port instead: `ss -ltnp | grep :8000`.

## The design tooling

The design passes used the Impeccable skill. Its state lives in
`.impeccable/` (committed):

- `design.json`;
- the direction brief in `surfaces/`;
- the critique snapshot in `critique/`;
- the screenshots of the first review in `review/`.

The skill itself (`.claude/skills/impeccable`) is installed on the owner's
machine only and is not in the repository. To run another critique or
polish with Claude Code, install it the same way, or ask the owner for
the folder.
