# Alpha test script: every task, screen by screen

*3 Nov 2026. For running the system in a browser on the server laptop.
The setup at school (hotspot, APK) is in `docs/ALPHA_TEST_GUIDE.md`; the
screens and steps are the same on a phone.*

Mark each line ✔ or ✘. For a ✘, write down the time, the window, what
you did, what you expected and what you saw.

## 0. Open four windows

The phone app and the console each run in the browser. One browser keeps
**one login per address**, and `localhost` and `127.0.0.1` count as two
different addresses. That gives four separate logins without incognito:

| Window | Address | Sign in as | Role |
|---|---|---|---|
| A | http://localhost:3000 | `passenger@sabaygo.dev` (or sign up) | Passenger |
| B | http://127.0.0.1:3000 | `dispatcher5@sabaygo.dev` | Dispatcher |
| C | http://localhost:3001 | `manager@sabaygo.dev` | Terminal Manager |
| D | http://127.0.0.1:3001 | `cashier@sabaygo.dev` | Cashier |

Password for all: `sabaygo123`. The phone app's sign-in screen has
dev-account shortcuts.

In windows A and B, press **F12**, then **Ctrl+Shift+M** (device
toolbar) and pick a phone size: the app is laid out for a phone.

**Trips to use** (the demo data is dated from the last reset):

| Trip | Leaves | State | Use it for |
|---|---|---|---|
| `TRIP-A2Z-LIVE-SOON`, Ecoland → Tagum | about 2 h after the reset | scheduled, van NBC-7788, `dispatcher5@` | the main round (section 2) |
| `TRIP-A2Z-DIG-D0-1230`, Ecoland → Digos | 12:30 | scheduled, no van | assigning (section 3) |
| `TRIP-A2Z-LIVE-BOARD` | about 15 min after the reset | started, `dispatcher@` | a started trip, Depart |
| `TRIP-A2Z-LIVE-DEPART` | already left | on the road, GPS simulated | live maps |

## 1. Settings for testing (window C)

Console → **Setup** → step **Rules & Settings**. Each setting takes
effect at once. Write the old value down and put it back afterwards.

| Setting | Set to | Why |
|---|---|---|
| When Start opens | 240 minutes | so the 2-hour trip can be started now |
| When check-in opens | 240 minutes | so "I'm at the terminal" is open now |
| Farthest a home pickup may be from the route | 3000 metres | home pickup ships switched off |
| Release unpaid reservations before departure | leave at 5 for now | section 4 changes it |

For check-in, the browser has to pretend to be at Ecoland. In window A:
F12 → ⋮ → More tools → **Sensors** → Location → *Other…* → latitude
`7.0524`, longitude `125.5931`. Allow location when the page asks.

## 2. The main round: one trip, cash only

On `TRIP-A2Z-LIVE-SOON`. Do the steps in order.

