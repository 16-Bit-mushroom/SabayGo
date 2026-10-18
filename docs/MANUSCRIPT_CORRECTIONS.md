# Manuscript corrections

Every place the manuscript claims something the code does not do, with
replacement wording ready to paste.

`docs/ACM_GoEstilFernandez _ GROUP 4.docx.md` is a **pandoc export**, not
the manuscript. Editing it changes nothing. Make these edits in the `.docx`
itself; the line numbers below are the export's, for locating the sentence.

Sections 1-8 verified against the tree at `d5d22e9`, 28 September 2026.
Sections 9-10 added 8 October 2026, when the evaluation harness
(`ai_service/eval/`) was built and surfaced them.
Section 11 added 13 October 2026, for the revision 468 data dictionary
(migrations 018 and 019).
Section 12 added 16 October 2026: where the code settled an [OPEN] point
of revision 603. Sections 3, 7 and 9 were marked superseded the same day:
they describe the rev 468 server-side camera check, which is retired.

---

## 1. Google Maps SDK → OpenStreetMap  (§2.3.5, export line 530)

**Now:** "The mobile client integrates the Google Maps SDK for node-based
route visualization and live NAHGM tracking display…"

**Replace with:** "The mobile client renders node-based route
visualization and live NAHGM tracking using OpenStreetMap tiles through
the `flutter_map` package…"

**Why:** no Google Maps dependency exists in either client. Both use
`flutter_map: ^8.3.2` with `latlong2`. Chosen deliberately: no API key, no
billing account and no per-load quota between the panel and a working
demo, and one widget runs on both Android and Flutter Web. The tile vendor
is incidental to NAHGM, which is where the contribution is. ODbL
attribution is on both maps as a licence condition.

## 2. Same, in the technology table  (export line 136)

**Now:** "| Google Maps SDK/API | Used for geolocation services, map
visualization of terminal nodes and route stop sequences, and supporting
coordinate capture during geofenced check-in."

**Replace with:** "| OpenStreetMap / `flutter_map` | Map visualization of
terminal nodes and route stop sequences. | `geolocator` | Device
coordinate capture for geofenced check-in and SOS location."

**Why:** two separate tools. Geolocation is `geolocator`; map *rendering*
is OpenStreetMap. The old row credits one vendor for both.

## 3. "Door closures" → the event the system actually observes  (§2.3.5, line 530)

> **Superseded 16 Oct (rev 603): do not paste.** The `door_close` and
> `gps_node` captures below were removed with the rev 468 audit. Under
> rev 603 the in-van phone counts people crossing a door line in its own
> camera view (door events). There is still no door sensor; if the paper
> says "door", it should mean that line in the camera's view.

**Now:** "an in-van IoT camera captures cabin snapshots triggered by door
closures or specific GPS nodes to initiate physical audits."

**Replace with:** "an in-van camera captures cabin snapshots triggered by
the conductor closing boarding, or by the vehicle crossing out of a
registered terminal geofence, to initiate physical audits."

**Why:** **there is no physical door sensor.** The van kit is a camera and
a GPS unit — no reed switch, no door hardware. The `door_close` trigger is
implemented as `DepartTripUseCase` closing boarding, which is the closest
event the system genuinely observes. The `gps_node` trigger needs no proxy
— it is the real thing. Both fire on *leaving* a node, never arriving,
because an undocumented passenger boards at a terminal and leg *k* is the
stretch they are now riding.

## 4. Firebase Authentication → JWT  (§2.3.5, line 530)

**Now:** "…and uses Firebase Authentication for secure access."

**Replace with:** "…and authenticates through server-issued JSON Web
Tokens, stored on the device in `flutter_secure_storage`."

**Why:** no Firebase dependency exists. Auth is HS256 JWT issued by
`app/core/security.py`.

## 5. FCM push → in-app notifications  (§2.3.5, line 534)

**Now:** "…Firebase for background push notifications (FCM) and real-time
two-way message delivery…"

