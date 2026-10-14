# SabayGo: Change Brief for Claude Code

Last updated: 2026-10-14. Matches the paper draft "SabayGo Paper Revision: Replacement Sections", revision 603.

**Changed since the previous version of this brief (revision 514).** The remittance and trip model was rebuilt around **one boarding point and payment before departure**. The earlier "settlement at the van's turn" model is **gone**.

1. **A2Z's 15 % applies only to the trip that boards at the terminal.** The fares collected on the **return leg** are the operator's own income for the van's upkeep. The system **neither records nor audits them**, and the edge phone **pauses at arrival** and resumes at the van's next assignment (Sections 2.1 and 4.2).
2. **Passengers board only at the terminal, before departure.** The **passenger list with destinations exists before the van leaves**: QR and gateway seats, plus walk-up (pasabay) cash passengers that the Dispatcher enters. Fares come from `Fare_Matrix` by drop-off terminal. A **side pickup is no longer a concept**: a roadside pickup after the van leaves the terminal zone is not flagged or priced (a disclosed limitation). The one exception is the **home pickup** of a disabled or elderly passenger (Section 2.6).
3. **Equation (2) is `Remittance owed = ρ × (V + D)`.** Estimated income (U), "amount at risk", and "if all estimates are confirmed" are **removed**, and so is the Terminal Manager's confirm/dismiss decision on estimates.
4. **The Dispatcher hands the 15 % to the Cashier, who records it.** **Hard block:** Start is blocked until the share is recorded, and a van whose last trip is unpaid is not assigned its next departure. Only the Terminal Manager can override, with a written reason. GPS auto-start is never blocked: a van that leaves unpaid is started by the system, flagged **'Left unpaid'**, and held out of the statement, and its unpaid share (`HeldShare`) still counts toward the van's balance (Section 2.1).
5. **The camera works in two modes.** Before departure it compares the number aboard with the number listed (a no-show is fine; more aboard than listed means the Dispatcher fixes the list or types a reason). After departure it only holds the van to **14 passengers**. It never prices a fare (Sections 2.4 and 5.2).
6. **Start and Depart are separate steps.** **Start** is the counter step (Cashier or Terminal Manager). **Depart** is tapped by the **Dispatcher** (or by the Cashier or Terminal Manager). If nobody taps, **GPS detects the departure**, and a trip nobody started is started automatically. A **'Not a passenger trip'** button lets the Dispatcher mark an errand (Section 4.2).
7. **NAHGM** now gives each capacity alert and driving flag a **general location** (the stretch between two stops, or the stop nearest to it). A declared home-pickup stop is **not** an unscheduled stop, and its wait is **subtracted** from the stretch time (Section 6.3).
8. **Disputes** cover only a **fare line** or a **driving flag**, and a fare-line dispute can be recorded only **until the payment is recorded** (Section 2.1).
9. **Tables are now 25 to 41.** New: **Table 40 `Non_Passenger_Moves`** and **Table 41 `Assisted_Pickups`**, plus a **`Messages`** table (chat with image attachments). Changed: Tables 29, 32, 33, 35, 39, `TripSchedules`, `Bookings`, `Notifications`. A start/void log table, if it is ever added, would now be **Table 42** (Section 7).
10. **Figure 9** (remittance flow) is redrawn in the paper. Still to redraw in Word: the **ERD (Figure 7)**, the **Figure 4** labels, and the **Scrum plan (Figures 1 and 2)** (Section 14).
11. **Acceptance tests** are rebuilt (Section 12), and the sample trip has **new numbers** (the home pickup, a no-show, two unlisted roadside passengers, remittance **₱217.50**).
12. **Updated from the group's latest answers (revision 603).**
    - **An independent trip is a special trip** (a passenger books the entire van and pays all its seats). It is created from an app request **or by the Terminal Manager or the Cashier for a walk-in**. The fee is agreed on the spot by pickup and destination, **payment comes first**, and the 15 % is handed to the Cashier before Start (Section 2.5). `Special_Trip_Requests` (Table 34) gains `CustomerName`, `CustomerContact`, `EnteredBy`, and `FeeNote`, and `PassengerID` can be NULL.
    - **Evidence retention is one fixed period** (`RetentionDays`, 30 assumed). `RetentionMode` and the "until settled" option are **removed**. **Only the Terminal Manager can view the blurred snapshots.** Passengers are told about the camera by a sign in each van and a notice on the booking screen (Sections 4.5 and 11).
    - **Chat images are limited to 10 MB**, and their retention period (30 days) is assumed.
    - **A2Z's data privacy contact is not yet named.** Keep the placeholder `[name and position to be supplied by A2Z]`.

**Still valid from earlier versions of this brief:** the in-van phones are a **pool kept in the office** and go out **only with a Dispatcher** (Section 5.5, `Edge_Devices` Table 37, `Device_Checkouts` Table 38); a van with no phone out runs **Unaudited** (`'No_Phone'`); the van and the Dispatcher are **assigned at the van's turn** by the Terminal Manager, or by the Cashier when the Terminal Manager is off duty (no duty roster); there is **one van per operator**; one **fixed retention period** covers snapshots and GPS logs, with the snapshot-hash safeguard (Section 4.5); trips are created from the timetable **days ahead**.

Paper title (current): *SabayGo: A YOLOv8-Audited Booking and QR Ticketing System with NAHGM Driving Behavior Monitoring for Public Utility Vans.*
Pilot site: the A2Z Transport Cooperative Van Terminal, Davao. Call it **A2Z** everywhere.
Team: Liam E. Go (project leader, documentation), Chris Cyrel Estil (developer), Carl Lawrence Fernandez (UI structure, documentation). Adviser: Ms. Charisse P. Barbosa.

---

## 0. How to use this file

1. This file describes **what changed** in the study's design since the original proposal. The original code base was built for the old design (booking and fleet management with Conductor, Operator, and Driver users and an Orange Pi/Raspberry Pi edge node), so parts of the repo will be out of date.
2. **Read the repo first.** Compare it with this brief and write a short **gap report** (what exists, what differs, what is missing) before you change anything.
3. **Ask before significant actions.** Present the plan as a short list of options with a recommendation, and wait for approval before: database migrations, deleting tables or screens, renaming roles, or changing public API shapes. Small, reversible edits can go ahead.
4. Every statement below is tagged:
   - **[DECIDED]** the group decided it.
   - **[PAPER]** it is written in the paper, so the code should match it.
   - **[ASSUMED]** the paper assumes it and A2Z has not confirmed it. Make it configurable, do not hard-code it.
   - **[ADVICE]** a recommendation that is not in the paper. Take it or leave it, but say which.
   - **[OPEN]** not decided. Do not invent an answer. Ask.
5. All numbers in the sample route, fares, speed limits, and thresholds are **illustrative placeholders**. A2Z's surveyed values will replace them. Store them as settings (Section 7.3), not constants.
6. Names in the paper may differ from names in the repo (for example `Conductors` is now `Dispatchers`). Map them, and report any mismatch.

---

## 1. What changed, in one table

