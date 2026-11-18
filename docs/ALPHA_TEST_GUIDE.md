# Alpha test guide

*Written 3 Nov 2026 for round 1 (run 10 Nov); updated 18 Nov for round 2.
Covers setting the system up at school, the accounts, one trip from start
to finish, each role's tasks, and what a round at school cannot test.*

The system is three programs on one laptop and two apps on phones:

| Piece | Who uses it | Where it runs |
|---|---|---|
| MySQL, backend (FastAPI) | nobody directly | the server laptop |
| Operator console (web) | Terminal Manager, Cashier | any browser on the network, `http://<laptop-ip>:3001` |
| Mobile app (Android) | Passenger, Dispatcher (same app, the account decides) | testers' phones; a browser build for a tester without Android (§2) |
| Edge app (Kotlin) | the in-van phone, counting at the door | optional for alpha; without it every trip is Unaudited (`no_phone`), which is correct behaviour |

## 1. Status

Round 1 ran on 10 Nov with A2Z's paper trip ticket. Since then, all on
`main`:

- **12 Nov, the owner's decisions:** "seat" everywhere (never "space");
  **Walk-in** (was walk-up); the passenger's check-in button is now
  **"I'm here to pay"**, and marking a seat Paid also counts the passenger
  as at the terminal; **who rode is who paid**: a paid seat becomes
  boarded at Depart, only an unpaid one is a no-show. Plain money words
  on screens: Total fees, Total paid, Balance.
- **12 Nov:** a passenger sees a van's position only for a trip they hold
  a seat on, while it is boarding or on the road (decision C5).
- **17–18 Nov:** a terminal added by mistake can be deleted; Overview
  lists a van on the road with no location yet as **No signal**; the trip
  panel shows **Paid earlier today** and the **Balance** when part of a
  van's fees was recorded before; buttons are dark green with white text.

Checked 16 Nov: the full journey suite 1261 passed, 0 failed; both apps
analyse without errors; every console page loads for the Terminal Manager
and the Cashier. 18 Nov: `test_terminal_delete.sh` 18/0.

Known and expected during alpha:

- Every trip is **Unaudited (`no_phone`)** unless the edge phone is out
  with the van. That is correct behaviour, not a bug.
- After Depart a **paid** seat reads boarded and stays the passenger's
  current trip, with tracking and the SOS, until the trip is completed.
  An **unpaid** one is a no-show.
- S7 (special trips: fee basis, counter flow) was not re-checked; the
  flow worked under rev 603 and the fee is now cash to the Dispatcher.
- Open Day 1 findings (`docs/DAY1_FINDINGS.md`) that testers will meet;
  note them, do not report them as new:
  - **#2:** trips are not posted by themselves; someone presses **Create
    upcoming trips** (Trips).
  - **#8:** voiding a trip after its fees were recorded leaves an
    overpayment that shows nowhere.
  - **#17:** a departure saved with the wrong time cannot be deleted, only
    switched off.
  - **#22:** **Track the van** is still in the passenger app.
  - **#23:** no list gathers the day's Unaudited trips.

### What this round cannot test

| Area | At school | Why |
|---|---|---|
| Booking, Paid, walk-ins, fees, Start, Depart, statements, disputes, messages | ✅ fully | nothing here depends on place |
| **SOS** | ✅ raise it, see it on the console, close it with a note | ❌ **no text messages**: SMS is off and no SOS numbers are set. A browser build shows "No location"; the Android app shows the school's position |
| **"I'm here to pay"** | ⚠️ only after widening the terminal zone (§4) | it checks the phone is at the terminal. Not in the browser build: a browser gives no location over plain `http` |
| **Van on the live map** | ⚠️ simulated | `run.sh` simulates trips already on the road when it started; a trip that departs later needs the simulator by hand (§4). Without it Overview lists the van as **No signal** |
| **Door camera (YOLOv8)** | ⚠️ possible at a classroom door | the Realme with the edge app, checked out to the trip's van (console → Phones), the door line drawn on the phone. It would be the first test with people crossing a line |
| GPS departure, stretch speed flags, the rental speed flag | ❌ switched off | they wait on A2Z's numbers (`depart_zone_radius_m`, stretch speed limits, `special_trip_speed_kmh`) |
| Home pickup | ✅ with the Day 1 data (3 km) | the setting is A2Z's to confirm |
| A2Z's real routes, fares, timetable | ❌ | the Day 1 setup is a stand-in; `seed_alpha.py` adds the fares on ticket Nº 0012223 |
| A whole day or week of use | ❌ | a session cannot age; `seed_alpha.py` posts 7 days of trips to look at |
| The edge app's release build | ❌ | its lint fails; use the debug build |