| # | Window | Do | Expect |
|---|---|---|---|
| 1 | A | **Home**: From **Ecoland Terminal**, To **Tagum City Overland Terminal**, today → **Search departures** | The trip about 2 h out is listed with fare and spaces left |
| 2 | A | Tap it → **Reserve a space** | **Reservation** screen: booking code `SG-…`, fare, **Unpaid**, "Pay … in cash to the Dispatcher at Ecoland before HH:MM" |
| 3 | A | **Copy** the code. Back to **Trips** tab | The trip at the top, chip **UNPAID**, "Code SG-… · pay in cash by HH:MM" |
| 4 | B | Open the trip from **your trips** | Trip screen: status, plate NBC-7788 and operator, counters, **RESERVATIONS AND WALK-UPS** |
| 5 | B | Type part of the code (or the passenger's name) in **Name or booking code** | Only that reservation stays; chip **UNPAID** |
| 6 | B | **Mark as Paid** → confirm | Chip **PAID**; "… is Paid and on the passenger list" |
| 7 | A | Wait up to 15 s, or tap **I have paid — check again** | Band turns green: "Paid: you are on the passenger list". **Cancel** is gone; "To cancel a paid seat, ask the Dispatcher" |
| 8 | A | Reserve a second seat on the same trip | Second code, Unpaid |
| 9 | B | That seat → ⋮ → **Cancel reservation** → **Nobody came for it** | It leaves the list |
| 10 | A | Open the second reservation | "Cancelled by the Dispatcher: nobody came for it." |
| 11 | A | Reserve a third seat → **Cancel reservation** → confirm | "Cancelled"; the space is free again |
| 12 | B | **Walk-in** → tap a destination → **COLLECT** → **Done** | The walk-up is on the list as PAID ("walk-up") |
| 13 | B | Scroll to **Terminal fees** | "Hand ₱X to the Cashier" (15 % of the lines + ₱75 ticket + ₱50 parking if unpaid) and "Give the operator ₱Y" |
| 14 | D | **Trips** → pick the trip → **Start and departure** panel | Says the terminal fees are not recorded; **Start trip** waits |
| 15 | D | **Record terminal fees** | Dialog: lines, **Due now** = the same ₱X as step 13, operator's share prefilled |
| 16 | D | **Record payment** | "Terminal fees recorded. Start is open." |
| 17 | D | **Start trip** → confirm | Status **Boarding**; operator name, licence and plate copied |
| 18 | B | Pull down to refresh → **Depart** → confirm | Status DEPARTED; the list shows who was on it |
| 19 | B | **Arrived** → confirm | "Trip completed." |
| 20 | D | **Money** → **Remittance**, van NBC-7788 | Booked (B), Walk-up (W), A2Z's 15 %, DCOTT tickets (n × ₱75), Parking ₱50, **Terminal fees owed**, Paid, **Due now ₱0**, operator's share owed and given |
| 21 | C | **Reviews** → **Review Starts** and **Boarding Audit** | The trip is **Unaudited (no phone)**: correct, no edge phone went out |
| 22 | A | **Trips** tab → **History** | The trip reads "Trip departed" or completed, never "Missed" |

Check the arithmetic: terminal fees = 15 % × (B + W) + ₱75 per trip + ₱50
once a day; operator's share = B + W − terminal fees. The brief's sample
trip (B ₱1,370, W ₱80) gives ₱217.50 / ₱342.50 / ₱1,107.50.

## 3. Assigning a trip (windows C, D, B)

| # | Window | Do | Expect |
|---|---|---|---|
| 1 | C | Trips → 12:30 Digos trip → **Assign van and Dispatcher** → a validated van, `dispatcher2@` | "Van and Dispatcher assigned by …" |
| 2 | — | Sign window B out (**End shift**), sign in as `dispatcher2@` | The 12:30 trip is in the list |
| 3 | D | **Change assignment** on the same trip | The Terminal Manager (C) gets an **Assignment by Cashier** notification (bell) |
| 4 | C | **Lift payment block** with a reason, on a trip whose fees are not recorded | Start opens without the fees; the fees stay owed on the van's statement |
| 5 | C | **Void trip** on a scheduled trip (reason required) | Trip Cancelled; only the Terminal Manager has this button |

## 4. An unpaid reservation is released (windows A, C)

| # | Window | Do | Expect |
|---|---|---|---|
| 1 | A | Reserve on the 2-hour trip; do **not** pay | Unpaid, pay by HH:MM |
| 2 | C | Rules & Settings → **Release unpaid reservations before departure** → **150** | — |
| 3 | A | Wait up to a minute (the release runs every 60 s), refresh **Trips** | The reservation is in **Cancelled**: "Released, unpaid"; **Updates** has a reminder and the release notice |
| 4 | C | Set the setting back to **5** | — |

## 5. Special trip: rent the whole van

| # | Window | Do | Expect |
|---|---|---|---|
| 1 | A | Home → **Rent a van** (top right) → **Request a special trip**: date and time, pickup, destination, passengers ≤ 14 | Chip **WAITING FOR A2Z** |
| 2 | C or D | **Trips** → **Special Trips** → the request → **Agree the fee**: fee, **What the fee is based on** (required), van, Dispatcher | **Approved** |
| 3 | A | Pull to refresh | **APPROVED: PAY IN CASH**, the fee, "Pay … in cash to the Dispatcher at the terminal" |
| 4 | B | Sign in as the Dispatcher you assigned → the rental trip → **Collected ₱… in cash** | Fee recorded as paid |
| 5 | D | Trips → the rental trip → **Record terminal fees** → **Start trip** | Starts |
| 6 | D | Special Trips → **Walk-in request** → customer name, contact, pickup, destination, passengers, fee, basis → **Agree and create the trip** | A trip is created at once (counter walk-in) |
| 7 | C | A request → **Refuse** with a reason | Passenger's card: **NOT POSSIBLE** |
| 8 | A | **Withdraw** a request still waiting | Withdrawn |

## 6. Home pickup: book for someone else

Needs the home-pickup distance from section 1.

| # | Window | Do | Expect |
|---|---|---|---|
| 1 | A | Search → the 2-hour trip → **Book for someone else (home pickup)** | Form: name, contact, map |
| 2 | A | Name, mobile number, tap a pin **near the route** on the map, a note → book | Two booking codes (yours and theirs), "pay both fares in cash to the Dispatcher" |
| 3 | A | Pin far from the route | Refused, in the server's words |
| 4 | A | **Send a landmark photo** (any image file) | "Sent to the trip's Dispatcher in the chat" |
| 5 | B | The trip → **Home pickups** panel → **Landmark photo** | The image opens |
| 6 | B | Reservations: **Mark as Paid** on both seats | The pickup shows activated |
| 7 | B | After Start and Depart: **Van is at the pin** → **Boarded** or **No-show** | Closed; a no-show seat is still owed |

## 7. Screen by screen

### Passenger app (window A)

- [ ] **Welcome** → **Create an account**: first and last name, email, mobile, password, accept terms → signed in. A `.test` email is refused.
- [ ] **Sign in** with a wrong password → error; with the right one → Home.
- [ ] **Home**: swap From/To; change the date; filter by time of day; **No departures found** for a route with no trips.
- [ ] Trip details sheet: fare for this journey, spaces left, route, van; **Reserve a space**; a full trip says "This trip is full".
- [ ] **Reservation** screen: code, Copy, fare, Payment, Pay before, Track the van, I'm at the terminal (with the location override), Undo check-in, Cancel (only when unpaid).
- [ ] **Trips** tab: upcoming, history, cancelled; pull down to refresh.
- [ ] **Track the van** (on the reservation screen): map with the stops and OpenStreetMap credit; the van appears and moves once its trip is on the road and sending GPS (section 8 for a simulator); **SOS** on the map screen → pick a type → **Done**.
- [ ] **Chat** → **New message** → a contact → send; the other side replies.
- [ ] **Updates**: booking, reminder, release, delay notices; search them.
- [ ] **Profile**: **Edit Profile** (details, emergency contact, password), **Saved Destinations** (add, delete), notification switches, **Sign Out**.

### Dispatcher app (window B)

- [ ] Trip list: assigned trips only; another Dispatcher's trip is not there.
- [ ] Trip screen: plate, operator name and licence; counters Paid / Unpaid / Checked in / Spaces left.
- [ ] Reservations: search by name, by code, by part of either; clear; **Mark as Paid**; ⋮ **Cancel reservation** (on a paid seat the dialog says to hand the cash back).
- [ ] **Walk-in**: destination, optional name and number for a receipt, **COLLECT**, **Next passenger**.
- [ ] **Terminal fees** panel: amounts match the Cashier's dialog; **Dispute** a line (operator's words) → the console's Disputes page has it.
- [ ] **Not a passenger trip** → pick a reason → banner → **End**.
- [ ] Crew switch "I am riding in the van as crew" (in the camera panel, when shown).
- [ ] **Depart** (only after Start), **Arrived**.
- [ ] Bell: notifications, **Mark all read**; Messages; **SOS** in the trip screen's top bar.
- [ ] **End shift** → signed out.

