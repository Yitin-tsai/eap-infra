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
WORKERS="${WORKERS:-128}"
MAX_IN_FLIGHT="${MAX_IN_FLIGHT:-$((WORKERS * 2))}"
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
FLUSH_REDIS_ON_RESET="${FLUSH_REDIS_ON_RESET:-true}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-1}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-false}"
WALLET_JFR_ENABLED="${WALLET_JFR_ENABLED:-false}"
WALLET_JFR_SETTINGS="${WALLET_JFR_SETTINGS:-profile}"
WALLET_JFR_MAX_SIZE="${WALLET_JFR_MAX_SIZE:-512m}"
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
WALLET_JFR_PID=""
WALLET_JFR_RECORDING_NAME="eap-wallet-loadtest"
WALLET_JFR_FILE="${RUN_DIAG_DIR}/wallet.jfr"

start_wallet_jfr() {
  if [[ "${WALLET_JFR_ENABLED}" != "true" ]]; then
    return 0
  fi
  if ! command -v jcmd >/dev/null 2>&1; then
    echo "[ERROR] WALLET_JFR_ENABLED=true requires jcmd on PATH" >&2
    return 1
  fi

  mkdir -p "${RUN_DIAG_DIR}"
  WALLET_JFR_PID="$(lsof -nP -tiTCP:8081 -sTCP:LISTEN | head -n 1)"
  if [[ -z "${WALLET_JFR_PID}" ]]; then
    echo "[ERROR] could not resolve Wallet JVM PID from listening port 8081" >&2
    return 1
  fi

  rm -f "${WALLET_JFR_FILE}"
  echo "[INFO] starting Wallet JFR pid=${WALLET_JFR_PID}, settings=${WALLET_JFR_SETTINGS}, file=${WALLET_JFR_FILE}"
  jcmd "${WALLET_JFR_PID}" JFR.start \
    "name=${WALLET_JFR_RECORDING_NAME}" \
    "settings=${WALLET_JFR_SETTINGS}" \
    "filename=${WALLET_JFR_FILE}" \
    "maxsize=${WALLET_JFR_MAX_SIZE}" \
    dumponexit=true > "${RUN_DIAG_DIR}/wallet-jfr-start.txt"
}

stop_wallet_jfr() {
  if [[ -z "${WALLET_JFR_PID}" ]]; then
    return 0
  fi

  if kill -0 "${WALLET_JFR_PID}" >/dev/null 2>&1; then
    jcmd "${WALLET_JFR_PID}" JFR.stop \
      "name=${WALLET_JFR_RECORDING_NAME}" > "${RUN_DIAG_DIR}/wallet-jfr-stop.txt" 2>&1 || true
  fi
  WALLET_JFR_PID=""

  if [[ ! -s "${WALLET_JFR_FILE}" ]]; then
    echo "[WARN] Wallet JFR recording was not written: ${WALLET_JFR_FILE}" >&2
    return 0
  fi
  if ! command -v jfr >/dev/null 2>&1; then
    echo "[WARN] jfr CLI unavailable; keeping raw recording without text views" >&2
    return 0
  fi

  jfr summary "${WALLET_JFR_FILE}" > "${RUN_DIAG_DIR}/wallet-jfr-summary.txt" 2>&1 || true
  for view in \
    hot-methods \
    allocation-by-class \
    allocation-by-site \
    contention-by-class \
    contention-by-site \
    cpu-load \
    thread-cpu-load \
    socket-reads-by-host; do
    jfr view --width 200 "${view}" "${WALLET_JFR_FILE}" \
      > "${RUN_DIAG_DIR}/wallet-jfr-${view}.txt" 2>&1 || true
  done
  echo "[INFO] Wallet JFR reports written to ${RUN_DIAG_DIR}"
}

reset_pg_stats() {
  if [[ "${RESET_PG_STATS_BEFORE_RUN}" != "true" ]]; then
    return 0
  fi
  echo "[INFO] resetting PostgreSQL diagnostic statistics"
  DIAG_DIR="${RUN_DIAG_DIR}" \
    MARKET_ID="${MARKET_ID}" \
    DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" reset || true
}

cleanup() {
  http_matched_stop_diagnostics
  stop_wallet_jfr
  http_matched_stop_services
}
trap cleanup EXIT

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the standard HTTP matched-trade completion run uses 10000 trades." >&2
fi
http_matched_validate_common
case "${WALLET_JFR_ENABLED}" in
  true|false)
    ;;
  *)
    echo "[ERROR] WALLET_JFR_ENABLED must be true or false" >&2
    exit 2
    ;;
esac

http_matched_assert_environment
http_matched_start_services

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"

echo "[INFO] HTTP matched-trade completion chain"
echo "[INFO] runId=${RUN_ID}, trades=${EVENTS}, offeredHttpOrders=$((EVENTS * 2))"
echo "[INFO] targetOrderTpsPerPhase=${TARGET_TPS}, usersPerSide=${USERS_PER_SIDE}, workers=${WORKERS}, maxInFlight=${MAX_IN_FLIGHT}"
echo "[INFO] walletTradeConcurrency=${EAP_WALLET_TRADE_EXECUTED_CONCURRENCY:-8}, walletTradeSettlementMode=single-event"
echo "[INFO] serviceLaunchMode=${LOADTEST_SERVICE_LAUNCH_MODE}, report=${RUN_REPORT_JSON}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, diagnostics=${RUN_DIAG_DIR}"
echo "[INFO] walletJfrEnabled=${WALLET_JFR_ENABLED}, walletJfrSettings=${WALLET_JFR_SETTINGS}, walletJfrMaxSize=${WALLET_JFR_MAX_SIZE}"

reset_pg_stats
http_matched_start_diagnostics
start_wallet_jfr
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
stop_wallet_jfr
http_matched_collect_after_run_diagnostics

http_matched_persist_result
exit "${run_status}"
