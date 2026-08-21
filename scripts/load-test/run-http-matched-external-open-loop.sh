#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"

if (( $# > 1 )); then
  echo "usage: $0 [RUN_ID]" >&2
  exit 2
fi

TARGET_ORDER_TPS="${TARGET_ORDER_TPS:-300}"
WARMUP_SECONDS="${WARMUP_SECONDS:-10}"
DURATION_SECONDS="${DURATION_SECONDS:-30}"
USERS_PER_SIDE="${USERS_PER_SIDE:-500}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-900}"
SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-1}"
PROGRESS_INTERVAL_SECONDS="${PROGRESS_INTERVAL_SECONDS:-10}"
MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_LOAD_RATIO:-0.95}"
MIN_COMPLETION_RATIO="${MIN_COMPLETION_RATIO:-0.95}"
MAX_BACKLOG_GROWTH_PER_SECOND="${MAX_BACKLOG_GROWTH_PER_SECOND:-}"
MAX_STEADY_BACKLOG="${MAX_STEADY_BACKLOG:-}"
WORKLOAD_SEED="${WORKLOAD_SEED:-20260804}"
RUN_ID="${RUN_ID:-${1:-GLT_$(date +%Y%m%d_%H%M%S)_EXTERNAL_OPEN_LOOP}}"
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
FLUSH_REDIS_ON_RESET=true
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-none}"
DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-5}"
LOADTEST_RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
LOADTEST_REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER:-eap-redis-loadtest}"
LOADTEST_SERVICE_LAUNCH_MODE="${LOADTEST_SERVICE_LAUNCH_MODE:-boot-run}"
LOADTEST_SERVICE_JAVA_BIN="${LOADTEST_SERVICE_JAVA_BIN:-java}"
LOADTEST_DRIVER_JAVA_BIN="${LOADTEST_DRIVER_JAVA_BIN:-java}"
VEGETA_CPUS="${VEGETA_CPUS:-2}"
VEGETA_WORKERS="${VEGETA_WORKERS:-16}"
VEGETA_MAX_WORKERS="${VEGETA_MAX_WORKERS:-4096}"
VEGETA_TIMEOUT="${VEGETA_TIMEOUT:-10s}"
LOAD_GENERATOR_PLACEMENT="${LOAD_GENERATOR_PLACEMENT:-co-located}"
REMOTE_DRIVER_SSH_TARGET="${REMOTE_DRIVER_SSH_TARGET:-}"
REMOTE_DRIVER_SSH_PORT="${REMOTE_DRIVER_SSH_PORT:-}"
REMOTE_DRIVER_IDENTITY_FILE="${REMOTE_DRIVER_IDENTITY_FILE:-}"
REMOTE_DRIVER_WORK_DIR="${REMOTE_DRIVER_WORK_DIR:-/tmp/eap-loadtest-${RUN_ID}}"
REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS="${REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS:-2}"
REMOTE_DRIVER_KEEP_ARTIFACTS="${REMOTE_DRIVER_KEEP_ARTIFACTS:-false}"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
RUN_PREFIX="${REPORT_DIR}/http-matched-external-${RUN_ID}"
RUN_REPORT_LOG="${RUN_PREFIX}.log"
RUN_REPORT_JSON="${RUN_PREFIX}-result.json"
RUN_SAMPLES_CSV="${RUN_PREFIX}-samples.csv"
RUN_DIAG_DIR="${RUN_PREFIX}-diagnostics"
RUN_MANIFEST="${RUN_PREFIX}-manifest.json"
RUN_TARGETS="${RUN_PREFIX}-targets.jsonl"
RUN_MONITOR_CSV="${RUN_PREFIX}-monitor.csv"
RUN_MONITOR_LOG="${RUN_PREFIX}-monitor.log"
RUN_MONITOR_READY="${RUN_PREFIX}-monitor.ready"
RUN_MONITOR_STOP="${RUN_PREFIX}-monitor.stop"
RUN_VEGETA_JSONL="${RUN_PREFIX}-vegeta.jsonl"
RUN_VEGETA_REPORT="${RUN_PREFIX}-vegeta-report.json"
RUN_VEGETA_TIME="${RUN_PREFIX}-vegeta-time.txt"
RUN_VEGETA_GZIP="${RUN_PREFIX}-vegeta.jsonl.gz"
RUN_REMOTE_METADATA="${RUN_PREFIX}-remote-driver-metadata.json"
RUN_REMOTE_PREFLIGHT="${RUN_PREFIX}-remote-driver-preflight.txt"
RUN_CLASSPATH="${RUN_PREFIX}-classpath.txt"
DIAG_SAMPLER_PID=""
MONITOR_PID=""
REMOTE_DRIVER_ACTIVE=false
REMOTE_DRIVER_HELPER="${ROOT_DIR}/scripts/load-test/remote-vegeta-driver.sh"
REMOTE_SSH_ARGS=(-o BatchMode=yes)
REMOTE_SCP_ARGS=(-o BatchMode=yes)

