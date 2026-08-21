#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if (( $# > 1 )); then
  echo "usage: $0 [MARKET_ID]" >&2
  exit 2
fi

TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-5}"
EVENTS="${EVENTS:-10000}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO:-0.95}"
MARKET_ID="${MARKET_ID:-${1:-GLT_$(date +%Y%m%d)_MATCHED_TRADE_COMPLETION_10K}}"

RESET_PG_STATS_BEFORE_RUN=false
if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
  RESET_PG_STATS_BEFORE_RUN=true
fi

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the standard matched-trade completion probe is normally EVENTS=10000." >&2
fi

if (( TARGET_TPS <= 0 )); then
  echo "[ERROR] TARGET_TPS must be positive." >&2
  exit 2
fi

EXPECTED_EVENTS=$((TARGET_TPS * DURATION_SECONDS))
if (( EVENTS != EXPECTED_EVENTS )); then
  EXPECTED_WINDOW="$(awk "BEGIN { printf \"%.2f\", ${EVENTS} / ${TARGET_TPS} }")"
  echo "[WARN] EVENTS=${EVENTS} does not equal TARGET_TPS * DURATION_SECONDS (${EXPECTED_EVENTS})." >&2
  echo "[WARN] Expected publish window is ${EXPECTED_WINDOW}s, not ${DURATION_SECONDS}s." >&2
fi

echo "[INFO] matched-trade-completion-chain"
echo "[INFO] marketId=${MARKET_ID}, targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, timeoutSeconds=${TIMEOUT_SECONDS}"

MARKET_ID="${MARKET_ID}" \
EVENTS="${EVENTS}" \
TARGET_TPS="${TARGET_TPS}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
PUBLISHERS=1 \
TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
RUN_MODE=prepare-run \
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO}" \
  bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e-two-phase.sh"
