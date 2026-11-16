# UI run, 11 Nov 2026: every role, through the screens

One complete day's work done by clicking and typing in the real apps, as
each person would, against the live system (`./run.sh`, A2Z Day 1 data +
`seed_alpha.py` + `seed_live_now.py`). Nothing was entered through the API
except reading results back to check them.

**How:** a headless Brave driven over the DevTools protocol
(`ui_driver.py` here). Flutter's accessibility tree is switched on, so each
button and field is found by its label, as a screen reader finds it, and
clicked or typed into with real input events. Each role has its own browser
context, so sign-ins never mix. The phone app ran as its web build at
412 × 915; the console at 1440 × 900, a common laptop size. The screenshots
here are named by role and order: `d` Dispatcher, `p` passenger, `m`
Terminal Manager, `c` Cashier, `n` new passenger, `dd` new Dispatcher.

## The run

| # | Who | What they did | Result |
|---|---|---|---|
| 1 | Dispatcher Nonoy | Signed in; opened his 1:59 AM trip (on the road); **Arrived** | Completed; "Trip completed. Nothing left to do" |
| 2 | Terminal Manager | Trips › post bar: van TST-1023, Dispatcher Nonoy, 11:30 AM; **Post** | "Posted. Passengers can book the 11:30 AM trip today now." |
| 3 | Passenger Lea | Signed in; From already Ecoland; picked Digos; departures loaded by themselves; **Reserve a space** | Code SG-6JY3US, ₱150, pay before 11:00 |
| 4 | Dispatcher Nonoy | Opened the 11:30 trip (Next: "Collect ₱150 …"); found Lea by typing "6jy3"; **Mark ₱150 paid** | Paid; fees owed ₱97.50 (15 % + ₱75) |
| 4b | Dispatcher Nonoy | **Add walk-up** to Kidapawan; **Log** | SG-VCY3TW, "Collect ₱340.00"; fees ₱148.50 |
| 5 | Passenger Paolo | Reserved the same trip, went straight to My trips, opened it, **Cancel reservation** | Shown at once (after the fix); "Cancelled. Book again …" |
| 6 | Cashier Joy | Opened the trip's detail (fares ₱490, 15 % ₱73.50, DCOTT ₱75, share ₱341.50); **Record payment**, receipt 0012401 | "Ready to start"; list locked |
| — | Passenger Lea | **I'm at the terminal** (position at Ecoland simulated, see below) | "Checked in at … Ecoland (0m)"; Dispatcher sees Checked in 1 |
| — | Lea ↔ Nonoy | Chat: Lea wrote from the bench; Nonoy replied | Both ways, the reply arrived in Lea's open thread within seconds |
| — | Terminal Manager | Money › TST-1023 statement | Every figure checked by hand: 15 % ₱383.85, owed ₱583.85, paid ₱532.85, ₱51 disputed, due ₱0 |
| 7 | Cashier Joy | At 11:00, **Start trip** on the row | "Trip started."; row shows Depart |
| 8 | Dispatcher Nonoy | Next: "Everyone has paid … tap Depart"; **Depart** | "Departed."; On the road; manifest Lea paid, walk-up boarded |
| 9 | Dispatcher Nonoy | **Arrived** | Completed; "Nothing to hand to the Cashier now" |
| 10 | Terminal Manager | Reviews › Disputes: **Reject** the Kidapawan line, with a reason (Decide disabled until written; preview "Due ₱0.00 → ₱51.00") | Decided; counts cleared on the next refresh |
| 11 | Cashier Joy | Money › TST-1023 › **Record payment** ₱51, receipt 0012402 | ₱583.85 of ₱583.85, **Settled** |
| 12 | New passenger | **Create an account** (Carlo Mendoza): a 5-letter password refused, no terms ticked refused, then created | Signed in on Home; the account signs in again on its own |
| 13 | Terminal Manager | Setup › Staff › **Add staff member** Dodong Saavedra (Dispatcher); **Validate** | Added, Validated; Dodong signs in on the phone: "No trips assigned" |
| 14 | Dispatcher Nonoy | **Emergency** › Breakdown, a note marked TEST ONLY; **Send alert now** | "Alert recorded. 3 in-app alert(s) … No SMS was sent: no emergency contact numbers are set." |
| 14b | Terminal Manager | Emergencies: **Mark as responding**, **Close with a note** | "Emergency closed." |

