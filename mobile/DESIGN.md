---
name: SabayGo (Passenger and Dispatcher app)
description: Ink on paper, a watchful red eye, a record that adds up. Clean and minimal, built to read in sunlight at a van door.
colors:
  owl-ink: "#16161D"
  owl-ink-soft: "#3A3A44"
  ink-mist: "#ECECF0"
  pin-red: "#C8151D"
  pin-red-mist: "#FBE7E8"
  paid-green: "#00713C"
  paid-green-mist: "#E0EEE8"
  ochre: "#8A5A00"
  ochre-mist: "#F1EBE0"
  sos-red: "#B3261E"
  sos-red-mist: "#F6E5E4"
  terminal-blue: "#1565C0"
  terminal-blue-mist: "#E3EAF2"
  morning-paper: "#F7F7FA"
  white-card: "#FFFFFF"
  night-text: "#1A1A2E"
  slate-note: "#5A5A6E"
  control-edge: "#84849C"
  hairline: "#DDDDE5"
typography:
  headline-large:
    fontFamily: "Roboto"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.5px"
  headline-medium:
    fontFamily: "Roboto"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.3px"
  app-bar-title:
    fontFamily: "Roboto"
    fontSize: "20px"
    fontWeight: 700
    letterSpacing: "-0.2px"
  title-large:
    fontFamily: "Roboto"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.35
  title-medium:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.4
  body-large:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  body-medium:
    fontFamily: "Roboto"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  body-small:
    fontFamily: "Roboto"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  label-button:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 600
  label-small:
    fontFamily: "Roboto"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "0.8px"
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
    backgroundColor: "{colors.owl-ink}"
    textColor: "{colors.white-card}"
    typography: "{typography.label-button}"
    rounded: "{rounded.md}"
    height: "52px"
    width: "100%"
  button-outlined:
    textColor: "{colors.owl-ink}"
    typography: "{typography.label-button}"
    rounded: "{rounded.md}"
    height: "52px"
    width: "100%"
  button-text:
    textColor: "{colors.owl-ink}"
    height: "48px"
  input-field:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.night-text}"
    typography: "{typography.body-large}"
    rounded: "{rounded.md}"
    padding: "16px"
  card-outlined:
    backgroundColor: "{colors.white-card}"
    rounded: "{rounded.lg}"
    padding: "16px"
  card-raised:
    backgroundColor: "{colors.white-card}"
    rounded: "{rounded.lg}"
    padding: "20px"
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
    backgroundColor: "{colors.terminal-blue-mist}"
    textColor: "{colors.terminal-blue}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-brand:
    backgroundColor: "{colors.ink-mist}"
    textColor: "{colors.owl-ink}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  chip-status-muted:
    backgroundColor: "{colors.morning-paper}"
    textColor: "{colors.slate-note}"
    typography: "{typography.label-small}"
    rounded: "{rounded.full}"
    padding: "6px 10px"
  status-band:
    rounded: "{rounded.md}"
    padding: "16px"
  app-bar:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.night-text}"
    typography: "{typography.app-bar-title}"
  navigation-bar:
    backgroundColor: "{colors.white-card}"
    textColor: "{colors.slate-note}"
    height: "68px"
  navigation-bar-selected:
    backgroundColor: "{colors.ink-mist}"
    textColor: "{colors.owl-ink}"
    rounded: "{rounded.full}"
  bottom-sheet:
    backgroundColor: "{colors.white-card}"
    rounded: "{rounded.xl}"
  snackbar:
    backgroundColor: "{colors.night-text}"
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

**Creative North Star: "The Night Owl's Ledger"**

The logo is an ink-black owl with a red eye, beside a route line that ends
in a red pin. The app takes its two jobs from it. Ink is the hand that
writes the record: every action, every selected state, every line of text
someone acts on. Red is the eye on the route: it marks where a passenger
boards and where they get off, and nothing else. The ledger part is the
discipline: figures line up, each status is stated in a word, and nothing
shows a fact the system does not have.

The app is clean and minimal, built to be read in sunlight at a van door.
Paper-grey screens with white cards, one ink action per decision, status
said in words on a tinted chip. It is calm and exact rather than
expressive. Weight, spacing and alignment carry the hierarchy. The interface
stays quiet, so a warning or an SOS stands out the moment it appears.
Light theme only; the app has no dark theme.

The September purple (`#2D2059`) is retired. Anything still purple, or
anything that describes a "purple brand", is out of date.

**Key Characteristics:**
- Ink (`#16161D`) does every action. Red marks route geometry only.
- Status is a meaning (`StatusTone`), never a loose colour, and always comes
  with a word or an icon.
- Every colour pair is measured against WCAG 2.1 AA; control edges clear
  3:1.
