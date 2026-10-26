---
version: 1
slug: "operator-console-lib"
primary_target: "operator_console/lib"
related_targets: []
---

# Operator console (`operator_console/lib`)

Scope: the whole A2Z office console (Flutter Web): shell, seven hubs, the Setup page. Visitor mode: **Operate**.

Audience and job: the Terminal Manager and the Cashier at an office PC, all day, plus the first-day set-up on an empty database. Success is finishing a task without error. First-day set-up runs inside one page, with no jumping between pages.

Pinned by the owner (UI-UX-redesign-v3, 25 Oct): white 60, green 30, black/red 10; light only; seven menu entries with tabs; a Setup page with a checklist rail and inline forms; Roboto.

Unresolved: what A2Z checks before validating a Dispatcher (in QUESTIONS_FOR_COOPERATIVE).

## Direction contract

THESIS: The console is the terminal's pila. Every ordered list is a queue with a head, and the head is the thing to do now. It refuses the category default: a stepper bar over a form card, and sixteen flat menu entries.

OWN-WORLD:
- Whiteboard enamel: a faint green-white canvas and white panels.
- Painted terminal-green steel: the sidebar, primary buttons and the selected entry.
- Marker black for text, marker red only for SOS, danger and route pins.
- Plate-number tiles: a square outlined tile with a bold tabular number.
- Neutrals from one fixed green-grey ramp. Urgency on one ramp: none, ochre, red.
- Every state carries a mark: a check for done, a ring for to do, a lock for blocked.

STORY: Staff see what is next, do it in place, and watch the queue advance. The next slot is always visible and one click away.

FIRST VIEWPORT:
- Green 248 px sidebar: the logo plate, six entries, and Emergencies pinned at the foot.
- White 64 px top bar with today's chips.
- Under the title, three columns:
  - the set-up queue, 320 px. The head slot is raised: green tint, "NOW", a 44 px tile.
  - the step's list, as a table.
  - an inline add/edit form, 420 px, with "Save and add another" in the primary position.

FORM: The Pila Board, candidate 6 of 7 (the terminal's van queue on the dispatch whiteboard). seed:cb53eb35caaf9167. Signature move: the pila strip, an ordered column of plate tiles whose head is raised. It is used by the Setup queue and wherever the order is real (a van's turn). Lists without an order stay plain lists.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
