# UI redesign — state and next steps

Started 28 September 2026. The goal, in the user's words: friendlier
terminology, navigation that does not confuse, tasks completed without
error, WCAG compliance, and a look that is **clean, minimalist, yet premium
and luxurious**.

---

## Decisions

| Decision | Chosen |
|---|---|
| Palette | **Keep the deep purple brand**, darken only what failed AA |
| Where colour goes | Chrome is the page surface; purple is spent on the primary action, the journey rail and the welcome screen — not on every app bar |
| Typeface | **Roboto, bundled** in `assets/fonts` and named on every themed style |
| Order | Design system → demo path → the rest |
| Crew chrome | Conductor screens keep the purple app bar: they carry white-on-purple content and the role signal is useful at a van door |

## What "premium" turned out to mean here

Nothing that costs a frame to render. No gradients, no drop shadows, no
tinted fills behind text. The four things doing the work:

1. **Restraint with colour.** One accent, spent where a decision is made.
2. **One vertical rhythm.** `AppSpacing` everywhere, one gutter, one radius.
3. **Hierarchy by weight and position**, not by boxes. Most bordered
   containers in the app were removed, not restyled.
4. **Type that is the same on every device**, which is why Roboto is now
   carried rather than borrowed from the host.

---

## Done

### Phase 1–2 (`60046ae`, `1950c3b`) — tokens and the demo path

`lib/core/design/` owns colour, spacing, radius, sizing and motion. Five
colours failed WCAG 2.1 AA and every one of them carried status:

| token | was | now |
|---|---|---|
| `accent` (boarding, paid) | 3.11:1 | `success` 6.13:1 |
| `warning` (unpaid, variance) | **1.97:1** | 5.93:1 |
| `Colors.blue` (AT TERMINAL) | 3.12:1 | `info` 5.75:1 |
| `Colors.deepOrange` (ROADSIDE) | 3.16:1 | tokenised |
| `Colors.teal` (TERMINAL CASH) | 3.67:1 | tokenised |

Input borders were #DDDDE5 at **1.35:1** against WCAG 1.4.11's 3:1 for a
control boundary; a white field on the #F7F7FA scaffold is 1.07:1, so
nothing delimited the field at all. Now 3.64:1.

### Phase 3 (`c75f59a`, and the two commits after it) — composition

**Shell.** Five bare icons in a top `TabBar` → a labelled bottom
`NavigationBar`. The icons were unlabelled (a screen reader announced "Tab 3
of 5", failing WCAG 4.1.2), sat at the far end of the thumb's reach, and
said "tabs" where these are five destinations. `IndexedStack` replaced
`TabBarView`, so a search survives a look at a ticket.

**Chrome.** App bars are the page surface with a left-aligned dark title.

**Search.** Two `DropdownButtonFormField`s sharing a phone's width gave each
~140 logical pixels, so the journey was picked from two lists of truncated
terminal names. Now full-width stacked rows sharing a rail, swap control on
the line between them, and a searchable terminal sheet that shows each
terminal's city.

**Results, boarding pass, my trips, reserve sheet.** Recomposed — see the
commit messages, which carry the reasoning per screen.

**New shared components** in `core/design/components/`, each replacing
between three and eleven hand-drawn copies: `AppCard`, `AppPickerRow`,
`AppSectionHeader`, `AppInfoRow`, `AppSheet`, `JourneyStrip` /
`JourneyMarker`, `StatusBand`, `Money`. `core/util/when.dart` replaced
twenty-three date format strings (the pass said `05:30 AM`, the results list
`5:30 AM`).

### Proof

`test/layout_test.dart` lays every recomposed screen out at **320dp and
390dp, at 100% and 200% text**, and fails on any overflow. Flutter reports
an overflow as an exception during layout, so this catches the class of
defect that shipped a blank purple welcome screen and that `flutter analyze`
cannot see. It found two real ones: the trip card overflowed by 28px at
200%, and the same bug was latent in the bookings list.

The harness registers the app's own bundled Roboto, so strings are measured
at the width a passenger actually gets rather than in Ahem.

`test/widget_test.dart` was deleted: the untouched Flutter counter template,
asserting on an app that never existed, red since the project started.

---

## Not done

**Passenger screens still in the old composition.** Raw colour counts are a
decent proxy for how much of each is untouched:

| screen | raw colours |
|---|---|
| `profile/profile_screen.dart` | 35 |
| `tracking/live_map_screen.dart` | 29 |
| `notifications/notifications_screen.dart` | 26 |
| `profile/edit_profile_screen.dart` | 24 |
| `profile/manage_destinations_screen.dart` | 18 |
| `messages/*` | 19 |
| `auth/signup_screen.dart` | 16 |
| `reservations/reschedule_sheet.dart` | — uses the old sheet pattern |

**Conductor screens (Phase 4).** Untouched, and they cannot be reviewed in a
browser: `mobile_scanner` needs a camera and the walk-in queue needs
`sqflite`, which has no web implementation. Their app bar is pinned purple so
the light-chrome change did not turn their white-on-purple headers invisible.

**`AppColors.accent`** — twelve files still import the deprecated alias.

**"Seat" in the data layer.** `UvTripModel.availableSeats` / `totalSeats` and
the API's `seats_available` still say seat internally. Nothing a passenger
reads says it any more. Renaming is a migration, not a UI pass.

---

## Running it

```fish
# backend must be up for anything past the welcome screen
cd backend; and source venv/bin/activate.fish
uvicorn app.main:app --host 0.0.0.0 --port 8000

# the app in a browser -- port 3000, because adminer holds 8080 and
# cors_origins allows only 8080 and 3000
cd mobile
set -x CHROME_EXECUTABLE /usr/bin/chromium
flutter run -d chrome --web-port=3000 \
  --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# layout, without a device or a backend
flutter test
```

Web caches hard — **Ctrl+Shift+R** after a rebuild, or the old bundle keeps
serving and it looks like nothing changed.
