# Manual input sheet: the alpha data

Everything the alpha database held on 20 Nov 2026, before it was emptied, in the order the console's **Setup** asks for it. Type it back in by hand and note every place a task is slow, confusing or takes a jump to another screen.

- **Full backup** (restorable): `db/backups/alpha_before_empty_20261120_0932.sql`. To go back to it instead of typing: `./db/apply.sh --reset`, then load that file the way `db/load-day1.sh` loads its SQL.
- **Van photos** (four per van, needed before a van can be validated): `db/backups/van_photos/<plate>/front|rear|left|right`.
- **Passwords**: every account below used `sabaygo123`.
- **Left out**: the phone (door camera) and its set-up code, since the camera audit is out of scope for this round; and trips, bookings, fees and money, which the test itself creates.

## 0. Before Setup: the first Terminal Manager

Staff do not self-register, so the first manager is made once from the laptop (already done for this round):

| First | Last | Email | Phone |
|---|---|---|---|
| Maria | Santos | manager@a2z.dev | +639171110001 |

## 1. Terminals

| Name | City | Address | Latitude | Longitude | Zone (m) | Staffed | Active |
|---|---|---|---|---|---|---|---|
| Carmen Terminal | Carmen |  | 7.362000 | 125.706000 | 120 | yes | no |
| Cooperative Van Terminal – Ecoland | Davao City | In front of SM City Ecoland, Quimpo Boulevard, Davao City | 7.051048 | 125.587456 | 200 | yes | yes |
| Cotabato City Terminal | Cotabato City |  | 7.221700 | 124.246700 | 150 | yes | yes |
| Digos City Terminal | Digos | Digos City | 6.738249 | 125.365530 | 150 | yes | yes |
| Kidapawan City Terminal | Kidapawan |  | 7.008300 | 125.089700 | 150 | no | yes |
| Panabo City Terminal | Panabo City |  | 7.308000 | 125.684000 | 150 | no | no |
| Tagum City Overland Terminal | Tagum City |  | 7.447800 | 125.807800 | 200 | yes | no |

## 2. Route

### ECO-COT · Davao (Ecoland) – Cotabato City

LTFRB case no.: (none) · active: yes

| Stop | Terminal | Minutes from start |
|---|---|---|
| 1 | Cooperative Van Terminal – Ecoland | 0 |
| 2 | Digos City Terminal | 90 |
| 3 | Kidapawan City Terminal | 195 |
| 4 | Cotabato City Terminal | 300 |

## 3. Fares

### ECO-COT · Davao (Ecoland) – Cotabato City

| From | To | Fare (₱) | In force from |
|---|---|---|---|
| Cooperative Van Terminal – Ecoland | Digos City Terminal | 135.00 | 2026-11-03 |
| Cooperative Van Terminal – Ecoland | Kidapawan City Terminal | 340.00 | 2026-11-03 |
| Cooperative Van Terminal – Ecoland | Cotabato City Terminal | 500.00 | 2026-11-03 |
| Cooperative Van Terminal – Ecoland | Digos City Terminal | 150.00 | 2026-11-20 |
| Cooperative Van Terminal – Ecoland | Cotabato City Terminal | 363.00 | 2026-11-20 |

A later row for the same pair is a fare change: enter the older one first, then the new one with its date.

## 4. Operators & vans

| Operator | Contact | Email | Licence no. | Licence expiry | Membership | Validation |
|---|---|---|---|---|---|---|
| Arnel Bautista | +639171234567 |  | N03-22-145678 | 2028-12-31 | active | validated |
| Juan Dela Cruz | +639170000003 |  | N01-23-456789 | 2028-06-30 | active | validated |
| Pedro Lumbay | +639170000006 |  | N01-22-118734 | 2030-09-30 | active | validated |

| Plate | Operator | CPC case no. | CPC no. | Brand | Model | Colour | Seats | Route | Status | Validation |
|---|---|---|---|---|---|---|---|---|---|---|
| ABC-1234 | Juan Dela Cruz |  |  | Toyota | Hiace |  | 14 | ECO-COT | active | validated |
| LCT-9042 | Pedro Lumbay |  |  | Nissan | Urvan |  | 14 | ECO-COT | active | validated |
| TST-1023 | Arnel Bautista |  |  |  |  |  | 14 |  | active | validated |

## 5. Staff

| Role | First | Middle | Last | Email | Phone | Birth date | Gender | Address | Terminal | Validation |
|---|---|---|---|---|---|---|---|---|---|---|
| Terminal Manager | Maria |  | Santos | manager@a2z.dev | +639171110001 |  |  |  |  | pending |
| Cashier | Joy |  | Alcantara | joy@a2z.dev | +639171110002 |  |  |  |  | pending |
| Cashier | Rose |  | Lim | rose@a2z.dev | +639181234570 |  |  |  |  | pending |
| Dispatcher | Nonoy |  | Abellana | nonoy@a2z.dev | +639181234567 |  |  |  |  | validated |
| Dispatcher | Jun |  | Bautista | jun@a2z.dev | +639181234568 |  |  |  |  | validated |
| Dispatcher | Liza |  | Cruz | liza@a2z.dev | +639171110004 |  |  |  |  | validated |
| Dispatcher | Mae |  | Ocampo | mae@a2z.dev | +639181234569 |  |  |  |  | validated |
| Dispatcher | Ramon |  | Villanueva | ramon@a2z.dev | +639171110003 |  |  |  |  | validated |