**Replace with:** "…an in-app notification store that clients poll, with
the schema prepared for later Firebase Cloud Messaging delivery…"

**Why:** notifications and messages are rows in MySQL that clients poll
(30 s in the conductor bell and the console sidebar, 10 s on the SOS
console). FCM is **schema-ready, not delivered**: `delivery_status` stays
`'queued'` and `fcm_message_id` stays `NULL`. Claiming background push
claims a delivery path that does not run. Two-way messaging itself *is*
built (migration 014) — it is the *push transport* that is not.

## 6. Twilio as the mechanism → an SMS gateway  (§2.3.5 line 534, Scope line 76)

**Now (§2.3.5):** "…and the Twilio API to dispatch SMS alerts during SOS
emergencies."
**Now (Scope):** "…emergency alerts continue to be handled separately
through the Twilio API integration described in Section 2.3.5."

**Replace "the Twilio API" in both with:** "an SMS gateway (Twilio, or a
cooperative-operated Android SMS gateway)"

**Why:** Twilio is implemented and works, but it is **not the default**.
It costs roughly US$0.04–0.10 per segment to a Philippine number, and a
trial account texts only numbers verified in its console. The default is
`android_gateway` — a handset on the cooperative's own SIM, free at the
margin. `SMS_PROVIDER` selects between `disabled`, `android_gateway` and
`twilio`. Naming one vendor as *the mechanism* overstates a paid
dependency the system does not require.

---

## 7. New paragraph for Scope and Limitation

> **Superseded 16 Oct (rev 603): do not paste.** It describes the
> retired automatic capture through the server's camera. The in-van phone
> runs the model itself; a trip with no phone reporting is marked
> Unaudited (`no_phone`, `silent_at_start`, `lens_blocked`,
> `lost_en_route`) rather than counted.

Paste at the end of the second Limitation paragraph, after the sentence
ending "…rather than dedicated vehicle-mounted hardware."

> Automatic capture requires a camera attached to the inference host.
> The `door_close` and `gps_node` triggers request a frame from the
> YOLOv8 service directly, so during the prototype demonstration the
> laptop webcam serves as that camera and automatic reconciliation runs
> end to end. The phone-as-camera stand-in, used while dedicated
> vehicle-mounted hardware is unavailable, cannot serve automatic
> captures: a handset cannot accept an inbound request, so it polls for a
> pending one instead, which makes that path conductor-initiated by
> construction. Automatic per-leg reconciliation in a deployed vehicle
> therefore begins when the in-van camera unit is installed. Consistent
> with the system's rule that an unreachable device is an error state and
> never a fabricated success, a capture that cannot be completed writes no
> audit record at all rather than substituting a placeholder count.
> Finally, the automatic trigger, the seat-hold sweeper and the
> phone-capture slot hold their coordination state in process. The
> per-leg uniqueness check reads the audit table and so survives
> additional backend workers, but the in-flight guard does not; the
> prototype is therefore deployed as a single backend process.

**Why:** without this, §2.3.5's automatic capture reads as a field
capability. It is real and tested — but on a server-attached camera, which
in a van means hardware not yet in hand.

---

## 8. Role naming — flagged, not drafted

The manuscript calls the office role **Operator** throughout (Scope,
Table 2, §2.2.1, the ERD). The system renamed this to `coop_admin` in
migration 010, deliberately: under LTFRB usage an *operator* is the
franchise holder — the CPC holder, usually the van owner — which is a
different party from cooperative office staff. Leaving it as "Operator"
invites a panel question the code answers better than the paper does.

Not drafted here because it is pervasive and touches the ERD and every
role table, so it is a decision for the group rather than a find-and-replace:
either rename to "cooperative administrator" everywhere, or add one
sentence at first use defining "Operator" as office staff and
distinguishing it from the franchise holder.

---

## 9. Two different alert rules  (§2.3.2.1 export line 228, §2.3.4 line 154)

