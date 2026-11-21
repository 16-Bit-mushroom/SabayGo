# SabayGo mobile app: brief for a UI/UX redesign

*Written 20 Nov 2026 from the app as it is built today. Hand this whole
file to the designer (person or AI).*

## Your task

Redesign the SabayGo mobile app so it is **easier to use and more
appealing**, without changing what it does. Every feature, rule and
screen below already works; we want it clearer, calmer and better
looking.

Please give back:

1. **A short design direction**: the principles you followed and why
   they suit these users.
2. **Design tokens**: colour, type scale, spacing, corner radius,
   elevation. Start from the current ones (section 8) and change them only
   where it helps.
3. **Every screen in sections 5 and 6, laid out**, at a 390 × 844 phone
   size, including its main states: loading, empty, error or offline, and
   success. A mockup image or HTML/CSS plus a few lines of spec per screen
   both work.
4. **The two main journeys as step sequences**: a passenger booking and
   paying, and a Dispatcher boarding a van.
5. **A component list**: buttons, cards, status chips, list rows, sheets,
   dialogs, the journey strip, money amounts.

It will be built in **Flutter (Material 3) for Android phones**, so
please keep layouts buildable with standard Material widgets.

---

## 1. What SabayGo is

SabayGo is a booking and fleet system for **UV Express vans**: shared
14-seat vans that run fixed government-approved routes in Davao City,
Philippines. The pilot partner is **A2Z**, a transport cooperative with
its own van terminal. The app was built as a university capstone
project.

- A **passenger** reserves a seat on a departure from the starting
  terminal and gets a **booking code**, so they don't have to queue at
  the terminal without knowing whether there is room.
