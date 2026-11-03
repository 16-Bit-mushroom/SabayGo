# Day 1 test: findings

*Started 3 Nov 2026. The system was set up from an empty database, as A2Z
would on its first day: one Terminal Manager made with
`backend/scripts/create_first_manager.py`, everything else entered in the
console. One line per finding; newest at the bottom.*

| # | Where | What happened | Status |
|---|---|---|---|
| 1 | Console, sidebar | A new message did not show a number on **Messages** in the sidebar (tester). The count existed per conversation inside the page but was never added up for the menu. | **Fixed** 3 Nov: the sidebar poller counts unread messages every 30 s and opening a thread clears it. Retest |
| 2 | Console, Timetable | Trips exist only after someone presses **Create upcoming trips**. Nothing creates them nightly: `backend/scripts/generate_trips.py` is a cron job that is not installed, and the backend runs no such job. The brief has trips created "days ahead" automatically. | Open: install the cron on the server, or make it a backend job |
| 3 | Console, Terminals | Closing a terminal needs **Save changes** after switching Open off; the first attempt left all three open. The Staffed switch came out wrong twice. | UX note: easy to miss, works when saved |
| 4 | Console, Staff | The new Dispatcher was left Pending: **Validate** sits at the foot of the panel. | UX note |
| 5 | Data | From A2Z's trip-schedule poster: their route is Davao (Ecoland) → Cotabato City, every 2 h from 5:30 AM, shared with Kutoco Coop. Not on the poster: the stops, minutes and fares (test values used), how departures split with Kutoco, whether the last trip is 5:30 or 6:00 PM, and whether the Lebak/Kalamansig and Zamboanga night trips are A2Z's. | Questions for A2Z |
| 6 | Console, Setup | **Phones** counts as a required step, so with no edge phone the checklist never shows the "ready, Go to Trips" banner. The rules let a trip run without a phone: Start only warns, and the trip is Unaudited (`no_phone`). | Open: make the step optional with "every trip will be Unaudited"? Group decision (the phone is the study's core) |
| 7 | Console, Timetable | A 3:30 PM departure was saved as 3:30 AM (12-hour time picker), then switched off; the 11:30 AM departure was not added, so tomorrow had 6 trips instead of 7. | UX note: the list could show the departures in 24-hour time or group AM/PM |
| 8 | Console, Trips / Remittance | The Cashier recorded ₱125 on the 1:30 PM trip (LCT-9042: ₱75 ticket + ₱50 parking), then the Terminal Manager voided the trip. The void removes the trip's ₱75 ticket from the statement (owed now ₱50), but the ₱125 stays settled: the statement balance is −₱75 and the console shows it only as settled. The overpayment is visible nowhere. | Open: show a credit ("₱75 over") on the statement, or carry it to the van's next trip; and ask A2Z whether a voided trip's DCOTT ticket is returned |
| 9 | Console, Trips | The 3:30 PM trip's fees (₱125) were recorded before any passenger reserved. Correct by the rules, but each seat paid afterwards is a top-up and sets the trip back to Owes until the Cashier records the 15 % again. At the terminal the Dispatcher brings the cash just before Start. | UX note: the dialog could say "No passengers yet: record now only if the van leaves empty" |
