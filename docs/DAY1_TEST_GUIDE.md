# Day 1 test: from an empty system to the first trip

*Run on 3 Nov 2026, branch `rev721-frontends`. The system was set up the
way A2Z would on its first day: an empty database, one Terminal Manager
made by the development team, and everything else entered through the
console and the apps by the people whose job it is. Then one trip was run
end to end with cash. Part 1 is the procedure to repeat it; Part 2 is
what happened on the day; the problems found are in
`docs/DAY1_FINDINGS.md`.*

**Result:** setup and the first trip work end to end: reservation with a
booking code, Mark as Paid, a walk-up, the terminal fees and the
operator's share, Start, Depart, Arrived, and a statement that matches
the brief's arithmetic. Ten defects were found and fixed the same day;
seven items are open, two are questions for A2Z and four are UX notes
(findings table).

**To skip the setup** and start from the state the test ended in:
`./db/load-day1.sh` (section 1.2).

---

## Part 1. The procedure

### 1.1 What runs where

Everything runs on one laptop. The phone app is built for the browser,
so a single screen can play all four people.

| Window | Address | Who signs in |
|---|---|---|
| Console, Terminal Manager | `http://localhost:3001` | `manager@a2z.dev` |
| Console, Cashier | `http://127.0.0.1:3001` | `joy@a2z.dev` |
| App, Dispatcher | `http://127.0.0.1:3000` | `ramon@a2z.dev` |
| App, passenger | `http://localhost:3000` | the tester signs up |

`localhost` and `127.0.0.1` keep separate logins in the browser, which is
how two people share one console and two share one app. All passwords
are `sabaygo123`.

Start the system and serve the app:

```fish
./run.sh                                   # MySQL, backend :8000, console :3001
cd mobile
flutter build web --release --pwa-strategy=none \
    --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
python3 -m http.server 3000 -d build/web   # the app on :3000
```

On phones instead of a browser, follow `docs/ALPHA_TEST_GUIDE.md`
section 2 (`./run.sh --mobile`, the APK). After changing backend code,
stop `run.sh` (Ctrl-C) and start it again: the backend runs without
auto-reload. After changing app code, rebuild and reload the page
(Ctrl+Shift+R).

### 1.2 Start empty, or load the Day 1 data

**Empty, as on the day:**

```fish
./db/apply.sh --reset        # migrations only, no demo seed
./run.sh
cd backend
venv/bin/python scripts/create_first_manager.py \
    --email manager@a2z.dev --phone 09171110001 --first Maria --last Santos
```

The script asks for the password twice (at least 8 characters). Staff do
not self-register and only a Terminal Manager creates staff accounts, so
the first one has to be made by the development team, once.

**Or the state the test ended in:** `./db/load-day1.sh`. It rebuilds the
database from the migrations and loads `db/day1/day1_a2z.sql`. Its trips
are dated 3–5 Nov 2026; sign in as the manager and press **Create
upcoming trips** (Setup → Timetable) to get trips from today. The
passenger in it is `chris@a2z.dev`.

Do **not** use `./run.sh --reset-db` or `./db/reset-dev.sh` for this
test: both load the demo dataset (`@sabaygo.dev` accounts, other routes).

### 1.3 Setup, as the Terminal Manager

Sign in at `http://localhost:3001` as `manager@a2z.dev`. **Setup** shows
a checklist; do the steps in its order. The values are the ones used on
the day. The route and timetable come from A2Z's trip-schedule poster at
the terminal; the stops' minutes, the fares and the operators are test
values (finding 5).

**Step 1. Terminals.** Add each, then switch **Open** and **Staffed** as
listed and press **Save changes** (the switches do nothing until saved;
finding 3).

| Terminal | City | Latitude, longitude | Zone (m) | Staffed | Open |
|---|---|---|---|---|---|
| Cooperative Van Terminal – Ecoland | Davao City | 7.051048, 125.587456 | 200 | yes | yes |
| Digos City Terminal | Digos | 6.738249, 125.365530 | 150 | yes | yes |
| Kidapawan City Terminal | Kidapawan | 7.008300, 125.089700 | 150 | no | yes |
| Cotabato City Terminal | Cotabato City | 7.221700, 124.246700 | 150 | yes | yes |
| Panabo City Terminal | Panabo City | 7.308000, 125.684000 | 150 | no | no |
| Carmen Terminal | Carmen | 7.362000, 125.706000 | 120 | yes | no |
| Tagum City Overland Terminal | Tagum City | 7.447800, 125.807800 | 200 | yes | no |

Ecoland's address: "In front of SM City Ecoland, Quimpo Boulevard,
Davao City". The zone is the check-in geofence.

**Step 2. Route.** Code `ECO-COT`, name "Davao (Ecoland) – Cotabato
City", stops in order with the minutes from the start:

| Stop | Terminal | Minutes |
|---|---|---|
| 1 | Cooperative Van Terminal – Ecoland | 0 |
| 2 | Digos City Terminal | 90 |
| 3 | Kidapawan City Terminal | 195 |
| 4 | Cotabato City Terminal | 300 |

