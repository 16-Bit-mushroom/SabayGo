---
name: SabayGo operator console
description: The A2Z office console as the terminal's pila board. Whiteboard white, terminal green, marker black and red.
colors:
  terminal-green: "#0B5D35"
  terminal-green-pressed: "#0E6E40"
  green-tint: "#E3F1E7"
  on-fill: "#FFFFFF"
  sidebar-selected: "#18784A"
  sidebar-edge: "#2C7A52"
  on-sidebar-muted: "#CFE3D6"
  marker-ink: "#121712"
  marker-red: "#C8151D"
  marker-red-tint: "#FBE7E8"
  logo-plate: "#FFFFFF"
  success: "#00713C"
  success-container: "#E0EEE8"
  warning: "#8A5A00"
  warning-container: "#F6EEDC"
  danger: "#B3261E"
  danger-container: "#F6E5E4"
  info: "#121712"
  info-container: "#E6ECE8"
  attention: "#F5B841"
  enamel-white: "#FFFFFF"
  whiteboard-canvas: "#F3F6F3"
  sunken-step: "#EEF3EF"
  divider: "#DCE4DE"
  disabled: "#9AA79E"
  control-border: "#7A867C"
  muted-ink: "#4E5A52"
  scrim: "#12171773"
  map-shadow: "#00000066"
typography:
  headline-large:
    fontFamily: "Roboto, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.5px"
  headline-medium:
    fontFamily: "Roboto, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.3px"
  headline-small:
    fontFamily: "Roboto, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.2px"
  title-large:
    fontFamily: "Roboto, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.35
  title-medium:
    fontFamily: "Roboto, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.4
  title-small:
    fontFamily: "Roboto, sans-serif"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.4
  body-large:
    fontFamily: "Roboto, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
  body-medium:
    fontFamily: "Roboto, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  body-small:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.4
  label-large:
    fontFamily: "Roboto, sans-serif"
    fontSize: "14px"
    fontWeight: 700
  label-medium:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 700
  label-small:
    fontFamily: "Roboto, sans-serif"
    fontSize: "11.5px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "0.6px"
  table-head:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    letterSpacing: "0.4px"
  figure:
    fontFamily: "Roboto, sans-serif"
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
    backgroundColor: "{colors.terminal-green}"
    textColor: "{colors.on-fill}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
    hitTarget: "48px"
  button-primary-hover:
    backgroundColor: "{colors.terminal-green-pressed}"
  button-danger:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
  button-outlined:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.terminal-green}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
    height: "40px"
  button-text:
    textColor: "{colors.terminal-green}"
    typography: "{typography.label-large}"
    rounded: "{rounded.sm}"
    height: "40px"
  input:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.marker-ink}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.sm}"
    padding: "12px"
  sidebar:
    backgroundColor: "{colors.terminal-green}"
    textColor: "{colors.on-fill}"
    width: "248px"
  sidebar-folded:
    backgroundColor: "{colors.terminal-green}"
    width: "76px"
  sidebar-item:
    textColor: "{colors.on-fill}"
    rounded: "{rounded.md}"
    height: "44px"
  sidebar-item-selected:
    backgroundColor: "{colors.sidebar-selected}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.md}"
    height: "44px"
  sidebar-plate-tile:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.terminal-green}"
    rounded: "{rounded.tile}"
    size: "26px"
  top-bar:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.marker-ink}"
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
    textColor: "{colors.terminal-green}"
  count-pill:
    backgroundColor: "{colors.warning-container}"
    textColor: "{colors.warning}"
    rounded: "{rounded.full}"
  count-pill-sidebar:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.marker-ink}"
    rounded: "{rounded.full}"
  panel:
    backgroundColor: "{colors.enamel-white}"
    rounded: "{rounded.lg}"
    padding: "16px"
  stat-tile:
    backgroundColor: "{colors.sunken-step}"
    textColor: "{colors.marker-ink}"
    typography: "{typography.figure}"
    rounded: "{rounded.md}"
    padding: "12px"
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
    backgroundColor: "{colors.green-tint}"
    rounded: "{rounded.md}"
    padding: "12px 8px"
  queue-tile:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.marker-ink}"
    rounded: "{rounded.tile}"
    size: "30px"
  queue-tile-head:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.marker-ink}"
    rounded: "{rounded.sm}"
    size: "44px"
  queue-tile-done:
    backgroundColor: "{colors.terminal-green}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.tile}"
    size: "30px"
  queue-tile-waiting:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.muted-ink}"
    rounded: "{rounded.tile}"
    size: "30px"
  now-pill:
    backgroundColor: "{colors.terminal-green}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.full}"
  plate-tag:
    backgroundColor: "{colors.enamel-white}"
    textColor: "{colors.marker-ink}"
    rounded: "{rounded.plate}"
  record-row-selected:
    backgroundColor: "{colors.green-tint}"
    textColor: "{colors.marker-ink}"
  side-panel:
    backgroundColor: "{colors.enamel-white}"
    rounded: "{rounded.lg}"
    width: "400px"
  tooltip:
    backgroundColor: "{colors.marker-ink}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.sm}"
  snackbar:
    backgroundColor: "{colors.marker-ink}"
    textColor: "{colors.on-fill}"
    rounded: "{rounded.md}"
    width: "480px"
