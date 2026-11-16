# UI/UX and Flutter stack recommendations

10 Nov. From screenshots of every console page and the main app screens
(headless browser and the Pixel 6 emulator), and a read of both apps'
code. Both design systems (`DESIGN.md`, `mobile/DESIGN.md`) are kept as
they are; nothing here proposes a new look. What was already fixed is in
`docs/PROGRESS_LOG.md`, "Design polish, both apps".

Effort: XS under an hour, S a morning, M a day or two.

## Do before the alpha and the defence

**1. The invented camera count (S, backend + app).** With no phone
reporting, `GET /trips/{id}/door-check` answers `aboard: 0`, and the
Dispatcher app shows "0 aboard (camera)" and "Fewer aboard than listed:
no-shows. Nothing to do." That is the fabricated zero the project's first
principle forbids, on the Dispatcher's main screen. The console already
gets this right ("aboard not counted (no phone)", `van_board_screen.dart`).
Make `aboard` nullable when no phone has reported for the trip, and have
`DoorCheckPanel` (`mobile/lib/views/dispatcher/dashboard_panels.dart`) say
"Not counted: no phone in the van" instead of a number.

**2. Done 10 Nov: each page has an address.** (Kept for the record.) **The console forgot where you were (S).** `OperatorShell` keeps the
page as an index in widget state (`_hub`, `_tab`), with no URL. A browser
refresh, or the console's own rebuild, lands on Overview; Back leaves the
app; nobody can bookmark Money or send a link to a trip. Office staff
refresh by habit.
- Smaller option, no new package: write the hub and tab to the URL
  fragment (`#/money`, `#/reviews/boarding-audit`) when they change, and
  read it back in `initState`. About 20 lines in `operator_shell.dart`.
  Recommended now.
- Full option, after the pilot: `go_router` with a `ShellRoute` for the
  sidebar, a route per tab and `/trips/:id`, and a `Title` per page so
  several open tabs are told apart.

**3. A layout and accessibility test for the console (S–M).** The console
has one smoke test (`operator_console/test/widget_test.dart`). The app's
`test/layout_test.dart` pumps each screen at 320 and 390 dp and at 200 %
text, and since 10 Nov also checks the WCAG guidelines `flutter_test`
ships with (48 dp targets, a name on every tappable thing, AA text
contrast). Copy that harness to the console at 1280 × 720 (the projector)
and 1024 wide. It costs no dependency and would have caught the five
console buttons that had no screen-reader name.

**4. Keep the colour drift at zero (XS).** The app went from about 100
raw `Colors.*` / `Color(0x…)` uses in screens to none on 10 Nov (the
console had none). A grep in a check script stops it coming back:

```bash
grep -rnE '(^|[^A-Za-z])Colors\.[a-z]|Color\(0x' mobile/lib/views operator_console/lib/modules \
  | grep -vE 'Colors\.(transparent|white|black)\b|Colors\.black(12|26|38)|Colors\.black\.withValues' \
  && { echo "raw colour in a screen: use the tokens"; exit 1; } || true
```

The allowed exceptions are the shadows both DESIGN.md files specify.

**5. The Android toolchain will break before the defence if left (S).**
The APK build warns that Flutter will soon drop Android Gradle Plugin
8.11.1 and Kotlin 2.2.20; move them to AGP 9.0.1+ and Kotlin 2.3.20+ in
`mobile/android/settings.gradle`, on a branch, and rebuild. The build
also failed on this machine with the system Java 21 (no compiler); it
needs `JAVA_HOME` at a full JDK 17 (`~/Android/jdk-17`). `run.sh
--mobile` and `setup.sh` should set or check it, and `docs/SETUP.md`
should name the Flutter version the team builds with (3.47.9 here):
`setup.sh` only checks Dart ≥ 3.12.1.

## After pilot feedback

**6. Try the WebAssembly build (XS to try).** `flutter build web --wasm`
renders faster in Chrome and Edge and falls back to CanvasKit where WasmGC
is missing. Time the Van Status Board and the map on the office PC before
switching; it is one flag in `run.sh`.

**7. Golden tests for the signature pieces (S).** The overflow tests
catch text that does not fit, not a tile that changed colour. A
`matchesGoldenFile` image of the pila strip, the journey strip and the
Money ledger, at one size, catches visual regressions. The app's harness
already loads bundled Roboto, which golden images need.

**8. One flow test per role (M).** The journey scripts test the backend;
no test drives the apps. An `integration_test` for "passenger reserves
and gets a booking code" and "Dispatcher marks a seat Paid", run on the
emulator, covers the two flows the pilot depends on.

**9. Two lint rules (XS).** `flutter_lints` 6 leaves
`prefer_const_constructors` and `prefer_const_literals_to_create_immutables`
off. Turning them on in both `analysis_options.yaml` lets Flutter skip
rebuilding unchanged widgets on every 15-second poll; `dart fix --apply`
does most of the work.

**10. Screen readers on the console, only if needed (XS).** Flutter Web
draws to a canvas, and a screen reader turns the semantics tree on
through Flutter's "Enable accessibility" button. If an A2Z staff member
uses a screen reader, call `SemanticsBinding.instance.ensureSemantics()`
in the console's `main()`. It costs some frame time, so leave it off
otherwise. Keyboard use works either way.

## Deliberately not recommended

- **Switching state management** (Provider to Riverpod or Bloc): no change
  a user would see, and a rewrite of every view model before the defence.
- **One shared token package for both apps:** the two systems differ on
  purpose (the console is green with no blue; the app is ink with
  Terminal Blue for information). Sharing spacing alone is not worth a
  package.
- **A dark theme or a theme toggle:** both DESIGN.md files rule it out.
- **A service worker / PWA:** `run.sh` turns it off on purpose; a cached
  bundle pointed at the old backend cannot be fixed from the demo floor.
- **Animation or UI-kit packages:** the motion rules (100/180/240 ms,
  reduced motion honoured) need none.

## Documents that are out of date

`PRODUCT.md` still describes QR scans and PayMongo, and `mobile/DESIGN.md`
still has a QR Scanner component; rev 721 removed both (cash only,
booking code). Brief rev 721 wins where they disagree.