**Step 3. Fares**, from Ecoland: Digos ₱135, Kidapawan ₱340, Cotabato
₱500. Passengers board only at stop 1, so these three are all that is
sold.

**Step 4. Operators and vans.** One operator per van; the operator has
no login.

| Operator | Contact | Licence | Expires | Van | Spaces |
|---|---|---|---|---|---|
| Juan Dela Cruz | 09170000003 | N01-23-456789 | 2028-06-30 | ABC-1234 | 14 |
| Pedro Lumbay | 09170000006 | N01-22-118734 | 2030-09-30 | LCT-9042 | 14 |

A van needs all four photos (front, rear, left, right) before it can be
validated. Press **Validate** on each operator and each van.

**Step 5. Staff.** Each gets the temporary password `sabaygo123`.

| Name | Role | Email | Mobile | Validate? |
|---|---|---|---|---|
| Joy Alcantara | Cashier | joy@a2z.dev | 09171110002 | not needed |
| Ramon Villanueva | Dispatcher | ramon@a2z.dev | 09171110003 | **yes** |
| Liza Cruz | Dispatcher | liza@a2z.dev | 09171110004 | **no**, left Pending on purpose |

**Validate** sits at the foot of the staff panel (finding 4). A Pending
Dispatcher is not offered when a trip is assigned; check that Liza is not.
Sign in once as Joy (`127.0.0.1:3001`) and as Ramon (`127.0.0.1:3000`).

**Step 6. Timetable.** Route ECO-COT, every day, at 5:30, 7:30, 9:30,
11:30 AM and 1:30, 3:30, 5:30 PM. The time picker is 12-hour: check AM
and PM before saving (finding 7). A wrong departure cannot be deleted,
only switched off (finding 17). Then **Create upcoming trips**, 3 days
ahead. A departure already past today is skipped. Nothing creates trips
nightly yet (finding 2), so press it again on later days.

**Step 7. Phones.** Skip it: the in-van phone app is not finished. The
checklist keeps saying "No phone yet" (finding 6); every trip runs
**Unaudited (no phone)**, which is correct behaviour.

**Step 8. Rules & Settings.** Review, change only the one:

| Setting | Value |
|---|---|
| A2Z's share | 15 % |
| DCOTT ticket per trip | ₱75 |
| Parking per van per day | ₱50 |
| Unpaid reservations released | 30 min before departure |
| Start opens | 30 min before departure |
| Check-in opens | 45 min before departure |
| Booking opens | 7 days ahead |
| Home pickup max distance from route | **3000 m** (unset means no home pickup) |

The three timing settings apply to today's trips at once.

### 1.4 The first trip

Pick a departure at least an hour away; below it is the 3:30 PM, so the
times are: **pay by 3:00**, check-in from 2:45, Start from 3:00.

**Assign** (Terminal Manager, or the Cashier when the manager is off
duty): Trips → the 3:30 PM → **Assign van and Dispatcher** → ABC-1234,
Ramon Villanueva. Ramon's app lists the trip.

**Reserve** (passenger, `localhost:3000`):

1. **Create an account**: name, an email (`.test` is refused), a mobile
   number not used by staff, a password.
2. Home: From Cooperative Van Terminal – Ecoland, To Cotabato City
   Terminal, today → **Search departures**. Only departures still ahead
   are listed.
3. The 3:30 PM → **Reserve a space**. Expect a booking code `SG-…`,
   ₱500, **Unpaid**, "Pay ₱500 in cash to the Dispatcher at Ecoland
   before 3:00 PM", and **Cancel** while unpaid.
4. The console's passenger list shows the name, the code and Unpaid.

**Take the cash** (Dispatcher, `127.0.0.1:3000`):

1. Open the trip → **Reservations and walk-ups** → type part of the code
   in **Name or booking code** → **Mark as Paid** → confirm. Chip PAID;
   the passenger's screen turns green within 15 s ("Paid: you are on the
   passenger list") and Cancel goes.
2. **Walk-in** → Digos → **Log** → collect ₱135. Listed as a walk-up,
   paid at once.

**Terminal fees and the operator's share** (Cashier, `127.0.0.1:3001`):
Trips → the 3:30 PM → **Record terminal fees** (the button is the
Cashier's only; the Terminal Manager can only **Lift payment block**).
The dialog prefills **Due now**. Enter the operator's share the dialog
names ("Owed today …") and **Record payment**. The same can be done from
**Money**, on the van's statement.

Record the fees after the Dispatcher has taken the cash, just before
Start. Recorded earlier, each seat paid afterwards is a top-up and the
trip owes again until the Cashier records the difference.

**Start, Depart, Arrived:**

1. At 3:00 PM the Cashier's **Start trip** turns on (no override for the
   time; finding 16). Start warns that no phone went out with the van;
   the trip becomes Unaudited. The operator's name, licence and plate
   are copied onto the trip.
2. Ramon taps **Depart** (the office can too).
3. Ramon taps **Arrived**. Completed.

**Check:**

- Passenger: the paid reservation reads "Trip departed". The server
  closes every seat still on the trip at Depart, because nobody can tell
  whether an app passenger got on; the money is unaffected.