### Console: every page (window C, then check window D)

The Cashier (D) does not see Review Starts, Boarding Audit, the
Terminals / Route / Fares / Timetable steps, or Rules & Settings. Check
that they are missing, not just refused.

- [ ] **Overview**: map with `TRIP-A2Z-LIVE-DEPART` moving; click a van → speed, passengers aboard; OpenStreetMap credit.
- [ ] Top strip: vans on the road, trips today, boardings to review (C) or vans owing terminal fees (D), open emergencies.
- [ ] **Trips**: pick a day; pick a trip; passenger list with codes and Unpaid / Paid; Start and departure panel (assign, record terminal fees, start, depart, change van, void).
- [ ] **Van Status Board**: each van's status, where and with whom, terminal fees owed.
- [ ] **Special Trips**: waiting / approved / closed; agree the fee; refuse; walk-in request.
- [ ] **Review Starts** (C): trips started by the system, left unpaid, departed with more aboard, Unaudited → **Review start**.
- [ ] **Boarding Audit** (C): camera count against the list; **View blurred still** (needs the edge phone).
- [ ] **Driving Flags**: open / all; **Mark reviewed**, **Dismiss** (reason), **Record dispute**; "Show en-route stops".
- [ ] **Disputes**: open / decided; **Decide** (C only): Upheld, Rejected, Adjusted with the share due; **Withdraw**.
- [ ] **Remittance** (D): each van's statement; **Record payment** (amount, receipt number, operator's share); **Record operator's share** (a later difference) → "Operator share differs" if it does not match; **Parking-only charge** → pick a van with no trip today → a ₱50 statement → pay it; **Record dispute** on a line; previous days with the day picker.
- [ ] **Messages**: conversations; reply as the cooperative office.
- [ ] **Setup**, in order: **Terminals** (add, staffed, zone), **Route** (add, stops in order with minutes, in service), **Fares** (per pair, takes effect on a date), **Operators & vans** (add operator with licence, add van with plate and spaces; validate in the roster; import/export CSV or PDF), **Staff** (add a Dispatcher with a temporary password; validate; the new Dispatcher signs in on the app), **Timetable** (add a regular departure → **Create upcoming trips**), **Phones** (add phone, issue token, **Check out** to a Dispatcher and van, **Record return**, retire), **Rules & Settings** (edit, save; values show units).
- [ ] **Emergencies (SOS)**: an SOS from the app appears → **Mark as responding** → **Close with a note** → in History. Texts are not sent (`SMS_PROVIDER=disabled`); the dispatch rows say so.
- [ ] Bell: notifications; profile dialog (change password); sign out; light/dark switch in the top bar.

## 8. What a browser cannot test

- **Offline Mark as Paid and walk-ups**: the offline queue uses on-device
  storage, which a browser does not have. Test it on the Android app:
  airplane mode, mark a seat Paid, turn airplane mode off, see it sync.
- **The edge phone** (door counting, blurred stills): needs the Kotlin
  app in a van. Without it every trip is Unaudited, which is correct.
- **GPS for a trip you depart yourself**: only `TRIP-A2Z-LIVE-DEPART`
  is simulated. For another trip:
  `backend/venv/bin/python backend/scripts/tracking_simulator.py --trip <trip_id> --loop`.

## 9. Start again

Stop what is running, then start with fresh data:

```fish
pkill -f run.sh; pkill -f "uvicorn app.main:app"; pkill -f "http.server 3000"
./run.sh --reset-db        # database, backend, console; live trips dated from now, settings back to normal
cd mobile/build/web; python3 -m http.server 3000   # the phone app in the browser, second terminal
```

(If `./run.sh` runs in your own terminal, Ctrl-C there stops it.)
