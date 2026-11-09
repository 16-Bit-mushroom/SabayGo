# Handoff: the simulation test before alpha (9 Nov 2026)

*For the teammate who runs the simulation today. The alpha test is
tomorrow, 10 Nov, on the owner's laptop. The owner keeps the Realme phone,
so you test **both apps in a browser**: the phone app is built for the web
and played in a phone-sized window. The starter prompt for your Claude
Code session is at the end (§9).*

## 1. What you are doing today

1. **Run a Day 1-style simulation** on your laptop: set A2Z up from an
   empty database, then do every role's tasks, in order, until the trip
   arrives and the money is settled. On 3 Nov the setup and one cash trip
   passed (`docs/DAY1_TEST_GUIDE.md`, Part 2). This time also run what
   Day 1 left out: **SOS, the speed monitor, the camera path (with events
   played over HTTP), special trips, home pickup, the unpaid release, a
   voided trip and a dispute.**
2. **Write down every finding** (§5).
3. **Fix what you can before the cutoff** (§6), most useful first. Agree
   the cutoff with the owner (suggested 20:00): the owner has to pull,
   restart and rebuild before tomorrow, and anything merged later waits
   until after alpha.

Where things stand: rev 721 (cash only, booking code, terminal fees) is
done except **S7** (special trips, not re-checked since rev 603) and
**S11** (docs). The backend journey suite is 1070 passed, 0 failed. All
of this is on `main` now.

## 2. Get the code and start it

```bash
git fetch origin && git checkout main && git pull
git checkout -b alpha-fixes          # your fixes go here, never straight on main
./setup.sh                           # safe to re-run: .env files, venv, packages
```

The project docs write commands for the **fish** shell (`set VAR (cmd)`,
no heredocs). In bash, translate as you go. If `flutter` is not on your
PATH, use its full path.

Start the system and serve the phone app for the browser:

```bash
./run.sh                             # MySQL, backend :8000, console :3001
cd mobile
flutter build web --release --pwa-strategy=none \
    --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
python3 -m http.server 3000 -d build/web      # the phone app on :3000, second terminal
```

The first `./run.sh` builds the console (about 3.5 min); later runs skip
it unless `operator_console/lib/` changed or your LAN address did.

**Four windows, four logins.** A browser keeps one login per address, and
`localhost` and `127.0.0.1` count as two:

| Window | Address | Role |
|---|---|---|
| A | http://localhost:3000 | Passenger |
| B | http://127.0.0.1:3000 | Dispatcher |
| C | http://localhost:3001 | Terminal Manager |
| D | http://127.0.0.1:3001 | Cashier |

In A and B press F12, then Ctrl+Shift+M, and pick a phone size. For a
second Dispatcher or passenger use `http://<your-lan-ip>:3000`, or a
private window. All passwords `sabaygo123`.

## 3. The data

Pick one. Both rebuild the database from the migrations, so an old
database on your machine does not matter.

