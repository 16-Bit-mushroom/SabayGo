---
name: SabayGo operator console
description: The A2Z office console. A balanced mid-green on meadow mist, Inter and Plus Jakarta Sans.
colors:
  meadow-mist: "#F0FDF4"
  emerald-tint: "#DCFCE7"
  edge-green: "#86EFAC"
  kelly: "#22C55E"
  emerald-action: "#10B981"
  secondary-hover: "#059669"
  green-text: "#047857"
  on-action: "#0F2A20"
  slate-green: "#1E3A2F"
  muted-ink: "#4B6358"
  control-border: "#6B8579"
  divider: "#BBF7D0"
  disabled: "#A3B8AD"
  on-fill: "#FFFFFF"
  enamel-white: "#FFFFFF"
  sunken-step: "#E8F7EE"
  marker-red: "#C8151D"
  marker-red-tint: "#FBE7E8"
  logo-plate: "#FFFFFF"
  success: "#047857"
  success-container: "#DCFCE7"
  warning: "#8A5A00"
  warning-container: "#FFF4DB"
  danger: "#B3261E"
  danger-container: "#FDECEA"
  info: "#1E3A2F"
  info-container: "#E6EFEA"
  scrim: "#1E3A2F73"
  map-shadow: "#00000066"
typography:
  headline-large:
    fontFamily: "Plus Jakarta Sans, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.5px"
  headline-medium:
    fontFamily: "Plus Jakarta Sans, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.3px"
  headline-small:
    fontFamily: "Plus Jakarta Sans, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.2px"
  title-large:
    fontFamily: "Plus Jakarta Sans, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.35
  title-medium:
    fontFamily: "Inter, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.4
  title-small:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.4
  body-large:
    fontFamily: "Inter, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
  body-medium:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  body-small:
    fontFamily: "Inter, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.4
  label-large:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 700
  label-medium:
    fontFamily: "Inter, sans-serif"
    fontSize: "12px"
    fontWeight: 700
  label-small:
    fontFamily: "Inter, sans-serif"
    fontSize: "11.5px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "0.6px"
  table-head:
    fontFamily: "Inter, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    letterSpacing: "0.4px"
  figure:
    fontFamily: "Plus Jakarta Sans, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
rounded:
  plate: "5px"
  tile: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  full: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  xxxl: "32px"
  section: "40px"
  gutter: "16px"
components:
  button-primary:
    backgroundColor: "{colors.emerald-action}"
    textColor: "{colors.on-action}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
    hitTarget: "48px"
  button-primary-hover:
    backgroundColor: "{colors.kelly}"
  button-danger:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
  button-outlined:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.green-text}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
  button-text:
    textColor: "{colors.green-text}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    height: "40px"
  input:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.sm}"
    padding: "12px"
  sidebar:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    width: "248px"
  sidebar-folded:
    backgroundColor: "{colors.enamel-white}"
    width: "76px"
  sidebar-item:
    textColor: "{colors.slate-green}"
    rounded: "{rounded.md}"
    height: "44px"
  sidebar-item-selected:
    backgroundColor: "{colors.emerald-action}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.md}"
    height: "44px"
  sidebar-plate-tile:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.green-text}"
    rounded: "{rounded.tile}"
    size: "26px"
  top-bar:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    height: "64px"
    padding: "0 24px"
  today-chip:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.muted-ink}"
    rounded: "{rounded.full}"
    padding: "8px 12px"
  tab-bar:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.muted-ink}"
    height: "46px"
  tab-selected:
    textColor: "{colors.green-text}"
  count-pill:
    backgroundColor: "{colors.warning-container}"
    textColor: "{colors.warning}"
    rounded: "{rounded.full}"
  count-pill-sidebar:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.slate-green}"
    rounded: "{rounded.full}"
  panel:
    backgroundColor: "{colors.enamel-white}"
    rounded: "{rounded.lg}"
    padding: "16px"
  stat-tile:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    typography: "{typography.figure}"
    rounded: "{rounded.md}"
    padding: "16px"
  status-badge-success:
    backgroundColor: "{colors.success-container}"
    textColor: "{colors.success}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  status-badge-warning:
    backgroundColor: "{colors.warning-container}"
    textColor: "{colors.warning}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  status-badge-danger:
    backgroundColor: "{colors.danger-container}"
    textColor: "{colors.danger}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  status-badge-info:
    backgroundColor: "{colors.info-container}"
    textColor: "{colors.info}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  status-badge-neutral:
    backgroundColor: "{colors.sunken-step}"
    textColor: "{colors.muted-ink}"
    rounded: "{rounded.full}"
    padding: "3px 8px"
  queue-slot:
    rounded: "{rounded.md}"
    padding: "8px"
  queue-slot-head:
    backgroundColor: "{colors.emerald-tint}"
    rounded: "{rounded.md}"
    padding: "12px 8px"
  queue-tile:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    rounded: "{rounded.tile}"
    size: "30px"
  queue-tile-head:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    rounded: "{rounded.sm}"
    size: "44px"
  queue-tile-done:
    backgroundColor: "{colors.green-text}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.tile}"
    size: "30px"
  queue-tile-waiting:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.muted-ink}"
    rounded: "{rounded.tile}"
    size: "30px"
  now-pill:
    backgroundColor: "{colors.green-text}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.full}"
  plate-tag:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.slate-green}"
    rounded: "{rounded.plate}"
  record-row-selected:
    backgroundColor: "{colors.emerald-tint}"
    textColor: "{colors.slate-green}"
  side-panel:
    backgroundColor: "{colors.enamel-white}"
    rounded: "{rounded.lg}"
    width: "400px"
  tooltip:
    backgroundColor: "{colors.slate-green}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.sm}"
  snackbar:
    backgroundColor: "{colors.slate-green}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.md}"
    width: "480px"
