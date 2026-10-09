#!/usr/bin/env bash
# Start the whole SabayGo system with one command.
#
#   ./run.sh                     database, backend, AI node, console
#   --mobile                     also the passenger/conductor app on a handset
#   --capture                    also the AI capture app on a handset
#   --device <id>                which handset (default: the first attached)
#   --host <ip>                  force the address handsets dial, when
#                                detection picks the wrong interface
#   --reset-db                   rebuild the demo data before starting
#   --soon                       rebuild it with the trip departing in 20 min
#   --no-ai                      skip the Flask/YOLOv8 node
#   --no-console                 skip the cooperative console
#   --no-gps                     do not simulate GPS for trips on the road
#
# WHY THIS SCRIPT EXISTS
#
# The address of this machine is the one piece of configuration that is
# different at every venue, and it has to arrive in five places at once:
# the backend's CORS rules, the console's API_BASE_URL, the handset's
# API_BASE_URL, and the capture app's two URLs. At the last demo the
# school network handed out a different address, the handsets were still
# built against the home one, and the console's trigger-phone request
# went to a phone that was polling a dead host. Nothing was broken --
# four copies of an IP address had drifted apart.
#
# So the address is resolved ONCE here and handed to every process. There
# is no second copy to forget.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

HOST=""
WITH_AI=1
WITH_MOBILE=0
WITH_CAPTURE=0
WITH_CONSOLE=1
WITH_GPS=1
RESET_DB=0
RESET_ARGS=()
DEVICE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)       HOST="${2:?--host needs an address}"; shift 2 ;;
    --device)     DEVICE="${2:?--device needs a device id}"; shift 2 ;;
    --mobile)     WITH_MOBILE=1; shift ;;
    --capture)    WITH_CAPTURE=1; shift ;;
    --no-ai)      WITH_AI=0; shift ;;
    --no-console) WITH_CONSOLE=0; shift ;;
    --no-gps)     WITH_GPS=0; shift ;;
    --reset-db)   RESET_DB=1; shift ;;
    --soon)       RESET_DB=1; RESET_ARGS+=(--soon); shift ;;
    -h|--help)    sed -n '2,14p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $1  (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '  . %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

PORT_BACKEND=8000
PORT_AI=5000
PORT_CONSOLE=3001        # pinned, not random: see the CORS note in config.py
LOGS="$ROOT/logs"
mkdir -p "$LOGS"

# ───────────────────────────────────────────── the one address
# `ip route get` reports the source address the kernel would actually use
# to leave this machine, which is the one a handset on the same LAN can
# reach. `hostname -I` is the fallback and can list several; take the
# first non-loopback.
resolve_host() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n 1)"
  fi
  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -vE '^(127\.|$)' | head -n 1)"
  fi
  printf '%s' "$ip"
}

if [ -z "$HOST" ]; then
  HOST="$(resolve_host)"
  [ -n "$HOST" ] || die "could not work out this machine's LAN address. Pass it: ./run.sh --host 192.168.x.x"
  ok "LAN address detected: $HOST"
else
  ok "LAN address given: $HOST"
fi
case "$HOST" in
  127.*|localhost)
    warn "$HOST is loopback -- no handset can reach it. Pass --host with the real LAN address." ;;
esac

# A host firewall drops a handset's connection silently: the phone can
# even ping this machine while every request to 8000 dies, and the
# backend log stays empty because nothing arrived. ufw did exactly this
# on a phone hotspot. Rules need root, so the script only checks and
# prints the one command that fixes it; ufw keeps the rule across reboots.
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
  warn "ufw is active. If a phone cannot reach this machine, allow the two"
  warn "  ports from private networks (once, it persists):"
  warn "    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; sudo ufw allow proto tcp from \$net to any port $PORT_BACKEND,$PORT_AI; end"
  warn "  (bash: for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do sudo ufw allow proto tcp from \$net to any port $PORT_BACKEND,$PORT_AI; done)"