if [[ -n "${REMOTE_DRIVER_SSH_PORT}" ]]; then
  REMOTE_SSH_ARGS+=(-p "${REMOTE_DRIVER_SSH_PORT}")
  REMOTE_SCP_ARGS+=(-P "${REMOTE_DRIVER_SSH_PORT}")
fi
if [[ -n "${REMOTE_DRIVER_IDENTITY_FILE}" ]]; then
  REMOTE_SSH_ARGS+=(-i "${REMOTE_DRIVER_IDENTITY_FILE}")
  REMOTE_SCP_ARGS+=(-i "${REMOTE_DRIVER_IDENTITY_FILE}")
fi

remote_ssh() {
  local command=""
  printf -v command '%q ' "$@"
  ssh "${REMOTE_SSH_ARGS[@]}" "${REMOTE_DRIVER_SSH_TARGET}" "${command% }"
}

remote_driver_cleanup() {
  if [[ "${REMOTE_DRIVER_ACTIVE}" != "true" || "${REMOTE_DRIVER_KEEP_ARTIFACTS}" == "true" ]]; then
    return 0
  fi
  remote_ssh bash "${REMOTE_DRIVER_WORK_DIR}/remote-vegeta-driver.sh" \
    cleanup "${REMOTE_DRIVER_WORK_DIR}" >/dev/null 2>&1 || true
  REMOTE_DRIVER_ACTIVE=false
}

