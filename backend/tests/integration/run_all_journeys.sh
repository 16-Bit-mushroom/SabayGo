#!/usr/bin/env bash
# Run every role journey and write a plain-text report.
#
#   ./tests/integration/run_all_journeys.sh
#   ./tests/integration/run_all_journeys.sh --quiet     (file only, no console)
#
# Output goes to docs/test-reports/journeys_<timestamp>.txt with ANSI colour
# stripped -- escape codes written literally into a file turn every PASS into
# "^[[32mPASS^[[0m", which is unreadable in a manuscript appendix. The
# console still gets colour, via tee.
set -uo pipefail
cd "$(dirname "$0")/../.."

REPORT_DIR="../docs/test-reports"
mkdir -p "$REPORT_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$REPORT_DIR/journeys_${STAMP}.txt"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[mGKHfJ]//g'; }

# ── header ────────────────────────────────────────────────────────────
{
  echo "==================================================================="
  echo "  SabayGo - Role Journey Test Report"
  echo "==================================================================="
  echo
  echo "  Generated : $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  Host      : $(hostname)"
  echo "  Git       : $(git rev-parse --short HEAD 2>/dev/null || echo n/a) on $(git branch --show-current 2>/dev/null || echo n/a)"
  echo "  API       : http://127.0.0.1:8000"
  echo
  echo "  Legend"
  echo "    PASS  assertion held"
  echo "    FAIL  regression - something that worked is now broken"
  echo "    GAP   endpoint not built yet (a checklist item, not a defect)"
  echo
  echo "-------------------------------------------------------------------"
} | tee "$REPORT"

# ── preflight ─────────────────────────────────────────────────────────
{
  echo
  echo "PREFLIGHT"
  if curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "  ok    API responding"
  else
    echo "  STOP  API not running - start: uvicorn app.main:app --reload"
  fi
  if curl -sf http://127.0.0.1:5000/health >/dev/null 2>&1; then
    echo "  ok    AI node responding"
  else
    echo "  warn  AI node offline - audit steps will report GAP"
  fi
} | tee -a "$REPORT"

if grep -q "STOP" "$REPORT"; then
  echo
  echo "Aborted. See $REPORT"
  exit 1
fi

# ── journeys ──────────────────────────────────────────────────────────
# Each journey gets a clean database: the conductor script departs the
# trip and the passenger script consumes seats, so shared state produces
# failures that look like bugs but are really ordering.
for journey in passenger conductor driver_operator; do
  label=$(echo "$journey" | tr '[:lower:]_' '[:upper:] ')
  {
    echo
    echo "==================================================================="
    echo "  ${label} JOURNEY"
    echo "==================================================================="
  } | tee -a "$REPORT"

  ( cd .. && ./db/reset-dev.sh --soon >/dev/null 2>&1 ) || \
  ( cd .. && ./db/reset-dev.sh >/dev/null 2>&1 )

  if [ "$QUIET" = "1" ]; then
    ./tests/integration/test_${journey}_journey.sh 2>&1 | strip_ansi >> "$REPORT"
  else
    ./tests/integration/test_${journey}_journey.sh 2>&1 \
      | tee >(strip_ansi >> "$REPORT")
  fi
done

sleep 1   # let the tee subshells finish flushing before counting

# ── totals ────────────────────────────────────────────────────────────
P=$(grep -c '^  PASS' "$REPORT" || true)
F=$(grep -c '^  FAIL' "$REPORT" || true)
G=$(grep -c '^  GAP'  "$REPORT" || true)

{
  echo
  echo "==================================================================="
  echo "  TOTALS"
  echo "==================================================================="
  printf "    passed   %3d\n" "$P"
  printf "    failed   %3d\n" "$F"
  printf "    gaps     %3d\n" "$G"
  echo
  if [ "$F" -eq 0 ]; then
    echo "  No regressions. A failure-free run means role boundaries, policy"
    echo "  enforcement and state transitions all held."
  else
    echo "  ${F} regression(s) - review the FAIL lines above."
  fi
  if [ "$G" -gt 0 ]; then
    echo
    echo "  Unbuilt endpoints flagged this run:"
    grep '^  GAP' "$REPORT" | sed 's/^  GAP  /    - /' | sort -u
  fi
  echo
} | tee -a "$REPORT"

echo "Report written to: $(cd "$REPORT_DIR" && pwd)/$(basename "$REPORT")"
