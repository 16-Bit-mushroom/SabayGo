# Flutter Phase 1 — Issues Encountered and Fixes

*Development log, 10 September 2026.*
*Environment: CachyOS (Arch), fish shell, Flutter 3.47.2, Redmi Note 9 Pro on LineageOS (Android 15), physical device over USB then wireless ADB.*

Recorded as encountered. Roughly two thirds of the time in this phase went
to environment and connectivity rather than to writing Dart, which is
worth knowing before estimating the next one.

---

## 1. Environment and toolchain

### 1.1 Flutter not installed after OS change

**Symptom.** `fish: Unknown command: flutter`

**Cause.** The machine had been reinstalled from Debian 13 to CachyOS.
The Flutter SDK lived outside the repository and was not restored.

**Attempted.** `sudo pacman -S flutter` → `target not found`.
`pacman -Ss flutter` returned only `fvm` (a version manager, which needs
Flutter first) and `flutter-engine` (a dependency, not the SDK).

**Fix.** Installed from source outside the package manager:

```fish
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
fish_add_path ~/flutter/bin
```

**Why this route.** Flutter self-updates through `flutter upgrade`, so
having pacman manage it adds friction without benefit. Installing under
`$HOME` also avoids the root-owned `/opt` permission problems the AUR
package creates.

---

### 1.2 First `flutter --version` appeared to hang

**Symptom.** Output stopped after `Got dependencies.` for several minutes.

**Diagnosis.** `top` showed `git` at 286% CPU — the tool was building
itself, not stuck.

**Resolution.** Waited. First run compiles the Flutter tool and resolves
its own dependency tree; on a dual-core i3-7130U this takes minutes.

**Lesson.** Check whether a process is consuming CPU before assuming a
hang. Repeated across this phase: Gradle's first build looked identical.

---

### 1.3 Android SDK missing

**Symptom.** `flutter doctor` → `Unable to locate Android SDK`

**Fix.** Command-line tools only, no Android Studio:

```fish
sudo pacman -S --needed jdk17-openjdk
paru -S android-sdk-cmdline-tools-latest android-sdk-build-tools
flutter config --android-sdk /opt/android-sdk
```

**Note.** `android-platform-tools` does not exist in the AUR; the already
installed `android-tools` provides `adb` and `fastboot`.

Android Studio was avoided deliberately — roughly a gigabyte plus an IDE
that would be unusable on this hardware, for a component we only need the
build tools from.

---

### 1.4 Duplicate `adb` binaries

**Symptom.** `flutter doctor` warned of two adb binaries, at
`/opt/android-sdk/platform-tools/adb` and `/usr/bin/adb`.

**Why it matters.** Flutter and the SDK can end up talking to different
adb servers, so a device visible to one is invisible to the other.

**Fix.** Removed the standalone package, kept the SDK's copy:

```fish
sudo pacman -Rdd android-tools
fish_add_path /opt/android-sdk/platform-tools
```

---

### 1.5 `flutter doctor --android-licences` did nothing

**Symptom.**

```
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated.
Warning: The --licenses option is no longer needed.
```

The command exited without prompting or writing anything, and
`flutter doctor` continued reporting `Android license status unknown`.

**Consequence.** Surfaced later as a build failure (§2.1). The newer
Android CLI claims licences are unnecessary; Gradle still checks for the
hash files the old tool wrote.

---

## 2. Build

### 2.1 Gradle: NDK licence not accepted

**Symptom.**

```
com.android.builder.sdk.LicenceNotAcceptedException: Failed to install the
following Android SDK packages as some licences have not been accepted.
   ndk;28.2.13676358
```

**Attempted.** `android sdk install "ndk;28.2.13676358"` downloaded 2.1 GB
successfully but then threw `java.nio.file.AccessDeniedException` while
writing `package.xml` — the NDK itself installed, only the metadata write
failed.

**Fix.** Wrote the licence acceptance files directly:

```fish
mkdir -p /opt/android-sdk/licenses
printf '\n24333f8a63b6825ea9c5514f83c2829b004d1fee' \
  > /opt/android-sdk/licenses/android-sdk-license
printf '\n84831b9409646a918e30573bab4c9c91346d8abd' \
  > /opt/android-sdk/licenses/android-sdk-preview-license
printf '\n79120722343a6f314e0719f863036c702b0e6b2a\n84831b9409646a918e30573bab4c9c91346d8abd' \
  > /opt/android-sdk/licenses/android-sdk-arm-dbt-license
```

**What these are.** The hashes are exactly what `sdkmanager --licenses`
writes when the prompt is answered. The file contents *are* the
acceptance record. Standard practice for CI machines where no one can
answer an interactive prompt. The terms accepted are Google's ordinary
Android SDK terms.

**Time cost.** Roughly 20 minutes, including a 688 MB NDK download.

---

### 2.2 Gradle first build looked frozen

**Symptom.** `Running Gradle task 'assembleDebug'...` for over four
minutes with no output.

**Resolution.** Normal. First build downloads dependencies and compiles
from scratch; later builds are much faster and hot reload is near
instant.

