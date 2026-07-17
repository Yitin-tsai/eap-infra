#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOCK_DIR="${ROOT_DIR}/.loadtest-lock/global-matched-e2e-two-phase-driver.lock"
LOCK_INFO_FILE="${LOCK_DIR}/owner.env"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"

EVENTS="${EVENTS:-500}"
PUBLISHERS="${PUBLISHERS:-64}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
TARGET_TPS="${TARGET_TPS:-0}"
DURATION_SECONDS="${DURATION_SECONDS:-0}"
MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO:-0.95}"
MARKET_ID="${MARKET_ID:-GLOBAL_LOADTEST_$(date +%Y%m%d_%H%M%S)}"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STARTUP_TIMEOUT_SECONDS="${STARTUP_TIMEOUT_SECONDS:-90}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-false}"
RUN_MODE="${RUN_MODE:-prepare-run}"
RUN_REPORT_LOG="${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-run.log"
RUN_REPORT_JSON="${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-result.json"
RUN_REPORT_META="${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-meta.txt"
RUN_DIAG_DIR="${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-diagnostics"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-}"
if [[ -z "${DIAGNOSTICS_LEVEL}" ]]; then
  case "${DIAGNOSTICS_ENABLED:-}" in
    true) DIAGNOSTICS_LEVEL="deep" ;;
    false) DIAGNOSTICS_LEVEL="baseline" ;;
    "") DIAGNOSTICS_LEVEL="baseline" ;;
    *)
      echo "[ERROR] DIAGNOSTICS_ENABLED must be true or false when DIAGNOSTICS_LEVEL is not set." >&2
      exit 2
      ;;
  esac
fi
DIAG_SAMPLER_PID=""

case "${RUN_MODE}" in
  prepare|run-only|prepare-run) ;;
  *)
    echo "[ERROR] RUN_MODE must be one of: prepare, run-only, prepare-run" >&2
    exit 2
    ;;
esac

case "${DIAGNOSTICS_LEVEL}" in
  baseline|off|none)
    DIAGNOSTICS_LEVEL="baseline"
    ;;
  light|deep)
    ;;
  *)
    echo "[ERROR] DIAGNOSTICS_LEVEL must be one of: baseline, light, deep" >&2
    exit 2
    ;;
esac

mkdir -p "${REPORT_DIR}" "$(dirname "${LOCK_DIR}")"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "[ERROR] another two-phase global matched E2E load-test driver appears to be running: ${LOCK_DIR}" >&2
  if [[ -f "${LOCK_INFO_FILE}" ]]; then
    echo "[ERROR] current lock owner:" >&2
    sed 's/^/[ERROR]   /' "${LOCK_INFO_FILE}" >&2 || true
  fi
  echo "[ERROR] remove the lock only after confirming no seed/run/loadtest process is active." >&2
  exit 2
fi
{
  echo "pid=$$"
  echo "MARKET_ID=${MARKET_ID}"
  echo "events=${EVENTS}"
  echo "publishers=${PUBLISHERS}"
  echo "timeoutSeconds=${TIMEOUT_SECONDS}"
  echo "targetTps=${TARGET_TPS}"
  echo "durationSeconds=${DURATION_SECONDS}"
  echo "runMode=${RUN_MODE}"
  echo "startedAt=${STARTED_AT}"
  echo "script=${BASH_SOURCE[0]}"
} > "${LOCK_INFO_FILE}"

stop_diagnostic_sampler() {
  if [[ -n "${DIAG_SAMPLER_PID}" ]]; then
    DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" \
      bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" stop-sample >/dev/null 2>&1 || true
    wait "${DIAG_SAMPLER_PID}" >/dev/null 2>&1 || true
    DIAG_SAMPLER_PID=""
  fi
}

cleanup() {
  stop_diagnostic_sampler
  rm -f "${LOCK_INFO_FILE}" 2>/dev/null || true
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

assert_environment() {
  echo "[INFO] checking loadtest infrastructure: $1"
  bash "${ROOT_DIR}/scripts/load-test/assert-loadtest-environment.sh"
}

wait_http() {
  local name="$1"
  local url="$2"
  local deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS))
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "[ERROR] ${name} did not become ready: ${url}" >&2
      return 1
    fi
    sleep 2
  done
  echo "[INFO] ${name} ready"
}

