#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
PAIRS="${PAIRS:-10000}"
WORKERS="${WORKERS:-12}"
DB_POOL_SIZE="${DB_POOL_SIZE:-35}"
CLEANUP_BATCH_SIZE="${CLEANUP_BATCH_SIZE:-1000}"
LEASE_CHUNK_SIZE="${LEASE_CHUNK_SIZE:-50}"
WORKLOAD_SEED="${WORKLOAD_SEED:-20260814}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
OUTPUT="${REPORT_DIR}/match-processor-${RUN_ID}.json"

mkdir -p "${REPORT_DIR}" "${GRADLE_USER_HOME_DIR}"

cleanup() {
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -f "${COMPOSE_FILE}" stop match-postgres redis >/dev/null 2>&1 || true
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

echo "[INFO] starting only MatchEngine PostgreSQL and Redis"
docker compose -f "${COMPOSE_FILE}" up -d match-postgres redis
wait_for_healthy eap-match-postgres-loadtest
wait_for_healthy eap-redis-loadtest

echo "[INFO] pairs=${PAIRS}, workers=${WORKERS}, dbPoolSize=${DB_POOL_SIZE}, seed=${WORKLOAD_SEED}"
(
  cd "${ROOT_DIR}/eap-matchEngine"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchProcessorLoadProbe \
    --args="--pairs ${PAIRS} --workers ${WORKERS} --db-pool-size ${DB_POOL_SIZE} --cleanup-batch-size ${CLEANUP_BATCH_SIZE} --lease-chunk-size ${LEASE_CHUNK_SIZE} --seed ${WORKLOAD_SEED} --output ${OUTPUT}"
)

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  arrivalPattern,
  totalOrders,
  pairs,
  processedOrdersPerSecond,
  persistedTradesPerSecond,
  cleanupTasksPerSecond,
  orderLatencyP95Ms,
  tradeTransactionMeanMs,
  correctness,
  capacityClaimAllowed
}' "${OUTPUT}"