---

# Design System: SabayGo operator console

Scope: the A2Z office console (`operator_console/`, Flutter Web), used by the Terminal Manager and the Cashier. The Passenger and Dispatcher app keeps its own system in `mobile/DESIGN.md`; nothing here applies to it. The source of truth for every value is `operator_console/lib/core/design/tokens.dart` and `theme.dart`; this file records them.

## Overview

**Creative North Star: "The Pila Board"**

The console is the terminal's pila: the dispatch whiteboard where vans queue by plate number and the van at the head goes next. Every ordered list is a queue with a head, and the head is the thing to do now. Staff see what is next, do it in place, and watch the queue advance. The world is made of the board's own materials: whiteboard enamel for the page, painted terminal-green steel for the frame and the action colour, marker black for words, marker red only for alarms and route pins, and square plate-number tiles that sit on the board like magnets.

It is a desk tool for non-technical office staff working all day, sometimes on a projector, so it is light only, dense enough for a desk, and plain. Seven labelled menu entries replace sixteen flat ones; related pages sit as tabs under their entry. First-day set-up is one page: a queue of steps on the left, the step's records in the middle, the add or edit form beside them. Nothing on screen uses a system or table name; the console speaks in A2Z's words.

The dark "Night Owl's Ledger" console and the earlier deep purple are retired. There is no dark palette and no fourth hue.

**Key Characteristics:**
- White, green and black/red in a 60-30-10 split.
- Light only, Roboto bundled, flat white panels on a faint green-white canvas.
- A green sidebar with seven labelled hubs, Emergencies pinned at its foot.
- The pila strip: an ordered column of plate tiles whose head is raised.
- Every state carries a word and a mark, never colour alone.
- Selection is marker ink on the map and green tint in lists.

## Colors

Whiteboard white is the page, terminal green is the frame and the action, and marker black and red are the ink.

### Primary
- **Terminal Green** (terminal-green): the sidebar, filled primary buttons, the focus outline, the avatar, the selected tab, a done queue tile and the Now pill. White on it is 7.98:1.
- **Terminal Green, Pressed** (terminal-green-pressed): hovered and pressed primary.
- **Green Tint** (green-tint): the raised head of the set-up queue and a selected record row. Terminal green on it is 6.84:1.
- **Sidebar Selected** (sidebar-selected): the selected menu entry, one step lighter than the rail. White on it is 5.49:1; the fill is never the only cue.
- **Sidebar Muted** (on-sidebar-muted): unselected sidebar icons and captions, 5.93:1 on the rail. **Sidebar Edge** (sidebar-edge) is a decorative rule above the fold button.

### Secondary
- **Marker Red** (marker-red): the logo's red. Route geometry and pins on the map, nothing else. 5.86:1. **Marker Red Tint** (marker-red-tint) is its container.
- **Danger** (danger): cancelled, failed, refused, the Emergencies entry, destructive confirmation buttons and error messages. 6.54:1; 5.37:1 on danger-container.