---

# Design System: SabayGo operator console

Scope: the A2Z office console (`operator_console/`, Flutter Web), used by the Terminal Manager and the Cashier. The Passenger and Dispatcher app keeps its own system in `mobile/DESIGN.md`; nothing here applies to it. The source of truth for every value is `operator_console/lib/core/design/tokens.dart` and `theme.dart`; this file records them.

## Overview

**Palette and type (10 Nov, the owner's VerdantPulse reference):** a balanced mid-green -- meadow-mist page `#F0FDF4`, white and soft-emerald `#DCFCE7` cards with mid-light green `#86EFAC` edges, kelly `#22C55E` and emerald `#10B981` accents, `#059669` for secondary hover, slate green-grey `#1E3A2F` type -- set in Inter and Plus Jakarta Sans. It replaces the October terminal greens and Roboto, and the same day's monochromatic emerald. The pila board below is still the console's structure; its colours are now these.

**Creative North Star: "The Pila Board"**

The console is the terminal's pila: the dispatch whiteboard where vans queue by plate number and the van at the head goes next. Every ordered list is a queue with a head, and the head is the thing to do now. Staff see what is next, do it in place, and watch the queue advance. The world is made of the board's own materials: meadow mist for the page, white and soft-emerald cards with green edges, the emerald action, slate green-grey for words, marker red only for alarms and route pins, and square plate-number tiles that sit on the board like magnets.

It is a desk tool for non-technical office staff working all day, sometimes on a projector, so it is light only, dense enough for a desk, and plain. Seven labelled menu entries replace sixteen flat ones; related pages sit as tabs under their entry. First-day set-up is one page: a queue of steps on the left, the step's records in the middle, the add or edit form beside them. Nothing on screen uses a system or table name; the console speaks in A2Z's words.

The dark "Night Owl's Ledger" console and the earlier deep purple are retired. There is no dark palette and no fourth hue.

**Key Characteristics:**
- White, emerald and ink, with red only for SOS, danger and the route.
- Light only, Inter and Plus Jakarta Sans bundled, flat white panels and cards with light edges on a near-white canvas.
- A green sidebar with seven labelled hubs, Emergencies pinned at its foot.
- The pila strip: an ordered column of plate tiles whose head is raised.
- Every state carries a word and a mark, never colour alone.
- Selection is marker ink on the map and green tint in lists.

## Colors

A balanced mid-green on meadow mist; the source of truth is `operator_console/lib/core/design/tokens.dart`, where every ratio is computed.

### The greens
- **Meadow Mist** (`#F0FDF4`): the page behind every panel.
- **Soft Emerald Tint** (`#DCFCE7`): count pills, the progress track, the success container, a selected row. (No tinted figure cards or icon tiles since 10 Nov.)
- **Edge green** (`#86EFAC`): the sidebar's right edge and chart accents. Cards and panels take the lighter divider `#BBF7D0` since 10 Nov (toned down), so green is left for the main action and paid/live states. Decorative (1.40:1): a control a person must find takes the control border.
- **Emerald** (`#10B981`): the main action (filled buttons, one per view) and the selected sidebar entry, always with dark text `#0F2A20` on it (6.03:1). The reference's white on emerald is 2.54:1, under AA, so it is not used.
- **Kelly** (`#22C55E`): the main action under the pointer (dark text 6.7:1), and the start of the progress gradient (kelly to emerald).
- **Secondary hover** (`#059669`): an outlined button's edge under the pointer (3.77:1, an edge, never text).
- **Green text** (`#047857`): every green text and icon (links, the selected tab, outlined-button labels, focus rings), the avatar, success. 5.48:1 on white, 5.24:1 on the page, 4.99:1 on the tint. The lighter greens fail as text.

### Status
- **Success** is green text on the tint. **Warning** (`#8A5A00` on `#FFF4DB`, 5.42:1): awaiting payment, money still owed, a difference to look at; never red. **Danger** (`#B3261E` on `#FDECEA`, 5.72:1): cancelled, failed, emergencies, destructive confirmation (white text on it). **Info** is the type colour on `#E6EFEA`.
- **Marker Red** (`#C8151D`): the logo's red, route geometry and pins on the map only.

### Type and neutrals
The slate green-grey ramp (`AppRamp`): type `#1E3A2F` (12.34:1), muted `#4B6358` (6.51:1), control borders `#6B8579` (4.00:1), inner rules `#BBF7D0`, disabled `#A3B8AD`, hover rows `#E8F7EE`.

### Named Rules
**The Balanced Green Rule.** Meadow mist is the page, white and the soft tint are the cards, edge green outlines them, emerald is the action, green text is `#047857`; slate green-grey and red are the words and the alarms. No other hue carries meaning or decoration.

**The Emerald Is A Fill Rule.** Emerald and kelly are fills with dark text on them, never text on white. Green text is `#047857`.

**The Red Is An Alarm Rule.** Red means SOS, danger or a route pin. It is never a primary button, so a red SOS never sits beside a red Save. The only red fill on a button is a destructive confirmation.

**The No Blue Rule.** Informational status is marker ink on a grey-green tint, not a fourth hue. Blue is out of the world.

**The One Ramp Rule.** Every grey is a step of the green-grey ramp. No screen mixes its own grey.

**The Measured Pair Rule.** Every text and control pairing is measured against WCAG 2.1 AA, and anything drawn on a filled colour uses on-fill white.

## Typography

**Interface font: Inter** (400, 500, 600, 700), for body text, labels, tables, buttons and every amount, in tabular figures so a column of pesos lines up.
**Heading font: Plus Jakarta Sans** (600, 700, 800), for page titles, dialog titles and the big figures on the cards. Its rounder, geometric capitals give the page a heading voice that Inter, a neutral text face, does not.

Both are bundled in `operator_console/assets/fonts` (static weights cut from the OFL variable fonts in google/fonts, licences beside them), never fetched: a font that loads from the network is missing on exactly the demo machine without it. Code asks only for the weights bundled. Where weight carries a state (the selected tab), it is 600 against 500.

**Character:** Plus Jakarta Sans for what you read first, Inter for everything you work with. Hierarchy comes from size and weight; the figures are set heavy so a count reads from across the office.

### Hierarchy
- **Headline Medium** (Plus Jakarta Sans 700, 24px, 1.3, -0.3px): every page title, worded exactly as its menu entry or tab.
- **Title Large** (700, 18px, 1.35): a Setup step's title under the page title (the compact page header), and dialog titles.
- **Title Small** (700, 14px, 1.4): panel headings, queue step names.
- **Body Medium** (400, 14px, 1.45): table cells, form text, the one plain sentence under every title (in muted ink).
- **Body Small** (400, 12.5px, 1.4): captions and the line under a record name, in muted ink.
- **Label Large** (700, 14px): button labels.
- **Label Medium** (700, 12px): stat tile labels and column heads, in muted ink.
- **Table Head** (700, 12px, 0.4px tracking): data table column heads on the sunken header row, in sentence case.
- **Figure** (Plus Jakarta Sans 700, 24px, 1.2, tabular): a figure card's number; the top-bar figures use Inter 700 at 14px.

### Named Rules
**The Title Is The Label Rule.** A page title matches its menu entry or tab word for word, and has one plain sentence under it.

**The Office Words Rule.** System, table and column names never appear on screen. Statuses are shown in A2Z's words ("Not yet boarded", "No longer working"), not stored values.

## Layout

The shell is fixed: a 248 px light-green sidebar (76 px folded, names shown on hover), a 64 px white top bar carrying today's figures as outlined pills, the bell and the signed-in person, then, for a hub with more than one page, a 46 px white tab bar, then the page on the whiteboard canvas.

Seven menu entries: Overview, Trips, Reviews, Money, Messages, Setup, and Emergencies (SOS) pinned at the sidebar's foot apart from the rest. My account is a page too, opened from the menu under the signed-in name, not a dialog.

Every page has its own address (`#/money`, `#/trips/van-status-board`, `#/account`; `core/layout/console_router.dart`): a refresh keeps the page, Back and Forward move between pages, a bookmark or link opens the page after sign-in, and the browser tab is titled with the page name. Pages that answer the same question are tabs under one entry. The Cashier's menu omits the Terminal Manager's pages rather than refusing them.

Pages sit inside a 24 px top-bar padding and the 16 px gutter. A page opens with its header (title, sentence, its own buttons right-aligned), then panels. Spacing is a 4-point scale (4, 8, 12, 16, 20, 24, 32, 40); ad-hoc values are drift.

Setup is a queue with inline forms. Wide (1100 px and up) it is three columns: the queue at 272 px (248 px narrower), the step's record list, and a 400 px side panel holding the add or edit form or the selected record (360 px under 820 px of content width). Under 660 px the side panel stacks above a 440 px list, and the queue becomes one scrolling row of tiles above the step.

### Named Rules
**The Labelled Menu Rule.** Navigation is labelled, never icon-only. Staff never learn an icon to find a page; folded, the rail names each entry on hover.

**The In Place Rule.** Records are added and edited beside their list, not in a dialog, so first-day set-up never leaves the page.

## Elevation & Depth

The console is flat. Depth is tonal: canvas, then white panels with a divider edge, then sunken steps inside a panel. Material 3's surface tint is switched off so white cards never go faintly green. Raising is done with tint and outline, not shadow: the queue head lifts with a green tint and a bigger tile; the open step is outlined in green.

### Shadow Vocabulary
- **Map float** (map-shadow, blur 24): a card or filter bar floating over map tiles.
- **Map marker** (map-shadow, blur 3 to 6): a van marker over map tiles.
- **Hover lift** (11 Nov; `AppShadow.lift`, `#047857` at 18 %, blur 18, y 6): under the pointer only. A clickable card rises 2 px on it, a top-bar pill 1 px, the main button takes it as elevation 3. Reduced motion keeps the edge and drops the movement.
- **Rest** (`AppShadow.rest`, 6 % green, blur 6): the post box alone, so the composer reads as the thing to use.

### Glass and light (11 Nov, "transparency")
The page carries two soft emerald glows over the meadow mist (top right, bottom left). The top bar and the hub's tabs are frosted glass over it: white at 78 % on a 14 px blur, a divider hairline under. Every panel that holds figures stays solid white: no amount is read through a gradient.

### Interaction states (11 Nov)
One set of see-through emerald washes for every pointer state (`AppColors.hoverWash` 8 %, `pressWash` 16 %, `focusWash` 12 %), set in the theme for every InkWell, button, tab and field. A wash is a tint over the surface, never a new colour, so text on it keeps its measured contrast.

### Named Rules
**The Pointer-Only Shadow Rule.** At rest, surfaces are flat except over map tiles and the post box's faint rest shadow. A shadow elsewhere means the pointer is on something that opens or acts.

## Shapes

Gently rounded and consistent. Buttons, inputs, menus and tooltips use 8px; sidebar entries, queue slots, stat tiles and snackbars 12px; panels, cards, dialogs and the queue frame 16px; chips, status badges, count pills and the Now pill are full pills. The pila's own objects are squarer: a queue tile is a square with a 6px corner (8px at 40px and up) and an ink edge of 1.5px (2px when large); a plate tag has a 5px corner and a 1.5px ink edge. Focus and error outlines are 2px.

### Named Rules
**The Plate Tile Rule.** The square, ink-edged tile with a bold tabular figure is the world's signature object: queue steps, the sidebar's icon plate, van plates. It is kept for things that have an order or an identity, not used as decoration.

## Components

### Buttons
Compact and sized to their label, for a mouse at a desk.
- **Shape:** gently rounded (8px).
- **Primary:** emerald fill (`#10B981`) with a dark 14px semibold label (`#0F2A20`; white would be 2.54:1), 12px by 20px padding, 40px high with a 48px pointer target (`materialTapTargetSize.padded`). One primary per view, and it is the next step: on an add form "Save and add another"; on an unassigned trip "Assign van and Dispatcher", then "Start trip". A disabled button is never the filled one.
- **Hover:** kelly `#22C55E`; an outlined button's edge turns `#059669`.
- **Keyboard focus:** a 2px ring outside the control, terminal green on the page and marker ink around a green fill. Custom tappables (menu entries, queue steps, record rows, chips) take the same ring from `FocusRing`; on the green rail it is white.
- **Outlined:** white with a control-border edge and green label; Refresh, Import, Export and a form's secondary Save.
- **Text:** green label, no fill; Cancel and in-panel "Add" actions.
- **Danger:** red fill only for a destructive confirmation in a dialog.

### Chips and Pills
- **Today chips (top bar):** see-through white full pills with a divider edge, a muted icon and label, and the figure in heavy ink or its status colour; one that needs someone keeps its status tint at rest. A breathing dot replaces the icon while vans are moving. Under the pointer: up 1 px on the lift, the secondary-hover edge, the icon green. The strip ends with its freshness: "Live · 10 s ago" with a breathing dot, a spinner while it reloads, "Not updating" in red when nothing answered; a click reloads.
- **Status badge:** a tinted full pill with a 6px dot and a bold 12px word in the tone's colour (success, warning, danger, info, neutral). Never colour alone. Money still owed is warning (ochre), never danger: owing the day's share is routine until it is paid. A van out of service is neutral.
- **Count pill:** ochre text on its tint beside a tab; amber with ink on the sidebar. Shown only when the count loaded and is above zero.
- **Filter chips:** sunken fill, selected in terminal green with white text.

### Cards / Containers
- **Panel:** white, 16px corner, divider edge, 16px padding, optional heading row (muted 18px icon, 14px semibold title, one trailing control).
- **Figure card (stat tile), toned down 10 Nov:** a white card with a divider border and a 16px corner, 16px padding. A 16px icon beside the label (in the status colour when the label has one), the 24px Plus Jakarta Sans figure in the type colour, an optional caption that carries any ratio in words ("of 14 spaces", "of 3 vans"). **One progress bar a page at most**, a real ratio only (Money: terminal fees paid; Overview: today's fees paid), a flat 6px green-text bar on the tint. **At most four cards a row** (`CardRow`, equal widths, one height); Money shows Terminal fees, Due now, Operator's share, Disputed.
- **Today panel (Overview):** above the map, three cards: Today's trips (a donut of the trip board by status, shades from light for not yet left to dark for arrived, cancelled grey, with a legend of words and counts), Needs you today (the review counts the menu shows, each row opening its page; done is a green check and "Nothing waiting", waiting an ochre count, an unloaded count says "Not loaded", never zero), and Terminal fees today (the figure card with paid of owed).
- **Setup, 11 Nov:** records that change rarely; the timetable lives in the Trips area (Trips · Timetable · Van Status Board · Special Trips), beside the post box that posts it. While the first set-up is under way the left side is the numbered queue with its progress (the order matters then; its Timetable step points to Trips › Timetable); once every required step is done it is a plain **Records** list, each with what it holds, and the page says the day's work is on Trips and Money. Each step (`StepFrame`): its heading with one primary **Add …** at the right; the records as a table (`RecordList` with `RecordColumn` heads, `RecordRow` cells in the sheet style); the side panel only when there is something to show -- the record clicked, or the add form after Add -- and a ✕ that gives the table its width back. A step with no records opens its form at once. Phones keep their cards (each carries several actions).
- **Sheet (Trips, Money), 11 Nov:** the office's paper sheets as tables. A white 16px panel with a title, filter chips and a search field; a 40px head row on meadow mist with 12px muted labels, a green italic `ƒx` after every column that fills itself; rows 60px (64 with a second line), no column rules, a `#E8F7EE` line between rows, under the pointer the see-through wash with a 3 px emerald bar sliding in at the left edge and a hand cursor (Setup's record rows add a chevron that slides in), the selected row keeping the bar on the soft tint; figures right-aligned in tabular digits; a total row on meadow mist. Trips: Time, then Van and Dispatcher as dropdown cells in the 48 px field box (an empty one ochre, "Pick a van", saved on choice), Passengers ("8 of 14"), Fares, Terminal fees (a green check when recorded), Status, one next step; a click opens the trip's detail from the right. Money: Van, Operator (trips under), Fares (B and W under), Terminal fees (paid under), Due now, Operator's share, one next step; a click opens the statement under its row. Cash is never typed into a cell: **Record payment** opens its confirm. Under 1120px the sheet scrolls sideways in its panel.
- **Post a trip (Trips, Terminal Manager), 11 Nov:** one compact composer above the sheet: title with **Post the timetable for 7 days** at its right, then route, day, time, van and Dispatcher (both optional) and **Post** on one line. The sheet is the list of trips: nothing beside the composer repeats it.
- **No word said twice (11 Nov):** a sheet row's next step is empty where its cells or status already say it (no van; arrived; cancelled). A trip's detail opens with the time, route and the sheet's own status words, then Passengers (aboard, camera count, not yet boarded, unpaid: what the row lacks) with the list, the operator, and **More on this trip**: only what the row cannot do (lift the payment block, review a start, change a started trip's van, void) and facts that add something; with nothing to add the panel is absent (`TripLifecyclePanel(besideSheet: true)`; Special Trips and Review Starts keep the full panel). The top bar shows only what needs the person, while it does (open emergencies, or that they could not be checked; reviews or vans owing; vans with no signal), else "Nothing needs you right now"; no plain counts that a page already shows.
- **Fees chart (Money):** terminal fees recorded over 7 days, 30 days or a year by month (`GET /statements/history`): bars for the fees owed (light-green gradient, the selected period solid emerald), a green-text line with nodes for the amount paid, a strip above with the selected period's owed, paid and fares. Recorded sums only: no trend, no forecast.
- **Search:** Money filters the day's statements by plate or operator; Trips filters its list by route, plate or Dispatcher. The totals on the cards still count the whole day.
- **Day picker:** the arrows step a day; the date between them opens a calendar ("Choose a day", "Show this day"), so a day weeks away is one pick. Every page with a day uses it.
- **Clickable card:** a card that opens a page shows it: a chevron beside its icon, a pointer on hover, its edge turning the secondary-hover green `#059669`, the keyboard focus ring, and a screen-reader label naming where it goes (`ClickableCard`). On Overview, Today's trips opens Trips and Terminal fees today opens Money; each "Needs you today" row and each live van opens its page.
- **Live vans (Overview, beside the map):** every van boarding or on the road as its two witnesses see it. The door camera (YOLOv8 on the van's phone): the count against the van's spaces as a figure and a load bar (green up to 14, red over), with the camera's state in words -- live, covered, silent since a time (the count shown as last count), or "No phone in the van: not counted", never 0. The GPS: live near a stop, last seen at a time, or no reading yet, and the trip's open driving flags as a link to Driving Flags. A van over its spaces heads the list in red, saying the server already alerted the Terminal Manager, the Cashier and the Dispatcher, with "Open Boarding Audit". The Van Status Board's detail line uses the same words.
- **Shadow Strategy:** none (see Elevation & Depth).

### Inputs / Fields
- **One box (11 Nov, `FieldBox`, `FieldSelect`, `FieldLabel`):** every input, dropdown, picker and read-only value is 48 px high (`AppSizing.field`), white, a control-border edge, 8px corner, an 18 px muted icon at the left, a chevron at the right for a picker; the buttons in a row with fields are 48 too. The label is small capitals over the box at one height for every field in the row, with an optional quick link at its right ("+ Next slot"). Under the pointer the edge turns `#059669` and the wash comes up; a fixed value is sunken with a lock and no hover; a problem is a 2 px red edge on the red tint, said in words, and the action that would fail is disabled beside it.
- **Style:** text fields share the box: white fill, control-border outline, 8px corner, 14px vertical padding (48 high), outlined floating label.
- **Focus:** a 2px green-text (`#047857`) outline.
- **Error / Disabled:** a red outline (2px when focused) with a 12.5px red message; disabled edges in the disabled grey. Passwords use a show/hide eye.

### Navigation
- **Sidebar:** white with an edge-green right edge, as in the reference; entries grouped under "Daily work" and "System" (sentence case); the logo at the top -- the van over the wordmark when open, the van alone when folded -- with "A2Z cooperative office" centred under it, labelled entries 44px high with a 12px corner, a light grey on hover, ink labels and muted icons.
- **Selected entry:** carried three ways: the emerald fill, the icon on a 26px white tile in green, and a bold dark label (6.03:1). Hover is a see-through green wash.
- **Emergencies:** pinned at the foot, its icon always on a red tile; it turns red when open.
- **Tabs:** under the top bar on white, green bold label and indicator for the selected tab, muted medium (500) for the rest.

### Data Tables and Record Lists
- **Tables:** sunken header row (44px), 12px bold muted heads, 14px ink cells, a divider between rows, sunken on hover.
- **Record list:** a white panel with a heading and count, an add action, and rows with a leading mark (avatar letter or plate tag), a name, a muted line and badges. A selected row takes the green tint and a bold name; its record opens in the side panel.
- **Fact row:** a 132px muted label beside a semibold value.

### The Pila Strip (signature)
The set-up queue: numbered tiles in the order the system needs them, inside a white 16px panel with a progress bar and "n of 7 done". Every state carries a mark and a word: done is a green tile that keeps its number, with a check at its corner (so the order still reads once the queue is finished), to do is an ink-edged tile with its number, waiting is a muted tile with a lock, optional is a muted tile with a tune mark. The head (the first required step not done) is raised wherever the office is looking: green tint, a 44px tile against the others' 30px, and a green "Now" pill. The open step is outlined in 1.5px terminal green. A blocked step shows its lock tile, why, and the way there. The strip is used where the order is real (the Setup queue, a van's turn); lists without an order stay plain lists. Motion is a 180ms ease-out on the slot, dropped when the platform asks for reduced motion.

