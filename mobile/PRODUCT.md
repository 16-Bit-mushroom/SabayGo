# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

The Passenger and Dispatcher app (`mobile/`, Flutter, Material). Shared
product truth, terminology and principles are in the root `PRODUCT.md`; this
file adds what is particular to the app.

## Users

- **Passenger**: the commuting public in Davao City. Self-registers.
  Books a space on a van from its starting terminal, pays through the
  gateway, boards with a QR ticket, follows the van on a map. Can rent a van
  (special trip) and book for someone else: a disabled or elderly relative
  picked up at home from a map pin.
- **Dispatcher**: A2Z staff who rides the van, phone in hand at the van
  door. Scans tickets, lists cash walk-ins (pasabay) before departure, fixes
  or explains each unlisted boarding the camera counted, sets the crew
  switch, departs and marks arrival, runs home pickups, hands A2Z's share to
  the Cashier, records the operator's disputes.

## Product Purpose

The passenger books and pays without queueing at the terminal. The
Dispatcher's list matches who is physically aboard before the van leaves,
which is what the revenue audit checks (see the root file). Success is the
A2Z pilot running on it daily without errors.

## Operating Context

- The Dispatcher works standing at a van door at a terminal, one-handed,
  between passengers. Depart is gated on the count: aboard (camera) against
  listed plus explained.
- The passenger books ahead, then shows the QR at the door. Check-in near the
  terminal is a heads-up, never a gate.
- Notifications poll every 30 s. Nothing is pushed.
- When the gateway is down, the relative sends a payment screenshot in the
  chat with the trip's Dispatcher. The Dispatcher confirms it.
- The booking screen carries the camera notice. Its retention period is
  read from A2Z's settings.

## Capabilities and Constraints

- Passenger: search, reserve, pay, QR ticket, check-in, my bookings,
  reschedule (same journey, another trip), cancel (no refund), live map,
  Request a Special Trip, Book for Someone Else, messages, notifications,
  SOS, profile.
- Dispatcher: assigned trips, the trip dashboard (count aboard against
  listed, Add to list, Reason, crew, Depart, Not a passenger trip, home
  pickups, rental cash fee, A2Z's share with a dispute per line, driving
  flags), scan, walk-in, notifications, SOS.
- Boarding is at stop 1 only. There is no "Van is at" stop.
- No seat numbers are ever shown. A space, not a seat.
- The Dispatcher has no van picking, void or change-van. Those are the
  office's.
- Operator shown only as name + licence + plate.
- A walk-in that fixes a counted boarding is sent at once, never queued
  offline.
- Chat images: payment proof only, at most 10 MB, kept 30 days (assumed).
- Verified on Android handsets. The paper lists iOS 15 as a minimum, but
  the app has not been built or tested on iOS.
- The SOS takes two taps, so a control used all day cannot fire by
  accident. It reports SMS delivery only as the gateway answered.

## Brand Commitments

Same as the root file: SabayGo, `assets/branding/sabaygo_logo.png` (the
ink owl with the red eye and pin), English only, plain words. Say
Dispatcher, never Conductor. The visual system is `DESIGN.md` beside this
file.

## Product Principles

1. **At the door, speed and certainty.** A verdict the Dispatcher can read
   at a glance and one obvious action. Never a modal that blocks a queue.
2. **Never fabricate.** A position with no fix is "tracking begins at
   departure". A stale one is "last known". An unknown count is never zero.
3. **The passenger's terms are fixed at booking.** Fares, cutoffs and
   no-refund are shown before payment, and later changes do not alter them.

## Accessibility & Inclusion

WCAG 2.1 AA (`docs/UI_REDESIGN.md`): status colours at AA contrast,
control boundaries at 3:1 or more, a labelled bottom navigation bar, never
unlabelled icons. Home pickup exists for disabled and elderly passengers;
the relative books and pays for them.