Records this run added to the live data: the 11:30 AM trip (completed);
bookings SG-6JY3US (paid), SG-VCY3TW (walk-up), SG-4X8CGP (cancelled);
payments 0012401 (₱148.50) and 0012402 (₱51); the rejected dispute; the
chat; passenger Carlo Mendoza; Dispatcher Dodong Saavedra; one TEST SOS,
closed.

## What it found, and what became of it

| # | Finding | Status |
|---|---|---|
| 1 | At 1440 px the post bar squeezed its fields to icons and cut-off labels | Fixed: the bar needs 1400 px of page; narrower gets the full card |
| 2 | The trip sheet said "You pay on the next screen …" (the old online-payment wording) | Fixed: "You pay in cash to the Dispatcher at the terminal …" |
| 3 | The camera notice shows "[name and position to be supplied by A2Z]" | Open: A2Z's data privacy contact (brief 4.5), theirs to give |
| 4 | My trips never showed a booking made after sign-in (tab kept alive, loaded once) | Fixed: reloads each time the tab is shown |
| 5 | The walk-up screen was titled "Walk-in passenger" | Fixed: "Walk-up passenger" |
| 6 | A cancelled reservation still said "… when you pay" and "Unpaid: cash to the Dispatcher" | Fixed |
| 7 | At 1440 px the trip sheet's Status and Next step (Record payment, Start) were past the right edge | Fixed: menu folds to icons under 1500 px; a laptop column set (fares in the detail and Money); a visible scrollbar below that |
| 8 | Two badges in the trip detail said the same thing ("Fees due", "Terminal fees unpaid") | Fixed |
| 9 | "₱51.00 is under dispute" in a trip's payment dialog read as that trip's line | Fixed: "on this van's statement today" |
| 10 | "Payment recorded … Start is open." half an hour before Start opened | Fixed: "Start opens at 11:00 AM." |
| 11 | **A paid passenger was still told to pay**: the reservation screen showed the list's old copy | Fixed: asks the server on opening, then every 30 s |
| 12 | The same walk-up is "Walk-up passenger" before departure, "Cash passenger · TERMINAL CASH" after | Open (wording) |
| 13 | A departed trip moves to Past trips at once ("No trip booked" while riding), taking Track the van with it | Question for the owner |
| 15 | The Money ledger still said "Parking only" for a van with a trip | Fixed (the statement header was fixed on 11 Nov) |
| 17 | The SOS card said "set sos_contact_numbers in Policies" | Fixed: "no SOS numbers are set (Setup › Rules & Settings)" |
| 18 | The top bar kept "Open emergencies 1" for up to 30 s after closing it | Fixed: any action reloads the top bar and the review counts at once |
| 19 | A passenger gets no notice when the Dispatcher marks the seat Paid | Question: a server change (a notification type, a migration) |

(16 was withdrawn: the terms message does appear; the first screenshot was
taken after it had gone.)

Also seen and correct: the 1:59 AM trip became **Unaudited, "the phone went
silent on the road"**, because this computer slept from 02:31 to 06:49 and
the simulated phone stopped reporting. The system refused to invent a count.

## Limits of this run

- **Location.** The headless browser refuses geolocation whatever
  permission it is given, so check-in was tested with the page's position
  answered as the Ecoland terminal. The app and the server ran unchanged;
  the phone's own GPS was not part of it. The SOS, which never depends on
  a position, went through with "No location".
- **The phone app ran as its web build.** The camera, texting and the
  Android-only parts were not exercised; the in-van door count came from
  the simulated phone `seed_live_now.py` leaves running.
- Phones' screen sizes: one size (412 × 915). The layout tests in
  `mobile/test/layout_test.dart` cover 320 dp at 200 % text.
