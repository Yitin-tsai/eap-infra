#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
EVENTS="${EVENTS:-20000}"
TARGET_TPS="${TARGET_TPS:-2000}"
WORKERS="${WORKERS:-128}"
MAX_IN_FLIGHT="${MAX_IN_FLIGHT:-512}"
RUN_ID="${RUN_ID:-DRIVER_$(date +%Y%m%d_%H%M%S)_PREPARED_ASYNC}"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/prepared-http-driver-${RUN_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/prepared-http-driver-${RUN_ID}-result.json"

if (( EVENTS <= 0 || TARGET_TPS <= 0 || WORKERS <= 0 || MAX_IN_FLIGHT <= 0 )); then
  echo "[ERROR] EVENTS, TARGET_TPS, WORKERS, and MAX_IN_FLIGHT must be positive." >&2
  exit 2
fi

echo "[INFO] prepared synchronous HTTP driver calibration"
echo "[INFO] events=${EVENTS}, targetTps=${TARGET_TPS}, workers=${WORKERS}, maxInFlight=${MAX_IN_FLIGHT}"
echo "[INFO] this diagnostic does not start EAP services or Docker containers"
echo "[INFO] result=${RUN_REPORT_JSON}"

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"
cd "${ROOT_DIR}/eap-order"
set +e
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon preparedHttpLoadDriverCalibration \
  --args="--run-id ${RUN_ID} --events ${EVENTS} --target-tps ${TARGET_TPS} --workers ${WORKERS} --max-in-flight ${MAX_IN_FLIGHT}" \
  2>&1 | tee "${RUN_REPORT_LOG}"
status=${PIPESTATUS[0]}
set -e

if http_matched_extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
  echo "[INFO] persisted result JSON=${RUN_REPORT_JSON}"
  http_matched_render_report "${RUN_REPORT_JSON}" || true
else
  echo "[ERROR] could not extract calibration result JSON from ${RUN_REPORT_LOG}" >&2
  exit 1
fi
exit "${status}"
