#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
TRADES="${TRADES:-10000}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MARKET_ID="${MARKET_ID:-MATCH_RELAY_DOWNSTREAM_$(date +%Y%m%d_%H%M%S)}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JARS="${BUILD_JARS:-true}"
OUTPUT="${REPORT_DIR}/match-relay-downstream-${RUN_ID}.json"

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
  stop_pid "${LOG_DIR}/eap-matchEngine.pid"
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -f "${COMPOSE_FILE}" stop \
      order-postgres wallet-postgres match-postgres rabbitmq redis >/dev/null 2>&1 || true
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

start_match_service() {
  local relay_enabled="$1"
  start_service eap-matchEngine http://localhost:8082/match-engine/actuator/health \
    --spring.rabbitmq.listener.simple.auto-startup=false \
    --eap.match-engine.trade-outbox-relay.enabled="${relay_enabled}" \
    --eap.match-engine.trade-checkpoint-relay.enabled=false \
    --eap.match-engine.reservation-cleanup.enabled=false \
    --eap.match-engine.reservation-reconciler.enabled=false
}

run_generator() {
  local phase="$1"
  local output_args=()
  if [[ "${phase}" == "relay-downstream-run" ]]; then
    output_args=(--output "${OUTPUT}")
  fi
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoad \
      --args="--phase ${phase} --market-id ${MARKET_ID} --events ${TRADES} --timeout-seconds ${TIMEOUT_SECONDS} ${output_args[*]}"
  )
}

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true

echo "[INFO] starting RabbitMQ, Redis, and all three PostgreSQL instances"
docker compose -f "${COMPOSE_FILE}" up -d \
  rabbitmq redis order-postgres wallet-postgres match-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-redis-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-wallet-postgres-loadtest
wait_for_healthy eap-match-postgres-loadtest

echo "[INFO] purging retained RabbitMQ messages before consumers start"
RABBIT_CONTAINER=eap-rabbitmq-loadtest bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

if [[ "${BUILD_JARS}" == "true" ]]; then
  echo "[INFO] building Order, Wallet, and MatchEngine executable jars"
  for repo in eap-order eap-wallet eap-matchEngine; do
    (
      cd "${ROOT_DIR}/${repo}"
      GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
    )
  done
else
  echo "[INFO] reusing existing executable jars"
fi

start_service eap-order http://localhost:8080/eap-order/actuator/health \
  --eap.scheduling.enabled=false \
  --eap.order-projection.enabled=false \
  --eap.order.market-data-scheduler.enabled=false \
  --eap.rate-limit.enabled=false \
  --management.health.redis.enabled=false
start_service eap-wallet http://localhost:8081/eap-wallet/actuator/health \
  --eap.wallet.outbox-relay.enabled=false

echo "[INFO] starting MatchEngine once with relay disabled to apply current migrations"
start_match_service false
stop_pid "${LOG_DIR}/eap-matchEngine.pid"

echo "[INFO] seeding durable Match facts/deferred outbox plus legal Order/Wallet state; trades=${TRADES}"
run_generator relay-downstream-seed

echo "[INFO] starting the real Match trade outbox relay"
start_match_service true

echo "[INFO] activating the deferred Match outbox and measuring durable downstream convergence"
run_generator relay-downstream-run

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  measurementBoundary,
  trades,
  matchRelaySentPerSecond,
  orderApplicationsPerSecond,
  walletSettlementsPerSecond,
  downstreamDurableTradesPerSecond,
  durableConvergedTradesPerSecond,
  fullGateTradesPerSecond,
  orderQueueMax,
  walletQueueMax,
  dlqMax,
  correctnessGate,
  capacityClaimAllowed
}' "${OUTPUT}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${OUTPUT}" >/dev/null
echo "[INFO] readable report=${OUTPUT%.json}-report.md"
