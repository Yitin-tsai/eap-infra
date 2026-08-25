#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
PAIRS="${PAIRS:-10000}"
TARGET_ORDER_TPS="${TARGET_ORDER_TPS:-2000}"
WORKLOAD_SEED="${WORKLOAD_SEED:-20260814}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
OUTPUT="${REPORT_DIR}/rabbit-match-intake-${RUN_ID}.json"

mkdir -p "${REPORT_DIR}" "${GRADLE_USER_HOME_DIR}"

cleanup() {
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -f "${COMPOSE_FILE}" stop match-postgres redis rabbitmq >/dev/null 2>&1 || true
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

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true

echo "[INFO] starting only RabbitMQ, MatchEngine PostgreSQL, and Redis"
docker compose -f "${COMPOSE_FILE}" up -d rabbitmq match-postgres redis
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-match-postgres-loadtest
wait_for_healthy eap-redis-loadtest

echo "[INFO] pairs=${PAIRS}, targetOrderTps=${TARGET_ORDER_TPS}, seed=${WORKLOAD_SEED}"
(
  cd "${ROOT_DIR}/eap-matchEngine"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon rabbitMatchIntakeProbe \
    --args="--pairs ${PAIRS} --target-order-tps ${TARGET_ORDER_TPS} --seed ${WORKLOAD_SEED} --timeout-seconds ${TIMEOUT_SECONDS} --output ${OUTPUT}"
)

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  arrivalPattern,
  targetOrderTps,
  offeredOrdersPerSecond,
  persistedOrdersPerSecond,
  persistedTradesPerSecond,
  cleanupConvergedTradesPerSecond,
  queueMaxReady,
  queueMaxUnacked,
  listenerMeanMs,
  tradeTransactionMeanMs,
  correctness,
  capacityClaimAllowed
}' "${OUTPUT}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${OUTPUT}" >/dev/null
echo "[INFO] readable report=${OUTPUT%.json}-report.md"
