# Setting up SabayGo on a new PC

For a teammate joining the project. `README.md` §"Running and testing"
assumes a machine that is already set up — this is the part before that.

**Docker is not enough on its own.** It runs the database and nothing else.
The system is four pieces and only one of them is containerised:

| Piece | How it runs | Needed for the UI work? |
|---|---|---|
| MySQL 8 + Adminer | Docker | **yes** |
| FastAPI backend | Python venv on the host | **yes** |
| Flutter clients | Flutter SDK on the host | **yes** |
| Flask + YOLOv8 AI node | Python venv on the host | no — skip it |

The AI node is the one you can leave out. It pulls in `ultralytics`, which
pulls in PyTorch — a multi-gigabyte install — and nothing in the passenger
or conductor UI needs it running. Set it up only when you touch the audit
path.

---

## The short path

Install the three prerequisites below, then from the project root:

```bash
./setup.sh              # database + backend + Flutter clients
./setup.sh --with-ai    # also the YOLOv8 node (pulls PyTorch, ~6 GB)
```

It is idempotent, so re-running it is safe. It writes the `.env` files,
generates the keys, builds the Python venv, brings up the containers,
applies all 16 migrations, seeds the demo data, resolves the Flutter
packages and runs the layout suite as proof the toolchain is right.

Two things it deliberately does not do: install Docker, Python or Flutter
— those need administrator rights and differ per OS, so it checks for them
and names what is missing — and it never deletes a venv. One that arrived
in a zip from another machine is unusable (console scripts carry an
absolute path in their shebang), so it is moved to `venv.stale-<date>` and
rebuilt, and you delete the old one yourself.

Note that it **drops and rebuilds the database**. Pass `--keep-db` if you
have data you want to keep.

If you are asking Claude Code to do the setup for you, this is the whole
brief: *"Read docs/SETUP.md and run ./setup.sh. Tell me what it asks for."*

---

## Windows 11

Everything in this project is bash and Docker, so the supported path is
**WSL2** — one shell, one filesystem, every script working unchanged. Do
not try to run `db/*.sh` or `setup.sh` from PowerShell or Git Bash:
`db/apply.sh` pipes heredoc SQL through `docker compose exec`, and Git
Bash's path translation mangles it.

### 1. WSL2 and Ubuntu

In **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot, then open Ubuntu from the Start menu and set a UNIX username and
password when it asks. Ubuntu 24.04 ships Python 3.12, which is new enough.

### 2. Docker Desktop

Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/),
then in **Settings → Resources → WSL integration**, switch on your
`Ubuntu-24.04` distro. Without that checkbox the `docker` command does not
exist inside Ubuntu and `setup.sh` stops on its first check.

Leave Docker Desktop running whenever you work on the project.

### 3. Unpack inside the Linux filesystem, not on C:

This matters more than it looks. Everything in the remaining sections runs
from **inside Ubuntu**:

```bash
sudo apt update
sudo apt install -y python3 python3-venv unzip git curl xz-utils zip libglu1-mesa
cd ~
unzip /mnt/c/Users/<your-windows-name>/Downloads/sabaygo-handover.zip -d SabayGo_VS
cd SabayGo_VS
```

Keep the project at `~/SabayGo_VS`, **not** under `/mnt/c/`. Windows drives
are mounted over a network protocol inside WSL: pip and Flutter builds run
several times slower there, and `uvicorn --reload` misses file changes
because inotify does not work across that mount. You will edit files
happily either way — VS Code's WSL extension opens `~/SabayGo_VS` natively,
and `\\wsl$\Ubuntu-24.04\home\<you>\SabayGo_VS` works in Explorer.

### 4. Flutter inside Ubuntu

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter --version        # Dart must be 3.12.1 or newer
```

`flutter doctor` will report the Android toolchain missing. Ignore it — the
web target and the layout suite need neither an Android SDK nor a device.
You only need the SDK for the conductor screens (see below).

Point Flutter at the Chrome you already have on Windows:

```bash
echo 'export CHROME_EXECUTABLE="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"' >> ~/.bashrc
source ~/.bashrc
```

WSL2 forwards localhost in both directions, so Chrome running on Windows
reaches both the Flutter web server and the backend inside Ubuntu with no
extra flags.

### 5. Run the setup

```bash
./setup.sh
```

Then the run commands at the end of its output, same as on Linux.

### Conductor screens need a handset

`mobile_scanner` needs a camera and the offline walk-in queue needs
`sqflite`, neither of which has a web implementation, so those screens
cannot be opened in Chrome at all. For them:

```bash
sudo apt install -y android-sdk-platform-tools    # or: sudo apt install adb
adb connect 192.168.1.2:5555                      # the phone's wireless-adb address
cd mobile
flutter run -d 192.168.1.2:5555 \
  --dart-define=API_BASE_URL=http://<windows-lan-ip>:8000/api/v1
