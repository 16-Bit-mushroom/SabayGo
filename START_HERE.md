# Start here

SabayGo — booking and fleet management for terminal-based UV Express vans.
Capstone, BSIT, University of Mindanao. A2Z Transport Cooperative is the
pilot partner.

## Getting the code

Fork `16-Bit-mushroom/SabayGo` on GitHub, then:

```bash
git clone https://github.com/<your-username>/SabayGo.git SabayGo_VS
cd SabayGo_VS
git remote add upstream https://github.com/16-Bit-mushroom/SabayGo.git
```

Add the `upstream` remote even though it looks optional — without it you
cannot `git pull upstream main`, and your fork drifts from ours over the
weeks to the defence. Your work comes back as a pull request from your fork.

If you were handed `sabaygo-handover.zip` instead, that is a snapshot for a
day with no internet. It goes stale as soon as either of us commits, so
prefer the fork.

## Three things you install yourself

None of these can be automated — they need administrator rights and differ
per platform. Everything *after* them is one command.

1. **Docker** with Compose v2 — runs MySQL. Nothing else is containerised.
2. **Python 3.12 or newer** — the backend. Our machine runs 3.14.7.
3. **Flutter stable**, Dart 3.12.1 or newer — the apps.

Then, in the project root:

```bash
./setup.sh
```

It is idempotent, so re-running after a failure is safe. It writes the
`.env` files and generates the keys, builds the Python venv, starts MySQL,
applies all 16 migrations, seeds the demo data, resolves the Flutter
packages, and finishes by running the layout test suite to prove the
toolchain is sound. It prints the run commands when it is done.

The `.env` files are not in the repository and not in the archive — secrets
should not travel through either. `setup.sh` generates them. The one value
it cannot invent is `PAYMONGO_WEBHOOK_SECRET`, needed only to test a live
payment webhook, which the UI work does not touch.

---

## Linux

### Docker

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y docker.io docker-compose-v2

# Arch / CachyOS / Manjaro
sudo pacman -S --needed docker docker-compose
```

Then, on any distro:

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker            # or log out and back in
docker info >/dev/null && echo "docker ok"
```

Do not skip the group step. Without it every `docker` call needs `sudo`,
and `setup.sh` stops at its first check rather than silently running the
database as root.

### Python

```bash
# Debian / Ubuntu -- python3-venv is a separate package and setup.sh needs it
sudo apt install -y python3 python3-venv python3-pip

# Arch
sudo pacman -S --needed python
```

### Flutter

```bash
# build prerequisites
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa   # Debian / Ubuntu
sudo pacman -S --needed curl git unzip xz zip glu              # Arch

git clone https://github.com/flutter/flutter.git -b stable ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc   # or ~/.config/fish/config.fish
source ~/.bashrc
flutter --version        # Dart must be 3.12.1 or newer
```

`flutter doctor` will report the Android toolchain missing. Ignore it —
the web target and the layout suite need neither an Android SDK nor a
device. You only need the SDK for the conductor screens (see the last
section).

If `flutter run -d chrome` cannot find a browser:

```bash
export CHROME_EXECUTABLE=/usr/bin/chromium    # or /usr/bin/google-chrome-stable
```

### Run it

```bash
./setup.sh
```

---

## Windows 11

Everything here is bash and Docker, so the supported path is **WSL2** — one
shell, one filesystem, every script working unchanged. Do not run `db/*.sh`
or `setup.sh` from PowerShell or Git Bash: `db/apply.sh` pipes heredoc SQL
through `docker compose exec`, and Git Bash's path translation mangles it.

### 1. WSL2 and Ubuntu

In **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot, open Ubuntu from the Start menu, set a UNIX username and password.
Ubuntu 24.04 ships Python 3.12, which is new enough.

### 2. Docker Desktop

Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/),
then in **Settings → Resources → WSL integration**, switch on your
`Ubuntu-24.04` distro. Without that checkbox the `docker` command does not
exist inside Ubuntu and `setup.sh` stops on its first check. Leave Docker
Desktop running whenever you work on the project.

### 3. Work inside the Linux filesystem, not on C:

This matters more than it looks. Everything below runs **inside Ubuntu**:

```bash
sudo apt update
sudo apt install -y python3 python3-venv git curl unzip xz-utils zip libglu1-mesa
cd ~
git clone https://github.com/<your-username>/SabayGo.git SabayGo_VS
cd SabayGo_VS
```

Keep the project at `~/SabayGo_VS`, **not** under `/mnt/c/`. Windows drives
are mounted over a network protocol inside WSL: pip and Flutter builds run
several times slower there, and `uvicorn --reload` never sees your edits
because inotify does not work across that mount. Editing is unaffected —
VS Code's WSL extension opens `~/SabayGo_VS` natively, and
`\\wsl$\Ubuntu-24.04\home\<you>\SabayGo_VS` works in Explorer.

### 4. Flutter inside Ubuntu

