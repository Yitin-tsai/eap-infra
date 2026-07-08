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
PUBLISHERS="${PUBLISHERS:-128}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-true}"
RUN_MODE="${RUN_MODE:-prepare-run}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-baseline}"
MARKET_ID="${MARKET_ID:-${1:-GLT_$(date +%Y%m%d)_MARKER_10K}}"

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the 2000 TPS ticket marker probe is normally EVENTS=10000." >&2
fi

MARKET_ID="${MARKET_ID}" \
EVENTS="${EVENTS}" \
TARGET_TPS="${TARGET_TPS}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
PUBLISHERS="${PUBLISHERS}" \
TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
RUN_MODE="${RUN_MODE}" \
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
  bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e-sustained.sh"