### Tertiary
- **Ochre Warning** (warning): awaiting payment, a difference to look at, and the count pill on a tab. 5.93:1; 5.13:1 on warning-container.
- **Attention Amber** (attention): the count pill on the green sidebar only, with marker ink on it (10.21:1).
- **Success Green** (success): confirmed, paid, boarded, live, validated. 6.13:1; 5.12:1 on success-container.

### Neutral
All neutrals come from one fixed green-grey ramp (`AppRamp` n0 to n900).
- **Enamel White** (enamel-white, n0): panels, cards, the top bar, the tab bar, inputs and side panels.
- **Whiteboard Canvas** (whiteboard-canvas, n50): the page behind every panel.
- **Sunken Step** (sunken-step, n100): table header rows, hovered rows, stat tiles, read-only fields.
- **Divider** (divider, n200): decorative separation only, panel edges and row rules.
- **Disabled** (disabled, n400): a disabled control's edge, a waiting queue tile, the resting scrollbar.
- **Control Border** (control-border, n500): the edge of anything interactive (inputs, outlined buttons, day picker). 3.80:1, clears WCAG 1.4.11.
- **Muted Ink** (muted-ink, n700): secondary text, descriptions, captions, labels. 7.22:1.
- **Marker Ink** (marker-ink, n900): body text, titles, tooltips, snackbars, the selected van and route on the map. 18.15:1.
- **Info** (info) resolves to marker ink, with **Info Container** (info-container) as its tint: "Scheduled", "At terminal".

### Named Rules
**The 60-30-10 Rule.** White is the page (about 60 %), terminal green is the frame and the action colour (about 30 %), black and red are the ink (about 10 %). No other hue carries meaning or decoration.

**The Red Is An Alarm Rule.** Red means SOS, danger or a route pin. It is never a primary button, so a red SOS never sits beside a red Save. The only red fill on a button is a destructive confirmation.

**The No Blue Rule.** Informational status is marker ink on a grey-green tint, not a fourth hue. Blue is out of the world.

**The One Ramp Rule.** Every grey is a step of the green-grey ramp. No screen mixes its own grey.

**The Measured Pair Rule.** Every text and control pairing is measured against WCAG 2.1 AA, and anything drawn on a filled colour uses on-fill white.

## Typography

**Body Font:** Roboto, bundled in `operator_console/assets/fonts` (Regular 400, Medium 500, Bold 700), so every demo machine renders the same face. Only those three weights exist: a 600 or 800 is drawn as 700, so code asks for 400, 500 or 700 only. Where weight carries a state (the selected tab, a selected record), it is 500 against 700.

**Character:** One workmanlike sans for everything. Hierarchy comes from size and weight, and figures are set heavy so a count reads from across the office.

### Hierarchy
- **Headline Medium** (700, 24px, 1.3, -0.3px): every page title, worded exactly as its menu entry or tab.
- **Title Large** (700, 18px, 1.35): a Setup step's title under the page title (the compact page header), and dialog titles.
- **Title Small** (700, 14px, 1.4): panel headings, queue step names.
- **Body Medium** (400, 14px, 1.45): table cells, form text, the one plain sentence under every title (in muted ink).
- **Body Small** (400, 12.5px, 1.4): captions and the line under a record name, in muted ink.
- **Label Large** (700, 14px): button labels.
- **Label Medium** (700, 12px): stat tile labels and column heads, in muted ink.
- **Table Head** (700, 12px, 0.4px tracking): data table column heads on the sunken header row, in sentence case.
- **Figure** (700, 22px, 1.2): a stat tile's number; the top-bar figures use the same weight at 14px.

### Named Rules
**The Title Is The Label Rule.** A page title matches its menu entry or tab word for word, and has one plain sentence under it.

**The Office Words Rule.** System, table and column names never appear on screen. Statuses are shown in A2Z's words ("Not yet boarded", "No longer working"), not stored values.

## Layout

