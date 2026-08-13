#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"

if (( $# > 1 )); then
  echo "usage: $0 [RUN_ID]" >&2
  exit 2
fi

TARGET_TPS="${TARGET_TPS:-2000}"
EVENTS="${EVENTS:-10000}"
USERS_PER_SIDE="${USERS_PER_SIDE:-500}"
WORKERS=128
MAX_IN_FLIGHT=256
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
RUN_ID="${RUN_ID:-${1:-GLT_$(date +%Y%m%d_%H%M%S)_HTTP_MATCHED_TRADE_COMPLETION_10K}}"
MARKET_ID="${MARKET_ID:-ENERGY-SPOT}"
ORDER_URL="${ORDER_URL:-http://localhost:8080/eap-order}"
WALLET_URL="${WALLET_URL:-http://localhost:8081/eap-wallet}"
ORDER_JDBC_URL="${ORDER_JDBC_URL:-jdbc:postgresql://localhost:15432/eap_order_db}"
WALLET_JDBC_URL="${WALLET_JDBC_URL:-jdbc:postgresql://localhost:15433/eap_wallet_db}"
MATCH_JDBC_URL="${MATCH_JDBC_URL:-jdbc:postgresql://localhost:15434/eap_match_db}"
JDBC_USER="${JDBC_USER:-admin}"
JDBC_PASSWORD="${JDBC_PASSWORD:-admin123}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
RABBIT_MANAGEMENT_URL="${RABBIT_MANAGEMENT_URL:-http://localhost:15672}"
RABBIT_VHOST="${RABBIT_VHOST:-/}"
RABBIT_USER="${RABBIT_USER:-admin}"
RABBIT_PASSWORD="${RABBIT_PASSWORD:-admin123}"
START_SERVICES="${START_SERVICES:-true}"
STOP_SERVICES_AFTER_RUN="${STOP_SERVICES_AFTER_RUN:-${START_SERVICES}}"
ASSERT_LOADTEST_ENVIRONMENT="${ASSERT_LOADTEST_ENVIRONMENT:-true}"
FLUSH_REDIS_ON_RESET=true
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-1}"
LOADTEST_RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
LOADTEST_REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER:-eap-redis-loadtest}"
LOADTEST_SERVICE_LAUNCH_MODE="${LOADTEST_SERVICE_LAUNCH_MODE:-boot-run}"
LOADTEST_SERVICE_JAVA_BIN="${LOADTEST_SERVICE_JAVA_BIN:-java}"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/http-matched-trade-completion-${RUN_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/http-matched-trade-completion-${RUN_ID}-result.json"
RUN_DIAG_DIR="${REPORT_DIR}/http-matched-trade-completion-${RUN_ID}-diagnostics"
DIAG_SAMPLER_PID=""

cleanup() {
  http_matched_stop_diagnostics
  http_matched_stop_services
}
trap cleanup EXIT

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the standard HTTP matched-trade completion run uses 10000 trades." >&2
fi
http_matched_validate_common

http_matched_assert_environment
http_matched_start_services

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"

echo "[INFO] HTTP matched-trade completion chain"
echo "[INFO] runId=${RUN_ID}, trades=${EVENTS}, offeredHttpOrders=$((EVENTS * 2))"
echo "[INFO] targetOrderTpsPerPhase=${TARGET_TPS}, usersPerSide=${USERS_PER_SIDE}, workers=${WORKERS}, maxInFlight=${MAX_IN_FLIGHT}"
echo "[INFO] serviceLaunchMode=${LOADTEST_SERVICE_LAUNCH_MODE}, report=${RUN_REPORT_JSON}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, diagnostics=${RUN_DIAG_DIR}"

http_matched_start_diagnostics
http_matched_export_generator_environment
cd "${ROOT_DIR}/eap-order"
run_status=0
set +e
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon httpMatchedTradeCompletionLoadTest \
  --args="--run-id ${RUN_ID} \
  --market-id ${MARKET_ID} \
  --events ${EVENTS} \
  --target-tps ${TARGET_TPS} \
  --users-per-side ${USERS_PER_SIDE} \
  --workers ${WORKERS} \
  --max-in-flight ${MAX_IN_FLIGHT} \
  --wait-timeout-seconds ${WAIT_TIMEOUT_SECONDS} \
  --order-url ${ORDER_URL} \
  --wallet-url ${WALLET_URL} \
  --order-jdbc-url ${ORDER_JDBC_URL} \
  --wallet-jdbc-url ${WALLET_JDBC_URL} \
  --match-jdbc-url ${MATCH_JDBC_URL} \
  --jdbc-user ${JDBC_USER} \
  --redis-host ${REDIS_HOST} \
  --redis-port ${REDIS_PORT} \
  --rabbit-management-url ${RABBIT_MANAGEMENT_URL} \
  --rabbit-vhost ${RABBIT_VHOST} \
  --rabbit-user ${RABBIT_USER} \
  --flush-redis-on-reset ${FLUSH_REDIS_ON_RESET}" | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e
http_matched_stop_diagnostics
http_matched_collect_after_run_diagnostics

persist_status=0
http_matched_persist_result "${run_status}" "http-matched-trade-completion-chain" || persist_status=$?
if (( run_status == 0 && persist_status != 0 )); then
  run_status="${persist_status}"
fi
exit "${run_status}"