fi

# The console runs in a browser on THIS machine, so it dials 127.0.0.1 and
# is immune to the address changing. Only the handsets need $HOST.
API_LAN="http://$HOST:$PORT_BACKEND/api/v1"
API_LOCAL="http://127.0.0.1:$PORT_BACKEND/api/v1"
AI_LAN="http://$HOST:$PORT_AI"

read_env() {  # read_env <file> <key>
  [ -f "$1" ] || return 0
  grep -E "^$2=" "$1" 2>/dev/null | tail -n 1 | cut -d= -f2- || true
}
AI_KEY="$(read_env backend/.env AI_NODE_API_KEY)"
PHONE_KEY="$(read_env backend/.env PHONE_CAPTURE_API_KEY)"

# ───────────────────────────────────────────── child process bookkeeping
PIDS=()
NAMES=()
# 1 = the system is broken without it; 0 = an aid that may stop on its own
# (a GPS simulator exits when its trip completes, and that must not
# take the backend down in the middle of a demo).
CRITICAL=()
SHUTTING_DOWN=0

# uvicorn and `flutter run` both shut their own children down on SIGTERM,
# so ask politely first and only insist on the ones still standing.
cleanup() {
  trap - INT TERM EXIT
  SHUTTING_DOWN=1
  [ ${#PIDS[@]} -gt 0 ] || return 0
  say "stopping"
  for i in "${!PIDS[@]}"; do
    kill -TERM "${PIDS[$i]}" 2>/dev/null && ok "${NAMES[$i]} asked to stop" || true
  done
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    local alive=0
    for pid in "${PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
    [ "$alive" = 1 ] || break
    sleep 1
  done
  for pid in "${PIDS[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
  printf '\nMySQL is still up (docker compose down to stop it).\nLogs are in %s\n' "$LOGS"
}
# INT/TERM must also END the script: a handler returns to wherever the
# script was, and that is the watch loop at the bottom.
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

# start <name> <workdir> <logfile> <command...>
# A subshell cd rather than `env -C`, which is GNU-only and the handover
# zip is meant to run on macOS and Git Bash too. `exec` keeps $! pointing
# at the real process, not a shell wrapper that would survive the kill.
start() {
  local name="$1" dir="$2" log="$3"; shift 3
  : > "$log"
  ( cd "$dir" && exec "$@" ) >>"$log" 2>&1 < /dev/null &
  PIDS+=("$!")
  NAMES+=("$name")
  CRITICAL+=(1)
  ok "$name started (pid $!, log ${log#$ROOT/})"
}

# start_aux: as start, but the process is allowed to exit on its own.
start_aux() {
  start "$@"
  CRITICAL[${#CRITICAL[@]}-1]=0
}

# Poll a URL until it answers, or give up and show the tail of the log --
# an empty log means the process never got as far as binding.
# Wall clock, not an iteration count: each failed probe can itself cost
# the two-second connect timeout, so counting attempts would have made
# "within 300s" mean something closer to fifteen minutes.
wait_for() {  # wait_for <label> <url> <seconds> <logfile>
  local label="$1" url="$2" limit="$3" log="$4"
  local deadline=$(( $(date +%s) + limit ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if python3 - "$url" <<'PY' >/dev/null 2>&1
import sys, urllib.request
urllib.request.urlopen(sys.argv[1], timeout=2).read()
PY
    then ok "$label is answering"; return 0; fi
    sleep 1
  done
  warn "$label did not answer $url within ${limit}s. Last lines of its log:"
  tail -n 15 "$log" >&2 || true
  die "$label failed to start"
}

# ───────────────────────────────────────────── 1. database
say "database"
# docker-compose.yml interpolates MYSQL_* from the repo-root .env. Without
# it the containers come up with blank credentials and the backend's first
# query fails with an access-denied that looks like a schema problem.
[ -f .env ] || die "repo-root .env is missing -- run ./setup.sh first"
docker compose up -d >/dev/null
# `docker compose up -d` returns before MySQL finishes its first-boot
# initialisation, and the backend's first query would fail against a
# half-open server.
i=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' sabaygo-mysql 2>/dev/null)" = "healthy" ]; do
  i=$((i+1)); [ "$i" -lt 90 ] || die "MySQL never became healthy (docker compose logs mysql)"
  sleep 1
done
ok "MySQL healthy on 127.0.0.1:3307"

if [ "$RESET_DB" = 1 ]; then
  say "rebuilding demo data ${RESET_ARGS[*]-}"
  ./db/reset-dev.sh ${RESET_ARGS[@]+"${RESET_ARGS[@]}"}
  ok "schema applied and seeded"
fi

# ───────────────────────────────────────────── 2. backend
say "backend"
[ -x backend/venv/bin/python ] || die "backend/venv is missing -- run ./setup.sh first"
start backend "$ROOT/backend" "$LOGS/backend.log" \
  "$ROOT/backend/venv/bin/python" -m uvicorn app.main:app \
  --host 0.0.0.0 --port "$PORT_BACKEND"
wait_for backend "http://127.0.0.1:$PORT_BACKEND/health" 45 "$LOGS/backend.log"

# ───────────────────────────────────────────── 3. AI node
if [ "$WITH_AI" = 1 ]; then
  say "AI node"
  if [ ! -x ai_service/venv/bin/python ]; then
    warn "ai_service/venv is missing -- skipping the AI node."
    warn "  ./setup.sh --with-ai installs it (PyTorch, ~6 GB)."
    warn "  Without it, audits return 502 rather than an invented count."
    WITH_AI=0
  else
    # app.py reads AI_NODE_API_KEY from the environment, not from its
    # .env file, and it must be the same string the backend sends or every
    # capture comes back 401.
    if [ -n "$AI_KEY" ]; then export AI_NODE_API_KEY="$AI_KEY"; fi
    start "ai node" "$ROOT/ai_service" "$LOGS/ai_service.log" \
      "$ROOT/ai_service/venv/bin/python" app.py
    wait_for "ai node" "http://127.0.0.1:$PORT_AI/health" 90 "$LOGS/ai_service.log"
  fi
fi

# ───────────────────────────────────────────── GPS for trips on the road
# The live map draws only vans that have REPORTED a position -- it never
# places one where nobody said it was. Until the van kit's GPS unit
# exists, tracking_simulator.py is that unit: real HTTP pings to the real
# endpoint, map-matched by the real server, only the coordinates are
# simulated. One per trip that is departed today, so a seeded or
# demo-departed trip shows up moving instead of not at all.
#
# A trip departed AFTER this point gets none until ./run.sh is re-run --
# or start one by hand: backend/venv/bin/python backend/scripts/tracking_simulator.py --trip <id> --loop
GPS_TRIPS=()
if [ "$WITH_GPS" = 1 ]; then
  say "GPS for trips on the road"
  # shellcheck disable=SC1091
  MYSQL_USER_="$(read_env .env MYSQL_USER)"; MYSQL_PW_="$(read_env .env MYSQL_PASSWORD)"
  MYSQL_DB_="$(read_env .env MYSQL_DATABASE)"
  mapfile -t GPS_TRIPS < <(docker exec -e MYSQL_PWD="$MYSQL_PW_" sabaygo-mysql \
      mysql -u"$MYSQL_USER_" "$MYSQL_DB_" -N -e \
      "SELECT trip_id FROM trips WHERE status = 'departed' AND service_date = CURDATE()" \
      2>/dev/null || true)
  if [ ${#GPS_TRIPS[@]} -eq 0 ]; then
    ok "no trip is on the road today -- nothing to simulate"
  else
    TRACKER_KEY_="$(read_env backend/.env TRACKER_API_KEY)"
    if [ -n "$TRACKER_KEY_" ]; then export TRACKER_API_KEY="$TRACKER_KEY_"; fi
    export SABAYGO_API="http://127.0.0.1:$PORT_BACKEND/api/v1"
    for trip in "${GPS_TRIPS[@]}"; do
      # --speed 4: a 50 km route crosses the map in minutes, not an hour.
      # --loop: back to the first stop on arrival, so the van stays visible.
      start_aux "gps $trip" "$ROOT/backend" "$LOGS/gps_$trip.log" \
        "$ROOT/backend/venv/bin/python" -u scripts/tracking_simulator.py \
        --trip "$trip" --loop --speed 4
    done
  fi
fi

# ───────────────────────────────────────────── 4. Flutter clients
# This script runs under bash while the shell here is fish, so flutter may
# be on the interactive PATH and not on this one. Check the usual place
# before concluding it is absent.
if ! command -v flutter >/dev/null 2>&1 && [ -x "$HOME/flutter/bin/flutter" ]; then
  PATH="$HOME/flutter/bin:$PATH"
fi
HAVE_FLUTTER=1
command -v flutter >/dev/null 2>&1 || HAVE_FLUTTER=0
[ "$HAVE_FLUTTER" = 1 ] || warn "flutter not found -- no client will be started"

# Pick an attached handset: the first device that is neither a browser nor
# this desktop. Printed so it is obvious which phone got the build.
pick_device() {
  flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try: devices = json.load(sys.stdin)
except Exception: sys.exit(0)
for d in devices:
    if d.get("targetPlatform", "").startswith(("android", "ios")) and not d.get("emulator", False):
        print(d["id"]); break
else:
    for d in devices:
        if d.get("targetPlatform", "").startswith(("android", "ios")):
            print(d["id"]); break
'
}

# The console is BUILT and then served as static files, not run through
# `flutter run`.
#
# `flutter run` cannot serve this app on this machine. `-d chrome` needs a
# binary named exactly google-chrome and reports "no supported devices"
# where there is a Chromium; `-d web-server` opens the port but never
# accepts a connection -- nine minutes at "Launching in debug mode", 73%
# CPU, reproduced by hand with no script involved. `flutter doctor` says
# the same thing: [X] Chrome - develop for the web.
#
# `flutter build web` has none of that in its path: no browser, no debug
# service, no handshake. What comes out is a directory of files, and
# serving a directory of files is something that cannot half-work. The
# cost is hot reload, which a demo does not use.
CONSOLE_WEB="$ROOT/operator_console/build/web"
CONSOLE_STAMP="$CONSOLE_WEB/.sabaygo-api-base"

# Rebuild only when the bundle is missing, older than the source, or was
# built against a different backend -- API_BASE_URL is compiled in, so a
# bundle built for another address is wrong, not merely stale, and that is
# exactly the drift that broke the last demo.
console_needs_build() {
  [ -f "$CONSOLE_WEB/main.dart.js" ] || return 0
  [ -f "$CONSOLE_STAMP" ] || return 0
  [ "$(cat "$CONSOLE_STAMP")" = "$API_LOCAL" ] || return 0
  [ -z "$(find "$ROOT/operator_console/lib" "$ROOT/operator_console/pubspec.yaml" \
            -newer "$CONSOLE_WEB/main.dart.js" -print -quit 2>/dev/null)" ] || return 0
  return 1
}

if [ "$WITH_CONSOLE" = 1 ] && [ "$HAVE_FLUTTER" = 1 ]; then
  say "cooperative console"
  if console_needs_build; then
    ok "building (a few minutes, and only when the console changes)"
    # --pwa-strategy=none: no service worker. One would cache the previous
    # bundle and happily serve a console still pointed at the old
    # backend, which is unfixable from the demo floor.
    if ! ( cd "$ROOT/operator_console" && flutter build web --release \
             --pwa-strategy=none \
             --dart-define=API_BASE_URL="$API_LOCAL" ) \
           > "$LOGS/console_build.log" 2>&1; then
      warn "the console failed to build. Last lines:"
      tail -n 20 "$LOGS/console_build.log" >&2 || true
      die "console build failed"
    fi
    printf '%s' "$API_LOCAL" > "$CONSOLE_STAMP"
    ok "built"
  else
    ok "bundle is current -- not rebuilding"
  fi

  # ThreadingHTTPServer since Python 3.7, so the app's many asset requests
  # are not serialised behind each other.
  start console "$CONSOLE_WEB" "$LOGS/console.log" \
    python3 -m http.server "$PORT_CONSOLE" --bind 0.0.0.0 --directory "$CONSOLE_WEB"
  wait_for console "http://127.0.0.1:$PORT_CONSOLE/" 30 "$LOGS/console.log"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:$PORT_CONSOLE" >/dev/null 2>&1 || true
    ok "opened in your default browser"
  fi
fi

if { [ "$WITH_MOBILE" = 1 ] || [ "$WITH_CAPTURE" = 1 ]; } && [ "$HAVE_FLUTTER" = 1 ]; then
  if [ -z "$DEVICE" ]; then
    DEVICE="$(pick_device)"
  fi
  if [ -z "$DEVICE" ]; then
    warn "no handset attached. Connect one (adb devices) or pass --device <id>."
    WITH_MOBILE=0; WITH_CAPTURE=0
  else
    ok "handset: $DEVICE"
  fi
fi

# Handset apps are BUILT, INSTALLED and LAUNCHED -- one after the other,
# in the foreground -- not left running under `flutter run`.
#
# The first version backgrounded two `flutter run`s at the same handset.
# They queued on Flutter's startup lock and fought over Gradle, the
# summary said "SabayGo is up" a full minute before either app existed,
# and the shutdown that followed killed both mid-build with nothing
# installed and no error in either log.
#
# Installed this way, an app outlives the launcher: Ctrl-C and re-run on
# a new network and it is still on the phone, which is what makes the
# capture app's "Find server" button useful. `adb install -r` rather than
# `flutter install` because -r keeps app data -- the conductor stays
# signed in across a reinstall.
#
# Debug builds, because that is what has been verified on device: a
# release build hides the dev-account chips and is a different binary.
ADB=""
for cand in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk "$HOME/Android/Sdk"; do
  if [ -n "$cand" ] && [ -x "$cand/platform-tools/adb" ]; then
    ADB="$cand/platform-tools/adb"; break
  fi
done
[ -n "$ADB" ] || ADB="$(command -v adb || true)"

MOBILE_STATUS="not installed (pass --mobile)"
CAPTURE_STATUS="not installed (pass --capture)"

# install_app <label> <dir> <android package> <log> <dart-define...>
# Sets INSTALL_RESULT rather than printing it, so its progress lines reach
# the terminal instead of being captured. Never dies: a phone app that failed to build should not take the
# backend and console down with it. It reports, and the summary says so.
install_app() {
  local label="$1" dir="$2" pkg="$3" log="$4"; shift 4
  local defines=()
  for d in "$@"; do defines+=("--dart-define=$d"); done

  say "$label -> $DEVICE"
  ok "building (Gradle: a few minutes the first time, faster after)"
  if ! ( cd "$dir" && flutter build apk --debug "${defines[@]}" ) > "$log" 2>&1; then
    warn "$label failed to build. Last lines of ${log#$ROOT/}:"
    tail -n 15 "$log" >&2 || true
    INSTALL_RESULT="BUILD FAILED -- see ${log#$ROOT/}"
    return 0
  fi
  local apk="$dir/build/app/outputs/flutter-apk/app-debug.apk"
  ok "installing"
  if ! "$ADB" -s "$DEVICE" install -r "$apk" >> "$log" 2>&1; then
    warn "$label built but would not install. Last lines of ${log#$ROOT/}:"
    tail -n 8 "$log" >&2 || true
    warn "  Unlock the phone and allow 'Install via USB' if it asks."
    INSTALL_RESULT="INSTALL FAILED -- see ${log#$ROOT/}"
    return 0
  fi
  # monkey with the LAUNCHER category starts the app without our having to
  # know its activity name.
  "$ADB" -s "$DEVICE" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 \
    >> "$log" 2>&1 || warn "installed, but could not launch it -- open it by hand"
  ok "installed and opened on the phone"
  INSTALL_RESULT="installed on $DEVICE"
}

if { [ "$WITH_MOBILE" = 1 ] || [ "$WITH_CAPTURE" = 1 ]; } && [ -z "$ADB" ]; then
  warn "adb not found -- cannot install to a handset. Install platform-tools."
  WITH_MOBILE=0; WITH_CAPTURE=0
fi

if [ "$WITH_MOBILE" = 1 ]; then
  install_app "passenger / conductor app" "$ROOT/mobile" \
    com.example.mobile_v2_uv_express "$LOGS/mobile_build.log" \
    "API_BASE_URL=$API_LAN"
  MOBILE_STATUS="$INSTALL_RESULT"
fi

if [ "$WITH_CAPTURE" = 1 ]; then
  install_app "AI capture app" "$ROOT/ai_capture_app" \
    com.sabaygo.ai_capture_app "$LOGS/capture_build.log" \
    "BACKEND_URL=$API_LAN" "PHONE_DEVICE_KEY=$PHONE_KEY" \
    "AI_NODE_URL=$AI_LAN" "AI_NODE_API_KEY=$AI_KEY"
  CAPTURE_STATUS="$INSTALL_RESULT"
fi

# ───────────────────────────────────────────── summary
CONSOLE_SUMMARY="not running"
if [ "$WITH_CONSOLE" = 1 ] && [ "$HAVE_FLUTTER" = 1 ]; then
  CONSOLE_SUMMARY="http://localhost:$PORT_CONSOLE"
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
  SabayGo is up.      this machine: $HOST

  Console                  $CONSOLE_SUMMARY
  Backend                  http://$HOST:$PORT_BACKEND   (docs: /docs)
  AI node                  $([ "$WITH_AI" = 1 ] && echo "$AI_LAN" || echo "not running")
  Adminer                  http://localhost:8080

  Handsets dial            $API_LAN
  GPS simulated for        $([ ${#GPS_TRIPS[@]} -gt 0 ] && echo "${GPS_TRIPS[*]}" || echo "no trip")
EOF

cat <<EOF

  Passenger/conductor app  $MOBILE_STATUS
  AI capture app           $CAPTURE_STATUS
EOF

cat <<EOF

  If the network changes mid-demo: Ctrl-C and re-run ./run.sh. An already
  installed capture app needs no rebuild -- press "Find server" on it.

  Ctrl-C stops everything. Logs: ${LOGS#$ROOT/}/
────────────────────────────────────────────────────────────────────
EOF

# Hold the terminal open so Ctrl-C reaches the trap, and watch the
# children. A critical one dying means the system is broken: say so and
# stop everything. An auxiliary one (a GPS simulator) is reported once and
# left alone. Polling rather than `wait -n`, which cannot tell the two apart.
REPORTED=()
while :; do
  for i in "${!PIDS[@]}"; do
    kill -0 "${PIDS[$i]}" 2>/dev/null && continue
    if [ "${CRITICAL[$i]}" = 1 ]; then
      warn "${NAMES[$i]} exited on its own -- check $LOGS. Stopping everything."
      exit 1
    fi
    if [ -z "${REPORTED[$i]:-}" ]; then
      warn "${NAMES[$i]} stopped (its log says why); everything else keeps running"
      REPORTED[$i]=1
    fi
  done
  sleep 2
done
