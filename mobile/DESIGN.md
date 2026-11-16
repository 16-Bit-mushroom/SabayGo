---
name: SabayGo (Passenger and Dispatcher app)
description: The office console's balanced mid-green, sized for a thumb. Clean and minimal, built to read in sunlight at a van door.
colors:
  green-text: "#047857"
  green-outline: "#059669"
  emerald-tint: "#DCFCE7"
  emerald: "#10B981"
  kelly: "#22C55E"
  on-emerald: "#0F2A20"
  green-edge: "#86EFAC"
  pin-red: "#C8151D"
  pin-red-mist: "#FBE7E8"
  paid-green: "#047857"
  paid-green-mist: "#DCFCE7"
  ochre: "#8A5A00"
  ochre-mist: "#FFF4DB"
  sos-red: "#B3261E"
  sos-red-mist: "#FDECEA"
  info-slate: "#1E3A2F"
  info-mist: "#E6EFEA"
  meadow-mist: "#F0FDF4"
  white-card: "#FFFFFF"
  sunken: "#E8F7EE"
  slate-green: "#1E3A2F"
  slate-note: "#4B6358"
  control-edge: "#6B8579"
  hairline: "#BBF7D0"
  disabled: "#A3B8AD"
typography:
  headline-large:
    fontFamily: "Plus Jakarta Sans"
    fontSize: "28px"
    fontWeight: 800
    lineHeight: 1.25
    letterSpacing: "-0.5px"
  headline-medium:
    fontFamily: "Plus Jakarta Sans"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.3px"
  app-bar-title:
    fontFamily: "Plus Jakarta Sans"
    fontSize: "20px"
    fontWeight: 700
    letterSpacing: "-0.2px"
  title-large:
    fontFamily: "Plus Jakarta Sans"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.35
  title-medium:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.4
  body-large:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  body-medium:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  body-small:
    fontFamily: "Inter"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  label-button:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 600
  label-small:
    fontFamily: "Inter"
    fontSize: "11.5px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.4px"
rounded:
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
    backgroundColor: "{colors.emerald}"
    textColor: "{colors.on-emerald}"
    typography: "{typography.label-button}"
    rounded: "{rounded.md}"
    height: "52px"
    width: "100%"
  button-primary-pressed:
    backgroundColor: "{colors.kelly}"
    textColor: "{colors.on-emerald}"
  button-primary-disabled:
    backgroundColor: "{colors.sunken}"
    textColor: "{colors.slate-note}"
  button-outlined:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.green-text}"
    typography: "{typography.label-button}"
    rounded: "{rounded.md}"
    height: "52px"
    width: "100%"
  button-text:
    textColor: "{colors.green-text}"
    height: "48px"
  input-field:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.slate-green}"
    typography: "{typography.body-large}"
    rounded: "{rounded.md}"
    padding: "16px"
  card:
    backgroundColor: "{colors.white-card}"
    rounded: "{rounded.lg}"
    padding: "16px"
  chip-status-success:
    backgroundColor: "{colors.paid-green-mist}"
    textColor: "{colors.paid-green}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-warning:
    backgroundColor: "{colors.ochre-mist}"
    textColor: "{colors.ochre}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-danger:
    backgroundColor: "{colors.sos-red-mist}"
    textColor: "{colors.sos-red}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-info:
    backgroundColor: "{colors.info-mist}"
    textColor: "{colors.info-slate}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-brand:
    backgroundColor: "{colors.emerald-tint}"
    textColor: "{colors.green-text}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-muted:
    backgroundColor: "{colors.meadow-mist}"
    textColor: "{colors.slate-note}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  status-band:
    rounded: "{rounded.md}"
    padding: "16px"
  app-bar:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.slate-green}"
    typography: "{typography.app-bar-title}"
  navigation-bar:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.slate-note}"
    height: "68px"
  navigation-bar-selected:
    backgroundColor: "{colors.emerald}"
    textColor: "{colors.green-text}"
    rounded: "{rounded.full}"
  bottom-sheet:
    backgroundColor: "{colors.white-card}"
    rounded: "{rounded.xl}"
  snackbar:
    backgroundColor: "{colors.slate-green}"
    textColor: "{colors.white-card}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.md}"