reset_pg_stats() {
  echo "[INFO] resetting PostgreSQL stats before run phase"
  docker exec eap-order-postgres-loadtest psql -U admin -d eap_order_db -v ON_ERROR_STOP=1 -c "select pg_stat_reset();" >/dev/null
  docker exec eap-wallet-postgres-loadtest psql -U admin -d eap_wallet_db -v ON_ERROR_STOP=1 -c "select pg_stat_reset();" >/dev/null
  docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -v ON_ERROR_STOP=1 -c "select pg_stat_reset();" >/dev/null
  if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
    DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" \
      bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" reset || true
  fi
}

collect_diagnostics() {
  local phase="$1"
  case "${DIAGNOSTICS_LEVEL}" in
    baseline)
      return 0
      ;;
    light)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" "${phase}-light" || true
      ;;
    deep)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" "${phase}" || true
      ;;
  esac
}

start_diagnostic_sampler() {
  if [[ "${DIAGNOSTICS_LEVEL}" == "baseline" ]]; then
    return 0
  fi
  rm -f "${RUN_DIAG_DIR}/sampler.stop" 2>/dev/null || true
  DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" sample &
  DIAG_SAMPLER_PID="$!"
  echo "[INFO] diagnostics sampler pid=${DIAG_SAMPLER_PID}, level=${DIAGNOSTICS_LEVEL}, dir=${RUN_DIAG_DIR}"
}

append_service_metadata() {
  {
    echo
    echo "[services]"
    for repo in eap-wallet eap-order eap-matchEngine; do
      local pid_file="${LOG_DIR}/${repo}.pid"
      local pid=""
      local args=""
      if [[ -f "${pid_file}" ]]; then
        pid="$(cat "${pid_file}")"
        args="$(ps -p "${pid}" -o args= 2>/dev/null || true)"
      fi
      echo "${repo}.pid=${pid:-missing}"
      echo "${repo}.profile=loadtest"
      echo "${repo}.args=${args:-missing}"
    done
    echo "orderDb.port=15432"
    echo "walletDb.port=15433"
    echo "matchDb.port=15434"
  } >> "${RUN_REPORT_META}"
}

append_rabbitmq_metadata() {
  local rabbit_container="${RABBIT_CONTAINER:-eap-rabbitmq}"
  {
    echo
    echo "[rabbitmq.queues]"
    echo "container=${rabbit_container}"
    docker exec "${rabbit_container}" rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers \
      | grep -E '^(order|wallet|matchEngine)\.|^order\.dlq$' || true
  } >> "${RUN_REPORT_META}" 2>&1
}

append_redis_metadata() {
  local redis_container="${REDIS_CONTAINER:-eap-redis}"
  {
    echo
    echo "[redis]"
    echo "container=${redis_container}"
    docker exec "${redis_container}" redis-cli --raw CONFIG GET maxmemory || true
    docker exec "${redis_container}" redis-cli --raw CONFIG GET maxmemory-policy || true
    docker exec "${redis_container}" redis-cli INFO stats \
      | grep -E '^(evicted_keys:|expired_keys:|keyspace_hits:|keyspace_misses:)' || true
    docker exec "${redis_container}" redis-cli INFO memory \
      | grep -E '^(used_memory:|used_memory_peak:|maxmemory:|maxmemory_policy:)' || true
  } >> "${RUN_REPORT_META}" 2>&1
}

write_run_metadata() {
  {
    echo "MARKET_ID=${MARKET_ID}"
    echo "marketId=${MARKET_ID}"
    echo "events=${EVENTS}"
    echo "publishers=${PUBLISHERS}"
    echo "timeout=${TIMEOUT_SECONDS}"
    echo "timeoutSeconds=${TIMEOUT_SECONDS}"
    echo "targetTps=${TARGET_TPS}"
    echo "durationSeconds=${DURATION_SECONDS}"
    echo "runMode=${RUN_MODE}"
    echo "resetPgStatsBeforeRun=${RESET_PG_STATS_BEFORE_RUN}"
    echo "startedAt=${STARTED_AT}"
    echo "orderDbEndpoint=localhost:15432/eap_order_db"
    echo "walletDbEndpoint=localhost:15433/eap_wallet_db"
    echo "matchDbEndpoint=localhost:15434/eap_match_db"
    echo "rabbitMqEndpoint=localhost:5672"
    echo "orderJdbc=localhost:15432/eap_order_db"
    echo "walletJdbc=localhost:15433/eap_wallet_db"
    echo "matchJdbc=localhost:15434/eap_match_db"
    echo "rabbitmq=localhost:5672"
    echo "runReportLog=${RUN_REPORT_LOG}"
    echo "runReportJson=${RUN_REPORT_JSON}"
    echo "runReportMeta=${RUN_REPORT_META}"
    echo "runDiagnosticDir=${RUN_DIAG_DIR}"
    echo "diagnosticsLevel=${DIAGNOSTICS_LEVEL}"
  } > "${RUN_REPORT_META}"
}

