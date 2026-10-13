# SabayGo: Change Brief for Claude Code

Last updated: 2026-10-13. Matches the paper draft "SabayGo Paper Revision: Replacement Sections", revision 468.

**Changed since the previous version of this brief (revision 416):** (1) the in-van phones are a **pool kept in the office of the Cashier and the Terminal Manager**, and a phone goes out **only with a Dispatcher**, for a van in the terminal's queue and for an independent van alike (Section 5.5); (2) `Edge_Devices` (Table 37) no longer holds `VanID`, and the new **`Device_Checkouts` (Table 38)** records which Dispatcher took which phone to which van and when it came back; (3) the Terminal Manager adds phones to the pool, and the Terminal Manager **or the Cashier** checks them out and in after a setup check; (4) a van with **no phone out** runs **Unaudited** with the new reason `'No_Phone'`; (5) the **Unaudited Trip** alert also goes to the **Cashier**; (6) en-route silence is final only if the phone's **stored reports** do not cover the gap (Section 4.4); (7) new **`Disputes` (Table 39)**: the operator can contest an estimated fare, a fare line, or a driving flag at the counter before full payment, pays the undisputed part, and only the Terminal Manager decides (Section 2.1); (8) there is **no duty roster**: the Cashier's assignment always works, is stored in `AssignedBy`, and alerts the Terminal Manager; (9) **Completed** and the events between two trips are now decided (Sections 4.1 and 4.2); (10) tables are now **25 to 39**, and a start/void log table, if it is ever added, would be **Table 40**.

