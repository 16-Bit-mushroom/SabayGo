# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

This file covers the whole product and the operator console
(`operator_console/`, Flutter Web). The Passenger and Dispatcher app has its
own record at `mobile/PRODUCT.md` (platform `android`). The in-van phone app
(`edge_app/`, native Kotlin) has no design surface beyond its set-up screen.

## Users

- **Terminal Manager** (A2Z office, web console at a desk). Decides what is
  owed, validates vans, operators and Dispatchers, reviews boarding audits
  and automatic starts, decides disputes, sets the rules.
- **Cashier** (web console). Records A2Z's share, starts trips, checks phones
  in and out, enters walk-in rental requests. Terminal-Manager-only pages are
  hidden.
- Both are non-technical office staff working through the day. The console
  was rewritten in their words (`docs/CONSOLE_REDESIGN.md`).
- **Dispatcher** and **Passenger**: the mobile app, see `mobile/PRODUCT.md`.
- **Operator**: the van owner, who always drives. A roster row, no login,
  one van each. Shown only as name + licence number + the van's plate.
- **Admin**: the development team.
- Secondary audience: the BSIT capstone panel, University of Mindanao. The
  final defence date waits on endorsement.

## Product Purpose

SabayGo books seats on, and manages the fleet of, terminal-based UV Express
vans in Davao City. A2Z Transport Cooperative Van Terminal is the pilot
partner.

The study is a revenue audit. A2Z takes 15 % of each van's gross fares
daily. A phone in the van counts boardings and alightings at the door line.
The server matches them to QR scans and cash entries, so a fare that never
entered the record is found before the van leaves.

Success, in order: the A2Z pilot runs on it daily without errors; then the
defence. Where the two pull apart, pilot use wins.

## Positioning

The passenger list is checked against a physical count before departure,
not reconciled after it. An unlisted boarding must be added to the list or
explained before a person can depart the van. Door events are hash-chained
per trip, so a later change is detectable. A2Z's share is computed from fare
lines that follow the list. A paper logbook cannot do any of this.

Claims the code makes good on: the revenue audit, Equation 2, the hash
chain, NAHGM driving flags. Nothing else.

## Operating Context