| | Start empty, as Day 1 | `./db/load-day1.sh` | `./run.sh --reset-db` (demo) |
|---|---|---|---|
| What | migrations only; you enter A2Z's setup in the console | the state Day 1 ended in | the demo seed the journey scripts use |
| Accounts | the first manager you create | `manager@a2z.dev`, `joy@a2z.dev` (Cashier), `ramon@` / `liza@a2z.dev` (Dispatchers), `chris@a2z.dev` | `manager@`, `cashier@`, `dispatcher@`…`dispatcher5@`, `passenger@sabaygo.dev` |
| Route | what you enter | Ecoland → Cotabato (A2Z's real route, test fares) | Ecoland → Digos / Tagum (test values) |
| Trips from today | after **Create upcoming trips** | after **Create upcoming trips** | three live trips dated from the reset |
| Unpaid cutoff | what you set | 30 min | 5 min |
| Home pickup | off until you set it | on (3000 m) | off until you set it |

**Recommended:** start empty, as Day 1 did (`DAY1_TEST_GUIDE.md` §1.2):
setup is itself a set of Terminal Manager tasks. If setup goes wrong,
fall back to `./db/load-day1.sh` and continue from the trips.

**The journey scripts reset the database.** Dump it first if you need
the day's data (`docs/HANDOFF_DAY1.md`, "Traps").

## 4. The simulation, in order

The screen-by-screen steps already exist: `docs/DAY1_TEST_GUIDE.md` §1.3
(setup) and §1.4 (the first trip), and `docs/ALPHA_TEST_SCRIPT.md` §2–7
(every task; written for the demo data, but the screens are the same).
Follow them; this list is the order and what is new.

| # | Who | Do | New since Day 1? |
|---|---|---|---|
| 1 | Terminal Manager | Setup: terminals, route, fares, operators and vans, staff (validate each Dispatcher), timetable, **Phones** (add one phone and copy its token: you need it in step 7), Rules & Settings | |
| 2 | Terminal Manager | Rules & Settings for testing: when Start opens and when check-in opens to 240 min, home pickup 3000 m, and **Speed Limits** for the route's stretches (without them the speed monitor flags only stops) | Speed limits: yes |
| 3 | Terminal Manager | Add a departure about an hour from now (check it saved as AM/PM correctly, finding 7), then **Create upcoming trips**, then assign a van and a Dispatcher | |
| 4 | Passenger | Sign up; search; reserve; read the booking code; cancel one and reserve again; chat with the Dispatcher; check in ("I'm at the terminal": fake the location, §4.1); **book for someone else with home pickup**; **rent the whole van** (special trip) | Home pickup, special trip: yes |
| 5 | Dispatcher | The assigned trip; reservations; **Mark as Paid**; log walk-ups; reply in chat; collect the special trip's fee | |
| 6 | Cashier | **Record terminal fees** just before Start (not earlier, finding 9), then **Start**; the Money page; Special Trips (agree a fee, a walk-in request, refuse one) | Special trips: yes |
| 7 | (you, as the phone) | The camera path without the phone, §4.2: check the phone out to the van, send heartbeats and door events, then see the Dispatcher's unlisted boarding, fix the list or explain, and Depart blocked while more are aboard than listed. Also run one trip with **no** phone: it must read Unaudited (`no_phone`) on its Trips panel and in the bell | Yes |
| 8 | Dispatcher | **Depart**; then feed GPS at speed (§4.3) | |
| 9 | Terminal Manager | Reviews → **Driving Flags**: an overspeed flag appears; mark it reviewed or dismissed with a note | Yes |
| 10 | Dispatcher, passenger, Cashier | **SOS**, §4.4: raise one from the Dispatcher's app and one from the passenger's; respond to and close both on **Emergencies (SOS)** in the console | Yes |
| 11 | Dispatcher | **Arrived**; the statement; the operator's share | |
| 12 | Cashier, Terminal Manager | A **dispute** from the operator at the counter; the Terminal Manager decides it with a reason | Yes |
| 13 | Passenger, system | **Unpaid release**: leave one reservation unpaid past the cutoff; it is cancelled and the passenger told. Then mark a released seat Paid and see it restored or the `paid_after_release` alert | Yes |
| 14 | Terminal Manager | Void a trip after its fees were recorded, and **Change van** after a payment (reproduces finding 8, still open) | |
| 15 | everyone | Retest the eight findings fixed on 3 Nov: 1, 10, 11, 12, 13, 18, 20, 21 (`docs/DAY1_FINDINGS.md`) | |

### 4.1 Check-in from your desk

Check-in is fenced to Ecoland (200 m). In window A: F12 → ⋮ → More tools
→ **Sensors** → Location → Other…, latitude `7.051048`, longitude
`125.587456` (the demo data's Ecoland: `7.0524`, `125.5931`), then
allow location. Firefox has no Sensors panel; its
`about:config` route is in `DAY1_TEST_GUIDE.md` §1.6. A check-in pays
nothing and does not save a seat from the release: that is correct.

### 4.2 The camera path, played over HTTP

The Realme is not here, so you play the phone. This proves the server
side (matching, the Dispatcher's fix-or-explain, the Depart block,
Boarding Audit); it proves nothing about YOLOv8 itself.

1. Console → **Phones**: the phone from step 1 → **Check out** to the
   trip's van, after a Dispatcher is assigned to that trip.
2. Send heartbeats around the Start, then one boarding more than the list
   holds. The payload shapes are the `reports`, `event` and `fix` helpers
   at the top of `backend/tests/integration/test_edge_ingestion.sh`
   (lines 44–68); the header is `X-Device-Token: <token>`:

```bash
API=http://127.0.0.1:8000/api/v1; TOKEN=<token from Phones>
NOW=$(python3 -c "import datetime;print(datetime.datetime.now().isoformat())")
curl -s -X POST $API/edge/heartbeats -H "X-Device-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"reports\":[{\"recorded_at\":\"$NOW\",\"camera_ok\":true,\"gps_ok\":true,\"lens_blocked\":false,\"battery_pct\":80,\"battery_temp_c\":36.5,\"charging\":true}]}"
curl -s -X POST $API/edge/events -H "X-Device-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"events\":[{\"event_id\":\"$(python3 -c 'import uuid;print(uuid.uuid4())')\",\"event_type\":\"board\",\"event_at\":\"$NOW\"}]}"
```

Times are naive local (Asia/Manila), as everywhere in the system. A
phone that goes quiet at Start makes the trip Unaudited
(`silent_at_start`): that is correct, keep the heartbeats coming.

### 4.3 The speed monitor

After Depart:

```bash
cd backend && venv/bin/python scripts/tracking_simulator.py --trip <trip_id> --speed 90 --loop
```

An overspeed flag needs a speed limit on the stretch (step 2) and about
10 s above it. The trip id is on the console's Trips panel, or
`SELECT trip_id, departure_datetime FROM trips WHERE DATE(departure_datetime) = CURDATE()`.
Map tiles need internet; without it the map is blank and the rest works.

### 4.4 SOS

- The Dispatcher's SOS is on the trip's passenger-list screen. The
  passenger's is **only on the Track-the-van map** (finding 22): the
  reservation → **Track the van** → SOS in the top bar.
- The alert is recorded and shown in-app and on **Emergencies (SOS)**.
  No text is sent: `SMS_PROVIDER` is disabled in development. **Do not
  type real phone numbers into the SOS numbers setting**: from that
  moment an SOS texts real people.

### 4.5 What a browser cannot test (the owner does these on the Realme)

The app installed on a handset (the rev 721 screens have never run on
one), the offline queue for Mark as Paid and walk-ups, the edge phone
counting real people at a door, real GPS, and the cleartext fix on a new
network address.

## 5. Recording findings

Add them to `docs/DAY1_FINDINGS.md`, numbering on from **24**, with
"9 Nov sim" in the Where column. One line each: where, what you did, what
you expected, what happened. Mark each **Blocks alpha** or **After
alpha**. Keep a screenshot for anything visual. A finding you fix gets
"Fixed 9 Nov" and the commit.

## 6. Not fixed yet: what to fix before alpha, if possible

Anything your simulation finds that stops a role's task goes **first**,
ahead of this list.

### Decisions for the owner and the group (no code)

| | What | Why it matters tomorrow |
|---|---|---|
| D1 | **Which data tomorrow.** `ALPHA_TEST_GUIDE.md` §3 lists the `@sabaygo.dev` accounts (demo seed); the owner's database currently holds the Day 1 data (`@a2z.dev`) | Testers following the guide cannot sign in. Once decided, make §3 match |
| D2 | **Create upcoming trips** must be pressed: the owner's database has **zero** trips from today (finding 2) | Nobody can book until it is |
| D3 | Finding 22: the passenger's SOS lives on the out-of-scope Track-the-van map | Decides whether passenger SOS is tested tomorrow |
| D4 | Finding 6: **Phones** is a required setup step, so without the edge phone the checklist never reads "ready" | Testers may think setup is broken |

### Code, in the order I would take them

| # | Finding | Fix | Size |
|---|---|---|---|
| 1 | **23** | List the day's Unaudited trips, with their reason, at the top of Boarding Audit. Without the edge phone **every** alpha trip is Unaudited and the Terminal Manager has nowhere to review them (brief §4.2 rule 11) | Medium: one backend query and endpoint, one console section |
| 2 | **17** | **Delete** a departure that never made a trip; one that made trips keeps only Switch off (trips point to it with `ON DELETE SET NULL`) | Small |
| 3 | **7** | Show the timetable's departures in 24-hour time, or grouped AM/PM, so a 3:30 AM slip is visible | Small, console only |
| 4 | **9** | In **Record terminal fees** on a trip with an empty list, say "No passengers yet: record now only if the van leaves empty" | Tiny, console only |
| 5 | **2** | Create upcoming trips automatically: a backend periodic job, as `application/booking/unpaid_release.py` runs every 60 s (the logic is `backend/scripts/generate_trips.py`) | Medium |
| 6 | **22** | Only if the group says yes (D3): move the passenger's SOS to the reservation screen, then hide Track the van | Medium, app only |

**Not before alpha:** finding 8 (money left on a voided trip's statement;
needs A2Z's answer first), finding 19 (console-wide text pass, its own
session), S7 beyond what you find today, S11 docs, a server-address
field in the app (so one APK works on any network; needed for beta and
the Cloudflare Tunnel pilot), and the per-stop cabin snapshot.

### Rules for every fix

- On `alpha-fixes`, one commit per fix. Follow `CLAUDE.md` ("Rules that
  are not obvious", "Domain invariants"): say Dispatcher, never
  Conductor; a migration ships a down script; never touch the locking in
  `seat_repository.py`.
- Prove it: the one journey script for the area (on a database you can
  lose), `flutter analyze` for app or console changes, then a retest in
  the browser. Record it at the end of `docs/PROGRESS_LOG.md` and in the
  findings line.
- Push, open a PR to `main`, and tell the owner what changed and what
  they must redo: restart `./run.sh` for a backend change (no
  auto-reload), the console rebuilds by itself when `lib/` changed, and
  an app change needs a new APK (`./run.sh --mobile`).

## 7. Traps

- **The backend does not reload.** After a backend change, Ctrl-C
  `run.sh` and start it again.
- **The journey scripts reset the database** (see §3).
- **The console is now built against your LAN address**, not 127.0.0.1,
  so other laptops can use it. Change networks and the next `./run.sh`
  rebuilds it (3.5 min). If it picks the wrong network card:
  `./run.sh --host <ip>`.
- **Start opens 30 min before departure** and the **unpaid cutoff is
  30 min** in the Day 1 data (5 min in the demo). A trip too close to now
  releases seats mid-test; one too far away cannot be started (raise the
  Start window, step 2).
- **Fees recorded before any seat** make every later paid seat a top-up
  that sets the trip back to Owes (findings 9, 14, 15). Record them just
  before Start.
- **Web-only bugs exist.** On the web, `1 << 32` is 0 (finding 13); every
  button must show a failure, never do nothing.
- **The app theme makes every FilledButton full width**; one in a row
  needs `minimumSize` (finding 10).
- **The `mysql` client prints cp1252** unless given
  `--default-character-set=utf8mb4`.
- After a reseed, a signed-in window holds a token for a user that no
  longer exists: sign out and in again.

## 8. What the owner is doing meanwhile

On the Realme: installing the APK and smoke-testing the rev 721 screens
on a handset (reserve, booking code, Mark as Paid, walk-up), the edge app
with people walking through a door, and building both apps on
tomorrow's network. Do not duplicate these; do tell the owner at once
about anything you find that would break them.

## 9. Starter prompt for your Claude Code session

Open Claude Code in the repository after `git pull`, and paste:

```text
I'm taking over SabayGo testing from the owner for today. Read
docs/HANDOFF_ALPHA_PREP.md first, then docs/DAY1_FINDINGS.md and
docs/DAY1_TEST_GUIDE.md §1.1–1.4. CLAUDE.md and docs/SESSION_RULES.md
are already loaded: follow them.

Today: I run a Day 1-style simulation of every role (Terminal Manager,
Cashier, Dispatcher, passenger) on my laptop, browser only: the phone app
is built for the web (handoff §2), no handset, no edge phone. Alpha
testing is tomorrow, 10 Nov, on the owner's laptop.

1. Check my machine is ready: on branch alpha-fixes off an up-to-date
   main, ./setup.sh done, Flutter found. Then help me start the system
   and the web build of the app, and choose the data (handoff §3).
2. Walk the simulation with me in the order of handoff §4, one step at a
   time. Give me the commands for §4.2 (door events over HTTP), §4.3
   (speed monitor) and the trip ids I need. Don't run the journey
   scripts on the simulation database without dumping it first.
3. Record each finding I report in docs/DAY1_FINDINGS.md from #24, marked
   Blocks alpha or After alpha.
4. Then fix, in the order of handoff §6: anything that blocks a role's
   task first, then findings 23, 17, 7, 9, 2. For each, state the design
   in a few lines, ask me before anything large, prove it with the area's
   journey script and flutter analyze, one commit each, record it in
   docs/PROGRESS_LOG.md. Stop at the cutoff the owner and I agreed, and
   draft the message telling the owner what to pull, restart and rebuild.
```