**Earlier changes (revision 355 to 416):** (1) trips are created from the timetable **days ahead**, and there is **no "usual van"**: the Terminal Manager assigns the van and the Dispatcher at the van's turn (Section 4.2); (2) the Cashier can make that assignment when the Terminal Manager is off duty; (3) manual Start needs both a van and a Dispatcher; (4) the automatic start uses the assigned van, or the van whose phone detects the departure, and the trip is **held out of the statement** until the Terminal Manager reviews it; (5) a trip whose phone is off, covered, or silent is marked **Unaudited** and service is not blocked (Section 4.4); (6) new table **`Edge_Devices` (Table 37)**, redefined above as the phone pool; (7) **one van per operator**; (8) one **retention setting** for snapshots and GPS logs, with a snapshot-hash safeguard (Section 4.5); (9) the Dispatcher can scan and log on a scheduled trip before it is started.

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
| Purpose | Booking and fleet management with a headcount check against the manifest | **Revenue audit**: A2Z gets **15 % of each van's gross fares daily**, and the system finds fares that never entered the record |
| Capacity | 14 seats, per route segment | **Strictly 14 passengers per van** (A2Z's operating rule), checked by the door camera as well as by booking |
| Detection | Headcount at one moment, compared with the manifest | **Door events**: each boarding and alighting is detected, timed, and placed on the route, then **matched** to a QR scan or a Dispatcher's cash log |
| NAHGM | Greedy segment matching and live passenger ETA | **Node-Aligned Haversine Geofenced Monitoring**: geometry only. Tags each door event and driving flag with time and place. Passenger live position and ETA are no longer in scope |
| Driving | Not covered | Flags for **overspeed, slow stretch, unscheduled stop** (and an en-route stop record) |
| Evidence | None | **SHA-256 hash chain** over each trip's door events (evidence-based non-repudiation) |
| Roles | Passenger, Conductor, Operator, Driver | **Passenger, Dispatcher, Terminal Manager, Cashier**. The Conductor is now the **Dispatcher**. The Operator and the Driver are **not users** |
| Operator | A user | The **van owner, who always drives**. An A2Z member but an independent contractor. One roster record, **no account** |
| Edge node | Orange Pi 5 or Raspberry Pi 4 with a USB webcam | A **pool of dedicated Realme 5G Android phones**, kept in the office and taken out by a Dispatcher, that supply the camera, GPS, processor, and mobile data |
| Boarding rule | Not defined | Fixed-route boarding **only inside a terminal stop zone before departure**. Anything else is a **side pickup** (flagged, fare still counted) |
| New features | | Special trips (rent the whole van), member roster with import and export, van status board, daily remittance statement and Cashier settlement, van and Dispatcher assignment at the van's turn, trip start by Cashier or Terminal Manager with an automatic fallback, an Unaudited flag for trips without camera evidence, a retention setting for snapshots and GPS logs, phone check-out and return, operator disputes |
| Writing terms | node, segment, chainage, geofence | **stop, stretch, distance from the starting terminal, stop zone** |

---

## 2. Business rules [PAPER unless tagged]

### 2.1 Money
- The operator collects fares and **remits 15 % of gross fares to A2Z each day**. The system **does not hold or move money**. It records how each fare was paid, computes the remittance, and lets the Cashier record the payment.
- Rate is `ρ = 0.15`, a **dated, configurable** setting. A change applies only to later days (`TerminalSettings.EffectiveFrom`).
- Income is sorted into three groups by how well the evidence backs the fare:
  - **Verified (V)**: paid through the payment gateway or by QR ticket.
  - **Declared (D)**: cash fares that the Dispatcher logged in the manifest.
  - **Estimated (U)**: fares of boardings the camera found with no scan and no log, priced from the fare table.
- **Equation (2):**
  ```
  Remittance owed                          = ρ × (V + D)
  Amount at risk                           = ρ × U
  Remittance if all estimates are confirmed = ρ × (V + D + U)
  ```
- The Terminal Manager decides each estimate. **Confirmed**: it moves from estimated to **declared** and raises the remittance owed by ρ × its fare. **Dismissed** (for example a misdetection): it leaves the amount at risk. Both decisions are logged with the user and the time.
- Settlement is **daily, per van**. The Cashier shows or prints the statement for the operator, receives the confirmed amount, and records the payment against its fare lines with a reference number and date. [ASSUMED] One payment per van per day against all lines, not one per trip.
- **Held lines [DECIDED].** A trip that the system started without confirmation (`StartReviewStatus = 'Pending'`) is **left out of the statement** until the Terminal Manager reviews it. Its fare lines are created after the review. [ASSUMED] If lines are added to a statement that is **already paid**, the statement is **reopened** (`Status` back to `'Open'`) and **only the difference between `RemittanceOwed` and `SettledAmount` is due**. Confirm with A2Z and the Cashier. The later payment is **added to `SettledAmount`** and its reference is **appended to `SettlementRef`** (one payment slot per statement, a known limitation).
- **Unaudited trips [DECIDED].** A trip with no camera evidence (Section 4.4) counts only its QR tickets and logged fares. It has no estimated income, and the statement **shows it as unaudited** so that A2Z can see how much of the day's remittance was not checked.
- **Disputes [DECIDED].** The operator has no account, so a dispute is raised **at the counter, before the statement is fully paid**, while the operator checks the statement. The Dispatcher, the Cashier, or the Terminal Manager records it with the operator's own statement (`Disputes`, Table 39).
  - **Scope:** an **estimated fare**, a **fare line**, or a **driving flag**.
  - **Money:** the operator **pays the undisputed part**, and the **disputed share (ρ × the item's fare) waits**. The statement shows it separately. A driving flag withholds nothing (`AmountDisputed = 0.00`).
  - **Decision:** **only the Terminal Manager decides**, with a written note, logged with who and when. **Upheld**: the item leaves the amount owed. **Rejected**: the share becomes due. **Adjusted**: the Terminal Manager sets the share that is due (`AdjustedAmount`). **Withdrawn**: the operator drops it and the share becomes due.
  - **Evidence:** snapshots and GPS logs of the trip are kept while the dispute is open (Section 4.5).
  - **Not covered:** a contest **after the statement is fully paid** [ASSUMED], passenger complaints, and refunds. The Terminal Manager may decide a dispute over their own earlier decision, because there is no third role (limitation in the paper).
  - **Example (sample trip, Section 12.1):** E13 and E14 are confirmed, so the remittance owed is ₱216.00. The operator contests E14 (₱75 fare, ₱11.25 share). Due now: **₱204.75**. If **Upheld**, the remittance owed is ₱204.75 and the payment settles it. If **Rejected**, the ₱11.25 becomes due.
- Gateway payments settle to the operator's payout account [ASSUMED]. Gateway example: GCash through PayMongo.

### 2.2 Fare lines
A fare line groups passengers who **boarded at the same terminal, got off at the same terminal, and paid the same fare**, per trip. Fares come from `Fare_Matrix` (terminal-to-terminal, with `EffectiveFrom`). A special-trip rental fee is also a line.

### 2.3 Capacity
- Aboard now = aboard at departure + boardings − alightings since then.
- When aboard rises **above 14**, raise a **capacity alert** carrying the time and the place on the route.
- Booking also holds each van to 14 (row-level locking in MySQL).

### 2.4 Boarding rule and side pickups
- **Fixed-route trip:** boarding is allowed only when it happens **inside a stop zone, before the van departs**. This holds whether the passenger has a QR ticket or walks up and pays cash to the Dispatcher.
- A boarding **outside every stop zone** is a **side pickup**. Flag it with time, place, and the blurred snapshot, and alert the **Dispatcher and the Terminal Manager**.
- The side-pickup flag is **separate from matching**: a side pickup with a QR scan or Dispatcher entry is still recorded, and one without is still an unrecorded boarding with an estimated fare. The remittance is computed as before.
- **Special trips are exempt** from this rule.
- [ASSUMED] Boarding is allowed at intermediate terminals. A2Z only flags a side pickup and does not penalize it.

### 2.5 Special trips
- A passenger **rents the whole van** and is picked up at a chosen location. It is the only trip type that allows pickup outside a terminal.
- The passenger requests it in the app (date and time, pickup, destination, passenger count, **at most 14**). The **Terminal Manager** reviews it, sets the rental fee, and **assigns a van and a Dispatcher**. The passenger pays through the gateway, or pays cash to the Dispatcher, who logs it.
- It has no fixed route, no stop zones, and no terminal-to-terminal fare. The camera still counts people and raises the capacity alert. GPS is still stored. Overspeed uses a **default limit** set by the Terminal Manager (`SpecialTripSpeedKmh`).
- The fee enters the van's gross fares for the day (verified if paid by gateway, declared if the Dispatcher logs cash), so the 15 % covers it.
- [ASSUMED] A Dispatcher rides on a rented van. Confirm with A2Z.

---

## 3. Roles and permissions [DECIDED / PAPER]

Four roles only. Do **not** build screens, accounts, or tables for an Operator user or a Driver user.

| Capability | Passenger | Dispatcher | Terminal Manager | Cashier |
|---|:--:|:--:|:--:|:--:|
| Find route and schedule, reserve a seat, pay, get QR ticket, check in | ✔ | | | |
| Request a special trip, pay the rental fee | ✔ | | | |
| Receive booking, delay, cancellation, boarding notifications | ✔ | | | |
| Scan QR tickets at boarding (also on the **scheduled** trip before it is started, once the Dispatcher is assigned) | | ✔ | | |
| Log cash pasabay fares in the manifest (works **offline**, also before the start) | | ✔ | | |
| Confirm the van's plate number against the van, at the door | | ✔ | | |
| Alerts: 15th person, unlogged boarding, side pickup, driving flags | | ✔ | ✔ | |
| Alert: **Unaudited Trip** (phone off, covered, silent, or not taken out) [DECIDED] | | ✔ | ✔ | ✔ |
| Alert: **Assignment by Cashier** (the Cashier assigned a van and a Dispatcher) | | | ✔ | |
| Attach the operator's explanation to an estimated fare | | ✔ | | |
| **Assign a van and a Dispatcher** to the next departure at the van's turn | | | ✔ | ✔ **only when the Terminal Manager is off duty**. The action always works, is stored in `AssignedBy`, and alerts the Terminal Manager [DECIDED; no duty roster]  |
| **Start a trip** (confirm or change the **assigned** van) | | | ✔ | ✔ |
| **Void a started trip or change its van** | | | **✔ only** | |
| Review trips the system had to start without confirmation, and trips that went Unaudited | | | ✔ | |
| Validate operator, dispatcher, and van records | | | ✔ | |
| **Add a phone to the pool** (`Edge_Devices`) | | | ✔ **only** [DECIDED] | |
| **Check a phone out** (after the setup check) to a Dispatcher and van, and **receive it back** (`Device_Checkouts`) | | | ✔ | ✔ |
| **Collect a phone from the office, mount it in the van's holder, and return it** | | ✔ | | |
| **Record an operator's dispute** (`Disputes`) | | ✔ | ✔ | ✔ |
| **Decide a dispute** (Upheld, Rejected, Adjusted) | | | **✔ only** | |
| Approve special trips, set the rental fee, assign van and Dispatcher | | | ✔ | |
| Decide on estimated fares (confirm or dismiss) | | | ✔ | |
| Set rate, fares, speed limits, **retention of snapshots and GPS logs**, other rules | | | ✔ | |
| Fleet screens: capacity alerts, boarding audit, driving flags | | | ✔ | |
| Van status board (on site, travelling, not on a trip, out of service) | | | ✔ | ✔ |
| Import and export member records | | | ✔ | ✔ |
| Show or print the daily statement for the operator | | | | ✔ |
| Receive the 15 % and record the payment | | | | ✔ |

**Separation of duties [PAPER]:** the person who records a payment (Cashier) does not decide what is owed (Terminal Manager), and the Cashier cannot erase a trip. The person who encodes an imported record is not the only one who approves it.

**One login per staff member [ASSUMED]:** `StartedBy`, `AssignedBy`, `ChangedBy`, and `StartReviewedBy` name a person, so there must be **no shared Cashier or Terminal Manager account**.

**Operator [DECIDED]:** the van owner who also drives. Roster record only (name, license number and expiry, contact, optional email, payout reference). **One van per operator.** The operator **arranges in person with the Terminal Manager and the Cashier which trips the van takes**. No login, no app screens. A substitute driver and an owner of several vans are **not supported** (limitation in the paper).

**Dispatcher [PAPER]:** an A2Z staff member whom the Terminal Manager assigns to the van's **departure at its turn** (the Cashier does so when the Terminal Manager is off duty), and who **rides in the van**. The Dispatcher uses the mobile app on **their own phone**, which is **not** the edge phone. The Dispatcher also **collects the edge phone from the office, mounts it in the van's holder, keeps it for the day's trips, and returns it** (Section 5.5).

---

## 4. Trip lifecycle, assignment, and start rule [DECIDED; the values are ASSUMED]

The group chose **rotation by turn** and a **hybrid start**: trips are created automatically from the timetable **days ahead** (passengers book seats on them), the **Terminal Manager assigns the van and a Dispatcher** to the next departure when the van's turn comes, a **Cashier or Terminal Manager confirms the start**, and a **fallback** starts any trip that nobody started. There is **no "usual van"** in the timetable.

### 4.1 Status flow (`TripSchedules.Status`)
```
Scheduled ──start──▶ Boarding ──depart──▶ En Route ──arrive──▶ Completed
    │                    │
    └──── void (Terminal Manager only) ────▶ Cancelled
```
- **Scheduled**: created from the timetable. `AssignedVanID` and `DispatcherID` are **NULL until they are assigned at the van's turn**. Bookings attach to the trip from the day it is created.
- **Boarding**: the trip has been started.
- **En Route**: the van has departed.
- **Completed** [DECIDED]: the trip stays open after the van arrives until the **number aboard is 0 or the Dispatcher taps Arrived**. `CompletedAt` is set then and `Status` becomes `'Completed'`.
- **Cancelled**: voided by the Terminal Manager, or cancelled.

### 4.2 Rules
1. **Creation.** The server creates trips from the timetable (`Timetable_Templates`, Section 7.4) **ahead of time** (see `AdvanceBookingDays`), not "the day's trips" only. The timetable stores route, time, and operating days. It does **not** store a van or a Dispatcher.
2. **Assignment at the van's turn [DECIDED].** When a van's turn comes at the terminal, the **Terminal Manager assigns the van and a Dispatcher to the next departure**. The **Cashier can do this when the Terminal Manager is off duty**. Store `AssignedBy` and `AssignedAt`. When the Cashier assigns, send the Terminal Manager an **'Assignment by Cashier'** alert; the Terminal Manager can change the assignment. There is **no on-duty toggle and no duty roster** [DECIDED]. Only **validated** vans and Dispatchers can be assigned.
3. **Scanning before the start [DECIDED].** Once the Dispatcher is assigned, the Dispatcher can **scan QR tickets and log cash fares on the scheduled trip**. A late start never blocks boarding.
4. **Start window.** The **Start** action appears a set time before departure. Setting `StartOpensMin`, **assumed 30**.
5. **Manual start [DECIDED].** The **Cashier or the Terminal Manager** confirms or changes the **assigned** van (from the validated vans) and taps **Start**. **Manual Start is blocked until both a van and a Dispatcher are assigned.** The system shows the van's plate number and operator, then **copies the operator's name, license number, and the van's plate number onto the trip** (so the trip record stays fixed if the roster changes later). An **expired license raises a warning** to the starter and to the Terminal Manager. It does not block the start [ASSUMED]. If the van that is confirmed is **not the van that the sending phone is checked out to** (its open `Device_Checkouts` row), **warn the starter**. Do not block. If **no phone is out with the van**, also warn (the trip will be Unaudited, Section 4.4).
6. **Not on the roster.** A van or operator that is not on the roster, or not validated, **cannot be picked**. The Terminal Manager adds and validates the record first.
7. **Automatic fallback [DECIDED].** If nobody has started a trip by **departure time + `StartGraceMin`** (assumed **10 minutes**), **or** by the time the van **leaves the terminal** (leaves the origin stop zone with at least one boarding counted), whichever is first, the **system starts the trip itself**:
   - with the **assigned van**, `StartMode = 'Auto_Assigned'`; or, if no van was assigned, with the **van whose phone detects the departure**, `StartMode = 'Auto_Detected'`;
   - `StartedBy` stays NULL, `StartReviewStatus = 'Pending'`, and the Terminal Manager gets an **'Unconfirmed Trip Start'** alert;
   - if **no Dispatcher** was assigned, the trip still starts but is **flagged "No Dispatcher"** (`DispatcherID` is NULL) for review;
   - if there is **neither an assigned van nor a detected van**, raise a **'Trip Not Started'** alert and leave the trip **open** for the Terminal Manager.
   The operator named on an automatic start is only an assumption until the Terminal Manager reviews it.
8. **Hold and review [DECIDED].** A trip with `StartReviewStatus = 'Pending'` is **left out of the daily statement**. When the Terminal Manager reviews it (confirms or changes the van), set `'Reviewed'`, `StartReviewedBy`, `StartReviewedAt`, and create its fare lines. If the statement is already paid, see the reopen rule in Section 2.1 [ASSUMED].
9. **Departure.** The trip moves to En Route when the Cashier or Terminal Manager taps **Depart**, **or** when the phone's GPS shows the van **leaving the terminal's stop zone with at least one boarding counted**, whichever is first. Store `DepartedAt` and `DepartureSource` (`'Confirmed'` or `'Detected'`).
10. **No silent edits [DECIDED].** A started trip is **not edited quietly**. **Only the Terminal Manager** can void it or change its van. Each start, void, and change is stored with **who, when, and why** (the earlier van and operator are kept in `ChangeNote`). The **hash chain stays on door events only**. Do not add a start/void log table without asking.
11. **The edge phone does not start and stop with the trip.** It stays open and keeps counting **from the setup check at check-out until it is returned**. A trip start is only a **server record** that says which trip the door events belong to. Every event carries the sending phone's `DeviceID`. The server finds that phone's van from its **open `Device_Checkouts` row** (`ReturnedAt IS NULL`) and **matches the event to the trip of that van, by time**, even if the start is late or missed.
12. **Events between trips [DECIDED].** A door event that arrives when the van has **no open trip** goes to the van's **next scheduled trip** if the event falls **inside that trip's start window** (`StartOpensMin` before departure). Otherwise it **waits in an unassigned list held at the server intake, outside the ledger** (`Passenger_Events.ScheduleID` is NOT NULL, so it cannot be stored there yet), and the system raises **'Trip Not Started'**. When the trip is started, match the waiting events to it by time. The paper does not model the waiting list in the data dictionary (Section 7.4).

### 4.3 Columns this adds or changes in `TripSchedules` [PAPER, working note]
| Column | Type | Meaning |
|---|---|---|
| `AssignedVanID` | FK NULL | NULL until a van is assigned at its turn (or, on a special trip, until the Terminal Manager assigns one) |
| `DispatcherID` | FK NULL (renamed from `ConductorID`) | NULL until assigned. An automatic start with NULL is flagged "No Dispatcher" |
| `AssignedBy` | VARCHAR(32) FK NULL → TerminalStaff | Who assigned the van and the Dispatcher (Terminal Manager, or Cashier when the manager is off duty). Replaces the old `DispatcherAssignedBy` |
| `AssignedAt` | DATETIME NULL | Replaces the old `DispatcherAssignedAt` |
| `StartMode` | ENUM('Manual','Auto_Assigned','Auto_Detected') NULL | How the trip was started. **Replaces `'Auto_Unconfirmed'`** |
| `StartedBy` | VARCHAR(32) FK NULL → TerminalStaff | NULL when the system started it |
| `StartedAt` | DATETIME NULL | |
| `StartReviewStatus` | ENUM('Not_Required','Pending','Reviewed') NOT NULL DEFAULT 'Not_Required' | `'Pending'` for an automatic start. A Pending trip is left out of the statement |
| `StartReviewedBy` | VARCHAR(32) FK NULL → TerminalStaff | |
| `StartReviewedAt` | DATETIME NULL | |
| `AuditStatus` | ENUM('Audited','Unaudited') NOT NULL DEFAULT 'Audited' | `'Unaudited'` when the phone gave no camera evidence (Section 4.4) |
| `UnauditedAt` | DATETIME NULL | When the trip became unaudited |
| `UnauditedReason` | ENUM('No_Phone','Silent_At_Start','Lost_En_Route','Lens_Blocked') NULL | `'No_Phone'`: no phone was out with the van |
| `DepartedAt` | DATETIME NULL | |
| `DepartureSource` | ENUM('Confirmed','Detected') NULL | |
| `CompletedAt` | DATETIME NULL | When the number aboard fell to 0 at the destination or the Dispatcher tapped Arrived |
| `ChangedBy` | VARCHAR(32) FK NULL → TerminalStaff | Terminal Manager who voided or changed the van |
| `ChangedAt` | DATETIME NULL | |
| `ChangeNote` | VARCHAR(255) NULL | Reason, plus the earlier van and operator. A void sets `Status = 'Cancelled'` |

### 4.4 Phone status and Unaudited trips [DECIDED]
- The phone sends a **status report (heartbeat)** that updates its `Edge_Devices` row (`LastHeartbeatAt`, `BatteryPct`, `BatteryTempC`, `CameraOk`, `GpsOk`). The server counts the phone as **silent** when no report arrives within `HeartbeatGapS`, **placeholder 120 s** [ASSUMED]. Keep it a setting. The phone **stores its reports while it is offline and sends them after it reconnects**.
- **At Start:** if **no phone is out with the van** (for example a van that goes out without a Dispatcher), or the phone is silent, or its camera or GPS is not working, **warn the person who starts the trip**, **start the trip anyway**, set `AuditStatus = 'Unaudited'` **immediately** (`UnauditedReason = 'No_Phone'`, `'Silent_At_Start'`, or `'Lens_Blocked'` when the camera is covered), and send an **'Unaudited Trip'** alert to the **Terminal Manager, the Cashier, and the Dispatcher** [DECIDED].
- **During the trip:** if the phone goes silent, send the alert **at once**, but make the Unaudited mark **final only if the reports the phone stores and sends after it reconnects do not show the camera and GPS working through the gap** (a gap in mobile data coverage is not a camera that is switched off). If those reports cover the gap, clear it. If they do not, mark the trip Unaudited **from the start of the gap** (`UnauditedAt`, `'Lost_En_Route'`). A **covered lens** is marked at once (`'Lens_Blocked'`). [ADVICE] Hold a provisional flag until the stored reports arrive or the trip ends.
- **Never block the service.**
- An Unaudited trip is **not checked against the camera**. The statement counts only its QR tickets and logged fares and shows the trip as unaudited (Section 2.1).

### 4.5 Evidence retention [DECIDED]
- **One setting for blurred snapshots and GPS logs**, in `TerminalSettings`, set by the **Terminal Manager** and flexible:
  - `RetentionMode = 'FixedDays'` with `RetentionDays` (a fixed period), **or**
  - `RetentionMode = 'UntilSettled'` (until the van's remittance for that service date is closed, `Remittances.Status = 'Settled'`).
- The paper states **no default period** and does not choose a mode. Do not invent one. [OPEN]
- **Safeguard [DECIDED]:** never delete evidence tied to a **pending estimate** (`Passenger_Events.ResolutionStatus = 'Pending'`) or to an **open dispute** (`Disputes.Status = 'Open'` on that trip's `ScheduleID`). In `'UntilSettled'` mode, keep the evidence until the statement is settled **and its disputes are decided**.
- **Deleting a snapshot keeps the chain verifiable.** When a snapshot is deleted: delete the file, set `SnapshotURL` to NULL, set `SnapshotDeletedAt`, and **keep `SnapshotHash`**. `EventHash` is computed over the event's fields **including `SnapshotHash`**, so recomputing it after deletion still matches.
- [DECIDED] For GPS logs, delete only the raw `Nahgm_tracking_logs` rows. `Driving_Events` rows stay.
- [ADVICE] Run it as a scheduled job and log what it deletes.
- The chosen rule is to be checked against the notice and retention requirements of the **Data Privacy Act of 2012** before the pilot. [OPEN]

### 4.6 Open points for the trip start [OPEN]
- Confirm with A2Z: the **30-minute** start window, the **10-minute** grace, that the **Cashier** has time to start trips at the counter in peak hours, and that the **Cashier may assign** the van and Dispatcher when the Terminal Manager is off duty.
- **Off duty [DECIDED].** No duty roster and no toggle. The Cashier's assign action always works, `AssignedBy` shows who did it, and the Terminal Manager is alerted ('Assignment by Cashier').
- Should each start, void, and change join a **hash chain**? That needs a small log table (it would be **Table 40**, and the ERD, Figure 7, would be redrawn). Right now the paper says only that they are stored with who, when, and why. Do not add the table without asking.
- **How does a van that runs independently of the timetable get a trip in the system?** The paper creates trips only from the timetable and from special-trip requests, yet the phone rule covers independent vans. [OPEN] Ask before building.
- **When does a phone that has not come back count as missing**, and who is alerted? [OPEN]

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
- GPS readings come **every 1 to 2 seconds** from the phone's GNSS receiver. This replaces the older 15-second phone ping (a van at 55 km/h covers about 229 m in 15 s, more than the 200 m width of a 100 m stop zone). An **alarm fires if the readings stop**.
- Speed is the speed reported by the phone's GNSS receiver. The study applies no hardware GPS-spoofing protection beyond plausibility checks.
- The exact Realme model, Android version, RAM, and processor are **not known yet**. [OPEN] Do not hard-code device assumptions. Keep a bracketed placeholder.

### 5.2 Detection logic [PAPER]
1. A **virtual line across the doorway**. A tracked person crossing **inward = boarding**, **outward = alighting**.
2. A **mask over the driver's and Dispatcher's seats** so the crew are not counted.
3. Each event carries a **time stamp** and the **number aboard after the event**.
4. A **cabin snapshot at each stop** corrects counting drift: if the running count differs from the snapshot count, flag the difference for review.
5. `TrackID` is only a tracker id within the trip. It is **not a passenger identity**. No face or identity matching.
6. Tracking and counting depend on lighting, door and camera placement, and crowding. Treat camera findings as **estimates for review**.

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
- A phone goes out **only with a Dispatcher**, for a van in the terminal's queue **or** a van that runs independently of the timetable.
- **Check-out:** the Cashier or the Terminal Manager runs a **setup check** (the app is open, the camera and GPS are reporting, the charger works) and records the check-out in `Device_Checkouts` (phone, van, Dispatcher, who, when). `Edge_Devices.Status` becomes `'Checked_Out'`.
- The Dispatcher **mounts the phone in the van's fixed holder**, confirms on the phone's screen that the **door line** is in place, keeps the phone for the day's trips, and **returns it** to the office. The Cashier or the Terminal Manager records the return and the phone's condition (`ReturnedBy`, `ReturnedAt`, `ReturnNote`), and `Status` goes back to `'In_Office'`.
- A van that goes out **without a Dispatcher has no phone**. Its trip is **Unaudited** with `'No_Phone'`.
- Because a phone changes vans, the **door line and the seat mask must be re-aligned at every mounting**. The paper's mitigation is a **fixed holder of the same kind in every van** and the setup check. [ADVICE] Store the door line and the seat mask per van and load them when the check-out names the van. Benchmark on the real phone.
- **Phone count:** the number of vans that can be out at the same time, plus a spare. [ASSUMED, to confirm]

---

## 6. Pipelines: matching, geotagging, driving flags

### 6.1 Matching door events to records [PAPER]
- A boarding is **recorded** if a **QR scan or Dispatcher entry** was made **on the same stretch of the route within two minutes before or after** the boarding, **and has not already been used** for another boarding. Otherwise it is an **unrecorded pasabay boarding**. Window: `MatchWindowS`, sample value 120 s.
- A **pasabay** is a passenger who flags the van and rides **without a booking or QR ticket**.
- **Ticket-count rule at each stop:** compare the number who got off with the number of recorded tickets and logged fares that **end at that stop**.
  - **More** got off than there are tickets: the extra people are matched to the **earliest unrecorded boardings still aboard, first in first out**. That stop becomes their destination.
  - If the extras outnumber the unrecorded boardings aboard, flag the surplus as a **count mismatch** for review.
  - **Fewer** got off than there are tickets: treat the difference as a **no-show or missed detection, never as a lost fare**.
  - No face or identity matching.
- **Fare of an unrecorded boarding:** from `Fare_Matrix`, using the **stop nearest to where the person boarded** and the **stop where the person is matched to have got off**. "Nearest stop" is a configurable choice.
- `MatchStatus` values: `'Matched_QR'`, `'Matched_Log'`, `'Unrecorded'`, `'Mismatch'`.

### 6.2 The four phases [PAPER, Figure 4]
1. **Edge detection** on the phone: detect, track, record each boarding and alighting with a time stamp.
2. **Geotagging** by NAHGM: each event gets its place on the route.
3. **Matching** on the server: matching, ticket-count, fare, and boarding rules against the day's QR scans and Dispatcher logs.
4. **Logging and alerting** on the server: write each event to `Passenger_Events` with a hash that links it to the previous event of the trip, raise unrecorded-boarding and side-pickup alerts with the blurred snapshot, and update the day's remittance.

`EventHash` = SHA-256 of the event's fields (**including `SnapshotHash`**) **and the previous event's hash for the same trip**, so a later change to any event is detectable, even after a snapshot is deleted under the retention rule (Section 4.5). [OPEN] the first event's "previous hash" is not defined in the paper. [ADVICE] use a fixed genesis value derived from `ScheduleID`.

### 6.3 NAHGM geotagging [PAPER]
- Route model: ordered **stops**, each with coordinates, a **stop zone** (circle, **100 m in the sample**), and distance from the starting terminal. Each **stretch** has a length, speed limit, and expected time.
- Expected time of a stretch = (stretch length − stop-zone radius at each end) ÷ expected average speed (**55 km/h** in the sample).
- Haversine distance: `a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)`, `c = 2·atan2(√a, √(1−a))`, `d = R·c`, with `R ≈ 6,371 km`. **The van has reached a stop when `d ≤ stop-zone radius`.**
- **Snap each GPS reading to the nearest point on the route line** to get distance from the starting terminal.
- For each door event, interpolate the van's position between the two GPS readings on either side of the event time, snap it to the route, and store **latitude, longitude, distance from start, stretch, nearest stop and distance to it**.
- NAHGM is **geometry, not machine learning**.

### 6.4 Driving flags [PAPER]
All thresholds are **configurable settings of A2Z**. Sample values:

| Flag | Rule (sample thresholds) |
|---|---|
| `Overspeed` | Speed stays **above the stretch's limit for 10 s or more** |
| `Slow_Stretch` | Time from leaving one stop zone to entering the next is **more than 25 % above expected** (ratio above 1.25) |
| `Unscheduled_Stop` | **Standstill (2 km/h or less) for more than 120 s** while **more than 100 m from every stop** |
| `En_Route_Stop` | A stop of **120 s or less** outside a stop zone. Compare it with the door events: one that coincides with an unrecorded boarding is **location evidence of loading along the route** (a side pickup) |

- Smoking is **not detected**. Unscheduled stops are its measurable proxy. Every flag is an **indicator for review, not proof of misconduct**.
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

### 7.2 New tables (paper Tables 25 to 39)
| # | Table | Purpose and key fields |
|---|---|---|
| 25 | `Operators` | `OperatorID` PK, `FullName`, `ContactNumber` UNIQUE, `Email` NULL (optional), `PayoutRef` NULL, `LicenseNumber` UNIQUE, `LicenseExpiry`, `MembershipStatus` ('Active','Suspended','Inactive'), `ValidationStatus` ('Pending','Validated','Rejected','Suspended'), `ValidatedBy`, `ValidatedAt`, `ImportBatchID`. **No login.** |
| 26 | `TerminalStaff` | `StaffID`, `FullName`, `Email` (login), `StaffRole` ENUM('Manager','Cashier'), `IsActive` |
| 27 | `Fare_Matrix` | `FareID`, `OriginTerminalID`, `DestTerminalID`, `Fare`, `EffectiveFrom`. UNIQUE (origin, destination, EffectiveFrom) |
| 28 | `Route_Stretches` | `StretchID`, `RouteCode`, `StretchNo`, `FromTerminalID`, `ToTerminalID`, `FromDistanceM`, `LengthM`, `SpeedLimitKmh`, `StopZoneRadiusM` (default 100), `ExpectedTimeS` |
| 29 | `Passenger_Events` | One row per door event: `EventID`, `ScheduleID`, **`DeviceID` FK NOT NULL → `Edge_Devices` (the phone that sent the event)**, `EventType` ('BOARD','ALIGHT'), `EventAt` DATETIME(6), `Latitude`, `Longitude`, `DistanceFromStartM`, `StretchNo`, `NearestStopID`, `NearestStopDistM`, `SidePickup`, `OccupancyAfter`, `TrackID`, `MatchStatus`, `MatchedBookingID`, `MatchedLogEntryID`, `DestStopID`, `EstimatedFare`, `SnapshotURL` (NULL once the snapshot is deleted), **`SnapshotHash` CHAR(64) NULL**, **`SnapshotDeletedAt` DATETIME NULL**, `EventHash` CHAR(64), `ResolutionStatus` ('Pending','Confirmed','Dismissed'), `ResolvedBy`, `ResolvedAt` |
| 30 | `Driving_Events` | `DrivingEventID`, `ScheduleID`, `FlagType`, `StartAt`, `EndAt`, `DistanceFromStartM`, `StretchNo`, `MaxSpeedKmh`, `LimitKmh`, `TimeRatio`, `NearestStopDistM`, `DurationS`, `ReviewStatus` |
| 31 | `Nahgm_tracking_logs` | GPS readings: `LogID` BIGINT AUTO_INCREMENT, `ScheduleID`, `RecordedAt` DATETIME(3), `Latitude`, `Longitude`, `SpeedKmh` (from the phone's GNSS), `DistanceFromStartM`, `StretchNo`, `NearestStopDistM` |
| 32 | `Remittances` | Daily statement per van: `RemittanceID`, `OperatorID`, `VanID` (UNIQUE with `ServiceDate`), `ServiceDate`, `VerifiedIncome`, `DeclaredIncome`, `EstimatedIncome`, `RatePct`, `RemittanceOwed`, `AmountAtRisk`, `Status` ('Open','Settled'), `SettledAmount`, `SettledAt`, `SettlementRef`, `RecordedBy` (Cashier) |
| 33 | `TerminalSettings` | Key-value rules with `EffectiveFrom`: `SettingKey`, `EffectiveFrom` (PK together), `SettingValue`, `UpdatedBy`, `UpdatedAt` |
| 34 | `Special_Trip_Requests` | `RequestID`, `PassengerID`, `PickupAt`, pickup and destination address and coordinates, `PassengerCount` (≤ 14), `RentalFee`, `PaymentStatus`, `PaymentReference`, `Status` ('Requested','Approved','Rejected','Completed','Cancelled'), `ScheduleID` (trip created on approval, `IsSpecial = TRUE`), `ReviewedBy`, `ReviewedAt` |
| 35 | `Remittance_Lines` | Fare lines behind a statement: `LineID`, `RemittanceID`, `ScheduleID`, `OriginTerminalID`, `DestTerminalID` (NULL on a special trip), `RequestID` (when the line is a rental fee), `IncomeGroup` ('Verified','Declared','Estimated'), `FarePerPassenger`, `PassengerCount`, `GrossFare`, `ShareAmount` |
| 36 | `Data_Transfers` | Import and export log: `TransferID`, `Direction`, `RecordType` ('Operators','Vans','Dispatchers'), `FileName`, `FileFormat` ('CSV','XLSX','PDF'), `ExportPurpose` ('Backup','LTFRB Check','Other'), `RowsInFile`, `RowsAccepted`, `RowsRejected`, `ErrorFileURL`, `PerformedBy`, `PerformedAt` |
| 37 | `Edge_Devices` | The terminal's phone pool, with each phone's status and latest report: `DeviceID` PK, `DeviceModel` NOT NULL, `AndroidVersion`, `AppVersion`, `Status` ENUM('In_Office','Checked_Out','Retired') NOT NULL DEFAULT 'In_Office', `RegisteredBy` FK → TerminalStaff (Terminal Manager, who added the phone), `RegisteredAt`, `LastHeartbeatAt`, `BatteryPct`, `BatteryTempC` DECIMAL(4,1), `CameraOk`, `GpsOk`. **No `VanID` and no `IsActive`**: a retired phone has `Status = 'Retired'` and keeps its row |
| 38 | `Device_Checkouts` | Each time a phone leaves the office and comes back: `CheckoutID` PK, `DeviceID` FK NOT NULL, `VanID` FK NOT NULL, `DispatcherID` FK NOT NULL, `CheckedOutBy` FK → TerminalStaff NOT NULL (Cashier or Terminal Manager), `CheckedOutAt` NOT NULL, `ReturnedBy` FK → TerminalStaff NULL, `ReturnedAt` NULL, `ReturnNote` VARCHAR(255) NULL. Open = `ReturnedAt IS NULL`. One open check-out per phone, enforced by the application (Section 5.3) |
| 39 | `Disputes` | An operator's contest of an item: `DisputeID` PK, `RemittanceID` FK NOT NULL, `ScheduleID` FK NOT NULL, `Subject` ENUM('Estimated_Fare','Fare_Line','Driving_Flag') NOT NULL, `EventID` FK NULL → Passenger_Events, `LineID` FK NULL → Remittance_Lines, `DrivingEventID` FK NULL → Driving_Events (exactly one is filled to match `Subject`), `OperatorStatement` VARCHAR(500) NOT NULL, `AmountDisputed` DECIMAL(10,2) NOT NULL DEFAULT 0.00 (the share that waits; 0.00 for a driving flag), `RaisedByRole` ENUM('Dispatcher','Cashier','Manager') NOT NULL, `RaisedByID` VARCHAR(32) NOT NULL (in `Dispatchers` or `TerminalStaff` according to the role, so no foreign key), `RaisedAt` NOT NULL, `Status` ENUM('Open','Resolved','Withdrawn') NOT NULL DEFAULT 'Open', `Outcome` ENUM('Upheld','Rejected','Adjusted') NULL, `AdjustedAmount` DECIMAL(10,2) NULL (the share due when the outcome is 'Adjusted'), `DecidedBy` FK NULL → TerminalStaff, `DecidedAt` NULL, `DecisionNote` VARCHAR(255) NULL |

### 7.3 Edits to existing tables [PAPER, working note]
- **Bookings:** `TripID` → `ScheduleID` (FK to `TripSchedules`; the old ERD named a table that does not exist). Describe `BookingID` as a UUID. Add `OriginTerminalID`, `DestTerminalID` (FK), `PaymentReference` VARCHAR(64) NULL, `PaymentStatus` ENUM('Unpaid','Paid','Refunded').
- **TripSchedules:**
  - add `DriverName` VARCHAR(255) NULL, `DriverLicenseNo` VARCHAR(15) NULL, `VanPlateNumber` VARCHAR(8) NULL (copies taken **when the trip is started**);
  - add `RouteCode`, `Status` ENUM('Scheduled','Boarding','En Route','Completed','Cancelled'), `IsSpecial` BOOLEAN;
  - allow NULL in `AssignedVanID` until a van is assigned at its turn (or, on a special trip, until the Terminal Manager assigns one);
  - rename `ConductorID` → `DispatcherID`, NULL until assigned; add `AssignedBy` FK NULL → TerminalStaff and `AssignedAt` DATETIME NULL (they record who assigned the **van and** the Dispatcher; these replace the old `DispatcherAssignedBy` and `DispatcherAssignedAt`);
  - remove `StandardFare` or keep it as a display value only (every fare is priced from `Fare_Matrix`);
  - add the **start, review, and audit columns** in Section 4.3.
- **Vans:** add `OperatorID` FK NOT NULL **UNIQUE** (one van per operator); replace the `RegisteredRoute` ENUM with `RouteCode` VARCHAR(30); allow NULL in the four photograph URLs (so an imported van can be saved first).
- **Dispatchers and Vans:** add `ValidationStatus` ENUM('Pending','Validated','Rejected','Suspended') NOT NULL DEFAULT 'Pending', `ValidatedBy` FK NULL → TerminalStaff, `ValidatedAt` NULL, `ImportBatchID` FK NULL → `Data_Transfers`.
- **LogBookEntries:** add `ScheduleID` FK, `DestStopID` FK, `FareAmount` DECIMAL(10,2), `LoggedBy` FK → Dispatchers.
- **Yolov8_audit_logs:** remove `DriverID`. Keep as the **cabin-snapshot drift check**. Fix the stray "2" in `NOT NULL2`. Align its columns with Figure 21.
- **Notifications:** replace `PassengerID` with `RecipientType` ENUM('Passenger','Dispatcher','Manager','Cashier') and `RecipientID` VARCHAR(32). Add types `'Capacity Alert'`, `'Unrecorded Boarding'`, `'Side Pickup'`, `'Driving Flag'`, `'Special Trip Request'`, `'Unconfirmed Trip Start'`, `'Unaudited Trip'`, `'Trip Not Started'`, `'Assignment by Cashier'`, `'Dispute Raised'`.
- **Remittances:** a later payment on a reopened statement is added to `SettledAmount`, and its reference is appended to `SettlementRef`. There is one payment slot per statement (known limitation).
- **TerminalSettings keys:** `'RemittanceRate'` (0.15), `'SeatCapacity'` (14), `'MatchWindowS'` (120), `'OverspeedSeconds'` (10), `'StopSeconds'` (120), `'SlowTolerance'` (0.25), `'ExpectedSpeedKmh'` (55), `'AdvanceBookingDays'`, `'HoldReleaseS'`, `'SpecialTripSpeedKmh'`, **`'StartOpensMin'`** (30), **`'StartGraceMin'`** (10), **`'HeartbeatGapS'`** (120, placeholder), **`'RetentionMode'`** (`'FixedDays'` or `'UntilSettled'`, no default in the paper), **`'RetentionDays'`** (used when the mode is `'FixedDays'`). Sample values are illustrative.

### 7.4 Proposed, not yet in the data dictionary [OPEN]
- **`Timetable_Templates`**: `RouteCode`, `DepartureTime`, `OperatingDays`, `IsActive`. **No `UsualVanID` or `UsualDispatcherID`**: the van and the Dispatcher are assigned at the van's turn, not stored in the timetable. Needed for "trips are created from the timetable". The prototype's Timetable screen (22) has no table today.
- **`SosAlerts` and `Messages`**, or drop those prototype screens. SOS alerts and in-app messaging are **supporting functions and are not evaluated**.
- A **start/void log table** (would be **Table 40**). Not added. See Section 4.6.
- A server-side **unassigned events** list for door events that match no open trip (Section 4.2, rule 12). The paper holds them outside the ledger and does not model them in the data dictionary. [OPEN]
- Dispatchers' sign-in: by phone number, or add an `Email` field. The existing table has no email. [OPEN]

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
- **Van status board** (Terminal Manager and Cashier): each van is **on site** (trip scheduled or boarding at a terminal), **travelling** (trip en route, also showing Dispatcher, operator, route, number aboard, last GPS position), **not on a trip** (no trip today), or **out of service** (maintenance or inactive). It uses trip status and GPS already stored, so it needs no extra data entry. For the Cashier it shows which statements to expect that day.

---

## 9. Screens

Prototype figure numbers (7 to 27) and the table they read from. Mobile: **Flutter** (Passenger and Dispatcher). Terminal Manager and Cashier use **web screens** (the paper does not name a web framework).

| Screen (figure) | Needs |
|---|---|
| Authentication (7) | Passengers and TerminalStaff email via Firebase Authentication. Dispatcher sign-in method [OPEN] |
| Available Routes (8), Booking Confirmation (9), Gateway and E-Ticket (10, 11), Active Trips and History (12), Profile (14) | `TripSchedules`, `Fare_Matrix`, `Bookings`, `Vans`, `Route_Stretches` |
| Dispatcher Dashboard (13) | Boarding status, occupancy, operator name and license, van plate. Shows the trip **assigned** to the Dispatcher's van turn (scan and cash log work **before** the start) and, once started, the operator and the plate number. **No** van picking, **no** void or change-van buttons |
| Operations Map (15) | `Nahgm_tracking_logs`, `Passenger_Events.OccupancyAfter`. The 15-second map refresh is a **display setting**, separate from the 1 to 2 s GPS readings |
| Trip Monitoring (16) | Status, Dispatcher, operator, booked, aboard, no-show, camera check, **who started the trip and how**, `AuditStatus`, and the phone's last report (`Edge_Devices`) |
| **Start Trip (new)** | Terminal Manager and Cashier. Shows the van and Dispatcher **assigned at the van's turn**. Here the Terminal Manager (or the Cashier when the manager is off duty) **assigns the van and the Dispatcher** (`AssignedVanID`, `DispatcherID`, `AssignedBy`, `AssignedAt`). Confirm or change the van from validated vans. Start (blocked until van and Dispatcher are assigned), Depart. Warnings: expired license, **no phone out with the van**, phone silent, confirmed van differs from the van the phone is checked out to. **Void and Change Van buttons for the Terminal Manager only.** Writes `StartMode`, `StartedBy`, `StartedAt` |
| **Review Automatic Starts (new)** | Terminal Manager. Trips with `StartReviewStatus = 'Pending'` and trips that are Unaudited. Confirm or change the van, then mark Reviewed (this releases the trip's fare lines to the statement) |
| Special Trips (17), Timetable (22) | `Special_Trip_Requests`, `TripSchedules.IsSpecial`, `Timetable_Templates` (route, time, days, in-use toggle only). New **Request a Special Trip** screen for the Passenger |
| Remittance (replaces Fares and Cash, 20) | `Remittances` and `Remittance_Lines`: verified, declared, estimated income, owed, at risk, settlement status, fare lines by trip, terminals, and fare. The **Cashier records the payment here**, can **record a dispute on a line**, and sees the **disputed share** separately |
| Boarding Audit (replaces Passenger Count Checks, 21) | `Passenger_Events`: unrecorded boardings with time, location, snapshot, hash check, and resolution. The **Terminal Manager decides each estimate here** and **decides each dispute** |
| Vans and Crew (23) → **Member Records** | `Vans`, `Operators`, `Dispatchers`, validation fields, `ImportBatchID`. Import and export buttons log to `Data_Transfers` |
| **Van Status Board (new)** | Terminal Manager and Cashier |
| **Phones (new)** | Cashier and Terminal Manager. List the pool (`Edge_Devices`: status, battery, last report), **check a phone out** to a Dispatcher and van after the setup check, and **record its return** and condition (`Device_Checkouts`). The Terminal Manager also **adds a phone to the pool** |
| **Disputes (new)** | `Disputes`. The Cashier, the Dispatcher, and the Terminal Manager **record** a dispute (item, operator's statement, share withheld). Only the Terminal Manager **decides** (Upheld, Rejected, Adjusted) with a note. Where the Dispatcher records it (mobile app or web) is [OPEN] |
| Rules and Settings (24) | `TerminalSettings`: booking window, seats sold in advance, cancellation deadline, hold release, reschedules, refund policy, **start window and grace period, silent-phone gap, and retention of snapshots and GPS logs (fixed days or until settled)**. Terminal Manager only |
| Emergencies (18), Messages (19) | Supporting only. Keep or drop [OPEN] |

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
- Non-goals: processing or holding money; handling cash, banking, or A2Z's accounting; connecting to LTFRB records; reading binder pages automatically; smoking detection; hardware-level GPS-spoofing protection; passenger live position and ETA; routing or door-to-door pickup on fixed-route trips.
- **LTFRB franchise capacity** and **en-route loading rules** remain A2Z's responsibility to confirm. 14 passengers is A2Z's rule.
- **Retention:** blurred snapshots and GPS logs are kept under one setting (Section 4.5). A deleted snapshot keeps its hash. Evidence tied to a pending estimate or an open dispute is never deleted.
- The hash chain makes a later change **detectable**. It is only as reliable as the camera's detection and the integrity of the edge node. The controls detect and deter collusion among trip personnel. They cannot fully prevent it.

---

## 12. Acceptance tests

### 12.1 The paper's sample trip

The paper's numbers come from a simulated trip (Ecoland Terminal → Digos City Terminal, departure 05:30:00, four stops, 100 m stop zones, expected speed 55 km/h). All values are **illustrative**. Use them as a regression test for the matching, remittance, and flag logic.

**Route model**

| Stop | Lat | Lon | Distance from start (m) | Next stretch (m) | Limit (km/h) | Expected (min) |
|---|---|---|---|---|---|---|
| Ecoland Terminal | 7.0540 | 125.6060 | 0 | 12,967 | 60 | 13.9 |
| Toril | 7.0130 | 125.4960 | 12,967 | 21,751 | 80 | 23.5 |
| Sta. Cruz | 6.8370 | 125.4100 | 34,718 | 11,306 | 60 | 12.1 |
| Digos City Terminal | 6.7500 | 125.3570 | 46,025 | | | |

**Door events**

| Event | Time | Distance (m) | Aboard | Expected result |
|---|---|---|---|---|
| E01 to E12 (12 boardings) | 05:28:00 | 0 | 12 | 12 of 12 QR scans, verified |
| E13 | 05:47:41 | 16,999 | 13 | Unrecorded, side pickup |
| E14 | 05:47:48 | 16,999 | 14 | Unrecorded, side pickup |
| E15 | 06:00:37 | 26,001 | **15** | **Capacity alert fires.** Cash log made 47 s later, so declared. Side pickup |
| A01 to A02 (2 alightings) | 06:09:11 | 34,718 | 13 | Match 2 tickets to Sta. Cruz |
| A03 to A15 (13 alightings) | 06:28:31 | 46,025 | 0 | 11 tickets and logs to Digos, **2 extra**. E13 and E14 are matched to Digos in FIFO order and priced **Toril to Digos at ₱75** (their boarding point is nearest Toril) |

**Remittance (ρ = 0.15)**

| Group | Line | Passengers | Gross ₱ | Share ₱ |
|---|---|---|---|---|
| Verified | Ecoland to Digos at ₱110, QR | 10 | 1,100.00 | 165.00 |
| Verified | Ecoland to Sta. Cruz at ₱80, QR | 2 | 160.00 | 24.00 |
| Declared | Sta. Cruz to Digos at ₱30, E15 cash log | 1 | 30.00 | 4.50 |
| | **Remittance owed** | 13 | 1,290.00 | **193.50** |
| Estimated | Toril to Digos at ₱75, E13 and E14 | 2 | 150.00 | **22.50 at risk** |
| | **If all estimates are confirmed** | 15 | 1,440.00 | **216.00** |

**Driving flags**

| Flag | Time | Distance (m) | Evidence | Duration |
|---|---|---|---|---|
| Overspeed | 05:37:48 to 05:38:28 | 7,043 | Max 88.0 km/h against 60 | 40 s |
| En-route stop | 05:47:30 to 05:48:04 | 17,001 | 4,034 m from nearest stop, coincides with E13 and E14 | 34 s |
| Unscheduled stop | 05:52:28 to 05:56:32 | 21,798 | 8,831 m from nearest stop, no door event | 244 s |
| En-route stop | 06:00:26 to 06:00:56 | 26,000 | 8,719 m from nearest stop, coincides with E15 | 30 s |

**Stretch time check (flag above 1.25 × expected)**

| Stretch | Actual (min) | Expected (min) | Ratio | Result |
|---|---|---|---|---|
| Ecoland to Toril | 13.6 | 13.9 | 0.98 | Normal |
| Toril to Sta. Cruz | 24.5 | 23.5 | 1.04 | Normal |
| Sta. Cruz to Digos | 17.6 | 12.1 | 1.45 | **Slow** |

Notes the test must respect: the Toril to Sta. Cruz stretch passes the time check even though it holds 244 s of unscheduled stopping, because the simulated driver cruised at 70 km/h to recover time. That is why the **stop flags are needed alongside the stretch-time check**. E13, E14, and E15 are all side pickups, **even though E15 is recorded as declared income**: matching asks whether the fare was recorded, and the side-pickup flag asks where the person boarded.

### 12.2 Acceptance tests for the start, audit, and retention rules

These are not in the paper's sample trip. They follow Sections 4 and 2.1. Use the sample route and the ₱ figures above where a number is needed.

| # | Situation | Expected result |
|---|---|---|
| T1 | Terminal Manager assigns a van and a Dispatcher at the van's turn. The Cashier starts the trip on time | `StartMode = 'Manual'`, `StartedBy` = the Cashier, `StartReviewStatus = 'Not_Required'`, operator name, license number, and plate copied onto the trip |
| T2 | Late tap: the Dispatcher scans QR tickets and logs cash on the scheduled trip, and the start is tapped 6 minutes later | Scans and cash log already belong to the trip. Door events match them. Nothing is lost |
| T3 | No tap: the grace period passes with an assigned van | Trip starts automatically, `'Auto_Assigned'`, `StartedBy` NULL, `StartReviewStatus = 'Pending'`, **'Unconfirmed Trip Start'** alert to the Terminal Manager. The trip is **not** in the statement |
| T4 | After T3 the Terminal Manager reviews the trip | `'Reviewed'` with who and when. Its fare lines appear in the statement |
| T5 | Same as T4, but the statement was already paid | Statement reopens (`'Open'`). Only `RemittanceOwed − SettledAmount` is due [ASSUMED rule] |
| T6 | No tap and **no van assigned**, but the phone of a van detects the departure | `'Auto_Detected'` with that phone's van, `'Pending'` review |
| T7 | No tap, no van assigned, no phone detects a departure | **'Trip Not Started'** alert. Trip stays open for the Terminal Manager |
| T8 | Manual Start tapped with **no Dispatcher** assigned | **Blocked** |
| T9 | Automatic start with no Dispatcher assigned | Trip starts, **flagged "No Dispatcher"** (`DispatcherID` NULL), review `'Pending'` |
| T10 | The starter confirms van A, but the events come from the phone checked out to van B | **Warning** to the starter. Start is not blocked. Events are still matched to the trip of the van that sent them, by time |
| T11 | The Cashier tries to void a started trip or change its van | **Refused.** The Terminal Manager's void is stored with who, when, and why, `Status = 'Cancelled'` |
| T12 | The phone is silent when the Cashier starts the trip | **Warning**, trip starts, `AuditStatus = 'Unaudited'`, `'Silent_At_Start'`, alert to the Terminal Manager, the Cashier, and the Dispatcher |
| T13 | The phone goes silent mid-trip (no report within `HeartbeatGapS`) and the reports it stores do **not** cover the gap | Alert at once. When the phone reconnects, or the trip ends, the trip becomes Unaudited from the start of the gap, `'Lost_En_Route'`. Service continues. The statement counts only QR tickets and logged fares for the trip and shows it as unaudited |
| T14 | An operator is named on two vans in an import file | The row is **rejected** with a reason. The database `UNIQUE` on `Vans.OperatorID` also refuses it |
| T15 | `RetentionMode = 'FixedDays'`, `RetentionDays = N`. A snapshot is older than N days and its event is not pending | File deleted, `SnapshotURL` NULL, `SnapshotDeletedAt` set, `SnapshotHash` kept |
| T16 | Same as T15, but the event is a **pending estimate** | **Not deleted** |
| T17 | `RetentionMode = 'UntilSettled'` | Evidence for a service date is deleted only after that van's remittance is `'Settled'` |
| T18 | Recompute `EventHash` for a trip after T15 | Every hash still matches, and the chain verifies without the image |
| T19 | A second staff member signs in | `StartedBy`, `AssignedBy`, and `ChangedBy` record that person. There is no shared account |
| T20 | The Cashier runs the setup check and checks a phone out to a Dispatcher and van | Open `Device_Checkouts` row, `Edge_Devices.Status = 'Checked_Out'`. Events from that phone match the trip of that van |
| T21 | The Dispatcher returns the phone and the Cashier records it | `ReturnedBy`, `ReturnedAt`, and `ReturnNote` set, `Status = 'In_Office'`. A second check-out of the same phone, or of the same van, while one is open is **refused** |
| T22 | A van goes out with no Dispatcher and no phone, and the trip is started | **Warning**, trip starts, `AuditStatus = 'Unaudited'`, `'No_Phone'`, alert to the Terminal Manager, the Cashier, and the Dispatcher. The statement counts only QR tickets and logged fares |
| T23 | The phone loses mobile data for 3 minutes mid-trip, then reconnects with stored reports that show the camera and GPS working | The alert fires at once, but the trip **stays Audited** because the stored reports cover the gap |
| T24 | The Cashier assigns a van and a Dispatcher while the Terminal Manager is off duty | Allowed. `AssignedBy` is the Cashier, and the Terminal Manager gets an **'Assignment by Cashier'** alert and can change it |
| T25 | A door event arrives when the van has no open trip: (a) inside the next trip's start window, (b) outside it | (a) The event goes to the next scheduled trip. (b) It waits in the unassigned list, outside `Passenger_Events`, **'Trip Not Started'** is raised, and once the trip is started the event is matched to it by time |
| T26 | The van arrives. Aboard is still 2. Later the Dispatcher taps Arrived (or aboard reaches 0) | The trip stays open until then, then `CompletedAt` is set and `Status = 'Completed'` |
| T27 | Sample trip, E13 and E14 confirmed (owed ₱216.00). The operator contests E14 at the counter | `Disputes` row (`'Estimated_Fare'`, `AmountDisputed = 11.25`). Due now **₱204.75**. The statement shows the ₱11.25 separately |
| T28 | Continue T27: the Terminal Manager decides (a) Upheld, (b) Rejected, (c) Adjusted | (a) Remittance owed ₱204.75, and it settles when paid. (b) The ₱11.25 becomes due. (c) The share due is `AdjustedAmount`. Each decision stores `DecidedBy`, `DecidedAt`, and `DecisionNote`. A Cashier or a Dispatcher who tries to decide is **refused** |
| T29 | The operator disputes a driving flag | `'Driving_Flag'`, `AmountDisputed = 0.00`, nothing is withheld, the Terminal Manager decides |
| T30 | The operator tries to dispute an item after the statement is fully paid | **Refused** [ASSUMED rule] |
| T31 | Retention job: a trip has an open dispute (mode `'FixedDays'` and the snapshots are older than N days; or mode `'UntilSettled'` and the statement is settled but a dispute is open) | **Nothing is deleted** until the dispute is decided (and, in `'UntilSettled'` mode, the statement is settled) |

---

## 13. Suggested order of work [ADVICE]

1. **Gap report**: repo vs this brief (roles, tables, screens, edge app, matching code). Wait for approval.
2. **Schema migration** (Sections 7.1 to 7.3), written as reversible migrations. Roles and renames first, then new tables (including `Edge_Devices`, `Device_Checkouts`, and `Disputes`), then the start, review, and audit columns. `Vans.OperatorID` becomes UNIQUE, so check the existing data for an operator on two vans before migrating.
3. **Settings and roster**: `TerminalSettings` keys (start, heartbeat, retention), `Operators`, validation, import and export with preview (one van per operator), `Data_Transfers`, and the phone pool with check-out and return (`Edge_Devices`, `Device_Checkouts`).
4. **Trip lifecycle**: timetable → trips days ahead, assignment at the van's turn (Terminal Manager, Cashier backup), Start Trip screen and API, the **auto-start fallback job** (assigned van, then phone-detected van, "No Dispatcher" flag, "Trip Not Started" alert), the review hold on statements, departure detection, void and change-van (Terminal Manager only), alerts.
5. **Edge ingestion API**: authenticated event upload with `DeviceID`, offline-tolerant, idempotent, with heartbeat into `Edge_Devices` (including stored reports sent after a reconnect); the Unaudited check (`'No_Phone'` too). Then the Android edge app (Section 5).
6. **Matching, hash chain (with `SnapshotHash`), side-pickup flag, capacity alert, remittance computation** (held lines, reopen rule, disputed share), then the **dispute record and decision** (`Disputes`). Run the Section 12 acceptance tests.
7. **Retention job** (Section 4.5) after the hash chain works, so test T18 can run. It skips trips with an open dispute.
8. **NAHGM and driving flags** against `Nahgm_tracking_logs`.
9. **Screens**: Start Trip, Review Automatic Starts, Boarding Audit, Remittance, Van Status Board, Phones, Disputes, Member Records, Rules and Settings, Special Trips.
10. **Pilot checks**: full-trip phone benchmark (fps, temperature, battery, uptime) before any figure is stated.

---

## 14. Open items to confirm with A2Z or decide in the group

- Capacity: confirm the **franchise capacity** of A2Z's units with LTFRB Region XI (an LTFRB reminder lists UV Express at 9, 10, or 12 including the driver, or the manufacturer's specification). 14 is A2Z's cap.
- Whether en-route loading is still treated as a franchise breach (reference [11]).
- **Boarding at intermediate terminals**, and whether a side pickup is only flagged or also penalized.
- **Special trips:** the assumptions in Section 2.5, including whether a Dispatcher rides on a rented van.
- **Trip start and assignment:** the 30-minute window, the 10-minute grace, that A2Z assigns a van and a Dispatcher to each departure at the van's turn, that the Cashier may assign when the Terminal Manager is off duty, and that the Cashier has time to start trips at the counter in peak hours.
- **Held lines:** that an auto-started trip is held out of the statement until reviewed, and that a reopened statement collects only the difference between the amount owed and the amount settled (ASSUMED).
- **Edge phone and custody:** exact model, Android version, RAM, and processor. How many phones A2Z needs, and when a phone that has not come back counts as missing. How a van that runs independently gets a trip in the system. The silent-phone gap (placeholder 120 s). Whether A2Z allows a camera in the cabin.
- **Evidence retention:** which mode A2Z prefers (fixed days or until settled), a default period, and a check against the notice and retention requirements of the Data Privacy Act of 2012.
- **Disputes:** that an operator can contest only at the counter and only before full payment, that the operator pays the undisputed part meanwhile, that only the Terminal Manager decides, and whether a second person should review a dispute over the Terminal Manager's own decision. Passenger complaints and refunds are not covered.
- **One login per staff member** (needed because `StartedBy`, `AssignedBy`, and `ChangedBy` name a person).
- **Hash chain** hardening: device-side signing in the Keystore, and whether starts and voids join the chain (would be Table 40).
- **Dispatcher sign-in:** phone number or email.
- **Operators:** the paper assumes **one van per operator** and that the owner always drives. Confirm that no A2Z member owns several vans, and what happens when someone else drives (a substitute).
- **Gateway settlement** goes to the operator's payout account. Confirm with A2Z.
- **Member records:** which fields the binder really holds (operators: name, contact, email, license number and expiry; vans: plate, CPC case number and number, model, color, route). Whether both the Terminal Manager and the Cashier may import and export.
- **Export for LTFRB:** which fields and file format LTFRB Region XI needs.
- Replace every **illustrative value** (stop coordinates, limits, fares, expected speed, stop-zone radius, matching window, flag thresholds) with surveyed ones, and rerun the sample script and tests.
- **Figures the group must still redraw:**
  - **ERD (Figure 7):** `Edge_Devices` one-to-many to `Device_Checkouts` and to `Passenger_Events`; `Device_Checkouts` many-to-one to `Vans`, `Dispatchers`, and `TerminalStaff` (twice: check-out and return); `Disputes` many-to-one to `Remittances`, `TripSchedules`, and `TerminalStaff` (`DecidedBy`), and optionally to `Passenger_Events`, `Remittance_Lines`, and `Driving_Events`; `Vans.OperatorID` one-to-one with `Operators`; new columns of `TripSchedules` (`StartMode`, `StartedBy`, `AssignedBy`, `AssignedAt`, `StartReviewStatus`, `AuditStatus`, `CompletedAt`) and of `Passenger_Events` (`DeviceID`, `SnapshotHash`, `SnapshotDeletedAt`).
  - **Scrum sprint plan (Figures 1 and 2).**
- **Design risks to watch:**
  - A phone that changes vans needs the **door line and seat mask re-aligned** at every mounting (Section 5.5).
  - Door events that match no open trip are held at the server, and **the data dictionary does not model that list**.
  - `Remittances` has **one payment slot** (`SettledAmount`, `SettlementRef`).
  - **One open check-out per phone and per van** is enforced by the application, not by the paper's schema.
  - Disputes after full payment are out of scope, and the Terminal Manager may decide a dispute over their own decision.

---

## 15. Terminology and writing conventions

- **A2Z** (not "the co-op" or "the cooperative"). Full name once: "A2Z Transport Cooperative Van Terminal".
- **Dispatcher** (not Conductor), **Terminal Manager** (not Cooperative Administrator or Operator), **Cashier**, **operator** (lower case, the van owner and driver, not a user), **passengers** (not commuters).
- **stop, stretch, distance from the starting terminal, stop zone** (not node, segment, chainage, geofence).
- **pasabay**: a passenger who rides without a booking or QR ticket.
- In documentation and comments: no promotional adjectives, and avoid "propose", "proposal", "proponents". State only what the code or the paper does.
- Do not state a frame rate, accuracy, or uptime figure for the edge phone until it has been measured.