| Area | Before | Now |
|---|---|---|
| Purpose | Booking and fleet management with a headcount check against the manifest | **Pre-departure remittance audit**: A2Z gets **15 % of the fares on the passenger list of each trip that boards at the terminal**, handed by the Dispatcher to the Cashier **before Start**. The camera checks the list at the door and holds the 14 cap on the road |
| Money | One statement settled at the van's turn, return leg included, with estimated income | **Payment before departure** on the passenger list only. `ρ × (V + D)`. **No estimated income. The return leg is outside the system** |
| Capacity | 14 seats, per route segment | **Strictly 14 passengers per van** (A2Z's operating rule), checked by booking and by the door camera after departure |
| Detection | Headcount at one moment, compared with the manifest | **Door events.** Before departure: aboard against listed (no-show allowed; more aboard than listed needs a fix or a reason). After departure: only the 14 cap. **No fare is priced from the camera** |
| NAHGM | Greedy segment matching and live passenger ETA | **Node-Aligned Haversine Geofenced Monitoring**: geometry only. Gives each capacity alert and driving flag a **general location** and places the van on stops and stretches. Passenger live position and ETA are no longer in scope |
| Driving | Not covered | Flags for **overspeed, slow stretch, unscheduled stop** (and an en-route stop record that is not flagged) |
| Evidence | None | **SHA-256 hash chain** over each trip's door events (evidence-based non-repudiation) |
| Roles | Passenger, Conductor, Operator, Driver | **Passenger, Dispatcher, Terminal Manager, Cashier**. The Conductor is now the **Dispatcher**. The Operator and the Driver are **not users** |
| Operator | A user | The **van owner, who always drives**. An A2Z member but an independent contractor. One roster record, **no account**, one van |
| Edge node | Orange Pi 5 or Raspberry Pi 4 with a USB webcam | A **pool of dedicated Realme 5G Android phones**, kept in the office and taken out by a Dispatcher, that supply the camera, GPS, processor, and mobile data |
| Boarding rule | Not defined | Fixed-route boarding **only at the starting terminal, before departure**. **One exception: the home pickup** of a disabled or elderly passenger, booked and paid before departure by a relative who rides along. A roadside pickup after the van leaves the terminal zone is **not flagged or priced** (disclosed limitation) |
| Trip start | Not defined | **Start** (counter step, blocked until the share is recorded) and **Depart** (Dispatcher taps it; GPS detects it if nobody does), automatic start for a trip nobody started, and a **'Not a passenger trip'** button |
| New features | | Special trips (rent the whole van), **home pickup (Book for Someone Else, chat with image proof)**, member roster with import and export, van status board, remittance statement and Cashier payment record, van and Dispatcher assignment at the van's turn, an Unaudited flag for trips without camera evidence, a retention setting, phone check-out and return, operator disputes |
| Writing terms | node, segment, chainage, geofence | **stop, stretch, distance from the starting terminal, stop zone** (the NAHGM expansion keeps "Node-Aligned" and "Geofenced") |

---

## 2. Business rules [PAPER unless tagged]

### 2.1 Money
- The operator collects fares and **remits 15 % of the fares on the passenger list of the trip about to leave, at the terminal, before the van leaves**. The system **does not hold or move money**. It records how each seat was paid, computes the remittance, and lets the Cashier record the payment.
- Rate is `ρ = 0.15`, a **dated, configurable** setting. A change applies only to later days (`TerminalSettings.EffectiveFrom`).
- Income is sorted into **two groups**:
  - **Verified (V)**: seats paid through the payment gateway or by QR ticket, **including home-pickup seats paid digitally**, and special-trip fees paid through the gateway.
  - **Declared (D)**: cash fares that the Dispatcher listed (and a cash special-trip fee that the Dispatcher logged).
- **Equation (2):**
  ```
  Remittance owed = ρ × (V + D)
  ```
- **A seat counts whether or not the passenger comes.** A no-show still counts because the seat was paid. **The camera's count adds nothing to the amount.**
- **Who pays whom [DECIDED]:** the **Dispatcher hands 15 % of the paid seats on the passenger list to the Cashier**, and the **Cashier records the payment** with its reference number and date and the **name of the Dispatcher who handed it over** (`Remittances.HandedOverBy`, `RecordedBy`).
- **List lock [DECIDED].** The list **locks to cancellations** when the Cashier records the payment **or** the van departs, whichever comes first (`TripSchedules.ListLockedAt`). Before the lock, a cancellation removes the seat and its share from the amount owed. After the lock there is **no cancellation, no refund, and no credit**. The list **can still grow before Start**: a seat added after the payment was recorded (for example a cash passenger) adds a **top-up of 15 % of its fare** (`Remittance_Lines.IsTopUp = TRUE`), which the Dispatcher hands over before Start is allowed. The list **cannot shrink** after the lock.
- **Hard block [DECIDED].**
  - **Start is blocked** (counter action by the Cashier or the Terminal Manager) until the share of the trip about to leave is recorded.
  - **Assignment is blocked** while the van's **last trip is unpaid**. "Unpaid" counts `RemittanceOwed + HeldShare − SettledAmount` on the van's statements, **leaving out disputed shares**.
  - Only the **Terminal Manager** can override, with a **written reason** (`PaymentOverrideBy`, `PaymentOverrideAt`, `PaymentOverrideNote`). The Cashier cannot. [ASSUMED] The same override covers both blocks.
  - [ADVICE] When a seat is added after the payment was recorded, set `PaymentStatus` back to `'Unpaid'` until the top-up is recorded, so that Start stays blocked.
- **GPS auto-start is never blocked [DECIDED].** The system cannot stop a van from physically leaving. A van that leaves the terminal with passengers aboard and without paying is **started by the system**, flagged **'Left unpaid'** (`PaymentStatus = 'Left_Unpaid'`), and **held out of the statement** until the Terminal Manager reviews it (Section 4.2). Its unpaid share is stored in **`Remittances.HeldShare`** and **still counts toward the van's balance**, so the van is **refused its next assignment** until it pays or the Terminal Manager overrides.
- **The way back is outside the system [DECIDED].** The fares collected on the return leg belong to the operator for the van's upkeep. They are **neither recorded nor audited**. The phone **pauses when the van arrives** and **resumes at the van's next assignment**. Do not build a return-leg trip, statement, or settlement.
- **Statement.** One row per van per service date (`UNIQUE (VanID, ServiceDate)`) that adds the van's trips of the day. `Status` is `'Open'` while a balance remains (including `HeldShare`), otherwise `'Settled'`. Payments add up in `SettledAmount` (the payment before each trip's Start, plus top-ups), `SettledAt` is the latest, and `SettlementRef` joins the references (VARCHAR(255)). The old "overdue" statement idea is **removed**.
- [ASSUMED] The operator **fronts** the 15 % before the day's fares are collected. Confirm with A2Z.
- **Held trips.** A trip the system started without confirmation (`StartReviewStatus = 'Pending'`) is **left out of the statement and of the fare lines** until the Terminal Manager reviews it. On review, create its fare lines and move its `HeldShare` into `RemittanceOwed` [ASSUMED mechanism, the paper does not spell it out]. A payment that was recorded for a trip that is later held stays in `SettledAmount`.
- **Unaudited trips [DECIDED].** A trip with no camera evidence (Section 4.4) is **not checked against the camera**: its door count is not compared with the list, and no overload alert is raised. The amount owed still comes from the list, and the statement **shows the trip as unaudited**.
- **Disputes [DECIDED].** The operator has no account, so a dispute is raised **at the counter while the operator checks the list and the amount before the share is paid**. The Dispatcher, the Cashier, or the Terminal Manager records it with the operator's own words (`Disputes`, Table 39).
  - **Scope:** a **fare line** or a **driving flag** only.
  - **Money:** the operator **pays the undisputed part**, and the **disputed share (15 % of the item's fare) waits**. It is shown separately from the amount due, and the block checks the **undisputed** amount only, so one contested fare line does not hold up Start. A driving flag withholds nothing (`AmountDisputed = 0.00`).
  - **Timing:** a **fare-line dispute can be recorded only until the Cashier records the payment**. A **driving-flag dispute can be recorded after the trip**, while its evidence is kept.
  - **Decision:** **only the Terminal Manager decides**, with a written reason, logged with who and when. **Upheld**: the item leaves the amount owed. **Rejected**: the share becomes due. **Adjusted**: the Terminal Manager sets the share that is due (`AdjustedAmount`). **Withdrawn**: the operator drops it and the share becomes due.
  - **Evidence:** snapshots and GPS logs of the trip are kept while a dispute is open (Section 4.5).
  - **Not covered:** a passenger's complaint or refund, and a contest of a fare line after the payment is recorded. The Terminal Manager may decide a dispute over their own earlier decision, because there is no third role (limitation in the paper).
  - **Example (sample trip, Section 12.1):** the operator contests the **cash seat to Sta. Cruz** (₱80, share ₱12.00). The operator pays **₱205.50** at once and the ₱12.00 waits. **Upheld**: the remittance owed is ₱205.50. **Rejected**: the ₱12.00 becomes due.
- **Worked example (sample trip, Section 12.1):** 14 listed seats, V = ₱1,370.00 (11 seats to Digos at ₱110 and 2 QR seats to Sta. Cruz at ₱80), D = ₱80.00 (one cash seat to Sta. Cruz). Remittance owed = 0.15 × 1,450.00 = **₱217.50**, handed over before Start. The unused seat still counts. The two unlisted roadside passengers add **nothing**. If the cash seat is added after the payment was recorded but before Start, only a **₱12.00 top-up** is owed.
- Gateway payments settle to the operator's payout account [ASSUMED]. Gateway example: GCash through PayMongo.
- [OPEN] A van that never departs again, an owner who stops operating, and a trip paid in advance that is later voided (the statement is overpaid, so a credit would be needed).

### 2.2 Fare lines
A fare line groups the paid seats of **one trip** that go to **the same drop-off terminal, at the same fare, in the same income group**. The origin is always the starting terminal. Fares come from `Fare_Matrix` (terminal-to-terminal, with `EffectiveFrom`), read by the **drop-off terminal** that the passenger or the Dispatcher entered. A special-trip rental fee is also a line (`RequestID`, `PassengerCount = 1`).

### 2.3 Capacity
- Aboard now = **door count minus the crew**. The **driver's seat is masked**, and the **Dispatcher adds themselves as crew once in the app** (`TripSchedules.CrewAboard`, logged, **not counted toward the 14**).
- When aboard rises **above 14**, raise a **capacity alert** with the time and the **general location** on the route. It goes to the **Terminal Manager, the Dispatcher, and the Cashier** [DECIDED].
- Booking also holds each van to 14 (row-level locking in MySQL).

### 2.4 Boarding rule and the camera
- **Fixed-route trip:** boarding is allowed **only at the starting terminal, before the van departs**, whether the passenger holds a QR ticket or walks up and pays cash to the Dispatcher. The **passenger list is complete before departure**: QR and gateway seats, the Dispatcher's cash walk-ups **with destinations**, and home-pickup seats.
- **Before departure,** the Dispatcher's screen compares **the number aboard (door count minus crew)** with **the number listed**, leaving out home-pickup seats that have not boarded yet.
  - **Fewer aboard than listed:** a **no-show**. Allowed, because the seat is paid. No action.
  - **More aboard than listed:** the Dispatcher must **fix the list** (the person, the destination, the fare, and the 15 % on it) **or type a reason** before tapping Depart. A van that **leaves anyway** raises **'Departed with more people aboard than listed'** to the Terminal Manager. **The camera's count alone sets no fare.**
- **After departure,** the camera counts **only to hold the van to 14**. A passenger picked up along the road after the van leaves the terminal zone is **neither flagged nor priced**. [OPEN] This is a disclosed limitation: an operator could load passengers just outside the zone, and the study does not audit them. Confirm that A2Z accepts it.
- **Special trips and home pickups booked and paid before departure** are not checked by this rule.

### 2.5 Special trips [DECIDED]
- A passenger **rents the whole van** and is picked up at a chosen location. Apart from the home pickup, it is the only trip type that allows pickup outside a terminal.
- **An independent trip is a special trip** [DECIDED]. A van that runs **outside the timetable** does so because a passenger **books the entire van and pays for all of its seats**. The system has no separate "independent van" path: such a trip is created as a special trip (`IsSpecial = TRUE`).
- **Two ways to create one:**
  - the passenger **requests it in the app** (date and time, pickup, destination, passenger count, **at most 14**), or
  - a **walk-in** passenger asks at the counter, where the **Terminal Manager or the Cashier enters the same details** (`PassengerID` NULL, `CustomerName`, `CustomerContact`, `EnteredBy`).
- The **Terminal Manager or the Cashier agrees the rental fee** with the passenger **according to the pickup location and the destination**. There is no fare table for it (`RentalFee`, with a `FeeNote` that records what the fee is based on). The same person **assigns a van and a Dispatcher**. [INTERPRETED] The group's answer was garbled: it was read as a fee agreed on the spot and not taken from a table. Confirm what the fee is actually based on (distance, destination, hours, or an agreed amount).
- **Payment comes first** [DECIDED]. The fee is paid **before the van leaves**, through the gateway, or in cash at the terminal, which the Dispatcher logs. As on every trip, the Dispatcher hands **15 % of the fee to the Cashier before Start**, under the same hard block (Sections 2.1 and 4.2). GPS auto-start is still never blocked.
- A **Dispatcher rides on it and an edge phone goes out with it**, as on a timetabled trip [DECIDED by the group; confirm with A2Z]. The trip is therefore audited like any other.
- A special trip **takes the van's turn**, but the **operator may decline one that is too far away**. The Terminal Manager or the Cashier then assigns another van [DECIDED, "quite flexible"]. [OPEN] Whether the declining van keeps its place in the queue.
- It has no fixed route, no stop zones, and no terminal-to-terminal fare. The camera still counts people and raises the capacity alert. GPS is still stored. Overspeed uses a **default limit** set by the Terminal Manager (`SpecialTripSpeedKmh`).
- The fee is the **whole income of the trip**: verified (V) if paid through the gateway, declared (D) if the Dispatcher logs cash. The 15 % covers it.
- [OPEN] The Cashier agrees the fee and also records the payments. This weakens the separation of duties (Section 3). Ask whether the Terminal Manager alone should agree fees.

### 2.6 Home pickup [DECIDED]
The only exception to "board at the terminal". It is for a **disabled or elderly passenger** who cannot come to the terminal.
- A **relative books** the seat in the app (**'Book for someone else'**): the passenger's name and contact number, and a **pin on the map with a short note**. The relative **also holds a seat and pays for both**, **comes to the terminal first, and rides along**, so the van is never sent alone to a house.
- **Payment is digital only.** Use the payment gateway first. When the gateway is not available, the relative sends a **screenshot of the payment in the trip chat** (Messages, Figure 19), and the **Dispatcher confirms it to the Terminal Manager** (`Assisted_Pickups.ProofMessageID`, `ProofConfirmedBy`, `ProofConfirmedAt`; notification 'Home Pickup Proof').
- The seat is on the passenger list like any other. It counts in V (paid digitally) and is **owed even if the passenger is not found**.
- **The pin is accepted automatically** within a maximum distance from the route (`HomePickupMaxRouteM`, a Terminal Manager setting). Store the distance in `Assisted_Pickups.RouteDistanceM`.
- **Activation:** the relative **scans the QR ticket** at the terminal, or the **Dispatcher enters it by hand** because the relative paid at the terminal in cash or digitally (`ActivationMode`, `ActivatedBy`, `ActivatedAt`).
- **On the trip:** the van goes to the pin and **waits up to 10 minutes** (`HomePickupWaitMin`). The Dispatcher can **end the stop early** by marking the passenger boarded or a no-show, and the early end is **logged with the Dispatcher** (`ClosedEarly`, `ClosedBy`). A home-pickup stop is **expected**: no flag, **not an unscheduled stop**, and its wait is **subtracted from the stretch time** (Section 6.3).
- **The chat keeps image attachments** for this proof only: up to **10 MB** each (`ChatImageMaxKb` = 10240 [DECIDED]), kept for a **retention period** (`ChatImageRetentionDays`, **30 days** [ASSUMED: the group gave only the size], `Messages.RetainUntil`), and a **line in the privacy section**, because a payment screenshot can show personal details.

---

## 3. Roles and permissions [DECIDED / PAPER]

Four roles only. Do **not** build screens, accounts, or tables for an Operator user or a Driver user.

| Capability | Passenger | Dispatcher | Terminal Manager | Cashier |
|---|:--:|:--:|:--:|:--:|
| Find route and schedule, reserve a seat, pay, get QR ticket, check in | ✔ | | | |
| **Book for someone else** (home pickup): beneficiary, map pin, own seat, digital payment, chat with payment proof | ✔ | | | |
| Request a special trip, pay the rental fee | ✔ | | | |
| Receive booking, delay, cancellation, boarding notifications | ✔ | | | |
| Scan QR tickets and **list walk-up cash passengers with their destinations** (works **offline**, also on the scheduled trip before Start, once the Dispatcher is assigned) | | ✔ | | |
| **Add themselves as crew** once in the app (logged, not counted toward the 14) | | ✔ | | |
| **Fix the list** (person, destination, fare, 15 %) or **type a reason** when more people are aboard than listed | | ✔ | | |
| **Hand the 15 % to the Cashier** before Start | | ✔ | | |
| **Tap Depart** (primary) | | ✔ | ✔ | ✔ |
| **'Not a passenger trip'**: press before leaving and pick a reason (logged in `Non_Passenger_Moves`) | | ✔ | | |
| Home pickup: **activate by hand**, **end the stop early**, **confirm a payment screenshot to the Terminal Manager** | | ✔ | | |
| Confirm the van's plate number against the van, at the door | | ✔ | | |
| Alert: **capacity alert** (15th person) | | ✔ | ✔ | ✔ |
| Alert: **Departed With More Than Listed** | | | ✔ | |
| Alert: **Left Unpaid** [ASSUMED recipients] | | | ✔ | ✔ |
| Alert: driving flags | | ✔ | ✔ | |
| Alert: **Unaudited Trip** (phone off, covered, silent, or not taken out) [DECIDED] | | ✔ | ✔ | ✔ |
| Alert: **Assignment by Cashier** (the Cashier assigned a van and a Dispatcher) | | | ✔ | |
| Alert: **Unconfirmed Trip Start**, **Trip Not Started**, **Home Pickup Proof** | | | ✔ | |
| **Assign a van and a Dispatcher** to the next departure at the van's turn (**refused while the van's last trip is unpaid**, Section 2.1) | | | ✔ | ✔ **only when the Terminal Manager is off duty**. The action always works, is stored in `AssignedBy`, and alerts the Terminal Manager [DECIDED; no duty roster] |
| **Start a trip** (confirm or change the **assigned** van). **Blocked until the share is recorded** | | | ✔ | ✔ |
| **Void a started trip or change its van** | | | **✔ only** | |
| Review trips the system started, trips that **left unpaid**, trips that departed with more aboard than listed, and trips that went Unaudited | | | ✔ | |
| Validate operator, dispatcher, and van records | | | ✔ | |
| **Add a phone to the pool** (`Edge_Devices`) | | | ✔ **only** [DECIDED] | |
| **Check a phone out** (after the setup check) to a Dispatcher and van, and **receive it back** (`Device_Checkouts`) | | | ✔ | ✔ |
| **Collect a phone from the office, mount it in the van's holder, and return it** | | ✔ | | |
| **Record an operator's dispute** (`Disputes`) | | ✔ | ✔ | ✔ |
| **Decide a dispute** (Upheld, Rejected, Adjusted) | | | **✔ only** | |
| **View the blurred snapshots** [DECIDED] | | | **✔ only** | |
| **Enter a walk-in special trip**, approve special trips, **agree the rental fee** (by pickup and destination), assign van and Dispatcher [DECIDED; the Cashier setting a fee is [OPEN]] | | | ✔ | ✔ |
| Set rate, fares, speed limits, **terminal zone radius and departure readings**, **home-pickup wait and maximum distance**, **chat image limit and retention**, **retention of snapshots and GPS logs**, other rules | | | ✔ | |
| Fleet screens: capacity alerts, boarding audit, driving flags | | | ✔ | |
| Van status board (on site, travelling, not on a trip, out of service) | | | ✔ | ✔ |
| Import and export member records | | | ✔ | ✔ |
| Show or print the van's statement (the fares of the trip about to leave, any top-up, and any unpaid share) | | | | ✔ |
| **Receive the 15 % from the Dispatcher and record the payment** | | | | ✔ |
| **Override the payment block** (Start, or the next assignment), with a written reason | | | **✔ only** [DECIDED] | |

**Separation of duties [PAPER]:** the person who records a payment (Cashier) does not decide what is owed (Terminal Manager), and the Cashier cannot erase a trip. **Exception [OPEN]:** the Cashier may agree the fee of a special trip, and the Cashier also records its 15 %. Ask whether the Terminal Manager alone should agree fees. The person who encodes an imported record is not the only one who approves it.

**One login per staff member [ASSUMED]:** `StartedBy`, `AssignedBy`, `ChangedBy`, `StartReviewedBy`, and `RecordedBy` name a person, so there must be **no shared Cashier or Terminal Manager account**.

**Operator [DECIDED]:** the van owner who also drives. Roster record only (name, license number and expiry, contact, optional email, payout reference). **One van per operator.** The operator **arranges in person with the Terminal Manager and the Cashier which trips the van takes**. No login, no app screens. A substitute driver and an owner of several vans are **not supported** (limitation in the paper).

**Dispatcher [PAPER]:** an A2Z staff member whom the Terminal Manager assigns to the van's **departure at its turn** (the Cashier does so when the Terminal Manager is off duty), and who **rides in the van**. The Dispatcher uses the mobile app on **their own phone**, which is **not** the edge phone. The Dispatcher also **collects the edge phone from the office, mounts it in the van's holder, keeps it for the day's trips, and returns it** (Section 5.5). A van that goes out **without a Dispatcher** has no phone, no GPS departure, no door count, and no overload alert, and its Start is manual.

---

## 4. Trip lifecycle, assignment, and start rule [DECIDED; the values are ASSUMED]

The group chose **rotation by turn** and a **hybrid start**: trips are created automatically from the timetable **days ahead** (passengers book seats on them), the **Terminal Manager assigns the van and a Dispatcher** to the next departure when the van's turn comes, the **Dispatcher builds the passenger list** and hands over the share, the **Cashier records it**, a **Cashier or Terminal Manager taps Start**, the **Dispatcher taps Depart**, and **GPS is the fallback** for both a missed Depart and a missed Start. There is **no "usual van"** in the timetable.