- Roboto bundled at 400 / 500 / 700, so type is identical on every phone.
- Full-width 52 px primary actions, 48 px minimum targets, one-handed reach.
- Flat by default; soft ambient shadows only on raised cards.

## Colors

A near-monochrome ink-and-paper base, one red for the route, and four
semantic tones that each come as a text colour with its own tinted
container.

### Primary
- **Owl Ink** (`AppColors.primary`, 18.0:1 on white): filled buttons, focus
  outlines, the selected tab and navigation item, progress indicators,
  outlined and text button labels. It is the colour of "the thing you act
  on".
- **Owl Ink Soft** (`primaryLight`, 11.2:1): secondary surfaces and pressed
  states.
- **Ink Mist** (`primaryContainer`, Owl Ink on it 15.3:1): the selected
  navigation pill, the neutral "brand" chip (for example SCHEDULED), default
  chip fill.

### Secondary
- **Pin Red** (`brand`, 5.86:1 on white): the passenger's own boarding and
  alighting markers on the journey strip and the live map. Allowed as text,
  meant for markers.
- **Pin Red Mist** (`brandContainer`, Pin Red on it 4.9:1): the tint behind
  a red marker label.

### Tertiary (semantic tones)
- **Paid Green** (`success`, 6.13:1) on **Paid Green Mist**: confirmed, paid,
  boarded.
- **Ochre** (`warning`, 5.93:1) on **Ochre Mist**: awaiting payment, needs
  attention, nothing has gone wrong yet. Amber is never used as text; it
  fails on white.
- **SOS Red** (`danger`, 6.54:1) on **SOS Red Mist**: cancelled, failed,
  flagged, the SOS. Darker and more muted than Pin Red, so danger and route
  never read alike.
- **Terminal Blue** (`info`, 5.75:1) on **Terminal Blue Mist**:
  informational, neither good nor bad (AT TERMINAL, queued to send).

### Neutral
- **Morning Paper** (`surface`): every scaffold background, and the muted
  chip's fill.
- **White Card** (`surfaceRaised`): cards, app bar, navigation bar, sheets,
  dialogs, input fills.
- **Night Text** (`textPrimary`, 17.06:1): all primary text; the snackbar's
  fill.
- **Slate Note** (`textMuted`, 6.73:1): secondary text, labels, unselected
  navigation, muted chips. Muted is still AA.
- **Control Edge** (`border`, 3.64:1 on white, 3.41:1 on Morning Paper):
  the outline of anything a user must find in order to operate it: input
  outlines, outlined buttons, the journey rail.
- **Hairline** (`divider`): decorative separation only: dividers, card
  outlines, the sheet's drag handle.

### Named Rules

**The One Meaning for Red Rule.** Pin Red marks route geometry and is never
a button fill. On an action, red means stop or danger, and that is SOS Red.
A red Book beside a red Cancel beside a red SOS would make all three look
equally alarming.

**The Pair Rule.** A status colour is chosen as a `StatusTone`, which hands
over its text colour and container together, both verified. Never pick a
foreground on its own, and never let hue alone carry the status: the label
or an icon goes with it.

**The Edge Rule.** If a user must locate it to operate it, its boundary is
Control Edge (3:1 or more). Hairline is for decoration, where nothing needs
to be found.

## Typography

**Display Font:** Roboto (bundled; no fallback is ever reached)
**Body Font:** Roboto
**Label/Mono Font:** Roboto, with tabular figures for money

**Character:** One family, and the hierarchy comes from weight, size and
tracking. Headlines are bold and slightly tightened; body text is regular
and generous in line height; micro-labels are small bold capitals with the
tracking opened up.

### Hierarchy
- **Headline Large** (700, 28 px, 1.25, −0.5 px): the largest step, kept
  for a screen's single heading and used sparingly.
- **Headline Medium** (700, 22 px, 1.3, −0.3 px): screen headings such as
  sign-in, and the headline figure on the trip details sheet.
- **App Bar Title** (700, 20 px, −0.2 px): left-aligned on the gutter.
- **Title Large** (600, 18 px, 1.35): sheet titles, empty-state titles.
- **Title Medium** (600, 16 px, 1.4): section headers, status band titles.
- **Body Large** (400, 16 px, 1.5): primary reading text; info-row values
  and journey stop names at 600.
- **Body Medium** (400, 14 px, 1.5): standard body, status band body.
- **Body Small** (400, 13 px, 1.45, Slate Note): notes under a value, sheet
  subtitles.
- **Label Button** (600, 16 px): filled and outlined buttons (text buttons
  15 px).
- **Label Small** (700, 11 px, 1.3, +0.8 px, UPPERCASE): status chips and
  micro-labels such as BOARDING and AT TERMINAL.

Only 400, 500 and 700 are bundled. The 600 weights above have no face of
their own; the engine substitutes the nearest bundled one.

### Named Rules

