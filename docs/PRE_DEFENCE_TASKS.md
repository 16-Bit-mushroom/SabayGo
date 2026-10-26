# Before the defence: five tasks

*Written 19 October 2026. These are the open items of
`REMAINING_WORK.md` ("Open, 18 October") plus the demo rehearsal, as steps.
The defence date waits on endorsement, so the order below is by risk:
the panel will ask about the camera first.*

| # | Task | Who | Needs | Can start |
|---|---|---|---|---|
| 1 | Test door counting with people, then in a van | owner + team | a laptop running the system, the Realme, 3+ people, an A2Z van | now |
| 2 | Benchmark Run on vehicle power (part 2) | owner | the Realme, a van trip, a car charger | with task 1's van day |
| 3 | Get A2Z's figures and enter them | owner asks A2Z; team enters | the printed questions | now (answers take days) |
| 4 | Put the corrections into the manuscript | owner | the `.docx` | now; one sentence waits on task 2 |
| 5 | Rehearse the demo | whole team | tasks 1–3 settled | last, and again the morning of the defence |

Tick each box as you go. A task is done when its **Done when** line is
true, not when its steps are.

---

## Task 1 — Test door counting

**Why.** The camera's door count is the project's contribution, and it
has never counted real people. The app reaches the server and uploads
(18 Oct), but no one has walked across its door line.

**Set the phone up (once).**

- [ ] On the laptop: `./run.sh`. Note the address it prints; the phone
      uses `http://<that address>:8000/api/v1`.
- [ ] Console as `manager@sabaygo.dev` → **Phones** → add the Realme. The
      token is shown **once**: copy it.
- [ ] On the phone, open the edge app (`com.sabaygo.edge`, built from
      `edge_app/`) → **Set-up** → the server address and the token. (Debug build, over adb instead:
      `adb shell am start -n com.sabaygo.edge/.HomeActivity --es server URL --es token TOKEN`.)
- [ ] **Checklist** in the app: camera and location allowed (Location
      "Allow all the time"), battery optimisation off, and the Realme
      switches the app cannot check for itself (auto-launch, background
      activity).

**Make the phone count.** It counts only while a trip is assigned to its
van, from assignment until arrival.

- [ ] Console → **Phones** → check the phone out to a van and a
      Dispatcher.
- [ ] Console → **Trips** → pick a trip on that van's route → **Start and
      departure** panel → assign the same van and Dispatcher.
- [ ] On the phone: **Door line**. Drag the yellow line across the
      doorway, the red box over the driver's seat, set the cabin arrow,
      **Save**. (The line is stored on the van; the next phone in that van
      loads it.)

**Test A: a doorway, not a van.** Mount the phone where it would sit in a
van: above and to the side of the door, looking down at the doorway.

- [ ] Write the script before anyone walks. About 30 crossings, mixed:
      one person in; one out; two side by side; one who stops on the
      line; one who steps in and backs out; one already inside when
      counting starts (must **not** count as a boarding); one sitting in
      the "driver's seat" box (must never be tracked).
- [ ] One person keeps the true tally on paper, or films it on a second
      phone.
- [ ] Walk the script. Then compare with what the system recorded: the
      Dispatcher app's trip dashboard (count aboard) and the console's
      **Boarding Audit**.
- [ ] Repeat once in poor light (evening, or lights off).

**Test B: in an A2Z van.** Same set-up, phone mounted in the van.

- [ ] Parked at the terminal: repeat Test A's script with the van's real
      door.
- [ ] One real trip. The phone does not need a network on the road: it
      keeps counting for its van and holds everything in its outbox, then
      sends it when it is back in range. Open the app while still
      connected, so it has the trip.
- [ ] At arrival, compare its boardings and alightings with the
      Dispatcher's passenger list and a hand tally.

**Write it down.**

- [ ] Create `docs/benchmarks/door_count_<date>.md`: for each test, true
      boardings and alightings against counted ones, false events,
      missed crossings, and the conditions (phone height and angle,
      light, how many people, 320 or 416 px).
- [ ] State only what was measured. No accuracy figure beyond these
      runs, and no frame rate (that is task 2).

**Done when** the file exists with Test A and Test B results, and every
miscount has a note on why it happened (angle, light, two people
together, someone lingering).

---

## Task 2 — Benchmark Run on vehicle power

