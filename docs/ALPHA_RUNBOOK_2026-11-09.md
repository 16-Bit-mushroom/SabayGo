# Alpha test runbook — 9 November 2026

*One sequence, start to finish, for a first-day-of-use simulation. The
data tables (terminals, route, fares, operators, staff, timetable) are
not repeated here: they are `docs/DAY1_TEST_GUIDE.md` section 1.3, which
is the authority. This file is the order of operations, the commands, and
what each step should produce.*

Both datasets stay available all day. Switching takes one command, so the
adviser can ask for either at any time.

| Want | Command | Accounts |
|---|---|---|
| Empty, true first day | `./db/apply.sh --reset` | none; make the first manager |
| A2Z data already in | `./db/load-day1.sh` | `@a2z.dev`, password `sabaygo123` |

Never `./run.sh --reset-db` or `./db/reset-dev.sh` for this test: both
load the demo dataset with `@sabaygo.dev` accounts and different routes.

Switching datasets drops the database, so every signed-in person must
sign in again afterwards. Decide before a round, not during one.

---

## Part 0. Before testers arrive

1. **Network you control.** A travel router or one phone's hotspot that
   the laptop and every tester joins. School Wi-Fi isolates clients, so a
   phone with full signal still cannot reach the laptop. Count testers
   against the hotspot's device cap.
2. **Laptop on mains power.**
3. **Open the ports once** (survives reboots):
   `sudo ufw allow 8000/tcp; sudo ufw allow 3001/tcp`
4. **Play money** for the Dispatcher to take.
5. **A USB cable** and one phone set up for adb.

---

## Part 1. Start the system

```bash
docker compose up -d                 # MySQL, if not already up
./db/load-day1.sh                    # or ./db/apply.sh --reset for empty
./run.sh                             # backend :8000, console :3001
```

`run.sh` resolves this machine's address once and hands the same one to
the backend, the console build and the APK. It prints it as
`this machine: <ip>`. If it picks the wrong card, stop it and use
`./run.sh --host <ip>`.

The console rebuilds (~3.5 min) whenever that address changed since the
last build. The APK build is about 2 minutes.

### Verify before anyone arrives

| Check | Expected |
|---|---|
| `curl http://<ip>:8000/health` | `{"status":"ok","environment":"development"}` |
| Browser on the laptop: `http://localhost:3001` | console sign-in |
| **Another laptop**: `http://<ip>:3001`, then **sign in** | lands on the dashboard |
| A tester phone's browser: `http://<ip>:8000/health` | the same JSON |

Sign in on the second laptop, do not stop at the page rendering. The page
rendered even when the console was misconfigured; only the API calls
failed.

An empty `logs/backend.log` means the request never arrived: network or
ufw, not the app.

---

## Part 2. The passenger and Dispatcher app

With a phone connected by USB:

```bash
adb devices                          # must list a device, not be empty
./run.sh --mobile                    # builds, installs, launches
```

With no phone attached, `run.sh --mobile` warns and skips the APK
entirely. To build without a device:

```bash
cd mobile
$HOME/flutter/bin/flutter build apk --debug \
    --dart-define=API_BASE_URL=http://<ip>:8000/api/v1
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Verify the address on the phone itself.** A debug build prints it under
the dev-account chips on the sign-in screen: `Dev accounts —
http://<ip>:8000/api/v1`. If that line shows an old address, the APK did
not rebuild or the wrong file was installed.

Share `mobile/build/app/outputs/flutter-apk/app-debug.apk` to testers'
phones by cable or a messaging app; they must allow "install unknown
apps".

### If phones are short

The app also runs in a browser, and `localhost` and `127.0.0.1` hold
separate logins, so one screen can play four people:

```bash
cd mobile
$HOME/flutter/bin/flutter build web --release --pwa-strategy=none \
    --dart-define=API_BASE_URL=http://<ip>:8000/api/v1
python3 -m http.server 3000 -d build/web
```

| Window | Address |
|---|---|
| Console, Terminal Manager | `http://localhost:3001` |
| Console, Cashier | `http://127.0.0.1:3001` |
| App, Dispatcher | `http://127.0.0.1:3000` |
| App, passenger | `http://localhost:3000` |

---

## Part 3. The in-van phone as the camera

A separate app from the passenger one. Build and install it once:

```bash
cd edge_app
tools/export_models.sh               # only after a fresh clone; models exist already
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Its server address is **not** compiled in, so a network change needs no
rebuild, only re-entering the address.

### Once per phone

1. **Console, as the Terminal Manager**: Setup to Phones, add the phone.
   The token is shown **once** — copy it now.
2. **On the phone**, Set-up screen: the server
   `http://<ip>:8000/api/v1` and the token. A debug build also takes them
   over adb:
   ```bash
   adb shell am start -n com.sabaygo.edge/.HomeActivity \
       --es server http://<ip>:8000/api/v1 --es token <token>
   ```