---

# Design System: SabayGo (Passenger and Dispatcher app)

Source of truth in code: `lib/core/design/tokens.dart` (colour, spacing,
radius, sizing, motion), `lib/core/design/theme.dart` (the one `ThemeData`)
and `lib/core/design/components/`. Sizes below are Flutter logical pixels
(dp), written as px.

## Overview

**One product, three screens.** Since 10 Nov the phone app wears the office
console's palette and type (`DESIGN.md` at the repo root, "VerdantPulse"):
a passenger booking a space, the Dispatcher at the van door and the
Terminal Manager at the office desk see the same greens, the same cards and
the same buttons. The token names and values in `tokens.dart` match the
console's; change one, change both.

The app is clean and minimal, built to be read in sunlight at a van door.
A meadow-mist page with white cards edged in mid-light green, one emerald
action per decision, status said in words on a tinted chip. Calm and exact
rather than expressive: weight, spacing and alignment carry the hierarchy,
and the interface stays quiet so a warning or an SOS stands out the moment
it appears. Light theme only; the app has no dark theme.

The owl and its ink-black palette (3 Oct to 10 Nov) and the September
purple (`#2D2059`) are retired. Anything still ink-black or purple, or that
describes an "owl" brand, is out of date.

**Key Characteristics:**
- Emerald (`#10B981`) with dark text is the main action; green text is
  `#047857`. Red marks route geometry and SOS only.
- Status is a meaning (`StatusTone`), never a loose colour, and always comes
  with a word or an icon.
- Every colour pair is measured against WCAG 2.1 AA; control edges clear
  3:1.
- Inter for text and Plus Jakarta Sans for headings, bundled, so type is
  identical on every phone and matches the console.
- Full-width 52 px primary actions, 48 px minimum targets, one-handed reach.
- Flat: cards are separated from the page by a green edge, never a shadow.

## Colors

A balanced mid-green: a mist page, white cards with a mid-light green edge,
emerald for the action, a deep green for text and icons, and a slate
green-grey for type. Four semantic tones each come as a text colour with
its own tinted container. All ratios are computed.

### Primary
- **Emerald** (`AppColors.action`): filled buttons, the selected tab's pill,
  the floating button. Never text (2.54:1 on white); everything on it is
  **On Emerald** (`onAction`, `#0F2A20`, 6.03:1).
- **Kelly** (`actionHover`, `#22C55E`): the main action while pressed
  (On Emerald on it 6.72:1).
- **Green Text** (`primary`, `#047857`, 5.48:1 on white, 5.24:1 on the
  page, 4.99:1 on the tint): links, outlined and text button labels, the
  selected tab's label, focus outlines, progress, icons in list tiles. White
  on it is 5.48:1, so it is also the fill for a selected chip or segment.
- **Green Outline** (`primaryLight`, `#059669`): an outlined button's edge
  while pressed or focused.
- **Emerald Tint** (`primaryContainer`, `#DCFCE7`): icon tiles, avatars, the
  neutral "brand" chip (for example Scheduled), the progress track.

### Secondary
- **Pin Red** (`brand`, 5.86:1 on white): the passenger's own boarding and
  alighting markers on the journey strip and the live map.
- **Pin Red Mist** (`brandContainer`, Pin Red on it 4.9:1): the tint behind
  a red marker.

### Tertiary (semantic tones)
- **Paid Green** (`success`, 5.48:1) on **Emerald Tint** (4.99:1):
  confirmed, paid, boarded.
- **Ochre** (`warning`, 5.93:1) on **Ochre Mist** (5.42:1): awaiting
  payment, needs attention. Amber is never used as text; it fails on white.
- **SOS Red** (`danger`, 6.54:1) on **SOS Red Mist** (5.72:1): cancelled,
  failed, flagged, the SOS. White on it 6.54:1.
