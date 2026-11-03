# Handoff: after the Day 1 test (3 Nov 2026)

*Written at the end of the session that finished S9 and S10 of the rev
721 refactor and ran the Day 1 test. Read this, then
`docs/DAY1_FINDINGS.md`; `docs/DAY1_TEST_GUIDE.md` is the procedure.*

## Where we left off

- **Branch `rev721-frontends`**, not merged into `main` and not pushed.
  It holds S9 (console), S10 (app) and every Day 1 fix, one commit each.
- **Rev 721 status** (`docs/GAP_REPORT.md` §10.4): S1–S6, S8, S9, S10
  done. Left: **S7** (special trips: walk-in fee basis, counter flow; not
  re-checked since rev 603) and **S11** (docs: `README.md`,
  `START_HERE.md`, `PRODUCT.md`, `docs/DEMO_SCRIPT.md`, `docs/SETUP.md`,
  `KNOWN_ISSUES.md`, `MANUSCRIPT_CORRECTIONS.md`,
  `QUESTIONS_FOR_COOPERATIVE.md`).
- **The Day 1 test passed end to end**: setup from an empty database
  through the console, then one cash trip from reservation to statement.
  23 findings: 10 fixed the same day, 7 open, 2 questions for A2Z, 4 UX
  notes.
- **Journey scripts run after the fixes:** `test_terminal_fees.sh` 79/0
  (10 new checks for the top-up bugs) and `test_trip_lifecycle.sh`
  135/0. **Full suite** at `f0d34d6`: **1070 passed, 0 failed, 0 gaps**
  (`docs/test-reports/journeys_20261103_154759.txt`).
- **Not tried on a phone yet.** The whole test ran in a browser; the APK
  builds but the new screens have not been on a handset.

## The Day 1 data

`./db/load-day1.sh` rebuilds the database from the migrations and loads
`db/day1/day1_a2z.sql`: A2Z's terminals, the Ecoland – Cotabato route
and fares, two operators with vans, the staff (`@a2z.dev`, password
`sabaygo123`), the timetable, the settings, and the 3 Nov trips with the
one trip that ran. The passenger's real email and number were replaced
with `chris@a2z.dev` and a dev number. After loading, press **Create
upcoming trips** for trips from today. The demo dataset
(`./run.sh --reset-db`) is unchanged and is still what the journey
scripts use.

## Open, in the order I would take them

| # | What | Kind |
|---|---|---|
| 8 | A voided trip, or a van changed after payment, leaves money recorded on a statement that no longer owes it; the console shows only "settled" | Money: show the credit, or carry it forward. Ask A2Z whether a voided trip's DCOTT ticket is returned |
| 23 | Brief §4.2 rule 11 has the Terminal Manager review Unaudited trips; no list gathers them (only an alert and the trip's panel) | List the day's Unaudited trips at the top of Boarding Audit |
| 2 | Trips exist only after **Create upcoming trips**; nothing runs nightly | A backend periodic job (as `unpaid_release` is), or install the cron |
| 17 | A wrong departure cannot be deleted | **Delete** only when it never made a trip |
| 6 | **Phones** is a required checklist step, so with no edge phone the checklist never reads "ready" | Group decision |
| 22 | Passenger **Track the van** is out of scope by the brief, but the passenger's SOS is on that map | Group decision: move SOS to the reservation screen, then hide the map |
| 19 | Console text is heavy: descriptions under every heading | Its own session with the impeccable skill |
| 5, 16 | Stops' minutes, fares, the Kutoco split, the night trips; whether vans leave early when full | Questions for A2Z |

Then S7 and S11.

## Traps found on the day

- **The backend does not reload.** `run.sh` starts uvicorn without
  `--reload`; after a backend change stop it and start it again (the
  console build is skipped when `lib/` is unchanged).
- **The app's theme makes every FilledButton full width**
  (`mobile/lib/core/design/theme.dart`, `Size.fromHeight`). One placed
  in a row must set `minimumSize`, or it squeezes its neighbours (finding
  10).
- **Bit shifts are 32-bit on the web.** `1 << 32` is 0 in the browser
  build; `nextInt(0)` threw and the walk-up was never sent (finding 13).
- **Every button press must report failure.** The walk-up screen caught
  only server errors, so a local exception looked like a dead button.
- **The `mysql` client prints cp1252** unless given
  `--default-character-set=utf8mb4`: the "–" in "Cooperative Van Terminal
  – Ecoland" became byte 0x96 and crashed `tracking_simulator.py`.
- **Fees recorded before any seat** are correct by the rules but make
  every later paid seat a top-up. At the terminal the Dispatcher brings
  the cash just before Start.
- **The journey scripts reset the database.** Save it first:
  `docker exec -e MYSQL_PWD=<root password> sabaygo-mysql mysqldump -uroot
  --single-transaction --default-character-set=utf8mb4 sabaygo > backup.sql`,
  and restore with `mysql ... sabaygo < backup.sql`.
- **Firefox has no Sensors panel**: the check-in location is faked
  through `about:config` (`docs/DAY1_TEST_GUIDE.md` §1.6).
- Known and unrelated: four widget tests in `mobile/test/layout_test.dart`
  fail on `main` too (a missing provider in the harness).
