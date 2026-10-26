# Known issues

Moved out of CLAUDE.md on 24 Oct 2026.

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