- Terminal Manager: the bell has "Unaudited trip · no phone"; the trip's
  panel says Unaudited. **Boarding Audit** stays empty: it lists only
  what a phone reported (finding 23).
- Cashier: **Money** → ABC-1234 → Paid, nothing due, the figures below.

### 1.5 The numbers of the day

| ABC-1234, 3 Nov | |
|---|---|
| Booked (B): 1 to Cotabato | ₱500.00 |
| Walk-up (W): 1 to Digos | ₱135.00 |
| A2Z's 15 % of ₱635 | ₱95.25 |
| DCOTT ticket, 1 trip | ₱75.00 |
| Parking, the van's day | ₱50.00 |
| **Terminal fees** | **₱220.25** |
| **Operator's share** (₱635 − ₱220.25) | **₱414.75**, given in full |

### 1.6 Optional checks

**Check-in** ("I'm at the terminal") is geofenced to Ecoland's 200 m.
The browser has to pretend to be there:

- *Chromium:* F12 → ⋮ → More tools → **Sensors** → Location → Other…,
  latitude `7.051048`, longitude `125.587456`.
- *Firefox* has no Sensors panel. In `about:config` set
  `geo.provider.network.url` to
  `data:application/json,{"location":{"lat":7.051048,"lng":125.587456},"accuracy":10}`
  and `geo.provider.use_geoclue` to `false` (Linux), reload, allow
  location. Reset both afterwards: they apply to every site.

Check-in only tells the Dispatcher the passenger is near; it does not
pay a seat or save it from the release.

**Track the van** moves only while something sends GPS. Between Depart
and Arrived:

```fish
cd backend; venv/bin/python scripts/tracking_simulator.py --trip <trip_id> --speed 20
```

For the trip id: `docker compose exec mysql mysql -u root -p sabaygo -e
"SELECT trip_id, departure_datetime FROM trips WHERE DATE(departure_datetime) = CURDATE()"`
(the root password is `MYSQL_ROOT_PASSWORD` in `.env`).
Passenger tracking is out of scope by the brief (finding 22).

**Messages:** a message from Ramon to the passenger puts a number on
the passenger's **Chat** within 15 s, and on the console's **Messages**
within 30 s.

---

## Part 2. What happened on 3 Nov

| Time | What | Finding |
|---|---|---|
| 10:48 | Database rebuilt empty; first Terminal Manager created | |
| 10:58 | Terminals entered; two closures needed a second try with **Save changes** | 3 |
| ~11:00 | Route and fares from A2Z's poster, with test minutes and fares | 5 |
| 11:36 | Operators and vans validated | |
| ~11:45 | Staff created; Ramon validated later (the button was missed) | 4 |
| 11:45 | Messages tested: no unread number on the console menu | 1 |
| 11:57 | Trips created for 3 days; the 11:30 AM was missing and a 3:30 AM saved by mistake | 7, 17 |
| 13:37 | Home pickup distance set to 3000 m | |
| 13:44 | 1:30 PM assigned to LCT-9042 and Ramon, already 14 min late; nobody could book it any more | |
| 13:51 | ₱125 recorded on it, then the trip was voided: the ₱75 ticket left the statement, the ₱125 stayed | 8 |
| 13:53 | 3:30 PM assigned to ABC-1234 and Ramon; its ₱125 recorded from Money with nobody listed | 9 |
| 14:03 | Passenger signed up and reserved SG-CYVQDJ; the console listed the code without the name, the app the name one letter per line | 10, 11 |
| 14:20 | Ramon marked it Paid. The statement owed ₱75 but the trip stayed Paid: the payment from Money had not locked the list | 14, 15 |
| 14:34 | Walk-up to Digos (SG-T6NCZH) after **Log** was fixed for the browser | 13 |
| 14:35 | Joy recorded ₱95.25 and the operator's ₱414.75 | |
| 15:00 | Start; Unaudited, no phone | |
| 15:03 | Depart (Ramon) | |
| 15:07 | Arrived | |
| ~15:20 | Boarding Audit empty, as designed; the guide had said otherwise | 23 |
| 15:35 | Journey scripts after the fixes: `test_terminal_fees.sh` 79/0 (10 new checks for findings 14–15), `test_trip_lifecycle.sh` 135/0 | |

Tester questions answered on the day, kept here for the next round:

- **Who taps Depart?** The Dispatcher, or the Cashier or Terminal
  Manager (brief §4.2 rule 7); the trip records which.
- **Why Change van after departure?** It corrects the record (rule 12):
  the van that actually left was not the one recorded, or the system
  started the trip with the wrong van. Terminal Manager only, with a
  reason; the earlier van is kept. The money recorded stays on the old
  van's statement (finding 8).
- **What is the booking code for?** It replaced the QR ticket: the
  passenger says it and the Dispatcher finds that one reservation to
  mark Paid. Walk-ups get one for the receipt and any dispute.
- **Why no override to Start early?** The brief gives Start a window
  setting and an override only for the payment block. The window equals
  the unpaid cutoff, and a van that leaves early is started by GPS and
  held for review (finding 16).