### Plate Tag
A van's plate as the board's magnet: a white tag, 1.5px marker-ink edge, 5px corner, the plate in bold 13px spaced capitals.

### Validation Panel and Status Picker
The validation panel decides a record in place: its state, each fact with a mark (met, a gap that blocks Validate, a note), and the Terminal Manager's buttons. Validate is disabled with the reason on screen while a blocking fact is unmet. The status picker is a dropdown in the office's words.

### Map Selection
The selected van, its route line and the trip-progress arc are drawn in marker ink with a soft ink halo, so selection reads as neither "go", nor "paid", nor "danger". Routes and pins are marker red. The OpenStreetMap attribution stays visible as a licence condition.

## Do's and Don'ts

### Do:
- **Do** keep to the balanced greens, spent sparingly: meadow mist page, white cards with divider borders, emerald fills with dark text for the one main action, `#047857` for green text and paid/live states, red only for SOS, danger and route pins.
- **Do** keep one place and one name per job: cash is recorded with **Record payment** (the same dialog from Money and Trips), trips are made with **Add trips** on Trips, and Setup is one-time set-up.
- **Do** take every grey from the green-grey ramp and every value from `tokens.dart`.
- **Do** pair every status colour with a word and a mark (badge dot, check, lock, number).
- **Do** title each page exactly as its menu entry or tab, with one plain sentence under it.
- **Do** put new pages under one of the seven entries as a tab before adding a menu entry.
- **Do** add and edit records beside their list, with "Save and add another" as the primary on an add form.
- **Do** raise the head of an ordered queue with the green tint, a 44px tile and a Now pill, and outline the open item.
- **Do** draw map selection in marker ink.
- **Do** give anything a pointer lands on a hit area of at least 48px (`AppSizing.minTouchTarget`), and honour reduced motion.

### Don't:
- **Don't** add a dark palette or a theme toggle; the console is light only.
- **Don't** introduce blue or any fourth hue; info is marker ink.
- **Don't** use red for a primary or Save button, or for decoration.
- **Don't** put a system, table or column name on screen.
- **Don't** make navigation icon-only; the folded 76px rail is the one exception, and it names every entry on hover.
- **Don't** add shadows outside things floating over map tiles.
- **Don't** use the pila strip for a list with no real order.
- **Don't** apply this system to the mobile app; it has its own `mobile/DESIGN.md`.
- **Don't** declare a font family other than bundled Inter and Plus Jakarta Sans, or fetch a font at runtime.
- **Don't** use emerald, kelly or a lighter green as text on white; green text is `#047857`.
- **Don't** show a growth percentage, a score or a forecast on a card or chart; the system records none.