### 4.1 Status flow (`TripSchedules.Status`)
```
Scheduled ──Start──▶ Boarding ──Depart──▶ En Route ──arrive──▶ Completed
    │                    │
    └──── void (Terminal Manager only) ────▶ Cancelled
```
- **Scheduled**: created from the timetable. `AssignedVanID` and `DispatcherID` are **NULL until they are assigned at the van's turn**. Bookings attach to the trip from the day it is created.
- **Boarding**: the trip has been started (the share is recorded, or the Terminal Manager overrode, or the system started it).
- **En Route**: the van has departed.
- **Completed** [DECIDED]: the trip stays open after the van arrives until the **number aboard is 0 or the Dispatcher taps Arrived**. `CompletedAt` is set then, `Status` becomes `'Completed'`, and the phone **pauses**.
- **Cancelled**: voided by the Terminal Manager, or cancelled.

### 4.2 Rules
1. **Creation.** The server creates trips from the timetable (`Timetable_Templates`, Section 7.4) **ahead of time** (see `AdvanceBookingDays`). A van that runs **outside the timetable** gets a **special trip** (Section 2.5), created from a request in the app or entered at the counter by the Terminal Manager or the Cashier. The timetable stores route, time, and operating days. It does **not** store a van or a Dispatcher.
2. **Assignment at the van's turn [DECIDED].** When a van's turn comes, the **Terminal Manager assigns the van and a Dispatcher to the next departure**. The **Cashier can do this when the Terminal Manager is off duty**. Store `AssignedBy` and `AssignedAt`. When the Cashier assigns, send the Terminal Manager an **'Assignment by Cashier'** alert; the Terminal Manager can change the assignment. There is **no on-duty toggle and no duty roster**. Only **validated** vans and Dispatchers can be assigned. **Special trips [DECIDED]:** a special trip takes the van's turn, but the operator may decline one that is too far away, and the Terminal Manager or the Cashier then assigns another van. Payment comes first on a special trip: the fee is paid before the van leaves, and the same payment block applies. **Payment block [DECIDED]:** refuse the assignment while the van's **last trip is unpaid** (Section 2.1). Only the Terminal Manager can override, with a written note in `PaymentOverrideBy`, `PaymentOverrideAt`, and `PaymentOverrideNote`.
3. **Building the list before Start [DECIDED].** Once the Dispatcher is assigned, the Dispatcher **scans QR tickets and lists cash walk-up passengers with their destinations** on the scheduled trip, and **adds themselves once as crew**. The passenger list therefore **exists before the van leaves**. When the list is ready, the Dispatcher **hands 15 % of the paid seats to the Cashier**, who records the payment. A late Start never blocks boarding.
4. **Start window.** The **Start** action appears a set time before departure. Setting `StartOpensMin`, **assumed 30**.
5. **Manual Start [DECIDED].** The **Cashier or the Terminal Manager** confirms or changes the **assigned** van (from the validated vans) and taps **Start**. **Manual Start is blocked until (a) a van and a Dispatcher are assigned and (b) the share of the trip is recorded** (`PaymentStatus = 'Paid'`, or `'Overridden'` after a Terminal Manager override with a written reason). The system shows the van's plate number and operator, then **copies the operator's name, license number, and the van's plate number onto the trip**. An **expired license raises a warning** to the starter and the Terminal Manager. It does not block the start [ASSUMED]. If the van that is confirmed is **not the van that the sending phone is checked out to** (its open `Device_Checkouts` row), **warn the starter**. If **no phone is out with the van**, also warn (the trip will be Unaudited, Section 4.4). The Start screen shows the **amount due** and any **top-up**.
6. **Not on the roster.** A van or operator that is not on the roster, or not validated, **cannot be picked**. The Terminal Manager adds and validates the record first.
7. **Depart [DECIDED].** The trip moves to En Route when the **Dispatcher taps Depart** (primary), or when the **Cashier or the Terminal Manager** taps it. Store `DepartedAt` and `DepartureSource` (`'Dispatcher'`, `'Staff'`, or `'GPS'`). Before Depart, if the camera shows **more people aboard than listed**, the Dispatcher must **fix the list or type a reason** (Section 2.4). A van that departs anyway raises **'Departed With More Than Listed'** to the Terminal Manager.
8. **GPS departure fallback [DECIDED].** If nobody taps Depart, the phone's GPS detects the departure: **N consecutive readings outside the terminal zone while moving, with at least one boarding counted**. The terminal zone covers the **whole queue and loading area**. Its radius and N are Terminal Manager settings (`DepartZoneRadiusM`, `DepartReadings`) that are **set from a site survey**. [OPEN] Do not hard-code either value.
9. **Automatic start [DECIDED].** If nobody has started the trip by the time the van departs, the **system starts it**:
   - with the **assigned van**, `StartMode = 'Auto_Assigned'`; or, if no van was assigned, with the **van the sending phone is out with**, `StartMode = 'Auto_Detected'`;
   - `StartedBy` stays NULL, `StartReviewStatus = 'Pending'`, and the Terminal Manager gets an **'Unconfirmed Trip Start'** alert;
   - if the share was **not recorded**, set `PaymentStatus = 'Left_Unpaid'` and send a **'Left Unpaid'** alert, and store the share in `Remittances.HeldShare`;
   - the trip is **held out of the statement** until the Terminal Manager reviews it.
   There is **no grace-period timer** (`StartGraceMin` is removed). The operator named on an automatic start is only an assumption until the Terminal Manager reviews it.