---

## 3. Device connection

### 3.1 Device visible to adb, invisible to Flutter

**Symptom.** `adb devices` listed `14957de1 device`, while
`flutter devices` showed only Linux desktop and Chrome.

**Fix.** `flutter devices --device-timeout 30`

**Cause.** Flutter's default device-discovery window is short, and on a
slow machine the query returns before the Android device responds.

---

### 3.2 Device dropped between commands

**Symptom.** `No supported devices found with name or id matching
'14957de1'` after a successful run minutes earlier.

**Cause.** USB mode reverts to charging-only on reconnect, and the cable
was being moved.

**Fix.** Wireless ADB, which removed the dependency on the cable
entirely:

```fish
adb tcpip 5555
adb connect 192.168.1.2:5555
```

LineageOS also exposes **Wireless debugging** with a pairing code in
developer options, which survives reboots better than the tcpip method.

---

### 3.3 Shell confusion

**Symptom.** `bash: flutter: command not found`, and
`bash: syntax error near unexpected token '('`.

**Cause.** Dropping into bash without noticing. `fish_add_path` only
affects fish, and `set VAR (command)` is fish-only syntax.

**Tell.** The prompt changes from `❯` to `[user@host dir]$`.

**Fix.** `exec fish`, or wrap bash-only constructs: `bash -c '...'`.

Recurred several times across the session, including heredocs
(`<< 'EOF'`), which fish does not support at all.

---

## 4. Code

### 4.1 `characters` getter undefined

**Symptom.**

```
error • The getter 'characters' isn't defined for the type 'String'
      • lib/data/repositories/auth_repository.dart:72
```

**Cause.** `String.characters` comes from the `characters` package, which
is a transitive dependency and not imported.

**Fix.** Used `email.substring(0, 1).toUpperCase()` instead. Grapheme
clustering is unnecessary for a single initial from an email address.

---

### 4.2 Archived screens still referenced

**Symptom.**

```
error • Target of URI doesn't exist:
        'package:mobile_v2_uv_express/views/dispatcher/dispatcher_main_screen.dart'
```

**Cause.** Ten dispatcher screens were archived when the cooperative
admin work moved to the web console, but `auth_screen.dart` and
`signup_screen.dart` still imported the old shell.

**Fix.** `auth_screen.dart` was superseded by the new `login_screen.dart`
and was archived. `signup_screen.dart` was rewritten (§5.2).

---

### 4.3 Stale file overwritten by an older version

**Symptom.**

```
error • Target of URI doesn't exist: 'conductor_home_screen.dart'
error • Undefined name 'UserRole'
```

...referring to code that had supposedly been replaced.

**Cause.** A regenerated file silently failed to overwrite an earlier
version, so the older content remained on disk while both parties assumed
it had been replaced.

**Fix.** Verified file contents before assuming a write succeeded.

**Lesson.** After replacing a file, `git diff` before running anything.
This class of problem recurred throughout the project — the same pattern
reverted a `DATETIME(fsp=6)` fix in the backend four separate times.

---

### 4.4 `TripManifestScreen` requires a trip argument

**Symptom.**

```
error • The named parameter 'trip' is required, but there's no
        corresponding argument
```

**Cause.** The screen was built to receive a specific trip, but the new
conductor shell listed it as a tab with nothing selected.

**Fix.** Added `ConductorTripsScreen` — the trips this crew member is
rostered to — with the manifest opening from a selection.

**Why this is better than making `trip` nullable.** A conductor is
already restricted server-side to their assigned trips, so the list is
also the boundary of what they can act on. The structure now matches the
permission model rather than working around it.

---

### 4.5 `withOpacity` deprecated

**Symptom.** Around fifteen warnings across the existing screens.

**Fix.**

```fish
grep -rl "withOpacity" lib/ | xargs sed -i \
  's/\.withOpacity(\([^)]*\))/.withValues(alpha: \1)/g'
```

Cosmetic, but cheap to clear in bulk and it keeps real warnings visible.

---

### 4.6 Comment swallowed a widget property

Found in the original `dispatcher_main_screen.dart`:

```dart
: null, // Hides the button on all other tabs      floatingActionButtonLocation: ...
```

`floatingActionButtonLocation` was inside the comment and had never taken
effect. No error, no warning — the property simply did not exist as far
as the compiler was concerned.

---

## 5. Design issues found during the rewrite

### 5.1 Role routing by email prefix

**Found.** The previous build chose the portal from the email address —
anything beginning `admin@` or `dispatcher@` opened the crew app.

**Why it matters.** A passenger could register such an address and reach
the crew interface. The backend would still refuse the actual requests,
but the client should not have offered the route.

**Fix.** Routing now reads the role the server returns on login.

---

### 5.2 Signup offered a crew-portal checkbox

**Found.** An "I'm a van terminal" checkbox routed new registrations to
the dispatcher portal.

**Why it matters.** `/auth/register` creates passengers only; conductors,
drivers and cooperative administrators are provisioned by the office
because employment is a cooperative decision. The control implied
otherwise.

