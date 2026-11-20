# Known issues

Moved out of CLAUDE.md on 24 Oct 2026.

- **NAHGM's ETAs (found 16 Nov, open).** The NAHGM benchmark
  (`backend/scripts/nahgm_benchmark.py`, report
  `docs/benchmarks/nahgm_2026-11-16_1527.txt`) shows two structural
  errors that GPS noise does not explain. (1) The next stop leaves the
  ETA list as soon as it becomes the *nearest* stop, about halfway along
  the leg: on ECO-COT, 28-64 min before the van arrives, so no ETA is
  ever shown in the last 15 min before a stop. (2) Distances are straight
  hops between stops; the road is 1.26 times longer, so with a true speed
  the ETAs are about 18-28 min early on stops an hour or more ahead.
  A progress rule (`geometry.snap_to_route` is already in the code) and
  a road factor or the schedule's offsets would address both; not
  changed yet, the group decides.
- **A released seat never offers "Find another trip" (found 20 Nov,
  open).** The app shows that button for `trip_canceled` updates, but the
  server sends the unpaid release (`booking/unpaid_release.py`) as a
  plain `trip_update`, and `NotificationType.fromServer` maps no type to
  cancelled. Only saved-destination updates get their "Book a seat". A
  release type of its own, on the server and in the app, would close it.
- **Left in place by the 20 Nov health check, on purpose.** The dead-code
  sweep removed what nothing used (`PROGRESS_LOG.md`, "Pre-merge health
  check"); these it kept, for a decision after the merge:
  (1) both apps store the role and user id at sign-in and nothing reads
  them -- removing them changes sign-in in both apps;
  (2) the `yolov8_audit_logs` and `cash_remittances` tables (the retired
  AI-node audit and the rev 468 cash handover) are still in the schema,
  and their ORM classes stay because the ORM describes the schema;
  dropping them is a migration with its down script;
  (3) `PolicyRepository.get_bool` and `get_str` have no caller yet but
  belong to the typed readers every policy goes through.
- **At large text the trip card reads as one label (20 Nov).** Above
  130 % text the Dispatcher's "This trip" card (status, the four counts,
  the next step) moves into the scrolling list, and a screen reader then
  reads it as one long label; at normal size each count is its own.
  Not changed.
- **This machine has only a Java runtime (16 Nov).** `jre21-openjdk` has
  no `javac`, so Gradle stops with "does not provide the required
  capabilities: [JAVA_COMPILER]". Build the APKs with
  `JAVA_HOME=/mnt/games/home-data/Android/jdk-17`, and the edge app with
  `ANDROID_HOME=$HOME/Android/Sdk` (it has no `local.properties`).
- **The edge app's release build fails lint (old, also on main).**
  `InvalidFragmentVersionForActivityResult` in `HomeActivity.kt:63` and
  `BenchActivity.kt:54`: `registerForActivityResult` wants
  `androidx.fragment` 1.3.0 or newer on the classpath. The debug APK,
  the one the phone runs, builds and its 15 unit tests pass. Adding
  `androidx.fragment:fragment-ktx` to `app/build.gradle.kts` would clear
  it.
- **The Trips sheet is wider than a 1280 px screen (16 Nov).** At
  1280 × 720 the last column ("Next") is cut off at the right edge.

- The `--soon` reschedule failure, recorded for weeks as fixture
  self-conflict, was a reset gap (fixed 16 Oct): `reset-dev.sh` zeroed the
  policy row but not the cutoff each fixture trip copied at generation.
  The suite now has no known failure.
- An earlier failure was long recorded as fixture self-conflict
  too. It was not — it was a test bug, fixed 28 Sep. The conductor
  journey reserved its unpaid ticket *after* `start-boarding`, but
  `APP_BOOKABLE` is `{scheduled}`, so the reserve was refused, `UNPAID_QR`
  came back empty, and scanning an empty payload returned `wrong_trip`.
  The unpaid-at-the-door verdict was never actually under test. The
  reserve now happens while the trip is still `scheduled`. Lesson: a
  failing assertion inherited as "known fixture noise" is worth
  re-deriving once.
- The ticket screen polls `GET /bookings/{id}` every 4 s while a booking
  is pending, capped at ~2 min; after the cap it offers a manual "check
  again". A webhook-driven push would remove the poll, but that is FCM.
- Passenger avatar hits `i.pravatar.cc` on every build; fails offline.
- AGP 8.11.1 and Kotlin 2.2.20 are below what Flutter will soon require.
  Deferred deliberately.
- Dev-account chips on the sign-in screen are guarded by
  `AppConfig.isDebug`. Confirm they are absent from a release build.
- The live map needs internet access for OpenStreetMap tiles. OSM's tile
  policy is for modest use and asks for an identifying user agent, which
  both maps send; a defence-room demo is well inside it, but heavy
  automated polling is not.
- **The manuscript claims five things the code does not do.** Google Maps
  SDK (it is OpenStreetMap via `flutter_map`), Firebase Authentication (it
  is JWT), FCM background push (rows are polled; FCM is schema-ready,
  `delivery_status` stays `queued`), Twilio as *the* SOS mechanism (it is
  one of three `SMS_PROVIDER` options and not the default), and "door
  closures" (there is no door sensor). Replacement wording for each, ready
  to paste, is in `docs/MANUSCRIPT_CORRECTIONS.md` — edit the `.docx`, not
  the `.docx.md`, which is a pandoc export and reaches nothing.
- SOS contact numbers are seeded for the demo (28 Sep) in
  `002_demo_dataset.sql`, as two placeholders on the **+63 900** prefix,
  which is not assigned to any Philippine network — so they cannot reach a
  real handset even if `SMS_PROVIDER` is switched off `disabled`. Swap
  them for A2Z's real numbers before the pilot, and only then, because
  from that moment a raised SOS texts actual people. Migration 016 still
  ships the policy **empty**, which is correct for production.
- `datetime.now(timezone.utc)` written into a naive Manila DATETIME
  column skews it eight hours. Fixed in `boarding.py` (14 Sep),
  `trigger_audit.py`, `payments.py`, `register_passenger.py`, `auth.py`
  and the `trips.py` search guard (15 Sep). The only remaining use is
  `seat_repository.py` (seat-hold expiry), left alone because it is the
  thesis file and any change there needs its own review — and
  `security.py`, where UTC is correct because JWT `exp` is epoch time.
- **The model-evaluation report exists**:
  `docs/benchmarks/ai_count_2026-10-09_full.txt` (COCO val2017, all
  degradation conditions, five-point threshold sweep, `yolov8n.pt` at
  640 px). The phone runs the same weights at 320 or 416 px, so the
  paper should say the counting error is at 640 px until a re-run at the
  phone's size exists. No staged in-van set yet (see
  `ai_service/eval/README.md`).
- **There is no physical door sensor.** "Door" means the door line in the
  phone camera's view (door events); say it that way in the paper.

