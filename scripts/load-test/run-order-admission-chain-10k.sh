#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-5}"
EVENTS="${EVENTS:-10000}"
USERS="${USERS:-500}"
WORKERS="${WORKERS:-128}"
SIDE="${SIDE:-SELL}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
RUN_ID="${RUN_ID:-GLT_$(date +%Y%m%d)_ORDER_ADMISSION_10K}"
MARKET_ID="${MARKET_ID:-ENERGY-SPOT}"
START_SERVICES="${START_SERVICES:-true}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-false}"
ASSERT_LOADTEST_ENVIRONMENT="${ASSERT_LOADTEST_ENVIRONMENT:-true}"
LOADTEST_RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
LOADTEST_REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER:-eap-redis-loadtest}"
ORDER_ADMISSION_MATCH_USER_OPEN_ORDER_INDEX_ENABLED="${ORDER_ADMISSION_MATCH_USER_OPEN_ORDER_INDEX_ENABLED:-false}"
ORDER_ADMISSION_ORDER_COMMAND_POOL_SIZE="${ORDER_ADMISSION_ORDER_COMMAND_POOL_SIZE:-35}"
ORDER_ADMISSION_ORDER_COMMAND_POOL_MIN_IDLE="${ORDER_ADMISSION_ORDER_COMMAND_POOL_MIN_IDLE:-10}"
ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE="${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE:-500}"
ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY="${ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY:-1}"
ORDER_ADMISSION_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED="${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED:-true}"
ORDER_ADMISSION_ORDER_OUTBOX_ASYNC_RELAY_ENABLED="${ORDER_ADMISSION_ORDER_OUTBOX_ASYNC_RELAY_ENABLED:-false}"
ORDER_ADMISSION_ORDER_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS="${ORDER_ADMISSION_ORDER_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS:-30}"
ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE="${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE:-50}"
ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS="${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS:-25}"
ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_RELAY_ENABLED="${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_RELAY_ENABLED:-false}"
ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES="${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES:-4}"
ORDER_ADMISSION_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS="${ORDER_ADMISSION_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS:-30}"
ORDER_ADMISSION_RATE_LIMIT_ENABLED="${ORDER_ADMISSION_RATE_LIMIT_ENABLED:-true}"
ORDER_ADMISSION_RATE_LIMIT_BACKEND="${ORDER_ADMISSION_RATE_LIMIT_BACKEND:-local}"
ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE="${ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE:-1}"
FLUSH_REDIS_ON_RESET="${FLUSH_REDIS_ON_RESET:-true}"
BENCHMARK_PROFILE="${BENCHMARK_PROFILE:-custom}"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/order-admission-${RUN_ID}.log"
RUN_DIAG_DIR="${REPORT_DIR}/order-admission-${RUN_ID}-diagnostics"

DIAG_SAMPLER_PID=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/load-test/run-order-admission-chain-10k.sh [options]

Profiles:
  --profile light-10k          10k order-admission attribution run with light diagnostics.
  --profile deep-10k           10k order-admission attribution run with deep diagnostics and pg_stat reset.
  --profile baseline-10k       10k order-admission capacity run without diagnostics sampler.
  --profile users10000-10k     10k order-admission light run with one user per order.
  --profile rate-limit-off-10k 10k attribution run with Order API rate limit disabled.
  --profile market-sequence-block1000-10k
                              10k attribution run with in-memory market sequence blocks.

Common options:
  --run-id VALUE
  --target-tps VALUE
  --duration-seconds VALUE
  --events VALUE
  --users VALUE
  --workers VALUE
  --side VALUE
  --wait-timeout-seconds VALUE
  --diagnostics-level VALUE    none, baseline, light, deep
  --reset-pg-stats             Reset pg_stat_statements before the run.
  --no-reset-pg-stats
  --assert-loadtest-environment VALUE true or false
  --start-services VALUE       true or false
  --flush-redis-on-reset VALUE true or false
  --order-outbox-batch-size VALUE
  --order-outbox-publish-concurrency VALUE
  --asset-confirmed-batch-size VALUE
  --asset-confirmed-receive-timeout-ms VALUE
  --rate-limit-enabled VALUE   true or false
  --rate-limit-backend VALUE   local or redis
  --market-sequence-allocation-block-size VALUE
  --help

Environment variables with the previous names remain supported. Command-line
options are applied in order, so put --profile before per-run overrides.
EOF
}

