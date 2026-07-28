#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

RUN_PREFIX="${1:-EAP_PUBLIC_10K_$(date +%Y%m%d_%H%M%S)}"

REPEATS="${REPEATS:-5}"
TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-5}"
EVENTS="${EVENTS:-10000}"
PUBLISHERS="${PUBLISHERS:-1}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-baseline}"
MIN_OFFERED_TPS_RATIO="${MIN_OFFERED_TPS_RATIO:-0.95}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-true}"

if (( REPEATS < 5 )); then
  echo "[ERROR] public benchmark requires REPEATS >= 5." >&2
  exit 2
fi

if [[ "${DIAGNOSTICS_LEVEL}" != "baseline" && "${DIAGNOSTICS_LEVEL}" != "light" ]]; then
  echo "[ERROR] public benchmark should use baseline/light diagnostics; got DIAGNOSTICS_LEVEL=${DIAGNOSTICS_LEVEL}." >&2
  exit 2
fi

echo "[INFO] public 10k matched-trade-completion-chain benchmark repeat"
echo "[INFO] runPrefix=${RUN_PREFIX}"
echo "[INFO] repeats=${REPEATS}, targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, minOfferedTpsRatio=${MIN_OFFERED_TPS_RATIO}"

REPEATS="${REPEATS}" \
TARGET_TPS="${TARGET_TPS}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
EVENTS="${EVENTS}" \
PUBLISHERS="${PUBLISHERS}" \
TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
MIN_OFFERED_TPS_RATIO="${MIN_OFFERED_TPS_RATIO}" \
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
  bash "${ROOT_DIR}/scripts/load-test/run-matched-trade-completion-repeat.sh" "${RUN_PREFIX}"