**Why.** Part 1, the bench Sweep (`docs/benchmarks/edge_sweep_2026-10-18.md`),
picked the model and backend: 320 px, CPU FP16. It ran 10 minutes on a desk.
A van trip is the real test: heat, battery and throttling. Until this Run
exists, no frame rate may be quoted in the paper, the slides or the
defence.

**Steps.**

- [ ] The Run and the counting service cannot share the camera, so use
      a different trip from task 1's Test B (opening **Benchmark** stops
      counting).
- [ ] Phone mounted, plugged into the van's power (car charger). Note the
      charger's wattage.
- [ ] Edge app → **Benchmark** → **Run**: model YOLOv8n 320, backend
      `cpu-fp16`, *Min ms between runs* 0. Start at departure.
- [ ] Keep the app on screen for the whole trip; leaving it ends the run.
      **Stop** at arrival.
- [ ] Note the conditions: route, trip length, time of day, weather,
      aircon on or off, where the phone was mounted.
- [ ] Pull and summarise:
      `adb pull /sdcard/Android/data/com.sabaygo.edge/files/ results/`
      then `python3 edge_app/tools/summarise_benchmark.py results/bench_*.csv`.
- [ ] Write `docs/benchmarks/edge_run_<date>.md` in the same shape as the
      Sweep report: the summary table, highest battery temperature,
      thermal status, battery % start and end, and the frames per second
      held over the trip. Say that the phone still had its owner's apps
      installed (decided 14 Oct; a short Run after the factory reset
      confirms the figures).

**Done when** the report is in `docs/benchmarks/`. Its frames-per-second
figure is the one the manuscript and the slides may quote, and only
with its conditions.

---

## Task 3 — Get A2Z's figures and enter them

**Why.** Several settings ship unset, and unset turns the feature off:
no GPS departure, no home pickup, no speed flag on rentals, only stops
flagged on the road. The routes, fares and SOS numbers are placeholders.

**Ask.**

- [ ] Print `docs/QUESTIONS_FOR_COOPERATIVE.md` (English, Tagalog or
      Bisaya). Part A goes to any Dispatcher, Part B to the Terminal
      Manager or the office.
- [ ] Ask for the documents at its end: each route with its terminals in
      order; the LTFRB fare between each pair of terminals; the daily
      timetable; the vans (plate, operator, licence, LTFRB case number);
      the Dispatchers' names.
- [ ] Ask who A2Z's data privacy contact is (name and position) for the
      camera notice.

**Measure (site survey).**

- [ ] `depart_readings` is set on site: at the terminal, note how many GPS
      readings a van takes to be clearly outside the terminal zone once
      it leaves. Pair it with the radius A2Z gives for
      `depart_zone_radius_m`.

**Enter, in the console as `manager@sabaygo.dev`.**

- [ ] **Rules & Settings**: `depart_zone_radius_m`, `depart_readings`,
      `home_pickup_max_route_m`, `special_trip_speed_kmh`, and any other
      answer the questions' last paragraph maps to a setting. Each change
      is kept in that setting's history.
- [ ] **Routes & Fares**: the terminals (name, city, coordinates,
      terminal zone), then each LTFRB route with its stops in order
      (fixed once saved: check them before Save), then the fare from the
      starting terminal to each drop-off, dated when it takes effect.
      Take the demo routes out of service there rather than editing
      `db/seed/002_demo_dataset.sql`: the demo script depends on its trips
      (see the caution below).
- [ ] **Rules & Settings → speed limits by route**: each stretch's limit.
- [ ] **Member Records → Import**: download the template, fill in vans and
      operators, preview, confirm. Then validate each record (whoever
      imported a record cannot validate it). Add the van photos.
- [ ] **Member Records**: add each Dispatcher (each gets their own login).
- [ ] **Timetable**: the departures for each route.
- [ ] **SOS numbers** (`sos_contact_numbers` in Rules & Settings) **last**,
      and only once A2Z has confirmed each number. From that moment a
      raised SOS texts real people.

**Caution for the demo.** `DEMO_SCRIPT.md` walks the seeded Ecoland –
Cotabato "First Trip". Keep A2Z's real data in a separate database or
seed file until after the defence, or rewrite the demo steps against the
real data and rehearse that instead.

**Done when** no setting in Rules & Settings shows "not set" except ones
A2Z chose to leave off, and the real network is entered where the pilot
will run.