remote_driver_prepare() {
  local expected_sha256 local_before local_after remote_epoch preflight_output
  expected_sha256="$(jq -r '.targetsSha256' "${RUN_MANIFEST}")"
  remote_ssh mkdir -p "${REMOTE_DRIVER_WORK_DIR}"
  REMOTE_DRIVER_ACTIVE=true
  scp "${REMOTE_SCP_ARGS[@]}" \
    "${REMOTE_DRIVER_HELPER}" \
    "${RUN_TARGETS}" \
    "${REMOTE_DRIVER_SSH_TARGET}:${REMOTE_DRIVER_WORK_DIR}/"
  local_before="$(date +%s)"
  preflight_output="$(remote_ssh \
    bash "${REMOTE_DRIVER_WORK_DIR}/remote-vegeta-driver.sh" \
    preflight \
    "${REMOTE_DRIVER_WORK_DIR}" \
    "${REMOTE_DRIVER_WORK_DIR}/$(basename "${RUN_TARGETS}")" \
    "${expected_sha256}" \
    "${ORDER_URL%/}/actuator/health")"
  local_after="$(date +%s)"
  printf '%s\n' "${preflight_output}" > "${RUN_REMOTE_PREFLIGHT}"
  remote_epoch="$(printf '%s\n' "${preflight_output}" | awk -F= '$1 == "remoteEpochSeconds" { print $2 }')"
  if [[ ! "${remote_epoch}" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] remote preflight did not return a valid epoch" >&2
    exit 2
  fi
  if (( remote_epoch < local_before - REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS \
        || remote_epoch > local_after + REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS )); then
    echo "[ERROR] remote clock is outside the allowed ${REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS}s window: local=${local_before}..${local_after}, remote=${remote_epoch}" >&2
    exit 2
  fi
  echo "[INFO] remote driver preflight passed: target checksum and service reachability verified"
}

run_remote_vegeta_attack() {
  local expected_results
  expected_results="$(jq -r '.expectedHttpOrders' "${RUN_MANIFEST}")"
  remote_ssh \
    bash "${REMOTE_DRIVER_WORK_DIR}/remote-vegeta-driver.sh" \
    attack \
    "${REMOTE_DRIVER_WORK_DIR}" \
    "${REMOTE_DRIVER_WORK_DIR}/$(basename "${RUN_TARGETS}")" \
    "${TARGET_ORDER_TPS}" \
    "${VEGETA_DURATION_NANOS}" \
    "${VEGETA_CPUS}" \
    "${VEGETA_WORKERS}" \
    "${VEGETA_MAX_WORKERS}" \
    "${VEGETA_TIMEOUT}" \
    "${expected_results}" || return $?
  scp "${REMOTE_SCP_ARGS[@]}" \
    "${REMOTE_DRIVER_SSH_TARGET}:${REMOTE_DRIVER_WORK_DIR}/results.jsonl.gz" \
    "${RUN_VEGETA_GZIP}" || return $?
  scp "${REMOTE_SCP_ARGS[@]}" \
    "${REMOTE_DRIVER_SSH_TARGET}:${REMOTE_DRIVER_WORK_DIR}/vegeta-report.json" \
    "${RUN_VEGETA_REPORT}" || return $?
  scp "${REMOTE_SCP_ARGS[@]}" \
    "${REMOTE_DRIVER_SSH_TARGET}:${REMOTE_DRIVER_WORK_DIR}/vegeta-time.txt" \
    "${RUN_VEGETA_TIME}" || return $?
  scp "${REMOTE_SCP_ARGS[@]}" \
    "${REMOTE_DRIVER_SSH_TARGET}:${REMOTE_DRIVER_WORK_DIR}/remote-driver-metadata.json" \
    "${RUN_REMOTE_METADATA}" || return $?
  gzip -dc "${RUN_VEGETA_GZIP}" > "${RUN_VEGETA_JSONL}" || return $?
  rm -f "${RUN_VEGETA_GZIP}" || return $?
}

external_cleanup() {
  if [[ -n "${MONITOR_PID:-}" ]]; then
    touch "${RUN_MONITOR_STOP}" 2>/dev/null || true
    wait "${MONITOR_PID}" >/dev/null 2>&1 || true
    MONITOR_PID=""
  fi
  remote_driver_cleanup
  http_matched_cleanup
}
trap external_cleanup EXIT

if (( TARGET_ORDER_TPS <= 0 || TARGET_ORDER_TPS % 2 != 0 )); then
  echo "[ERROR] TARGET_ORDER_TPS must be a positive even number." >&2
  exit 2
fi
if (( WARMUP_SECONDS < 0 || DURATION_SECONDS < 2 )); then
  echo "[ERROR] WARMUP_SECONDS must be non-negative and DURATION_SECONDS at least 2." >&2
  exit 2
fi
if [[ -z "${RESET_DATA_ON_PREPARE+x}" ]]; then
  if [[ "${START_SERVICES}" == "true" ]]; then
    RESET_DATA_ON_PREPARE=false
  else
    RESET_DATA_ON_PREPARE=true
  fi
fi
case "${LOAD_GENERATOR_PLACEMENT}" in
  co-located)
    if ! command -v vegeta >/dev/null 2>&1; then
      echo "[ERROR] vegeta is required. Install it with: brew install vegeta" >&2
      exit 2
    fi
    ;;
  remote-host)
    for command_name in ssh scp gzip; do
      if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "[ERROR] ${command_name} is required for a remote driver" >&2
        exit 2
      fi
    done
    if [[ -z "${REMOTE_DRIVER_SSH_TARGET}" ]]; then
      echo "[ERROR] REMOTE_DRIVER_SSH_TARGET is required for remote-host placement" >&2
      exit 2
    fi
    if [[ ! "${REMOTE_DRIVER_WORK_DIR}" =~ ^/tmp/eap-loadtest-[A-Za-z0-9_.-]+$ ]]; then
      echo "[ERROR] REMOTE_DRIVER_WORK_DIR must match /tmp/eap-loadtest-<safe-id>" >&2
      exit 2
    fi
    if [[ "${ORDER_URL}" =~ ^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:|/) ]]; then
      echo "[ERROR] remote-host placement requires an ORDER_URL reachable from the remote host" >&2
      exit 2
    fi
    if [[ ! "${REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS}" =~ ^[0-9]+$ ]]; then
      echo "[ERROR] REMOTE_DRIVER_MAX_CLOCK_SKEW_SECONDS must be a non-negative integer" >&2
      exit 2
    fi
    ;;
  *)
    echo "[ERROR] LOAD_GENERATOR_PLACEMENT must be co-located or remote-host." >&2
    exit 2
    ;;
esac

http_matched_validate_common
mkdir -p "${GRADLE_USER_HOME_DIR}" "${REPORT_DIR}"
http_matched_assert_environment
http_matched_start_services
http_matched_export_generator_environment