```

Wireless adb works from WSL2 because it is plain TCP. A phone plugged in
over **USB does not** — WSL2 has no USB passthrough. If you would rather
use a cable or the Android emulator, install Flutter on the Windows side as
well and point it at the same source tree over `\\wsl$\`; expect slower
builds. The API base URL must be the Windows machine's LAN IP (`ipconfig`
in PowerShell), not `localhost`, since the phone is a different device.

### Line endings

Do not set `git config core.autocrlf true`. A `.gitattributes` in the repo
pins `*.sh` to LF, but that global setting can still rewrite a script into
CRLF on checkout, and bash then fails with `$'\r': command not found`.

---

## Prerequisites

- **Docker** with Compose v2 (`docker compose`, not `docker-compose`).
- **Python 3.14** — that is what both venvs on the main machine run.
  3.12+ should be fine; `asyncmy` is the one dependency that compiles.
- **Flutter stable** with **Dart 3.13.2** or newer. `mobile/pubspec.yaml`
  requires `sdk: ^3.12.1`, so `flutter --version` must satisfy that.
- **Android SDK + platform-tools** only if you will run on a handset.
  Chrome alone is enough for the operator console and for reviewing most
  passenger screens.
- **Git**, and a `bash` available. The project's shell is fish, but every
  script in `db/` and `backend/scripts/` has a `#!/usr/bin/env bash`
  shebang, so your own shell does not matter.

## Three things are not in the repository or the archive

`.gitignore` excludes all three, and the handover archive leaves them out
too — secrets do not belong in a file that gets uploaded anywhere. You do
not need to chase any of them: `setup.sh` generates the first two and
Ultralytics fetches the third.

1. **`.env` (root)** and **`backend/.env`** — built from the `.env.example`
   files, with `JWT_SECRET`, `AI_NODE_API_KEY` and `PHONE_CAPTURE_API_KEY`
   generated locally. The one value nobody can invent is
   `PAYMONGO_WEBHOOK_SECRET`; ask for it only when you need to test a live
   payment webhook, which the UI work does not.
2. **`ai_service/.env`** — a single line, `AI_NODE_API_KEY=...`, written
   with the same value as `backend/.env`. They must match or the backend
   gets a 401 from the node.
3. **`yolov8n.pt`** — excluded by `*.pt`. Ultralytics downloads it on the
   node's first start, so this one needs no help, just internet.

Never commit any of them. If you generate a key you want the rest of the
team to share, send it over a channel that is not the repository.

---

## Setup, step by step

```bash
git clone https://github.com/16-Bit-mushroom/SabayGo.git SabayGo_VS
cd SabayGo_VS
```

### 1. Environment files

```bash
cp .env.example .env
cp backend/.env.example backend/.env
```

The root `.env` works as copied — it is what `docker-compose.yml`,
`db/apply.sh` and `db/reset-dev.sh` read for the MySQL credentials.