- **Info Slate** (`info`, the type colour) on **Info Mist** (10.52:1):
  informational, neither good nor bad (At terminal, queued to send). It was
  a blue until 10 Nov; the console's slate keeps the screen to one hue
  family.

### Neutral (one green-grey ramp, `AppRamp`)
- **Meadow Mist** (`surface`, `#F0FDF4`): every page background, the muted
  chip's fill.
- **White Card** (`surfaceRaised`): cards, app bar, navigation bar, sheets,
  dialogs, input fills.
- **Sunken** (`surfaceSunken`, `#E8F7EE`): a disabled button, a step inside
  a card.
- **Slate Green** (`textPrimary`, `#1E3A2F`, 12.34:1; 11.79:1 on the page):
  all primary text; the snackbar's fill.
- **Slate Note** (`textMuted`, `#4B6358`, 6.51:1; 6.22:1 on the page):
  secondary text, labels, unselected navigation. Muted is still AA.
- **Control Edge** (`border`, `#6B8579`, 4.00:1 on white): the outline of
  anything a user must find to operate it: inputs, outlined buttons, chips,
  the journey rail.
- **Green Edge** (`edge`, `#86EFAC`): card outlines and the app bar's rule.
  Decorative.
- **Hairline** (`divider`, `#BBF7D0`): dividers inside a card. Decorative.

### Named Rules

**The Dark-on-Emerald Rule.** Text, icons and spinners on the emerald or
the kelly are On Emerald, never white (2.54:1). White goes on Green Text,
the status colours and SOS Red.

**The One Meaning for Red Rule.** Pin Red marks route geometry and is never
a button fill. On an action, red means stop or danger, and that is SOS Red,
with white text. A red Book beside a red Cancel beside a red SOS would make
all three look equally alarming.

**The Pair Rule.** A status colour is chosen as a `StatusTone`, which hands
over its text colour and container together, both verified. Never pick a
foreground on its own, and never let hue alone carry the status.

**The Edge Rule.** If a user must locate it to operate it, its boundary is
Control Edge (3:1 or more). Green Edge and Hairline are for decoration.

## Typography

**Heading font:** Plus Jakarta Sans 600 / 700 / 800 (bundled)
**Text font:** Inter 400 / 500 / 600 / 700 (bundled), tabular figures for money

**Character:** the console's pair. Plus Jakarta Sans gives headings and the
app bar a rounder, friendlier face; Inter carries everything a person reads
or taps, at every weight it is set in, so no weight is synthesised.

### Hierarchy
- **Headline Large** (Jakarta 800, 28 px, 1.25, −0.5 px): a screen's single
  heading, used sparingly.
- **Headline Medium** (Jakarta 700, 22 px, 1.3, −0.3 px): screen headings
  such as sign-in, the headline figure on the trip details sheet.
- **App Bar Title** (Jakarta 700, 20 px, −0.2 px): left-aligned on the
  gutter. Dialog titles match it.
- **Title Large** (Jakarta 700, 18 px, 1.35): sheet titles, empty-state
  titles.
- **Title Medium** (Inter 600, 16 px, 1.4): section headers, status band
  titles.
- **Body Large / Medium / Small** (Inter 400; 16 / 14 / 13 px): reading
  text; Small is Slate Note, for notes under a value.
- **Label Button** (Inter 600, 16 px): filled and outlined buttons (text
  buttons 15 px).
- **Label Small** (Inter 600, 11.5 px, +0.4 px): status chips and
  micro-labels.

### Named Rules

**The Tabular Money Rule.** Every peso amount goes through `Money`, with
tabular figures, so a fare that changes never makes its column jump. Lists
that are scanned show whole pesos (₱1,180); receipts show centavos
(₱1,180.00).

**The Uncapped Rule.** No text size is capped and no single-line height is
hardcoded. Text must survive 200 % system scaling (WCAG 1.4.4), which is
why headline sizes stay restrained.

