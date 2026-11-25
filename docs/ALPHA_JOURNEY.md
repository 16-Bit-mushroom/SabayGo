# Alpha journey: one trip, from posting it to the statement

*20 Nov 2026, for round 2 (21 Nov). The database holds the setup data
only: terminals, route ECO-COT, fares, operators, vans, staff, trip
schedules, settings. No trips, no passengers, no phone. Setting up the
laptop and the network: `docs/ALPHA_TEST_GUIDE.md` §2. Reporting a
problem: the same guide, §7.*

Do the steps in order. Each row says who does it, what to do, and what
should happen. Write down every row where it did not.

## Who plays what

All passwords `sabaygo123`.

| Role | Account | Where |
|---|---|---|
| Terminal Manager | `manager@a2z.dev` | console, `http://<laptop-ip>:3001` |
| Cashier | `joy@a2z.dev` | console in a second browser, or on the laptop at `http://127.0.0.1:3001` (a browser keeps one sign-in per address) |
| Dispatcher | `ramon@a2z.dev` (also validated: `liza@`, `nonoy@`, `jun@`, `mae@a2z.dev`) | Android app, or a browser at `http://<laptop-ip>:3003` |
| Passengers, 3 or more | they **Create account** in the app with their own names | Android app (a browser cannot do "I'm here to pay") |
| Camera phone | no account: the edge app and its set-up code | a spare Android phone on a stand, facing the laptop screen |

Vans: `ABC-1234`, `LCT-9042`, `TST-1023`, all validated. Fares from
Ecoland: Digos ₱150, Kidapawan ₱340, Cotabato ₱363.

## Before the round (facilitator, about 15 min)

| # | Do | Check |
|---|---|---|
| 0.1 | Join the camera phone to the laptop's Wi-Fi (Settings › Wi-Fi; Android remembers it). Plug both phones into the laptop by USB, then `./run.sh --mobile --edge` on the school network | The summary says **Camera phone (edge app) reporting over Wi-Fi from …**: unplug the camera phone, it no longer needs the cable. The passenger app goes to the other phone, never the camera. From a phone, `http://<laptop-ip>:8000/health` shows `{"status":"ok"}` |
| 0.2 | If the laptop's address changed since 20 Nov, rebuild the browser app for port 3003 (`ALPHA_TEST_GUIDE.md` §2) | 3003 shows the sign-in screen |
| 0.3 | Console as Terminal Manager → **Setup** → Terminals → Cooperative Van Terminal – Ecoland → **Zone** large enough to cover the room (at most 2000 m) | Only needed for "I'm here to pay". If the room is more than 2 km from Ecoland, set Ecoland's latitude and longitude to the room instead for the session |
| 0.4 | *Optional, for an overspeed flag:* Setup → **Rules & Settings** → **Speed limits by route** → ECO-COT → 30 on every stretch → save | The simulated van drives at about 45 km/h. The console cannot clear a limit afterwards, only change it |
| 0.5 | On the camera phone, turn **Location off**, so the map shows the simulated van and not the school | — |
| 0.6 | Only if `run.sh` said the set-up code is missing or refused: console → Setup → **Phones** → **Add phone** (or the phone → **New set-up code**). The code is shown once. On the phone: edge app → **Set-up** → type the code (the server is already filled in); then the Checklist (permissions, battery optimisation off) | "Server reached and this phone's set-up code accepted" |
| 0.7 | Once counting, never tap **Stop** or **Benchmark** on the camera phone | A stopped phone counts and sends nothing, and a trip started while it is silent is **Unaudited** |
| 0.8 | Laptop: a bright video of people walking through a doorway, from a fixed camera, full screen, paused at the start. Phone on its stand 30–50 cm away, the doorway filling most of its picture | Avoid dark scenes: 15 s of a dark, even picture counts as a covered lens |

**On a network that keeps its devices apart** (21 Nov: the school's
LIC-WIFI-OPEN; no phone could reach the laptop), every phone works over
its USB cable instead of 0.1. Build the app once to dial `127.0.0.1`
(`usb_phones.sh` has the command), then `./usb_phones.sh` each time a
phone is plugged in: it opens the tunnel and installs and opens the app.
A USB reset kills that phone's tunnel (the camera phone's reset four
times in its first hour): keep `./usb_phones.sh --watch` running in a
second terminal, and it reopens each tunnel within 3 s. The camera phone's edge app is given
`http://127.0.0.1:8000/api/v1` as its server once. Browser testers use
the laptop itself, `http://localhost:3002` and `http://localhost:3003`,
with the browser build made for `127.0.0.1` too.