> **Settled by rev 603 (16 Oct).** Neither formula is the rule any more.
> Before departure the camera's count aboard is checked against the
> passenger list: fewer is a no-show, more stops Depart until each extra
> boarding is listed or given a reason. After departure the count only
> holds the van to 14 (brief 2.4, 6.1). The evaluation's both-direction
> figures stay valid as a description of the detector.

Not a claim the code fails to meet — a place where **the manuscript
contradicts itself**, found while building the evaluation harness.

**§2.3.2.1 states the reconciliation formula as:**

> Δ = C_visual − C_booked
> Δ = 0 → Reconciled
> Δ ≠ 0 → Discrepancy Detected (Audit Required)

**§2.3.4's functional requirement states:**

> "…instantly trigger a revenue leakage alert for the operator if the
> physical count **exceeds** the manifested count."

These are not the same rule. `Δ ≠ 0` fires in both directions; "exceeds"
is `Δ > 0` only. The difference is operationally large and the evaluation
measures both separately, because:

- `Δ ≠ 0` also fires when there are *fewer* bodies than tickets, which is
  not leakage at all — it is a no-show the system already released, or a
  passenger the detector failed to see. It therefore carries a much higher
  false-alarm rate against an honest crew.
- `Δ > 0` is blind to undercounting, which is the direction that hides a
  passenger.

**What the code does:** `yolov8_audit_logs.variance` is a signed
`SMALLINT`, stored signed on purpose, and the console's audit queue shows
any non-zero variance for a human to close. So the implementation follows
§2.3.2.1 — flag both directions, let the office decide — and §2.3.4's
"exceeds" is the sentence that needs fixing.

**Replace §2.3.4's wording with:** "…instantly flag the trip for operator
review if the physical count differs from the manifested count, recording
the signed variance so that an excess of physical passengers (the revenue
leakage case) is distinguishable from a shortfall."

**Why it matters for the defence:** Table 3 of
`docs/benchmarks/ai_count_<date>.txt` reports the false-alarm and detection
rates under *both* rules. If the paper states one rule and the Results
table reports the other, that is the first question the panel asks.

## 10. New Limitation sentence — how the model was evaluated

Paste after the sentence ending "…rather than dedicated vehicle-mounted
hardware."

> The headcount model's performance was characterised on held-out public
> person-detection data filtered to van-like occupancy and framing, and on
> the same frames under controlled degradation of resolution, illumination
> and motion standing in for cabin conditions, rather than on footage from
> a vehicle-mounted camera, which was unavailable during development. The
> reported counting error, and the false-alarm and detection rates that
> follow from it, therefore characterise the detector and the
> reconciliation rule at the system's configured operating threshold;
> accuracy inside an occupied cabin, under real seat geometry, inter-row
> occlusion and daylight glare, remains to be established once the in-van
> camera unit is installed.

**Why:** the model is pretrained and unmodified, so there is nothing to
report as training performance, and saying so plainly is stronger than
implying a training contribution that was never made. What *is* reported
is the counting error and what it implies for the reconciliation claim —
which is the actual contribution. The harness and its reasoning are in
`ai_service/eval/README.md`.

**If a staged set is shot** (a parked van at known occupancy — see that
README), delete the clause beginning "rather than on footage from" and
report the staged figures from Table 1b instead. That is a half-day of
work and it is the single cheapest upgrade available to this chapter.

## 11. Data dictionary (rev 468) — where the schema stores it differently  (Tables 25-39, brief 7.3)

The schema keeps its own names (decided 13 Oct); this is the mapping to
cite or to adopt in the data dictionary. The full lists are in the
headers of `db/migrations/018_revenue_audit_tables.sql` and
`019_trip_start_audit_columns.sql`. Three entries change what a column
*is*, not just its name, and need a sentence in the paper:

**Fare_Matrix (Table 27).** The paper keys fares by terminal pair:
UNIQUE (OriginTerminalID, DestTerminalID, EffectiveFrom). The schema keys
them per route by stop position: UNIQUE (route_id, from_stop_sequence,
to_stop_sequence, effective_from). Every fare charged is one terminal to
another along a route, so both give the same price; the schema form lets
two routes price the same terminal pair differently if LTFRB approves
them separately. Suggested sentence: "Fares are stored per route, from
one stop of the route to a later stop, with the date each fare takes
effect; a stop is a terminal's position on that route."

