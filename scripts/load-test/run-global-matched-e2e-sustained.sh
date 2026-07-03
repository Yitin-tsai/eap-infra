#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-40}"
EVENTS="${EVENTS:-$((TARGET_TPS * DURATION_SECONDS))}"
PUBLISHERS="${PUBLISHERS:-128}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-$((DURATION_SECONDS + 360))}"
MARKET_ID="${MARKET_ID:-GLOBAL_SUSTAINED_${TARGET_TPS}TPS_${EVENTS}_$(date +%Y%m%d_%H%M%S)}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-true}"

if (( TARGET_TPS <= 0 )); then
  echo "[ERROR] TARGET_TPS must be positive for sustained load tests." >&2
  exit 2
fi

EXPECTED_EVENTS=$((TARGET_TPS * DURATION_SECONDS))
if (( EVENTS != EXPECTED_EVENTS )); then
  EXPECTED_WINDOW="$(awk "BEGIN { printf \"%.2f\", ${EVENTS} / ${TARGET_TPS} }")"
  echo "[WARN] EVENTS=${EVENTS} does not equal TARGET_TPS * DURATION_SECONDS (${EXPECTED_EVENTS})." >&2
  echo "[WARN] This run will publish ${EVENTS} BUY trades at ${TARGET_TPS} TPS, so the expected publish window is ${EXPECTED_WINDOW}s, not ${DURATION_SECONDS}s." >&2
fi

echo "[INFO] sustained matched E2E load test"
echo "[INFO] marketId=${MARKET_ID}"
echo "[INFO] targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, publishers=${PUBLISHERS}, timeoutSeconds=${TIMEOUT_SECONDS}"

EVENTS="${EVENTS}" \
PUBLISHERS="${PUBLISHERS}" \
TARGET_TPS="${TARGET_TPS}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
MARKET_ID="${MARKET_ID}" \
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
  bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e-two-phase.sh"
