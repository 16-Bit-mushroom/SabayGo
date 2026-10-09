# Console redesign — October 2026

The cooperative office console (`operator_console/`) was redesigned to be
easier for non-technical office staff: a dark operations-dashboard look,
clearer navigation, and plain words on every page and button.

**No new features were added.** Every number, list and button on the new
screens comes from a backend endpoint the console already used. The
passenger and crew apps (`mobile/`) and the capture app are unchanged.

---

## At a glance

| | Before | After |
|---|---|---|
| Look | Light, white panels | Dark canvas, grey rounded panels, light buttons — or light mode, one click away |
| Navigation | 10 items in one sidebar | Same pages in 3 named groups, sidebar folds to icons |
| Top of the screen | Nothing | Today's figures, notifications, account menu |
| Page titles | Did not match the menu ("Trip Dispatch Command" under "Trip Dispatcher") | Match the menu word for word |
| Page purpose | Not stated | One plain sentence under every title |
| Words | System terms (manifest, leg, variance, remittance) | Office terms (passenger list, section, difference, cash turned in) |
| Empty / error screens | Different on every page | One style everywhere, saying what to do next |

---

## Dark and light mode

The **sun/moon button** in the top bar, left of the bell, switches the
whole console between dark (the default) and light.

- The choice is remembered by that browser, so each office PC keeps its
  own.
- You stay on the same page with the same trip selected; nothing
  reloads.
- Light mode is the console's earlier white palette, for a bright office
  or a washed-out projector. Both palettes pass WCAG AA.
- The map darkens its streets only in dark mode.

## Navigation

The sidebar keeps its labels so nobody has to learn icons. **Hide menu
names** at the bottom folds it to icons; hovering an icon shows its name.

| Group | Page | Was called |
|---|---|---|
| **Today** | Overview | Live Fleet |
| | Trips | Trips |
| | Special Trips | Trip Dispatcher |
| | Emergencies (SOS) | Emergency (SOS) |
| | Messages | Messages |
| **Money & checks** | Fares & Cash | Revenue |
| | Passenger Count Checks | YOLOv8 Audits |
| **Setup** | Timetable | Schedules |
| | Vans & Crew | Fleet & Crew |
| | Rules & Settings | Policies |

**Top bar.** Four clickable figures for today. Each one opens the page
that explains it:

- **Vans on the road** (and how many have no signal) → Overview
- **Trips today** (and how many are under way) → Trips
- **Checks to review** → Passenger Count Checks
- **Open emergencies** → Emergencies (SOS)

The bell and the account menu (**My profile**, **Sign out**) moved from
the sidebar to the top right. A figure that fails to load shows "—",
never "0", so the bar never says "no emergencies" when it could not
check.

---

## Pages

**Overview** (was Live Fleet)
- Full-size dark map.
- Filter chips over the map: **All / Live / No signal**.
- Clicking a van opens a card with:
  - plate and route
  - progress bar by stop ("stop 3 of 6")
  - next-stop arrival time
  - speed dial
  - passengers aboard out of seats
  - driver and conductor
- A van with no recent signal shows a warning and says to call the crew.

**Trips**
- Trip list on the left; the selected trip on the right as panels:
  - the trip, with its counts (Aboard, At terminal, Not yet boarded, Unpaid)
  - crew
  - seats booked and aboard
  - camera checks
  - passenger list
- Stops are named, not numbered: "Toril → Bangkal", not "Stop 1 → 3".
- The camera checks panel has a section dropdown, **All sections** or
  one section with its number of checks, so section 1 and section 2 can
  be read apart.
- The phone capture button is now **Check with phone camera**.

**Special Trips** (was Trip Dispatcher)
- Same form and list, in plain words.
- The time field says that a time already past books the trip for
  tomorrow, which the form always did silently.

**Passenger Count Checks** (was YOLOv8 Audits)
- Small "YOLOv8 camera" tag beside the title.
- Tabs: **Needs review / History**.
- Columns: Passenger list, Camera count, Difference.
- Buttons:
  - Flag & Resolve → **Confirm problem**
  - Ignore → **Dismiss**
  - Clear / No Action Needed → **Looks fine — close it**