**The Carried Type Rule.** The families are bundled, never fetched and
never borrowed from the phone. The app is used in connectivity dead zones,
and a font that arrives over the network is missing exactly when it
matters. Both are SIL OFL (`assets/fonts/OFL-*.txt`).

## Layout

A single phone column on a 4-point scale (4, 8, 12, 16, 20, 24, 32, 40).
One side gutter, 16 px, on every screen; titles, list tiles and content all
start on it. App bar titles sit left, never centred.

- **Navigation:** a bottom Material `NavigationBar`, 68 px, labels always
  shown. Inner tab bars (booking history, the Dispatcher's passenger list)
  sit under the app bar.
- **Actions:** primary and outlined buttons fill the width and stand 52 px
  tall, placed where a thumb reaches. Nothing tappable is under 48 × 48 px.
- **Rows:** an info row splits 4 : 6, the label left in Slate Note and the
  value right-aligned in 600. List tiles use the gutter with 12 px vertical
  padding.
- **Sheets:** bottom sheets rise to at most 90 % of the screen, move up
  with the keyboard and keep to the safe area.
- **Empty states:** centred, 40 px side padding, icon (48 px, Slate Note),
  title, one sentence, then an optional action. Still scrollable, so pull
  to refresh works.
- **Motion:** 100 ms (instant), 180 ms (quick), 240 ms (normal). Material's
  ink sparkle on press. Anything that animates honours reduce motion
  (`MediaQuery.disableAnimations`).

## Elevation & Depth

Flat. The theme sets zero elevation everywhere; the app bar does not lift
when content scrolls under it and is closed by a 1 px Green Edge rule
instead. Cards, grouped settings, the profile summary and saved
destinations are White Card with a 1 px Green Edge outline. A fixed action
bar at the foot of a form has a Green Edge rule along its top.

The only shadows are on the live map: the van and stop markers
(`0 0 3–8px rgba(0,0,0,0.12–0.38)`) need to stand off busy streets, and the
floating button keeps Material's elevation 2.

**The Edge, Not Shadow Rule.** A card is told apart from the mist page by
its green edge. A grey shadow muddies the green and reads as the generic
card kit.

## Shapes

Gently rounded throughout, with the radius growing with the surface.

- **12 px:** buttons, input fields, status bands, the snackbar.
- **16 px:** cards and dialogs.
- **20 px:** the top corners of bottom sheets, and the profile summary.
- **Pill (999 px):** status chips, filter chips, the navigation indicator,
  avatars.
- **8 px:** small inner elements.
- **Journey geometry:** the boarding point is a hollow Pin Red ring (13 px,
  2.5 px stroke); the alighting point is a filled Pin Red square with 3 px
  corners; the rail between them is a 2 px Control Edge line.

## Components

### Buttons
- **Primary (filled):** Emerald with an On Emerald 16 px / 600 label, full
  width, 52 px tall; Kelly while pressed; Sunken with a Slate Note label
  when it cannot be used. A busy spinner on it is On Emerald.
- **Danger (filled):** SOS Red with white text (sign out, the SOS). The SOS
  send button stays red while it sends: an alert on its way must not look
  switched off.
- **Outlined:** White Card, Green Text label, 1 px Control Edge outline
  (Green Outline, 2 px, when focused). The second choice beside a primary.
- **Text:** Green Text, 15 px / 600, at least 48 × 48 px.
- **Segmented:** Control Edge outline; the selected segment is Green Text
  fill with white.

### Chips
- **Status chip:** pill, tone container fill, tone text in Label Small,
  optional 13 px icon. Announced as "status: label".
- **Tones:** success (Paid Green), info (Info Slate), warning (Ochre),
  danger (SOS Red), brand (Green Text on Emerald Tint, a neutral default
  such as Scheduled), muted (Slate Note on Meadow Mist, so a finished trip
  recedes).
- **Filter chips** (time of day): White Card with a Control Edge outline;
  selected, Green Text fill with a white bold label.

### Status Band
The full-width statement of a state, for example the status on a booking.
A tone container fill, a 1 px outline in the tone's colour at 30 % opacity,
12 px radius, 16 px padding, a 22 px icon, a Title Medium headline in the
tone's colour, then a Body Medium sentence. It can be a live region, so a
screen reader announces a change.

### Cards / Containers
- **Card (`AppCard`, and the theme's `Card`):** White Card, 16 px radius,
  1 px Green Edge outline, 16 px padding, no shadow. When tappable, the
  ripple is clipped to the radius.
- **Bottom sheet (`AppSheet`):** White Card, 20 px top corners, drag
  handle, a Title Large header with an optional Body Small subtitle, and a
  Close icon button on the right.
- **Dialog:** White Card, 16 px radius, Jakarta title, no surface tint.

### Inputs / Fields
- **Style:** filled White Card, 1 px Control Edge outline, 12 px radius,
  16 px padding. The label is Slate Note, Green Text once it floats.
- **Focus:** the outline goes to 2 px Green Text.
- **Error:** SOS Red outline (2 px when focused), and a 13 px / 500 SOS Red
  message that says what to do.
- **Picker row (`AppPickerRow`):** a tappable row that shows the current
  answer, or a placeholder until one is chosen.

### Navigation
- **App bar:** White Card, no elevation, a 1 px Green Edge rule beneath,
  Slate Green left-aligned Jakarta title on the gutter.
- **Bottom navigation bar:** White Card, 68 px, labels always shown. The
  selected item is the console's selected sidebar entry on a phone: an
  Emerald pill behind an On Emerald icon, the icon filled, the label in
  Green Text at 700 (unselected: Slate Note at 500).
- **Tab bar:** Green Text label and indicator, Slate Note unselected,
  Hairline divider.
- **Snackbar:** floating, Slate Green fill, white 14 px text, Green Edge
  action, 12 px radius.

### Journey Strip (signature)
The passenger's journey as two stops on a rail: the boarding ring, a 2 px
Control Edge rail, the alighting square, each with the stop name in Body
Large 600 and an optional note. Read aloud as "From X. To Y." This is where
Pin Red lives, and the live map's markers echo it.

### Money (signature)
Tabular figures, ₱ prefix, whole pesos in lists and centavos on receipts.

### Empty State
Icon, Title Large headline, one Slate Note sentence, optional action, all
centred. The sentence says what to do next.

### Brand Logo
The console's van logo (`assets/branding/sabaygo_van_logo.png`): 120 px on
the welcome and splash screens, 72 px as a screen header. In an app bar the
van alone (`sabaygo_van_mark.png`, `BrandLogo(mark: true)`), because the
wordmark is unreadable at 30–36 px. Black ink on transparent, so it is drawn
only on a light surface; never recoloured.

## Do's and Don'ts

### Do:
- **Do** take every colour from `AppColors` or the theme, and every status
  colour through `StatusTone`.
- **Do** state a status in words or with an icon, never by colour alone.
- **Do** make the primary action an Emerald slab with dark text, full
  width, 52 px tall, within thumb reach, and only one per screen.
- **Do** give a button that sets its own dark fill (SOS Red, Green Text) a
  white `foregroundColor`: the theme's label colour is On Emerald.
- **Do** keep every tappable target at 48 × 48 px or more.
- **Do** outline every control a user must find in Control Edge.
- **Do** route every peso amount through `Money`.
- **Do** keep the palette in step with the console's `tokens.dart`.

### Don't:
- **Don't** put white text, icons or spinners on the emerald or the kelly.
- **Don't** fill a button with Pin Red, or use Pin Red for anything other
  than route geometry.
- **Don't** bring back the owl, its ink-black, the retired purple, or a
  coloured app bar.
- **Don't** write raw `Colors.*` or `Color(0x…)` in a screen. The remaining
  uses are the live map's markers (white rings and their shadows over the
  tiles) and white on dark fills; they are not precedent.
- **Don't** use amber or yellow as text; it fails on white. Use Ochre.
- **Don't** use gradients, or a shadow on a card.
- **Don't** centre an app bar title or hide navigation labels.
- **Don't** fetch a font at runtime or cap text size.