`backend/.env` needs one value filled in. `jwt_secret` is declared
`min_length=32` in [backend/app/config.py:33](backend/app/config.py#L33), so
an empty one fails at startup with a validation error rather than running
insecurely:

```bash
printf 'JWT_SECRET=%s\n' "$(openssl rand -hex 32)" >> backend/.env   # then delete the blank JWT_SECRET= line
```

Everything else in `backend/.env` has a working default. Leave
`SMS_PROVIDER=disabled` — an SOS is still recorded and the office still
notified in-app; each recipient simply gets a dispatch row saying no attempt
was made. Leave `PAYMONGO_SECRET_KEY` empty too; the journey suite expects
the checkout step to be skipped and reports it as a gap, not a failure.

### 2. Backend venv

Do this **before** the database step — `db/reset-dev.sh:18` shells out to
`backend/venv/bin/python` to bcrypt the dev password, so the seed cannot
finish without it. This is the reason a Docker-only setup gets stuck.

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cd ..
```

### 3. Database

```bash
docker compose up -d      # sabaygo-mysql on 127.0.0.1:3307, adminer on :8080
./db/reset-dev.sh         # applies all 16 migrations, seeds, dev trip departs tomorrow 05:30
```

Use `./db/reset-dev.sh --soon` instead when you need the check-in window
open — that trip departs in 20 minutes. Note the trade-off: a `--soon` trip
has already passed the reschedule cutoff, which is the one known journey-test
failure and not a defect.

Both host ports are bound to `127.0.0.1`. If something local already holds
8080, Adminer is the one to move — port 3307 was chosen precisely so MySQL
would not collide with a system `mariadb-server`.

**Migrations are the schema. Never run `create_all()`.**

### 4. Backend

```bash
cd backend
source venv/bin/activate          # or venv/bin/activate.fish
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
curl -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/docs   # expect 200
```

Bind `0.0.0.0`, not `localhost`, or a phone on the same LAN cannot reach it.

### 5. Flutter clients

```bash
cd mobile            && flutter pub get
cd ../operator_console && flutter pub get
```

Run them:

```bash
# passenger / conductor / driver, in a browser — port 3000 because
# cors_origins allows only 3000 and 8080, and adminer holds 8080
cd mobile
flutter run -d chrome --web-port=3000 \
  --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# on a handset over wireless adb — replace both addresses
flutter run -d 192.168.1.2:5555 \
  --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1

# operator console (coop_admin)
cd ../operator_console
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

`192.168.1.8` is the backend machine's LAN IP — find yours with `ip -4 addr`.

Sign in with `passenger@`, `conductor@`, `driver@` or
`coopadmin@sabaygo.dev`, password `sabaygo123`. The sign-in screen shows
dev-account chips in debug builds only.

### 6. Check it works

```bash
cd mobile && flutter test            # layout suite: no backend, no device needed
cd mobile && flutter analyze
cd backend && ./tests/integration/run_all_journeys.sh    # expect 162 passed, 1 failed
```

`flutter test` is the fastest proof the toolchain is correct — it lays every
recomposed screen out at 320dp and 390dp at 100% and 200% text and fails on
any overflow.

---

## Optional: the AI node

Only for work on the YOLOv8 audit path.

```bash
cd ai_service
python3 -m venv venv
./venv/bin/pip install -r requirements.txt      # large: ultralytics pulls PyTorch
printf 'AI_NODE_API_KEY=%s\n' "$(openssl rand -hex 16)" > .env   # same value in backend/.env
set -a; source .env; set +a
./venv/bin/python app.py                        # 0.0.0.0:5000, downloads yolov8n.pt on first run
curl http://127.0.0.1:5000/health
```

Automatic audits need a camera on this host — a laptop webcam is a verified
stand-in. With no camera the trigger writes no row at all and logs an
`UpstreamServiceError`, which is correct: the node never invents a count.

---

## Gotchas that have cost time here

- **An empty server log is the diagnostic.** If a request from the phone
  never appears, it never arrived — check the port, not just ping. `ufw`
  blocked 8000 for an hour on the main machine. ICMP passing proves only
  that a route exists.
- **MySQL stores naive local time (Asia/Manila).** Use
  `app.core.timezone`. `datetime.now(timezone.utc)` written into one of
  those columns skews it eight hours and breaks check-in windows silently.
- **Flutter web caches hard.** Ctrl+Shift+R after a rebuild, or the old
  bundle keeps serving and it looks like your change did nothing.
- **Conductor screens cannot be reviewed in Chrome.** `mobile_scanner`
  needs a camera and the offline walk-in queue needs `sqflite`, which has
  no web implementation. Those need a handset or an emulator.
- **`README.md`'s opening sections are stale** — they describe a
  carpooling app with gamification that this project is not. Trust
  `CLAUDE.md`, `docs/UI_REDESIGN.md` and `docs/REMAINING_WORK.md`.

## What to read before writing code

1. `CLAUDE.md` — vocabulary (route / stop / leg / **space**, never "seat"),
   the domain invariants, and current state.
2. `docs/UI_REDESIGN.md` — if you are continuing the redesign: what is
   done, what is left, and the decisions already made.
3. `docs/REMAINING_WORK.md` — everything else outstanding.
4. `backend/app/infrastructure/repositories/seat_repository.py` — read the
   module docstring before touching it. It locks coarsely on purpose.