- Vans board only at stop 1 of a fixed LTFRB route. 14 passengers per van
  (A2Z's rule). No seat numbers are shown; capacity is spaces.
- A trip goes assigned → Start (office; needs A2Z's share recorded) →
  Depart (Dispatcher, office, or GPS) → Arrived.
- Money changes hands as cash, Dispatcher to Cashier, or through the
  payment gateway (PayMongo, e.g. GCash). SabayGo records payments. It does
  not hold or process money.
- Office PCs in a browser, sometimes a projector. The console is light only.
- Screens poll. Nothing is pushed. Van Status Board 15 s, Emergencies
  10 s, notifications 30 s.
- Documents in use: LTFRB routes and fare matrix, roster import (CSV/XLSX),
  exports (CSV/PDF), the LTFRB check list.
- Demo: `./run.sh`, talk track `docs/DEMO_SCRIPT.md`.

## Capabilities and Constraints

Console menu (UI redesign v3, 25 Oct): seven entries, related pages as
tabs. Overview (map); Trips (Trips with the Start and departure panel, Van
Status Board, Special Trips); Reviews (Review Starts, Boarding Audit,
Driving Flags, Disputes); Money (Remittance); Messages; Setup (a queue of
Terminals, Route, Fares, Operators & vans, Staff, Timetable, Phones, then
Rules & Settings, each entered in place); Emergencies (SOS), pinned.

Terminology (brief rev 603 §15, binding):

- **A2Z**, not "the co-op". **Dispatcher**, never Conductor. **Terminal
  Manager**, **Cashier**. **operator** in lower case, never a user and never
  office staff. **passengers**, not commuters.
- stop, stretch, stop zone, distance from the starting terminal. Not node,
  segment, chainage or geofence.
- **pasabay**: someone who walks up and rides without a booking.
- On screen: passenger list (not manifest), section (not leg), difference
  (not variance). System and table names stay off the console (the owner's decision,
  25 Oct); the manuscript and the code carry them.

Rules the interface must keep:

- **Never show a fabricated count.** A trip with no phone reporting is
  Unaudited (`no_phone`, `silent_at_start`, `lens_blocked`,
  `lost_en_route`), never zero. A stale position is labelled last known.
- Settings that ship unset show as "not set" and mean off.
- Blurred snapshots are for the Terminal Manager only. Other roles never
  see the image or its address.
- No estimated income and no "amount at risk" anywhere.
- Cash in hand is not missing money. Fewer counted than listed is a camera
  question, not lost revenue.
- No refunds. Fares come from the fare matrix, never typed in.
- Every decision on money, starts, flags and disputes records who, when and
  why.

Technical: Flutter Web, built and served statically. OpenStreetMap through
`flutter_map`; the ODbL attribution is a licence condition and stays. JWT
sign-in, polled notifications.

Open: A2Z's real routes, fares, timetable, stretch speed limits and the
unset settings (`depart_zone_radius_m`, `depart_readings`,
`home_pickup_max_route_m`, `special_trip_speed_kmh`). A2Z's data privacy
contact is not named. Keep `[name and position to be supplied by A2Z]`.

## Brand Commitments

- Name: **SabayGo**. Logo: `operator_console/assets/branding/sabaygo_logo.png`
  and `mobile/assets/branding/sabaygo_logo.png`.
- The logo is an ink-black owl with a red eye and a red route pin. The
  console (UI redesign v3, 25 Oct, the owner's brief) is white, terminal
  green and black/red in a 60-30-10 split: white is the page, green the
  frame and the action colour, black the text, and red only route
  geometry, SOS and danger. Light only; the dark console is retired. The
  app keeps ink as its action colour. The earlier deep purple (#2D2059) is
  retired, though `docs/UI_REDESIGN.md` still describes it. The visual
  systems are `DESIGN.md` (the console) and `mobile/DESIGN.md` (the app).
- Voice: plain and factual. Every page title matches its menu label and has
  one plain sentence under it. Empty and error states say what to do next.
  No promotional adjectives.
- Interface copy is English only.
- Do not state a frame rate, accuracy or uptime for the phone until it is
  measured.

## Evidence on Hand

- The brief: `docs/SabayGo-Changes-for-Claude-Code (3).md` (rev 603).
  Gaps: `docs/GAP_REPORT.md`.
- A2Z interview notes: `mobile/UI_NOTES.txt`.
- Phone benchmark, bench sweep only:
  `docs/benchmarks/edge_sweep_2026-10-18.md`.
- Model counting accuracy on COCO street photos at 640 px, not a van cabin:
  `docs/benchmarks/ai_count_2026-10-09_full.txt`.
- Demo seed data (`db/seed/002_demo_dataset.sql`): placeholder routes
  shaped like the Davao network, not A2Z's.

Absent, and not to be invented: A2Z's real routes, fares and timetable;
door counting verified with people or in a van; an operating frame rate;
pilot feedback or user quotes; real SOS numbers (the seeded ones are
unassigned +63 900 placeholders).

## Product Principles

1. **Never fabricate.** Missing evidence shows as missing: Unaudited, not
   set, last known. An invented number would flag an innocent driver.
2. **Pilot first.** The person at the desk or the van door finishes the task
   without error. A good-looking demo comes second.
3. **Fair to the honest crew.** The audit separates cash in hand from
   unreconciled money and a camera doubt from lost revenue. Evidence is seen
   only by the role that decides on it.
4. **The office's words.** Say what A2Z says. System terms are footnotes.
5. **Every decision is attributable.** Who, when, why, beside the result.

## Accessibility & Inclusion

WCAG 2.1 AA is the standing goal (user's words in `docs/UI_REDESIGN.md`).
The console palette passes AA. Navigation is labelled, never icon-only; the
folded sidebar shows a name on hover. Staff are not technical: plain words
and one obvious next action per screen.
