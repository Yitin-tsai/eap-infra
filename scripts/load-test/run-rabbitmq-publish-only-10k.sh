#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"

TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-5}"
EVENTS="${EVENTS:-10000}"
PUBLISHERS="${PUBLISHERS:-128}"
PUBLISHER_CONNECTION_CACHE_SIZE="${PUBLISHER_CONNECTION_CACHE_SIZE:-16}"
PUBLISHER_MAX_IN_FLIGHT="${PUBLISHER_MAX_IN_FLIGHT:-4096}"
PUBLISHER_CONFIRM_TIMEOUT_MS="${PUBLISHER_CONFIRM_TIMEOUT_MS:-5000}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
MARKET_ID="${MARKET_ID:-GLT_$(date +%Y%m%d)_RABBITMQ_PUBLISH_ONLY_10K}"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/rabbitmq-publish-only-${MARKET_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/rabbitmq-publish-only-${MARKET_ID}-result.json"

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the standard RabbitMQ publish-only probe is normally EVENTS=10000." >&2
fi

echo "[INFO] RabbitMQ publish-only broker-confirm probe"
echo "[INFO] marketId=${MARKET_ID}"
echo "[INFO] targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, publishers=${PUBLISHERS}, publisherConnections=${PUBLISHER_CONNECTION_CACHE_SIZE}"
mkdir -p "${REPORT_DIR}"

run_status=0
set +e
MARKET_ID="${MARKET_ID}" \
EVENTS="${EVENTS}" \
PUBLISHERS="${PUBLISHERS}" \
PUBLISHER_CONNECTION_CACHE_SIZE="${PUBLISHER_CONNECTION_CACHE_SIZE}" \
PUBLISHER_MAX_IN_FLIGHT="${PUBLISHER_MAX_IN_FLIGHT}" \
PUBLISHER_CONFIRM_TIMEOUT_MS="${PUBLISHER_CONFIRM_TIMEOUT_MS}" \
TARGET_TPS="${TARGET_TPS}" \
DURATION_SECONDS="${DURATION_SECONDS}" \
TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
PHASE=publish-only \
  bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e.sh" | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e

if http_matched_extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
  echo "[INFO] persisted result JSON=${RUN_REPORT_JSON}"
  http_matched_render_report "${RUN_REPORT_JSON}" || true
else
  echo "[WARN] RabbitMQ publish-only probe did not emit a result JSON." >&2
fi
exit "${run_status}"
