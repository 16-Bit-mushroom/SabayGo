# SabayGo: Change Brief for Claude Code

Last updated: 2026-11-02. Matches the paper draft in the group's working copy (Google Doc "ACM_GoEstilFernandez _ GROUP 4 (Revised)") and the Claude Doc "SabayGo Paper Revision: Replacement Sections", revision 721, with the group's decisions of 2026-11-02 (items 12 and 13 below). The paper text (Abstract, Project Context, objective 1.3.2.4, Scope and Limitation, Table 2 role cells, requirements, IPO, Sections 2.3.2.3 and 2.3.2.6, the text under Table 10, the dispute example) now describes the terminal fees and the operator's share. The previous version of this brief (2026-10-14) matched revision 603.

**Changed since the previous version of this brief (revision 603).** A2Z handles **only cash**, so the study **no longer takes any online payment**. Passengers still **reserve seats in the app**, but they **pay cash to the Dispatcher at the terminal**. The payment gateway, the QR ticket, and the e-ticket are **gone**.

1. **Cash only; no online payment and no QR ticket [DECIDED].** The A2Z manager said that A2Z handles only cash, so passengers can still reserve seats in advance but must pay at the terminal. **Removed:** the payment gateway (for example GCash through PayMongo), QR tickets and QR scanning, the e-ticket screens, `Bookings.PaymentReference`, the `'Refunded'` payment status, `Operators.PayoutRef`, and `Special_Trip_Requests.PaymentReference`. The system still **does not hold or move money**. It records which seats the Dispatcher marked as paid (Sections 2.1 and 2.6).
2. **Reserve in the app, pay cash to the Dispatcher [DECIDED].** Each reservation gets a short **booking code** (`Bookings.BookingCode`, for example SG-4821). The Dispatcher finds the reservation by name or booking code and **marks it Paid** (`PaidAt`, `PaidBy`), before Start as well and offline. An **unpaid reservation is not on the passenger list** and is **released automatically at a cutoff before departure** (`TerminalSettings` key `UnpaidCutoffMin`, **default 30 minutes** [DECIDED]). It replaces `HoldReleaseS`.
3. **Income groups are Booked (B) and Walk-up (W).** **Equation (2) is `Remittance owed = ρ × (B + W)`.** B is the fares of the seats reserved in the app that the Dispatcher marked as paid, including home-pickup seats and special-trip fees requested in the app. W is the cash fares of the walk-up (pasabay) passengers that the Dispatcher listed, and special-trip fees entered at the counter. This replaces Verified (V) and Declared (D). The remittance of the sample trip does not change (**₱217.50**); the terminal fees add ₱75.00 and ₱50.00 (item 13).
4. **Cancellation [DECIDED].** A passenger cancels **only an unpaid reservation**, in the app. The **Dispatcher** cancels a reservation when the passenger asks in the chat (returning any cash already paid), or when a passenger forgot to cancel an unpaid reservation. Cancellation **closes** when the Cashier records the payment or the van departs (`TripSchedules.ListLockedAt`). New `Bookings` fields: `BookingCode`, `PaidAt`, `PaidBy`, `CancelledBy`, `CancelReason`.
5. **Matching has no time window [DECIDED].** A boarding is **listed** if an unmatched paid seat or walk-up entry remains on the trip's list, and each seat or entry matches only one boarding. `MatchWindowS` is **removed**. `MatchStatus` is `'Matched_Booking'`, `'Matched_Log'`, or `'Unlisted'` (Sections 5.2 and 6.1).
6. **Special trips and home pickups are paid in cash at the terminal [DECIDED].** Special trip: the renter, or someone acting for the renter, pays the **Dispatcher** in cash at the terminal before departure, the Dispatcher marks it paid, and **hands 15 % to the Cashier before Start**. Home pickup: the relative **pays both seats in cash at the terminal**, and the Dispatcher marks the home-pickup seat paid, which **activates** the pickup. The chat keeps an **image of a landmark** (`Assisted_Pickups.PhotoMessageID`), not a payment screenshot (Sections 2.5 and 2.6).
7. **The list can grow until the van departs [DECIDED].** A top-up added **before Start** blocks Start until it is handed over. A top-up added **after Start** joins the van's balance (Section 2.1).
8. **Capacity is counted per trip.** Every reserved and walk-up seat of a trip counts toward its 14 seats (Section 2.3).
9. **Tables are now 25 to 44.** In the dictionary since the last brief: **Table 42 `Messages`**, **Table 43 `Timetable_Templates`**, and **Table 44 `SosAlerts`**. A start/void log table, if it is ever added, would now be **Table 45**. Changed since the last brief: `Bookings`, `LogBookEntries`, `Passenger_Events`, `Remittances`, `Remittance_Lines`, `Special_Trip_Requests`, `Assisted_Pickups`, `Operators`, `TerminalSettings`, `Notifications` (Section 7).
10. **Figure numbers moved.** The remittance flow is **Figure 6**, the use case diagram **Figure 7**, the ERD **Figure 8**, the architecture diagram **Figure 9**, and the prototype screens **Figures 10 to 27** (the old 7 to 24) (Section 9).
11. **The paper title changed** (below).
12. **Four open points were decided on 2026-11-02 [DECIDED].** (a) The default of `UnpaidCutoffMin` is **30 minutes**. (b) A seat that the Dispatcher marks Paid **offline** after the server released it is **restored if the seat is still free**, and otherwise the **Terminal Manager is alerted** to resolve it. (c) A passenger's **check-in does not stop the release**; only the Dispatcher's Mark as Paid does. (d) The **rest of the cash reaches the operator, and the system records it** (item 13). Sections 2.1, 4.2 (rule 15), 4.6, 7.3, 12.2 (T55, T61 to T63), and 14 follow these.
13. **Terminal fees and the operator's share are recorded [DECIDED 2026-11-02].** The A2Z paper **trip ticket** lists the **terminal fees** of a trip: a **15 % dispatching fee** (the paper's remittance), a **₱50 parking fee**, and a **₱75 DCOTT ticket** (paid with ₱5 City Treasurer stamps), added into one total. On the sample ticket: gross ₱2,185.00, 15 % = ₱327.75, parking ₱50.00, DCOTT ticket ₱75.00, total ₱452.75. The study now has three amounts: **(a)** the **15 % remittance**, Equation (2), unchanged; **(b)** the **₱75 DCOTT ticket fee for each trip**; and **(c)** the **₱50 parking fee for each van each service day, charged once, even when the van has no trip**. Together they are the **terminal fees**.
    - The Dispatcher hands the terminal fees due to the **Cashier** before Start, and the Cashier **records them as one payment**. **Start and the next assignment are blocked until all the terminal fees due are recorded** (same Terminal Manager override).
    - The **rest of the cash** (the cash on the list less the terminal fees) is the **operator's share**. The Dispatcher hands it to the operator **at the counter, in front of the Cashier, in the same step**, and the **Cashier records it**, so that the Terminal Manager can monitor how the cash was divided. It is **no longer exactly 85 %**.
    - A **van with no trip** that is parked at the terminal still pays the ₱50: the **Cashier records a parking-only charge**.
    - The statement shows the cash on the list, the three fees, and the operator's share owed and given, and **flags a difference** (monitoring only; it blocks nothing). **Amounts only**: the DCOTT stamp serial numbers are not recorded.
    - [ASSUMED] The ₱75 also applies to a special trip. [OPEN] Confirm the three amounts with A2Z; they are settings (`DcottTicketFee`, `ParkingFee`). DCOTT is printed on the ticket; the group should confirm the full name.
    - **Reading rule:** wherever this brief still says that the Dispatcher hands "the 15 %" or "the share" to the Cashier, or that the Cashier records it, read **the terminal fees due**: the 15 %, the ₱75 of the trip, and the day's ₱50 when it has not been paid yet. `HeldShare` is the unpaid part of those fees on a held trip. Sections 2.1, 3, 4.2, 7.2, 7.3, 9, 12, and 14 follow this.

**Carried over from the previous version of this brief, still valid.** The model is built around **one boarding point and payment before departure**. A2Z's 15 % covers only the trip that boards at the terminal, and the return leg is outside the system (the phone pauses at arrival and resumes at the van's next assignment). The passenger list with destinations exists before the van leaves, and a roadside pickup after the van leaves the terminal zone is not flagged or priced (a disclosed limitation). The Dispatcher hands the 15 % to the Cashier, who records it, and **Start is blocked** until it is recorded; only the Terminal Manager can override, with a written reason, and GPS auto-start is never blocked. The camera works in two modes: before departure it compares the number aboard with the number listed, and after departure it holds the van to 14 and prices nothing. Start and Depart are separate steps, with a GPS departure fallback, an automatic start, and a 'Not a passenger trip' button. NAHGM gives each capacity alert and driving flag a general location. Disputes cover a fare line or a driving flag only. An independent trip is a special trip, created from an app request or by the Terminal Manager or the Cashier for a walk-in, with the fee agreed on the spot and paid first. Evidence retention is one fixed period (`RetentionDays`, 30 assumed), and only the Terminal Manager can view the blurred snapshots. Passengers are told about the camera by a sign in each van and a notice on the booking screen. Chat images are limited to 10 MB, and their retention period (30 days) is assumed. The in-van phones are a **pool kept in the office** and go out **only with a Dispatcher** (Section 5.5, `Edge_Devices` Table 37, `Device_Checkouts` Table 38). A van with no phone out runs **Unaudited** (`'No_Phone'`). The van and the Dispatcher are **assigned at the van's turn** by the Terminal Manager, or by the Cashier when the Terminal Manager is off duty (no duty roster). There is **one van per operator**, and trips are created from the timetable **days ahead**. A2Z's data privacy contact is **not yet named**, so keep the placeholder `[name and position to be supplied by A2Z]`.

Paper title (current): *SabayGo: A YOLOv8-Audited Seat Reservation System with NAHGM Driving Behavior Monitoring for Public Utility Vans.*
Pilot site: the A2Z Transport Cooperative Van Terminal, Davao. Call it **A2Z** everywhere.
Team: Liam E. Go (project leader, documentation), Chris Cyrel Estil (developer), Carl Lawrence Fernandez (UI structure, documentation). Adviser: Ms. Charisse P. Barbosa.

---

## 0. How to use this file

1. This file describes **what changed** in the study's design since the original proposal. The original code base was built for the old design (booking and fleet management with Conductor, Operator, and Driver users and an Orange Pi/Raspberry Pi edge node), and it may contain an online payment gateway and QR tickets, which are now out of scope, so parts of the repo will be out of date.
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
7. The paper's data dictionary in the Google Doc still lags in a few places (see the leftovers in Section 14). When a table there still mentions a matching window, `'MatchWindowS'`, `'Matched_QR'`, the Cashier marking a special-trip fee paid, or the notification type 'Home Pickup Proof', follow this brief.

---

## 1. What changed, in one table

