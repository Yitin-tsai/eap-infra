#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-5}"
EVENTS="${EVENTS:-10000}"
USERS="${USERS:-500}"
WORKERS=128
MAX_IN_FLIGHT=256
SIDE="${SIDE:-SELL}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
RUN_ID="${RUN_ID:-GLT_$(date +%Y%m%d)_ORDER_ADMISSION_10K}"
MARKET_ID="${MARKET_ID:-ENERGY-SPOT}"
START_SERVICES="${START_SERVICES:-true}"
STOP_SERVICES_AFTER_RUN="${STOP_SERVICES_AFTER_RUN:-}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
ORDER_ADMISSION_DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${ORDER_ADMISSION_DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-1}"
ASSERT_LOADTEST_ENVIRONMENT=true
LOADTEST_RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
LOADTEST_REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER:-eap-redis-loadtest}"
ORDER_ADMISSION_SERVICE_LAUNCH_MODE="${ORDER_ADMISSION_SERVICE_LAUNCH_MODE:-boot-run}"
ORDER_ADMISSION_SERVICE_JAVA_BIN="${ORDER_ADMISSION_SERVICE_JAVA_BIN:-java}"
FLUSH_REDIS_ON_RESET=true
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_REPORT_LOG="${REPORT_DIR}/order-admission-${RUN_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/order-admission-${RUN_ID}-result.json"
RUN_DIAG_DIR="${REPORT_DIR}/order-admission-${RUN_ID}-diagnostics"

DIAG_SAMPLER_PID=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/load-test/run-order-admission-chain-10k.sh [options]

Options:
  --run-id VALUE
  --target-tps VALUE
  --duration-seconds VALUE
  --events VALUE
  --users VALUE
  --side VALUE
  --wait-timeout-seconds VALUE
  --diagnostics-level VALUE    none, light, deep
  --diagnostic-sample-interval-seconds VALUE
                              Runtime sampler interval. Defaults to 1 for order-admission runs.
  --start-services VALUE       true or false
  --stop-services-after-run VALUE
                              true or false. Defaults to --start-services.
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --diagnostic-sample-interval-seconds)
      [[ $# -ge 2 ]] || { echo "[ERROR] --diagnostic-sample-interval-seconds requires a value" >&2; exit 2; }
      ORDER_ADMISSION_DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --start-services)
      [[ $# -ge 2 ]] || { echo "[ERROR] --start-services requires a value" >&2; exit 2; }
      START_SERVICES="$2"
      shift 2
      ;;
    --stop-services-after-run)
      [[ $# -ge 2 ]] || { echo "[ERROR] --stop-services-after-run requires a value" >&2; exit 2; }
      STOP_SERVICES_AFTER_RUN="$2"
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

if [[ -z "${STOP_SERVICES_AFTER_RUN}" ]]; then
  STOP_SERVICES_AFTER_RUN="${START_SERVICES}"
fi

RESET_PG_STATS_BEFORE_RUN=false
if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
  RESET_PG_STATS_BEFORE_RUN=true
fi

RUN_REPORT_LOG="${REPORT_DIR}/order-admission-${RUN_ID}.log"
RUN_REPORT_JSON="${REPORT_DIR}/order-admission-${RUN_ID}-result.json"
RUN_DIAG_DIR="${REPORT_DIR}/order-admission-${RUN_ID}-diagnostics"

collect_diagnostics() {
  local phase="$1"
  case "${DIAGNOSTICS_LEVEL}" in
    none)
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
      echo "[ERROR] unsupported DIAGNOSTICS_LEVEL=${DIAGNOSTICS_LEVEL}; expected none, light, or deep" >&2
      exit 2
      ;;
  esac
}

extract_last_json_object() {
  local source_log="$1"
  local target_json="$2"
  local temp_json="${target_json}.tmp.$$"

  if ! awk '
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
  ' "${source_log}" > "${temp_json}"; then
    rm -f "${temp_json}"
    return 1
  fi
  if ! jq -e . "${temp_json}" >/dev/null; then
    rm -f "${temp_json}"
    return 1
  fi
  mv "${temp_json}" "${target_json}"
}

start_diagnostic_sampler() {
  case "${DIAGNOSTICS_LEVEL}" in
    none)
      return 0
      ;;
  esac
  mkdir -p "${RUN_DIAG_DIR}"
  rm -f "${RUN_DIAG_DIR}/sampler.stop" 2>/dev/null || true
  DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${ORDER_ADMISSION_DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS}" \
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
  if [[ "${STOP_SERVICES_AFTER_RUN}" == "true" ]]; then
    bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
      bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh" >/dev/null 2>&1 || true
  fi
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
  echo "[INFO] stopping stale loadtest services before queue purge"
  bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"

  echo "[INFO] purging queues before service start"
  RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

  LOADTEST_SERVICE_LAUNCH_MODE="${ORDER_ADMISSION_SERVICE_LAUNCH_MODE}" \
    LOADTEST_SERVICE_JAVA_BIN="${ORDER_ADMISSION_SERVICE_JAVA_BIN}" \
    bash "${ROOT_DIR}/scripts/load-test/start-loadtest-services.sh"
fi

mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"

echo "[INFO] Order admission chain benchmark"
echo "[INFO] runId=${RUN_ID}"
echo "[INFO] targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, users=${USERS}, workers=${WORKERS}, maxInFlight=${MAX_IN_FLIGHT}, side=${SIDE}"
echo "[INFO] serviceLaunchMode=${ORDER_ADMISSION_SERVICE_LAUNCH_MODE}, serviceJavaBin=${ORDER_ADMISSION_SERVICE_JAVA_BIN}"
echo "[INFO] flushRedisOnReset=${FLUSH_REDIS_ON_RESET}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}"
echo "[INFO] diagnosticSampleIntervalSeconds=${ORDER_ADMISSION_DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS}"
echo "[INFO] resetPgStatsBeforeRun=${RESET_PG_STATS_BEFORE_RUN}"
echo "[INFO] assertLoadtestEnvironment=${ASSERT_LOADTEST_ENVIRONMENT}, loadtestRabbitContainer=${LOADTEST_RABBIT_CONTAINER}, loadtestRedisContainer=${LOADTEST_REDIS_CONTAINER}, startServices=${START_SERVICES}, stopServicesAfterRun=${STOP_SERVICES_AFTER_RUN}"
echo "[INFO] runReportLog=${RUN_REPORT_LOG}"
echo "[INFO] runReportJson=${RUN_REPORT_JSON}"

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
  --max-in-flight ${MAX_IN_FLIGHT} \
  --wait-timeout-seconds ${WAIT_TIMEOUT_SECONDS} \
  --flush-redis-on-reset ${FLUSH_REDIS_ON_RESET} \
  --order-admission-gate true" | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e
stop_diagnostic_sampler
collect_diagnostics after-run
if [[ -d "${RUN_DIAG_DIR}" && -f "${RUN_DIAG_DIR}/runtime-samples.log" ]]; then
  if hot_window_summary_file="$(bash "${ROOT_DIR}/scripts/load-test/summarize-runtime-hot-window.sh" "${RUN_DIAG_DIR}")"; then
    echo "[INFO] persisted runtime hot-window summary=${hot_window_summary_file}"
  else
    echo "[WARN] could not generate runtime hot-window summary" >&2
  fi
fi
if extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
  echo "[INFO] persisted run result json=${RUN_REPORT_JSON}"
else
  echo "[WARN] could not extract run result JSON from ${RUN_REPORT_LOG}" >&2
  rm -f "${RUN_REPORT_JSON}"
fi
exit "${run_status}"