## 2. Setting up at school

### What to bring

- The server laptop (this one, set up with `./setup.sh`), on mains power.
- **A network you control**: a travel router, or a phone hotspot that
  the laptop and every tester joins. School Wi-Fi usually isolates
  devices from each other, so a phone cannot reach the laptop even with
  full signal. A hotspot often caps at about 10 devices; count testers.
- Internet on that network if you want map tiles (OpenStreetMap). Without
  it the live maps are blank; everything else works.
- A USB cable and one Android phone already set up for `adb` (the
  Dispatcher's phone in the demo).
- Play money, so the Dispatcher has cash to take.
- Optional: the Realme with the edge app and its charger, to try the door
  camera at a classroom door.

### The address problem

The mobile app has the server address **built in** at compile time
(`API_BASE_URL`). Phones built against one network cannot reach the
server on another. On a network you control the laptop keeps the same
address, so one APK built the night before works on the day. If the
address changes, rebuild and reinstall on every phone.

### The night before (on the network you will use)

```fish
./run.sh --mobile          # database, backend, console, app on the attached phone
```

`run.sh` finds the laptop's address once and gives the same one to the
backend, the console build and the app. If it picks the wrong network
card: `./run.sh --host <ip> --mobile`. The console build (~3.5 min) and
the APK build are done now so they are not done on the day. Rebuild the
APK for round 2 even if the network is the same: the app changed after
round 1.

If `run.sh` stops with "port 8000 is already in use", on this laptop that
is another project's container: `docker stop sakshi-web-1`, then run it
again (`docker start sakshi-web-1` brings it back afterwards).

**A tester without Android** can use the app in a browser, as a passenger
or a Dispatcher (no location, so no "I'm here to pay"):

```fish
cd mobile; $HOME/flutter/bin/flutter build web --release --pwa-strategy=none --dart-define=API_BASE_URL=http://<laptop-ip>:8000/api/v1; cd ..
python3 operator_console/tool/serve_web.py 3002 mobile/build/web
```

Testers open `http://<laptop-ip>:3002` (open port 3002 in ufw, below).
Two accounts in one browser need two addresses: serve the same build on
3003 as well.

For the testers' phones, share the APK `run.sh` just built:
`mobile/build/app/outputs/flutter-apk/app-debug.apk` (by cable or a
messaging app; testers allow "install unknown apps"). It is a debug build,
so the sign-in screen shows the dev-account shortcuts.

If `run.sh` warns about ufw, open the two ports once (the rule survives
reboots):

```fish
sudo ufw allow 8000/tcp; sudo ufw allow 3001/tcp
# only if you serve the browser builds or a second console:
sudo ufw allow 3002/tcp; sudo ufw allow 3003/tcp; sudo ufw allow 3004/tcp
```

### On the day

Pick the data, then start:

```fish
# A2Z's Day 1 setup with the alpha people and fares (@a2z.dev accounts):
./db/load-day1.sh
./run.sh
backend/venv/bin/python backend/scripts/seed_alpha.py      # with run.sh up
backend/venv/bin/python backend/scripts/seed_live_now.py   # optional: two trips on the road now

# or the demo data (@sabaygo.dev accounts):
./run.sh --reset-db        # fresh demo data, live trips dated from now
```

Either way, reset **shortly before** the session: the seeds date their
trips from that moment. Do not reset after about 22:00 (it puts the
"soon" trip on tomorrow's board).

### Check before testers arrive

1. From a tester's phone browser: `http://<laptop-ip>:8000/health` shows
   `{"status":"ok"}`. If it does not load, the phone cannot reach the
   laptop: check the network and ufw, not the app. An empty
   `logs/backend.log` means the request never arrived.
2. From another laptop: `http://<laptop-ip>:3001` shows the console
   sign-in.
3. Sign in on one phone as a passenger (§3) and see today's trips from
   Ecoland. None? Trips → **Create upcoming trips** (finding #2).

### Between rounds

`./run.sh --reset-db` again, or keep the data if the next round continues
the same day. Ctrl-C stops everything `run.sh` started (MySQL stays up).

## 3. Accounts

All passwords `sabaygo123`.

**Day 1 setup with `seed_alpha.py`** (route Davao (Ecoland) – Cotabato
City; vans ABC-1234, LCT-9042 and TST-1023):

| Role | Accounts | Notes |
|---|---|---|
| Terminal Manager | `manager@a2z.dev` | console |
| Cashier | `joy@a2z.dev`, `rose@a2z.dev` | console; Door cameras, Trip Schedules, Review Starts and Boarding Audit are hidden |
| Dispatcher | `liza@`, `ramon@`, `nonoy@`, `jun@`, `mae@a2z.dev` | app; all validated |
| Passenger | `andrea.villamor@`, `rogelio.tan@`, `grace.dumaguing@`, `paolo.reyes@`, `lea.santiago@a2z.dev`, or **sign up** in the app | testers should sign up with their own name: it is a task to test |

**Demo data** (`./run.sh --reset-db`):

| Role | Accounts | Notes |
|---|---|---|
| Terminal Manager | `manager@sabaygo.dev` | console |
| Cashier | `cashier@sabaygo.dev` | console; Door cameras, Trip Schedules, Review Starts and Boarding Audit are hidden |
| Dispatcher | `dispatcher@` … `dispatcher5@sabaygo.dev` | app. `dispatcher@` is already on `TRIP-A2Z-LIVE-BOARD` |
| Passenger | `passenger@sabaygo.dev`, or **sign up** in the app | testers should sign up with their own name: it is a task to test |

Two people in one browser (the Terminal Manager and a Cashier) need two
addresses, since a browser keeps one sign-in per address: serve the
console's build a second time with
`python3 operator_console/tool/serve_web.py 3004 operator_console/build/web`
and open port 3004.

More staff: console → Setup → Staff, with a temporary password. A new
Dispatcher must be **validated** before a trip can be assigned to them.
The brief wants one login per person; for alpha, sharing the one
Cashier account is acceptable, but note who did what.

## 4. Timing rules that will surprise testers

- **Unpaid seats are released before departure** (`unpaid_cutoff_min`).
  The Day 1 data has the real **30 min**: book trips that leave **at least
  45 min later**. The demo reset leaves **5 min**: book at least 15 min
  ahead. A reservation not marked Paid by then is cancelled and the
  passenger told.
- **Start opens 30 min before departure**, and only after a van and a
  Dispatcher are assigned and the terminal fees are recorded.
- **"I'm here to pay" is geofenced** to the boarding terminal (Ecoland,
  200 m). From school it is refused, correctly. To test it, raise
  Ecoland's zone for the session (console → Setup → Terminals) to cover
  the room, and set it back to 200 afterwards. It tells the Dispatcher who
  is waiting with cash; it never pays or saves a seat.
- **Trips are not posted by themselves** (finding #2): Trips → **Create
  upcoming trips** when a day's trips are missing.
- **Policy changes apply to trips generated afterwards**, never to trips
  already on the board. Changing the cutoff will not change today's trips.
- **GPS on the map** is simulated by `run.sh` for trips already on the
  road when it started. For a trip that departs during the session:
  `backend/venv/bin/python backend/scripts/tracking_simulator.py --trip <trip_id> --loop`.

## 5. The round: one trip from start to finish

Use a scheduled trip from Ecoland at least 45 min away (Day 1 data; 30
min with the demo data). One Terminal Manager, one Cashier, one
Dispatcher, and four or more passengers.

| # | Who | Does | Expect |
|---|---|---|---|
| 1 | Terminal Manager | Trips → the trip → **Assign van and Dispatcher** (a validated van; `ramon@a2z.dev`, or `dispatcher2@` in the demo) | The Dispatcher's app shows the trip |
| 2 | Passengers | Search from Ecoland to Digos, Kidapawan or Cotabato (Digos or Sta. Cruz in the demo), reserve a seat | A **booking code**, the fare, **Unpaid**, "pay the Dispatcher in cash at the terminal before …" |
| 3 | One passenger | Cancels the reservation | The seat is free again; it cannot be cancelled once Paid |
| 4 | Passengers | Press **I'm here to pay** (only if the zone was widened, §4), go to the Dispatcher, say the code or name, hand play money | Those who pressed it are at the top of the Dispatcher's list, marked HERE TO PAY |
| 5 | Dispatcher | Finds each by name or code, **Mark as Paid** | The seat shows Paid; the passenger's app shows Paid |
| 6 | Dispatcher | Turns on airplane mode, marks one more Paid, turns it off | The mark syncs and keeps the time it was made |
| 7 | Dispatcher | Lists two walk-ins with destinations; adds self as crew | Walk-ins count as Walk-in income, paid at once; crew is not one of the 14 |
| 8 | Cashier | Tries **Start trip** | Refused: the terminal fees are not recorded |
| 9 | Dispatcher → Cashier | Hands over the fees at the counter; Cashier **Record payment**, with the operator's share | Amount = 15 % of (Booked + Walk-in) + ₱75 + ₱50 (the van's first trip today). If the van's parking was recorded earlier, the trip panel shows **Paid earlier today** and the **Balance**, and Record payment asks for the balance |
| 10 | Cashier | **Start trip** | Trip is Boarding; operator name, licence and plate copied onto it |
| 11 | Dispatcher | **Depart** | On the road; paid seats read boarded, unpaid ones no-show; a passenger with a seat can track the van (map position only with the simulator, §4) |
| 12 | Dispatcher | **Arrived** | Completed |
| 13 | Terminal Manager | The bell, then Trips → the trip | An **Unaudited trip · no phone** alert at Start, and the trip panel says Unaudited (no edge phone went out). Not a zero count. Boarding Audit stays empty: it lists only what a phone reported |
| 14 | Cashier | Money → Remittance, the van's statement | Booked, Walk-in, 15 %, ₱75 × trips, ₱50, terminal fees owed, operator's share owed and given |

The brief's sample trip is the arithmetic check: Booked ₱1,370 and
Walk-in ₱80 give 15 % = ₱217.50, terminal fees = ₱342.50, operator's
share = ₱1,107.50. `test_terminal_fees.sh` proves the backend gets it
right; the console and the app must show the same numbers.

## 6. Tasks by role

Step by step, with what each screen should show: `docs/ALPHA_TEST_SCRIPT.md`.

Each line is something a tester should try and report on.

### Passenger (app)

- Sign up, sign in, edit profile, save destinations.
- Search a route and date, see the fare and seats left; reserve.
- See reservations, Unpaid/Paid, the pay-by time; cancel an unpaid one.
- Leave one unpaid past the cutoff: a reminder first, then "Released: not paid in time".
- "I'm here to pay" at the terminal (see the geofence note).
- Track the van on the live map once it departs (only your own trip).
- Request a special trip (whole van, pickup, destination, at most 14); see it approved with a fee to pay in cash.
- Book for someone else: the beneficiary, a pin on the map with a note, own seat too; send a landmark photo in the chat.
- Chat with the Dispatcher; notifications; SOS (no text message goes out
  in alpha; the console must show it).

### Dispatcher (app)

- See today's assigned trips; open one.
- Find a reservation by name or booking code; **Mark as Paid**; cancel one (passenger asked, or nobody came).
- The same in airplane mode, then back online: the marks sync; a late one says *restored* or *seat gone*.
- List walk-ins with destinations (works offline).
- Add self as crew.
- Take a special trip's fee in cash and mark it paid.
- Home pickup: mark the seat Paid (activates it), arrived at the pin, boarded or no-show, end the stop early.
- Fix the list or type a reason when more are aboard than listed (needs the edge phone).
- Depart; Not a passenger trip (pick a reason); Arrived.
- Record a dispute; chat; SOS.

### Cashier (console)

- Trips: assign a van and a Dispatcher (alerts the Terminal Manager); Start a trip; Depart.
- Record the terminal fees and the operator's share (Trips → the trip → **Record payment**, or Money); record a later operator's-share difference; a parking-only charge for a van with no trip.
- Special Trips: enter a walk-in, agree the fee with a note, assign van and Dispatcher.
- Van Status Board; check a phone out and back in; Messages; SOS (responding, close with a note).

### Terminal Manager (console)

- Setup in order: terminals, routes, fares, operators and vans, staff, trip schedules, phones, rules. Validate operators, Dispatchers and vans.
- Add a terminal by mistake and **Delete** it (foot of its edit panel). Try deleting one on the route: refused, naming the route; close it instead.
- Overview: the ring, the map, and a van on the road with no location listed as **No signal**.
- Everything the Cashier does, plus: void a started trip or change its van; lift the payment block with a written reason.
- Reviews: Review Starts (system-started trips), Boarding Audit, Driving Flags, Disputes (Upheld, Rejected, Adjusted).
- Rules & Settings: the 15 % rate, ₱75 ticket, ₱50 parking, unpaid cutoff, home-pickup wait and distance, SOS numbers.

## 7. Reporting a problem

One line per problem, in a shared sheet:

| Time | Role and account | Phone or browser | Trip id | Did | Expected | Got | Screenshot |
|---|---|---|---|---|---|---|---|

The trip id is on the console's Trips page. The developer greps
`logs/backend.log` around that time; every request is there, and a
missing request means the phone never reached the laptop.
