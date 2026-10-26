---
target: the operator console (operator_console/lib)
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 4
target_identity: "file:/home/ccestil/Projects/school/SabayGo_VS/operator_console/lib"
timestamp: 2026-10-25T05-23-20Z
slug: operator-console-lib
closed: true
---
Method: dual-agent (A: design review, own browser · B: detector + semantics evidence, own browser). Scratch copy of the field database, 1440×900 unless noted; Terminal Manager and Cashier both signed in.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Cashier's trip detail shows loading bars that never finish; under 980 px the open step and the emergencies chip leave the view |
| 2 | Match System / Real World | 2 | Rules & Settings prints stored setting names, takes `false` as typed text, says "E.164"; "seats" vs spaces; Money opens on "Remittance" |
| 3 | User Control and Freedom | 2 | Reject and Suspend act on one click, no confirm, no reason (roster_parts.dart:138, staff_step.dart:71); date resets per tab |
| 4 | Consistency and Standards | 2 | Two validation styles; Timetable form outlier; 17:30 vs 5:30 PM, three date formats |
| 5 | Error Prevention | 2 | Lat/long typed by hand; yes/no setting as free text (policy_editor_screen.dart:178); "Lift payment block" at routine weight |
| 6 | Recognition Rather Than Recall | 3 | Pointers to other pages are plain text, not links |
| 7 | Flexibility and Efficiency | 2 | No shortcuts, no list search, one Save per setting |
| 8 | Aesthetic and Minimalist Design | 3 | Calm and flat; Rules & Settings is a wall of ~25 rows × 3 controls |
| 9 | Error Recovery | 2 | Server sentences pass through raw: "This action requires: dispatcher, terminal_manager." |
| 10 | Help and Documentation | 3 | One plain sentence per page and good step hints; no glossary for "payment block", "Issue new token" |
| **Total** | | **24/40** | **Acceptable** |

## Design Specificity Verdict

LLM: the pila board holds in the shell and Setup (green rail, plate tile behind the selected icon, Emergencies pinned, raised Now head, numbered route stops, plate tags). The daily-work pages fall back to generic admin UI: Reviews, Money, Special Trips, SOS are title + sentence + Refresh + centred empty icon; Rules & Settings is a generic settings form; Van Status Board is a bare row with the plate as plain text and no pila strip, though a van's turn is the one daily order that is real.

Deterministic scan: detector cannot read Flutter. `operator_console/lib` scanned 0 files; 68 .dart files by name, regex-only, 0 findings. `web/index.html:35` design-system-color: body #0E0F12, the deleted dark theme's boot colour, so every load flashes dark. Real defect.

Overlay: injected into the running page; canvas gives it nothing (`No anti-patterns found`, 0 elements). No user-visible overlay. Accessibility evidence came from Flutter's semantics tree.

## Overall Impression

The redesign answered the brief's main complaint: first-day set-up runs in one page and the queue tells the truth. Not yet reached: the Cashier's path, keyboard and screen-reader use, the settings page, and two places that state what nobody checked.

## What's Working

1. Setup queue reads state from the database and says it in words; Save disabled with the reason; unreadable lists say so (setup_status.dart:77).
2. Honest status copy (update intervals, Unaudited, "Not set: this is off").
3. Role fit: Cashier chip "Vans owing the share", manager pages left out not refused; nav and tabs carry correct semantics.

## Priority Issues

[P1] Cashier cannot see a trip's passenger list. trip_monitor_screen.dart:105 requests it; server allows Dispatcher + Terminal Manager only (operations.py:38). Red raw role error, endless loading bars (capture 41). Fix: skip the call for the Cashier, show counts and a plain sentence; refusals in office words. → harden

[P1] Two screens claim what nobody checked. Boarding Audit on a day with no trips: "Every boarding matched the passenger list…" (boarding_audit_screen.dart:83). Setup "Ready for the first trip" while SOS numbers are unset (texts off). Fix: "No trips on this day"; Ready note names what is still off. → harden

[P1] Keyboard and screen-reader paths break. Setup queue steps: button role with no tap action (setup_screen.dart:344); bell unnamed; 0 headings; map named "flutter_map"; focus only a faint fill (none on account menu); Tab zig-zags across sidebar/queue/form. Fix: tap action, names, header semantics, 2px green focus ring theme-wide, focus traversal groups per region. → harden

[P1] Rules & Settings speaks the system's language: stored names (policy_editor_screen.dart:169), `false` as text, "E.164", developer settings shown, ~25 Saves. Fix: drop names, switch for yes/no, SOS number list, "Advanced" fold, rewritten descriptions. → clarify, distill

[P2] Under 980 px Setup loses structure: strip cut at "Time…" with no scroll cue, head not raised, notes gone, Save cut off, emergencies chip dropped. → harden, adapt

## Persona Red Flags

Alex: no shortcuts, no search, day-by-day date that resets per tab, one Save per setting.
Sam: cannot open a Setup step by screen reader; loses focus on the rail and account menu; Tab crosses three regions in ~4 presses; bell unnamed; weekday chips "T T S S".
Jordan: "Lift payment block", "Back to pending", "Issue new token" unexplained; Money → "Remittance"; types coordinates.
Terminal Manager (first day): one page, but "Ready" with SOS texts off; settings wall; Reject on one misclick with no reason; no who/when on validation.
Cashier (share and Start): lands on the map; role error on the trip; "Owes ₱X" in danger red; account menu says "A2Z office" not the role; Setup "3 of 3 done" though they set nothing up.

## Minor Observations

- Filled button on the disabled Start while Assign (the real next step) is outlined.
- "Seats" wording against spaces.
- Special Trips empty state says no next step (special_trips_screen.dart:134).
- Walk-in dialog fields touch; disabled "Enter request" without a reason.
- SOS card category uppercase w900 (not bundled), raw role id (sos_console_screen.dart:215).
- Notification sheet elevation 12 (notification_bell.dart:66).
- Theme asks for w600/w800; only 400/500/700 bundled.
- A done queue step loses its number.
- Phones step "1 in the pool" vs card "Out with a van".
- Route form label truncated "Minut…"; sign-in says "Cooperative office console".
- Menu toggle name doubled; account button name includes the avatar letter.

## Questions to Consider

- Should the Cashier land on today's Trips instead of the map?
- Are the SOS numbers a set-up step rather than an optional setting?
- Does the Terminal Manager ever need "How often unpaid holds are released"?
- If the Van Status Board were the real pila, would "assign at the van's turn" explain itself?
