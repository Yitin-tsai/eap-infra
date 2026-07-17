#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
LOCK_DIR="${ROOT_DIR}/.loadtest-lock/global-matched-e2e.lock"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"

EVENTS="${EVENTS:-1000}"
PUBLISHERS="${PUBLISHERS:-32}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
TARGET_TPS="${TARGET_TPS:-0}"
DURATION_SECONDS="${DURATION_SECONDS:-0}"
MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO:-0.95}"
PHASE="${PHASE:-all}"
MARKET_ID="${MARKET_ID:-GLOBAL_LOADTEST_$(date +%Y%m%d_%H%M%S)}"
REPORT_FILE="${REPORT_DIR}/matched-e2e-${MARKET_ID}.log"

mkdir -p "$(dirname "${LOCK_DIR}")" "${REPORT_DIR}"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "[ERROR] another global matched E2E load test appears to be running: ${LOCK_DIR}" >&2
  echo "[ERROR] remove the lock only after confirming no Gradle/loadtest process is active." >&2
  exit 2
fi

cleanup() {
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cd "${ROOT_DIR}/eap-order"
echo "[INFO] marketId=${MARKET_ID}"
echo "[INFO] report=${REPORT_FILE}"
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoadTest --args="--phase ${PHASE} --events ${EVENTS} --publishers ${PUBLISHERS} --timeout-seconds ${TIMEOUT_SECONDS} --market-id ${MARKET_ID} --target-tps ${TARGET_TPS} --duration-seconds ${DURATION_SECONDS} --min-offered-load-ratio ${MIN_OFFERED_LOAD_RATIO}" | tee "${REPORT_FILE}"