## 6. Trip Schedules

Days: 1 = Monday … 7 = Sunday, as the database stores them.

| Route | Departs | Days | Label | From | Until |
|---|---|---|---|---|---|
| ECO-COT | 03:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 05:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 07:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 09:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 13:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 15:30 | 1111111 |  | 2026-11-03 |  |
| ECO-COT | 17:30 | 1111111 |  | 2026-11-03 |  |

Then **Trips → Post 7 days of trips**.

## 7. Rules & Settings

**Change these** (the alpha value differs from the empty database's default):

| Setting | Group | Empty DB has | Alpha had |
|---|---|---|---|
| Release unpaid reservations before departure | Booking and changes | 30 | 5 |

Release unpaid reservations was 5 min for the home test; A2Z's real value is 30.

<details><summary>Already the same in an empty database</summary>

| Setting | Group | Value |
|---|---|---|
| How far ahead passengers can book | Booking and changes | 7 |
| Seats that can be booked ahead | Booking and changes | 14 |
| Largest chat image, in KB (10 MB) |  | 10240 |
| Days chat pictures are kept | Evidence and privacy | 30 |
| When check-in opens | At the terminal | 45 |
| DCOTT ticket per trip | Trips and payment | 75.00 |
| Size of a terminal area | At the terminal | 150 |
| Seats in a new van | Vans and tracking | 14 |
| Readings that make a GPS departure | Departure and home pickup | (not set) |
| Terminal zone for a GPS departure | Departure and home pickup | (not set) |
| Average speed behind each stretch's expected time, applied when the stretch is saved |  | 55 |
| A phone is silent after | Phones and camera | 120 |
| Farthest a home pickup may be from the route | Departure and home pickup | (not set) |
| How long the van waits at a home pickup | Departure and home pickup | 10 |
| Days before a driver licence expires that the office is warned. |  | 30 |
| Above the limit this long is overspeed | Driving flags | 10 |
| Parking per van per day | Trips and payment | 50.00 |
| Share of a van's daily gross fares remitted to the cooperative, in percent |  | 15.00 |
| Days blurred stills and GPS logs are kept | Evidence and privacy | 30 |
| A slow stretch is over its expected time by | Driving flags | 25 |
| Numbers texted on an emergency (SOS) | Safety | (not set) |
| Speed limit on a special trip | Driving flags | (not set) |
| At or below this speed the van is standing still |  | 2 |
| When Start opens | Trips and payment | 30 |
| An unscheduled stop is longer than | Driving flags | 120 |
| How often an in-vehicle unit should report its position. |  | 10 |
| Show "No signal" after | Vans and tracking | 120 |
| Walk-in passengers must give details | At the terminal | false |

</details>

## 8. Passengers (they register themselves in the app)

| First | Middle | Last | Email | Phone | Gender | Address | Emergency contact | Relation | Contact no. |
|---|---|---|---|---|---|---|---|---|---|
| Grace |  | Dumaguing | grace.dumaguing@a2z.dev | +639193334455 |  |  |  |  |  |
| Chris |  | Estil | chris@a2z.dev | +639171110005 |  |  |  |  |  |
| Paolo |  | Reyes | paolo.reyes@a2z.dev | +639174445566 |  |  |  |  |  |
| Lea |  | Santiago | lea.santiago@a2z.dev | +639185556677 |  |  |  |  |  |
| Rogelio |  | Tan | rogelio.tan@a2z.dev | +639182223344 |  |  |  |  |  |
| Andrea |  | Villamor | andrea.villamor@a2z.dev | +639171112233 |  |  |  |  |  |

## 9. Today's trips as the alpha seed left them

For re-creating the same day: assign each van and Dispatcher on **Trips**.

| Departs | Route | Label | Extra | Van | Dispatcher | Status then |
|---|---|---|---|---|---|---|
| 09:04 | ECO-COT | Extra trip (paid later) | yes | ABC-1234 | Mae Ocampo | departed |
| 09:08 | ECO-COT | Extra trip | yes | TST-1023 | Nonoy Abellana | departed |
| 09:30 | ECO-COT |  | no | LCT-9042 | Liza Cruz | departed |
| 13:30 | ECO-COT |  | no |  | Jun Bautista | scheduled |
| 15:30 | ECO-COT |  | no |  | Ramon Villanueva | scheduled |
| 17:30 | ECO-COT |  | no |  |  | scheduled |