- The note box gives an example, and **Save** stays off until a note is
  written. Before, an empty note did nothing without saying why.

**Fares & Cash** (was Revenue)
- Totals:
  - Collected Fare → **Fares received**
  - Cash In Hand → **Cash with crew**
  - Unreconciled → **Not accounted for**
  - Pending Audits → **Camera checks to review**
- Export menu: **Excel file** / **Plain table**.

**Timetable** (was Schedules)
- Schedule template → **regular departure**.
- Generate Trips → **Create upcoming trips**.
- Default van/driver → **usual van/driver**.
- A note that pointed to Trip Dispatcher for assigning vans was removed,
  because that page cannot assign a van to an existing trip.

**Vans & Crew** (was Fleet & Crew)
- Statuses in words:
  - vans: In service / Under repair / Not in use
  - crew: Working / Suspended / No longer working
- Provision Crew → **Add a crew member**.
- The email field no longer mentions test data.

**Rules & Settings** (was Policies)
- Each rule has a plain title, for example "Trip-change deadline before
  departure" instead of `reschedule_cutoff_hours`.
- Rules are grouped by topic, and each value shows its unit.
- The stored name stays underneath in small text for the team.

**Emergencies (SOS)**
- Acknowledge → **Mark as responding**.
- Status words: Open / Responding / Closed.

**Sign-in, start-up, browser tab**
- The logo sits on a light tile, because the black owl would disappear on
  dark.
- The browser tab reads "SabayGo — Cooperative Office" instead of
  "operator_console". Office staff are never called operators.

---

## Words

These apply on screen only. Database values and API fields are
unchanged.

| System term | On screen now |
|---|---|
| Manifest | Passenger list |
| Leg 2 | Section 2 (Toril → Bangkal) |
| Variance | Difference |
| Remittance / cash in hand | Cash turned in / cash with crew |
| Unreconciled | Not accounted for |
| Audit queue | Needs review |
| Door-close trigger | Automatic — van departed |
| GPS-node trigger | Automatic — van left a stop |
| SILENT | No signal |
| Departed | Departed (the conductor app's word, kept on purpose) |

The trigger was "doors closed". It is now "van departed" because there
is no door sensor; the check fires when the conductor departs.

The backend's audit readings and variance notifications say "passenger
list" instead of "manifest" too, for example "2 more people than the
passenger list". `tests/test_audit_reading.py` passes.

---

## Under the hood

- **Theme.** `core/design/tokens.dart` holds two palettes,
  `AppPalette.dark` and `AppPalette.light`. Every colour pairing in both
  is measured against WCAG AA; the lowest are:

  | | Dark | Light |
  |---|---|---|
  | Body text | 15.9:1 | 17.1:1 |
  | Muted text | 7.3:1 | 6.7:1 |
  | Input borders | 3.75:1 | 3.64:1 |

  `AppColors.x` reads whichever palette is in use, so colours can no
  longer sit inside `const` widgets; about 150 `const` keywords were
  removed for that.

  `core/design/appearance.dart` switches the palette, saves the choice in
  the browser, and redraws every widget with Flutter's hot-reload
  mechanism (`reassembleApplication`), which keeps each page's state.

  The console no longer copies the mobile app's colours.
- **Shared building blocks** in `core/design/components/`:
  - `PageHeader`
  - `Panel`
  - `StatTile`
  - `StatusBadge` (the one place trip and passenger status words live)
  - `LoadError`
  - `EmptyState`
  - `PersonRow`
  - `BrandPlate`

  They replace copies that each screen kept for itself.
- **One mapping for a check's outcome** (`auditOutcomeBadge`). The Trips
  page and Passenger Count Checks used to word the same result
  differently.
- **Map tiles** are still OpenStreetMap, darkened by flutter_map's
  built-in filter. There is no new map provider and the OSM credit stays.

## Left out of the reference design on purpose

The reference dashboard shows fuel level, on-time percentage, driver
rating, a compass and a 3D vehicle. SabayGo does not measure any of
these, so they are not shown. Their places on the screen show data the
system does have: passengers aboard, stop progress, and crew.

## Checks

- `flutter analyze`: no errors or warnings.
- Release web build: succeeds.
- `backend/tests/test_audit_reading.py`: all checks pass.