- **Payment is cash only.** The passenger hands the fare to the
  **Dispatcher** (A2Z's staff member at the van) at the terminal, and the
  Dispatcher marks the seat **Paid** in the app. Nothing is paid inside
  the app.
- A camera phone at the van door counts people getting on and off. The
  system checks that count against the Dispatcher's passenger list
  before the van leaves, so a fare that was never recorded is caught.
  This is the project's core idea.
- The A2Z office uses a separate web console. It is not part of this
  brief, but the app shares its colours and fonts.

## 2. Who uses the app

One app, two kinds of user. The account decides which side opens at
sign-in.

**Passenger**: the commuting public of Davao City.
- Uses a budget or mid-range Android phone, often on patchy mobile data.
- Varies widely in comfort with apps. Includes older people and
  relatives booking for them.
- Reads the app outdoors and in a hurry. The interface is English only,
  in plain words.

**Dispatcher**: A2Z staff who rides the van.
- Works standing at the van door, often **one-handed**, in **sunlight**,
  with a queue of passengers and cash in the other hand.
- Needs to see a passenger's status at a glance and act in one tap.
- Sometimes has no signal: marking Paid, cancelling and adding a walk-in
  must keep working offline and sync later.

Two other people appear in the app but never use it:
- The **operator** owns the van and always drives it. They have no
  account and are shown only as name, licence number and van plate.
- The **A2Z office** (Terminal Manager and Cashier) works in the web
  console. In the app it is a chat contact.

## 3. Rules the design must keep

These are decisions of the cooperative and the project. Please don't
design them away.

1. **Cash only.** No in-app payment, no card or e-wallet, no QR ticket
   to scan. The flow is: reserve, get a booking code, pay cash to the
   Dispatcher at the terminal, the seat turns **Paid**.
2. **Unpaid seats are released.** If a seat is still unpaid 30 minutes
   before departure (an A2Z setting), it is cancelled automatically and
   given to someone else. The passenger is reminded before that. The
   **"pay before" time** therefore matters a great deal and must be easy
   to see.
3. **"I'm here to pay"** is the check-in. The passenger taps it when they
   reach the terminal, and it only works near the terminal. It tells the
   Dispatcher who is waiting with cash. There is no separate check-in
   step.
4. **Seats have no numbers.** UV Express doesn't assign seats, so show
   "seats left" or "your seat", never "Seat 5". Each van takes 14
   passengers.
5. **Boarding happens only at the starting terminal, before departure.**
   The one exception is the **home pickup** of an elderly or disabled
   passenger.
6. **Fares are fixed** by the government for each pair of terminals.
   They are shown before booking and can never be typed or edited.
7. **No refunds or rescheduling in the app.**
   - A passenger can cancel an *unpaid* seat in the app.
   - To cancel a *paid* seat, they ask the Dispatcher in the chat, who
     hands the cash back.
   - To change a trip: cancel, then book again.
8. **Never show an invented number.**
   - No camera reporting: say "Not counted", never 0.
   - Old van position: say "last known" and how old it is.
   - Tracking not started yet: say "tracking begins when the van leaves
     the terminal".
9. **Privacy of the van's location.** Only a passenger with a seat on
   that trip sees the van on the map, and only while it is boarding or
   on the road. The van's position is the driver's position.
10. **Camera notice.** Before booking, the passenger is told about the
    door camera:
    - it counts people;
    - faces are blurred on the phone, and no video leaves the van;
    - a still of each boarding is kept for a set number of days;
    - only A2Z's Terminal Manager sees it.
11. **SOS takes two taps.** The first opens a sheet; the alert is sent
    only from the button inside it. A one-tap panic button on a screen
    used all day would go off by accident.
12. **Words.** Use these exactly:
    - **Seat**, **booking code**, **Paid / Unpaid**, **walk-in** (a
      passenger with no booking who pays at the van).
    - **Dispatcher**, never "conductor"; **operator** for the van
      owner/driver.
    - **Balance** and **Total paid**, never "owed", "due" or "given".

## 4. How the app is organised

**Passenger**
```
Welcome ─┬─ Sign in
         └─ Create account
Main screen
  ├─ top bar: the van logo and a "Rent a van" button on Home;
  │           the tab's name on the other tabs
  └─ bottom bar (labels always shown):
       Home (search) · Trips · Chat · Updates · Profile
           │            │                         (Chat and Updates show
           │            │                          unread-count badges)
           │            └─ Reservation ─┬─ Track the van (live map) ─ SOS
           │                            └─ Cancel
           └─ results ─ Trip details sheet ─┬─ Reserve a seat → Reservation
                                            └─ Book for someone else
                                               (home pickup)
```

**Dispatcher**
```
Sign in
My trips
  ├─ top bar: Messages · Notifications · End shift
  └─ Trip screen (one per trip): the passenger list and everything for that trip
       ├─ top bar: SOS · Refresh · More (Not a passenger trip)
       ├─ Add walk-in → Walk-in screen
       └─ Depart → Arrived
```

---

## 5. Passenger screens

### 5.1 Welcome
- The logo.
- The line "Book a seat on your UV Express before you get to the
  terminal."
- Two buttons: **Create an account** and **Sign in**.

### 5.2 Sign in
- Heading "Welcome back" and the line "Sign in to book a seat or start
  your shift." (Dispatchers use the same screen.)
- Email and password fields, with show/hide on the password.
- **Sign in** button and a link to create an account.

### 5.3 Create account
- Fields:
  - first name and last name;
  - email;
  - mobile number (format 09XXXXXXXXX or +639XXXXXXXXX);
  - password (at least 8 characters).
- A checkbox to agree to the terms and privacy notice.
- **Create account** button.
- Passengers only: staff accounts are made by the office.

### 5.4 Home: find a departure
- **Search card**, read top to bottom:
  - **From**: the boarding terminal, chosen from a searchable list;
  - **To**: the destination;
  - a swap button between the two;
  - **Day**: Today, Tomorrow or Other day (opens a calendar).
- Terminal names can be long ("Davao City Overland Terminal"). The list
  holds only terminals on A2Z's routes.
- **Time-of-day filter chips:** Any time, Leaving soon, Morning,
  Afternoon, Evening, Last trip.
- **Results:**
  - "N departures";
  - one **trip card** each, showing departure time and fare on top, the
    route, and seats left ("Only 2 left", "FULL").
- **States:**
  - before choosing: "Where are you going? Pick your boarding terminal
    and destination…";
  - nothing found: "Nothing runs this journey on the date you picked.
    Try another day.";
  - load error, with **Try again**;
  - two people booking the last seat at once: "Someone else is booking
    this trip right now. Please try again."

### 5.5 Trip details (bottom sheet)
This is the last step before reserving. It shows:
- Departure time and "Arrives about …".
- The **journey strip**: a boarding marker and an alighting marker
  joined by a rail, with the terminal names.
- **Fare**, the largest thing on the sheet, with the note "Set by LTFRB
  for these two terminals".
- **Van**: the plate, or "Assigned later".
- **Seats left**: "8 of 14", or "Filling up" / "FULL".
- The cash note: "You pay in cash to the Dispatcher at the terminal. A
  seat still unpaid shortly before departure goes to someone else."
- The camera notice (rule 10).
- The primary button **Reserve a seat**, and a second option **Book for
  someone else (home pickup)**.

### 5.6 Book for someone else (home pickup)
For a relative who cannot come to the terminal because of age or
disability. The person booking takes a seat too: they board at the
terminal, ride along, and the van stops for the relative at a map pin on
the way.

- **Step 1, who and where:**
  - the passenger's name and contact number;
  - **a map** where you tap the place they will wait (it must be near
    the route; "Here" uses your own location);
  - an optional note for the Dispatcher ("Green gate beside the
    sari-sari store");
  - a summary, "2 seats: Ecoland → Digos", and the total for both;
  - **Reserve both seats**.
- **Step 2, done:**
  - two booking codes, "Your seat" and "<name>'s seat";
  - what to do next: come to the terminal and pay both in cash; once
    both are Paid, the van stops at the pin;
  - **Send a landmark photo**, which goes to the Dispatcher in the chat.

### 5.7 Trips (my reservations)
- **Next trip** card at the top:
  - status;
  - **booking code** in large type ("BOOKING CODE SG-7K2Q9M");
  - departure day and time, and a countdown ("in 1 h 20 min");
  - From → To, and the fare;
  - the instruction for the current state, for example "Pay ₱150 in cash
    by 10:00 AM" or "Paid. Your seat is yours.";
  - a Cancel button while unpaid.
- **Also booked**: later reservations, as compact rows.
- Home pickup bookings carry an extra line ("Your seat, riding with
  Lola Nena…") and the landmark-photo button.
- Below, two tabs: **Past trips** and **Cancelled**. A released seat is
  labelled "RELEASED, UNPAID".
- Empty state: "No trip booked. Search for a departure on the Home tab…"
- Cancel asks first: "Cancel this reservation? Your seat will be
  released for someone else. You have not paid, so there is nothing to
  hand back." with **Keep it** and **Cancel reservation**.

### 5.8 Reservation (one booking)
This is the screen a passenger shows at the van door.

- **Booking code**, very large, with a **Copy** button and the line
  "Show this code at the van door / give this code or your name to the
  Dispatcher when you pay".
- A **status band**: one tinted panel with a headline and one sentence
  saying what to do. The states, in order:
  1. **Reserved: pay at the terminal.** "Pay ₱150 in cash to the
     Dispatcher at Ecoland before 10:00 AM. An unpaid reservation is
     released then and the seat goes to someone else."
  2. **Here to pay.** "The Dispatcher knows you are here. Hand over the
     cash and show your code; your seat turns Paid on this screen."
  3. **Paid: you are on the passenger list.** "Board at Ecoland before
     the van leaves at 10:30 AM."
  4. **On board.** "Have a safe trip."
  5. **The van has departed** / **Trip completed** ("Thank you for
     riding with A2Z").
  6. **Released: not paid in time**, **Cancelled**, or "The van left
     before this reservation was paid". Each comes with **Book again**.
- **Details:** departs, arrives about, passenger, fare, payment ("Paid
  in cash" or "Unpaid: cash to the Dispatcher"), pay before, van.
- **Actions**, depending on state:
  - **I'm here to pay**: opens near departure, location-checked; shows
    "you are too far from the terminal" when it can't be used;
  - **I have paid — check again**;
  - **Track the van**;
  - **Cancel reservation** (unpaid only). A paid seat shows "To cancel a
    paid seat, ask the Dispatcher in the chat."

### 5.9 Track the van (live map)
Open only to a passenger with a seat on that trip, while it is boarding
or on the road.

- **Map** (OpenStreetMap, credit "© OpenStreetMap contributors" always
  visible):
  - the route as numbered stops joined by straight lines;
  - the passenger's boarding and alighting stops highlighted;
  - the van marker.
- **Van info:** "Near Digos · 52 km/h" and when it last reported.
- **ETA list:** each remaining stop with distance and time ("12.4 km ·
  11:05 AM · 25 min").
- **Buttons:** Centre on the van, Refresh, and the **SOS** button.
- **States:**
  - not reporting yet: "The van has not started reporting yet… tracking
    begins when it leaves the terminal";
  - stale: "Last reported 5m ago. This is where the van was, not where
    it is now.";
  - "The van has already passed your boarding stop";
  - map unavailable.
- Known limitation: the ETA for the *next* stop can disappear about
  halfway along the leg. An "Arriving soon" state would help.

### 5.10 Rent a van (special trip)
Opened from the **Rent a van** button in the Home tab's top bar.

- **List of my requests**, each with a status chip:
  - WAITING FOR A2Z;
  - APPROVED: PAY IN CASH (with the agreed fee);
  - PAID;
  - DONE;
  - NOT POSSIBLE (the reason is in Updates);
  - WITHDRAWN.

  Each also shows pickup → destination and the number of passengers. A
  pending request has **Withdraw**.
- **Request form:**
  - pickup date and time;
  - pickup address and destination;
  - number of passengers, with − and + buttons, at most 14;
  - **Send request**.

  The text explains that A2Z agrees the fee by pickup and destination,
  and that it is paid in cash before the van leaves.

### 5.11 Chat
- **Conversation list:**
  - each row has the other person's name and role label (A2Z office,
    Dispatcher), the last message, the time and an unread count;
  - a **New message** (pencil) button;
  - empty state: "No messages yet. Tap the pencil to start a
    conversation."
- **New message:** a passenger can only write to the Dispatcher of a
  trip they are on and to the A2Z office. There is no free search.
- **Thread:**
  - bubbles, a message box and **Send**;
  - photos, for example a landmark photo;
  - hold your own message to **Edit** or **Delete** it. It then shows
    "· edited" or "Message deleted" for both people.

### 5.12 Updates (notifications)
- A list of reminders and trip changes, with a search box.
- Some updates carry an action button: **Book a seat**, **Find another
  trip** or **See the next departures**. For example, a seat released
  unpaid offers Find another trip.
- Empty state: "No updates yet. Reminders and changes to your trips will
  appear here." No-match state: "Nothing matches".

### 5.13 Profile
- **Summary:** name, email, phone; **Edit profile**.
- **Account:**
  - home address;
  - gender;
  - **emergency contact** (name, relation, phone).
- **Preferences:**
  - **Saved destinations** (e.g. "Mom's house"), so the passenger hears
    when a van runs there;
  - notification switches: Allow notifications, Departures to my saved
    destinations, Changes to my trips.
- **Edit profile:**
  - personal details;
  - emergency contact;
  - change password (current and new).

  The email can't be changed.
- **Sign out** (asks first), and **Delete account**: confirmed with the
  password; booking history is kept for A2Z's records.

### 5.14 SOS sheet (passenger and Dispatcher)
- Title "Emergency SOS".
- Choose what is happening: Medical, Accident, Security, Breakdown,
  Other.
- An optional note.
- The line "The cooperative office is alerted immediately, and the
  emergency numbers on file are texted."
- A red **Send alert now** button.
- **After sending:** "Alert sent", each number with whether the text
  actually went out, and "If nobody reaches you shortly, call for help
  directly."

---

## 6. Dispatcher screens

### 6.1 My trips (shift home)
- **Top bar:** "SabayGo" with a **DISPATCHER** label, and:
  - **Messages**, with an unread badge;
  - **Notifications**, with Mark all read;
  - **End shift**, which signs out after asking first.
- **Trip list**, grouped **Next**, **Later** and **Done**. Each card
  shows:
  - a status chip: SCHEDULED, BOARDING, ON THE ROAD or COMPLETED;
  - time, as "Leaves in 25 min" or "Left 40 min ago";
  - route, first → last stop, and the van's plate;
  - **Open passenger list**.
- Empty state: "No trips assigned. Pull down to refresh, or ask the
  office if you expected one."

### 6.2 Trip screen
The Dispatcher's main working screen. Today it is one long scrolling
page, in the order of the work.

**Top bar:** the trip name, **SOS**, **Refresh**, and **More**, which
holds "Not a passenger trip" for a van moving with no passengers.

1. **Status panel:**
   - status chip, day and time;
   - van plate · operator name;
   - four counts: **Paid**, **Unpaid**, **At terminal** (pressed "I'm
     here to pay"), **Seats left**.
2. **Waiting to sync** banner, when marks are saved on the phone offline.
3. **Camera count against the list:**
   - two big numbers, *aboard (camera)* and *listed or explained*.
   - **More aboard than listed:** "2 more aboard than listed. Add each
     person to the list with where they get off, or give a reason.
     Depart waits until then." Each unexplained boarding is a row,
     "Boarded 10:42 AM, not on the list", with **Add to list** and
     **Reason**.
   - **No camera phone in the van:** show "Not counted", never 0.
   - A switch, "I am riding in the van as crew", so the Dispatcher is not
     counted as a passenger.
4. **Reservations and walk-ins** (before departure):
   - filter chips: **To collect**, **Paid**, **All**, each with a count;
   - a search box for "Booking code or name".
   - Each row shows:
     - name, booking code;
     - "To Digos · ₱150";
     - a status chip: HERE TO PAY (listed first), UNPAID, PAID,
       PAID · NOT SYNCED, or ABOARD;
     - buttons **Mark ₱150 paid** and **Cancel**.
   - **Mark as Paid?** confirms "Juan Dela Cruz · SG-7K2Q9M — ₱150.00 in
     cash, in your hand now."
   - Cancel asks for a reason: "The passenger asked. I hand back the
     ₱150 I took" / "The passenger asked me to cancel it" / "Nobody came
     for it."
   - After departure this becomes the locked **passenger list**.
5. **Home pickups:** each pickup shows the passenger's name, contact, map
   pin, note and landmark photo. Its status is one of NOT ACTIVATED,
   ACTIVATED, AT THE PIN, BOARDED or NO-SHOW, with buttons **Activate**,
   **Van is at the pin**, **Boarded** and **No-show**.
6. **Van rental** (on a special trip only):
   - the renter, pickup → destination, number of passengers;
   - fee, FEE PAID / FEE UNPAID, and **Collected ₱X in cash**;
   - the note "Start waits for the fee."
7. **Terminal fees:**
   - "Hand ₱567 to the Cashier": A2Z's 15 % of the fares, the ₱75
     terminal ticket, and the day's ₱50 parking;
   - "Give the operator ₱Y, in front of the Cashier";
   - the fare lines, "4 × ₱363 to Cotabato";
   - **Record the operator's dispute** on a line, if the operator
     disagrees with it.
8. **Driving flags** (e.g. speeding), with the note "For review by the
   Terminal Manager, not proof of misconduct" and a **Dispute** button.

**Fixed action bar at the bottom**, under the thumb:
- before departure: **Add walk-in** and **Depart**;
- after departure: **Arrived**.

**Confirm dialogs:**
- **Depart now?** Boarding closes and the list locks. Paid passengers
  count as aboard; unpaid ones become no-shows. It warns if the terminal
  fees aren't recorded yet.
- **Arrived?** "Tap this when the van is at its last stop and everyone is
  off."
- **Why is this person not on the list?** A reason box, e.g. "the
  operator's child, riding free to the next terminal".
- **The operator's dispute:** the operator's words.

### 6.3 Walk-in passenger
Laid out like a till, for a queue at the door.

- "Boarding at Ecoland" (always the first stop).
- **Getting off at:** one large button per destination, each showing its
  fixed fare (Digos ₱150, Kidapawan ₱340, Cotabato ₱363).
- **COLLECT ₱340**, in large type.
- Optional **receipt details:** name, mobile number, "Wants a receipt".
- A **Log** button, a running count ("3 logged"), and then **Next
  passenger** or **Done**.
- **Offline:** "Logged offline. Saved on this phone; it syncs and gets a
  real booking code once you are back online."
- A walk-in added to fix a camera-counted boarding is sent straight
  away, never saved offline.

---

## 7. States every screen needs

- **Loading, empty, error, offline.** Each says what happened and what
  to do next ("Check your connection, then pull down to try again").
- **Pull to refresh** on every list.
- **Long text:** terminal names, and Filipino names with two surnames.
- **Large system text** (200 %) and small phones (320 dp wide): nothing
  clipped, nothing fixed-height.
- **Sunlight:** high contrast. The Dispatcher's statuses must read at
  arm's length.

## 8. The current look (your starting point)

The app shares the A2Z web console's palette and fonts, so the office,
the Dispatcher and the passenger see one product. If you change the
palette, keep it in the same green family, or tell us why not.

- **Mood:** clean, flat, calm. A pale green page, white cards with a
  thin green edge, one deep-green action per screen. Red only for SOS, danger
  and the passenger's own route markers. Light theme only today.
- **Colours:**

  | Use | Hex |
  |---|---|
  | Page background | #F0FDF4 |
  | Cards | #FFFFFF, with a #86EFAC edge |
  | Main button | #047857, with white text (since 17 Nov; it was #10B981 with dark text) |
  | Green text and links | #047857 |
  | Main text | #1E3A2F |
  | Secondary text | #4B6358 |
  | Control outlines | #6B8579 |
  | Paid | #047857 on #DCFCE7 |
  | Needs attention | #8A5A00 on #FFF4DB |
  | Danger / SOS | #B3261E on #FDECEA |
  | Route markers | #C8151D |

- **Type:** **Plus Jakarta Sans** for headings (600–800) and **Inter**
  for everything else (400–700). Both are bundled in the app. Money uses
  tabular figures.
- **Sizes:**
  - full-width **52 px** main buttons;
  - **48 × 48 px** minimum tap targets;
  - 16 px side margin and a 4-point spacing scale;
  - corner radius 12 px (buttons, fields), 16 px (cards, dialogs), 20 px
    (bottom sheets), pill (chips);
  - **no shadows on cards**.
- **Signature pieces:**
  - the **journey strip**: a hollow red ring for boarding and a filled
    red square for alighting, joined by a rail;
  - the **status band**: a tinted panel with a headline and one sentence;
  - **status chips**: always a word, never colour alone.
- **Logo:** a light-green van carrying passengers inside the camera's
  detection boxes, with a GPS signal at the windscreen, over the
  "SabayGo" wordmark. The van alone is the small icon.
- **Accessibility goal:** WCAG 2.1 AA, with labelled navigation (never
  icon-only) and screen-reader names on every control.

## 9. Where we think it can improve

These are our own observations, not user research. Use them as starting
points.

- **The Dispatcher's trip screen is long.** Eight panels stack on one
  scrolling page. At the door, the list and the next action matter most;
  fees, flags and pickups matter at other moments. A clearer priority or
  progressive disclosure would help.
- **The reservation screen has many states.** The passenger should
  always see, first, *what to do next* and *by when* (the pay-before
  time), and the booking code.
- **The cash-only flow is new to passengers.** Reserve, then pay at the
  terminal by a deadline, or lose the seat: the design should teach this
  once, simply, then stay out of the way.
- **Search:** long terminal names, picking a day, and making the
  difference between "leaving soon" and "full" quick to read.
- **Home pickup** asks for a map pin. It needs to be easy for a relative
  who doesn't use maps much.
- **Consistency:** the passenger's bottom tab is labelled "Trips", and
  some older text still says "spaces" instead of "seats".

## 10. Please don't

- Add online payment, QR tickets, seat numbers or seat maps, ratings,
  refunds or rescheduling.
- Show a number the system doesn't have, such as an estimated count or a
  guessed arrival.
- Use red for anything but danger, SOS and route markers.
- Hide navigation labels or rely on icons alone.
- Use Google Maps branding. The maps are OpenStreetMap, and its credit
  line must stay visible.
