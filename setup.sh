#!/usr/bin/env bash
# Set up SabayGo on a fresh machine. Idempotent -- safe to re-run.
#
#   ./setup.sh              database + backend + Flutter clients
#   ./setup.sh --with-ai    also the Flask/YOLOv8 node (pulls PyTorch, ~6 GB)
#   ./setup.sh --keep-db     skip ./db/reset-dev.sh (keeps existing data)
#
# What this script will NOT do: install Docker, Python or Flutter. Those
# need administrator rights and differ per OS, so it checks for them and
# tells you what is missing instead of guessing.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

WITH_AI=0
KEEP_DB=0
for arg in "$@"; do
  case "$arg" in
    --with-ai) WITH_AI=1 ;;
    --keep-db) KEEP_DB=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
ok()   { printf '  . %s\n' "$*"; }

# ─────────────────────────────────────────────── 1. prerequisites
say "checking prerequisites"
MISSING=()

if ! command -v docker >/dev/null 2>&1; then
  MISSING+=("docker -- install Docker Desktop (Windows/macOS) or your distro's docker + docker-compose-plugin")
elif ! docker info >/dev/null 2>&1; then
  MISSING+=("docker is installed but the daemon is not running -- start Docker Desktop, or: sudo systemctl start docker")
elif ! docker compose version >/dev/null 2>&1; then
  MISSING+=("docker compose v2 -- install the docker-compose-plugin package (the old 'docker-compose' binary will not do)")
else
  ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"
fi

PY=""
for cand in python3.14 python3.13 python3.12 python3 python; do
  if command -v "$cand" >/dev/null 2>&1 &&
     "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' 2>/dev/null; then
    PY="$cand"; break
  fi
done
if [ -z "$PY" ]; then
  MISSING+=("python 3.12 or newer -- the main machine runs 3.14.7")
else
  ok "$("$PY" --version)"
fi

HAVE_FLUTTER=1
if ! command -v flutter >/dev/null 2>&1; then
  HAVE_FLUTTER=0
  warn "flutter not found -- the database and backend will still be set up,"
  warn "  but no client can run. Install Flutter stable (Dart 3.12.1+) and re-run."
else
  ok "$(flutter --version 2>/dev/null | head -n 1)"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  printf '\nCannot continue. Install these first:\n\n' >&2
  for m in "${MISSING[@]}"; do printf '  - %s\n' "$m" >&2; done
  printf '\nThen run ./setup.sh again.\n' >&2
  exit 1
fi

# ─────────────────────────────────────────────── 2. environment files
# A zipped handover carries .env along (it is gitignored, not absent), so
# these branches are no-ops in that case. A fresh git clone needs them.
say "environment files"

gen_hex() { "$PY" -c 'import secrets,sys; print(secrets.token_hex(int(sys.argv[1])))' "$1"; }

# Fill a blank or missing KEY= in a .env file, printing what it did.
# Never overwrites a value that is already there.
set_env_if_blank() {
  local file="$1" key="$2" value="$3"
  "$PY" - "$file" "$key" "$value" <<'PY'
import sys, pathlib
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines(keepends=True) if path.exists() else []
for i, line in enumerate(lines):
    if line.split("=", 1)[0].strip() == key:
        if line.split("=", 1)[1].strip():
            print(f"  . {path.name}: {key} already set, left alone")
            sys.exit(0)
        lines[i] = f"{key}={value}\n"
        path.write_text("".join(lines))
        print(f"  . {path.name}: {key} generated")
        sys.exit(0)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"
lines.append(f"{key}={value}\n")
path.write_text("".join(lines))
print(f"  . {path.name}: {key} added")
PY
}

read_env() {  # read_env <file> <key> -> value on stdout, empty if absent
  [ -f "$1" ] || return 0
  grep -E "^$2=" "$1" 2>/dev/null | tail -n 1 | cut -d= -f2- || true
}

for pair in ".env.example:.env" "backend/.env.example:backend/.env"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  if [ -f "$dst" ]; then
    ok "$dst present"
  elif [ -f "$src" ]; then
    cp "$src" "$dst"; ok "$dst created from $(basename "$src")"
  else
    warn "$src is missing -- cannot create $dst"; exit 1
  fi
done

# jwt_secret is declared min_length=32 in backend/app/config.py, so a blank
# one fails at import. This is the single most common setup failure.
set_env_if_blank backend/.env JWT_SECRET "$(gen_hex 32)"

# The AI node key must be identical on both sides or the backend gets a 401.
AI_KEY="$(read_env backend/.env AI_NODE_API_KEY)"
if [ -z "$AI_KEY" ]; then
  AI_KEY="$(gen_hex 16)"
  set_env_if_blank backend/.env AI_NODE_API_KEY "$AI_KEY"
fi
if [ -f ai_service/.env ]; then
  ok "ai_service/.env present"
  if [ "$(read_env ai_service/.env AI_NODE_API_KEY)" != "$AI_KEY" ]; then
    warn "ai_service/.env AI_NODE_API_KEY does not match backend/.env --"
    warn "  the backend will get 401s from the node. Make them the same."
  fi
