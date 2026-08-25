#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
TRADES="${TRADES:-10000}"
TARGET_TRADE_TPS="${TARGET_TRADE_TPS:-1000}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MARKET_ID="${MARKET_ID:-TRADE_FANOUT_$(date +%Y%m%d_%H%M%S)}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JARS="${BUILD_JARS:-true}"
OUTPUT="${REPORT_DIR}/trade-consumer-fanout-${RUN_ID}.json"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"

find_service_jar() {
  local repo="$1"
  find "${ROOT_DIR}/${repo}/build/libs" -maxdepth 1 -type f \
    -name "${repo}-*.jar" \
    ! -name "*-plain.jar" \
    ! -name "*-stubs.jar" \
    | sort \
    | head -n 1
}

stop_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${pid_file}"
  fi
}

cleanup() {
  stop_pid "${LOG_DIR}/eap-order.pid"
  stop_pid "${LOG_DIR}/eap-wallet.pid"
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -f "${COMPOSE_FILE}" stop order-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_healthy() {
  local container="$1"
  local deadline=$(( $(date +%s) + 60 ))
  until [[ "$(docker inspect --format '{{.State.Health.Status}}' "${container}" 2>/dev/null || true)" == "healthy" ]]; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] ${container} did not become healthy" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_http() {
  local service="$1"
  local url="$2"
  local log_file="$3"
  local pid_file="$4"
  local deadline=$(( $(date +%s) + 120 ))
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
      echo "[ERROR] ${service} did not become ready: ${url}" >&2
      tail -n 100 "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
}

start_service() {
  local repo="$1"
  local health_url="$2"
  shift 2
  local jar
  local log_file="${LOG_DIR}/${repo}.log"
  local pid_file="${LOG_DIR}/${repo}.pid"
  jar="$(find_service_jar "${repo}")"
  if [[ -z "${jar}" ]]; then
    echo "[ERROR] executable jar missing for ${repo}" >&2
    exit 1
  fi
  java -jar "${jar}" --spring.profiles.active=loadtest "$@" >"${log_file}" 2>&1 &
  echo "$!" >"${pid_file}"
  wait_http "${repo}" "${health_url}" "${log_file}" "${pid_file}"
}

run_generator() {
  local phase="$1"
  local target_tps="$2"
  local output_args=()
  if [[ "${phase}" == "downstream-run" ]]; then
    output_args=(--output "${OUTPUT}")
  fi
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoad \
      --args="--phase ${phase} --market-id ${MARKET_ID} --events ${TRADES} --target-tps ${target_tps} --timeout-seconds ${TIMEOUT_SECONDS} ${output_args[*]}"
  )
}

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true

echo "[INFO] starting only RabbitMQ and the Order/Wallet PostgreSQL instances"
docker compose -f "${COMPOSE_FILE}" up -d rabbitmq order-postgres wallet-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-wallet-postgres-loadtest

echo "[INFO] purging retained RabbitMQ messages before consumers start"
RABBIT_CONTAINER=eap-rabbitmq-loadtest bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

if [[ "${BUILD_JARS}" == "true" ]]; then
  echo "[INFO] building only Order and Wallet executable jars"
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
  )
  (
    cd "${ROOT_DIR}/eap-wallet"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
  )
else
  echo "[INFO] reusing existing Order and Wallet executable jars"
fi

start_service eap-order http://localhost:8080/eap-order/actuator/health \
  --eap.scheduling.enabled=false \
  --eap.order-projection.enabled=false \
  --eap.order.market-data-scheduler.enabled=false \
  --eap.rate-limit.enabled=false \
  --management.health.redis.enabled=false
start_service eap-wallet http://localhost:8081/eap-wallet/actuator/health \
  --eap.wallet.outbox-relay.enabled=false

echo "[INFO] seeding legal Order and Wallet state; trades=${TRADES}, marketId=${MARKET_ID}"
run_generator downstream-seed 0

echo "[INFO] publishing TradeExecuted at target=${TARGET_TRADE_TPS} events/s"
run_generator downstream-run "${TARGET_TRADE_TPS}"

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  measurementBoundary,
  trades,
  targetTradeEventsPerSecond,
  publisherConfirmedEventsPerSecond,
  orderApplicationsPerSecond,
  walletSettlementsPerSecond,
  durableFanoutTradesPerSecond,
  fanoutConvergedTradesPerSecond,
  orderQueueMax,
  walletQueueMax,
  dlqMax,
  correctnessGate,
  capacityClaimAllowed
}' "${OUTPUT}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${OUTPUT}" >/dev/null
echo "[INFO] readable report=${OUTPUT%.json}-report.md"