The shell is fixed: a 248 px terminal-green sidebar (76 px folded, names shown on hover), a 64 px white top bar carrying today's figures as outlined pills, the bell and the signed-in person, then, for a hub with more than one page, a 46 px white tab bar, then the page on the whiteboard canvas.

Seven menu entries: Overview, Trips, Reviews, Money, Messages, Setup, and Emergencies (SOS) pinned at the sidebar's foot apart from the rest. Pages that answer the same question are tabs under one entry. The Cashier's menu omits the Terminal Manager's pages rather than refusing them.

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

### Named Rules
**The Map-Only Shadow Rule.** Shadows exist only on things floating over map tiles. Everywhere else, surfaces are flat at rest, including the notification sheet and the SOS cards (an open alert is marked by its red edge).

## Shapes

Gently rounded and consistent. Buttons, inputs, menus and tooltips use 8px; sidebar entries, queue slots, stat tiles and snackbars 12px; panels, cards, dialogs and the queue frame 16px; chips, status badges, count pills and the Now pill are full pills. The pila's own objects are squarer: a queue tile is a square with a 6px corner (8px at 40px and up) and an ink edge of 1.5px (2px when large); a plate tag has a 5px corner and a 1.5px ink edge. Focus and error outlines are 2px.

### Named Rules
**The Plate Tile Rule.** The square, ink-edged tile with a bold tabular figure is the world's signature object: queue steps, the sidebar's icon plate, van plates. It is kept for things that have an order or an identity, not used as decoration.

## Components

### Buttons
Compact and sized to their label, for a mouse at a desk.
- **Shape:** gently rounded (8px).
- **Primary:** terminal-green fill, white 14px bold label, 12px by 20px padding, 40px high with a 48px pointer target (`materialTapTargetSize.padded`). One primary per view, and it is the next step: on an add form "Save and add another"; on an unassigned trip "Assign van and Dispatcher", then "Start trip". A disabled button is never the filled one.
- **Hover:** a step to terminal-green-pressed.
- **Keyboard focus:** a 2px ring outside the control, terminal green on the page and marker ink around a green fill. Custom tappables (menu entries, queue steps, record rows, chips) take the same ring from `FocusRing`; on the green rail it is white.
- **Outlined:** white with a control-border edge and green label; Refresh, Import, Export and a form's secondary Save.
- **Text:** green label, no fill; Cancel and in-panel "Add" actions.
- **Danger:** red fill only for a destructive confirmation in a dialog.

### Chips and Pills
- **Today chips (top bar):** white full pills with a divider edge, a muted icon and label, and the figure in heavy ink or its status colour.
- **Status badge:** a tinted full pill with a 6px dot and a bold 12px word in the tone's colour (success, warning, danger, info, neutral). Never colour alone. Money still owed is warning (ochre), never danger: owing the day's share is routine until it is paid. A van out of service is neutral.
- **Count pill:** ochre text on its tint beside a tab; amber with ink on the sidebar. Shown only when the count loaded and is above zero.
- **Filter chips:** sunken fill, selected in terminal green with white text.

### Cards / Containers
- **Panel:** white, 16px corner, divider edge, 16px padding, optional heading row (muted 18px icon, 14px semibold title, one trailing control).
- **Stat tile:** sunken step fill, 12px corner, 12px padding, a muted label over a 22px heavy figure.
- **Shadow Strategy:** none (see Elevation & Depth).

### Inputs / Fields
- **Style:** white fill, control-border outline, 8px corner, dense 12px padding, outlined floating label.
- **Focus:** a 2px terminal-green outline.
- **Error / Disabled:** a red outline (2px when focused) with a 12.5px red message; disabled edges in the disabled grey. Passwords use a show/hide eye.

### Navigation
- **Sidebar:** terminal-green rail, logo on a white plate at the top with "A2Z cooperative office" under it, labelled entries 44px high with a 12px corner, a white wash on hover.
- **Selected entry:** carried three ways: a lighter green fill, the icon set on a 26px white plate tile in green, and a bold label.
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
- **Do** keep the 60-30-10 split: white page, terminal-green frame and actions, black text with red only for SOS, danger and route pins.
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
- **Don't** declare a font family other than bundled Roboto.
