#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"

RUN_ID="${RUN_ID:-CANCELLATION_LIFECYCLE_$(date +%Y%m%d_%H%M%S)}"
MARKET_ID="ENERGY-SPOT"
ORDER_URL="${ORDER_URL:-http://localhost:8080/eap-order}"
WALLET_URL="${WALLET_URL:-http://localhost:8081/eap-wallet}"
MATCH_URL="${MATCH_URL:-http://localhost:8082/match-engine}"
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
LOADTEST_RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
LOADTEST_REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER:-eap-redis-loadtest}"
LOADTEST_SERVICE_LAUNCH_MODE="${LOADTEST_SERVICE_LAUNCH_MODE:-jar}"
LOADTEST_SERVICE_JAVA_BIN="${LOADTEST_SERVICE_JAVA_BIN:-java}"
LOADTEST_DRIVER_JAVA_BIN="${LOADTEST_DRIVER_JAVA_BIN:-java}"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
FLUSH_REDIS_ON_RESET=true
START_SERVICES=true
STOP_SERVICES_AFTER_RUN=true
ASSERT_LOADTEST_ENVIRONMENT=true
DIAGNOSTICS_LEVEL=none
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
RACE_ITERATIONS="${RACE_ITERATIONS:-10}"
STOP_INFRA_AFTER_RUN="${STOP_INFRA_AFTER_RUN:-true}"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/http-cancellation-${RUN_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/http-cancellation-${RUN_ID}-result.json"

cleanup() {
  http_matched_cleanup
  if [[ "${STOP_INFRA_AFTER_RUN}" == "true" ]]; then
    docker compose -f "${ROOT_DIR}/docker-compose.loadtest.yml" down >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"
docker compose -f "${ROOT_DIR}/docker-compose.loadtest.yml" up -d --wait --wait-timeout 120
http_matched_assert_environment
http_matched_start_services
http_matched_export_generator_environment

args="--run-id ${RUN_ID} \
--order-url ${ORDER_URL} \
--wallet-url ${WALLET_URL} \
--match-url ${MATCH_URL} \
--order-jdbc-url ${ORDER_JDBC_URL} \
--wallet-jdbc-url ${WALLET_JDBC_URL} \
--match-jdbc-url ${MATCH_JDBC_URL} \
--jdbc-user ${JDBC_USER} \
--rabbit-management-url ${RABBIT_MANAGEMENT_URL} \
--rabbit-user ${RABBIT_USER} \
--timeout-seconds ${TIMEOUT_SECONDS} \
--race-iterations ${RACE_ITERATIONS}"

run_status=0
set +e
(
  cd "${ROOT_DIR}/eap-order"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon httpCancellationLifecycleLoadTest \
    --args="${args}"
) 2>&1 | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e

if ! http_matched_extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
  echo "[ERROR] cancellation lifecycle did not emit a result JSON" >&2
  exit 2
fi
echo "[INFO] cancellation lifecycle result=${RUN_REPORT_JSON}"
exit "${run_status}"