---

## Task 4 — Put the corrections into the manuscript

**Why.** The paper still claims things the system does not do (Google
Maps, Firebase sign-in, push notifications, door sensors).
`docs/MANUSCRIPT_CORRECTIONS.md` has the replacement wording, section by
section.

**Steps.**

- [ ] Edit the **`.docx`** (the owner's copy; it is not in the repo), not
      `docs/ACM_GoEstilFernandez _ GROUP 4.docx.md`. That file is a
      one-way export, and changes there reach nothing.
- [ ] Work through `MANUSCRIPT_CORRECTIONS.md` §1 to §12 in order. Each
      section names the place (§ and the export's line number) and gives
      the text to paste. §3, §7 and §9 are marked **superseded: do not
      paste**; read their note for what applies instead.
- [ ] §11 (data dictionary) and §12 (rev 603 points the code settled):
      update the tables and wording they list.
- [ ] Leave one placeholder for the phone's frame rate and the door-count
      results. Fill it from tasks 1 and 2, with their conditions, or
      write that they were not yet measured. Never a guessed number.
- [ ] Wording rules from the brief: "Dispatcher", never Conductor; "A2Z";
      "passengers"; no promotional adjectives; there is no physical door
      sensor ("the door line in the phone camera's view").
- [ ] Have a second team member check the edited `.docx` against the
      corrections file.

**Done when** every section of `MANUSCRIPT_CORRECTIONS.md` is either in
the `.docx` or marked superseded, and the measured figures (or "not yet
measured") are in place.

---

## Task 5 — Rehearse the demo

**Why.** Much changed after the last full rehearsal (15 September): new
screens, the share before Start, the edge app. Find what breaks in a
rehearsal, not in front of the panel.

**The day before.**

- [ ] `./run.sh --soon` on the demo laptop. This rebuilds the demo data
      with the First Trip departing in 20 minutes (so check-in is open),
      and builds the console if needed (~3.5 min, which is why it runs
      the day before).
- [ ] `./run.sh --mobile` with the phone attached, so the app is built
      against this network's address.
- [ ] `cd backend && ./tests/integration/run_all_journeys.sh`, with the
      backend venv activated and `backend/.env` exported (otherwise every
      payment step fails as "unpaid"). The last recorded result is 922
      passed, 0 failed (16 Oct). Any failure gets fixed or explained
      before the rehearsal.
- [ ] `backend/scripts/demo_rehearsal.sh`: green all the way down.

**The rehearsal.** One person runs it, one times it, one notes problems.

- [ ] Walk `docs/DEMO_SCRIPT.md` rows 1 to 14 on the real devices: the
      passenger phone, the Dispatcher phone, the console as `manager@`,
      and `cashier@` in a private window (row 9a).
- [ ] Time it against the slot the panel gives.
- [ ] Write down every step that does not match the screen.
- [ ] Decide whether the edge phone is shown live. If task 1 went well,
      a few people crossing the door line fills row 10's count. If not,
      leave it out and fill Boarding Audit with
      `tests/integration/test_door_check.sh` on a reset database (row 11
      explains).

**Fix the script.** `DEMO_SCRIPT.md` is out of date in places:

- [ ] The header still says "Rehearsed 15 September": change it to this
      rehearsal's date.
- [ ] The set-up block shows the old manual commands; `./run.sh --soon` is
      what the demo uses now.
- [ ] Rows 7 to 9 say "Conductor": it is **Dispatcher**.
- [ ] Any row the rehearsal found wrong.

**The morning of the defence.**

- [ ] `./run.sh --soon` (the live trips are dated from the reset, so
      reset shortly before), then `demo_rehearsal.sh`. A red ✘ gets fixed
      before anything else.
- [ ] If the venue's network differs from the rehearsal's, run
      `./run.sh --mobile` again so the app points at the new address.
- [ ] The Overview map's streets need internet (OpenStreetMap tiles).

**Done when** one full rehearsal ran end to end within the time slot
with no unexplained failure, and `DEMO_SCRIPT.md` matches what is on
screen.

---

## After these

One Impeccable critique of the Dispatcher's trip dashboard, fixing only
P0 and P1 findings:
`/impeccable critique mobile/lib/views/dispatcher`. It is the screen used
at the van door and in the demo, and the 15 October screens have not been
checked on a phone. Anything wider waits until after the defence.