COMMON_ARGS="--run-id ${RUN_ID} \
--market-id ${MARKET_ID} \
--target-order-tps ${TARGET_ORDER_TPS} \
--warmup-seconds ${WARMUP_SECONDS} \
--duration-seconds ${DURATION_SECONDS} \
--users-per-side ${USERS_PER_SIDE} \
--wait-timeout-seconds ${WAIT_TIMEOUT_SECONDS} \
--sample-interval-seconds ${SAMPLE_INTERVAL_SECONDS} \
--progress-interval-seconds ${PROGRESS_INTERVAL_SECONDS} \
--min-offered-load-ratio ${MIN_OFFERED_LOAD_RATIO} \
--min-completion-ratio ${MIN_COMPLETION_RATIO} \
--arrival-pattern shuffled \
--workload-seed ${WORKLOAD_SEED} \
--runtime-profile canonical \
--http-driver-mode external-vegeta \
--reset-data ${RESET_DATA_ON_PREPARE} \
--sample-output ${RUN_SAMPLES_CSV} \
--manifest ${RUN_MANIFEST} \
--targets ${RUN_TARGETS} \
--monitor-output ${RUN_MONITOR_CSV} \
--monitor-ready ${RUN_MONITOR_READY} \
--monitor-stop ${RUN_MONITOR_STOP} \
--vegeta-results ${RUN_VEGETA_JSONL} \
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
--flush-redis-on-reset ${FLUSH_REDIS_ON_RESET}"
if [[ -n "${MAX_BACKLOG_GROWTH_PER_SECOND}" ]]; then
  COMMON_ARGS="${COMMON_ARGS} --max-backlog-growth-per-second ${MAX_BACKLOG_GROWTH_PER_SECOND}"
fi
if [[ -n "${MAX_STEADY_BACKLOG}" ]]; then
  COMMON_ARGS="${COMMON_ARGS} --max-steady-backlog ${MAX_STEADY_BACKLOG}"
fi

echo "[INFO] external open-loop HTTP matched lifecycle"
echo "[INFO] runId=${RUN_ID}, targetTotalOrderTps=${TARGET_ORDER_TPS}"
echo "[INFO] warmupSeconds=${WARMUP_SECONDS}, measurementSeconds=${DURATION_SECONDS}"
echo "[INFO] vegetaCpus=${VEGETA_CPUS}, workers=${VEGETA_WORKERS}, maxWorkers=${VEGETA_MAX_WORKERS}"
echo "[INFO] loadGeneratorPlacement=${LOAD_GENERATOR_PLACEMENT}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, businessSampleInterval=${SAMPLE_INTERVAL_SECONDS}s"
echo "[INFO] manifest=${RUN_MANIFEST}, result=${RUN_REPORT_JSON}"

cd "${ROOT_DIR}/eap-order"
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon httpMatchedExternalPrepare \
  --args="${COMMON_ARGS}"
GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon writeLoadTestRuntimeClasspath \
  -PloadTestClasspathOutput="${RUN_CLASSPATH}"

if [[ "${LOAD_GENERATOR_PLACEMENT}" == "remote-host" ]]; then
  remote_driver_prepare
fi

rm -f "${RUN_MONITOR_READY}" "${RUN_MONITOR_STOP}"
# COMMON_ARGS contains only validated scalar values and workspace paths without whitespace.
"${LOADTEST_DRIVER_JAVA_BIN}" -cp "$(cat "${RUN_CLASSPATH}")" \
  com.eap.eap_order.loadtest.HttpMatchedExternalMonitor \
  ${COMMON_ARGS} > "${RUN_MONITOR_LOG}" 2>&1 &
MONITOR_PID="$!"
for _ in $(seq 1 120); do
  if [[ -f "${RUN_MONITOR_READY}" ]]; then
    break
  fi
  if ! kill -0 "${MONITOR_PID}" 2>/dev/null; then
    echo "[ERROR] external monitor exited before becoming ready." >&2
    cat "${RUN_MONITOR_LOG}" >&2
    exit 2
  fi
  sleep 0.25
done
if [[ ! -f "${RUN_MONITOR_READY}" ]]; then
  echo "[ERROR] external monitor did not become ready within 30 seconds." >&2
  exit 2
fi

http_matched_start_diagnostics
TOTAL_SECONDS=$((WARMUP_SECONDS + DURATION_SECONDS))
VEGETA_DURATION_NANOS=$(((TOTAL_SECONDS + 1) * 1000000000))
attack_status=0
encode_status=0
filter_status=0
if [[ "${LOAD_GENERATOR_PLACEMENT}" == "remote-host" ]]; then
  set +e
  run_remote_vegeta_attack
  attack_status=$?
  set -e