3. **Checklist**: permissions, battery optimisation off, the Realme
   switches the app cannot read. Realme refuses `pm grant` over adb, so
   the first launch asks for the camera on screen — unlock the phone and
   allow it.
4. **Verify**: the console's Phones page shows a recent heartbeat. Status
   reports arrive every 30 s.

### Each mounting

5. **Console**: check the phone out to a van and a Dispatcher. This needs
   the van already assigned to a trip, so do it after Part 5's assign
   step.
6. **On the phone**: Door line — drag the yellow line across the doorway,
   the red box over the driver's seat, set the cabin arrow, **Save**. The
   line is stored on the van, so the next phone in that van loads it.
7. Opening the app starts the counting service. It counts while the
   server says the trip is live, from assignment until arrival.

### What to expect, honestly

Door counting has **never been tested with people crossing a line**. Unit
tests cover the tracker on synthetic frames; the phone has only been
proven to reach the server. Treat this as a side station, not on the
critical path of a tester round, and write down what you see: N people
walked in, the app counted M.

If no phone goes out with a van, every trip is **Unaudited (no phone)**.
That is correct behaviour, not a bug.

---

## Part 4. First-day setup, as the Terminal Manager

Skip this whole part if you loaded the Day 1 data — it is already done.
Press **Create upcoming trips** (Part 5, step 0) and go.

On an empty database:

```bash
cd backend
venv/bin/python scripts/create_first_manager.py \
    --email manager@a2z.dev --phone 09171110001 --first Maria --last Santos
```

It asks for the password twice, at least 8 characters. Staff never
self-register and only a Terminal Manager creates staff, so the first one
is made here, once, by the development team.

Then sign in at `http://localhost:3001` and work down the **Setup**
checklist in its own order. All values: `docs/DAY1_TEST_GUIDE.md` 1.3.

| Step | Watch out for |
|---|---|
| 1. Terminals | The Open and Staffed switches do nothing until **Save changes** |
| 2. Route | `ECO-COT`, four stops, minutes from the start |
| 3. Fares | From Ecoland only: passengers board at stop 1 |
| 4. Operators and vans | A van needs all four photos before **Validate** |
| 5. Staff | **Validate** is at the foot of the panel. Leave Liza Pending on purpose and check she is not offered when assigning |
| 6. Timetable | The picker is 12-hour — **check AM/PM before saving**. A wrong departure cannot be deleted, only switched off |
| 7. Phones | Do it now (Part 3), unlike the 3 Nov run which skipped it |
| 8. Rules and Settings | Home pickup max distance must be **3000 m**; unset means home pickup is never offered |

---

## Part 5. One trip, end to end

**Step 0 — trips on the board.** Setup to Timetable to **Create upcoming
trips**, 3 days ahead. Nothing creates them nightly, so this is
mandatory: the Day 1 data's own trips are dated 3–5 Nov and are in the
past. A departure already past today is skipped.

**Pick a departure at least an hour away.** A2Z's timetable is 5:30,
7:30, 9:30, 11:30 AM and 1:30, 3:30, 5:30 PM. For a 3:30 PM departure:

| | Time |
|---|---|
| Check-in opens (45 min) | 2:45 |
| Unpaid seats released (30 min) | 3:00 |
| Start opens (30 min) | 3:00 |

