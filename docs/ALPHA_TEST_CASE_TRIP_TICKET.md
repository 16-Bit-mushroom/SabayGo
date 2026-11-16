# Alpha test case: A2Z trip ticket Nº 0012223, five trips

*Run by hand on 10 Nov 2026 before the alpha, on the Day 1 data
(`./db/load-day1.sh`). The automated twin is
`backend/tests/integration/test_trip_ticket.py`. Findings from the run
are 24–33 in `docs/DAY1_FINDINGS.md`.*

## The reference

A2Z's paper trip ticket Nº 0012223 (Gold Silver Diamond Management
Consultancy Services Corporation, 10/23, 11:22, plate withheld):

| Destination | Fare | Passengers | Gross |
|---|---|---|---|
| Cotabato | ₱363 | 2 | ₱726 |
| Cotabato, senior (₱363 less 20 %) | ₱290 | 4 | ₱1,160 |
| (third line, unclear) | ₱149 | 1 | ₱149 |
| Digos | ₱150 | 1 | ₱150 |
| **Total** | | **8** | **₱2,185** |

Terminal fees on the ticket: 15 % ₱327.75 + parking ₱50 + DCOTT ₱75 =
**₱452.75**. SabayGo computes the same three fees in the same way.

**What SabayGo cannot match yet:** the senior fare (no discount fares,
finding 32) and the ₱149 line (not a fare on the route). Trip 1 below
therefore counts the four seniors at ₱363 and the unclear passenger as
Kidapawan (₱340): the expected amounts are SabayGo's, worked by hand.

## Users (password `sabaygo123`)

| Who | Account | Made by |
|---|---|---|
| Terminal Manager | `manager@a2z.dev` | Day 1 |
| Cashier | `joy@a2z.dev` | Day 1 |
| Dispatchers | `ramon@a2z.dev`, `liza@a2z.dev` (validate Liza first) | Day 1 |
| Dispatcher (new) | `nonoy@a2z.dev`, Nonoy Abellana, 0918 123 4567 | Terminal Manager, Setup → Staff, then **Validate** |
| Passengers (new) | `andrea.villamor@`, `rogelio.tan@`, `grace.dumaguing@a2z.dev` | each signs up in the app |
| Passenger | `chris@a2z.dev` | Day 1 |

## Setup (Terminal Manager, console)

1. **Setup → Fares:** Digos City Terminal **₱150**, Cotabato City Terminal
   **₱363**, takes effect today → **Save 2 fares**. Kidapawan stays ₱340.
2. **Setup → Operators & vans:** Add operator **Arnel Bautista**,
   0917 123 4567, licence N03-22-145678, expiry 31 Dec 2028 → Save →
   **Validate**. Vans → Add van: operator Arnel, plate **TST-1023**,
   Toyota Hiace, 14 spaces, cabin camera → Save; add its four photographs;
   **Validate**.
3. **Setup → Staff:** add Nonoy (above) → Save → **Validate**.
4. **Rules & Settings** (for the test only; put them back to 30 and 45
   afterwards): **When Start opens** 300 minutes, **When check-in opens**
   300 minutes.
5. **Setup → Timetable:** add **11:20 AM**, **12:00 PM**, **12:40 PM**,
   today's weekday only, then **Trips → Post the timetable for 7 days** (was "Create upcoming trips" on the Timetable). With the Day 1
   timetable this gives six trips today: 11:20, 12:00, 12:40, 13:30, 15:30,
   17:30.

## The five trips

Stops: 2 Digos ₱150 · 3 Kidapawan ₱340 · 4 Cotabato ₱363. "Booked" =
reserved in the app and marked **Paid** by the Dispatcher; "walk-in" =
listed by the Dispatcher (paid as listed).

| Trip | Van · Dispatcher | Passengers | Gross | 15 % | Fees due | Operator's share |
|---|---|---|---|---|---|---|
| 1 · 11:20 | TST-1023 · Nonoy | booked: Andrea, Rogelio → Cotabato; walk-ins: 4 → Cotabato, 1 → Kidapawan, 1 → Digos | ₱2,668 | ₱400.20 | **₱525.20** (+₱75 +₱50) | ₱2,142.80 |
| 2 · 12:00 | ABC-1234 · Ramon | booked: Grace → Kidapawan, Chris → Cotabato; walk-ins: 3 → Cotabato, 2 → Digos | ₱2,092 | ₱313.80 | **₱438.80** | ₱1,653.20 |
| 3 · 12:40 | LCT-9042 · Liza | Rogelio reserves → Digos and **cancels** (unpaid); walk-ins: 6 → Cotabato, 3 → Digos, 1 → Kidapawan | ₱2,968 | ₱445.20 | **₱570.20** | ₱2,397.80 |
| 4 · 13:30 | TST-1023 · Nonoy | booked: Grace → Digos; walk-ins: 5 → Cotabato | ₱1,965 | ₱294.75 | **₱369.75** (no second parking) | ₱1,595.25 |
| 5 · 15:30 | ABC-1234 · Ramon | walk-ins: 7 → Cotabato, 1 → Kidapawan; operator disputes the Kidapawan line | ₱2,881 | ₱432.15 → ₱403.65 | **₱478.65** after the decision | ₱2,402.35 |
| | | | | | **₱2,382.60** the day | |

Each trip, in order:

1. **Terminal Manager → Trips:** pick the trip → **Assign van and
   Dispatcher**. *Expect:* "Terminal fees not recorded yet … Start waits for
   them", and **Start trip** greyed out with that reason.
2. **Passengers (app):** reserve → note the **booking code** (unpaid).
3. **Dispatcher (app):** find each by name or code → **Mark as Paid**; list
   the walk-ins with their destinations.
4. **Cashier → Money:** the van's statement shows the lines and the fees
   due above → **Record payment** (receipt: the paper ticket's number;
   the operator's share is filled in). *Expect:* Due now ₱0.00, the bars at
   100 %.
5. **Cashier or Terminal Manager → Trips:** **Start trip**. With no phone
   in the van: "Started, with warnings … Unaudited".
6. **Dispatcher:** **Depart**, then **Arrived**.

Special checks:

- **Trip 3:** the cancelled reservation shows "Reservation cancelled and
  the seat released" and adds nothing.
- **Trip 4:** the van's statement adds ₱75 for the trip and **no** second
  ₱50: due ₱369.75. The operator's-share hint reads "₱1,595.25 still to
  give of ₱3,738.05 owed today".
- **Trip 5:** Money → the Kidapawan line → **Record dispute** ("got off at
  Digos"): due drops to ₱456.15 (₱51.00 waits). Reviews → Disputes →
  **Adjusted** to ₱22.50 with a note: due ₱478.65.
- **After all five:** Money shows terminal fees ₱2,382.60, paid ₱2,382.60;
  the chart's bar for today is ₱2,382.60; Trips shows "8 of 14 spaces
  booked" on trip 1 after it left.

## Run it automatically

```bash
./db/load-day1.sh
backend/venv/bin/python backend/tests/integration/test_trip_ticket.py
```

It sets the departures 40–80 minutes from now (run before 22:40) and
checks every amount above; `run_all_journeys.sh` runs it on fresh Day 1
data.
