# Alpha test guide

*Written 3 Nov 2026, between S8 and S7 of the rev 721 refactor
(`docs/HANDOFF_REV721.md`). Covers setting the system up at school, the
accounts, one trip from start to finish, and each role's tasks. Update
the status table as S7 and S9–S11 land.*

The system is three programs on one laptop and two apps on phones:

| Piece | Who uses it | Where it runs |
|---|---|---|
| MySQL, backend (FastAPI) | nobody directly | the server laptop |
| Operator console (web) | Terminal Manager, Cashier | any browser on the network, `http://<laptop-ip>:3001` |
| Mobile app (Android) | Passenger, Dispatcher (same app, the account decides) | testers' phones |
| Edge app (Kotlin) | the in-van phone, counting at the door | optional for alpha; without it every trip is Unaudited (`no_phone`), which is correct behaviour |

## 1. Status

S9 (console) and S10 (app) landed on 3 Nov on branch `rev721-frontends`:
the apps now follow the cash-only backend. Checked: both apps analyse
without errors; every API path and every JSON key both apps read exists
in the backend; the reservation, Mark as Paid, walk-up, cancel and
statement responses were parsed by the apps' own models;
`test_passenger_journey.sh` 55/0 and `test_home_pickup.sh` 68/0.
**Not yet tried on a phone or in a browser**: the first round is also the
first real run of the new screens.

Known and expected during alpha:

- Every trip is **Unaudited (`no_phone`)** unless the edge app is out
  with the van. That is correct behaviour, not a bug.
- After Depart, the server closes every seat still on the trip. A paid
  passenger's reservation then reads **"Trip departed"** (the console
  says "Paid, departed"), because nobody can tell whether that person
  rode. The money is unaffected.
- S7 (special trips: fee basis, counter flow) was not re-checked; the
  flow worked under rev 603 and the fee is now cash to the Dispatcher.
- Four widget layout tests in `mobile/test/layout_test.dart` fail on
  `main` too (a missing provider in the test harness); not a runtime
  problem.

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
the APK build are done now so they are not done on the day.

For the testers' phones, share the APK `run.sh` just built:
`mobile/build/app/outputs/flutter-apk/app-debug.apk` (by cable or a
messaging app; testers allow "install unknown apps"). It is a debug build,
so the sign-in screen shows the dev-account shortcuts.

If `run.sh` warns about ufw, open the two ports once (the rule survives
reboots):

```fish
sudo ufw allow 8000/tcp; sudo ufw allow 3001/tcp
```

### On the day

```fish
./run.sh --reset-db        # fresh demo data, live trips dated from now
```