**Bookings Origin/DestTerminalID, PaymentStatus, PaymentReference
(7.3).** Not stored on the booking. The terminals are found from the
booking's boarding and alighting stop positions on the trip's route,
and the payment state and gateway reference are in `payments`
(`status`, `provider_ref_id`), one row per payment attempt. Storing them
again on the booking would let the two copies disagree. Suggested
sentence: "A booking records its boarding and alighting stop positions;
the terminals follow from the route, and payment state is recorded per
payment in Payments."

**IsSpecial (TripSchedules).** A van rental is a trip with
`is_special_trip` set and **no route** (`route_id` NULL). `is_special_trip`
alone also marks the office's extra departures on a fixed route, which
the paper does not describe. Either describe them, or say that a special
trip in the paper's sense is one with no route.

Name-only mappings (no wording change needed beyond the table names):
ScheduleID → `trip_id`; TerminalStaff and Dispatchers → `users` +
`staff_profiles`; LogBookEntries → walk-in rows of `bookings`
(`logged_by`, `alighting_stop_sequence`, `fare_amount`);
Nahgm_tracking_logs → `trip_location_pings`; Passenger_Events'
MatchedBookingID and MatchedLogEntryID → one `matched_booking_id`;
Route_Stretches' From/ToTerminalID → the terminals at stops *k* and *k*+1;
Notifications RecipientType/RecipientID → `audience`/`user_id`;
Status 'En Route' → `departed`.

---

## 12. Revision 603: open points the code has settled  (brief rev 603)

Revision 603 marks these [OPEN]. Each was decided while building (the
owner delegated the choices on 15 Oct); the paper should state the
decision rather than leave the point open.

**Hash-chain genesis (brief 6.2, `EventHash`).** Built: the first event's
"previous hash" is SHA-256 of `"sabaygo:" + ScheduleID`. Events are
chained in the order they reach the server (a late upload appends), and
the phone declares each still's `SnapshotHash` on the event, so a still
deleted under retention leaves the chain intact. Suggested sentence:
"For the first event of a trip, the previous hash is the SHA-256 of a
fixed prefix and the trip's identifier." The stronger design in the
brief, signing each event on the phone with a hardware-backed key, is not
built; the server computes the hash.

**Where the Dispatcher records a dispute (brief, Disputes).** In the
mobile app, on their own trip's fare lines and driving flags. The Cashier
and the Terminal Manager record one in the web console; only the
Terminal Manager decides.

**Emergencies (brief, module 18).** Kept as built: SOS from any role,
recorded before any text message is attempted.

**Dispatcher sign-in (brief, Authentication).** Email and password, the
same JWT sign-in as every other role (see §4 for Firebase).

**A van that leaves with boardings counted and no trip waiting.** No
trip is created for it. The phone's events stay held, the Terminal
Manager gets one "Trip not started · van left" alert, and the events
join the trip the van is next assigned to. Suggested sentence: "Door
events recorded while a van has no assigned trip are kept and attached
to its next assigned trip; the Terminal Manager is alerted."

**Settings with no value in the paper.** Shipped unset, and unset turns
the feature off rather than guessing: `DepartZoneRadiusM` and
`DepartReadings` (no GPS departure until a site survey sets them),
`HomePickupMaxRouteM` (no home pickup offered), and the special-trip
speed limit (no rental flagged). `RetentionDays` ships at the brief's
assumed 30.

**The model's input size (adds to §10).** The evaluation harness counts
at Ultralytics' default 640 px input; the phone runs the same weights and
thresholds at 320 or 416 px, chosen by the on-device benchmark
(`docs/benchmarks/`). Until a re-run at the phone's size exists, say that
the reported counting error is at 640 px.
