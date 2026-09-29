# UI redesign — state and next steps

Started 28 September 2026. The goal, in the user's words: friendlier
terminology, navigation that does not confuse, tasks completed without
error, WCAG compliance, and a look that is **clean, minimalist, yet premium
and luxurious**.

---

## Decisions already made

| Decision | Chosen |
|---|---|
| Palette | **Keep the deep purple brand**, darken only what failed AA. Not a new palette — it would invalidate every screenshot already in the manuscript |
| Order | Design system first, then the DEMO_SCRIPT.md path, then the rest |
| Typeface | Bundled **Roboto**. `google_fonts` fetches at first run and this app works in dead zones by design |

## Done (commits `60046ae`, `1950c3b`)

**Phase 1 — the token layer.** `lib/core/design/` now owns colour, spacing,
radius, sizing and motion; it used to live in `core/config/app_config.dart`
beside the API base URL, so 18 screens imported the API host to read a
colour.

Five colours failed WCAG 2.1 AA and every one of them carried status:

| token | was | now |
|---|---|---|
| `accent` (boarding, paid) | 3.11:1 | `success` 6.13:1 |
| `warning` (unpaid, variance) | **1.97:1** | 5.93:1 |
| `Colors.blue` (AT TERMINAL) | 3.12:1 | `info` 5.75:1 |
| `Colors.deepOrange` (ROADSIDE) | 3.16:1 | tokenised |
| `Colors.teal` (TERMINAL CASH) | 3.67:1 | tokenised |

Also the input border: #DDDDE5 at **1.35:1**, against WCAG 1.4.11's 3:1 for
a control boundary — and a white filled field on the #F7F7FA scaffold is
1.07:1, so nothing delimited the field at all. Now 3.64:1.

`StatusChip` takes a **tone, not a colour**, so a failing pair cannot be
built at a call site. `AppEmptyState` promoted out of `home_screen`.

**Phase 2 — the demo path, steps 1–6.** Welcome, sign-in, home search, trip
card, reserve sheet, boarding pass. Unverified colours on that path: 0.
Wording corrected — the boarding pass told passengers to show the ticket to
the "dispatcher" (the conductor scans it); the reserve sheet said "RESERVE
SEAT", "seats left" and drew a seat icon, though UV Express assigns no seat
numbers and `seat_number` is an internal slot counter nobody is shown.

## The gap — what tomorrow is for

**Only the welcome screen was actually recomposed.** Everything else got
new colour and new words inside the old layout, which is why it does not
read as a redesign. The remaining work is composition, and that is where
"premium" lives:

1. **Home / results** — hierarchy and density. The results list is a flat
   stack of equal-weight cards; nothing guides the eye to departure time,
   fare or scarcity in that order.
2. **Trip card** — partially recomposed already, but the row still competes
   with itself for attention.
3. **Boarding pass** — 512 lines of inline styling, a hand-drawn
   perforation, and a status header that does not use the type scale. The
   most-shown screen in the demo.
4. **Passenger shell** — the tab bar and app bars are untouched.
5. **Spacing rhythm** — `AppSpacing` exists and is barely used outside the
   files already migrated. 108 unverified colours remain in `lib/views`,
   worst: notifications (20), profile (16), reservations (12).

Constraints that do not move: terminology in CLAUDE.md (space not seat,
never "operator"), Roboto, the purple brand, and AA on every pair.

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
```

Web caches hard — **Ctrl+Shift+R** after a rebuild, or the old bundle keeps
serving and it looks like nothing changed.

Conductor screens do not run on web: `mobile_scanner` needs a camera and
the walk-in queue needs `sqflite`, which has no web implementation. Reads
degrade to empty; `enqueue` throws rather than silently dropping a cash
walk-in.
