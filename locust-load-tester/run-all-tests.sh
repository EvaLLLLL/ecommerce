#!/bin/bash
# Run Locust load tests.
#
# Mode A (continuous stair-step, default):
#   ./run-all-tests.sh
#   Runs one Locust process with a LoadTestShape so users do not reset between steps.
#
# Mode B (legacy/custom rounds):
#   ./run-all-tests.sh "400:20:300" "800:20:300" "1200:20:300" "1500:20:300"
#   Each arg = "users:spawn_rate:duration_seconds"
#
# Mode C (fixed-duration rounds via env, no args):
#   MODE=rounds USER_STEPS="400,800,1200,1500" STEP_DURATION=300 SPAWN_RATE=20 ./run-all-tests.sh
#
# Optional env vars:
#   HOST             - target URL (default: from terraform output)
#   PROCESSES        - locust worker count (default: 4)
#   OUTDIR           - output directory (default: reports-r5)
#   MODE             - shape (default) | rounds
#   SPAWN_RATE       - default spawn rate for step mode (default: 20)
#   STEP_DURATION    - seconds per step in step mode (default: 600)
#   USER_STEPS       - comma-separated user steps for step mode (default: 400,800,1200,1500)
#   EXPORT_METRICS   - set to 1 to call ./export-aws-metrics.sh after each round
#   METRICS_OUTDIR   - metrics output directory base (default: metrics-runs)
set -euo pipefail

cd "$(dirname "$0")"

PROCESSES="${PROCESSES:-4}"
OUTDIR="${OUTDIR:-reports-after-2}"
MODE="${MODE:-shape}"
SPAWN_RATE="${SPAWN_RATE:-10}"
STEP_DURATION="${STEP_DURATION:-600}"
USER_STEPS="${USER_STEPS:-400,800,1200,1500}"
EXPORT_METRICS="${EXPORT_METRICS:-0}"
METRICS_OUTDIR="${METRICS_OUTDIR:-metrics-after-2}"

if [[ -z "${HOST:-}" ]]; then
  HOST="http://$(cd ../terraform && terraform output -raw alb_dns_name 2>/dev/null || true)"
  if [[ "$HOST" == "http://" ]]; then
    echo "ERROR: Could not detect ALB DNS. Set HOST env var manually."
    exit 1
  fi
fi

# Build round specs from env for MODE=rounds with no args.
IFS=',' read -r -a STEP_USERS <<< "$USER_STEPS"
DEFAULT_ROUNDS=()
for u in "${STEP_USERS[@]}"; do
  trimmed="${u//[[:space:]]/}"
  [[ -z "$trimmed" ]] && continue
  DEFAULT_ROUNDS+=("${trimmed}:${SPAWN_RATE}:${STEP_DURATION}")
done

mkdir -p "$OUTDIR"

echo "========== Load Test Started: $(date) =========="
echo "HOST=$HOST  PROCESSES=$PROCESSES  OUTDIR=$OUTDIR  MODE=$MODE"
echo ""

if [[ "$MODE" == "shape" ]]; then
  if [[ $# -gt 0 ]]; then
    echo "ERROR: MODE=shape does not accept round args. Use MODE=rounds for per-round specs."
    exit 1
  fi

  LAST_USERS="${STEP_USERS[${#STEP_USERS[@]}-1]}"
  TOTAL_RUNTIME=$(( STEP_DURATION * ${#STEP_USERS[@]} ))
  CSV_PREFIX="$OUTDIR/csv-shape-${LAST_USERS}u"
  HTML_REPORT="$OUTDIR/report-shape-${LAST_USERS}u.html"

  echo "[$(date)] Continuous stair-step: users=${USER_STEPS}, step=${STEP_DURATION}s, total=${TOTAL_RUNTIME}s, ramp=${SPAWN_RATE}/s"
  LOCUST_USE_STAIR_SHAPE=1 STEP_USERS="$USER_STEPS" STEP_DURATION="$STEP_DURATION" STEP_SPAWN_RATE="$SPAWN_RATE" \
    locust --headless --processes "$PROCESSES" \
      --run-time "${TOTAL_RUNTIME}s" \
      --html "$HTML_REPORT" \
      --csv "$CSV_PREFIX" \
      --host "$HOST"

  if [[ "$EXPORT_METRICS" == "1" ]]; then
    RUN_METRICS_DIR="${METRICS_OUTDIR}/shape-${LAST_USERS}u"
    mkdir -p "$RUN_METRICS_DIR"
    echo "[$(date)] Exporting AWS metrics to ${RUN_METRICS_DIR} ..."
    ./export-aws-metrics.sh "$RUN_METRICS_DIR"
  fi
else
  if [[ $# -eq 0 ]]; then
    set -- "${DEFAULT_ROUNDS[@]}"
  fi
  echo "ROUNDS: $*"
  echo ""

  ROUND=1
  for spec in "$@"; do
    IFS=':' read -r USERS RATE DURATION <<< "$spec"
    if [[ -z "${USERS:-}" || -z "${RATE:-}" || -z "${DURATION:-}" ]]; then
      echo "ERROR: Invalid round spec '$spec'. Expected users:spawn_rate:duration_seconds"
      exit 1
    fi
    echo "[$(date)] Round $ROUND: ${USERS} users, ramp ${RATE}/s, ${DURATION}s"

    locust --headless --processes "$PROCESSES" \
      -u "$USERS" --spawn-rate "$RATE" --run-time "${DURATION}s" \
      --html "$OUTDIR/report-${USERS}u.html" \
      --csv "$OUTDIR/csv-${USERS}u" \
      --host "$HOST"

    echo "[$(date)] Round $ROUND done."
    if [[ "$EXPORT_METRICS" == "1" ]]; then
      RUN_METRICS_DIR="${METRICS_OUTDIR}/round-${ROUND}-${USERS}u"
      mkdir -p "$RUN_METRICS_DIR"
      echo "[$(date)] Exporting AWS metrics to ${RUN_METRICS_DIR} ..."
      ./export-aws-metrics.sh "$RUN_METRICS_DIR"
    fi
    echo ""
    ROUND=$((ROUND + 1))
  done
fi

echo "========== All Tests Completed: $(date) =========="
