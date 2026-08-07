#!/usr/bin/env bash

# Shared lifecycle for the full HTTP completion, steady-state, and staircase contracts.

http_matched_extract_last_json_object() {
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

http_matched_persist_result() {
  if http_matched_extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
    echo "[INFO] persisted result JSON=${RUN_REPORT_JSON}"
  else
    echo "[WARN] could not extract result JSON from ${RUN_REPORT_LOG}" >&2
    rm -f "${RUN_REPORT_JSON}"
  fi
}

http_matched_validate_common() {
  if [[ "${MARKET_ID}" != "ENERGY-SPOT" ]]; then
    echo "[ERROR] Order HTTP currently assigns market ENERGY-SPOT; MARKET_ID must match." >&2
    return 2
  fi
  case "${DIAGNOSTICS_LEVEL}" in
    none|light|deep)
      ;;
    *)
      echo "[ERROR] unsupported DIAGNOSTICS_LEVEL=${DIAGNOSTICS_LEVEL}" >&2
      return 2
      ;;
  esac
}

http_matched_assert_environment() {
  if [[ "${ASSERT_LOADTEST_ENVIRONMENT}" != "true" ]]; then
    return 0
  fi
  RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/assert-loadtest-environment.sh"
}

http_matched_start_diagnostics() {
  if [[ "${DIAGNOSTICS_LEVEL}" == "none" ]]; then
    return 0
  fi
  mkdir -p "${RUN_DIAG_DIR}"
  if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
    DIAG_DIR="${RUN_DIAG_DIR}" \
      MARKET_ID="${MARKET_ID}" \
      DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
      RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
      REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
      bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" reset
  fi
  rm -f "${RUN_DIAG_DIR}/sampler.stop" 2>/dev/null || true
  DIAG_DIR="${RUN_DIAG_DIR}" \
    MARKET_ID="${MARKET_ID}" \
    DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
    DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS}" \
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" sample &
  DIAG_SAMPLER_PID="$!"
  echo "[INFO] diagnostics sampler pid=${DIAG_SAMPLER_PID}, dir=${RUN_DIAG_DIR}"
}

http_matched_stop_diagnostics() {
  if [[ -z "${DIAG_SAMPLER_PID:-}" ]]; then
    return 0
  fi
  DIAG_DIR="${RUN_DIAG_DIR}" \
    RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" stop-sample >/dev/null 2>&1 || true
  wait "${DIAG_SAMPLER_PID}" >/dev/null 2>&1 || true
  DIAG_SAMPLER_PID=""
}

http_matched_collect_after_run_diagnostics() {
  case "${DIAGNOSTICS_LEVEL}" in
    light)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" after-run-light || true
      ;;
    deep)
      DIAG_DIR="${RUN_DIAG_DIR}" MARKET_ID="${MARKET_ID}" DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
        RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
        bash "${ROOT_DIR}/scripts/load-test/collect-loadtest-diagnostics.sh" after-run || true
      ;;
  esac
  if [[ -f "${RUN_DIAG_DIR}/runtime-samples.log" ]]; then
    local hot_window_summary
    if hot_window_summary="$(bash "${ROOT_DIR}/scripts/load-test/summarize-runtime-hot-window.sh" "${RUN_DIAG_DIR}")"; then
      echo "[INFO] runtime hot-window summary=${hot_window_summary}"
    else
      echo "[WARN] could not summarize runtime hot window" >&2
    fi
  fi
}

http_matched_start_services() {
  if [[ "${START_SERVICES}" != "true" ]]; then
    return 0
  fi
  echo "[INFO] stopping stale loadtest services"
  bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"
  echo "[INFO] purging EAP queues before service start"
  RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"
  http_matched_pre_reset_data

  LOADTEST_SERVICE_LAUNCH_MODE="${LOADTEST_SERVICE_LAUNCH_MODE}" \
  LOADTEST_SERVICE_JAVA_BIN="${LOADTEST_SERVICE_JAVA_BIN}" \
    bash "${ROOT_DIR}/scripts/load-test/start-loadtest-services.sh"
}

http_matched_pre_reset_data() {
  echo "[INFO] resetting matched HTTP data before consumer startup"
  http_matched_export_generator_environment
  local reset_args="--market-id ${MARKET_ID} \
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
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon httpMatchedResetLoadTest \
      --args="${reset_args}"
  )
}

http_matched_stop_services() {
  if [[ "${STOP_SERVICES_AFTER_RUN}" == "true" ]]; then
    bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
  fi
}

http_matched_cleanup() {
  http_matched_stop_diagnostics
  http_matched_stop_services
}

http_matched_export_generator_environment() {
  export EAP_LOADTEST_JDBC_PASSWORD="${JDBC_PASSWORD}"
  export EAP_LOADTEST_RABBIT_PASSWORD="${RABBIT_PASSWORD}"
  export EAP_LOADTEST_RABBIT_VHOST="${RABBIT_VHOST}"
}