else
  set +e
  /usr/bin/time -p vegeta -cpus="${VEGETA_CPUS}" attack \
    -lazy \
    -format=json \
    -targets="${RUN_TARGETS}" \
    -rate="${TARGET_ORDER_TPS}/1s" \
    -duration="${VEGETA_DURATION_NANOS}ns" \
    -workers="${VEGETA_WORKERS}" \
    -max-workers="${VEGETA_MAX_WORKERS}" \
    -timeout="${VEGETA_TIMEOUT}" \
    -max-body=0 2> "${RUN_VEGETA_TIME}" \
    | vegeta encode --to=json \
    | jq -c 'select(.error != "no targets to attack")' > "${RUN_VEGETA_JSONL}"
  pipeline_status=("${PIPESTATUS[@]}")
  attack_status="${pipeline_status[0]}"
  encode_status="${pipeline_status[1]}"
  filter_status="${pipeline_status[2]}"
  set -e
fi

touch "${RUN_MONITOR_STOP}"
monitor_status=0
set +e
wait "${MONITOR_PID}"
monitor_status=$?
set -e
MONITOR_PID=""

if (( attack_status != 0 )); then
  echo "[ERROR] Vegeta attack failed with status ${attack_status}." >&2
  exit "${attack_status}"
fi
if (( encode_status != 0 )); then
  echo "[ERROR] Vegeta result encoder failed with status ${encode_status}." >&2
  exit "${encode_status}"
fi
if (( filter_status != 0 )); then
  echo "[ERROR] Vegeta EOF filter failed with status ${filter_status}." >&2
  exit "${filter_status}"
fi
if (( monitor_status != 0 )); then
  echo "[ERROR] external monitor failed with status ${monitor_status}." >&2
  cat "${RUN_MONITOR_LOG}" >&2
  exit "${monitor_status}"
fi

run_status=0
set +e
"${LOADTEST_DRIVER_JAVA_BIN}" -cp "$(cat "${RUN_CLASSPATH}")" \
  com.eap.eap_order.loadtest.HttpMatchedExternalVerifyLoadGenerator \
  ${COMMON_ARGS} | tee "${RUN_REPORT_LOG}"
run_status=${PIPESTATUS[0]}
set -e
if [[ "${LOAD_GENERATOR_PLACEMENT}" == "co-located" ]]; then
  vegeta report -type=json "${RUN_VEGETA_JSONL}" > "${RUN_VEGETA_REPORT}"
fi
http_matched_stop_diagnostics
http_matched_collect_after_run_diagnostics

persist_status=0
http_matched_persist_result "${run_status}" "external-http-matched-steady-state-chain" || persist_status=$?
if [[ -f "${RUN_REPORT_JSON}" ]]; then
  enriched_result="${RUN_REPORT_JSON}.external.tmp.$$"
  jq \
    --arg placement "${LOAD_GENERATOR_PLACEMENT}" \
    --arg vegetaReport "${RUN_VEGETA_REPORT}" \
    --arg driverTime "${RUN_VEGETA_TIME}" \
    --arg manifest "${RUN_MANIFEST}" \
    --arg remoteMetadata "${RUN_REMOTE_METADATA}" \
    --arg remotePreflight "${RUN_REMOTE_PREFLIGHT}" \
    --slurpfile driverReportData "${RUN_VEGETA_REPORT}" \
    --argjson cpus "${VEGETA_CPUS}" \
    --argjson workers "${VEGETA_WORKERS}" \
    --argjson maxWorkers "${VEGETA_MAX_WORKERS}" \
    '. + {
      externalOpenLoopDriver: true,
      loadGeneratorPlacement: $placement,
      externalDriverCpuLimit: $cpus,
      externalDriverInitialWorkers: $workers,
      externalDriverMaxWorkers: $maxWorkers,
      externalScheduledRequests: $driverReportData[0].requests,
      externalScheduledRequestRate: $driverReportData[0].rate,
      externalResponseThroughput: $driverReportData[0].throughput,
      externalHttpSuccessRatio: $driverReportData[0].success,
      externalDriverReport: $vegetaReport,
      externalDriverTime: $driverTime,
      workloadManifest: $manifest,
      remoteDriverMetadata: (if $placement == "remote-host" then $remoteMetadata else null end),
      remoteDriverPreflight: (if $placement == "remote-host" then $remotePreflight else null end)
    }' "${RUN_REPORT_JSON}" > "${enriched_result}"
  mv "${enriched_result}" "${RUN_REPORT_JSON}"
fi
if (( run_status == 0 && persist_status != 0 )); then
  run_status="${persist_status}"
fi
echo "[INFO] Vegeta report=${RUN_VEGETA_REPORT}, driver time=${RUN_VEGETA_TIME}"
exit "${run_status}"
