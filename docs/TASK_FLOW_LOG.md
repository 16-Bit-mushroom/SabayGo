# Task flow log

How each task is done by hand, step by step, and where the flow breaks:
a jump to another screen, a step that leads nowhere, a choice made twice,
a wait. Bugs found on the way go here too, typed **Error**. The data to
type in is `docs/MANUAL_INPUT_SHEET.md`.

This log is the **baseline**. After the flows are fixed, copy the Session
block below for a retest, so the screens, clicks and time can be compared
task by task.

---

## How to log

- **One row per task attempt** in the Task log. Time it from the first
  click to done; a phone stopwatch is enough.
- **Screens**: count every change of page, tab, dialog or side panel.
  **Clicks**: taps and clicks, typing not counted. Rough counts are fine.
- **Screens visited**: the path in order, e.g. `Setup › Staff › Add staff
  › (panel) Validate`.
- **Each problem gets an Issue entry** (F-01, F-02, …), and its number
  goes in the task's Issues column.
- **Screenshots**: `docs/task-flow-shots/F-01.png`, named after the issue.
- Write it as it happens. A note written straight away beats a tidy one
  written later.

### Type

| Type | Means |
|---|---|
| **Jump** | Had to leave the screen to do or check something the task needed |
| **Disconnected** | Finishing a step did not lead to the next one, and nothing linked to it |
| **Lost context** | Had to pick the day, trip, van or person again |
| **Hidden** | The control exists but was hard to find |
| **Unclear** | A label, message or state did not say what it means |
| **No feedback** | Could not tell whether it worked, or why it was refused |
| **Extra step** | A step that could be skipped, combined or filled in already |
| **Slow** | Waiting on the system |
| **Error** | Something wrong or broken |

### Severity

| | Means |
|---|---|
| **3 Blocker** | Could not finish without help or a workaround |
| **2 Major** | Finished, but slow or confusing; it would catch a new user every time |
| **1 Minor** | An annoyance; finished easily |

### Heuristic (optional, for the paper)

Nielsen's ten usability heuristics:
- **H1** Visibility of system status
- **H2** Match with the real world
- **H3** User control and freedom
- **H4** Consistency and standards
- **H5** Error prevention
- **H6** Recognition rather than recall
- **H7** Flexibility and efficiency of use
- **H8** Aesthetic and minimalist design
- **H9** Help users recognise, diagnose and recover from errors
- **H10** Help and documentation

---

## Session 1

| | |
|---|---|
| Date | 20 Nov 2026 |
| Tester | |
| Roles played | |
| Devices | Console: laptop, Chromium · Passenger: Redmi Note 9 Pro, app · Dispatcher: browser, `http://localhost:3003` |
| Data | Empty database (only manager@a2z.dev) + `docs/MANUAL_INPUT_SHEET.md` |
| Build | `git rev-parse --short HEAD`: 24b8551 (branch docs-alpha-round2) |

### Task log

**Outcome**: Done · Done with help · Gave up.

#### A. Setup (Terminal Manager, console)

| ID | Task | Start screen | Screens visited | Screens | Clicks | Time | Outcome | Issues |
|---|---|---|---|---|---|---|---|---|
| A1 | Add the 7 terminals (sheet §1) | | | | | | | |
| A2 | Create route ECO-COT with its 4 stops (§2) | | | | | | | |
| A3 | Enter the fares, then the two fare changes (§3) | | | | | | | |
| A4 | Add the 3 operators and 3 vans with their photos; validate them (§4) | | | | | | | |
| A5 | Add the 7 staff; validate the Dispatchers (§5) | | | | | | | |
| A6 | Add the 7 trip schedules; post 7 days of trips (§6) | | | | | | | |
| A7 | Rules & Settings: set the unpaid cutoff (§7) | | | | | | | |

#### B. One trip, start to finish

| ID | Role | Task | Start screen | Screens visited | Screens | Clicks | Time | Outcome | Issues |
|---|---|---|---|---|---|---|---|---|---|
| B1 | Terminal Manager | Assign a van and a Dispatcher to a trip | | | | | | | |
| B2 | Passenger | Register in the app | | | | | | | |
| B3 | Passenger | Search Ecoland → Digos and reserve a seat | | | | | | | |
| B4 | Passenger | Cancel an unpaid reservation | | | | | | | |
| B5 | Passenger | "I'm here to pay" (fake GPS at Ecoland) | | | | | | | |
| B6 | Dispatcher | Find the passenger by name or code; Mark as Paid | | | | | | | |
| B7 | Dispatcher | List two walk-ins; add self as crew | | | | | | | |
| B8 | Cashier | Record the terminal fees and the operator's share | | | | | | | |
| B9 | Cashier | Start the trip | | | | | | | |
| B10 | Dispatcher | Depart | | | | | | | |
| B11 | Passenger | Track the van | | | | | | | |
| B12 | Dispatcher | Arrived | | | | | | | |
| B13 | Cashier | Read the van's statement on Money | | | | | | | |

#### C. Other tasks, as time allows

| ID | Role | Task | Start screen | Screens visited | Screens | Clicks | Time | Outcome | Issues |
|---|---|---|---|---|---|---|---|---|---|
| C1 | Passenger | Request a special trip; see it approved with its fee | | | | | | | |
| C2 | Passenger | Book for someone else with a home pickup pin | | | | | | | |
| C3 | Passenger ↔ Dispatcher | Chat, with a photo | | | | | | | |
| C4 | Dispatcher | Mark Paid in airplane mode, then sync | | | | | | | |
| C5 | Dispatcher | Record a dispute | | | | | | | |
| C6 | Passenger → console | Raise an SOS; respond and close it in the console | | | | | | | |
| C7 | Cashier | A parking-only charge for a van with no trip | | | | | | | |
| C8 | Terminal Manager | Lift the payment block with a reason | | | | | | | |
| C9 | Terminal Manager | Void a started trip, or change its van | | | | | | | |
| C10 | Terminal Manager | Add a terminal by mistake and delete it | | | | | | | |
| | | | | | | | | | |

### Issues

Copy this block for each one; newest at the bottom.

```markdown
#### F-00 · <short title>
- **Task**: <ID> · **Role**: <role> · **Where**: <screen › part>
- **Type**: <type> · **Severity**: <1-3> · **Heuristic**: <H1-H10, optional>
- **What I did**:
- **What happened**:
- **What I expected**:
- **Steps it took → steps it should take**:
- **Screenshot**:
- **Idea** (optional):
```

*Example, from Day 1 finding 4 (delete once you have your own):*

#### F-00 · Validate is out of sight
- **Task**: A5 · **Role**: Terminal Manager · **Where**: Setup › Staff, the new Dispatcher's panel
- **Type**: Hidden · **Severity**: 2 · **Heuristic**: H1, H6
- **What I did**: Added a Dispatcher and saved.
- **What happened**: The Dispatcher stayed Pending; **Validate** sits at the foot of the panel, below the form.
- **What I expected**: Saving to offer the next step, Validate, where I was looking.
- **Steps it took → steps it should take**: scroll + 1 click → 1 click
- **Screenshot**: —
- **Idea**: After Save, show "Validate this Dispatcher" beside the Saved message.

<!-- New issues below this line. -->

### Summary (at the end of the session)

| Role | Tasks tried | Done | Done with help | Gave up | Total time | Worst three issues |
|---|---|---|---|---|---|---|
| Terminal Manager | | | | | | |
| Cashier | | | | | | |
| Dispatcher | | | | | | |
| Passenger | | | | | | |