Same as the Linux section above. For the browser, point Flutter at the
Chrome already installed on Windows:

```bash
echo 'export CHROME_EXECUTABLE="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"' >> ~/.bashrc
source ~/.bashrc
```

WSL2 forwards localhost both ways, so Chrome on Windows reaches the Flutter
web server and the backend inside Ubuntu with no extra flags.

### 5. Run it

```bash
./setup.sh
```

### Line endings

Do not set `git config core.autocrlf true`. A `.gitattributes` in the repo
pins `*.sh` to LF, but that global setting can still rewrite a script on
checkout, and bash then fails with `$'\r': command not found`.

---

## Claude Code: the skills we use

Run Claude Code from the project root — on Windows, **inside Ubuntu**,
where the project lives, so it picks up the same paths and shell as the
scripts.

Ask Claude to install these by name; the `find-skills` skill exists for
exactly this, so `/find-skills mobile app ui design` or plain *"install the
mobile-app-ui-design skill"* is enough. Only four are worth your time for
the redesign:

| Skill | What it is for |
|---|---|
| `mobile-app-ui-design` | Mobile screen, flow and component design. The closest fit to the remaining work. |
| `craft` | 12 concrete visual-craft rules — bans gradients, glow, `transition:all`. Catches the "looks AI-generated" failure mode. |
| `accessibility` | WCAG 2.1 A/AA review. We fixed five contrast failures already; this keeps new ones out. |
| `ux-heuristics-review` | Nielsen's 10 heuristics against a screen or flow. |

We also run **caveman**, which compresses Claude's replies to cut token
cost: `caveman` itself plus `caveman-commit`, `caveman-review`,
`caveman-explore`, `caveman-help` and `caveman-stats`. Invoke a mode with
`/caveman` and `/caveman-help` prints the reference card. Optional — it
changes how Claude talks to you, not what it does.

Two caveats worth knowing before you install more of either family:

- The rest of the caveman set (`caveman-setup`, `caveman-discover`,
  `caveman-optimize`, `caveman-manage`, `caveman-evidence-review`,
  `caveman-compress`) needs a Caveman Cloud gateway configured as an MCP
  server, and `cavecrew` needs its own subagents. Without those they load
  and then fail, so leave them out unless you set the gateway up.
- There are eighteen more UI/UX skills on our machine — `design-analysis`,
  `dieter-rams-principles`, `cognitive-load-conversion`, `persuasive-ux`,
  `journey-mapping`, `ux-personas`, the `ai-*` pattern set and so on.
  Useful for the paper's design chapter, mostly noise for finishing
  screens. Install them when you have a reason.

If installing by name does not find one, ask Clarence for the folder from
his `~/.claude/skills/` — a skill is just a directory with a `SKILL.md` in
it, and it works the same dropped into your own `~/.claude/skills/`. Use
the WSL home for that on Windows, not the Windows user profile.

`CLAUDE.md` in the repo root is loaded automatically every session, so
Claude already knows the project's vocabulary and invariants. You do not
need to explain the domain to it.

---

## Then read these, in order

| File | Why |
|---|---|
| `CLAUDE.md` | Vocabulary, domain invariants, current state. Read before writing any code. |
| `docs/UI_REDESIGN.md` | The task you are picking up: what is done, what is left, decisions already made. |
| `docs/status/2026-09-29-status.html` | Where the whole project stands. Open it in a browser. |
| `docs/SETUP.md` | Setup in more depth than this page, including the AI node and how to attach a phone. |
| `docs/REMAINING_WORK.md` | Everything else outstanding. |

Two pieces of vocabulary that will save you a wrong assumption. Capacity is
counted in **spaces per leg**, not seats — UV Express assigns no seat
numbers, and one space can carry two paying passengers on one trip when
their journeys do not overlap. And `coop_admin` is **never** called
"operator": under LTFRB usage an operator is the franchise holder, a
different party from the cooperative's office staff.

## Signing in

Dev accounts, password `sabaygo123`:
`passenger@sabaygo.dev`, `conductor@sabaygo.dev`, `driver@sabaygo.dev`,
`coopadmin@sabaygo.dev`. The sign-in screen offers them as one-tap chips in
debug builds.

## What you can and cannot see in a browser

Most passenger screens review fine in Chrome. The conductor screens do not
open there at all — `mobile_scanner` needs a camera and the offline walk-in
queue needs `sqflite`, and neither has a web implementation. Those need a
real handset:

```bash
sudo apt install -y adb
adb connect 192.168.1.2:5555      # the phone's wireless-adb address
cd mobile
flutter run -d 192.168.1.2:5555 \
  --dart-define=API_BASE_URL=http://<your-lan-ip>:8000/api/v1
```

Wireless adb works from WSL2 because it is plain TCP. **USB does not** —
WSL2 has no USB passthrough. On native Linux a cable works once your user
is in the right group for the device. Either way the API base URL must be
the host machine's LAN IP, not `localhost`, because the phone is a
different device.