apply_profile() {
  local profile="$1"
  case "${profile}" in
    light-10k|order-admission-light-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      BENCHMARK_PROFILE="${profile}"
      ;;
    deep-10k|order-admission-deep-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=deep
      RESET_PG_STATS_BEFORE_RUN=true
      BENCHMARK_PROFILE="${profile}"
      ;;
    baseline-10k|order-admission-baseline-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=none
      RESET_PG_STATS_BEFORE_RUN=false
      BENCHMARK_PROFILE="${profile}"
      ;;
    users10000-10k|order-admission-users10000-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=10000
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      BENCHMARK_PROFILE="${profile}"
      ;;
    order-outbox-publish4-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY=4
      BENCHMARK_PROFILE="${profile}"
      ;;
    order-outbox-batch250-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE=250
      BENCHMARK_PROFILE="${profile}"
      ;;
    asset-confirmed-timeout50-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE=50
      ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS=50
      BENCHMARK_PROFILE="${profile}"
      ;;
    rate-limit-off-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      ORDER_ADMISSION_RATE_LIMIT_ENABLED=false
      BENCHMARK_PROFILE="${profile}"
      ;;
    market-sequence-block1000-10k)
      TARGET_TPS=2000
      DURATION_SECONDS=5
      EVENTS=10000
      USERS=500
      WORKERS=128
      WAIT_TIMEOUT_SECONDS=300
      DIAGNOSTICS_LEVEL=light
      RESET_PG_STATS_BEFORE_RUN=false
      ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE=1000
      BENCHMARK_PROFILE="${profile}"
      ;;
    *)
      echo "[ERROR] unsupported profile=${profile}" >&2
      usage >&2
      exit 2
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "[ERROR] --profile requires a value" >&2; exit 2; }
      apply_profile "$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || { echo "[ERROR] --run-id requires a value" >&2; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    --target-tps)
      [[ $# -ge 2 ]] || { echo "[ERROR] --target-tps requires a value" >&2; exit 2; }
      TARGET_TPS="$2"
      shift 2
      ;;
    --duration-seconds)
      [[ $# -ge 2 ]] || { echo "[ERROR] --duration-seconds requires a value" >&2; exit 2; }
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --events)
      [[ $# -ge 2 ]] || { echo "[ERROR] --events requires a value" >&2; exit 2; }
      EVENTS="$2"
      shift 2
      ;;
    --users)
      [[ $# -ge 2 ]] || { echo "[ERROR] --users requires a value" >&2; exit 2; }
      USERS="$2"
      shift 2
      ;;
    --workers)
      [[ $# -ge 2 ]] || { echo "[ERROR] --workers requires a value" >&2; exit 2; }
      WORKERS="$2"
      shift 2
      ;;
    --side)
      [[ $# -ge 2 ]] || { echo "[ERROR] --side requires a value" >&2; exit 2; }
      SIDE="$2"
      shift 2
      ;;
    --wait-timeout-seconds)
      [[ $# -ge 2 ]] || { echo "[ERROR] --wait-timeout-seconds requires a value" >&2; exit 2; }
      WAIT_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --diagnostics-level)
      [[ $# -ge 2 ]] || { echo "[ERROR] --diagnostics-level requires a value" >&2; exit 2; }
      DIAGNOSTICS_LEVEL="$2"
      shift 2
      ;;
    --reset-pg-stats)
      RESET_PG_STATS_BEFORE_RUN=true
      shift
      ;;
    --no-reset-pg-stats)
      RESET_PG_STATS_BEFORE_RUN=false
      shift
      ;;
    --start-services)
      [[ $# -ge 2 ]] || { echo "[ERROR] --start-services requires a value" >&2; exit 2; }
      START_SERVICES="$2"
      shift 2
      ;;
    --assert-loadtest-environment)
      [[ $# -ge 2 ]] || { echo "[ERROR] --assert-loadtest-environment requires a value" >&2; exit 2; }
      ASSERT_LOADTEST_ENVIRONMENT="$2"
      shift 2
      ;;
    --flush-redis-on-reset)
      [[ $# -ge 2 ]] || { echo "[ERROR] --flush-redis-on-reset requires a value" >&2; exit 2; }
      FLUSH_REDIS_ON_RESET="$2"
      shift 2
      ;;
    --order-outbox-batch-size)
      [[ $# -ge 2 ]] || { echo "[ERROR] --order-outbox-batch-size requires a value" >&2; exit 2; }
      ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE="$2"
      shift 2
      ;;
    --order-outbox-publish-concurrency)
      [[ $# -ge 2 ]] || { echo "[ERROR] --order-outbox-publish-concurrency requires a value" >&2; exit 2; }
      ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY="$2"
      shift 2
      ;;
    --asset-confirmed-batch-size)
      [[ $# -ge 2 ]] || { echo "[ERROR] --asset-confirmed-batch-size requires a value" >&2; exit 2; }
      ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE="$2"
      shift 2
      ;;
    --asset-confirmed-receive-timeout-ms)
      [[ $# -ge 2 ]] || { echo "[ERROR] --asset-confirmed-receive-timeout-ms requires a value" >&2; exit 2; }
      ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS="$2"
      shift 2
      ;;
    --rate-limit-enabled)
      [[ $# -ge 2 ]] || { echo "[ERROR] --rate-limit-enabled requires a value" >&2; exit 2; }
      ORDER_ADMISSION_RATE_LIMIT_ENABLED="$2"
      shift 2
      ;;
    --rate-limit-backend)
      [[ $# -ge 2 ]] || { echo "[ERROR] --rate-limit-backend requires a value" >&2; exit 2; }
      ORDER_ADMISSION_RATE_LIMIT_BACKEND="$2"
      shift 2
      ;;
    --market-sequence-allocation-block-size)
      [[ $# -ge 2 ]] || { echo "[ERROR] --market-sequence-allocation-block-size requires a value" >&2; exit 2; }
      ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

RUN_REPORT_LOG="${REPORT_DIR}/order-admission-${RUN_ID}.log"
RUN_DIAG_DIR="${REPORT_DIR}/order-admission-${RUN_ID}-diagnostics"

collect_diagnostics() {
  local phase="$1"
  case "${DIAGNOSTICS_LEVEL}" in
    none|baseline)
      return 0
      ;;
    light)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" "${phase}-light" || true
      ;;
    deep)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" "${phase}" || true
      ;;
    *)
      echo "[ERROR] unsupported DIAGNOSTICS_LEVEL=${DIAGNOSTICS_LEVEL}; expected none, baseline, light, or deep" >&2
      exit 2
      ;;
  esac
}

start_diagnostic_sampler() {
  case "${DIAGNOSTICS_LEVEL}" in
    none|baseline)
      return 0
      ;;
  esac
  mkdir -p "${RUN_DIAG_DIR}"
  rm -f "${RUN_DIAG_DIR}/sampler.stop" 2>/dev/null || true
  DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" sample &
  DIAG_SAMPLER_PID="$!"
  echo "[INFO] diagnostics sampler pid=${DIAG_SAMPLER_PID}, level=${DIAGNOSTICS_LEVEL}, dir=${RUN_DIAG_DIR}"
}

stop_diagnostic_sampler() {
  if [[ -n "${DIAG_SAMPLER_PID}" ]]; then
    DIAG_DIR="${RUN_DIAG_DIR}" RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
      bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" stop-sample >/dev/null 2>&1 || true
    wait "${DIAG_SAMPLER_PID}" >/dev/null 2>&1 || true
    DIAG_SAMPLER_PID=""
  fi
}

cleanup() {
  stop_diagnostic_sampler
}
trap cleanup EXIT

if (( EVENTS != 10000 )); then
  echo "[WARN] EVENTS=${EVENTS}; the standard order-admission-chain probe is normally EVENTS=10000." >&2
fi

if [[ "${MARKET_ID}" != "ENERGY-SPOT" ]]; then
  echo "[WARN] Order HTTP API currently assigns default market ENERGY-SPOT; MARKET_ID=${MARKET_ID} is used only for admission gate lookup." >&2
fi

if [[ "${ASSERT_LOADTEST_ENVIRONMENT}" == "true" ]]; then
  RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/assert-loadtest-environment.sh"
fi

if [[ "${START_SERVICES}" == "true" ]]; then
  EAP_MATCH_USER_OPEN_ORDER_INDEX_ENABLED="${ORDER_ADMISSION_MATCH_USER_OPEN_ORDER_INDEX_ENABLED}" \
    EAP_ORDER_COMMAND_POOL_SIZE="${ORDER_ADMISSION_ORDER_COMMAND_POOL_SIZE}" \
    EAP_ORDER_COMMAND_POOL_MIN_IDLE="${ORDER_ADMISSION_ORDER_COMMAND_POOL_MIN_IDLE}" \
    EAP_ORDER_OUTBOX_BATCH_SIZE="${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE}" \
    EAP_ORDER_OUTBOX_PUBLISH_CONCURRENCY="${ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY}" \
    EAP_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED="${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED}" \
    EAP_ORDER_OUTBOX_ASYNC_RELAY_ENABLED="${ORDER_ADMISSION_ORDER_OUTBOX_ASYNC_RELAY_ENABLED}" \
    EAP_ORDER_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS="${ORDER_ADMISSION_ORDER_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS}" \
    EAP_RATE_LIMIT_ENABLED="${ORDER_ADMISSION_RATE_LIMIT_ENABLED}" \
    EAP_RATE_LIMIT_BACKEND="${ORDER_ADMISSION_RATE_LIMIT_BACKEND}" \
    EAP_ORDER_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE="${ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE}" \
    EAP_ORDER_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE="${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE}" \
    EAP_ORDER_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS="${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS}" \
    EAP_WALLET_OUTBOX_ASYNC_RELAY_ENABLED="${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_RELAY_ENABLED}" \
    EAP_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES="${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES}" \
    EAP_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS="${ORDER_ADMISSION_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS}" \
    bash "${ROOT_DIR}/scripts/load-test/start-loadtest-services.sh"
fi

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"

echo "[INFO] Order admission chain benchmark"
echo "[INFO] profile=${BENCHMARK_PROFILE}"
echo "[INFO] runId=${RUN_ID}"
echo "[INFO] targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, users=${USERS}, workers=${WORKERS}, side=${SIDE}"
echo "[INFO] matchUserOpenOrderIndexEnabled=${ORDER_ADMISSION_MATCH_USER_OPEN_ORDER_INDEX_ENABLED}"
echo "[INFO] orderCommandPoolSize=${ORDER_ADMISSION_ORDER_COMMAND_POOL_SIZE}, orderCommandPoolMinIdle=${ORDER_ADMISSION_ORDER_COMMAND_POOL_MIN_IDLE}"
echo "[INFO] orderOutboxBatchSize=${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_SIZE}, orderOutboxPublishConcurrency=${ORDER_ADMISSION_ORDER_OUTBOX_PUBLISH_CONCURRENCY}, orderOutboxBatchConfirmEnabled=${ORDER_ADMISSION_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED}, orderOutboxAsyncRelayEnabled=${ORDER_ADMISSION_ORDER_OUTBOX_ASYNC_RELAY_ENABLED}"
echo "[INFO] rateLimitEnabled=${ORDER_ADMISSION_RATE_LIMIT_ENABLED}, rateLimitBackend=${ORDER_ADMISSION_RATE_LIMIT_BACKEND}, marketSequenceAllocationBlockSize=${ORDER_ADMISSION_MARKET_SEQUENCE_ALLOCATION_BLOCK_SIZE}"
echo "[INFO] orderAssetReservationConfirmedBatchSize=${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_BATCH_SIZE}, orderAssetReservationConfirmedReceiveTimeoutMs=${ORDER_ADMISSION_ASSET_RESERVATION_CONFIRMED_RECEIVE_TIMEOUT_MS}"
echo "[INFO] walletOutboxAsyncRelayEnabled=${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_RELAY_ENABLED}, walletOutboxAsyncMaxInFlightBatches=${ORDER_ADMISSION_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES}"
echo "[INFO] flushRedisOnReset=${FLUSH_REDIS_ON_RESET}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}"
echo "[INFO] resetPgStatsBeforeRun=${RESET_PG_STATS_BEFORE_RUN}"
echo "[INFO] assertLoadtestEnvironment=${ASSERT_LOADTEST_ENVIRONMENT}, loadtestRabbitContainer=${LOADTEST_RABBIT_CONTAINER}, loadtestRedisContainer=${LOADTEST_REDIS_CONTAINER}"
echo "[INFO] runReportLog=${RUN_REPORT_LOG}"

cd "${ROOT_DIR}/eap-order"
if [[ "${RESET_PG_STATS_BEFORE_RUN}" == "true" ]]; then
  DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" reset || true
fi
collect_diagnostics before-run
start_diagnostic_sampler
run_status=0
set +e
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon orderHttpLoadTest \
  --args="--mode orderAdmissionChain \
  --run-id ${RUN_ID} \
  --market-id ${MARKET_ID} \
  --side ${SIDE} \
  --events ${EVENTS} \
  --tps ${TARGET_TPS} \
  --duration-seconds ${DURATION_SECONDS} \
  --users ${USERS} \
  --workers ${WORKERS} \
  --wait-timeout-seconds ${WAIT_TIMEOUT_SECONDS} \
  --flush-redis-on-reset ${FLUSH_REDIS_ON_RESET} \
  --order-admission-gate true" | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e
stop_diagnostic_sampler
collect_diagnostics after-run
exit "${run_status}"