extract_last_json_object() {
  local source_log="$1"
  local target_json="$2"

  awk '
    /^\{/ {
      in_json = 1
      buffer = $0 ORS
      next
    }
    in_json {
      buffer = buffer $0 ORS
      if ($0 ~ /^\}/) {
        last = buffer
        in_json = 0
        buffer = ""
      }
    }
    END {
      if (last == "") {
        exit 1
      }
      printf "%s", last
    }
  ' "${source_log}" > "${target_json}"
}

echo "[INFO] marketId=${MARKET_ID}"
echo "[INFO] events=${EVENTS}, publishers=${PUBLISHERS}, timeout=${TIMEOUT_SECONDS}s"
echo "[INFO] runMode=${RUN_MODE}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}"
echo "[INFO] run report log=${RUN_REPORT_LOG}"
echo "[INFO] run report json=${RUN_REPORT_JSON}"
echo "[INFO] run report meta=${RUN_REPORT_META}"
write_run_metadata

if [[ "${RUN_MODE}" == "prepare" || "${RUN_MODE}" == "prepare-run" ]]; then
  assert_environment "before seed"

  echo "[INFO] stopping services before seed"
  bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"

  echo "[INFO] purging queues before seed"
  assert_environment "before queue purge"
  bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

  echo "[INFO] seeding test data"
  MARKET_ID="${MARKET_ID}" EVENTS="${EVENTS}" PUBLISHERS="${PUBLISHERS}" TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" TARGET_TPS=0 DURATION_SECONDS=0 PHASE=seed \
    bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e.sh"

  echo "[INFO] purging queues after seed"
  assert_environment "after seed"
  bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

  echo "[INFO] prewarming Order projection before run"
  MARKET_ID="${MARKET_ID}" EVENTS="${EVENTS}" PUBLISHERS="${PUBLISHERS}" TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" TARGET_TPS=0 DURATION_SECONDS=0 PHASE=project \
    bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e.sh"

  if [[ "${RUN_MODE}" == "prepare" ]]; then
    echo "[INFO] prepare complete; rerun with RUN_MODE=run-only and the same MARKET_ID/EVENTS to execute the sustained load."
    exit 0
  fi
else
  echo "[INFO] skipping seed/projection because RUN_MODE=run-only"
  echo "[INFO] expecting prepared, unused dataset: marketId=${MARKET_ID}, events=${EVENTS}"
fi

if [[ "${RESET_PG_STATS_BEFORE_RUN}" == "true" ]]; then
  reset_pg_stats
fi

echo "[INFO] starting services for run phase"
assert_environment "before service start"
bash "${ROOT_DIR}/scripts/load-test/start-loadtest-services.sh"

wait_http "wallet" "http://localhost:8081/eap-wallet/actuator/health"
wait_http "order" "http://localhost:8080/eap-order/actuator/health"
wait_http "matchEngine" "http://localhost:8082/match-engine/actuator/health"
append_service_metadata
append_rabbitmq_metadata
append_redis_metadata
collect_diagnostics before-run

echo "[INFO] running load test"
assert_environment "before run"
start_diagnostic_sampler
run_status=0
set +e
MARKET_ID="${MARKET_ID}" EVENTS="${EVENTS}" PUBLISHERS="${PUBLISHERS}" TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" TARGET_TPS="${TARGET_TPS}" DURATION_SECONDS="${DURATION_SECONDS}" MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO}" PHASE=run \
  bash "${ROOT_DIR}/scripts/load-test/run-global-matched-e2e.sh" | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e
stop_diagnostic_sampler
append_rabbitmq_metadata
append_redis_metadata
collect_diagnostics after-run

if extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
  echo "[INFO] persisted run result json=${RUN_REPORT_JSON}"
else
  echo "[WARN] could not extract JSON result from ${RUN_REPORT_LOG}" >&2
  rm -f "${RUN_REPORT_JSON}"
fi

echo "[INFO] stopping services after run"
bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"

echo "[INFO] final queue state"
assert_environment "before final queue verification"
bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

if [[ "${run_status}" -ne 0 ]]; then
  echo "[ERROR] load test failed with exit code ${run_status}; diagnostics were still collected." >&2
  exit "${run_status}"
fi
