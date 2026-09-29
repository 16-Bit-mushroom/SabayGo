# Start here

SabayGo — booking and fleet management for terminal-based UV Express vans.
Capstone, BSIT, University of Mindanao. A2Z Transport Cooperative is the
pilot partner.

This archive is the whole project, minus three things you do not need to
chase: the Python virtual environments and Flutter build output, which are
machine-specific and get rebuilt on your side, and the `.env` files, which
hold secrets and should never travel through cloud storage. `setup.sh`
generates the keys for you. The only one it cannot invent is
`PAYMONGO_WEBHOOK_SECRET`, and that is needed solely to test a live payment
webhook — not for the UI work.

## On Windows 11 — the whole setup

You need three things installed, and none of them can be automated because
they need administrator rights:

1. **WSL2 with Ubuntu** — in PowerShell as Administrator:
   `wsl --install -d Ubuntu-24.04`, then reboot.
2. **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** —
   and in Settings → Resources → WSL integration, switch on `Ubuntu-24.04`.
   Leave Docker Desktop running while you work.
3. **Flutter stable**, installed *inside* Ubuntu (Dart 3.12.1 or newer).

Then, in the Ubuntu terminal:

```bash
sudo apt update
sudo apt install -y python3 python3-venv unzip git curl xz-utils zip libglu1-mesa
cd ~
unzip /mnt/c/Users/<your-name>/Downloads/sabaygo-handover.zip -d SabayGo_VS
cd SabayGo_VS
./setup.sh
```

Unpack it at `~/SabayGo_VS` and **not** under `/mnt/c/`. Windows drives are
mounted over a network protocol inside WSL, which makes builds several times
slower and stops `uvicorn --reload` from seeing your edits.

`setup.sh` is idempotent, so re-running it after a failure is safe. It
writes the environment keys, builds the Python venv, starts MySQL, applies
all 16 migrations, seeds the demo data, resolves the Flutter packages, and
finishes by running the layout test suite as proof the toolchain is sound.
It prints the run commands when it is done.

Do not run the `.sh` scripts from PowerShell or Git Bash — they pipe SQL
through `docker compose exec` and Git Bash mangles the paths.

**Step-by-step detail, including the Flutter install and how to attach a
phone: [docs/SETUP.md](docs/SETUP.md).** Read that one if anything here
does not go to plan.

## Then read these, in order

| File | Why |
|---|---|
| `CLAUDE.md` | Vocabulary, domain invariants, and current state. Read before writing any code. |
| `docs/UI_REDESIGN.md` | The task you are picking up: what is done, what is left, decisions already made. |
| `docs/status/2026-09-29-status.html` | Where the whole project stands. Open it in a browser. |
| `docs/REMAINING_WORK.md` | Everything else outstanding. |

Two pieces of vocabulary that will save you a wrong assumption: capacity is
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
open there at all — `mobile_scanner` needs a camera and the walk-in queue
needs `sqflite`, and neither has a web implementation. Those need a real
handset over wireless adb; `docs/SETUP.md` has the commands.