else
  printf 'AI_NODE_API_KEY=%s\n' "$AI_KEY" > ai_service/.env
  ok "ai_service/.env created, key matched to backend/.env"
fi

set_env_if_blank backend/.env PHONE_CAPTURE_API_KEY "$(gen_hex 16)"

# The development payment sandbox signs its webhooks with this, exactly as
# PayMongo would. Real PayMongo issues its own secret; paste that over this
# one when real keys are configured.
set_env_if_blank backend/.env PAYMONGO_WEBHOOK_SECRET "$(gen_hex 32)"

# ─────────────────────────────────────────────── 3. python venvs
# A venv is tied to its absolute path: console scripts carry it in their
# shebang. One that travelled in a zip from another machine is unusable,
# so it is moved aside (never deleted) and rebuilt.
ensure_venv() {
  local dir="$1" want="$ROOT/$1/venv"
  if [ -d "$dir/venv" ]; then
    local stale=0
    if [ -f "$dir/venv/bin/pip" ] && ! head -n 1 "$dir/venv/bin/pip" | grep -qF "$want"; then
      stale=1
    elif ! "$dir/venv/bin/python" -m pip --version >/dev/null 2>&1; then
      stale=1
    fi
    if [ "$stale" = 1 ]; then
      local aside="$dir/venv.stale-$(date +%Y%m%d%H%M%S)"
      mv "$dir/venv" "$aside"
      warn "$dir/venv was built elsewhere or is broken -- moved to $(basename "$aside")"
      warn "  delete it yourself once this finishes: rm -rf $aside"
    fi
  fi
  if [ ! -d "$dir/venv" ]; then
    say "creating $dir/venv"
    "$PY" -m venv "$dir/venv"
  fi
  say "installing $dir dependencies"
  "$dir/venv/bin/python" -m pip install -q --upgrade pip
  "$dir/venv/bin/python" -m pip install -q -r "$dir/requirements.txt"
  ok "$dir dependencies installed"
}

# The backend venv must exist before the database step: db/reset-dev.sh
# shells out to backend/venv/bin/python to bcrypt the dev password.
ensure_venv backend

if [ "$WITH_AI" = 1 ]; then
  warn "installing the AI node -- ultralytics pulls PyTorch, this is a large download"
  ensure_venv ai_service
fi

# ─────────────────────────────────────────────── 4. settings validation
say "validating backend settings"
if ( cd backend && ./venv/bin/python -c 'from app.config import get_settings; get_settings()' ); then
  ok "backend/.env loads and validates"
else
  warn "backend/.env failed validation -- fix the error above before starting uvicorn"
  exit 1
fi

# ─────────────────────────────────────────────── 5. database
say "starting MySQL and Adminer"
docker compose up -d
ok "containers up (mysql on 127.0.0.1:3307, adminer on 127.0.0.1:8080)"

if [ "$KEEP_DB" = 1 ]; then
  warn "--keep-db given: skipping the reset, existing data left alone"
else
  say "applying migrations and seeding (this DROPS and rebuilds the database)"
  ./db/reset-dev.sh
  ok "schema applied and seeded"
fi

# ─────────────────────────────────────────────── 6. flutter packages
if [ "$HAVE_FLUTTER" = 1 ]; then
  CLIENTS=(mobile operator_console)
  if [ "$WITH_AI" = 1 ]; then CLIENTS+=(ai_capture_app); fi
  for c in "${CLIENTS[@]}"; do
    say "flutter pub get -- $c"
    if ( cd "$c" && flutter pub get >/dev/null ); then
      ok "$c packages resolved"
    else
      warn "$c: flutter pub get failed -- see the output above"
      exit 1
    fi
  done

  say "proving the Flutter toolchain (layout suite, no backend or device needed)"
  if ( cd mobile && flutter test ); then
    ok "layout suite passed"
  else
    warn "the layout suite failed -- see the output above. The toolchain or"
    warn "  the Dart SDK version is the first thing to check."
  fi
fi

# ─────────────────────────────────────────────── done
cat <<'EOF'

==> Setup finished. To run the system:

  ./run.sh

That starts the database, the backend on 0.0.0.0:8000, the AI node and the
cooperative console (built once, then served on localhost:3001), and
prints the address handsets should dial. Add
--mobile --capture to also build the two handset apps onto an attached
device. Ctrl-C stops everything.

To run one piece at a time instead:

  cd backend && source venv/bin/activate && \
    uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  cd mobile && flutter run -d chrome --web-port=3000 \
    --dart-define=API_BASE_URL=http://localhost:8000/api/v1

  cd operator_console && flutter run -d chrome --web-port=3001 \
    --dart-define=API_BASE_URL=http://localhost:8000/api/v1

Sign in as passenger@ / conductor@ / driver@ / coopadmin@sabaygo.dev,
password sabaygo123.

Conductor screens need a real handset or an emulator -- mobile_scanner
needs a camera and the walk-in queue needs sqflite, which has no web build.

Read docs/SETUP.md for the rest, CLAUDE.md before writing any code.
EOF