Reset **shortly before** the session: the seed dates its three live
trips from the moment of the reset. Do not reset after about 22:00 (it
puts the "soon" trip on tomorrow's board).

### Check before testers arrive

1. From a tester's phone browser: `http://<laptop-ip>:8000/health` shows
   `{"status":"ok"}`. If it does not load, the phone cannot reach the
   laptop: check the network and ufw, not the app. An empty
   `logs/backend.log` means the request never arrived.
2. From another laptop: `http://<laptop-ip>:3001` shows the console
   sign-in.
3. Sign in on one phone as `passenger@sabaygo.dev` and see trips for
   Ecoland → Digos.

### Between rounds

`./run.sh --reset-db` again, or keep the data if the next round continues
the same day. Ctrl-C stops everything `run.sh` started (MySQL stays up).

## 3. Accounts

All passwords `sabaygo123`.

| Role | Accounts | Notes |
|---|---|---|
| Terminal Manager | `manager@sabaygo.dev` | console |
| Cashier | `cashier@sabaygo.dev` | console; Review Starts, Boarding Audit and Rules are hidden |
| Dispatcher | `dispatcher@` … `dispatcher5@sabaygo.dev` | app. `dispatcher@` is already on `TRIP-A2Z-LIVE-BOARD` |
| Passenger | `passenger@sabaygo.dev`, or **sign up** in the app | testers should sign up with their own name: it is a task to test |

More staff: console → Setup → Staff, with a temporary password. A new
Dispatcher must be **validated** before a trip can be assigned to them.
The brief wants one login per person; for alpha, sharing the one
Cashier account is acceptable, but note who did what.

## 4. Timing rules that will surprise testers

- **Unpaid seats are released before departure.** The real setting is 30
  min; the reset leaves **5 min** (`unpaid_cutoff_min`) so tests can book
  close to departure. A reservation not marked Paid by then is cancelled
  and the passenger told. Book trips that leave at least 15 min later.
- **Start opens 30 min before departure**, and only after a van and a
  Dispatcher are assigned and the terminal fees are recorded.
- **Check-in ("I'm here") is geofenced** to the boarding terminal (Ecoland,
  200 m). From school it is refused, correctly. To test it, raise
  Ecoland's zone for the session (console → Setup → Terminals) to cover
  the room, and set it back to 200 afterwards. Check-in is a heads-up for
  the Dispatcher; it never pays or saves a seat.
- **Policy changes apply to trips generated afterwards**, never to trips
  already on the board. Changing the cutoff will not change today's trips.
- **GPS on the map** is simulated by `run.sh` for trips already on the
  road when it started. For a trip that departs during the session:
  `backend/venv/bin/python backend/scripts/tracking_simulator.py --trip <trip_id> --loop`.

## 5. The round: one trip from start to finish

Use a scheduled Ecoland → Digos trip at least 30 min away (for example
the 12:30 or 14:00). One Terminal Manager, one Cashier, one Dispatcher,
and four or more passengers.

| # | Who | Does | Expect |
|---|---|---|---|
| 1 | Terminal Manager | Trips → the trip → **Assign van and Dispatcher** (a validated van, `dispatcher2@`) | The Dispatcher's app shows the trip |
| 2 | Passengers | Search Ecoland → Digos (or Sta. Cruz), reserve one space | A **booking code**, the fare, **Unpaid**, "pay the Dispatcher in cash at the terminal before …" |
| 3 | One passenger | Cancels the reservation | The seat is free again; it cannot be cancelled once Paid |
| 4 | Passengers | Go to the Dispatcher, say the code or name, hand play money | — |
| 5 | Dispatcher | Finds each by name or code, **Mark as Paid** | The seat shows Paid; the passenger's app shows Paid |
| 6 | Dispatcher | Turns on airplane mode, marks one more Paid, turns it off | The mark syncs and keeps the time it was made |
| 7 | Dispatcher | Lists two walk-ups with destinations; adds self as crew | Walk-ups count as Walk-up income, paid at once; crew is not one of the 14 |
| 8 | Cashier | Tries **Start trip** | Refused: the terminal fees are not recorded |
| 9 | Dispatcher → Cashier | Hands over the fees at the counter; Cashier **Record payment**, with the operator's share | Amount = 15 % of (Booked + Walk-up) + ₱75 + ₱50 (the van's first trip today) |
| 10 | Cashier | **Start trip** | Trip is Boarding; operator name, licence and plate copied onto it |
| 11 | Dispatcher | **Depart** | En Route; passengers can track the van |
| 12 | Dispatcher | **Arrived** | Completed |
| 13 | Terminal Manager | The bell, then Trips → the trip | An **Unaudited trip · no phone** alert at Start, and the trip panel says Unaudited (no edge phone went out). Not a zero count. Boarding Audit stays empty: it lists only what a phone reported |
| 14 | Cashier | Money → Remittance, the van's statement | Booked, Walk-up, 15 %, ₱75 × trips, ₱50, terminal fees owed, operator's share owed and given |

The brief's sample trip is the arithmetic check: Booked ₱1,370 and
Walk-up ₱80 give 15 % = ₱217.50, terminal fees = ₱342.50, operator's
share = ₱1,107.50. `test_terminal_fees.sh` proves the backend gets it
right; the console and the app must show the same numbers.

## 6. Tasks by role

Step by step, with what each screen should show: `docs/ALPHA_TEST_SCRIPT.md`.

Each line is something a tester should try and report on.

### Passenger (app)

- Sign up, sign in, edit profile, save destinations.
- Search a route and date, see the fare and spaces left; reserve.
- See reservations, Unpaid/Paid, the pay-by time; cancel an unpaid one.
- Leave one unpaid past the cutoff: a reminder first, then "Released: not paid in time".
- "I'm here" at the terminal (see the geofence note).
- Track the van on the live map once it departs.
- Request a special trip (whole van, pickup, destination, at most 14); see it approved with a fee to pay in cash.
- Book for someone else: the beneficiary, a pin on the map with a note, own seat too; send a landmark photo in the chat.
- Chat with the Dispatcher; notifications; SOS.

### Dispatcher (app)

- See today's assigned trips; open one.
- Find a reservation by name or booking code; **Mark as Paid**; cancel one (passenger asked, or nobody came).
- The same in airplane mode, then back online: the marks sync; a late one says *restored* or *seat gone*.
- List walk-ups with destinations (works offline).
- Add self as crew.
- Take a special trip's fee in cash and mark it paid.
- Home pickup: mark the seat Paid (activates it), arrived at the pin, boarded or no-show, end the stop early.
- Fix the list or type a reason when more are aboard than listed (needs the edge phone).
- Depart; Not a passenger trip (pick a reason); Arrived.
- Record a dispute; chat; SOS.

### Cashier (console)

- Trips: assign a van and a Dispatcher (alerts the Terminal Manager); Start a trip; Depart.
- Record the terminal fees and the operator's share (Trips → Record terminal fees, or Money → Remittance); record a later operator's-share difference; a parking-only charge for a van with no trip.
- Special Trips: enter a walk-in, agree the fee with a note, assign van and Dispatcher.
- Van Status Board; check a phone out and back in; Messages; SOS (responding, close with a note).

### Terminal Manager (console)

- Setup in order: terminals, routes, fares, operators and vans, staff, timetable, phones, rules. Validate operators, Dispatchers and vans.
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
