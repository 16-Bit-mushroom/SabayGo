#!/usr/bin/env bash
# usb_phones.sh -- phones reach the laptop through their USB cable, for a
# network that keeps its devices apart (21 Nov: the school's
# LIC-WIFI-OPEN, a Meraki network where no phone could reach the laptop).
#
#   ./usb_phones.sh            each attached phone: a tunnel to the backend,
#                              and the passenger/Dispatcher app installed
#                              and opened (not on the camera phone)
#   ./usb_phones.sh --tunnel   the tunnels only, no install
#   ./usb_phones.sh --watch    keep running: reopen a phone's tunnel within
#                              3 s each time its USB connection resets
#                              (21 Nov: the camera phone's reset 4 times
#                              in an hour, and each reset closed it)
#
# Run it after plugging a phone in, and again after a cable comes out:
# the tunnel (adb reverse) dies with the USB connection. The app must be
# the USB build, which dials 127.0.0.1 -- the phone's own end of the
# tunnel -- not the laptop's Wi-Fi address that ./run.sh --mobile builds in:
#   cd mobile; $HOME/flutter/bin/flutter build apk --debug \
#     --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
# The camera phone gets the tunnel only; its edge app is given
# http://127.0.0.1:8000/api/v1 as its server once, at set-up.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${SABAYGO_BACKEND_PORT:-8000}"
APK="$ROOT/mobile/build/app/outputs/flutter-apk/app-debug.apk"
APP=com.example.mobile_v2_uv_express
INSTALL=1; [ "${1:-}" = "--tunnel" ] && INSTALL=0

ADB=""
for cand in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk "$HOME/Android/Sdk"; do
  [ -n "$cand" ] && [ -x "$cand/platform-tools/adb" ] && { ADB="$cand/platform-tools/adb"; break; }
done
[ -n "$ADB" ] || ADB="$(command -v adb || true)"
[ -n "$ADB" ] || { echo "adb not found: install platform-tools" >&2; exit 1; }
if [ "${1:-}" = "--watch" ]; then
  echo "$(date +%T) watching: each phone's tunnel is reopened after a reset (Ctrl-C stops)"
  while true; do
    for serial in $("$ADB" devices | awk 'NR > 1 && $2 == "device" {print $1}'); do
      "$ADB" -s "$serial" reverse --list 2>/dev/null | grep -q "tcp:$PORT" && continue
      if "$ADB" -s "$serial" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null 2>&1; then
        echo "$(date +%T) $serial: tunnel reopened"
      fi
    done
    sleep 3
  done
fi

[ "$INSTALL" = 0 ] || [ -f "$APK" ] || { echo "no APK at ${APK#$ROOT/}: build it first (see the top of this script)" >&2; exit 1; }

found=0
while read -r serial state; do
  [ -n "$serial" ] || continue
  found=1
  if [ "$state" != device ]; then
    echo "$serial: $state -- unlock the phone and allow USB debugging, then run this again"
    continue
  fi
  model="$("$ADB" -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  if ! "$ADB" -s "$serial" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null; then
    echo "$serial ($model): the tunnel failed -- replug the cable and run this again"
    continue
  fi
  if "$ADB" -s "$serial" shell pm list packages com.sabaygo.edge 2>/dev/null | grep -q edge; then
    echo "$serial ($model): camera phone, tunnel open"
    continue
  fi
  if [ "$INSTALL" = 1 ]; then
    if ! "$ADB" -s "$serial" install -r "$APK" >/dev/null 2>&1; then
      echo "$serial ($model): tunnel open, but the app would not install -- unlock it and allow 'Install via USB'"
      continue
    fi
    "$ADB" -s "$serial" shell monkey -p "$APP" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    echo "$serial ($model): tunnel open, app installed and opened"
  else
    echo "$serial ($model): tunnel open"
  fi
done < <("$ADB" devices | awk 'NR > 1 && NF >= 2 {print $1, $2}')

[ "$found" = 1 ] || echo "no phone attached (adb devices is empty): plug one in"