10. **'Not a passenger trip' [DECIDED].** A van sometimes leaves for a reason that is not a passenger trip (for example an errand at the operator's home). **Before leaving, the Dispatcher presses 'Not a passenger trip' and picks a reason** (`'Errand'`, `'Fuel_Or_Repair'`, `'Other'` with a note). Log it in **`Non_Passenger_Moves` (Table 40)** with who and when. **Nothing is started and nothing is owed**, and the GPS fallback does not start a trip. **But** if the camera sees a **passenger aboard while the button is on**, the trip **starts automatically** as `'Auto_Detected'`, pending review, the Terminal Manager is alerted, and `AutoStartedScheduleID` is stored. The move ends (`EndedAt`) when the Dispatcher turns the button off or the van comes back into the terminal zone.
11. **Hold and review [DECIDED].** A trip with `StartReviewStatus = 'Pending'` is **left out of the statement**. When the Terminal Manager reviews it (confirms or changes the van), set `'Reviewed'`, `StartReviewedBy`, `StartReviewedAt`, create its fare lines, and move its `HeldShare` into `RemittanceOwed` (Section 2.1). The Terminal Manager also reviews trips that **left unpaid**, trips that **departed with more aboard than listed**, and trips that went Unaudited.
12. **No silent edits [DECIDED].** A started trip is **not edited quietly**. **Only the Terminal Manager** can void it or change its van. Each start, void, change, override, and 'Not a passenger trip' is stored with **who, when, and why** (the earlier van and operator are kept in `ChangeNote`). The **hash chain stays on door events only**. Do not add a start/void log table without asking (Section 4.6).
13. **The phone counts from assignment to arrival [DECIDED].** The edge phone does **not** start and stop with the Start button. It counts **from the van's assignment until the van arrives**, then **pauses**, and **resumes at the van's next assignment**. It is out with the van from the **setup check at check-out** until it is **returned**. Recent Android versions restrict an app from starting its camera and location service in the background, which is why the app stays in the foreground and does not follow the trip's start. Every event carries the sending phone's `DeviceID`. The server finds that phone's van from its **open `Device_Checkouts` row** (`ReturnedAt IS NULL`) and **matches the event to the trip the van is assigned to, by time**, whether or not the trip has been started.
14. **Events between trips [DECIDED].** A door event is given to the **trip the van is assigned to**, even before Start, so the boardings before Start are kept. A door event that arrives when the van has **no assigned trip** **waits in an unassigned list at the server, outside the ledger** (`Passenger_Events.ScheduleID` is NOT NULL, so it cannot be stored there yet), and the system raises **'Trip Not Started'**. When a trip is assigned or started, match the waiting events to it by time. The paper does not model the waiting list in the data dictionary (Section 7.4).

### 4.3 Columns this adds or changes in `TripSchedules` [PAPER, working note]
| Column | Type | Meaning |
|---|---|---|
| `AssignedVanID` | FK NULL | NULL until a van is assigned at its turn (or, on a special trip, until the Terminal Manager or the Cashier assigns one) |
| `DispatcherID` | FK NULL (renamed from `ConductorID`) | NULL until assigned. A trip cannot be started until one is assigned |
| `AssignedBy` | VARCHAR(32) FK NULL → TerminalStaff | Who assigned the van and the Dispatcher (Terminal Manager, or Cashier when the manager is off duty) |
| `AssignedAt` | DATETIME NULL | |
| `StartMode` | ENUM('Manual','Auto_Assigned','Auto_Detected') NULL | How the trip was started. `'Auto_Assigned'`: the system used the assigned van. `'Auto_Detected'`: the van whose phone detected the departure |
| `StartedBy` | VARCHAR(32) FK NULL → TerminalStaff | NULL when the system started it |
| `StartedAt` | DATETIME NULL | |
| `StartReviewStatus` | ENUM('Not_Required','Pending','Reviewed') NOT NULL DEFAULT 'Not_Required' | `'Pending'` for an automatic start. A Pending trip is left out of the statement |
| `StartReviewedBy` | VARCHAR(32) FK NULL → TerminalStaff | |
| `StartReviewedAt` | DATETIME NULL | |
| `AuditStatus` | ENUM('Audited','Unaudited') NOT NULL DEFAULT 'Audited' | `'Unaudited'` when the phone gave no camera evidence (Section 4.4) |
| `UnauditedAt` | DATETIME NULL | When the trip became unaudited |
| `UnauditedReason` | ENUM('No_Phone','Silent_At_Start','Lost_En_Route','Lens_Blocked') NULL | `'No_Phone'`: no phone was out with the van |
| `DepartedAt` | DATETIME NULL | |
| `DepartureSource` | ENUM('Dispatcher','Staff','GPS') NULL | Who tapped Depart (the Dispatcher, or the Cashier or the Terminal Manager), or `'GPS'` when nobody did. **Replaces** `'Confirmed'` and `'Detected'` |
| `CompletedAt` | DATETIME NULL | When the number aboard fell to 0 at the destination or the Dispatcher tapped Arrived |
| `ChangedBy` | VARCHAR(32) FK NULL → TerminalStaff | Terminal Manager who voided or changed the van |
| `ChangedAt` | DATETIME NULL | |
| `ChangeNote` | VARCHAR(255) NULL | Reason, plus the earlier van and operator. A void sets `Status = 'Cancelled'` |
| `PaymentOverrideBy` | VARCHAR(32) FK NULL → TerminalStaff | Terminal Manager who assigned a van that owed a balance, or allowed a Start before the share was recorded |
| `PaymentOverrideAt` | DATETIME NULL | |
| `PaymentOverrideNote` | VARCHAR(255) NULL | The written reason |
| `PaymentStatus` | ENUM('Unpaid','Paid','Left_Unpaid','Overridden') NOT NULL DEFAULT 'Unpaid' | `'Paid'` when the Cashier records the share, `'Overridden'` after an override, `'Left_Unpaid'` when the system started a trip whose share was not recorded |
| `ListLockedAt` | DATETIME NULL | When the Cashier recorded the payment or the van departed, whichever came first |
| `CrewAboard` | TINYINT NOT NULL DEFAULT 0 | `1` when the assigned Dispatcher has added themselves as crew (not counted toward the 14) |

### 4.4 Phone status and Unaudited trips [DECIDED]
- The phone sends a **status report (heartbeat)** that updates its `Edge_Devices` row (`LastHeartbeatAt`, `BatteryPct`, `BatteryTempC`, `CameraOk`, `GpsOk`). The server counts the phone as **silent** when no report arrives within `HeartbeatGapS`, **placeholder 120 s** [ASSUMED]. Keep it a setting. The phone **stores its reports while it is offline and sends them after it reconnects**.
- **At Start:** if **no phone is out with the van** (for example a van that goes out without a Dispatcher), or the phone is silent, or its camera or GPS is not working, **warn the person who starts the trip**, **start the trip anyway**, set `AuditStatus = 'Unaudited'` **immediately** (`UnauditedReason = 'No_Phone'`, `'Silent_At_Start'`, or `'Lens_Blocked'` when the camera is covered), and send an **'Unaudited Trip'** alert to the **Terminal Manager, the Cashier, and the Dispatcher** [DECIDED].
- **During the trip:** if the phone goes silent, send the alert **at once**, but make the Unaudited mark **final only if the reports the phone stores and sends after it reconnects do not show the camera and GPS working through the gap** (a gap in mobile data coverage is not a camera that is switched off). If those reports cover the gap, clear it. If they do not, mark the trip Unaudited **from the start of the gap** (`UnauditedAt`, `'Lost_En_Route'`). A **covered lens** is marked at once (`'Lens_Blocked'`). [ADVICE] Hold a provisional flag until the stored reports arrive or the trip ends.
- **Never block the service.**
- An Unaudited trip is **not checked against the camera**. The statement counts only its QR tickets and logged fares and shows the trip as unaudited (Section 2.1).

### 4.5 Evidence retention [DECIDED]
- **One fixed period for blurred snapshots and GPS logs**, in `TerminalSettings` (`RetentionDays`), set by the **Terminal Manager** and changeable by A2Z. The group chose a **fixed number of days**. The paper uses **30 days** [ASSUMED, taken from the group's answer, to be confirmed with A2Z]. There is **no `RetentionMode`** and no "until settled" option.
- **Only the Terminal Manager can view the blurred snapshots** [DECIDED]. Enforce it in the API as well as in the screens: the Cashier, the Dispatcher, and the Passenger never receive a snapshot URL.
- **Safeguard [DECIDED]:** never delete evidence tied to a **flag that is not yet reviewed** (a `Driving_Events` row with `ReviewStatus = 'Open'`, or a `Passenger_Events` row with `ResolutionStatus = 'Pending'`) or to an **open dispute** (`Disputes.Status = 'Open'` on that trip's `ScheduleID`). Keep the evidence until the dispute is decided.
- **Deleting a snapshot keeps the chain verifiable.** When a snapshot is deleted: delete the file, set `SnapshotURL` to NULL, set `SnapshotDeletedAt`, and **keep `SnapshotHash`**. `EventHash` is computed over the event's fields **including `SnapshotHash`**, so recomputing it after deletion still matches.
- [DECIDED] For GPS logs, delete only the raw `Nahgm_tracking_logs` rows. `Driving_Events` rows stay.
- [ADVICE] Run it as a scheduled job and log what it deletes.
- **Chat images** (the payment proof of a home pickup) follow their **own** limits: up to **10 MB** each (`ChatImageMaxKb` = 10240 [DECIDED]) and a retention period (`ChatImageRetentionDays`, **30 days** [ASSUMED: the group gave only the size], `Messages.RetainUntil`). The privacy notice says so, because a screenshot can show personal details.
- **Notice [DECIDED]:** passengers are told about the camera by a **sign in each van** and a **notice on the booking screen**.
- **Privacy review [OPEN]:** A2Z's data privacy contact reviews the retention period and the notice against the **Data Privacy Act of 2012** before the pilot. The contact is **not yet named**. Keep the placeholder `[name and position to be supplied by A2Z]`.


### 4.6 Open points for the trip start and payment [OPEN]
- Confirm with A2Z: the **30-minute** start window, that the **Cashier** has time to start trips at the counter in peak hours, and that the **Cashier may assign** the van and Dispatcher when the Terminal Manager is off duty.
- **Off duty [DECIDED].** No duty roster and no toggle. The Cashier's assign action always works, `AssignedBy` shows who did it, and the Terminal Manager is alerted ('Assignment by Cashier').
- **Terminal zone radius and N (`DepartZoneRadiusM`, `DepartReadings`)** come from a **site survey** of the queue and loading area. Do not invent values.
- **Does one Terminal Manager override cover both blocks** (Start, and the next assignment)? The paper assumes yes. Confirm.
- **Home pickup:** confirm the 10-minute wait and the maximum distance from the route (`HomePickupMaxRouteM`) with A2Z, and confirm the chat image size limit (10 MB) and retention period (30 days, assumed), and the privacy line.
- **Operator fronting the 15 %:** confirm that the operator pays the share before the day's fares are collected.
- Should each start, void, change, override, and 'Not a passenger trip' join a **hash chain**? That needs a small log table (it would be **Table 42**, and the ERD, Figure 7, would be redrawn). Right now the paper says only that they are stored with who, when, and why. Do not add the table without asking.
- **Special trips [DECIDED, with open points]:** an independent trip is a special trip (Section 2.5). Confirm what the **fee is based on**, whether the **Cashier** may agree it, and whether a van that **declines** a far special trip keeps its queue place.
- **When does a phone that has not come back count as missing**, and who is alerted?
- **What happens** when a van does not depart again, when an owner stops operating, or when a trip that was paid in advance is voided and leaves its statement overpaid (Section 2.1).

---

## 5. Edge node: the in-van Realme 5G phone

### 5.1 Decided [DECIDED / PAPER]
- A **dedicated** phone from the terminal's pool (Section 5.5), **separate from the Dispatcher's phone** (which stays with the Dispatcher for scanning tickets).
- Kept on **vehicle power** with its battery as a backup. Mounted **above the door in the van's fixed holder** by the Dispatcher.
- Uses its **own camera and GNSS receiver**. Runs **YOLOv8 nano** on the device, with **ByteTrack**. The model is exported for Android (for example TFLite or NCNN).
- **No frame rate is claimed** until the phone is benchmarked. Do not write a fps figure into code comments, docs, or UI.
- Sends **only event details and a blurred snapshot** to the server. **No video is uploaded.**
- Stores events and holds them **until the connection returns**.
- The app runs in the **foreground**, with location access **always allowed** and battery optimization **turned off** [ASSUMED].
- The app **pauses when the van arrives and resumes at the van's next assignment** (Section 4.2, rule 13). It does not start and stop with the Start button, and the return leg is not counted.
- GPS readings come **every 1 to 2 seconds** from the phone's GNSS receiver. This replaces the older 15-second phone ping (a van at 55 km/h covers about 229 m in 15 s, more than the 200 m width of a 100 m stop zone). An **alarm fires if the readings stop**.
- Speed is the speed reported by the phone's GNSS receiver. The study applies no hardware GPS-spoofing protection beyond plausibility checks.
- The exact Realme model, Android version, RAM, and processor are **not known yet**. [OPEN] Do not hard-code device assumptions. Keep a bracketed placeholder.

### 5.2 Detection logic [PAPER]
1. A **virtual line across the doorway**. A tracked person crossing **inward = boarding**, **outward = alighting**.
2. **Crew:** a **mask over the driver's seat** so the driver is not counted. The **Dispatcher adds themselves as crew once in the app** (`CrewAboard`, logged), so that the Dispatcher's own steps through the door are not counted as a boarding and the Dispatcher is **not counted toward the 14**.
3. Each event carries a **time stamp** and the **number aboard after the event** (door count minus crew).
4. **Before departure** (`PreDeparture = TRUE`): the server compares the **number aboard** with the **number listed**. A boarding at the terminal is **listed** if a QR scan or a Dispatcher entry was made **within `MatchWindowS` (2 minutes) before or after it and was not already used** for another boarding (`MatchStatus` `'Matched_QR'` or `'Matched_Log'`). Otherwise it is **`'Unlisted'`** with `ResolutionStatus = 'Pending'` until the Dispatcher **fixes the list** (`'Listed'`) or **types a reason** (`'Explained'`, with `ResolutionNote`).
5. **After departure** (`PreDeparture = FALSE`): the camera counts **only to hold the van to 14**. A boarding is stored with the hash and the blurred snapshot, but it is **not flagged and not priced** (`MatchStatus = 'Unlisted'`, `ResolutionStatus = 'Not_Needed'`) [ASSUMED mapping]. Raise the **capacity alert** when aboard rises above 14.
6. A **cabin snapshot at each stop** corrects counting drift: if the running count differs from the snapshot count, flag the difference for review.
7. `TrackID` is only a tracker id within the trip. It is **not a passenger identity**. No face or identity matching. An **alighting is not matched to a person** (`MatchStatus` is NULL).
8. Tracking and counting depend on lighting, door and camera placement, and crowding. Treat camera findings as **estimates for review**. Field studies report undercounting at peak boarding, which is why the camera is a **check before departure** and prices nothing.

### 5.3 Implementation advice [ADVICE, not in the paper]
Say in the gap report whether you follow these.
- Build the edge app as a **native Android (Kotlin) app, separate from the Flutter app**. A Flutter plugin chain can add latency and background-service problems to a continuous camera and GPS loop. Check this on the real phone.
- Run **YOLOv8n at a reduced input size (320 to 416 px)** and a low detection rate, and raise the rate near stops and door activity. Decide the numbers **after benchmarking** on the real phone.
- **Android 14 and later:** a camera or location foreground service must declare its type (`FOREGROUND_SERVICE_CAMERA`, `FOREGROUND_SERVICE_LOCATION`) and **cannot be started from the background**. The app must be launched visibly and kept in the foreground. Verify on the real phone.
- **Realme background killing:** power-saving modes, Smart Performance, sleep standby optimization, and app freezing can kill the app. Provide a **setup checklist** (allow auto-launch, allow background and foreground activity, remove from battery optimization) and rely on a **heartbeat** to notice when it died. There is no known developer-side fix.
- **Offline queue** with ordered upload and retry.
- **Clock sync to server time.** The 2-minute matching window compares the phone's timestamps with the Dispatcher's phone and the server, so a clock offset breaks matching.
- **Heartbeat every 30 to 60 s** carrying battery temperature, battery level, charging state, camera status, GPS status, and detection rate. Use it for the "readings stopped" alarm.
- A **blocked-lens check** (for example, a frame that stays dark or unchanged).
- **`Edge_Devices` (Table 37)** is the phone pool and **`Device_Checkouts` (Table 38)** says which van a phone is in [DECIDED]. The heartbeat above fills `Edge_Devices`, and every event upload carries the `DeviceID`; the server finds the van through the open check-out. Apply `HeartbeatGapS` only while `Status = 'Checked_Out'`: a phone in the office is not "silent". [ADVICE] MySQL 8.0 has no partial unique index. The paper has the application enforce **one open check-out per phone and per van**. A functional unique index also works from MySQL 8.0.13, for example `CREATE UNIQUE INDEX uq_open_phone ON Device_Checkouts ((CASE WHEN ReturnedAt IS NULL THEN DeviceID END));` (closed rows give NULL and are ignored), and the same for `VanID`. Check it on the real server version.
- **Hash chain:** the paper has the **server** compute `EventHash`. A stronger design signs each event on the phone with a hardware-backed Keystore key. This is an **[OPEN] decision** in the paper's to-confirm list.
- **Heat:** the pilot test should log battery temperature over a full trip. Cooling hardware is **undecided**. Do not assume a cooler is fitted.
- **Data use:** an unverified estimate is under 10 MB per day if only events and snapshots are sent. Measure it.

### 5.4 Decided and still to confirm
- **Decided [DECIDED]:** if the phone is switched off, covered, silent, or **not taken out**, the system **warns the starter, marks the trip Unaudited, alerts the Terminal Manager, the Cashier, and the Dispatcher, and the service continues** (Section 4.4).
- **Decided [DECIDED]:** the Cashier or the Terminal Manager checks the phone at **check-out** (setup check, Section 5.5), and the Terminal Manager adds a replacement phone to the pool.
- How many phones A2Z needs (vans that can be out at the same time, plus a spare), and when a phone that has not come back counts as missing. [OPEN]
- How long a phone may be silent before it counts as a problem (`HeartbeatGapS`, placeholder 120 s). [OPEN]
- Whether A2Z allows a **camera in the cabin**. [OPEN]

### 5.5 Phone custody [DECIDED]
- The phones are a **pool kept in the office of the Cashier and the Terminal Manager**. The Terminal Manager adds phones (`Edge_Devices`, `Status = 'In_Office'`).
- A phone goes out **only with a Dispatcher**, for a van in the terminal's queue **or** on a **special trip** (Section 2.5).
- **Check-out:** the Cashier or the Terminal Manager runs a **setup check** (the app is open, the camera and GPS are reporting, the charger works) and records the check-out in `Device_Checkouts` (phone, van, Dispatcher, who, when). `Edge_Devices.Status` becomes `'Checked_Out'`.
- The Dispatcher **mounts the phone in the van's fixed holder**, confirms on the phone's screen that the **door line** is in place, keeps the phone for the day's trips, and **returns it** to the office. The Cashier or the Terminal Manager records the return and the phone's condition (`ReturnedBy`, `ReturnedAt`, `ReturnNote`), and `Status` goes back to `'In_Office'`.
- A van that goes out **without a Dispatcher has no phone**. Its trip is **Unaudited** with `'No_Phone'`, its Start is **manual**, and it has **no GPS departure, no door count, and no overload alert**.
- Because a phone changes vans, the **door line and the seat mask must be re-aligned at every mounting**. The paper's mitigation is a **fixed holder of the same kind in every van** and the setup check. [ADVICE] Store the door line and the seat mask per van and load them when the check-out names the van. Benchmark on the real phone.
- **Phone count:** the number of vans that can be out at the same time, plus a spare. [ASSUMED, to confirm]

---

## 6. Pipelines: checking the list, geotagging, driving flags

### 6.1 Checking door events against the passenger list [PAPER]
- A boarding at the terminal is **listed** if a **QR scan or Dispatcher entry** was made **within two minutes before or after** it and **has not already been used** for another boarding (`MatchWindowS`, sample value 120 s). Otherwise it is **unlisted**.
- A **pasabay** is a passenger who walks up and rides **without a booking or QR ticket**. At the terminal the Dispatcher **lists** the person with a destination, pays go into D, and the 15 % goes in the share handed to the Cashier.
- A passenger who holds a ticket or has paid but does not come is a **no-show**, and the **seat still counts**.
- **Before departure:** compare the number aboard (door count minus crew) with the number listed, **leaving out home-pickup seats that have not boarded**. More aboard than listed: the Dispatcher **fixes the list** (adds the person's destination and fare and the 15 % on it) **or types a reason** before Depart. A van that leaves anyway is flagged to the Terminal Manager as having departed with more aboard than listed. Fewer aboard: a no-show, and nothing changes.
- **Fare of every listed passenger:** from `Fare_Matrix`, by the **drop-off terminal** that the passenger or the Dispatcher entered. The same table prices a passenger whom the Dispatcher adds after the camera showed more aboard than listed. **Never price a fare from the camera's count.**
- **After departure:** no matching and no pricing. The camera only holds the van to 14.
- **Alightings are not matched** to people. The old ticket-count rule and its first-in-first-out matching are **removed**.
- No face or identity matching.
- `MatchStatus` values: `'Matched_QR'`, `'Matched_Log'`, `'Unlisted'` (NULL for an alighting). `ResolutionStatus` values: `'Not_Needed'`, `'Pending'`, `'Listed'`, `'Explained'`.

### 6.2 The four phases [PAPER, Figure 4]
1. **Edge detection** on the phone: detect, track, record each boarding and alighting with a time stamp.
2. **Geotagging** by NAHGM: each event and each alert gets its place on the route.
3. **Checking** on the server: apply the matching, boarding, and capacity rules to the QR scans and Dispatcher entries of the trip, and show the Dispatcher the number aboard against the number listed.
4. **Logging and alerting** on the server: write each event to `Passenger_Events` with a hash that links it to the previous event of the trip, raise a **capacity alert** or a **departed-with-more-than-listed alert** with the blurred snapshot. The remittance comes from the **passenger list**, not from the camera.

`EventHash` = SHA-256 of the event's fields (**including `SnapshotHash`**) **and the previous event's hash for the same trip**, so a later change to any event is detectable, even after a snapshot is deleted under the retention rule (Section 4.5). [OPEN] the first event's "previous hash" is not defined in the paper. [ADVICE] use a fixed genesis value derived from `ScheduleID`.

### 6.3 NAHGM geotagging [PAPER]
- Route model: ordered **stops**, each with coordinates, a **stop zone** (circle, **100 m in the sample**), and distance from the starting terminal. These stops are the nodes that give NAHGM its name, and **none of them except the starting terminal is a boarding point**. Each **stretch** has a length, speed limit, and expected time.
- Expected time of a stretch = (stretch length − stop-zone radius at each end) ÷ expected average speed (**55 km/h** in the sample).
- Haversine distance: `a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)`, `c = 2·atan2(√a, √(1−a))`, `d = R·c`, with `R ≈ 6,371 km`. **The van has reached a stop when `d ≤ stop-zone radius`.**
- **Snap each GPS reading to the nearest point on the route line** to get distance from the starting terminal. GPS readings come **every 1 to 2 seconds**.
- For each **capacity alert, driving flag, and departure**, interpolate the van's position between the two GPS readings on either side of the event time, snap it to the route, and store **latitude, longitude, distance from start, stretch, nearest stop and distance to it**. Show the location **generally**: the stretch between two named stops, or the stop nearest to it (for example "between Toril and Sta. Cruz"), so the Terminal Manager can see where overloading, overspeeding, and long stops repeat.
- **Declared home-pickup stop [DECIDED].** The stop at a declared home pickup is **expected**, not an unscheduled stop. **Subtract the wait** (`Assisted_Pickups.ArrivedAt` to `LeftAt`) from the **stretch time** before the slow-stretch ratio is computed. In the sample, 17.3 min measured less 3.5 min of waiting gives 13.8 min.
- **Departure detection:** uses the terminal zone (`DepartZoneRadiusM`) and N consecutive readings (`DepartReadings`), Section 4.2 rule 8.
- NAHGM is **geometry, not machine learning**.

### 6.4 Driving flags [PAPER]
All thresholds are **configurable settings of A2Z**. Sample values:

| Flag | Rule (sample thresholds) |
|---|---|
| `Overspeed` | Speed stays **above the stretch's limit for 10 s or more** |
| `Slow_Stretch` | Time from leaving one stop zone to entering the next, **less any declared home-pickup wait**, is **more than 25 % above expected** (ratio above 1.25) |
| `Unscheduled_Stop` | **Standstill (2 km/h or less) for more than 120 s** while **more than 100 m from every stop** and **not waiting at a declared home pickup within the set waiting time** |
| `En_Route_Stop` | A stop of **120 s or less** outside a stop zone. It is **recorded, not flagged** |

- Smoking is **not detected**. Unscheduled stops are its measurable proxy. Every flag is an **indicator for review, not proof of misconduct**.
- The capacity alert and the departed-with-more-than-listed alert are **not** driving flags. They are notifications.
- Each flag ties to a person only through the **operator name, license number, and van plate number copied onto the trip** at the start.
- `ReviewStatus`: `'Open'`, `'Reviewed'`, `'Dismissed'`.

---

## 7. Data model

Backend: **MySQL 8.0, InnoDB**. Reconcile with the schema in the repo and report differences.

### 7.1 Removed or merged
- **`Driver` table: removed.** Its license number and expiry moved into `Operators`.
- `Operators` is **no longer a web user.** It is a roster record with **no login**.
- `Vans.AssignedDriverID` / `TripSchedules.AssignedDriverID`: removed. The operator is found through `Vans.OperatorID`.
- `Yolov8_audit_logs.DriverID`: removed (the check belongs to the trip, not a person).
- `Conductors` → **`Dispatchers`** (`ConductorID` → `DispatcherID`).
- **Removed with the old money model [DECIDED]:** `Remittances.EstimatedIncome` and `Remittances.AmountAtRisk`; `Passenger_Events.SidePickup`, `DestStopID`, and `EstimatedFare`; the `'Estimated'` value of `Remittance_Lines.IncomeGroup`; the `'Estimated_Fare'` subject of `Disputes` (and its `EventID`); the `'Mismatch'` and `'Unrecorded'` values of `MatchStatus`; the `TerminalSettings` key `StartGraceMin`. Do not carry any of them forward. Do not add a return-leg trip, an "overdue" flag, or a settlement-at-turn job.

### 7.2 New tables (paper Tables 25 to 41)
| # | Table | Purpose and key fields |
|---|---|---|
| 25 | `Operators` | `OperatorID` PK, `FullName`, `ContactNumber` UNIQUE, `Email` NULL (optional), `PayoutRef` NULL, `LicenseNumber` UNIQUE, `LicenseExpiry`, `MembershipStatus` ('Active','Suspended','Inactive'), `ValidationStatus` ('Pending','Validated','Rejected','Suspended'), `ValidatedBy`, `ValidatedAt`, `ImportBatchID`. **No login.** |
| 26 | `TerminalStaff` | `StaffID`, `FullName`, `Email` (login), `StaffRole` ENUM('Manager','Cashier'), `IsActive` |
| 27 | `Fare_Matrix` | `FareID`, `OriginTerminalID`, `DestTerminalID`, `Fare`, `EffectiveFrom`. UNIQUE (origin, destination, EffectiveFrom) |
| 28 | `Route_Stretches` | `StretchID`, `RouteCode`, `StretchNo`, `FromTerminalID`, `ToTerminalID`, `FromDistanceM`, `LengthM`, `SpeedLimitKmh`, `StopZoneRadiusM` (default 100), `ExpectedTimeS` |
| 29 | `Passenger_Events` | One row per door event: `EventID`, `ScheduleID`, **`DeviceID` FK NOT NULL → `Edge_Devices` (the phone that sent the event)**, `EventType` ('BOARD','ALIGHT'), `EventAt` DATETIME(6), `Latitude`, `Longitude`, `DistanceFromStartM`, `StretchNo`, `NearestStopID`, `NearestStopDistM`, **`PreDeparture` BOOLEAN NOT NULL** (TRUE before the trip departed, when the door count is compared with the list; FALSE after, when the camera only holds the van to 14), `OccupancyAfter` (not counting the driver or the Dispatcher), `TrackID`, `MatchStatus` ('Matched_QR','Matched_Log','Unlisted'; **NULL for an alighting**), `MatchedBookingID`, `MatchedLogEntryID` (also the entry the Dispatcher added when fixing the list), `SnapshotURL` (NULL once the snapshot is deleted), **`SnapshotHash` CHAR(64) NULL**, **`SnapshotDeletedAt` DATETIME NULL**, `EventHash` CHAR(64), **`ResolutionStatus` ENUM('Not_Needed','Pending','Listed','Explained') NOT NULL DEFAULT 'Not_Needed'** (`'Pending'` is an unlisted boarding before departure that the Dispatcher has not yet fixed; `'Listed'` means the Dispatcher added the person to the list; `'Explained'` means the Dispatcher typed a reason), `ResolvedBy` FK → `Dispatchers`, `ResolvedAt`, `ResolutionNote` VARCHAR(255) NULL. **No `SidePickup`, `DestStopID`, or `EstimatedFare`** |
| 30 | `Driving_Events` | `DrivingEventID`, `ScheduleID`, `FlagType`, `StartAt`, `EndAt`, `DistanceFromStartM`, `StretchNo`, `MaxSpeedKmh`, `LimitKmh`, `TimeRatio`, `NearestStopDistM`, `DurationS`, `ReviewStatus` |
| 31 | `Nahgm_tracking_logs` | GPS readings: `LogID` BIGINT AUTO_INCREMENT, `ScheduleID`, `RecordedAt` DATETIME(3), `Latitude`, `Longitude`, `SpeedKmh` (from the phone's GNSS), `DistanceFromStartM`, `StretchNo`, `NearestStopDistM` |
| 32 | `Remittances` | Statement per van per service date, open until its balance is paid (`SettledAmount` adds up the payments, `SettledAt` is the latest, `SettlementRef` VARCHAR(255) joins the references): `RemittanceID`, `OperatorID`, `VanID` (UNIQUE with `ServiceDate`), `ServiceDate`, `VerifiedIncome` (V), `DeclaredIncome` (D), `RatePct`, `RemittanceOwed` (`ρ × (V + D)`), **`HeldShare` DECIMAL(10,2) NOT NULL DEFAULT 0.00** (share due on trips the system started and the Terminal Manager has not reviewed; left out of the fare lines and of `RemittanceOwed`, but counted toward the van's balance for the payment block), `Status` ('Open','Settled'), `SettledAmount`, `SettledAt`, `SettlementRef`, `RecordedBy` (Cashier), **`HandedOverBy` FK → `Dispatchers`** (the Dispatcher who handed over the latest payment). **No `EstimatedIncome` and no `AmountAtRisk`** |
| 33 | `TerminalSettings` | Key-value rules with `EffectiveFrom`: `SettingKey`, `EffectiveFrom` (PK together), `SettingValue`, `UpdatedBy`, `UpdatedAt`. Keys are listed in Section 7.3 |
| 34 | `Special_Trip_Requests` | `RequestID`, **`PassengerID` FK NULL (NULL for a walk-in)**, **`CustomerName` VARCHAR(100) NULL, `CustomerContact` VARCHAR(20) NULL** (walk-in), **`EnteredBy` FK NULL → TerminalStaff** (the Terminal Manager or Cashier who entered a counter request), `PickupAt`, pickup and destination address and coordinates, `PassengerCount` (≤ 14), `RentalFee` (agreed by the Terminal Manager or the Cashier according to pickup and destination), **`FeeNote` VARCHAR(255) NULL** (what the fee is based on), `PaymentStatus` (the fee is paid before the van leaves), `PaymentReference` (NULL when paid in cash), `Status` ('Requested','Approved','Rejected','Completed','Cancelled'), `ScheduleID` (trip created on approval, `IsSpecial = TRUE`), `ReviewedBy` (the Terminal Manager or the Cashier), `ReviewedAt` |
| 35 | `Remittance_Lines` | Fare lines behind a statement: `LineID`, `RemittanceID`, `ScheduleID`, `OriginTerminalID` (the starting terminal; NULL on a special trip), `DestTerminalID` (NULL on a special trip), `RequestID` (when the line is a rental fee), `IncomeGroup` ('Verified','Declared'), `FarePerPassenger`, `PassengerCount` (includes a seat whose passenger did not come), `GrossFare`, `ShareAmount`, **`IsTopUp` BOOLEAN NOT NULL DEFAULT FALSE** (TRUE for a line added after the Cashier recorded the payment) |
| 36 | `Data_Transfers` | Import and export log: `TransferID`, `Direction`, `RecordType` ('Operators','Vans','Dispatchers'), `FileName`, `FileFormat` ('CSV','XLSX','PDF'), `ExportPurpose` ('Backup','LTFRB Check','Other'), `RowsInFile`, `RowsAccepted`, `RowsRejected`, `ErrorFileURL`, `PerformedBy`, `PerformedAt` |
| 37 | `Edge_Devices` | The terminal's phone pool, with each phone's status and latest report: `DeviceID` PK, `DeviceModel` NOT NULL, `AndroidVersion`, `AppVersion`, `Status` ENUM('In_Office','Checked_Out','Retired') NOT NULL DEFAULT 'In_Office', `RegisteredBy` FK → TerminalStaff (Terminal Manager, who added the phone), `RegisteredAt`, `LastHeartbeatAt`, `BatteryPct`, `BatteryTempC` DECIMAL(4,1), `CameraOk`, `GpsOk`. **No `VanID` and no `IsActive`**: a retired phone has `Status = 'Retired'` and keeps its row |
| 38 | `Device_Checkouts` | Each time a phone leaves the office and comes back: `CheckoutID` PK, `DeviceID` FK NOT NULL, `VanID` FK NOT NULL, `DispatcherID` FK NOT NULL, `CheckedOutBy` FK → TerminalStaff NOT NULL (Cashier or Terminal Manager), `CheckedOutAt` NOT NULL, `ReturnedBy` FK → TerminalStaff NULL, `ReturnedAt` NULL, `ReturnNote` VARCHAR(255) NULL. Open = `ReturnedAt IS NULL`. One open check-out per phone, enforced by the application (Section 5.3) |
| 39 | `Disputes` | An operator's contest of an item: `DisputeID` PK, `RemittanceID` FK NOT NULL, `ScheduleID` FK NOT NULL, `Subject` ENUM('Fare_Line','Driving_Flag') NOT NULL, `LineID` FK NULL → Remittance_Lines, `DrivingEventID` FK NULL → Driving_Events (exactly one is filled to match `Subject`), `OperatorStatement` VARCHAR(500) NOT NULL, `AmountDisputed` DECIMAL(10,2) NOT NULL DEFAULT 0.00 (the share that waits, 15 % of the line; 0.00 for a driving flag), `RaisedByRole` ENUM('Dispatcher','Cashier','Manager') NOT NULL, `RaisedByID` VARCHAR(32) NOT NULL (in `Dispatchers` or `TerminalStaff` according to the role, so no foreign key), `RaisedAt` NOT NULL, `Status` ENUM('Open','Resolved','Withdrawn') NOT NULL DEFAULT 'Open', `Outcome` ENUM('Upheld','Rejected','Adjusted') NULL, `AdjustedAmount` DECIMAL(10,2) NULL (the share due when the outcome is 'Adjusted'), `DecidedBy` FK NULL → TerminalStaff, `DecidedAt` NULL, `DecisionNote` VARCHAR(255) NULL |
| 40 | `Non_Passenger_Moves` | A departure that the Dispatcher marked 'Not a passenger trip': `MoveID` PK, `VanID` FK NOT NULL, `DeviceID` FK NOT NULL → `Edge_Devices`, `DispatcherID` FK NOT NULL, `ScheduleID` FK NULL (the trip the van was assigned to, if any), `Reason` ENUM('Errand','Fuel_Or_Repair','Other') NOT NULL, `ReasonNote` VARCHAR(255) NULL, `StartedAt` NOT NULL, `EndedAt` NULL, `AutoStartedScheduleID` FK NULL → `TripSchedules` (set when the camera saw a passenger aboard during the move and the system started the trip, `StartMode 'Auto_Detected'`) |
| 41 | `Assisted_Pickups` | A home pickup of a disabled or elderly passenger: `PickupID` PK, `BookingID` FK NOT NULL (the passenger's seat), `RelativeBookingID` FK NOT NULL (the relative's seat), `ScheduleID` FK NOT NULL, `PickupLat`, `PickupLng`, `PickupNote` VARCHAR(255) NULL, `RouteDistanceM` INT NOT NULL (checked against `HomePickupMaxRouteM`), `BeneficiaryName`, `BeneficiaryContact`, `Status` ENUM('Requested','Activated','Arrived','Boarded','No_Show','Cancelled') NOT NULL DEFAULT 'Requested', `ActivationMode` ENUM('QR_Scan','Dispatcher_Entry') NULL, `ActivatedBy` FK NULL → `Dispatchers`, `ActivatedAt`, `ProofMessageID` FK NULL → `Messages`, `ProofConfirmedBy` FK NULL → `Dispatchers`, `ProofConfirmedAt`, `ArrivedAt`, `LeftAt` (the wait between them is taken out of the stretch time), `ClosedEarly` BOOLEAN NOT NULL DEFAULT FALSE, `ClosedBy` FK NULL → `Dispatchers` |

### 7.3 Edits to existing tables [PAPER, working note]
- **Bookings:** `TripID` → `ScheduleID` (FK to `TripSchedules`; the old ERD named a table that does not exist). Describe `BookingID` as a UUID. Add `OriginTerminalID`, `DestTerminalID` (FK), `PaymentReference` VARCHAR(64) NULL, `PaymentStatus` ENUM('Unpaid','Paid','Refunded'), **`BookedForOther` BOOLEAN NOT NULL DEFAULT FALSE**, **`IsHomePickupSeat` BOOLEAN NOT NULL DEFAULT FALSE** (the details are in `Assisted_Pickups`, Table 41), and **`CancelledAt` DATETIME NULL**, which can be set **only until the passenger list is locked** (before the Cashier records the payment or the van departs).
- **TripSchedules:**
  - add `DriverName` VARCHAR(255) NULL, `DriverLicenseNo` VARCHAR(15) NULL, `VanPlateNumber` VARCHAR(8) NULL (copies taken **when the trip is started**);
  - add `RouteCode`, `Status` ENUM('Scheduled','Boarding','En Route','Completed','Cancelled'), `IsSpecial` BOOLEAN;
  - allow NULL in `AssignedVanID` until a van is assigned at its turn (or, on a special trip, until the Terminal Manager or the Cashier assigns one);
  - rename `ConductorID` → `DispatcherID`, NULL until assigned; add `AssignedBy` FK NULL → TerminalStaff and `AssignedAt` DATETIME NULL (they record who assigned the **van and** the Dispatcher; these replace the old `DispatcherAssignedBy` and `DispatcherAssignedAt`);
  - remove `StandardFare` or keep it as a display value only (every fare is priced from `Fare_Matrix`);
  - add the **start, review, audit, departure, payment-override, `PaymentStatus`, `ListLockedAt`, and `CrewAboard` columns** in Section 4.3.
- **Vans:** add `OperatorID` FK NOT NULL **UNIQUE** (one van per operator); replace the `RegisteredRoute` ENUM with `RouteCode` VARCHAR(30); allow NULL in the four photograph URLs (so an imported van can be saved first).
- **Dispatchers and Vans:** add `ValidationStatus` ENUM('Pending','Validated','Rejected','Suspended') NOT NULL DEFAULT 'Pending', `ValidatedBy` FK NULL → TerminalStaff, `ValidatedAt` NULL, `ImportBatchID` FK NULL → `Data_Transfers`.
- **LogBookEntries:** add `ScheduleID` FK, `DestStopID` FK (the drop-off terminal that prices the seat), `FareAmount` DECIMAL(10,2), `LoggedBy` FK → Dispatchers.
- **Yolov8_audit_logs:** remove `DriverID`. Keep as the **cabin-snapshot drift check**. Fix the stray "2" in `NOT NULL2`. Align its columns with Figure 21.
- **Notifications:** replace `PassengerID` with `RecipientType` ENUM('Passenger','Dispatcher','Manager','Cashier') and `RecipientID` VARCHAR(32). Add types `'Capacity Alert'`, `'Departed With More Than Listed'`, `'Driving Flag'`, `'Special Trip Request'`, `'Unconfirmed Trip Start'`, `'Unaudited Trip'`, `'Trip Not Started'`, `'Assignment by Cashier'`, `'Left Unpaid'`, `'Payment Block Override'`, `'Home Pickup Proof'`, `'Dispute Raised'`. (`'Unrecorded Boarding'` and `'Side Pickup'` are **removed**.)
- **Messages (new table, not numbered in the dictionary):** sender, recipient, `ScheduleID`, body, `SentAt`, **`AttachmentURL` VARCHAR(255) NULL, `AttachmentType` ENUM('Image') NULL, `AttachmentSizeKb` INT NULL, `RetainUntil` DATE NULL**. The payment proof of a home pickup is an image sent in the chat (Figure 19), so the chat is kept, with an image size limit, a retention period, and a line in the privacy section.
- **Remittances:** add `HeldShare` and `HandedOverBy`, and **remove `EstimatedIncome` and `AmountAtRisk`** (Table 32). Payments from several trips and top-ups add up in `SettledAmount`, and their references are joined in `SettlementRef` (VARCHAR(255)).
- **TerminalSettings keys:** `'RemittanceRate'` (0.15), `'SeatCapacity'` (14), `'MatchWindowS'` (120), `'OverspeedSeconds'` (10), `'StopSeconds'` (120), `'SlowTolerance'` (0.25), `'ExpectedSpeedKmh'` (55), `'AdvanceBookingDays'`, `'HoldReleaseS'`, `'SpecialTripSpeedKmh'`, **`'StartOpensMin'`** (30), **`'HeartbeatGapS'`** (120, placeholder), **`'DepartZoneRadiusM'`** (site survey), **`'DepartReadings'`** (N, site survey), **`'HomePickupWaitMin'`** (10), **`'HomePickupMaxRouteM'`** (to be set), **`'ChatImageMaxKb'`** (10240, the group's 10 MB), **`'ChatImageRetentionDays'`** (30, assumed), **`'RetentionDays'`** (30, assumed; one fixed period for blurred snapshots and GPS logs). **There is no `RetentionMode`.** Sample values are illustrative. **`'StartGraceMin'` is removed.**

### 7.4 Proposed, not yet in the data dictionary [OPEN]
- **`Timetable_Templates`**: `RouteCode`, `DepartureTime`, `OperatingDays`, `IsActive`. **No `UsualVanID` or `UsualDispatcherID`**: the van and the Dispatcher are assigned at the van's turn, not stored in the timetable. Needed for "trips are created from the timetable". The prototype's Timetable screen (22) has no table today.
- **`SosAlerts`**, or drop the Emergencies screen. SOS alerts are a **supporting function and are not evaluated**. (`Messages` is no longer optional: the home-pickup proof is sent in the chat.)
- A **start/void log table** (would be **Table 42**). Not added. See Section 4.6.
- A server-side **unassigned events** list for door events that match no assigned trip (Section 4.2, rule 14). The paper holds them outside the ledger and does not model them in the data dictionary.
- Dispatchers' sign-in: by phone number, or add an `Email` field. The existing table has no email.

---

## 8. Roster, import, export, and van status board [PAPER]

- The binder becomes a **member roster** with three lists: **operators, vans, dispatchers**. Uses: replaces retyping, gives A2Z a digital copy, shows which vans and operators belong to A2Z.
- A van can be assigned to a trip **only when its record is validated**.
- **Import (Terminal Manager or Cashier):** download a **CSV or Excel template**, copy the binder into it, upload.
  - Covers operators (name, contact number, email if any, license number, license expiry) and vans (plate number, CPC case number and number, model, color, seat capacity, registered route, operator).
  - The system **checks every row before saving**: required fields filled, plate, license, and CPC formats valid, no duplicate of an existing record, and **no operator named on more than one van** (one van per operator).
  - It shows a **preview of passing and failing rows with the reason for each failure**, and **saves only after the user confirms**. Rejected rows can be **downloaded, corrected, and uploaded again**.
  - Imported records are marked with their import batch and stay **Pending until the Terminal Manager validates them**.
  - The **four van photographs are not part of the import**. They are uploaded afterward, and the van **cannot be validated until they are present**.
  - The system does **not read binder pages automatically**.
- **Export (Terminal Manager or Cashier):** any list as **CSV or PDF**. Purposes: backup, and an LTFRB cross-check list (plate number, CPC case number and number, operator, validation status and date). **No connection to LTFRB's records.**
- **Every import and export is logged** in `Data_Transfers` (file, row counts, user, time).
- **Van status board** (Terminal Manager and Cashier): each van is **on site** (trip scheduled or boarding at a terminal), **travelling** (trip en route, also showing Dispatcher, operator, route, number aboard, last GPS position), **not on a trip** (no trip today), or **out of service** (maintenance or inactive). It uses trip status and GPS already stored, so it needs no extra data entry. For the Cashier it shows which vans are out and which vans still owe the share of their last trip.

---

## 9. Screens

Prototype figure numbers (7 to 27) and the table they read from. Mobile: **Flutter** (Passenger and Dispatcher). Terminal Manager and Cashier use **web screens** (the paper does not name a web framework).

| Screen (figure) | Needs |
|---|---|
| Authentication (7) | Passengers and TerminalStaff email via Firebase Authentication. Dispatcher sign-in method [OPEN] |
| Available Routes (8), Booking Confirmation (9), Gateway and E-Ticket (10, 11), Active Trips and History (12), Profile (14) | `TripSchedules`, `Fare_Matrix`, `Bookings`, `Vans`, `Route_Stretches` |
| **Book for Someone Else and Home Pickup (new, beside Booking Confirmation, 9)** | Passenger. Beneficiary name and contact number, a **map pin with a note**, the relative's own seat, payment by gateway or by a screenshot in the chat. `Bookings` (`BookedForOther`, `IsHomePickupSeat`), `Assisted_Pickups` (Table 41), `Messages` for the proof. Refuse a pin beyond `HomePickupMaxRouteM` |
| Dispatcher Dashboard (13) | **Passenger list with each destination and fare**, **number aboard against number listed**, **crew toggle**, **Depart** button, **'Not a passenger trip'** button, home-pickup requests (activate, end the stop early, confirm proof), the operator's name and license number, the van's plate number. Works **before Start**. **No** van picking, **no** void or change-van buttons. Reads `Bookings.Status`, `LogBookEntries`, `Passenger_Events` (`OccupancyAfter`, `PreDeparture`, `ResolutionStatus`), `TripSchedules` (`CrewAboard`, `DepartedAt`, `DepartureSource`, `PaymentStatus`), `Non_Passenger_Moves`, `Assisted_Pickups`. Hands the 15 % to the Cashier |
| Operations Map (15) | `Nahgm_tracking_logs`, `Passenger_Events.OccupancyAfter`. The 15-second map refresh is a **display setting**, separate from the 1 to 2 s GPS readings |
| Trip Monitoring (16) | Status, Dispatcher, operator, booked, aboard, no-show, camera check, **who started the trip and how**, `AuditStatus`, `PaymentStatus`, and the phone's last report (`Edge_Devices`) |
| **Start Trip (new)** | Terminal Manager and Cashier. Shows the van and Dispatcher **assigned at the van's turn**. The Terminal Manager (or the Cashier when the manager is off duty) **assigns the van and the Dispatcher** (`AssignedVanID`, `DispatcherID`, `AssignedBy`, `AssignedAt`). Confirm or change the van from validated vans. **Start is blocked until the van and Dispatcher are assigned and the share is recorded** (`PaymentStatus`). Shows the **amount due and any top-up**. Assignment is **refused while the van's last trip is unpaid**, and the Terminal Manager has an **Override** that needs a written reason. Warnings: expired license, **no phone out with the van**, phone silent, confirmed van differs from the van the phone is checked out to. **Void and Change Van buttons for the Terminal Manager only.** Writes `StartMode`, `StartedBy`, `StartedAt`, and Depart (`DepartureSource 'Staff'`) |
| **Review Automatic Starts (new)** | Terminal Manager. Trips with `StartReviewStatus = 'Pending'`, trips that **left unpaid** (`HeldShare`), trips that **departed with more aboard than listed**, and trips that are Unaudited. Confirm or change the van, then mark Reviewed (this releases the trip's fare lines to the statement) |
| Special Trips (17), Timetable (22) | `Special_Trip_Requests`, `TripSchedules.IsSpecial`, `Timetable_Templates` (route, time, days, in-use toggle only). New **Request a Special Trip** screen for the Passenger. On the Special Trips screen the **Terminal Manager or the Cashier enters a walk-in request** (name, contact, pickup, destination, passenger count), **agrees the fee** with a basis note, and **assigns a van and a Dispatcher**. Both can review requests |
| Remittance (replaces Fares and Cash, 20) | Cashier. `Remittances` and `Remittance_Lines`: **verified and declared income, remittance owed, held share, and payment status**, with the fare lines of each statement by trip, drop-off terminal, and fare. The Dispatcher hands the share over and the **Cashier records the payment here** (with the Dispatcher's name), shows a **top-up** when a seat is added before Start, can **record a dispute on a line** (only until the payment is recorded), and sees the **disputed share** separately. **No estimated income and no amount at risk** |
| Boarding Audit (replaces Passenger Count Checks, 21) | `Passenger_Events`: **unlisted boardings before departure** with time, snapshot (**blurred snapshots are visible to the Terminal Manager only**), hash check, and the Dispatcher's fix or reason, and **capacity alerts with their general location**. The Terminal Manager reviews departures with more aboard than listed and **decides each dispute**. **No estimate decisions** |
| Vans and Crew (23) → **Member Records** | `Vans`, `Operators`, `Dispatchers`, validation fields, `ImportBatchID`. Import and export buttons log to `Data_Transfers` |
| **Van Status Board (new)** | Terminal Manager and Cashier. For the Cashier it shows which vans are out and which vans still owe the share of their last trip |
| **Phones (new)** | Cashier and Terminal Manager. List the pool (`Edge_Devices`: status, battery, last report), **check a phone out** to a Dispatcher and van after the setup check, and **record its return** and condition (`Device_Checkouts`). The Terminal Manager also **adds a phone to the pool** |
| **Disputes (new)** | `Disputes`. The Cashier, the Dispatcher, and the Terminal Manager **record** a dispute (a fare line or a driving flag, the operator's statement, the share withheld). Only the Terminal Manager **decides** (Upheld, Rejected, Adjusted) with a note. Where the Dispatcher records it (mobile app or web) is [OPEN] |
| Rules and Settings (24) | `TerminalSettings`: booking window, seats sold in advance, cancellation deadline, hold release, reschedules, refund policy, **start window, terminal zone radius and departure readings, home-pickup wait and distance from the route, silent-phone gap, chat image limit and retention, retention of snapshots and GPS logs (one fixed number of days)**. Terminal Manager only |
| Messages (19) | **Kept.** Chat threads **with image attachments** (home-pickup payment proof): size limit, retention period, privacy line. `Messages` table |
| Emergencies (18) | Supporting only. Keep or drop [OPEN] |

UI wording: show the operator **only as a name and license number, with the van's plate number**, on the trip. Never as a user. Say **Dispatcher**, never Conductor.

---

## 10. Stack [PAPER, Table 4]

| Layer | Choice |
|---|---|
| Mobile app | Flutter 3.x, Dart (Passenger and Dispatcher screens) |
| Backend | FastAPI (Python): bookings, check-in, seat locking, door-event intake, matching, remittance computation |
| Database | MySQL 8.0 (InnoDB), row-level locking to hold each van to 14 |
| Edge | Android app on a Realme 5G phone. YOLOv8 nano + ByteTrack, model exported for Android (TFLite or NCNN) |
| Server-side Python | Place events on the route, compute driving flags |
| Maps | Google Maps SDK/API (stops, van position, event locations, check-in coordinates) |
| Messaging and auth | Firebase: FCM push alerts to passengers, Dispatchers, and the Terminal Manager. Authentication for sign-in |
| Payments | Third-party gateway (for example GCash through PayMongo). The system records the result and does not process payments itself |
| Source control | GitHub |

Minimum hardware in the paper: Android device 4 GB RAM, 64 GB storage, Android 10 or later; iOS 15 or later; office laptop i5 10th gen or Ryzen 5, 8 GB RAM. The old **Orange Pi / Raspberry Pi + USB webcam** row is replaced by the **Realme 5G phone** row.

---

## 11. Privacy and non-goals [PAPER]

- **No video leaves the van.** Only event details and a blurred snapshot.
- **No individual passenger identification**, no face matching.
- Non-goals: processing or holding money; handling cash, banking, or A2Z's accounting; connecting to LTFRB records; reading binder pages automatically; smoking detection; hardware-level GPS-spoofing protection; passenger live position and ETA; routing or door-to-door pickup on fixed-route trips, **except the home pickup of a disabled or elderly passenger**; **pricing or flagging a roadside pickup after the van leaves the terminal zone**; **recording or auditing the fares collected on the return leg**.
- **LTFRB franchise capacity** and **en-route loading rules** remain A2Z's responsibility to confirm. 14 passengers is A2Z's rule.
- **Retention:** blurred snapshots and GPS logs are kept for one **fixed number of days** (30, assumed; Section 4.5), and **only the Terminal Manager can view the blurred snapshots**. A deleted snapshot keeps its hash. Evidence tied to a flag that is not yet reviewed or to an open dispute is never deleted. **Chat images** (payment proof of a home pickup) are limited to **10 MB** and have their own retention period (30 days, assumed), and the privacy notice says so, because a screenshot can show personal details. **Notice [DECIDED]:** passengers are told about the camera by a **sign in each van** and a **notice on the booking screen**. A2Z's **data privacy contact** reviews the retention period and the notice before the pilot; the contact is **not yet named**, so keep the placeholder `[name and position to be supplied by A2Z]`.
- The hash chain makes a later change **detectable**. It is only as reliable as the camera's detection and the integrity of the edge node. The controls detect and deter collusion among trip personnel. They cannot fully prevent it. **A roadside pickup just outside the terminal zone is not audited.**

---

## 12. Acceptance tests

### 12.1 The paper's sample trip

The paper's numbers come from a simulated trip (Ecoland Terminal → Digos City Terminal, departure 05:30:00, four stops, 100 m stop zones, expected speed 55 km/h), computed by the group's sample-dataset script (`sabaygo_sample_dataset.py`, version 2, sent with this brief). All values are **illustrative**. Use them as a regression test for the list check, remittance, and flag logic.

**Passenger list before departure (14 seats):** twelve QR seats, one **home-pickup seat paid online**, and one **cash seat** that the Dispatcher entered. **One QR passenger did not come** (a no-show). After the van left the terminal, **two people who were not on the list boarded by the road**. The simulated driver also made one overspeed burst and one unscheduled stop. The Dispatcher rides as crew and is not counted.

**Route model**

| Stop | Lat | Lon | Distance from start (m) | Next stretch (m) | Limit (km/h) | Expected (min) |
|---|---|---|---|---|---|---|
| Ecoland Terminal | 7.0540 | 125.6060 | 0 | 12,967 | 60 | 13.9 |
| Toril | 7.0130 | 125.4960 | 12,967 | 21,751 | 80 | 23.5 |
| Sta. Cruz | 6.8370 | 125.4100 | 34,718 | 11,306 | 60 | 12.1 |
| Digos City Terminal | 6.7500 | 125.3570 | 46,025 | | | |

**Door events**

| Event | Time | Distance (m) | Aboard after | Expected result |
|---|---|---|---|---|
| E01 to E11 (11 boardings) | 05:28:00 | 0 | 11 | 11 QR scans, `'Matched_QR'`. One listed QR seat is unused: a **no-show**, still counted |
| E12 | 05:28:20 | 0 | 12 | Cash entry logged 15 s earlier, `'Matched_Log'` (declared). **12 aboard against 13 listed at the door, so no action** |
| H01 | 05:40:26 | 9,400 | 13 | **Declared home pickup.** The relative has been aboard since the terminal. The van waited **210 s** at the pin. No flag |
| E13 | 05:51:24 | 16,999 | 14 | Not listed, boarded **after departure**: `PreDeparture = FALSE`, **not flagged, not priced** |
| E14 | 05:51:31 | 17,001 | **15** | Not listed, not priced. **Capacity alert fires** at 05:51:31, general location **"between Toril and Sta. Cruz"**, to the Terminal Manager, the Dispatcher, and the Cashier |
| A01 to A03 (3 alightings) | 06:12:07 | 34,718 | 12 | 3 listed seats to Sta. Cruz |
| A04 to A15 (12 alightings) | 06:31:27 | 46,024 | 0 | 10 listed seats to Digos and the 2 unlisted passengers. **Alightings are not matched to people** |

**Remittance (ρ = 0.15), recorded by the Cashier before Start**

| Group | Fare line (drop-off terminal) | Seats | Gross ₱ | Share ₱ |
|---|---|---|---|---|
| Verified (V) | Digos at ₱110 (QR and online, one seat unused) | 11 | 1,210.00 | 181.50 |
| Verified (V) | Sta. Cruz at ₱80, QR | 2 | 160.00 | 24.00 |
| Declared (D) | Sta. Cruz at ₱80, Dispatcher's cash entry | 1 | 80.00 | 12.00 |
| | **Remittance owed** | 14 | 1,450.00 | **217.50** |

V = ₱1,370.00, D = ₱80.00, and `0.15 × (1,370.00 + 80.00) = ₱217.50`. The script prints the online home-pickup seat as its own line (1 seat, ₱110.00, ₱16.50); the paper merges it with the QR seats to Digos (10 + 1 = 11 seats, ₱1,210.00, ₱181.50) because they share the drop-off terminal, the fare, and the income group. Both give ₱217.50. The two unlisted roadside passengers add **nothing**. If the cash seat is entered **after** the Cashier records the payment but before Start, only a **₱12.00 top-up** is owed.

**Driving flags and stops**

| Flag | Time | Distance (m) | Evidence | Duration |
|---|---|---|---|---|
| Overspeed | 05:37:48 to 05:38:28 | 7,043 | Max 88.0 km/h against 60 | 40 s |
| Home pickup stop (expected, **not flagged**) | 05:40:06 to 05:43:36 | 9,400 | At the declared pin, wait within 10 min | 210 s |
| En-route stop (**not flagged**) | 05:51:12 to 05:51:46 | 17,002 | 4,034 m from the nearest stop, 120 s or less | 34 s |
| Unscheduled stop | 05:56:12 to 06:00:16 | 21,798 | 8,830 m from the nearest stop, no declared pickup | 244 s |

**Stretch time check (flag above 1.25 × expected; the home-pickup wait is subtracted)**

| Stretch | Length (m) | Actual (min) | Expected (min) | Ratio | Result |
|---|---|---|---|---|---|
| Ecoland to Toril | 12,967 | 13.8 (17.3 measured less 3.5 waiting) | 13.9 | 0.99 | Normal |
| Toril to Sta. Cruz | 21,751 | 23.7 | 23.5 | 1.01 | Normal |
| Sta. Cruz to Digos | 11,306 | 17.6 | 12.1 | 1.45 | **Slow** |

Notes the test must respect: the Toril to Sta. Cruz stretch passes the time check even though it holds 244 s of unscheduled stopping and 34 s of en-route stopping, because the simulated driver cruised at 70 km/h (within the 80 km/h limit) to recover time. That is why the **stop flags are needed alongside the stretch-time check**. The 210 s home-pickup stop must **not** become an unscheduled-stop flag, and its wait must be **taken out** of the stretch time.

### 12.2 Acceptance tests for payment, start, camera, home pickup, and retention rules

These are not in the paper's sample trip. They follow Sections 2 and 4. Use the sample route and the ₱ figures above where a number is needed.

**Payment and Start**

| # | Situation | Expected result |
|---|---|---|
| T1 | The Terminal Manager assigns a van and a Dispatcher at the van's turn. The Dispatcher builds the list and hands over ₱217.50. The Cashier records it with the Dispatcher's name and taps Start | `PaymentStatus = 'Paid'`, `ListLockedAt` set, `RecordedBy` and `HandedOverBy` stored. `StartMode = 'Manual'`, `StartedBy` = the Cashier, `StartReviewStatus = 'Not_Required'`, operator name, license number, and plate copied onto the trip |
| T2 | The Dispatcher scans QR tickets and lists cash walk-ups **before** Start, and Start is tapped 6 minutes later | Scans and entries already belong to the trip. Nothing is lost |
| T3 | The Cashier taps Start **before** the share is recorded | **Blocked.** The Terminal Manager overrides with a written reason: Start allowed, `PaymentStatus = 'Overridden'`, `PaymentOverrideBy`, `PaymentOverrideAt`, and `PaymentOverrideNote` stored. The Cashier **cannot** override |
| T4 | Manual Start tapped with **no Dispatcher** assigned | **Blocked** |
| T5 | A van whose **last trip is unpaid** reaches its turn | **Assignment refused.** After the payment is recorded, or after a Terminal Manager override with a note, it is allowed. The Cashier assigning while the Terminal Manager is off duty is **refused** as well |
| T6 | A cancellation (a) before the Cashier records the payment, (b) after | (a) The seat and its share leave the amount owed. (b) **Refused**. No refund and no credit |
| T7 | After the payment is recorded, the Dispatcher adds the cash seat (₱80) before Start | **₱12.00 top-up** line (`IsTopUp = TRUE`). Start stays blocked until the top-up is recorded |
| T8 | A listed, paid QR passenger does not come | **No change** to the amount: still ₱217.50 |
| T9 | The operator contests the **cash seat to Sta. Cruz** before the payment is recorded | `Disputes` row (`'Fare_Line'`, `AmountDisputed = 12.00`). The operator pays **₱205.50**, and the block checks the undisputed amount, so Start is allowed. (a) **Upheld**: owed ₱205.50. (b) **Rejected**: the ₱12.00 becomes due. (c) **Adjusted**: the share due is `AdjustedAmount`. A Cashier or Dispatcher who tries to decide is **refused**. Each decision stores `DecidedBy`, `DecidedAt`, and `DecisionNote` |
| T10 | The operator disputes a **driving flag** after the trip | `'Driving_Flag'`, `AmountDisputed = 0.00`, nothing is withheld, the Terminal Manager decides |
| T11 | The operator tries to dispute a **fare line after the payment is recorded** | **Refused** |

**Depart, GPS fallback, and automatic start**

| # | Situation | Expected result |
|---|---|---|
| T12 | The Dispatcher taps Depart. In another trip the Cashier taps it | `DepartureSource = 'Dispatcher'`, then `'Staff'`. `DepartedAt` set, `ListLockedAt` set if not already |
| T13 | Nobody taps Depart. The phone shows N consecutive readings outside the terminal zone while moving with a boarding counted | The trip departs, `DepartureSource = 'GPS'`. A **single stray reading** does not start a departure |
| T14 | Nobody started the trip when the van departs, and the share was recorded | The system starts it: `'Auto_Assigned'` with the assigned van (or `'Auto_Detected'` with the van the phone is out with, if none was assigned), `StartedBy` NULL, `StartReviewStatus = 'Pending'`, **'Unconfirmed Trip Start'** alert. The trip is **not** in the statement |
| T15 | Same as T14, but the share was **not** recorded | `PaymentStatus = 'Left_Unpaid'`, **'Left Unpaid'** alert, the share stored in `HeldShare`, the trip held out of the statement. The van's **next assignment is refused** until it pays or the Terminal Manager overrides |
| T16 | The Terminal Manager reviews the trip from T15 | `'Reviewed'` with who and when. Its fare lines appear, and `HeldShare` moves into `RemittanceOwed` |
| T17 | The Dispatcher presses **'Not a passenger trip'** (reason `'Errand'`) and the van leaves | `Non_Passenger_Moves` row. **No trip is started and nothing is owed**, and the GPS fallback does not start one |
| T18 | Same as T17, but the camera sees a **passenger aboard** while the button is on | The trip **starts automatically** (`'Auto_Detected'`, `'Pending'`), the Terminal Manager is alerted, `AutoStartedScheduleID` set |
| T19 | A van leaves with **no Dispatcher** and no phone, and the Cashier starts the trip manually | **Warning**, trip starts, `AuditStatus = 'Unaudited'`, `'No_Phone'`, alert to the Terminal Manager, the Cashier, and the Dispatcher. No door count, no overload alert, no GPS departure |
| T20 | The starter confirms van A, but the events come from the phone checked out to van B | **Warning** to the starter. Start is not blocked. Events are still matched to the trip of the van that sent them, by time |
| T21 | The Cashier tries to void a started trip or change its van | **Refused.** The Terminal Manager's void is stored with who, when, and why, `Status = 'Cancelled'` |

**Camera and capacity**

| # | Situation | Expected result |
|---|---|---|
| T22 | Before departure, fewer people are aboard than listed (sample: 12 against 13) | A **no-show**. No action, no change to the amount |
| T23 | Before departure, **more** people are aboard than listed | The Dispatcher must **fix the list** (person, destination, fare, 15 %) or **type a reason** before Depart. `ResolutionStatus` becomes `'Listed'` or `'Explained'`. A seat added after the payment was recorded becomes a top-up (T7) |
| T24 | Same as T23, but the van leaves anyway | **'Departed With More Than Listed'** alert to the Terminal Manager. No fare is priced from the camera's count |
| T25 | After departure, E13 and E14 board by the road (sample) | **Not flagged, not priced.** Remittance stays ₱217.50. E14 raises the **capacity alert** at 05:51:31 with the location "between Toril and Sta. Cruz" to the Terminal Manager, the Dispatcher, and the Cashier |
| T26 | The Dispatcher has added themselves as crew | The Dispatcher is **not counted** toward the 14 and does not count as a boarding |
| T27 | The phone is **silent** when the Cashier starts the trip | **Warning**, trip starts, `AuditStatus = 'Unaudited'`, `'Silent_At_Start'`, alert to the Terminal Manager, the Cashier, and the Dispatcher |
| T28 | The phone goes silent mid-trip (no report within `HeartbeatGapS`) and the reports it stores do **not** cover the gap | Alert at once. When the phone reconnects, or the trip ends, the trip becomes Unaudited from the start of the gap, `'Lost_En_Route'`. Service continues |
| T29 | The phone loses mobile data for 3 minutes mid-trip, then reconnects with stored reports that show the camera and GPS working | The alert fires at once, but the trip **stays Audited** |

**Home pickup**

| # | Situation | Expected result |
|---|---|---|
| T30 | A relative books for someone else, with a pin (a) within `HomePickupMaxRouteM`, (b) beyond it | (a) Accepted **automatically**, `RouteDistanceM` stored. (b) Refused |
| T31 | The home-pickup seat is paid (a) through the gateway, (b) by a screenshot in the chat | (a) Counts in V. (b) The image is accepted within `ChatImageMaxKb`, the Dispatcher confirms it to the Terminal Manager (`ProofConfirmedBy`, **'Home Pickup Proof'**), and it counts in V |
| T32 | The pickup is activated (a) by the relative's QR scan, (b) by the Dispatcher's entry | `ActivationMode` `'QR_Scan'` or `'Dispatcher_Entry'` with `ActivatedBy` for (b). `Status = 'Activated'` |
| T33 | The van reaches the pin and waits | `ArrivedAt` set. The stop is **expected**: no flag, **not** an unscheduled stop. The wait is **subtracted** from the stretch time (sample: 17.3 − 3.5 = 13.8 min) |
| T34 | (a) The passenger boards within 10 minutes and the Dispatcher ends the stop early, (b) the passenger is not found | (a) `ClosedEarly = TRUE`, `ClosedBy` stored, `Status = 'Boarded'`. (b) `'No_Show'`, and the **seat still counts** in the remittance |

**Roster, custody, retention, and others**

| # | Situation | Expected result |
|---|---|---|
| T35 | An operator is named on two vans in an import file | The row is **rejected** with a reason. The database `UNIQUE` on `Vans.OperatorID` also refuses it |
| T36 | `RetentionDays = 30` (assumed). A snapshot is older than 30 days and its flag is reviewed | File deleted, `SnapshotURL` NULL, `SnapshotDeletedAt` set, `SnapshotHash` kept |
| T37 | Same as T36, but the event is an **unresolved over-list boarding** (`ResolutionStatus 'Pending'`), or its flag is not yet reviewed | **Not deleted** |
| T38 | The Cashier, a Dispatcher, or a Passenger asks for a blurred snapshot or its URL | **Refused.** Only the Terminal Manager receives it |
| T39 | Recompute `EventHash` for a trip after T36 | Every hash still matches, and the chain verifies without the image |
| T40 | A trip has an **open dispute** | **Nothing is deleted** until the dispute is decided |
| T41 | (a) A chat image larger than 10 MB (`ChatImageMaxKb` = 10240) is sent, (b) a chat image is older than `ChatImageRetentionDays` | (a) **Refused.** (b) It is deleted, and `Messages.RetainUntil` is honoured |
| T42 | A second staff member signs in | `StartedBy`, `AssignedBy`, `ChangedBy`, and `RecordedBy` record that person. There is no shared account |
| T43 | The Cashier runs the setup check and checks a phone out to a Dispatcher and van | Open `Device_Checkouts` row, `Edge_Devices.Status = 'Checked_Out'`. Events from that phone match the trip of that van |
| T44 | The Dispatcher returns the phone and the Cashier records it | `ReturnedBy`, `ReturnedAt`, and `ReturnNote` set, `Status = 'In_Office'`. A second check-out of the same phone, or of the same van, while one is open is **refused** |
| T45 | The Cashier assigns a van and a Dispatcher while the Terminal Manager is off duty | Allowed (if the van's last trip is paid). `AssignedBy` is the Cashier, and the Terminal Manager gets an **'Assignment by Cashier'** alert and can change it |
| T46 | A door event arrives when the van has **no assigned trip** | It waits in the unassigned list, outside `Passenger_Events`, **'Trip Not Started'** is raised, and once a trip is assigned or started the event is matched to it by time. An event that arrives when the van **has** an assigned trip, even unstarted, goes to that trip |
| T47 | The van arrives. Aboard is still 2. Later the Dispatcher taps Arrived (or aboard reaches 0) | The trip stays open until then, then `CompletedAt` is set, `Status = 'Completed'`, and the **phone pauses**. It resumes at the van's next assignment |
| T48 | The van drives back to the terminal with paying passengers | **Nothing is recorded or audited.** No trip, no statement, no fare line |
| T49 | A walk-in passenger asks at the counter for the whole van. The Cashier enters the pickup, destination, passenger count, name, and contact, agrees a fee, and writes what it is based on | A `Special_Trip_Requests` row with `PassengerID` NULL, `CustomerName`, `CustomerContact`, `EnteredBy` = the Cashier, and `FeeNote`. The trip is created with `IsSpecial = TRUE` |
| T50 | A passenger requests a special trip in the app with 15 passengers | **Refused** (the limit is 14). With 14, the request is stored with `PassengerID` set and `EnteredBy` NULL |
| T51 | A special trip with a cash fee of ₱2,000 (illustrative). The Dispatcher logs the cash and hands over the share | D = ₱2,000.00 and `RemittanceOwed` = ₱300.00. **Start is blocked** until the Cashier records the ₱300.00. Gateway payment of the same fee counts as V instead |
| T52 | The operator declines a far special trip. The Terminal Manager or the Cashier assigns another van | The first assignment is cleared, the new `AssignedVanID`, `AssignedBy`, and `AssignedAt` are stored, and the trip keeps `IsSpecial = TRUE`. [OPEN] Whether the first van keeps its place in the queue |

---

## 13. Suggested order of work [ADVICE]

1. **Gap report**: repo vs this brief (roles, tables, screens, edge app, matching code). Wait for approval.
2. **Schema migration** (Sections 7.1 to 7.3), written as reversible migrations. Roles and renames first, then new tables (including `Edge_Devices`, `Device_Checkouts`, `Disputes`, `Non_Passenger_Moves`, `Assisted_Pickups`, and `Messages`), then the start, review, audit, departure, and payment columns. **Drop** the old estimate and side-pickup columns (Section 7.1) only after asking. `Vans.OperatorID` becomes UNIQUE, so check the existing data for an operator on two vans before migrating.
3. **Settings and roster**: `TerminalSettings` keys (start window, heartbeat, terminal zone and departure readings, home pickup, chat images at 10 MB, `RetentionDays`), `Operators`, validation, import and export with preview (one van per operator), `Data_Transfers`, and the phone pool with check-out and return (`Edge_Devices`, `Device_Checkouts`).
4. **Trip lifecycle**: timetable → trips days ahead (and **special trips**, from an app request or a counter entry by the Terminal Manager or the Cashier, with the fee paid first), assignment at the van's turn (Terminal Manager, Cashier backup) with the **payment block** and the Terminal Manager's override, the **passenger list** (QR scans and Dispatcher cash entries with destinations, crew toggle), the Cashier's **payment record**, **Start** (blocked until the share is recorded), **Depart**, the **GPS departure fallback**, the **automatic start** (assigned van, then phone-detected van, 'Left Unpaid', held out of the statement), **'Not a passenger trip'**, void and change-van (Terminal Manager only), alerts.
5. **Edge ingestion API**: authenticated event upload with `DeviceID`, offline-tolerant, idempotent, with heartbeat into `Edge_Devices` (including stored reports sent after a reconnect); the Unaudited check (`'No_Phone'` too). Then the Android edge app (Section 5), which pauses at arrival and resumes at the next assignment.
6. **Checking, hash chain (with `SnapshotHash`), pre-departure comparison (aboard against listed, fix or reason), capacity alert, and remittance computation** (`ρ × (V + D)`, top-ups, held share, disputed share), then the **home pickup** (booking, pin check, activation, wait, proof) and the **dispute record and decision** (`Disputes`). Run the Section 12 acceptance tests.
7. **Retention job** (Section 4.5) after the hash chain works, so test T39 can run. It skips trips with an open dispute or an unreviewed flag, and it also covers chat images.
8. **NAHGM and driving flags** against `Nahgm_tracking_logs`, with the general location of each alert and the home-pickup wait subtracted.
9. **Screens**: Start Trip, Review Automatic Starts, Boarding Audit, Remittance, Van Status Board, Phones, Disputes, Member Records, Rules and Settings, Special Trips, Book for Someone Else, Messages.
10. **Pilot checks**: full-trip phone benchmark (fps, temperature, battery, uptime) before any figure is stated, and the site survey for the terminal zone radius and N.

---

## 14. Open items to confirm with A2Z or decide in the group

- Capacity: confirm the **franchise capacity** of A2Z's units with LTFRB Region XI (an LTFRB reminder lists UV Express at 9, 10, or 12 including the driver, or the manufacturer's specification). 14 is A2Z's cap.
- Whether en-route loading is still treated as a franchise breach (reference [11]).
- **Roadside loading just outside the terminal zone** is not flagged or priced (disclosed limitation). Confirm that A2Z accepts it.
- **Fixed-route boarding:** that passengers board only at the starting terminal before departure, and that the passenger list is complete before the van leaves.
- **Special trips:** the assumptions in Section 2.5. Confirm **what the fee is based on** (the group's answer was garbled, so it was read as a fee agreed on the spot by pickup and destination), **whether the Cashier may agree it** (separation of duties), **whether a van that declines a far special trip keeps its queue place**, that the fee is **paid before the van leaves** with the 15 % recorded before Start, and whether a Dispatcher rides on a rented van.
- **Home pickup:** the 10-minute wait, the maximum distance of the pin from the route, the chat image retention period (the group gave 10 MB, and 30 days is assumed), and the line in the privacy notice. Confirm that the Dispatcher's confirmation of a screenshot to the Terminal Manager is how A2Z wants to handle gateway outages.
- **Trip start and assignment:** the 30-minute window, that A2Z assigns a van and a Dispatcher to each departure at the van's turn, that the Cashier may assign when the Terminal Manager is off duty, and that the Cashier has time to start trips at the counter in peak hours.
- **Terminal zone and GPS departure:** the **radius of the terminal zone** and **N consecutive readings** from a **site survey** of the queue and loading area.
- **Payment block:** that the Terminal Manager alone overrides, with a written reason, and that **one override covers both** the Start block and the assignment block.
- **Remittance timing:** that the Dispatcher hands 15 % of the paid seats on the list to the Cashier before Start, that **the operator fronts the 15 %** before the day's fares are collected, and what happens when a van does not depart again, when an owner stops operating, or when a trip that was paid in advance is voided (Section 2.1).
- **Held trips:** that an auto-started trip is held out of the statement until reviewed while its unpaid share counts toward the van's balance.
- **Independent trips are special trips** [DECIDED]. Still open: the **'Not a passenger trip'** reasons list.
- **Edge phone and custody:** exact model, Android version, RAM, and processor. How many phones A2Z needs, and when a phone that has not come back counts as missing. The silent-phone gap (placeholder 120 s). Whether A2Z allows a camera in the cabin.
- **Evidence retention:** the group chose **fixed days** and gave **30 days**. Confirm 30 days with A2Z and that **only the Terminal Manager** may view the blurred snapshots. **A2Z's data privacy contact is not yet named**: keep the placeholder `[name and position to be supplied by A2Z]` until A2Z supplies it, and confirm the sign in each van and the notice on the booking screen.
- **Disputes:** that an operator can contest only a fare line or a driving flag at the counter, that a fare line can be contested only until the payment is recorded, that the operator pays the undisputed part meanwhile, that only the Terminal Manager decides, and whether a second person should review a dispute over the Terminal Manager's own decision. Passenger complaints and refunds are not covered.
- **One login per staff member** (needed because `StartedBy`, `AssignedBy`, `ChangedBy`, and `RecordedBy` name a person).
- **Hash chain** hardening: device-side signing in the Keystore, and whether starts, voids, overrides, and 'Not a passenger trip' join the chain (would be Table 42).
- **Dispatcher sign-in:** phone number or email.
- **Operators:** the paper assumes **one van per operator** and that the owner always drives. Confirm that no A2Z member owns several vans, and what happens when someone else drives (a substitute).
- **Gateway settlement** goes to the operator's payout account. Confirm with A2Z.
- **Member records:** which fields the binder really holds (operators: name, contact, email, license number and expiry; vans: plate, CPC case number and number, model, color, route). Whether both the Terminal Manager and the Cashier may import and export.
- **Export for LTFRB:** which fields and file format LTFRB Region XI needs.
- Replace every **illustrative value** (stop coordinates, limits, fares, expected speed, stop-zone radius, matching window, flag thresholds) with surveyed ones, and rerun the sample script and tests.
- **Wording to confirm with the group:** the group asked that a Dispatcher who "forgot to click Start" be covered by a fallback. The paper keeps **Start** as the counter step (Cashier or Terminal Manager) and gives the **Dispatcher the Depart tap**, so the fallback is the **GPS departure plus the automatic start**. Confirm that mapping.
- **Figures the group must still redraw in Word** (Figure 9 is already redrawn in the paper):
  - **ERD (Figure 7):** `Edge_Devices` one-to-many to `Device_Checkouts` and to `Passenger_Events`; `Device_Checkouts` many-to-one to `Vans`, `Dispatchers`, and `TerminalStaff` (twice: check-out and return); `Disputes` many-to-one to `Remittances`, `TripSchedules`, and `TerminalStaff` (`DecidedBy`), and optionally to `Remittance_Lines` and `Driving_Events`; `Non_Passenger_Moves` (Table 40) many-to-one to `Vans`, `Edge_Devices`, `Dispatchers`, and `TripSchedules`; `Assisted_Pickups` (Table 41) many-to-one to `Bookings` (twice), `TripSchedules`, `Dispatchers`, and `Messages`; `Vans.OperatorID` one-to-one with `Operators`; the new columns of `TripSchedules` (`StartMode`, `StartedBy`, `AssignedBy`, `AssignedAt`, `StartReviewStatus`, `AuditStatus`, `CompletedAt`, `PaymentOverrideBy`, `PaymentOverrideAt`, `PaymentOverrideNote`, `PaymentStatus`, `ListLockedAt`, `CrewAboard`, `DepartureSource`), of `Passenger_Events` (`DeviceID`, `SnapshotHash`, `SnapshotDeletedAt`, `PreDeparture`), and of `Remittances` (`HeldShare`, `HandedOverBy`); and remove `EstimatedIncome` and `AmountAtRisk` from `Remittances`, `SidePickup`, `DestStopID`, and `EstimatedFare` from `Passenger_Events`, and the `'Estimated'` value from `Remittance_Lines`.
  - **Figure 4:** relabel the phases as in Section 6.2 (pre-departure comparison against the list, no priced estimates).
  - **Scrum sprint plan (Figures 1 and 2).**
- **Design risks to watch:**
  - A phone that changes vans needs the **door line and seat mask re-aligned** at every mounting (Section 5.5).
  - Door events that match no assigned trip are held at the server, and **the data dictionary does not model that list**.
  - `Remittances` has **one `SettlementRef` field** that joins the references of several payments.
  - **One open check-out per phone and per van** is enforced by the application, not by the paper's schema.
  - Disputes after the payment is recorded are out of scope, and the Terminal Manager may decide a dispute over their own decision.
  - Because **GPS auto-start is never blocked**, a van can leave unpaid. The control is the held trip and the refused next assignment, not a physical stop.
  - **A roadside pickup after the van leaves the zone is not audited.**

---

## 15. Terminology and writing conventions

- **A2Z** (not "the co-op" or "the cooperative"). Full name once: "A2Z Transport Cooperative Van Terminal".
- **Dispatcher** (not Conductor), **Terminal Manager** (not Cooperative Administrator or Operator), **Cashier**, **operator** (lower case, the van owner and driver, not a user), **passengers** (not commuters).
- **stop, stretch, distance from the starting terminal, stop zone** (not node, segment, chainage, geofence). The NAHGM expansion, "Node-Aligned Haversine Geofenced Monitoring", stays as it is.
- **pasabay**: a passenger who walks up and rides without a booking or QR ticket (the Dispatcher lists the person with a destination before the van leaves).
- In documentation and comments: no promotional adjectives, and avoid "propose", "proposal", "proponents". State only what the code or the paper does.
- Do not state a frame rate, accuracy, or uptime figure for the edge phone until it has been measured.