## The round

**Timing.** Post the trip to leave **40 minutes from now**. "I'm here to
pay" opens 45 min before departure (so at once). **Start opens 30 min
before** (10 min in). An unpaid reservation is released **5 min before**.
Nothing waits for the departure time itself: Depart can be pressed as
soon as the trip has started.

### A. Post the trip and get the van ready

| # | Who | Do | Expect |
|---|---|---|---|
| 1 | Terminal Manager | **Trips** → **Post a trip** → route ECO-COT, Today, **Leaves at** = now + 40 min → Post | The trip is on the Trips list and bookable in the app at once |
| 2 | Terminal Manager | The trip → **Assign van and Dispatcher** → `TST-1023`, Ramon | Ramon's app lists the trip |
| 3 | Cashier or Terminal Manager | Setup → **Phones** → the camera phone → **Check out** → van `TST-1023`, Dispatcher Ramon | The phone shows as out with TST-1023. **Overview → Door cameras** shows it reporting |
| 4 | Dispatcher, on the camera phone | Edge app → **Door line** → drag the yellow line across the video's doorway, the red box onto an empty corner of the picture, the arrow pointing *in* → **Save** | "Door line saved for this van." |

### B. Passengers reserve

| # | Who | Do | Expect |
|---|---|---|---|
| 5 | Each passenger | App → **Create account** with your own name; sign in | The search screen |
| 6 | Each passenger | From Ecoland, to Digos, Kidapawan or Cotabato, **Today** → the trip → **Reserve a seat** | A **booking code**, the fare, **Unpaid**, and a pay-by time |
| 7 | One passenger | Reserve a second seat → **Cancel reservation** → confirm | Cancelled; the seat is free again |
| 8 | Passengers | **I'm here to pay** (Android, inside the widened zone) | Accepted. On the Dispatcher's list they move to the top, marked **HERE TO PAY**. Refused outside the zone: that is correct |

Leave **one** reservation unpaid on purpose: it becomes a no-show at
Depart, or is released 5 min before departure if Depart comes later.

### C. The Dispatcher takes the cash

| # | Who | Do | Expect |
|---|---|---|---|
| 9 | Dispatcher | App → the trip → type a name or booking code in **Name or booking code** → **Mark as Paid** → confirm | Chip **PAID**. The passenger's screen turns green within 15 s (or tap **I have paid — check again**). A paid seat can no longer be cancelled by the passenger |
| 10 | Dispatcher | *Phone only, optional:* airplane mode on, mark one more Paid, airplane mode off | The mark syncs and keeps the time it was made |
| 11 | Dispatcher | **Walk-in** → tap a destination → **COLLECT** → **Done**; do it twice | Two walk-in lines, **PAID** at once (Walk-in income) |
| 12 | Dispatcher | **I am riding in the van as crew** | "You are marked crew: not counted." Crew is not one of the 14 seats |
| 13 | Dispatcher | Scroll to **Terminal fees** | "Hand ₱X to the Cashier" and "Give the operator ₱Y" |

### D. The Cashier: fees, then Start (from 30 min before departure)

| # | Who | Do | Expect |
|---|---|---|---|
| 14 | Cashier | **Trips** → the trip → **Start trip** | Refused: Start waits for the terminal fees |
| 15 | Cashier | **Record payment**, with the operator's share | Due = 15 % of (Booked + Walk-in) + ₱75 DCOTT ticket + ₱50 parking (the van's first trip today): the same ₱X as step 13 |
| 16 | Cashier | **Start trip** → confirm | Status **Boarding**; the operator's name, licence and plate are on the trip |

### E. Boarding at the door: the camera counts