**The Tabular Money Rule.** Every peso amount goes through `Money`, with
tabular figures, so a fare that changes never makes its column jump. Lists
that are scanned show whole pesos (₱1,180); receipts show centavos
(₱1,180.00).

**The Uncapped Rule.** No text size is capped and no single-line height is
hardcoded. Text must survive 200 % system scaling (WCAG 1.4.4), which is
why headline sizes stay restrained.

**The Carried Type Rule.** The family is bundled, never fetched and never
borrowed from the phone. The app is used in connectivity dead zones, and a
font that arrives over the network is missing exactly when it matters.

## Layout

A single phone column on a 4-point scale (4, 8, 12, 16, 20, 24, 32, 40).
One side gutter, 16 px, on every screen; titles, list tiles and content all
start on it. App bar titles sit left, never centred.

- **Navigation:** a bottom Material `NavigationBar`, 68 px, labels always
  shown. Inner tab bars (booking history, the Dispatcher's passenger list)
  sit under the app bar.
- **Actions:** primary and outlined buttons fill the width and stand 52 px
  tall, placed where a thumb reaches. Nothing tappable is under 48 × 48 px,
  including icon buttons that look smaller.
- **Rows:** an info row splits 4 : 6, the label left in Slate Note and the
  value right-aligned in 600. List tiles use the gutter with 12 px vertical
  padding.
- **Sheets:** bottom sheets rise to at most 90 % of the screen, move up
  with the keyboard and keep to the safe area.
- **Empty states:** centred, 40 px side padding, icon (48 px, Slate Note),
  title, one sentence, then an optional action. Still scrollable, so pull
  to refresh works.
- **Motion:** short and consistent: 100 ms (instant), 180 ms (quick),
  240 ms (normal). Material's ink sparkle on press. Anything that animates
  honours the phone's reduce-motion setting
  (`MediaQuery.disableAnimations`). Long transitions read as lag when a
  queue is waiting.

## Elevation & Depth

Flat by default. The theme sets zero elevation everywhere, the app bar does
not lift when content scrolls under it, and the standard card is separated
by a Hairline outline, not a shadow. Soft ambient shadows are allowed on
raised cards: grouped settings, a profile summary, a saved destination, a
bottom action bar. Depth there is a whisper, never a drop.

### Shadow Vocabulary
- **Raised card** (`0 5px 15px rgba(0,0,0,0.04)`): a summary card that
  heads a screen (profile).
- **Raised group** (`0 4px 10px rgba(0,0,0,0.02)`): a group of settings
  rows; a single row uses `0 4px 8px rgba(0,0,0,0.02)`.
- **Bottom bar lift** (`0 -5px 10px rgba(0,0,0,0.05)`): a fixed action bar
  at the foot of a form, lifted off the content scrolling under it.
- **Map marker** (`0 0 3–8px rgba(0,0,0,0.12–0.38)`): the van and stop
  markers over map tiles, which need to stand off busy streets.

### Named Rules

**The Whisper Shadow Rule.** A card shadow is black at 5 % or less, 8 to
15 px blur, 4 to 5 px offset. No hard, coloured or stacked shadows. Map
markers are the only stronger ones.

**The Border or Shadow Rule.** A card has a Hairline outline (outlined card)
or a soft shadow (raised card), not both.

## Shapes

Gently rounded throughout, with the radius growing with the size of the
surface.

- **12 px:** buttons, input fields, status bands, the snackbar.
- **16 px:** cards and dialogs.
- **20 px:** the top corners of bottom sheets, and a screen-heading raised
  card.
- **Pill (999 px):** status chips, filter chips, the navigation indicator,
  avatars.
- **8 px:** small inner elements.
- **Journey geometry:** the boarding point is a hollow Pin Red ring (13 px,
  2.5 px stroke); the alighting point is a filled Pin Red square with 3 px
  corners; the rail between them is a 2 px Control Edge line. A ring for
  "you start here", a solid mark for "you stop here", the same as the
  logo's pin.
- **Drag handle:** 36 × 4 px Hairline bar, 2 px radius.

## Components

### Buttons
Calm and exact: one ink slab per decision, no ornament.
- **Shape:** gently rounded (12 px).
- **Primary (filled):** Owl Ink with white 16 px / 600 label, full width,
  52 px tall.
- **Outlined:** Owl Ink label, 1 px Control Edge outline, same size. The
  second choice beside a primary.
- **Text:** Owl Ink, 15 px / 600, at least 48 × 48 px.
- **Press / focus:** ink sparkle on press; focus is a 2 px Owl Ink outline,
  a change in weight as well as hue.
- **Verdict buttons:** after a scan, the Dispatcher's "Next passenger"
  button takes the verdict's colour: Paid Green when accepted, SOS Red when
  refused. Never Pin Red.

### Chips
- **Status chip:** pill, tone container fill, tone text in Label Small
  capitals, optional 13 px icon. Announced to screen readers as "status:
  label".
- **Tones:** success (Paid Green), info (Terminal Blue), warning (Ochre),
  danger (SOS Red), brand (Ink on Ink Mist, a neutral default such as
  SCHEDULED), muted (Slate Note on Morning Paper, so a finished trip
  recedes).
- **Filter chips:** Ink Mist fill, Owl Ink 12 px / 600 label, no outline,
  pill.

### Status Band
The full-width statement of a state, for example the status on a boarding
pass or the verdict after a scan. A tone container fill, a 1 px outline in
the tone's colour at 30 % opacity, 12 px radius, 16 px padding. A 22 px
icon on the left, a Title Medium headline in the tone's colour, then a
Body Medium sentence. It can be marked as a live region, so a screen reader
announces a change.

### Cards / Containers
- **Outlined card (default, `AppCard`):** White Card, 16 px radius, 1 px
  Hairline outline, 16 px padding, no shadow. When tappable, the ink
  ripple is clipped to the radius.
- **Raised card:** White Card, 16 px radius (20 px when it heads the
  screen), 20 px padding, a whisper shadow, no outline.
- **Bottom sheet (`AppSheet`):** White Card, 20 px top corners, drag
  handle, a Title Large header with an optional Body Small subtitle, and a
  Close icon button on the right.
- **Dialog:** White Card, 16 px radius, no surface tint.

### Inputs / Fields
- **Style:** filled White Card, 1 px Control Edge outline, 12 px radius,
  16 px padding. The label is in Slate Note.
- **Focus:** the outline goes to 2 px Owl Ink.
- **Error:** SOS Red outline (2 px when focused), and a 13 px / 500 SOS Red
  message that says what to do.
- **Picker row (`AppPickerRow`):** a tappable row that shows the current
  answer, or a placeholder until one is chosen, and is announced as "label:
  value" or "label: not chosen".

### Navigation
- **App bar:** White Card, no elevation, Night Text, left-aligned 20 px /
  700 title on the gutter.
- **Bottom navigation bar:** White Card, 68 px, labels always shown. The
  selected item is shown three ways at once: an Ink Mist pill behind the
  icon, the icon filled, and the label in Owl Ink at 700 (unselected: Slate
  Note at 500).
- **Tab bar:** Owl Ink label and indicator under the label, Slate Note
  unselected, Hairline divider.
- **Snackbar:** floating, Night Text fill, white 14 px text, 12 px radius.

### Journey Strip (signature)
The passenger's journey as two stops on a rail: the boarding ring, a 2 px
Control Edge rail 24 px tall, the alighting square, each with the stop name
in Body Large 600 and an optional Body Small note. Read aloud as "From X.
To Y." This is where Pin Red lives, and the live map's markers echo it.

### Money (signature)
Tabular figures, ₱ prefix, whole pesos in lists and centavos on receipts.
Right-aligned money columns stay columns.

### Empty State
Icon, Title Large headline, one Slate Note sentence, optional action, all
centred. The sentence says what to do next.

### Brand Logo
The owl mark from `assets/branding/sabaygo_logo.png` at three sizes: 120 px
(welcome), 72 px (screen header), 36 px (in a bar). Raster, scaled with high
filter quality; never recoloured.

### QR Scanner
The camera view sits on black with a 50 % black overlay around the frame.
That is the camera's own convention and the only black surface in the app.

## Do's and Don'ts

### Do:
- **Do** take every colour from `AppColors` or the theme, and every status
  colour through `StatusTone`.
- **Do** state a status in words (Label Small capitals) or with an icon,
  never by colour alone.
- **Do** make the primary action an Owl Ink slab, full width, 52 px tall,
  within thumb reach.
- **Do** keep every tappable target at 48 × 48 px or more.
- **Do** outline every control a user must find in Control Edge (3:1 or
  more).
- **Do** route every peso amount through `Money` (tabular figures).
- **Do** start titles and content on the 16 px gutter, titles left-aligned.
- **Do** keep motion at 100 / 180 / 240 ms and honour reduce motion.

### Don't:
- **Don't** fill a button with Pin Red, or use Pin Red for anything other
  than route geometry.
- **Don't** bring back the retired purple (`#2D2059`) or a coloured app bar.
- **Don't** write raw `Colors.*` or `Color(0x…)` in a screen. About 40 such
  uses remain in the profile, messages and notification screens; they are
  drift, not precedent.
- **Don't** use amber or yellow as text; it fails on white. Use Ochre.
- **Don't** use gradients.
- **Don't** give a card both an outline and a shadow, or a shadow heavier
  than 5 % black.
- **Don't** centre an app bar title or hide navigation labels.
- **Don't** fetch a font at runtime or cap text size.