| # | Who | Does | Expect |
|---|---|---|---|
| 1 | Terminal Manager | Trips, the departure, **Assign van and Dispatcher** | The Dispatcher's app lists the trip. A Pending Dispatcher is not offered |
| 2 | Office | Check the edge phone out to that van (Part 3, steps 5–6) | Heartbeat on the Phones page |
| 3 | Passenger | **Sign up** in the app: name, email (`.test` is refused), a mobile not used by staff, password | Signed in |
| 4 | Passenger | Ecoland to Cotabato, today, **Search departures** | Only departures still ahead are listed |
| 5 | Passenger | **Reserve a space** | A booking code `SG-…`, ₱500, **Unpaid**, "pay in cash to the Dispatcher before 3:00 PM", and **Cancel** while unpaid |
| 6 | Terminal Manager | The trip's passenger list | Name, code, Unpaid |
| 7 | One passenger | Cancels | The space is free again. Cannot cancel once Paid |
| 8 | Passengers | Hand play money to the Dispatcher, saying the code or name | — |
| 9 | Dispatcher | **Reservations and walk-ups**, type part of the code, **Mark as Paid**, confirm | Chip PAID. The passenger's screen turns green within 15 s and Cancel disappears |
| 10 | Dispatcher | Airplane mode on, mark one more Paid, airplane mode off | It syncs and keeps the time the cash was handed over |
| 11 | Dispatcher | **Walk-in**, destination Digos, **Log**, collect ₱135 | Listed as a walk-up, **paid at once** |
| 12 | Dispatcher | Add self as crew | Crew is not one of the 14, and one unmatched boarding is theirs |
| 13 | Cashier | Try **Start trip** | Refused: the terminal fees are not recorded |
| 14 | Cashier | Trips, **Record terminal fees**, enter the operator's share the dialog names, **Record payment** | 15 % of (Booked + Walk-up) + ₱75 ticket + ₱50 parking |
| 15 | Cashier | **Start trip** (opens at 3:00) | Boarding. Operator name, licence and plate copied onto the trip. With no phone out, it warns and the trip is Unaudited |
| 16 | Dispatcher | **Depart** | En Route. Every seat still on the trip is closed: a paid reservation reads "Trip departed", because nobody can tell whether that person rode. The money is unaffected |
| 17 | Dispatcher | **Arrived** | Completed |
| 18 | Terminal Manager | The bell, then the trip's panel | With a phone: door events and the audit. Without: "Unaudited trip · no phone". **Boarding Audit lists only what a phone reported** |
| 19 | Cashier | Money, the van's statement | Booked, Walk-up, 15 %, ₱75 × trips, ₱50, terminal fees owed, operator's share |

**Record the fees after the Dispatcher has taken the cash, just before
Start.** Recorded earlier, every seat paid afterwards is a top-up and the
trip owes again until the Cashier records the difference.

### The arithmetic check

For one ₱500 booking and one ₱135 walk-up on one van's first trip of the
day: 15 % of ₱635 = ₱95.25, ticket ₱75, parking ₱50, **terminal fees
₱220.25**, **operator's share ₱414.75**. The console and the app must
show the same numbers.

---

## Part 6. Extras, if there is time

| Feature | What it needs |
|---|---|
| **Check-in "I'm here"** | Geofenced to Ecoland's 200 m, so refused from school. Raise Ecoland's zone (Setup to Terminals) for the session and **set it back to 200** after |
| **Speed monitor** | Rules and Settings to **Speed Limits** for ECO-COT, then `backend/venv/bin/python backend/scripts/tracking_simulator.py --trip <trip_id> --speed 90 --loop`. Without stretch limits, only stops are flagged |
| **SOS** | Records the alert and notifies in-app. **No text is sent**: the provider defaults to disabled and the contact numbers are deliberately unassigned. The passenger's SOS lives on the Track-the-van screen |
| **Home pickup** | Only if home pickup max distance is set (3000 m in the Day 1 data) |
| **Unpaid release** | Leave a reservation unpaid past the cutoff: a reminder first, then "Released: not paid in time" |
| **Special trips** | Not re-checked since rev 603. Expect findings |
| **Live map** | Needs internet for OpenStreetMap tiles. Without it the map is blank and everything else works |

---

## Part 7. If something breaks

| Symptom | Cause |
|---|---|
| Phone cannot load `/health`, `logs/backend.log` empty | The request never arrived: network isolation or ufw |
| App installs, every call fails | Check the address printed on the sign-in screen first |
| App errors after a dataset switch | Stored tokens point at user IDs that no longer exist. Sign out and in |
| `port 8000 is already in use` | An old backend survived: `pkill -f 'uvicorn app.main:app'` |
| Banner shows a strange address | Wrong network card: `./run.sh --host <ip>` |
| Backend change seems ignored | `run.sh` starts uvicorn **without** auto-reload. Stop it and start it again |
| Console change seems ignored | Rebuild, then Ctrl+Shift+R |
| Edge phone silent after a network change | Its address is in app storage, not the APK. Re-enter it |

---

## Part 8. Recording findings

One line per problem, in a shared sheet. Testers who have to invent a
format report less.

| Time | Role and account | Phone or browser | Trip id | Did | Expected | Got | Screenshot |
|---|---|---|---|---|---|---|---|

The trip id is on the console's Trips page. Grep `logs/backend.log`
around that time: every request is there, and a missing request means the
phone never reached the laptop.

### Known and expected — not bugs

- Every trip without the edge phone is **Unaudited (no phone)**.
- A paid reservation reads **"Trip departed"** after Depart.
- **Boarding Audit is empty** unless a phone reported; an Unaudited trip
  shows on the bell and the trip's own panel.
- **Check-in is refused** away from the terminal's geofence.
- **No SOS text message** is sent.
- Four widget tests in `mobile/test/layout_test.dart` fail on `main` too.
