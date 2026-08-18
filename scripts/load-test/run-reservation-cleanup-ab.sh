#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
EVENTS="${EVENTS:-10000}"
BASELINE_BATCH_SIZE="${BASELINE_BATCH_SIZE:-1000}"
CANDIDATE_BATCH_SIZE="${CANDIDATE_BATCH_SIZE:-250}"
LEASE_CHUNK_SIZE="${LEASE_CHUNK_SIZE:-50}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
RUN_ORDER="${RUN_ORDER:-baseline,candidate}"
KEEP_INFRA="${KEEP_INFRA:-false}"

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

run_probe() {
  local label="$1"
  local batch_size="$2"
  local output="${REPORT_DIR}/reservation-cleanup-${RUN_ID}-${label}.json"

  echo "[INFO] ${label}: events=${EVENTS}, batchSize=${batch_size}, leaseChunkSize=${LEASE_CHUNK_SIZE}"
  (
    cd "${ROOT_DIR}/eap-matchEngine"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon reservationCleanupLoadProbe \
      --args="--events ${EVENTS} --batch-size ${batch_size} --lease-chunk-size ${LEASE_CHUNK_SIZE} --output ${output}"
  )
}

echo "[INFO] starting only MatchEngine PostgreSQL and Redis"
docker compose -f "${COMPOSE_FILE}" up -d match-postgres redis
wait_for_healthy eap-match-postgres-loadtest
wait_for_healthy eap-redis-loadtest

IFS=',' read -r -a variants <<< "${RUN_ORDER}"
for variant in "${variants[@]}"; do
  case "${variant}" in
    baseline)
      run_probe baseline "${BASELINE_BATCH_SIZE}"
      ;;
    candidate)
      run_probe candidate "${CANDIDATE_BATCH_SIZE}"
      ;;
    *)
      echo "[ERROR] RUN_ORDER must contain baseline and candidate; got ${RUN_ORDER}" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "${REPORT_DIR}/reservation-cleanup-${RUN_ID}-baseline.json" \
      || ! -f "${REPORT_DIR}/reservation-cleanup-${RUN_ID}-candidate.json" ]]; then
  echo "[ERROR] RUN_ORDER must execute both baseline and candidate exactly once" >&2
  exit 2
fi

echo "[INFO] isolated A/B complete; these results are diagnostics, not full-chain capacity evidence"
jq -s '[.[] | {
  batchSize,
  cleanupTasksPerSecond,
  cleanupCalls,
  batchMeanMs,
  batchMaxMs,
  redisCleanupMeanMs,
  correctness,
  capacityClaimAllowed
}]' \
  "${REPORT_DIR}/reservation-cleanup-${RUN_ID}-baseline.json" \
  "${REPORT_DIR}/reservation-cleanup-${RUN_ID}-candidate.json"