| Area | Before | Now |
|---|---|---|
| Purpose | Booking and fleet management with a headcount check against the manifest | **Pre-departure remittance audit**: A2Z gets **15 % of the fares on the passenger list of each trip that boards at the terminal**, handed by the Dispatcher to the Cashier **before Start**. The list holds the seats that the Dispatcher marked as paid and the walk-up cash passengers. The camera checks the list at the door and holds the 14 cap on the road |
| Payment and ticket | Online payment through a gateway and a QR e-ticket (earlier versions of this brief) | **Cash only.** The passenger **reserves in the app** (booking code) and **pays cash to the Dispatcher at the terminal**, who marks the seat Paid. **No online payment, no QR ticket.** An unpaid reservation is released at a cutoff |
| Money | One statement settled at the van's turn, return leg included, with estimated income | **Payment before departure** on the passenger list only. `ρ × (B + W)`, plus the **₱75 DCOTT ticket for each trip** and the **₱50 parking fee for each van each day**, and the Cashier records the **operator's share**. **No estimated income. The return leg is outside the system** |
| Capacity | 14 seats, per route segment | **Strictly 14 passengers per van, counted per trip** (A2Z's operating rule), held by booking and, after departure, by the door camera |
| Detection | Headcount at one moment, compared with the manifest | **Door events.** Before departure: aboard against listed (no-show allowed; more aboard than listed needs a fix or a reason). After departure: only the 14 cap. **No fare is priced from the camera** |
| NAHGM | Greedy segment matching and live passenger ETA | **Node-Aligned Haversine Geofenced Monitoring**: geometry only. Gives each capacity alert and driving flag a **general location** and places the van on stops and stretches. Passenger live position and ETA are no longer in scope |
| Driving | Not covered | Flags for **overspeed, slow stretch, unscheduled stop** (and an en-route stop record that is not flagged) |
| Evidence | None | **SHA-256 hash chain** over each trip's door events (evidence-based non-repudiation) |
| Roles | Passenger, Conductor, Operator, Driver | **Passenger, Dispatcher, Terminal Manager, Cashier**. The Conductor is now the **Dispatcher**. The Operator and the Driver are **not users** |
| Operator | A user | The **van owner, who always drives**. An A2Z member but an independent contractor. One roster record, **no account**, one van |
| Edge node | Orange Pi 5 or Raspberry Pi 4 with a USB webcam | A **pool of dedicated Realme 5G Android phones**, kept in the office and taken out by a Dispatcher, that supply the camera, GPS, processor, and mobile data |
| Boarding rule | Not defined | Fixed-route boarding **only at the starting terminal, before departure**. **One exception: the home pickup** of a disabled or elderly passenger, booked by a relative who comes to the terminal first and pays both seats in cash. A roadside pickup after the van leaves the terminal zone is **not flagged or priced** (disclosed limitation) |
| Trip start | Not defined | **Start** (counter step, blocked until the share is recorded) and **Depart** (Dispatcher taps it; GPS detects it if nobody does), automatic start for a trip nobody started, and a **'Not a passenger trip'** button |
| New features | | Booking code with Mark as Paid and cancellation by the Dispatcher, release of unpaid reservations, special trips (rent the whole van, fee paid in cash to the Dispatcher), **home pickup (Book for Someone Else, chat with a landmark photo)**, member roster with import and export, van status board, remittance statement and Cashier payment record, van and Dispatcher assignment at the van's turn, an Unaudited flag for trips without camera evidence, a retention setting, phone check-out and return, operator disputes |
| Writing terms | node, segment, chainage, geofence | **stop, stretch, distance from the starting terminal, stop zone** (the NAHGM expansion keeps "Node-Aligned" and "Geofenced") |

---

## 2. Business rules [PAPER unless tagged]

### 2.1 Money
- A2Z handles **only cash**. The operator collects fares and **remits 15 % of the fares on the passenger list of the trip about to leave, at the terminal, before the van leaves**. The system **takes no online payment** and **does not hold or move money**. It records which seats the Dispatcher marked as paid in cash, computes the remittance and the other terminal fees (below), and lets the Cashier record the payment and the operator's share.
- Rate is `ρ = 0.15`, a **dated, configurable** setting. A change applies only to later days (`TerminalSettings.EffectiveFrom`).
- **How a seat is paid [DECIDED].** The passenger reserves a seat in the app and gets a **booking code** (`Bookings.BookingCode`, for example SG-4821). The passenger **pays cash to the Dispatcher at the terminal before the van leaves**. The Dispatcher **finds the reservation by name or booking code and marks it Paid** (`PaymentStatus = 'Paid'`, `PaidAt`, `PaidBy`). This works **before Start** and **offline**: the list is kept on the Dispatcher's device and syncs when the connection returns. A passenger who walks up (a pasabay) is **listed by the Dispatcher with a destination and fare** (`LogBookEntries`). Every fare is read from `Fare_Matrix` by the drop-off terminal.
- **Unpaid reservations [DECIDED].** A reservation that is not paid is **not on the passenger list** and **adds nothing** to the amount owed. It still holds one of the 14 seats until it is released. The system **releases it automatically at a cutoff before departure** (`UnpaidCutoffMin`, a Terminal Manager setting): `CancelReason = 'Auto_Release'`, `CancelledAt` set, and the passenger is notified. Before the cutoff the passenger gets a **reminder to pay at the terminal**. **Default [DECIDED 2026-11-02]:** `UnpaidCutoffMin` is **30 minutes**, the same as `StartOpensMin`, so that the list is settled when Start opens. It stays a Terminal Manager setting, and A2Z confirms it in the pilot.
  - **Check-in does not hold the seat [DECIDED].** Only the Dispatcher's **Mark as Paid** stops the release, because a check-in in the app is not cash and the Dispatcher cannot verify it.
  - **Paid mark made offline after the release [DECIDED].** The Dispatcher's device keeps working offline (Section 2.1, how a seat is paid). When the mark syncs and the server **has already released** the reservation: **(a)** if the trip still has a free seat (fewer than 14 counted), the system **restores the reservation as Paid** (`Status` back to `'Confirmed'`, `PaymentStatus = 'Paid'`, `PaidAt` and `PaidBy` from the mark, the cancellation fields cleared) and the passenger is notified; **(b)** if a walk-up has taken the seat, the system **does not restore it** and **alerts the Terminal Manager**, who resolves it with the Dispatcher and the passenger, because the cash was already taken. The alert uses a new notification type, for example `'Paid After Release'` [ADVICE]. The mechanism of the restore is [ASSUMED]; the paper does not spell it out.
- Income is sorted into **two groups**:
  - **Booked (B)**: the fares of seats reserved in the app that the Dispatcher marked as paid, **including home-pickup seats** and **special-trip fees requested in the app**, paid at the terminal.
  - **Walk-up (W)**: the cash fares of the walk-up passengers that the Dispatcher listed, and **special-trip fees entered at the counter**.
- **Equation (2):**
  ```
  Remittance owed = ρ × (B + W)
  ```
- **Terminal fees and the operator's share [DECIDED 2026-11-02].** Besides the 15 % remittance, A2Z's trip ticket lists two fixed fees: a **₱75 DCOTT ticket for each trip** (`DcottTicketFee`) and a **₱50 parking fee for each van each service day** (`ParkingFee`), charged **once a day, even when the van has no trip**. With the remittance they are the **terminal fees**:
  ```
  Terminal fees owed   = ρ × (B + W) + DcottTicketFee × trips + ParkingFee (once per van per day)
  Operator's share owed = (B + W) − Terminal fees owed
  ```
  The two fixed fees are **settings with a start date**, like the rate. They are **not fare lines**, do **not depend on the number of passengers**, and are **not disputable** [ASSUMED]. [ASSUMED] A special trip also pays the ₱75. The trip ticket is the paper form of the statement, and its "15 % Disp. Fee" is the paper's remittance. The paper's text needs equation numbers for these two lines when it is edited.
- **A paid seat counts whether or not the passenger comes.** A paid no-show still counts because the seat was paid. A reservation that is **not paid counts for nothing**. **The camera's count adds nothing to the amount.**
- **Who pays whom [DECIDED]:** the Dispatcher takes the cash from the passengers and **hands the terminal fees due to the Cashier** (15 % of the paid seats on the passenger list, the ₱75 DCOTT ticket, and the day's ₱50 parking if not yet paid) **and the operator's share to the operator**, at the counter, in front of the Cashier, before Start. The **Cashier records the payment** with its reference number and date and the **name of the Dispatcher who handed it over** (`Remittances.HandedOverBy`, `RecordedBy`), and **records the operator's share handed over** (`OperatorShareGiven`, `OperatorShareGivenAt`, `OperatorShareRecordedBy`). The operator has no account, so the Cashier's entry is the only record and the operator does not sign [ASSUMED].
- **Cancellation and list lock [DECIDED].**
  - A **passenger cancels only an unpaid reservation**, in the app.
  - The **Dispatcher cancels** a reservation (a) at the passenger's request in the chat, **returning any cash already paid** (`CancelReason = 'Passenger_Asked_Dispatcher'`), or (b) when a passenger forgot to cancel and did not come to pay (`'Forgot_To_Cancel'`). The cash is returned between the Dispatcher and the passenger. The system records only the cancellation (`CancelledBy`, `CancelledAt`).
  - Cancellation **closes** when the Cashier records the payment **or** the van departs, whichever comes first (`TripSchedules.ListLockedAt`). Before the lock, a cancellation removes the seat and its share from the amount owed. After the lock there is **no cancellation, no refund, and no credit**, so no credit is ever computed.
- **The list can grow until the van departs [DECIDED].** A seat added after the Cashier recorded the payment (a walk-up, or a reservation that the Dispatcher marks Paid late) adds a **top-up of 15 % of its fare** (`Remittance_Lines.IsTopUp = TRUE`). The rest of that fare is the operator's share, recorded at the same counter step. The ₱75 and the ₱50 do not repeat.
  - If the trip **has not been started**, **Start stays blocked** until the Dispatcher hands the top-up over.
  - If the trip **has been started**, the top-up **joins the van's balance**, and the van is refused its next assignment until it is paid, unless the Terminal Manager records a reason.
  - The list **cannot shrink** after the lock.
- **Hard block [DECIDED].**
  - **Start is blocked** (counter action by the Cashier or the Terminal Manager) until the **terminal fees due** for the trip about to leave (the 15 %, the ₱75 DCOTT ticket, and the day's ₱50 parking if not yet paid) are recorded.
  - **Assignment is blocked** while the van's **last trip is unpaid**. "Unpaid" counts `TerminalFeesOwed + HeldShare − SettledAmount` on the van's statements, **leaving out disputed shares**. An unpaid **parking-only** statement counts like any other [ASSUMED]. The operator's share is never part of the block.
  - Only the **Terminal Manager** can override, with a **written reason** (`PaymentOverrideBy`, `PaymentOverrideAt`, `PaymentOverrideNote`). The Cashier cannot. [ASSUMED] The same override covers both blocks.
  - [ADVICE] When a seat is added after the payment was recorded and before Start, set `PaymentStatus` back to `'Unpaid'` until the top-up is recorded, so that Start stays blocked.
- **GPS auto-start is never blocked [DECIDED].** The system cannot stop a van from physically leaving. A van that leaves the terminal with passengers aboard and without paying is **started by the system**, flagged **'Left unpaid'** (`PaymentStatus = 'Left_Unpaid'`), and **held out of the statement** until the Terminal Manager reviews it (Section 4.2). Its unpaid fees (the 15 % and the ₱75 DCOTT ticket) are stored in **`Remittances.HeldShare`** and **still counts toward the van's balance**, so the van is **refused its next assignment** until it pays or the Terminal Manager overrides.
- **The way back is outside the system [DECIDED].** The fares collected on the return leg belong to the operator for the van's upkeep. They are **neither recorded nor audited**. The phone **pauses when the van arrives** and **resumes at the van's next assignment**. Do not build a return-leg trip, statement, or settlement.
- **Statement.** One row per van per service date (`UNIQUE (VanID, ServiceDate)`) that adds the van's trips of the day. `Status` is `'Open'` while a balance remains (including `HeldShare`), otherwise `'Settled'`. Payments add up in `SettledAmount` (the payment before each trip's Start, plus top-ups), `SettledAt` is the latest, and `SettlementRef` joins the references (VARCHAR(255)). The old "overdue" statement idea is **removed**. `SettledAmount` adds up the **terminal fees** paid. The statement also carries the ₱75 for each trip counted and the **₱50 parking, once per van per service day**: it is added when the Cashier opens the van's statement, or when the Cashier records a **parking-only charge** for a van that has no trip that day (the statement then holds no trip and no fare line, and the operator pays the ₱50 out of pocket).
- The Cashier's record (reference number and date) is the only payment record. There is **no payout account and no gateway settlement**. **The operator's share [DECIDED 2026-11-02]:** the system **records** the amount that the Dispatcher hands to the operator (the cash on the list less the terminal fees), entered by the Cashier at the same counter step, so that the Terminal Manager can monitor how the cash was divided. It records amounts only and **does not hold or move the money**. When every trip's list on the statement is locked and the amount given differs from the amount owed, the statement shows an **'Operator share differs'** flag on the Remittance screen and in the Terminal Manager's review. The flag blocks nothing [ADVICE]. [ASSUMED mechanism] The operator does not sign or confirm in the system.
- **Held trips.** A trip the system started without confirmation (`StartReviewStatus = 'Pending'`) is **left out of the statement and of the fare lines** until the Terminal Manager reviews it. On review, create its fare lines and move its `HeldShare` into `RemittanceOwed` [ASSUMED mechanism, the paper does not spell it out]. A payment that was recorded for a trip that is later held stays in `SettledAmount`.
- **Unaudited trips [DECIDED].** A trip with no camera evidence (Section 4.4) is **not checked against the camera**: its door count is not compared with the list, and no overload alert is raised. The amount owed still comes from the list, and the statement **shows the trip as unaudited**.
- **Disputes [DECIDED].** The operator has no account, so a dispute is raised **at the counter while the operator checks the list and the amount before the share is paid**. The Dispatcher, the Cashier, or the Terminal Manager records it with the operator's own words (`Disputes`, Table 39).
  - **Scope:** a **fare line** or a **driving flag** only.
  - **Money:** the operator **pays the undisputed part**, and the **disputed share (15 % of the item's fare) waits**. It is shown separately from the amount due, and the block checks the **undisputed** amount only, so one contested fare line does not hold up Start. A driving flag withholds nothing (`AmountDisputed = 0.00`). The operator's share of a disputed line is **not** withheld, and the ₱75 and ₱50 fees cannot be disputed [ASSUMED].
  - **Timing:** a **fare-line dispute can be recorded only until the Cashier records the payment**. A **driving-flag dispute can be recorded after the trip**, while its evidence is kept.
  - **Decision:** **only the Terminal Manager decides**, with a written reason, logged with who and when. **Upheld**: the item leaves the amount owed. **Rejected**: the share becomes due. **Adjusted**: the Terminal Manager sets the share that is due (`AdjustedAmount`). **Withdrawn**: the operator drops it and the share becomes due.
  - **Evidence:** snapshots and GPS logs of the trip are kept while a dispute is open (Section 4.5).
  - **Not covered:** a passenger's complaint or refund, and a contest of a fare line after the payment is recorded. The Terminal Manager may decide a dispute over their own earlier decision, because there is no third role (limitation in the paper).
  - **Example (sample trip, Section 12.1):** the operator contests the **walk-up cash seat to Sta. Cruz** (₱80, share ₱12.00). The operator pays the undisputed **₱330.50** at once (₱205.50 remittance, ₱75.00 DCOTT ticket, ₱50.00 parking) and the ₱12.00 waits. **Upheld**: the remittance owed is ₱205.50. **Rejected**: the ₱12.00 becomes due.
- **Worked example (sample trip, Section 12.1):** 14 listed seats, B = ₱1,370.00 (11 booked seats to Digos at ₱110, one of them the home-pickup seat, and 2 booked seats to Sta. Cruz at ₱80), W = ₱80.00 (one walk-up cash seat to Sta. Cruz). Remittance owed = 0.15 × 1,450.00 = **₱217.50**. The van's first and only trip that day also owes the ₱75.00 DCOTT ticket and the day's ₱50.00 parking, so the **terminal fees are ₱342.50**, handed over before Start, and the **operator's share is ₱1,450.00 − ₱342.50 = ₱1,107.50**, handed to the operator in the same step. The unused seat still counts. The two unlisted roadside passengers add **nothing**. If the walk-up seat is entered after the payment was recorded but before Start, only a **₱12.00 top-up** is owed (and ₱68.00 more goes to the operator).
- [OPEN] A van that never departs again, an owner who stops operating, and a trip whose payment was recorded but that is later voided (the statement is overpaid, so a credit would be needed).

### 2.2 Fare lines
A fare line groups the paid seats of **one trip** that go to **the same drop-off terminal, at the same fare, in the same income group**. The origin is always the starting terminal. Fares come from `Fare_Matrix` (terminal-to-terminal, with `EffectiveFrom`), read by the **drop-off terminal** that the passenger or the Dispatcher entered. A special-trip rental fee is also a line (`RequestID`, `PassengerCount = 1`).

### 2.3 Capacity
- Aboard now = **door count minus the crew**. The **driver's seat is masked**, and the **Dispatcher adds themselves as crew once in the app** (`TripSchedules.CrewAboard`, logged, **not counted toward the 14**).
- When aboard rises **above 14**, raise a **capacity alert** with the time and the **general location** on the route. It goes to the **Terminal Manager, the Dispatcher, and the Cashier** [DECIDED].
- Booking also holds each **trip** to 14 seats (row-level locking in MySQL, `SELECT ... FOR UPDATE`). **Every reserved and walk-up seat counts, per trip** (not per route segment). An unpaid reservation counts until it is released, and its release frees the seat for a walk-up.

### 2.4 Boarding rule and the camera
- **Fixed-route trip:** boarding is allowed **only at the starting terminal, before the van departs**, whether the passenger reserved a seat in the app or walks up, and **either way pays cash to the Dispatcher**. The **passenger list is complete before departure**: the seats that the Dispatcher marked as paid, the Dispatcher's cash walk-ups **with destinations**, and home-pickup seats. A reservation that is **not paid is not on the list**: a passenger who boards with an unpaid reservation is an unlisted boarding until the Dispatcher takes the cash and marks the seat Paid, or types a reason.
- **Before departure,** the Dispatcher's screen compares **the number aboard (door count minus crew)** with **the number listed**, leaving out home-pickup seats that have not boarded yet.
  - **Fewer aboard than listed:** a **no-show**. Allowed, because the seat is paid. No action.
  - **More aboard than listed:** the Dispatcher must **fix the list** (the person, the destination, the fare, and the 15 % on it) **or type a reason** before tapping Depart. A reason adds no fare, so a departure cleared with a reason instead of a corrected list is **also flagged to the Terminal Manager for review**. A van that **leaves anyway** raises **'Departed with more people aboard than listed'** to the Terminal Manager. **The camera's count alone sets no fare.**
- **After departure,** the camera counts **only to hold the van to 14**. A passenger picked up along the road after the van leaves the terminal zone is **neither flagged nor priced**. [OPEN] This is a disclosed limitation: an operator could load passengers just outside the zone, and the study does not audit them. Confirm that A2Z accepts it.
- **Special trips and home pickups booked and paid before departure** are not checked by this rule.

### 2.5 Special trips [DECIDED]
- A passenger **rents the whole van** and is picked up at a chosen location. Apart from the home pickup, it is the only trip type that allows pickup outside a terminal.
- **An independent trip is a special trip** [DECIDED]. A van that runs **outside the timetable** does so because a passenger **books the entire van and pays for all of its seats**. The system has no separate "independent van" path: such a trip is created as a special trip (`IsSpecial = TRUE`).
- **Two ways to create one:**
  - the passenger **requests it in the app** (date and time, pickup, destination, passenger count, **at most 14**), or
  - a **walk-in** passenger asks at the counter, where the **Terminal Manager or the Cashier enters the same details** (`PassengerID` NULL, `CustomerName`, `CustomerContact`, `EnteredBy`).
- The **Terminal Manager or the Cashier agrees the rental fee** with the passenger **according to the pickup location and the destination**. There is no fare table for it (`RentalFee`, with a `FeeNote` that records what the fee is based on). The same person **assigns a van and a Dispatcher**. [INTERPRETED] The group's answer was garbled: it was read as a fee agreed on the spot and not taken from a table. Confirm what the fee is actually based on (distance, destination, hours, or an agreed amount).
- **Payment comes first, in cash** [DECIDED]. The passenger, or someone acting for the passenger, **pays the fee in cash to the Dispatcher at the terminal before the van leaves**, and the Dispatcher **marks it paid** (`Special_Trip_Requests.PaymentStatus`, `PaidAt`). As on every trip, the Dispatcher hands **15 % of the fee to the Cashier before Start**, under the same hard block (Sections 2.1 and 4.2). GPS auto-start is still never blocked. [DECIDED: "Dispatcher takes cash, hands 15 %".] The paper's data dictionary text for Table 34 still says the Cashier records the fee as paid. Follow this brief.
- A **Dispatcher rides on it and an edge phone goes out with it**, as on a timetabled trip [DECIDED by the group; confirm with A2Z]. The trip is therefore audited like any other.
- A special trip **takes the van's turn**, but the **operator may decline one that is too far away**. The Terminal Manager or the Cashier then assigns another van [DECIDED, "quite flexible"]. [OPEN] Whether the declining van keeps its place in the queue.
- It has no fixed route, no stop zones, and no terminal-to-terminal fare. The camera still counts people and raises the capacity alert. GPS is still stored. Overspeed uses a **default limit** set by the Terminal Manager (`SpecialTripSpeedKmh`).
- The fee is the **whole income of the trip**: **booked income (B)** when the passenger requested the trip in the app, **walk-up income (W)** when it was entered at the counter. The 15 % covers it.
- [OPEN] The Cashier agrees the fee and also records the 15 % that the Dispatcher hands over. This weakens the separation of duties (Section 3). Ask whether the Terminal Manager alone should agree fees.

### 2.6 Home pickup [DECIDED]
The only exception to "board at the terminal". It is for a **disabled or elderly passenger** who cannot come to the terminal.
- A **relative books** the seat in the app (**'Book for someone else'**): the passenger's name and contact number, and a **pin on the map with a short note**. The relative **also holds a seat**, **comes to the terminal first, and rides along**, so the van is never sent alone to a house.
- **Payment is cash at the terminal.** The relative **pays both seats in cash to the Dispatcher at the terminal**, and the Dispatcher **marks the home-pickup seat Paid**. There is no online payment and no screenshot of a payment.
- The seat is on the passenger list like any other. It counts in B and is **owed even if the passenger is not found**.
- **The pin is accepted automatically** within a maximum distance from the route (`HomePickupMaxRouteM`, a Terminal Manager setting). Store the distance in `Assisted_Pickups.RouteDistanceM`.
- **Activation:** the pickup is activated when the Dispatcher **marks the home-pickup seat Paid** at the terminal after the relative pays in cash, or **enters it by hand** when the relative asks for it at the terminal (`Status = 'Activated'`, `ActivatedBy`, `ActivatedAt`). There is no QR scan and no `ActivationMode`.
- **On the trip:** the van goes to the pin and **waits up to 10 minutes** (`HomePickupWaitMin`). The Dispatcher can **end the stop early** by marking the passenger boarded or a no-show, and the early end is **logged with the Dispatcher** (`ClosedEarly`, `ClosedBy`). A home-pickup stop is **expected**: no flag, **not an unscheduled stop**, and its wait is **subtracted from the stretch time** (Section 6.3).
- **The chat keeps image attachments**, for example the **photo of a landmark** at the pickup place that the relative sends to the Dispatcher (`Assisted_Pickups.PhotoMessageID`). It is **not payment proof** and nothing depends on it. Images are up to **10 MB** each (`ChatImageMaxKb` = 10240 [DECIDED]) and are kept for a **retention period** (`ChatImageRetentionDays`, **30 days** [ASSUMED: the group gave only the size], `Messages.RetainUntil`), and the privacy section has a **line** about it, because a photo can show personal details.

---

## 3. Roles and permissions [DECIDED / PAPER]

Four roles only. Do **not** build screens, accounts, or tables for an Operator user or a Driver user.

| Capability | Passenger | Dispatcher | Terminal Manager | Cashier |
|---|:--:|:--:|:--:|:--:|
| Find route and schedule, reserve a seat (booking code), see the fare, **pay cash to the Dispatcher at the terminal**, check in | ✔ | | | |
| **Cancel an unpaid reservation** in the app, until the list is locked | ✔ | | | |
| **Book for someone else** (home pickup): beneficiary, map pin, own seat, **both seats paid in cash at the terminal**, chat with a landmark photo | ✔ | | | |
| Request a special trip, and **pay the rental fee in cash to the Dispatcher at the terminal** (in person or through someone acting for the passenger) | ✔ | | | |
| Receive booking, **pay-at-terminal reminder**, **release of an unpaid reservation**, delay, cancellation, boarding notifications | ✔ | | | |
| **Find a reservation by name or booking code and mark it Paid** when the passenger pays cash (also before Start, works **offline**) | | ✔ | | |
| **Cancel a reservation** at the passenger's request, returning any cash already paid, or an unpaid one that was forgotten (until the list is locked) | | ✔ | | |
| **List walk-up cash passengers with their destinations** (works **offline**, also on the scheduled trip before Start, once the Dispatcher is assigned) | | ✔ | | |
| **Take a special trip's rental fee in cash and mark it paid**, and hand its 15 % to the Cashier | | ✔ | | |
| **Add themselves as crew** once in the app (logged, not counted toward the 14) | | ✔ | | |
| **Fix the list** (person, destination, fare, 15 %) or **type a reason** when more people are aboard than listed | | ✔ | | |
| **Hand the terminal fees due (15 %, ₱75 DCOTT ticket, the day's ₱50 parking) to the Cashier** before Start, and **the operator's share to the operator**, at the counter in front of the Cashier | | ✔ | | |
| **Tap Depart** (primary) | | ✔ | ✔ | ✔ |
| **'Not a passenger trip'**: press before leaving and pick a reason (logged in `Non_Passenger_Moves`) | | ✔ | | |
| Home pickup: **mark the home-pickup seat Paid (this activates the pickup)** or enter it by hand, **end the stop early**, mark the passenger boarded or a no-show | | ✔ | | |
| Confirm the van's plate number against the van, at the door | | ✔ | | |
| Alert: **capacity alert** (15th person) | | ✔ | ✔ | ✔ |
| Alert: **Departed With More Than Listed** | | | ✔ | |
| Alert: **Left Unpaid** [ASSUMED recipients] | | | ✔ | ✔ |
| Alert: driving flags | | ✔ | ✔ | |
| Alert: **Unaudited Trip** (phone off, covered, silent, or not taken out) [DECIDED] | | ✔ | ✔ | ✔ |
| Alert: **Assignment by Cashier** (the Cashier assigned a van and a Dispatcher) | | | ✔ | |
| Alert: **Unconfirmed Trip Start**, **Trip Not Started** | | | ✔ | |
| **Assign a van and a Dispatcher** to the next departure at the van's turn (**refused while the van's last trip is unpaid**, Section 2.1) | | | ✔ | ✔ **only when the Terminal Manager is off duty**. The action always works, is stored in `AssignedBy`, and alerts the Terminal Manager [DECIDED; no duty roster] |
| **Start a trip** (confirm or change the **assigned** van). **Blocked until the share is recorded** | | | ✔ | ✔ |
| **Void a started trip or change its van** | | | **✔ only** | |
| Review trips the system started, trips that **left unpaid**, trips that departed with more aboard than listed **or were cleared with a reason**, and trips that went Unaudited | | | ✔ | |
| Validate operator, dispatcher, and van records | | | ✔ | |
| **Add a phone to the pool** (`Edge_Devices`) | | | ✔ **only** [DECIDED] | |
| **Check a phone out** (after the setup check) to a Dispatcher and van, and **receive it back** (`Device_Checkouts`) | | | ✔ | ✔ |
| **Collect a phone from the office, mount it in the van's holder, and return it** | | ✔ | | |
| **Record an operator's dispute** (`Disputes`) | | ✔ | ✔ | ✔ |
| **Decide a dispute** (Upheld, Rejected, Adjusted) | | | **✔ only** | |
| **View the blurred snapshots** [DECIDED] | | | **✔ only** | |
| **Enter a walk-in special trip**, approve special trips, **agree the rental fee** (by pickup and destination), assign van and Dispatcher [DECIDED; the Cashier setting a fee is [OPEN]] | | | ✔ | ✔ |
| Set rate, **DCOTT ticket fee, parking fee**, fares, speed limits, **cutoff for releasing unpaid reservations**, **terminal zone radius and departure readings**, **home-pickup wait and maximum distance**, **chat image limit and retention**, **retention of snapshots and GPS logs**, other rules | | | ✔ | |
| Fleet screens: capacity alerts, boarding audit, driving flags | | | ✔ | |
| Van status board (on site, travelling, not on a trip, out of service) | | | ✔ | ✔ |
| Import and export member records | | | ✔ | ✔ |
| Show or print the van's statement (the fares of the trip about to leave, any top-up, the terminal fees, the operator's share, and any unpaid share) | | | | ✔ |
| **Receive the terminal fees from the Dispatcher and record the payment**, **record the operator's share that the Dispatcher hands to the operator**, and **record a parking-only charge** for a van with no trip | | | | ✔ |
| **Override the payment block** (Start, or the next assignment), with a written reason | | | **✔ only** [DECIDED] | |
| **Raise an SOS alert** (supporting function, not evaluated) | ✔ | ✔ | | |
| **Mark an SOS alert as responding and close it with a note** (`SosAlerts`, Table 44) | | | ✔ | ✔ |

**Separation of duties [PAPER]:** the person who records a payment (Cashier) does not decide what is owed (Terminal Manager), and the Cashier cannot erase a trip. **Exception [OPEN]:** the Cashier may agree the fee of a special trip, and the Cashier also records its 15 %. Ask whether the Terminal Manager alone should agree fees. The person who encodes an imported record is not the only one who approves it.

**One login per staff member [ASSUMED]:** `StartedBy`, `AssignedBy`, `ChangedBy`, `StartReviewedBy`, and `RecordedBy` name a person, so there must be **no shared Cashier or Terminal Manager account**.

**Operator [DECIDED]:** the van owner who also drives. Roster record only (name, license number and expiry, contact, optional email). **One van per operator.** The operator **arranges in person with the Terminal Manager and the Cashier which trips the van takes**. No login, no app screens. A substitute driver and an owner of several vans are **not supported** (limitation in the paper).

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
3. **Building the list before Start [DECIDED].** Once the Dispatcher is assigned, the Dispatcher **finds each reservation by name or booking code and marks it Paid when the passenger pays cash, and lists cash walk-up passengers with their destinations** on the scheduled trip, and **adds themselves once as crew**. The passenger list therefore **exists before the van leaves**. When the list is ready, the Dispatcher **hands the terminal fees due to the Cashier** (15 % of the paid seats, the ₱75 DCOTT ticket, and the day's ₱50 parking if not yet paid) **and the operator's share to the operator**, and the Cashier records both. A late Start never blocks boarding.
4. **Start window.** The **Start** action appears a set time before departure. Setting `StartOpensMin`, **assumed 30**.
5. **Manual Start [DECIDED].** The **Cashier or the Terminal Manager** confirms or changes the **assigned** van (from the validated vans) and taps **Start**. **Manual Start is blocked until (a) a van and a Dispatcher are assigned and (b) the terminal fees due for the trip are recorded** (`PaymentStatus = 'Paid'`, or `'Overridden'` after a Terminal Manager override with a written reason). The system shows the van's plate number and operator, then **copies the operator's name, license number, and the van's plate number onto the trip**. An **expired license raises a warning** to the starter and the Terminal Manager. It does not block the start [ASSUMED]. If the van that is confirmed is **not the van that the sending phone is checked out to** (its open `Device_Checkouts` row), **warn the starter**. If **no phone is out with the van**, also warn (the trip will be Unaudited, Section 4.4). The Start screen shows the **amount due** and any **top-up**.
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
15. **Release of unpaid reservations [DECIDED].** A scheduled job releases each reservation that is still unpaid `UnpaidCutoffMin` minutes before departure: `Bookings.Status = 'Cancelled'`, `CancelReason = 'Auto_Release'`, `CancelledAt` set, `CancelledBy` NULL, and the passenger is notified. Before the cutoff, the passenger gets a **reminder to pay at the terminal**. The seat is then free for a walk-up. A reservation that the Dispatcher marked Paid is **never** released by the job. **Decided 2026-11-02:** the default is **30 minutes** (keep it a setting); a **check-in does not stop the release**; and a seat that the Dispatcher marks Paid **offline after the release** is **restored if the seat is still free**, and otherwise the Terminal Manager is alerted (Section 2.1). The job must therefore also handle the restore when an offline mark syncs.

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
- An Unaudited trip is **not checked against the camera**. The statement counts only the seats marked as paid and the walk-up fares that were logged, and shows the trip as unaudited (Section 2.1).

### 4.5 Evidence retention [DECIDED]
- **One fixed period for blurred snapshots and GPS logs**, in `TerminalSettings` (`RetentionDays`), set by the **Terminal Manager** and changeable by A2Z. The group chose a **fixed number of days**. The paper uses **30 days** [ASSUMED, taken from the group's answer, to be confirmed with A2Z]. There is **no `RetentionMode`** and no "until settled" option.
- **Only the Terminal Manager can view the blurred snapshots** [DECIDED]. Enforce it in the API as well as in the screens: the Cashier, the Dispatcher, and the Passenger never receive a snapshot URL.
- **Safeguard [DECIDED]:** never delete evidence tied to a **flag that is not yet reviewed** (a `Driving_Events` row with `ReviewStatus = 'Open'`, or a `Passenger_Events` row with `ResolutionStatus = 'Pending'`) or to an **open dispute** (`Disputes.Status = 'Open'` on that trip's `ScheduleID`). Keep the evidence until the dispute is decided.
- **Deleting a snapshot keeps the chain verifiable.** When a snapshot is deleted: delete the file, set `SnapshotURL` to NULL, set `SnapshotDeletedAt`, and **keep `SnapshotHash`**. `EventHash` is computed over the event's fields **including `SnapshotHash`**, so recomputing it after deletion still matches.
- [DECIDED] For GPS logs, delete only the raw `Nahgm_tracking_logs` rows. `Driving_Events` rows stay.
- [ADVICE] Run it as a scheduled job and log what it deletes.
- **Chat images** (the landmark photo of a home pickup) follow their **own** limits: up to **10 MB** each (`ChatImageMaxKb` = 10240 [DECIDED]) and a retention period (`ChatImageRetentionDays`, **30 days** [ASSUMED: the group gave only the size], `Messages.RetainUntil`). The privacy notice says so, because a photo can show personal details.
- **Notice [DECIDED]:** passengers are told about the camera by a **sign in each van** and a **notice on the booking screen**.
- **Privacy review [OPEN]:** A2Z's data privacy contact reviews the retention period and the notice against the **Data Privacy Act of 2012** before the pilot. The contact is **not yet named**. Keep the placeholder `[name and position to be supplied by A2Z]`.


### 4.6 Open points for the trip start and payment [OPEN]
- Confirm with A2Z: the **30-minute** start window, that the **Cashier** has time to start trips at the counter in peak hours, and that the **Cashier may assign** the van and Dispatcher when the Terminal Manager is off duty.
- **Off duty [DECIDED].** No duty roster and no toggle. The Cashier's assign action always works, `AssignedBy` shows who did it, and the Terminal Manager is alerted ('Assignment by Cashier').
- **Terminal zone radius and N (`DepartZoneRadiusM`, `DepartReadings`)** come from a **site survey** of the queue and loading area. Do not invent values.
- **Does one Terminal Manager override cover both blocks** (Start, and the next assignment)? The paper assumes yes. Confirm.
- **Home pickup:** confirm the 10-minute wait and the maximum distance from the route (`HomePickupMaxRouteM`) with A2Z, and confirm the chat image size limit (10 MB) and retention period (30 days, assumed), and the privacy line. Confirm that both seats are paid in cash at the terminal.
- **How the cash is divided [DECIDED 2026-11-02]:** the Dispatcher takes the cash at the terminal, hands the terminal fees due (15 %, ₱75, and the day's ₱50) to the Cashier and the operator's share to the operator at the counter, and the Cashier records both. Confirm with A2Z the three amounts, that the ₱75 also applies to a special trip, that the operator receives the share at the counter before Start, and whether the operator should sign for it (no account in the system).
- **Unpaid reservations [DECIDED]:** default `UnpaidCutoffMin` of 30 minutes, check-in does not hold the seat, and an offline Paid mark after the release restores the seat if it is still free, otherwise the Terminal Manager is alerted. Confirm the 30 minutes with A2Z in the pilot.
- Should each start, void, change, override, and 'Not a passenger trip' join a **hash chain**? That needs a small log table (it would be **Table 45**, and the ERD, Figure 8, would be redrawn). Right now the paper says only that they are stored with who, when, and why. Do not add the table without asking.
- **Special trips [DECIDED, with open points]:** an independent trip is a special trip (Section 2.5). Confirm what the **fee is based on**, whether the **Cashier** may agree it, and whether a van that **declines** a far special trip keeps its queue place.
- **When does a phone that has not come back count as missing**, and who is alerted?
- **What happens** when a van does not depart again, when an owner stops operating, or when a trip whose payment was recorded is voided and leaves its statement overpaid (Section 2.1).

---

## 5. Edge node: the in-van Realme 5G phone

### 5.1 Decided [DECIDED / PAPER]
- A **dedicated** phone from the terminal's pool (Section 5.5), **separate from the Dispatcher's phone** (which stays with the Dispatcher for the passenger list).
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
4. **Before departure** (`PreDeparture = TRUE`): the server compares the **number aboard** with the **number listed**. A boarding at the terminal is **listed** if an **unmatched seat that the Dispatcher marked as paid**, or an **unmatched walk-up entry by the Dispatcher**, **remains on the trip's list**. Each seat or entry is matched to **only one boarding** (`MatchStatus` `'Matched_Booking'` or `'Matched_Log'`). There is **no time window**. Otherwise it is **`'Unlisted'`** with `ResolutionStatus = 'Pending'` until the Dispatcher **fixes the list** (`'Listed'`) or **types a reason** (`'Explained'`, with `ResolutionNote`). The match is a **count, not an identity**: `MatchedBookingID` names the seat that was used up, not the person who boarded. [ADVICE] Use up paid seats in `PaidAt` order and walk-up entries in `LogTimestamp` order. The paper does not say which is taken first, and the amount owed does not depend on it.
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
- **Clock sync to server time.** The phone's time stamps order the events and feed the hash chain and the GPS departure rule, and the Dispatcher's offline entries are replayed in order, so a clock offset would corrupt the order. Matching itself no longer uses time.
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
- A boarding at the terminal is **listed** if an **unmatched seat that the Dispatcher marked as paid**, or an **unmatched walk-up entry by the Dispatcher**, **remains on the trip's list**. Each seat or entry is matched to **only one boarding**, and a boarding for which none is left is **unlisted**. **There is no time window** (`MatchWindowS` is removed). The match is a **count, not an identity** (Section 5.2).
- A reservation that is **not paid is not on the list**. A passenger who boards with an unpaid reservation is an unlisted boarding until the Dispatcher takes the cash and marks the seat Paid, or types a reason.
- A **pasabay** is a passenger who walks up and rides **without a reservation**. At the terminal the Dispatcher **lists** the person with a destination, the fare goes into W, and the 15 % goes in the share handed to the Cashier.
- A passenger who has paid but does not come is a **no-show**, and the **seat still counts**.
- **Before departure:** compare the number aboard (door count minus crew) with the number listed, **leaving out home-pickup seats that have not boarded**. More aboard than listed: the Dispatcher **fixes the list** (adds the person's destination and fare and the 15 % on it) **or types a reason** before Depart. A reason adds no fare, so a departure cleared with a reason is **also flagged to the Terminal Manager for review**. A van that leaves anyway is flagged to the Terminal Manager as having departed with more aboard than listed. Fewer aboard: a no-show, and nothing changes.
- **Fare of every listed passenger:** from `Fare_Matrix`, by the **drop-off terminal** that the passenger or the Dispatcher entered. The same table prices a passenger whom the Dispatcher adds after the camera showed more aboard than listed. **Never price a fare from the camera's count.**
- **After departure:** no matching and no pricing. The camera only holds the van to 14.
- **Alightings are not matched** to people. The old ticket-count rule and its first-in-first-out matching are **removed**.
- No face or identity matching.
- `MatchStatus` values: `'Matched_Booking'`, `'Matched_Log'`, `'Unlisted'` (NULL for an alighting). `ResolutionStatus` values: `'Not_Needed'`, `'Pending'`, `'Listed'`, `'Explained'`.

### 6.2 The four phases [PAPER, Figure 4]
1. **Edge detection** on the phone: detect, track, record each boarding and alighting with a time stamp.
2. **Geotagging** by NAHGM: each event and each alert gets its place on the route.
3. **Checking** on the server: apply the matching, boarding, and capacity rules to the seats marked as paid and the Dispatcher's walk-up entries of the trip, and show the Dispatcher the number aboard against the number listed.
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
- **Removed with online payment [DECIDED]:** `Bookings.PaymentReference` and the `'Refunded'` payment status; `Operators.PayoutRef`; `Special_Trip_Requests.PaymentReference`; `Remittances.VerifiedIncome` and `DeclaredIncome` (now `BookedIncome` and `WalkUpIncome`); the `'Verified'` and `'Declared'` values of `Remittance_Lines.IncomeGroup` (now `'Booked'` and `'Walk_up'`); the `'Matched_QR'` value of `MatchStatus` (now `'Matched_Booking'`); `Assisted_Pickups.ActivationMode`, `ProofMessageID`, `ProofConfirmedBy`, and `ProofConfirmedAt` (now `PhotoMessageID`); the `TerminalSettings` keys `MatchWindowS` and `HoldReleaseS` (now `UnpaidCutoffMin`); the notification type 'Home Pickup Proof'; and the payment gateway, QR ticket, and e-ticket screens. Do not carry any of them forward, and do not add an online payment path.

### 7.2 New tables (paper Tables 25 to 44)
| # | Table | Purpose and key fields |
|---|---|---|
| 25 | `Operators` | `OperatorID` PK, `FullName`, `ContactNumber` UNIQUE, `Email` NULL (optional), `LicenseNumber` UNIQUE, `LicenseExpiry`, `MembershipStatus` ('Active','Suspended','Inactive'), `ValidationStatus` ('Pending','Validated','Rejected','Suspended'), `ValidatedBy`, `ValidatedAt`, `ImportBatchID`. **No login.** |
| 26 | `TerminalStaff` | `StaffID`, `FullName`, `Email` (login), `StaffRole` ENUM('Manager','Cashier'), `IsActive` |
| 27 | `Fare_Matrix` | `FareID`, `OriginTerminalID`, `DestTerminalID`, `Fare`, `EffectiveFrom`. UNIQUE (origin, destination, EffectiveFrom) |
| 28 | `Route_Stretches` | `StretchID`, `RouteCode`, `StretchNo`, `FromTerminalID`, `ToTerminalID`, `FromDistanceM`, `LengthM`, `SpeedLimitKmh`, `StopZoneRadiusM` (default 100), `ExpectedTimeS` |
| 29 | `Passenger_Events` | One row per door event: `EventID`, `ScheduleID`, **`DeviceID` FK NOT NULL → `Edge_Devices` (the phone that sent the event)**, `EventType` ('BOARD','ALIGHT'), `EventAt` DATETIME(6), `Latitude`, `Longitude`, `DistanceFromStartM`, `StretchNo`, `NearestStopID`, `NearestStopDistM`, **`PreDeparture` BOOLEAN NOT NULL** (TRUE before the trip departed, when the door count is compared with the list; FALSE after, when the camera only holds the van to 14), `OccupancyAfter` (not counting the driver or the Dispatcher), `TrackID`, `MatchStatus` ('Matched_Booking','Matched_Log','Unlisted'; **NULL for an alighting**), `MatchedBookingID` (the seat that the Dispatcher marked as paid and that this boarding used up), `MatchedLogEntryID` (also the entry the Dispatcher added when fixing the list), `SnapshotURL` (NULL once the snapshot is deleted), **`SnapshotHash` CHAR(64) NULL**, **`SnapshotDeletedAt` DATETIME NULL**, `EventHash` CHAR(64), **`ResolutionStatus` ENUM('Not_Needed','Pending','Listed','Explained') NOT NULL DEFAULT 'Not_Needed'** (`'Pending'` is an unlisted boarding before departure that the Dispatcher has not yet fixed; `'Listed'` means the Dispatcher added the person to the list; `'Explained'` means the Dispatcher typed a reason), `ResolvedBy` FK → `Dispatchers`, `ResolvedAt`, `ResolutionNote` VARCHAR(255) NULL. **No `SidePickup`, `DestStopID`, or `EstimatedFare`** |
| 30 | `Driving_Events` | `DrivingEventID`, `ScheduleID`, `FlagType`, `StartAt`, `EndAt`, `DistanceFromStartM`, `StretchNo`, `MaxSpeedKmh`, `LimitKmh`, `TimeRatio`, `NearestStopDistM`, `DurationS`, `ReviewStatus` |
| 31 | `Nahgm_tracking_logs` | GPS readings: `LogID` BIGINT AUTO_INCREMENT, `ScheduleID`, `RecordedAt` DATETIME(3), `Latitude`, `Longitude`, `SpeedKmh` (from the phone's GNSS), `DistanceFromStartM`, `StretchNo`, `NearestStopDistM` |
| 32 | `Remittances` | Statement per van per service date, open until its balance is paid (`SettledAmount` adds up the terminal fees paid, `SettledAt` is the latest, `SettlementRef` VARCHAR(255) joins the references): `RemittanceID`, `OperatorID`, `VanID` (UNIQUE with `ServiceDate`), `ServiceDate`, `BookedIncome` (B), `WalkUpIncome` (W), `RatePct`, `RemittanceOwed` (`ρ × (B + W)`), **`DcottFees` DECIMAL(10,2) NOT NULL DEFAULT 0.00** (₱75 for each trip counted on the statement), **`ParkingFee` DECIMAL(10,2) NOT NULL DEFAULT 0.00** (₱50 once per statement; the only amount on a parking-only statement), **`TerminalFeesOwed`** (`RemittanceOwed + DcottFees + ParkingFee`), **`OperatorShareOwed`** (`(B + W) − TerminalFeesOwed`, never below 0.00, compared once every trip's list on the statement is locked), **`OperatorShareGiven` DECIMAL(10,2) NOT NULL DEFAULT 0.00** (what the Dispatcher handed to the operator, entered by the Cashier; adds up like `SettledAmount`), **`OperatorShareGivenAt` DATETIME NULL**, **`OperatorShareRecordedBy` FK NULL → TerminalStaff**, **`HeldShare` DECIMAL(10,2) NOT NULL DEFAULT 0.00** (fees, the 15 % and the ₱75, due on trips the system started and the Terminal Manager has not reviewed; left out of the fare lines and of `RemittanceOwed`, but counted toward the van's balance for the payment block), `Status` ('Open','Settled'), `SettledAmount`, `SettledAt`, `SettlementRef`, `RecordedBy` (Cashier), **`HandedOverBy` FK → `Dispatchers`** (the Dispatcher who handed over the latest payment). **No `EstimatedIncome` and no `AmountAtRisk`** |
| 33 | `TerminalSettings` | Key-value rules with `EffectiveFrom`: `SettingKey`, `EffectiveFrom` (PK together), `SettingValue`, `UpdatedBy`, `UpdatedAt`. Keys are listed in Section 7.3 |
| 34 | `Special_Trip_Requests` | `RequestID`, **`PassengerID` FK NULL (NULL for a walk-in)**, **`CustomerName` VARCHAR(100) NULL, `CustomerContact` VARCHAR(20) NULL** (walk-in), **`EnteredBy` FK NULL → TerminalStaff** (the Terminal Manager or Cashier who entered a counter request), `PickupAt`, pickup and destination address and coordinates, `PassengerCount` (≤ 14), `RentalFee` (agreed by the Terminal Manager or the Cashier according to pickup and destination), **`FeeNote` VARCHAR(255) NULL** (what the fee is based on), `PaymentStatus` ('Unpaid','Paid': the Dispatcher marks the fee paid after taking the cash at the terminal before the van leaves), `PaidAt` ([ADVICE] add `PaidBy` FK NULL → `Dispatchers` to record who took the cash; the paper's table has only `PaidAt`), `Status` ('Requested','Approved','Rejected','Completed','Cancelled'), `ScheduleID` (trip created on approval, `IsSpecial = TRUE`), `ReviewedBy` (the Terminal Manager or the Cashier), `ReviewedAt` |
| 35 | `Remittance_Lines` | Fare lines behind a statement: `LineID`, `RemittanceID`, `ScheduleID`, `OriginTerminalID` (the starting terminal; NULL on a special trip), `DestTerminalID` (NULL on a special trip), `RequestID` (when the line is a rental fee), `IncomeGroup` ('Booked','Walk_up'), `FarePerPassenger`, `PassengerCount` (includes a seat whose passenger did not come), `GrossFare`, `ShareAmount`, **`IsTopUp` BOOLEAN NOT NULL DEFAULT FALSE** (TRUE for a line added after the Cashier recorded the payment) |
| 36 | `Data_Transfers` | Import and export log: `TransferID`, `Direction`, `RecordType` ('Operators','Vans','Dispatchers'), `FileName`, `FileFormat` ('CSV','XLSX','PDF'), `ExportPurpose` ('Backup','LTFRB Check','Other'), `RowsInFile`, `RowsAccepted`, `RowsRejected`, `ErrorFileURL`, `PerformedBy`, `PerformedAt` |
| 37 | `Edge_Devices` | The terminal's phone pool, with each phone's status and latest report: `DeviceID` PK, `DeviceModel` NOT NULL, `AndroidVersion`, `AppVersion`, `Status` ENUM('In_Office','Checked_Out','Retired') NOT NULL DEFAULT 'In_Office', `RegisteredBy` FK → TerminalStaff (Terminal Manager, who added the phone), `RegisteredAt`, `LastHeartbeatAt`, `BatteryPct`, `BatteryTempC` DECIMAL(4,1), `CameraOk`, `GpsOk`. **No `VanID` and no `IsActive`**: a retired phone has `Status = 'Retired'` and keeps its row |
| 38 | `Device_Checkouts` | Each time a phone leaves the office and comes back: `CheckoutID` PK, `DeviceID` FK NOT NULL, `VanID` FK NOT NULL, `DispatcherID` FK NOT NULL, `CheckedOutBy` FK → TerminalStaff NOT NULL (Cashier or Terminal Manager), `CheckedOutAt` NOT NULL, `ReturnedBy` FK → TerminalStaff NULL, `ReturnedAt` NULL, `ReturnNote` VARCHAR(255) NULL. Open = `ReturnedAt IS NULL`. One open check-out per phone, enforced by the application (Section 5.3) |
| 39 | `Disputes` | An operator's contest of an item: `DisputeID` PK, `RemittanceID` FK NOT NULL, `ScheduleID` FK NOT NULL, `Subject` ENUM('Fare_Line','Driving_Flag') NOT NULL, `LineID` FK NULL → Remittance_Lines, `DrivingEventID` FK NULL → Driving_Events (exactly one is filled to match `Subject`), `OperatorStatement` VARCHAR(500) NOT NULL, `AmountDisputed` DECIMAL(10,2) NOT NULL DEFAULT 0.00 (the share that waits, 15 % of the line; 0.00 for a driving flag), `RaisedByRole` ENUM('Dispatcher','Cashier','Manager') NOT NULL, `RaisedByID` VARCHAR(32) NOT NULL (in `Dispatchers` or `TerminalStaff` according to the role, so no foreign key), `RaisedAt` NOT NULL, `Status` ENUM('Open','Resolved','Withdrawn') NOT NULL DEFAULT 'Open', `Outcome` ENUM('Upheld','Rejected','Adjusted') NULL, `AdjustedAmount` DECIMAL(10,2) NULL (the share due when the outcome is 'Adjusted'), `DecidedBy` FK NULL → TerminalStaff, `DecidedAt` NULL, `DecisionNote` VARCHAR(255) NULL |
| 40 | `Non_Passenger_Moves` | A departure that the Dispatcher marked 'Not a passenger trip': `MoveID` PK, `VanID` FK NOT NULL, `DeviceID` FK NOT NULL → `Edge_Devices`, `DispatcherID` FK NOT NULL, `ScheduleID` FK NULL (the trip the van was assigned to, if any), `Reason` ENUM('Errand','Fuel_Or_Repair','Other') NOT NULL, `ReasonNote` VARCHAR(255) NULL, `StartedAt` NOT NULL, `EndedAt` NULL, `AutoStartedScheduleID` FK NULL → `TripSchedules` (set when the camera saw a passenger aboard during the move and the system started the trip, `StartMode 'Auto_Detected'`) |
| 41 | `Assisted_Pickups` | A home pickup of a disabled or elderly passenger: `PickupID` PK, `BookingID` FK NOT NULL (the passenger's seat), `RelativeBookingID` FK NOT NULL (the relative's seat), `ScheduleID` FK NOT NULL, `PickupLat`, `PickupLng`, `PickupNote` VARCHAR(255) NULL, `RouteDistanceM` INT NOT NULL (checked against `HomePickupMaxRouteM`), `BeneficiaryName`, `BeneficiaryContact`, `Status` ENUM('Requested','Activated','Arrived','Boarded','No_Show','Cancelled') NOT NULL DEFAULT 'Requested', `ActivatedBy` FK NULL → `Dispatchers` (the Dispatcher who took the cash fare at the terminal and activated the pickup), `ActivatedAt`, `PhotoMessageID` FK NULL → `Messages` (the landmark photo that the relative sent in the chat), `ArrivedAt`, `LeftAt` (the wait between them is taken out of the stretch time), `ClosedEarly` BOOLEAN NOT NULL DEFAULT FALSE, `ClosedBy` FK NULL → `Dispatchers`. **No `ActivationMode`, `ProofMessageID`, `ProofConfirmedBy`, or `ProofConfirmedAt`** |
| 42 | `Messages` | In-app chat: `MessageID` PK, `SenderRole` ENUM('Passenger','Dispatcher','Manager','Cashier'), `SenderID` VARCHAR(32), `RecipientRole` (same values), `RecipientID` VARCHAR(32) (no foreign keys, because each points to three tables), `ScheduleID` FK NULL, `Body` VARCHAR(1000) NULL, `SentAt` DATETIME(6), `AttachmentURL` VARCHAR(255) NULL, `AttachmentType` ENUM('Image') NULL, `AttachmentSizeKb` INT NULL (an image above `ChatImageMaxKb` is refused), `RetainUntil` DATE NULL (the image is deleted after it) |
| 43 | `Timetable_Templates` | `TemplateID` PK, `RouteCode` VARCHAR(30), `DepartureTime` TIME, `OperatingDays` SET('Mon','Tue','Wed','Thu','Fri','Sat','Sun'), `IsActive` BOOLEAN NOT NULL DEFAULT TRUE, `CreatedBy` FK → `TerminalStaff`, `CreatedAt`. **No van and no Dispatcher**: they are assigned at the van's turn. 'Create upcoming trips' turns the active rows into `TripSchedules` rows days ahead |
| 44 | `SosAlerts` | Emergency alerts (a supporting function, not evaluated): `SosID` PK, `RaisedByRole` ENUM('Passenger','Dispatcher'), `RaisedByID` VARCHAR(32) (no foreign key), `ScheduleID` FK NULL, `Latitude` NULL, `Longitude` NULL, `RaisedAt`, `Status` ENUM('Open','Responding','Closed') NOT NULL DEFAULT 'Open', `RespondedBy` FK NULL → `TerminalStaff`, `RespondedAt`, `ClosedBy` FK NULL → `TerminalStaff`, `ClosedAt`, `ClosingNote` VARCHAR(255) NULL, `SmsSentAt` DATETIME NULL (SMS through the Twilio API) |

### 7.3 Edits to existing tables [PAPER, working note]
- **Bookings (Table 16):** `TripID` → `ScheduleID` (FK to `TripSchedules`; the old ERD named a table that does not exist). Describe `BookingID` as a UUID. Add **`BookingCode`** VARCHAR(32) UNIQUE NOT NULL (the short code, for example SG-4821, that the passenger gives the Dispatcher, generated when the booking is made), `OriginTerminalID`, `DestTerminalID` (FK), `BookingType` ENUM('App','Walk-in'), `FareAmount` (from `Fare_Matrix` when the booking is made), `PaymentStatus` ENUM('Unpaid','Paid') NOT NULL DEFAULT 'Unpaid' (the Dispatcher sets 'Paid' when the passenger pays cash at the terminal), **`PaidAt`** DATETIME NULL, **`PaidBy`** FK NULL → `Dispatchers`, `Status` ENUM('Pending','Confirmed','Boarded','Cancelled'), **`BookedForOther`** BOOLEAN NOT NULL DEFAULT FALSE, **`IsHomePickupSeat`** BOOLEAN NOT NULL DEFAULT FALSE (the details are in `Assisted_Pickups`, Table 41), **`CancelledAt`** DATETIME NULL (a paid seat can be cancelled **only until the passenger list is locked**, `ListLockedAt`; an unpaid reservation is not on the list and can be cancelled or released until the van departs), **`CancelledBy`** FK NULL → `Dispatchers` (NULL when the passenger cancelled or the system released it), and **`CancelReason`** ENUM('Passenger','Passenger_Asked_Dispatcher','Forgot_To_Cancel','Auto_Release') NULL. **No `PaymentReference` and no `'Refunded'`.**
- **TripSchedules:**
  - add `DriverName` VARCHAR(255) NULL, `DriverLicenseNo` VARCHAR(15) NULL, `VanPlateNumber` VARCHAR(8) NULL (copies taken **when the trip is started**);
  - add `RouteCode`, `Status` ENUM('Scheduled','Boarding','En Route','Completed','Cancelled'), `IsSpecial` BOOLEAN;
  - allow NULL in `AssignedVanID` until a van is assigned at its turn (or, on a special trip, until the Terminal Manager or the Cashier assigns one);
  - rename `ConductorID` → `DispatcherID`, NULL until assigned; add `AssignedBy` FK NULL → TerminalStaff and `AssignedAt` DATETIME NULL (they record who assigned the **van and** the Dispatcher; these replace the old `DispatcherAssignedBy` and `DispatcherAssignedAt`);
  - remove `StandardFare` or keep it as a display value only (every fare is priced from `Fare_Matrix`);
  - add the **start, review, audit, departure, payment-override, `PaymentStatus`, `ListLockedAt`, and `CrewAboard` columns** in Section 4.3.
- **Vans:** add `OperatorID` FK NOT NULL **UNIQUE** (one van per operator); replace the `RegisteredRoute` ENUM with `RouteCode` VARCHAR(30); allow NULL in the four photograph URLs (so an imported van can be saved first).
- **Dispatchers and Vans:** add `ValidationStatus` ENUM('Pending','Validated','Rejected','Suspended') NOT NULL DEFAULT 'Pending', `ValidatedBy` FK NULL → TerminalStaff, `ValidatedAt` NULL, `ImportBatchID` FK NULL → `Data_Transfers`.
- **LogBookEntries:** add `ScheduleID` FK, `DestStopID` FK (the drop-off terminal that prices the seat), `FareAmount` DECIMAL(10,2), `LoggedBy` FK → Dispatchers. An entry is a walk-up cash passenger. It counts toward the passenger list and toward walk-up income (W), and it no longer has a matching window.
- **Yolov8_audit_logs:** remove `DriverID`. Keep as the **cabin-snapshot drift check**. Fix the stray "2" in `NOT NULL2`. Align its columns with Figure 24.
- **Notifications:** replace `PassengerID` with `RecipientType` ENUM('Passenger','Dispatcher','Manager','Cashier') and `RecipientID` VARCHAR(32). Add types `'Capacity Alert'`, `'Departed With More Than Listed'`, `'Driving Flag'`, `'Special Trip Request'`, `'Unconfirmed Trip Start'`, `'Unaudited Trip'`, `'Trip Not Started'`, `'Assignment by Cashier'`, `'Left Unpaid'`, `'Payment Block Override'`, `'Home Pickup Photo'`, `'Dispute Raised'`. (`'Unrecorded Boarding'` and `'Side Pickup'` are **removed**.) The paper's Google Doc dictionary still says 'Home Pickup Proof'. The type is only a rename, and who receives it is [OPEN]. Passenger notices (reminder to pay at the terminal, release of an unpaid reservation, cancellation) use the paper's passenger types ('Tailored Schedule', 'Trip Update', 'System Alert') [ASSUMED mapping].
- **Messages (Table 42):** sender role and ID, recipient role and ID, `ScheduleID`, `Body`, `SentAt`, **`AttachmentURL` VARCHAR(255) NULL, `AttachmentType` ENUM('Image') NULL, `AttachmentSizeKb` INT NULL, `RetainUntil` DATE NULL**. The photo of the pickup landmark of a home pickup is an image sent in the chat (Figure 22), so the chat is kept, with an image size limit, a retention period, and a line in the privacy section.
- **Remittances:** add `HeldShare`, `HandedOverBy`, `DcottFees`, `ParkingFee`, `TerminalFeesOwed`, `OperatorShareOwed`, `OperatorShareGiven`, `OperatorShareGivenAt`, and `OperatorShareRecordedBy`, **replace `VerifiedIncome` and `DeclaredIncome` with `BookedIncome` and `WalkUpIncome`**, and **remove `EstimatedIncome` and `AmountAtRisk`** (Table 32). Payments from several trips and top-ups add up in `SettledAmount`, and their references are joined in `SettlementRef` (VARCHAR(255)).
- **TerminalSettings keys:** `'RemittanceRate'` (0.15), **`'DcottTicketFee'`** (75.00 for each trip, from A2Z's trip ticket), **`'ParkingFee'`** (50.00 for each van each service day, charged even with no trip; both dated like the rate), `'SeatCapacity'` (14), `'OverspeedSeconds'` (10), `'StopSeconds'` (120), `'SlowTolerance'` (0.25), `'ExpectedSpeedKmh'` (55), `'AdvanceBookingDays'`, **`'UnpaidCutoffMin'`** (minutes before departure at which an unpaid reservation is released; **default 30** [DECIDED 2026-11-02]), `'SpecialTripSpeedKmh'`, **`'StartOpensMin'`** (30), **`'HeartbeatGapS'`** (120, placeholder), **`'DepartZoneRadiusM'`** (site survey), **`'DepartReadings'`** (N, site survey), **`'HomePickupWaitMin'`** (10), **`'HomePickupMaxRouteM'`** (to be set), **`'ChatImageMaxKb'`** (10240, the group's 10 MB), **`'ChatImageRetentionDays'`** (30, assumed), **`'RetentionDays'`** (30, assumed; one fixed period for blurred snapshots and GPS logs). **There is no `RetentionMode`.** Sample values are illustrative. **`'StartGraceMin'`, `'MatchWindowS'`, and `'HoldReleaseS'` are removed.** The paper's Table 33 still lists `'MatchWindowS'`. Do not create it.

### 7.4 Still not in the data dictionary [OPEN]
- A **start/void log table** (would be **Table 45**). Not added. See Section 4.6.
- A server-side **unassigned events** list for door events that match no assigned trip (Section 4.2, rule 14). The paper holds them outside the ledger and does not model them in the data dictionary.
- Dispatchers' sign-in: by phone number, or add an `Email` field. The existing table has no email (the paper's Figure 10 shows email and password with a role toggle between Passenger and Dispatcher).
- `Timetable_Templates` (Table 43) and `SosAlerts` (Table 44) are **now in the dictionary** (Section 7.2). SOS alerts are a supporting function and are not evaluated.

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

Figure numbers are those of the paper: the prototype screens are **Figures 10 to 27** (the old 7 to 24), and the screens below name the tables they read from. Figures 13, 14, and 16 are screenshots that the group still has to replace in the paper. Mobile: **Flutter** (Passenger and Dispatcher). Terminal Manager and Cashier use **web screens** (the paper does not name a web framework).

| Screen (figure) | Needs |
|---|---|
| Authentication (10) | Passengers and TerminalStaff email via Firebase Authentication. The login screen has a role toggle between Passenger and Dispatcher. The Terminal Manager and the Cashier sign in on the web application. Dispatcher sign-in method [OPEN] |
| Available Routes (11), Booking Confirmation (12), **Seat Reservation and Pay-at-Terminal Notice (13)**, **Booking Code and Payment Status (14)**, Active Trips and History (15), Profile (17) | `TripSchedules`, `Fare_Matrix`, `Bookings`, `Vans`, `Route_Stretches`. The reservation shows the fare, the status **Unpaid**, and the notice that the fare is **paid in cash to the Dispatcher at the terminal before the cutoff**, after which an unpaid reservation is released. After the Dispatcher takes the cash, the status changes to **Paid** and the **booking code** stays on the screen. The passenger can cancel an unpaid reservation in the app. **No gateway screen and no QR e-ticket** |
| **Book for Someone Else and Home Pickup (new, beside Booking Confirmation, 12)** | Passenger. Beneficiary name and contact number, a **map pin with a note**, the relative's own seat, **both seats paid in cash at the terminal**, and a **landmark photo** sent in the chat. `Bookings` (`BookedForOther`, `IsHomePickupSeat`), `Assisted_Pickups` (Table 41), `Messages` for the photo. Refuse a pin beyond `HomePickupMaxRouteM` |
| Dispatcher Dashboard (16) | **Passenger list with each destination and fare**, a **search by name or booking code**, **Mark as Paid** and **Cancel Reservation** for each reserved seat, a form to **list a walk-up cash passenger**, **number aboard against number listed**, **crew toggle**, **Depart** button, **'Not a passenger trip'** button, home-pickup requests (mark the seat Paid to activate it, end the stop early), the operator's name and license number, the van's plate number. Works **before Start** and **offline** (the list is kept on the device and syncs when the connection returns). **No** van picking, **no** void or change-van buttons. Reads `Bookings` (`PaymentStatus`, `PaidAt`, `PaidBy`, `Status`, `CancelReason`), `LogBookEntries`, `Passenger_Events` (`OccupancyAfter`, `PreDeparture`, `ResolutionStatus`), `TripSchedules` (`CrewAboard`, `DepartedAt`, `DepartureSource`, `PaymentStatus`), `Non_Passenger_Moves`, `Assisted_Pickups`. Hands the 15 % to the Cashier |
| Operations Map (18) | `Nahgm_tracking_logs`, `Passenger_Events.OccupancyAfter`. The 15-second map refresh is a **display setting**, separate from the 1 to 2 s GPS readings |
| Trip Monitoring (19) | Status, Dispatcher, operator, booked, aboard, no-show, camera check, **who started the trip and how**, `AuditStatus`, `PaymentStatus`, and the phone's last report (`Edge_Devices`) |
| **Start Trip (new)** | Terminal Manager and Cashier. Shows the van and Dispatcher **assigned at the van's turn**. The Terminal Manager (or the Cashier when the manager is off duty) **assigns the van and the Dispatcher** (`AssignedVanID`, `DispatcherID`, `AssignedBy`, `AssignedAt`). Confirm or change the van from validated vans. **Start is blocked until the van and Dispatcher are assigned and the share is recorded** (`PaymentStatus`). Shows the **amount due and any top-up**. Assignment is **refused while the van's last trip is unpaid**, and the Terminal Manager has an **Override** that needs a written reason. Warnings: expired license, **no phone out with the van**, phone silent, confirmed van differs from the van the phone is checked out to. **Void and Change Van buttons for the Terminal Manager only.** Writes `StartMode`, `StartedBy`, `StartedAt`, and Depart (`DepartureSource 'Staff'`) |
| **Review Automatic Starts (new)** | Terminal Manager. Trips with `StartReviewStatus = 'Pending'`, trips that **left unpaid** (`HeldShare`), trips that **departed with more aboard than listed or were cleared with a reason**, and trips that are Unaudited. Confirm or change the van, then mark Reviewed (this releases the trip's fare lines to the statement) |
| Special Trips (20), Timetable (25) | `Special_Trip_Requests`, `TripSchedules.IsSpecial`, `Timetable_Templates` (route, time, days, in-use toggle only). New **Request a Special Trip** screen for the Passenger. On the Special Trips screen the **Terminal Manager or the Cashier enters a walk-in request** (name, contact, pickup, destination, passenger count), **agrees the fee** with a basis note, and **assigns a van and a Dispatcher**. Both can review requests. The fee is **paid in cash to the Dispatcher at the terminal** before the van leaves |
| Remittance (replaces Fares and Cash, 23) | Cashier. `Remittances` and `Remittance_Lines`: **booked and walk-up income, remittance owed, the ₱75 DCOTT ticket and ₱50 parking fees, terminal fees owed, held share, the operator's share owed and given, and payment status**, with the fare lines of each statement by trip, drop-off terminal, and fare. The Dispatcher hands the terminal fees over and the operator's share to the operator, and the **Cashier records both here** (with the Dispatcher's name) and records a **parking-only charge** for a van with no trip, shows a **top-up** when a seat is added before Start, can **record a dispute on a line** (only until the payment is recorded), and sees the **disputed share** separately. A statement whose operator's share given differs from the amount owed shows an **'Operator share differs'** flag, which the Terminal Manager also sees. **No estimated income and no amount at risk** |
| Boarding Audit (replaces Passenger Count Checks, 24) | `Passenger_Events`: **unlisted boardings before departure** with time, snapshot (**blurred snapshots are visible to the Terminal Manager only**), hash check, and the Dispatcher's fix or reason, and **capacity alerts with their general location**. The Terminal Manager reviews departures with more aboard than listed or cleared with a reason, and **decides each dispute**. **No estimate decisions** |
| Vans and Crew (26) → **Member Records** | `Vans`, `Operators`, `Dispatchers`, validation fields, `ImportBatchID`. Import and export buttons log to `Data_Transfers` |
| **Van Status Board (new)** | Terminal Manager and Cashier. For the Cashier it shows which vans are out and which vans still owe the share of their last trip |
| **Phones (new)** | Cashier and Terminal Manager. List the pool (`Edge_Devices`: status, battery, last report), **check a phone out** to a Dispatcher and van after the setup check, and **record its return** and condition (`Device_Checkouts`). The Terminal Manager also **adds a phone to the pool** |
| **Disputes (new)** | `Disputes`. The Cashier, the Dispatcher, and the Terminal Manager **record** a dispute (a fare line or a driving flag, the operator's statement, the share withheld). Only the Terminal Manager **decides** (Upheld, Rejected, Adjusted) with a note. Where the Dispatcher records it (mobile app or web) is [OPEN] |
| Rules and Settings (27) | `TerminalSettings`: booking window, seats sold in advance, **cutoff for releasing unpaid reservations**, reschedules, **start window, terminal zone radius and departure readings, home-pickup wait and distance from the route, silent-phone gap, chat image limit and retention, retention of snapshots and GPS logs (one fixed number of days)**. Terminal Manager only(the paper's Figure 27 text still lists a cancellation deadline and a refund policy; cancellation now closes when the list locks, so confirm what those two settings still mean [OPEN]) |
| Messages (22) | **Kept.** Chat threads **with image attachments** (the landmark photo of a home pickup, up to 10 MB each): size limit, retention period, privacy line. `Messages` table (Table 42) |
| Emergencies (21) | `SosAlerts` (Table 44). A supporting function, not evaluated. The Terminal Manager or the Cashier marks an alert as responding and closes it with a note. SMS goes through the Twilio API (`SmsSentAt`) |

UI wording: show the operator **only as a name and license number, with the van's plate number**, on the trip. Never as a user. Say **Dispatcher**, never Conductor.

---

## 10. Stack [PAPER, Table 4]

| Layer | Choice |
|---|---|
| Mobile app | Flutter 3.x, Dart (Passenger and Dispatcher screens) |
| Backend | FastAPI (Python): bookings, check-in, seat locking, door-event intake, matching, remittance computation |
| Database | MySQL 8.0 (InnoDB), row-level locking to hold each trip to 14 seats |
| Edge | Android app on a Realme 5G phone. YOLOv8 nano + ByteTrack, model exported for Android (TFLite or NCNN) |
| Server-side Python | Place events on the route, compute driving flags |
| Maps | Google Maps SDK/API (stops, van position, event locations, check-in coordinates) |
| Messaging and auth | Firebase: FCM push alerts to passengers, Dispatchers, and the Terminal Manager. Authentication for sign-in |
| Emergency SMS | Twilio API (SMS for SOS alerts, `SosAlerts.SmsSentAt`; it appears in the architecture, Figure 9) |
| Source control | GitHub |

Minimum hardware in the paper: Android device 4 GB RAM, 64 GB storage, Android 10 or later; iOS 15 or later; office laptop i5 10th gen or Ryzen 5, 8 GB RAM. The old **Orange Pi / Raspberry Pi + USB webcam** row is replaced by the **Realme 5G phone** row. There is **no payment gateway** in the stack: A2Z handles only cash.

---

## 11. Privacy and non-goals [PAPER]

- **No video leaves the van.** Only event details and a blurred snapshot.
- **No individual passenger identification**, no face matching.
- Non-goals: **online payment of any kind (no gateway, no QR ticket)**; processing or holding money (the system records the amounts that the Dispatcher hands to the Cashier and to the operator, and moves nothing); handling cash, banking, or A2Z's accounting; connecting to LTFRB records; reading binder pages automatically; smoking detection; hardware-level GPS-spoofing protection; passenger live position and ETA; routing or door-to-door pickup on fixed-route trips, **except the home pickup of a disabled or elderly passenger**; **pricing or flagging a roadside pickup after the van leaves the terminal zone**; **recording or auditing the fares collected on the return leg**.
- **LTFRB franchise capacity** and **en-route loading rules** remain A2Z's responsibility to confirm. 14 passengers is A2Z's rule.
- **Retention:** blurred snapshots and GPS logs are kept for one **fixed number of days** (30, assumed; Section 4.5), and **only the Terminal Manager can view the blurred snapshots**. A deleted snapshot keeps its hash. Evidence tied to a flag that is not yet reviewed or to an open dispute is never deleted. **Chat images** (the landmark photo of a home pickup) are limited to **10 MB** and have their own retention period (30 days, assumed), and the privacy notice says so, because a photo can show personal details. **Notice [DECIDED]:** passengers are told about the camera by a **sign in each van** and a **notice on the booking screen**. A2Z's **data privacy contact** reviews the retention period and the notice before the pilot; the contact is **not yet named**, so keep the placeholder `[name and position to be supplied by A2Z]`.
- The system records only which seats the Dispatcher marked as paid, so a cash fare that is never recorded is caught only when the camera finds an unlisted passenger before departure.
- The hash chain makes a later change **detectable**. It is only as reliable as the camera's detection and the integrity of the edge node. The controls detect and deter collusion among trip personnel. They cannot fully prevent it. **A roadside pickup just outside the terminal zone is not audited.**

---

## 12. Acceptance tests

### 12.1 The paper's sample trip

The paper's numbers come from a simulated trip (Ecoland Terminal → Digos City Terminal, departure 05:30:00, four stops, 100 m stop zones, expected speed 55 km/h), computed by the group's sample-dataset script (`sabaygo_sample_dataset.py`, which the group keeps; this brief does not include it, and its labels may still say verified, declared, or QR). All values are **illustrative**. Use them as a regression test for the list check, remittance, and flag logic.

**Passenger list before departure (14 seats):** twelve **reserved seats that the Dispatcher marked as paid in cash**, one **home-pickup seat** (reserved by the relative and **paid in cash at the terminal**), and one **walk-up cash seat** that the Dispatcher listed. **One reserved passenger did not come** (a no-show, and the seat still counts). A reservation that was never paid was released at the cutoff, is not on the list, and adds nothing. After the van left the terminal, **two people who were not on the list boarded by the road**. The simulated driver also made one overspeed burst and one unscheduled stop. The Dispatcher rides as crew and is not counted.

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
| E01 to E11 (11 boardings) | 05:28:00 | 0 | 11 | 11 seats marked as paid, `'Matched_Booking'` (booked). One listed paid seat is unused: a **no-show**, still counted |
| E12 | 05:28:20 | 0 | 12 | Walk-up cash entry logged 15 s earlier, `'Matched_Log'` (walk-up). **12 aboard against 13 listed at the door, so no action**. There is no matching window: the entry was simply still unmatched on the list |
| H01 | 05:40:26 | 9,400 | 13 | **Declared home pickup.** The relative has been aboard since the terminal, and the seat was paid in cash there (booked). The van waited **210 s** at the pin. No flag |
| E13 | 05:51:24 | 16,999 | 14 | Not listed, boarded **after departure**: `PreDeparture = FALSE`, **not flagged, not priced** |
| E14 | 05:51:31 | 17,001 | **15** | Not listed, not priced. **Capacity alert fires** at 05:51:31, general location **"between Toril and Sta. Cruz"**, to the Terminal Manager, the Dispatcher, and the Cashier |
| A01 to A03 (3 alightings) | 06:12:07 | 34,718 | 12 | 3 listed seats to Sta. Cruz |
| A04 to A15 (12 alightings) | 06:31:27 | 46,024 | 0 | 10 listed seats to Digos and the 2 unlisted passengers. **Alightings are not matched to people** |

**Remittance (ρ = 0.15), recorded by the Cashier before Start**

| Group | Fare line (drop-off terminal) | Seats | Gross ₱ | Share ₱ |
|---|---|---|---|---|
| Booked (B) | Digos at ₱110 (booked seats marked paid, including the home pickup, one seat unused) | 11 | 1,210.00 | 181.50 |
| Booked (B) | Sta. Cruz at ₱80 (booked seats marked paid) | 2 | 160.00 | 24.00 |
| Walk-up (W) | Sta. Cruz at ₱80, Dispatcher's cash entry | 1 | 80.00 | 12.00 |
| | **Remittance owed** | 14 | 1,450.00 | **217.50** |

B = ₱1,370.00, W = ₱80.00, and `0.15 × (1,370.00 + 80.00) = ₱217.50`. The script may print the home-pickup seat as its own line (1 seat, ₱110.00, ₱16.50); the paper merges it with the booked seats to Digos (10 + 1 = 11 seats, ₱1,210.00, ₱181.50) because they share the drop-off terminal, the fare, and the income group. Both give ₱217.50. The two unlisted roadside passengers add **nothing**. If the walk-up seat is entered **after** the Cashier records the payment but before Start, only a **₱12.00 top-up** is owed.

**Terminal fees and the operator's share (the van's first and only trip of the day)**

| Item | Amount ₱ |
|---|---|
| Cash on the list (B + W) | 1,450.00 |
| Remittance, 15 % (Equation (2)) | 217.50 |
| DCOTT ticket, one trip | 75.00 |
| Parking, once for the day | 50.00 |
| **Terminal fees owed** | **342.50** |
| **Operator's share owed** (1,450.00 − 342.50) | **1,107.50** |

A2Z's sample trip ticket (gross ₱2,185.00) works the same way: 15 % = ₱327.75, parking ₱50.00, DCOTT ticket ₱75.00, total ₱452.75, so the operator's share would be ₱1,732.25. If the walk-up seat is entered after the payment is recorded and before Start, the fees rise by the ₱12.00 top-up only, and ₱68.00 more goes to the operator.

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
| T1 | The Terminal Manager assigns a van and a Dispatcher at the van's turn. The Dispatcher builds the list and hands over the terminal fees of ₱342.50 (₱217.50 + ₱75.00 + ₱50.00) and the operator's share of ₱1,107.50. The Cashier records both with the Dispatcher's name and taps Start | `PaymentStatus = 'Paid'`, `ListLockedAt` set, `RecordedBy`, `HandedOverBy`, and `OperatorShareGiven` stored. `StartMode = 'Manual'`, `StartedBy` = the Cashier, `StartReviewStatus = 'Not_Required'`, operator name, license number, and plate copied onto the trip |
| T2 | The Dispatcher marks reservations Paid and lists cash walk-ups **before** Start, and Start is tapped 6 minutes later | The paid marks and entries already belong to the trip. Nothing is lost |
| T3 | The Cashier taps Start **before** the share is recorded | **Blocked.** The Terminal Manager overrides with a written reason: Start allowed, `PaymentStatus = 'Overridden'`, `PaymentOverrideBy`, `PaymentOverrideAt`, and `PaymentOverrideNote` stored. The Cashier **cannot** override |
| T4 | Manual Start tapped with **no Dispatcher** assigned | **Blocked** |
| T5 | A van whose **last trip is unpaid** reaches its turn | **Assignment refused.** After the payment is recorded, or after a Terminal Manager override with a note, it is allowed. The Cashier assigning while the Terminal Manager is off duty is **refused** as well |
| T6 | Cancellation: (a) a passenger cancels an **unpaid** reservation in the app before the list is locked, (b) the Dispatcher cancels a **paid** seat at the passenger's request before the lock (the cash is returned), (c) a passenger tries to cancel a **paid** seat in the app, (d) anyone cancels after the Cashier records the payment | (a) `CancelReason = 'Passenger'`, the seat is freed. (b) `'Passenger_Asked_Dispatcher'` with `CancelledBy` = the Dispatcher, and the seat and its share leave the amount owed. (c) **Refused**: only the Dispatcher cancels a paid seat. (d) **Refused**. No refund and no credit |
| T7 | After the payment is recorded, the Dispatcher adds the cash seat (₱80) before Start | **₱12.00 top-up** line (`IsTopUp = TRUE`). Start stays blocked until the top-up is recorded |
| T8 | A listed passenger whose seat was marked Paid does not come | **No change** to the amount: still ₱217.50 |
| T9 | The operator contests the **walk-up seat to Sta. Cruz** before the payment is recorded | `Disputes` row (`'Fare_Line'`, `AmountDisputed = 12.00`). The operator pays the undisputed **₱330.50** (₱205.50 + ₱75.00 + ₱50.00), and the block checks the undisputed amount, so Start is allowed. (a) **Upheld**: owed ₱205.50. (b) **Rejected**: the ₱12.00 becomes due. (c) **Adjusted**: the share due is `AdjustedAmount`. A Cashier or Dispatcher who tries to decide is **refused**. Each decision stores `DecidedBy`, `DecidedAt`, and `DecisionNote` |
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
| T23 | Before departure, **more** people are aboard than listed | The Dispatcher must **fix the list** (person, destination, fare, 15 %) or **type a reason** before Depart. `ResolutionStatus` becomes `'Listed'` or `'Explained'`. A seat added after the payment was recorded becomes a top-up (T7). A departure cleared with a **reason** (no fare added) is also flagged to the Terminal Manager |
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
| T31 | The relative pays both seats in cash at the terminal, and the Dispatcher marks the home-pickup seat Paid | The seat counts in B and is owed even if the passenger is not found. There is no payment screenshot and no gateway |
| T32 | The pickup is activated (a) when the Dispatcher marks the home-pickup seat Paid, (b) when the Dispatcher enters it by hand at the relative's request | `Status = 'Activated'`, `ActivatedBy`, and `ActivatedAt` stored in both cases. There is no QR scan and no `ActivationMode` |
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
| T41 | (a) A chat image larger than 10 MB (`ChatImageMaxKb` = 10240) is sent, (b) a chat image is older than `ChatImageRetentionDays`, (c) a relative sends a landmark photo of a home pickup | (a) **Refused.** (b) It is deleted, and `Messages.RetainUntil` is honoured. (c) Accepted within the limit, and `Assisted_Pickups.PhotoMessageID` points to the message. Neither the payment nor the activation depends on it |
| T42 | A second staff member signs in | `StartedBy`, `AssignedBy`, `ChangedBy`, and `RecordedBy` record that person. There is no shared account |
| T43 | The Cashier runs the setup check and checks a phone out to a Dispatcher and van | Open `Device_Checkouts` row, `Edge_Devices.Status = 'Checked_Out'`. Events from that phone match the trip of that van |
| T44 | The Dispatcher returns the phone and the Cashier records it | `ReturnedBy`, `ReturnedAt`, and `ReturnNote` set, `Status = 'In_Office'`. A second check-out of the same phone, or of the same van, while one is open is **refused** |
| T45 | The Cashier assigns a van and a Dispatcher while the Terminal Manager is off duty | Allowed (if the van's last trip is paid). `AssignedBy` is the Cashier, and the Terminal Manager gets an **'Assignment by Cashier'** alert and can change it |
| T46 | A door event arrives when the van has **no assigned trip** | It waits in the unassigned list, outside `Passenger_Events`, **'Trip Not Started'** is raised, and once a trip is assigned or started the event is matched to it by time. An event that arrives when the van **has** an assigned trip, even unstarted, goes to that trip |
| T47 | The van arrives. Aboard is still 2. Later the Dispatcher taps Arrived (or aboard reaches 0) | The trip stays open until then, then `CompletedAt` is set, `Status = 'Completed'`, and the **phone pauses**. It resumes at the van's next assignment |
| T48 | The van drives back to the terminal with paying passengers | **Nothing is recorded or audited.** No trip, no statement, no fare line |
| T49 | A walk-in passenger asks at the counter for the whole van. The Cashier enters the pickup, destination, passenger count, name, and contact, agrees a fee, and writes what it is based on | A `Special_Trip_Requests` row with `PassengerID` NULL, `CustomerName`, `CustomerContact`, `EnteredBy` = the Cashier, and `FeeNote`. The trip is created with `IsSpecial = TRUE` |
| T50 | A passenger requests a special trip in the app with 15 passengers | **Refused** (the limit is 14). With 14, the request is stored with `PassengerID` set and `EnteredBy` NULL |
| T51 | A special trip: the renter pays a rental fee of ₱2,000 (illustrative) in cash to the Dispatcher at the terminal, and the Dispatcher marks it paid and hands over the share | `RemittanceOwed` = ₱300.00. **Start is blocked** until the Cashier records the terminal fees (₱300.00 plus the ₱75.00 DCOTT ticket, and the day's ₱50.00 parking if not yet paid). The fee counts in B when the trip was requested in the app and in W when it was entered at the counter |
| T52 | The operator declines a far special trip. The Terminal Manager or the Cashier assigns another van | The first assignment is cleared, the new `AssignedVanID`, `AssignedBy`, and `AssignedAt` are stored, and the trip keeps `IsSpecial = TRUE`. [OPEN] Whether the first van keeps its place in the queue |

**Cash payment and unpaid reservations**

| # | Situation | Expected result |
|---|---|---|
| T53 | A passenger reserves a seat in the app | A `Bookings` row with a unique `BookingCode`, `PaymentStatus = 'Unpaid'`, and the seat counted toward the 14 of the trip. It is **not on the passenger list**. No payment screen and no QR ticket are offered |
| T54 | The passenger pays cash at the terminal. The Dispatcher finds the reservation (a) by name, (b) by booking code, and marks it Paid, once with a connection and once offline | `PaymentStatus = 'Paid'`, `PaidAt`, and `PaidBy` set. The seat is on the list and counts in B. The offline mark syncs when the connection returns |
| T55 | A reservation is still unpaid `UnpaidCutoffMin` minutes before departure | Released: `Status = 'Cancelled'`, `CancelReason = 'Auto_Release'`, `CancelledBy` NULL. The passenger is notified and the seat is free for a walk-up. A seat marked Paid is **never** released. The default cutoff is **30 minutes** (a setting) |
| T56 | A passenger forgot to cancel an unpaid reservation and did not come | The Dispatcher cancels it: `CancelReason = 'Forgot_To_Cancel'`, `CancelledBy` = the Dispatcher. Nothing is owed on it |
| T57 | A passenger with an **unpaid** reservation boards | An **unlisted** boarding (`'Unlisted'`, `ResolutionStatus = 'Pending'`) until the Dispatcher takes the cash and marks the seat Paid (`'Listed'`) or types a reason. Depart is held meanwhile |
| T58 | After the payment was recorded and the trip **has been started**, but before the van departs, the Dispatcher marks one more seat Paid | A top-up line (`IsTopUp = TRUE`) joins the **van's balance**. The van's next assignment is refused until it is paid, unless the Terminal Manager records a reason. Before Start (T7) it blocks Start instead |
| T59 | A boarding happens 10 minutes after the Dispatcher marked a seat Paid | Still **listed** (`'Matched_Booking'`): there is no matching window. Each seat or entry matches only one boarding |
| T60 | Review of the code base | No screen, endpoint, setting, or table field for an online payment or a QR ticket remains (Section 7.1) |
| T61 | An unpaid reservation whose passenger has checked in reaches the cutoff | **Released anyway.** A check-in does not hold the seat. Only the Dispatcher's Mark as Paid does |
| T62 | The Dispatcher, offline, marks a reservation Paid after the cutoff. The server released it before the mark synced, and the trip **still has a free seat** | The mark syncs and the reservation is **restored as Paid** (`Status = 'Confirmed'`, `PaidAt`, `PaidBy`, cancellation fields cleared), counts in B, and the passenger is notified |
| T63 | Same as T62, but a walk-up has taken the seat (14 counted) | The reservation is **not restored**. The Terminal Manager gets an alert (`'Paid After Release'` [ADVICE]) and resolves it with the Dispatcher and the passenger. Nothing is added to the amount owed until then |

**Terminal fees and the operator's share**

| # | Situation | Expected result |
|---|---|---|
| T64 | A van makes two trips on one service day | The ₱75 DCOTT ticket is charged for each trip (₱150.00) and the ₱50 parking **once**, on the day's statement |
| T65 | A van is parked at the terminal and has no trip. The Cashier records a parking-only charge | A statement with `ParkingFee = 50.00`, no trip and no fare line, and `OperatorShareOwed = 0.00`. It is `'Settled'` once the ₱50 is recorded. While unpaid it counts toward the van's balance for the assignment block [ASSUMED] |
| T66 | The Cashier taps Start with the 15 % recorded but the ₱75 DCOTT ticket not | **Blocked.** All terminal fees due must be recorded. Only the Terminal Manager overrides, with a written reason |
| T67 | The Dispatcher hands over the terminal fees and the operator's share, and the Cashier records both (sample: ₱342.50 and ₱1,107.50) | `SettledAmount = 342.50` and `OperatorShareGiven = 1,107.50`, with `OperatorShareGivenAt` and `OperatorShareRecordedBy` set. No flag |
| T68 | The Cashier records an operator's share of ₱1,000.00 instead of ₱1,107.50, after every trip's list on the statement is locked | The statement shows the **'Operator share differs'** flag (₱107.50 short). Nothing is blocked. [ASSUMED] The flag clears when the difference is recorded |
| T69 | A ₱80 walk-up seat is added after the payment is recorded and before Start | A ₱12.00 top-up blocks Start, ₱68.00 is added to the operator's share owed, and the ₱75 and ₱50 do not repeat |

---

## 13. Suggested order of work [ADVICE]

1. **Gap report**: repo vs this brief (roles, tables, screens, edge app, matching code). Wait for approval.
2. **Schema migration** (Sections 7.1 to 7.3), written as reversible migrations. Roles and renames first, then new tables (including `Edge_Devices`, `Device_Checkouts`, `Disputes`, `Non_Passenger_Moves`, `Assisted_Pickups`, `Messages`, `Timetable_Templates`, and `SosAlerts`), then the start, review, audit, departure, and payment columns. **Drop** the old estimate, side-pickup, and online-payment columns and screens (Section 7.1) only after asking. `Vans.OperatorID` becomes UNIQUE, so check the existing data for an operator on two vans before migrating.
3. **Settings and roster**: `TerminalSettings` keys (`UnpaidCutoffMin`, start window, heartbeat, terminal zone and departure readings, home pickup, chat images at 10 MB, `RetentionDays`), `Operators`, validation, import and export with preview (one van per operator), `Data_Transfers`, and the phone pool with check-out and return (`Edge_Devices`, `Device_Checkouts`).
4. **Trip lifecycle**: timetable → trips days ahead (and **special trips**, from an app request or a counter entry by the Terminal Manager or the Cashier, with the fee paid first), assignment at the van's turn (Terminal Manager, Cashier backup) with the **payment block** and the Terminal Manager's override, the **passenger list** (reservations with a booking code that the Dispatcher marks Paid, cancellation by the Dispatcher, release of unpaid reservations at the cutoff, Dispatcher cash entries with destinations, crew toggle), the Cashier's **payment record**, **Start** (blocked until the share is recorded), **Depart**, the **GPS departure fallback**, the **automatic start** (assigned van, then phone-detected van, 'Left Unpaid', held out of the statement), **'Not a passenger trip'**, void and change-van (Terminal Manager only), alerts.
5. **Edge ingestion API**: authenticated event upload with `DeviceID`, offline-tolerant, idempotent, with heartbeat into `Edge_Devices` (including stored reports sent after a reconnect); the Unaudited check (`'No_Phone'` too). Then the Android edge app (Section 5), which pauses at arrival and resumes at the next assignment.
6. **Checking, hash chain (with `SnapshotHash`), pre-departure comparison (aboard against listed, fix or reason), capacity alert, and remittance computation** (`ρ × (B + W)`, the ₱75 and ₱50 fees, the operator's share and its flag, top-ups, held share, disputed share), then the **home pickup** (booking, pin check, activation by marking the seat Paid, wait, landmark photo) and the **dispute record and decision** (`Disputes`). Run the Section 12 acceptance tests.
7. **Retention job** (Section 4.5) after the hash chain works, so test T39 can run. It skips trips with an open dispute or an unreviewed flag, and it also covers chat images.
8. **NAHGM and driving flags** against `Nahgm_tracking_logs`, with the general location of each alert and the home-pickup wait subtracted.
9. **Screens**: Dispatcher Dashboard (Mark as Paid, Cancel Reservation), the passenger reservation screens with the booking code, Start Trip, Review Automatic Starts, Boarding Audit, Remittance, Van Status Board, Phones, Disputes, Member Records, Rules and Settings, Special Trips, Book for Someone Else, Messages.
10. **Pilot checks**: full-trip phone benchmark (fps, temperature, battery, uptime) before any figure is stated, and the site survey for the terminal zone radius and N.

---

## 14. Open items to confirm with A2Z or decide in the group

- Capacity: confirm the **franchise capacity** of A2Z's units with LTFRB Region XI (an LTFRB reminder lists UV Express at 9, 10, or 12 including the driver, or the manufacturer's specification). 14 is A2Z's cap.
- Whether en-route loading is still treated as a franchise breach (reference [11]).
- **Roadside loading just outside the terminal zone** is not flagged or priced (disclosed limitation). Confirm that A2Z accepts it.
- **Fixed-route boarding:** that passengers board only at the starting terminal before departure, and that the passenger list is complete before the van leaves.
- **Special trips:** the assumptions in Section 2.5. Confirm **what the fee is based on** (the group's answer was garbled, so it was read as a fee agreed on the spot by pickup and destination), **whether the Cashier may agree it** (separation of duties), **whether a van that declines a far special trip keeps its queue place**, that the fee is **paid in cash to the Dispatcher at the terminal before the van leaves** and the 15 % is handed to the Cashier and recorded before Start, and whether a Dispatcher rides on a rented van.
- **Home pickup:** the 10-minute wait, the maximum distance of the pin from the route, the chat image retention period (the group gave 10 MB, and 30 days is assumed), and the line in the privacy notice. Confirm that the relative pays both seats in cash at the terminal and that marking the home-pickup seat Paid is what activates the pickup.
- **Trip start and assignment:** the 30-minute window, that A2Z assigns a van and a Dispatcher to each departure at the van's turn, that the Cashier may assign when the Terminal Manager is off duty, and that the Cashier has time to start trips at the counter in peak hours.
- **Terminal zone and GPS departure:** the **radius of the terminal zone** and **N consecutive readings** from a **site survey** of the queue and loading area.
- **Payment block:** that the Terminal Manager alone overrides, with a written reason, and that **one override covers both** the Start block and the assignment block.
- **Remittance timing:** that the Dispatcher hands the terminal fees due to the Cashier before Start (the 15 % of the paid seats on the list, the ₱75 DCOTT ticket for each trip, and the ₱50 parking for each van each day, even with no trip), that the operator's share is handed to the operator at the counter and recorded by the Cashier [DECIDED 2026-11-02; confirm with A2Z, including whether the ₱75 applies to a special trip and whether the operator signs], and what happens when a van does not depart again, when an owner stops operating, or when a trip whose payment was recorded is voided (Section 2.1).
- **Held trips:** that an auto-started trip is held out of the statement until reviewed while its unpaid share counts toward the van's balance.
- **Independent trips are special trips** [DECIDED]. Still open: the **'Not a passenger trip'** reasons list.
- **Edge phone and custody:** exact model, Android version, RAM, and processor. How many phones A2Z needs, and when a phone that has not come back counts as missing. The silent-phone gap (placeholder 120 s). Whether A2Z allows a camera in the cabin.
- **Evidence retention:** the group chose **fixed days** and gave **30 days**. Confirm 30 days with A2Z and that **only the Terminal Manager** may view the blurred snapshots. **A2Z's data privacy contact is not yet named**: keep the placeholder `[name and position to be supplied by A2Z]` until A2Z supplies it, and confirm the sign in each van and the notice on the booking screen.
- **Disputes:** that an operator can contest only a fare line or a driving flag at the counter, that a fare line can be contested only until the payment is recorded, that the operator pays the undisputed part meanwhile, that only the Terminal Manager decides, and whether a second person should review a dispute over the Terminal Manager's own decision. Passenger complaints and refunds are not covered.
- **One login per staff member** (needed because `StartedBy`, `AssignedBy`, `ChangedBy`, and `RecordedBy` name a person).
- **Hash chain** hardening: device-side signing in the Keystore, and whether starts, voids, overrides, and 'Not a passenger trip' join the chain (would be Table 45).
- **Dispatcher sign-in:** phone number or email.
- **Operators:** the paper assumes **one van per operator** and that the owner always drives. Confirm that no A2Z member owns several vans, and what happens when someone else drives (a substitute).
- **Unpaid reservations [DECIDED 2026-11-02]:** `UnpaidCutoffMin` defaults to 30 minutes (confirm in the pilot), a check-in does not hold the seat, and an offline Paid mark after the release restores the seat if it is still free, otherwise the Terminal Manager is alerted (Section 2.1).
- **Cash only [DECIDED]:** the A2Z manager said that A2Z handles only cash, so passengers reserve in the app and pay at the terminal. Confirm with A2Z that this holds for special trips and home pickups as well.
- **Member records:** which fields the binder really holds (operators: name, contact, email, license number and expiry; vans: plate, CPC case number and number, model, color, route). Whether both the Terminal Manager and the Cashier may import and export.
- **Export for LTFRB:** which fields and file format LTFRB Region XI needs.
- Replace every **illustrative value** (stop coordinates, limits, fares, expected speed, stop-zone radius, unpaid cutoff, flag thresholds) with surveyed ones, and rerun the sample script and tests.
- **Wording to confirm with the group:** the group asked that a Dispatcher who "forgot to click Start" be covered by a fallback. The paper keeps **Start** as the counter step (Cashier or Terminal Manager) and gives the **Dispatcher the Depart tap**, so the fallback is the **GPS departure plus the automatic start**. Confirm that mapping.
- **Figures the group must still redraw or replace by hand** (Figure 6, the remittance flow, is already redrawn in the paper):
  - **ERD (Figure 8):** `Edge_Devices` one-to-many to `Device_Checkouts` and to `Passenger_Events`; `Device_Checkouts` many-to-one to `Vans`, `Dispatchers`, and `TerminalStaff` (twice: check-out and return); `Disputes` many-to-one to `Remittances`, `TripSchedules`, and `TerminalStaff` (`DecidedBy`), and optionally to `Remittance_Lines` and `Driving_Events`; `Non_Passenger_Moves` (Table 40) many-to-one to `Vans`, `Edge_Devices`, `Dispatchers`, and `TripSchedules`; `Assisted_Pickups` (Table 41) many-to-one to `Bookings` (twice), `TripSchedules`, `Dispatchers`, and `Messages`; `Vans.OperatorID` one-to-one with `Operators`; the new columns of `TripSchedules` (`StartMode`, `StartedBy`, `AssignedBy`, `AssignedAt`, `StartReviewStatus`, `AuditStatus`, `CompletedAt`, `PaymentOverrideBy`, `PaymentOverrideAt`, `PaymentOverrideNote`, `PaymentStatus`, `ListLockedAt`, `CrewAboard`, `DepartureSource`), of `Passenger_Events` (`DeviceID`, `SnapshotHash`, `SnapshotDeletedAt`, `PreDeparture`), and of `Remittances` (`HeldShare`, `HandedOverBy`, `DcottFees`, `ParkingFee`, `TerminalFeesOwed`, `OperatorShareOwed`, `OperatorShareGiven`, `OperatorShareGivenAt`, and `OperatorShareRecordedBy`, the last many-to-one to `TerminalStaff`); and remove `EstimatedIncome` and `AmountAtRisk` from `Remittances`, `SidePickup`, `DestStopID`, and `EstimatedFare` from `Passenger_Events`, and the `'Estimated'` value from `Remittance_Lines`. Also leave out the payment-gateway fields (`Bookings.PaymentReference`, `Operators.PayoutRef`), show the new `Bookings` fields (`BookingCode`, `PaidAt`, `PaidBy`, `CancelledBy`, `CancelReason`), and add the tables `Messages`, `Timetable_Templates`, and `SosAlerts` (Tables 42 to 44).
  - **Figure 4:** relabel the phases as in Section 6.2 (pre-departure comparison against the list, no priced estimates, matching to seats marked as paid and walk-up entries).
  - **Scrum sprint plan (Figures 1 and 2).**
  - **Prototype screenshots** of Figures 13 and 14 (reservation with the pay-at-terminal notice, and booking code with payment status) and Figure 16 (the Dispatcher dashboard with Mark as Paid and Cancel Reservation), and the data dictionary rows listed under the next bullet.
- **Leftovers in the paper's Google Doc (text the group fixes by hand; follow this brief until then):**
  - Table 16 (`Bookings`): the `PaidAt` description still says "which the matching window uses", and the `CancelledAt` wording needs a check.
  - Table 21 (`LogBookEntries`): the introduction still mentions the matching window.
  - Table 29 (`Passenger_Events`): `MatchStatus` still says "within the matching window".
  - Table 32 (`Remittances`): add `DcottFees`, `ParkingFee`, `TerminalFeesOwed`, `OperatorShareOwed`, `OperatorShareGiven`, `OperatorShareGivenAt`, and `OperatorShareRecordedBy`.
  - Table 33 (`TerminalSettings`): still lists `'MatchWindowS'`, and needs `'DcottTicketFee'` and `'ParkingFee'`.
  - Table 10 itself (header and total still show only the 15 percent remittance, ₱217.50), the Figure 6 flowchart and its caption, and the screen text of Figure 23 (Fares and Cash) and Figure 27 (Rules and Settings) still show only the 15 percent. The paper's running text now describes the terminal fees and the operator's share, but Equation (2) is still the only numbered equation; the terminal fees and the operator's share are written in prose.
  - Table 34 (`Special_Trip_Requests`): `PaymentStatus` still says "counter of the Cashier", and `PaidAt` still says "the Cashier or the Terminal Manager recorded". The Dispatcher takes the cash and marks it paid.
  - Notifications: the type 'Home Pickup Proof' (now 'Home Pickup Photo').
  - Figure 6 caption ("Under the Operator-Collects Payment Mode"), Figure 17 text (Trust Rating), and Figure 27 text (cancellation deadline and refund policy).
  - Table 2: a stray comma in the Dispatcher cell ("no-show, (1.3.2.1)").
  - Tables 14 to 44 and Figures 10 to 27 are not yet mentioned in the running text.
- **Design risks to watch:**
  - A phone that changes vans needs the **door line and seat mask re-aligned** at every mounting (Section 5.5).
  - Door events that match no assigned trip are held at the server, and **the data dictionary does not model that list**.
  - `Remittances` has **one `SettlementRef` field** that joins the references of several payments.
  - **One open check-out per phone and per van** is enforced by the application, not by the paper's schema.
  - Disputes after the payment is recorded are out of scope, and the Terminal Manager may decide a dispute over their own decision.
  - Because **GPS auto-start is never blocked**, a van can leave unpaid. The control is the held trip and the refused next assignment, not a physical stop.
  - **A roadside pickup after the van leaves the zone is not audited.**
  - A reservation can be **released while the Dispatcher is offline**. The decided rule restores the seat if it is still free and alerts the Terminal Manager if a walk-up took it, so a cash fare can still end in a dispute at the counter. The paper's data dictionary does not model this yet.

---

## 15. Terminology and writing conventions

- **A2Z** (not "the co-op" or "the cooperative"). Full name once: "A2Z Transport Cooperative Van Terminal".
- **Dispatcher** (not Conductor), **Terminal Manager** (not Cooperative Administrator or Operator), **Cashier**, **operator** (lower case, the van owner and driver, not a user), **passengers** (not commuters).
- **stop, stretch, distance from the starting terminal, stop zone** (not node, segment, chainage, geofence). The NAHGM expansion, "Node-Aligned Haversine Geofenced Monitoring", stays as it is.
- **pasabay**: a passenger who walks up and rides without a reservation (the Dispatcher lists the person with a destination before the van leaves).
- In documentation and comments: no promotional adjectives, and avoid "propose", "proposal", "proponents". State only what the code or the paper does.
- Do not state a frame rate, accuracy, or uptime figure for the edge phone until it has been measured.
- **remittance** is the paper's word for the **15 % dispatching fee** that A2Z's trip ticket calls "Disp. Fee". **Terminal fees** are the remittance, the ₱75 **DCOTT ticket**, and the ₱50 **parking fee**. The **operator's share** is the cash on the list less the terminal fees (not "the 85 %").