**Fix.** Removed. Also added the fields the endpoint actually requires —
first name, last name, and a Philippine mobile number — which the old
form never collected.

---

### 5.3 Cooperative name hardcoded

**Found.** The crew app header read `RDT Transport` as a literal.

**Fix.** Reads from the signed-in profile, so one build serves any
cooperative.

---

## 6. Networking — the largest single cost

Roughly an hour, and the failure gave almost no useful signal.

### 6.1 Symptom

Login timed out after exactly ten seconds. **Nothing appeared in the
uvicorn log at all** — the request never reached the server.

```
E/flutter: Unhandled Exception: TimeoutException after 0:00:10.000000
  #1  ApiClient._send (api_client.dart:72)
  #2  AuthRepository.login (auth_repository.dart:88)
```

### 6.2 Elimination, in order

| Check | Result |
|---|---|
| `curl 192.168.1.8:8000/health` from the dev machine | ok — but proves little, since the address resolves locally |
| `ss -tlnp \| grep 8000` | `0.0.0.0:8000` — correctly bound to all interfaces |
| `adb shell ip addr show wlan0` | `192.168.1.2/24` — same subnet |
| `adb shell ping -c 2 192.168.1.8` | 0% loss — ICMP passes |
| `adb shell nc -w 3 192.168.1.8 8000` | **Timeout** — TCP does not |

ICMP passing while TCP failed was the decisive signal: the network path
exists, so something is filtering by port.

### 6.3 Cause

`ufw` active with `policy DROP` on INPUT and an empty `ufw-user-input`
chain. ICMP is explicitly permitted by ufw's default rules, which is why
ping succeeded and made the network appear healthy.

`sudo firewall-cmd --state` returned "command not found", which briefly
suggested no firewall was running. The correct check was
`sudo iptables -L INPUT -n`, which showed `policy DROP` immediately.

### 6.4 Fix

```fish
sudo ufw allow from 192.168.1.0/24 to any port 8000 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 5000 proto tcp
sudo ufw reload
```

Scoped to the LAN subnet rather than opened globally: the port serves an
unauthenticated health endpoint and a login endpoint, and has no reason
to be reachable beyond the local network. Port 5000 added at the same
time for the YOLOv8 node.

### 6.5 Prerequisites that were correct, but are easy to miss

Verified during elimination and worth listing, because any one of them
produces the same silent timeout:

- `uvicorn --host 0.0.0.0` — binding to `127.0.0.1` is invisible to a
  local `curl` on the LAN address
- `android:usesCleartextTraffic="true"` in the manifest — Android 9+
  blocks plaintext by default and fails before the packet leaves the
  device
- `networkSecurityConfig` listing the development host
- `INTERNET` permission
- Both devices on the same subnet, not a guest network or mobile data

---

## 7. Post-login: screen did not dismiss

**Symptom.** `POST /auth/login → 200` and `GET /auth/me → 200` in the
server log, but the app stayed on the sign-in screen.

**Cause.** The root router sits at `MaterialApp.home` and *had* rebuilt
to the conductor shell. But `LoginScreen` had been pushed on top of it
with `Navigator.push`, so it kept covering the router underneath.

**Fix.**

```dart
if (ok && mounted) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}
```

Clearing the stack rather than pushing another route also removes the
back gesture that would otherwise return to a stale sign-in form.

---

## 8. Time distribution

| Area | Share |
|---|---|
| Toolchain install (Flutter, SDK, licences) | ~35% |
| Networking diagnosis (ufw) | ~25% |
| Device connection | ~10% |
| Dart compile errors | ~15% |
| Writing new code | ~15% |

The estimate for this phase assumed the reverse.

---

## 9. Carried forward

**Verify a file changed before running it.** Two separate incidents came
from assuming a write succeeded. `git diff` costs a second.

**ICMP is not connectivity.** Ping proves a route exists, nothing more.
Test the actual port.

**A silent timeout means the request never arrived.** An empty server log
is itself the diagnostic — it eliminates every server-side cause at once.

**Know which shell you are in.** Several failures were bash-versus-fish
syntax, and the prompt says which.

**Record the working environment.** Flutter 3.47.2, Android SDK 37.0.0,
NDK 28.2.13676358, JDK 17, Gradle plugin 8.11.1, Kotlin 2.2.20. Arch is a
rolling release; a future update can move any of these.

---

## 10. Still outstanding

- **`TimeoutException` name collision.** `dart:async` exports a class of
  the same name as the one declared in `api_exception.dart`, so the
  `on TimeoutException` catch in `ApiClient` matches the wrong type and
  the error reaches the UI unhandled. Rename the local class.
- AGP 8.11.1 and Kotlin 2.2.20 are below the versions Flutter will soon
  require. Deferred deliberately — upgrading Gradle mid-project is a good
  way to lose a day.
- The dev-account chips on the sign-in screen are guarded by
  `AppConfig.isDebug`. Confirm they are absent from a release build
  before any public demonstration.