| # | Who | Do | Expect |
|---|---|---|---|
| 17 | Facilitator | Play the video | Each person who crosses the yellow line inward is counted as a boarding. Door cameras shows the camera working, lens clear (and GPS off, as set in 0.5) |
| 18 | Dispatcher | App → the trip | If the camera counts **more aboard than listed**: "The camera counts more aboard than listed. List them as walk-ins, or explain below, before Depart." List them or type a reason; **Depart waits until then** |
| 18a | Cashier | If walk-ins were listed in step 18: Trips → the trip → **Record payment** again, *before* Depart | The new lines show as **top-up**: 15 % of their fares, now owed. If Depart came first, the trip is marked **Left unpaid**; recording the top-up afterwards brings the Balance to ₱0 and the trip to Paid, and the Left unpaid alert stays on record |

### F. On the road: map, SOS, driving flags

| # | Who | Do | Expect |
|---|---|---|---|
| 19 | Dispatcher | **Depart** → confirm | **DEPARTED**. Paid seats read boarded; the unpaid one is a no-show. Within about 20 s the van appears and moves along the route (simulated GPS) |
| 20 | A passenger with a paid seat | Reservation → **Track the van** | The van moving, with arrival times for the stops ahead |
| 21 | Terminal Manager | **Overview** | The van on the map with its trip |
| 22 | The same passenger | On the map: **Emergency SOS** → confirm | The console's bell and **Emergencies (SOS)** show the alert with the phone's position. No text message goes out (SMS is off) |
| 23 | Terminal Manager | Emergencies (SOS) → the alert → **Responding**, then **Close with a note** | "Closed: <note>" |
| 24 | Terminal Manager | *If 0.4 was done:* **Reviews** → **Driving Flags** | An **overspeed** flag on the trip a few seconds after Depart |

### G. Close the trip

| # | Who | Do | Expect |
|---|---|---|---|
| 25 | Dispatcher | **Arrived** → confirm | "Trip completed." The van leaves the map (the simulator stops by itself) |
| 26 | Terminal Manager | **Reviews** → **Boarding Audit** | The door count against the list: the explained boardings from step 18 with their reason, or a paid passenger who did not come if the camera counted fewer |
| 27 | Cashier | Setup → **Phones** → the camera phone → return it | "Return recorded." |
| 28 | Cashier | **Money** → van `TST-1023`'s statement | Booked (B), Walk-in (W), 15 %, ₱75 ticket, ₱50 parking, terminal fees, paid, **Balance ₱0**, the operator's share and what was paid to the operator |
| 29 | Passenger | **Trips** → History | The trip completed, never "Missed" |

Check the arithmetic on step 28: terminal fees = 15 % × (B + W) + ₱75 +
₱50; operator's share = B + W − terminal fees. The brief's sample (B
₱1,370, W ₱80) gives ₱217.50, ₱342.50 and ₱1,107.50.

## If something stops the round

| Symptom | Cause |
|---|---|
| No trip in the passenger's search | The trip was not posted for today, or its time has passed |
| Start refused after the fees were recorded | More than 30 min before departure: wait, or post the trip later next time |
| "I'm here to pay" refused | The phone is outside Ecoland's zone (0.3), or location is off on that phone |
| The camera counts nothing | The trip has no van, the phone is not checked out to that van, the door line was not saved, or the picture is too dark or too small |
| The camera phone says "Stopped" or "Server: offline" | Tap **Start**. Offline: the phone left the laptop's Wi-Fi. It keeps what it counted and sends it once back |
| **Door cameras** shows no report for over a minute, the phone still on the Wi-Fi | The counting service is not running on the phone: open the edge app and tap **Start**. If it happens again, the Checklist: battery optimisation off, and the Realme background switches |
| Depart is not there | The trip has not been started (step 16), or the camera's extra boardings are not listed or explained (step 18) |
| The van is not on the map | The camera phone's Location is on (the map shows the phone's real place instead), or `run.sh` was not running when the trip departed |
| A request fails on a phone, nothing in `logs/backend.log` | The phone cannot reach the laptop: network or ufw, not the app |

## After the round

- Set Ecoland's zone back to **200 m**, or its latitude and longitude back
  to `7.051048, 125.587456`.
- A second round can post another trip on the same van. Its parking is
  already paid for the day, so that trip owes the 15 % and ₱75 only.
- Extras if time allows (`ALPHA_TEST_GUIDE.md` §6): a reservation left
  unpaid on a later trip until it is released; a special trip; booking for
  someone else with a home pickup pin; chat with a photo; a dispute; lift
  the payment block with a reason; void a trip.
