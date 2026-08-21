#!/usr/bin/env bash

# Shared lifecycle for the full HTTP completion, steady-state, and staircase contracts.

http_matched_sha256() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    sha256sum "${file}" | awk '{print $1}'
  fi
}

http_matched_write_provenance_snapshot() {
  local output="$1"
  local captured_at repositories_json containers_json os_name os_version architecture
  local logical_cpus physical_memory_bytes java_version docker_version vegeta_version
  local compose_sha runner_sha library_sha
  local repositories_file="${output}.repositories.tmp.$$"

  mkdir -p "$(dirname "${output}")"
  : > "${repositories_file}"
  while IFS='|' read -r name relative_path transaction_path; do
    local repo_dir commit branch dirty dirty_file_count available
    if [[ "${relative_path}" == "." ]]; then
      repo_dir="${ROOT_DIR}"
    else
      repo_dir="${ROOT_DIR}/${relative_path}"
    fi
    if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      available=true
      commit="$(git -C "${repo_dir}" rev-parse HEAD)"
      branch="$(git -C "${repo_dir}" branch --show-current)"
      dirty_file_count="$(git -C "${repo_dir}" status --porcelain --untracked-files=normal | wc -l | tr -d ' ')"
      if (( dirty_file_count == 0 )); then dirty=false; else dirty=true; fi
    else
      available=false
      commit=""
      branch=""
      dirty=true
      dirty_file_count=0
    fi
    jq -cn \
      --arg name "${name}" \
      --arg path "${relative_path}" \
      --arg commit "${commit}" \
      --arg branch "${branch}" \
      --argjson available "${available}" \
      --argjson dirty "${dirty}" \
      --argjson dirtyFileCount "${dirty_file_count}" \
      --argjson transactionPath "${transaction_path}" \
      '{name:$name,path:$path,available:$available,commit:$commit,
        branch:(if $branch == "" then null else $branch end),dirty:$dirty,
        dirtyFileCount:$dirtyFileCount,transactionPath:$transactionPath}' \
      >> "${repositories_file}"
  done <<'EOF'
eap-infra|.|false
eap-common|eap-common|true
eap-order|eap-order|true
eap-wallet|eap-wallet|true
eap-matchEngine|eap-matchEngine|true
EOF
  repositories_json="$(jq -s '.' "${repositories_file}")"
  rm -f "${repositories_file}"

  os_name="$(uname -s)"
  architecture="$(uname -m)"
  if command -v sw_vers >/dev/null 2>&1; then
    os_version="$(sw_vers -productVersion)"
  elif [[ -r /etc/os-release ]]; then
    os_version="$(awk -F= '$1 == "VERSION_ID" {gsub(/\"/, "", $2); print $2}' /etc/os-release)"
  else
    os_version="$(uname -r)"
  fi
  if logical_cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" && [[ "${logical_cpus}" =~ ^[0-9]+$ ]]; then
    :
  elif logical_cpus="$(sysctl -n hw.logicalcpu 2>/dev/null)" && [[ "${logical_cpus}" =~ ^[0-9]+$ ]]; then
    :
  else
    logical_cpus=0
  fi
  if physical_memory_bytes="$(sysctl -n hw.memsize 2>/dev/null)" && [[ "${physical_memory_bytes}" =~ ^[0-9]+$ ]]; then
    :
  elif [[ -r /proc/meminfo ]]; then
    physical_memory_bytes="$(awk '$1 == "MemTotal:" {print $2 * 1024}' /proc/meminfo)"
  else
    physical_memory_bytes=0
  fi

  java_version="$(${LOADTEST_SERVICE_JAVA_BIN:-java} -version 2>&1 | head -n 1 || true)"
  docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  vegeta_version="$(vegeta --version 2>&1 | head -n 1 || true)"
  compose_sha="$(http_matched_sha256 "${ROOT_DIR}/docker-compose.loadtest.yml")"
  runner_sha="$(http_matched_sha256 "$0")"
  library_sha="$(http_matched_sha256 "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh")"
  captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  containers_json='[]'
  if command -v docker >/dev/null 2>&1; then
    local inspected_containers
    if inspected_containers="$(docker inspect \
        eap-order-postgres-loadtest eap-wallet-postgres-loadtest eap-match-postgres-loadtest \
        "${LOADTEST_RABBIT_CONTAINER}" "${LOADTEST_REDIS_CONTAINER}" 2>/dev/null)"; then
      containers_json="$(jq '[.[] | {name:(.Name | ltrimstr("/")), configuredImage:.Config.Image, imageId:.Image}]' \
        <<< "${inspected_containers}")"
    fi
  fi

  jq -n \
    --arg capturedAt "${captured_at}" \
    --arg evidenceMode "${BENCHMARK_EVIDENCE_MODE}" \
    --arg benchmarkContract "${BENCHMARK_PROVENANCE_CONTRACT:-unknown}" \
    --arg loadGeneratorPlacement "${LOAD_GENERATOR_PLACEMENT:-co-located}" \
    --arg serviceLaunchMode "${LOADTEST_SERVICE_LAUNCH_MODE:-boot-run}" \
    --arg diagnosticsLevel "${DIAGNOSTICS_LEVEL:-none}" \
    --arg synchronousCommit "${EAP_LOADTEST_SYNCHRONOUS_COMMIT:-off}" \
    --arg trackIoTiming "${EAP_LOADTEST_TRACK_IO_TIMING:-off}" \
    --arg trackWalIoTiming "${EAP_LOADTEST_TRACK_WAL_IO_TIMING:-off}" \
    --arg osName "${os_name}" \
    --arg osVersion "${os_version}" \
    --arg architecture "${architecture}" \
    --argjson logicalCpus "${logical_cpus}" \
    --argjson physicalMemoryBytes "${physical_memory_bytes}" \
    --arg javaVersion "${java_version}" \
    --arg dockerVersion "${docker_version}" \
    --arg vegetaVersion "${vegeta_version}" \
    --arg composeSha256 "${compose_sha}" \
    --arg runnerSha256 "${runner_sha}" \
    --arg librarySha256 "${library_sha}" \
    --argjson repositories "${repositories_json}" \
    --argjson containers "${containers_json}" \
    '{schemaVersion:1,capturedAt:$capturedAt,evidenceMode:$evidenceMode,
      benchmarkContract:$benchmarkContract,
      sourceClean:all($repositories[]; .available and (.dirty | not)),
      repositories:$repositories,
      host:{os:$osName,osVersion:$osVersion,architecture:$architecture,
        logicalCpus:$logicalCpus,physicalMemoryBytes:$physicalMemoryBytes},
      execution:{loadGeneratorPlacement:$loadGeneratorPlacement,
        serviceLaunchMode:$serviceLaunchMode,diagnosticsLevel:$diagnosticsLevel,
        postgres:{synchronousCommit:$synchronousCommit,trackIoTiming:$trackIoTiming,
          trackWalIoTiming:$trackWalIoTiming}},
      tooling:{java:$javaVersion,docker:$dockerVersion,vegeta:$vegetaVersion},
      fingerprints:{composeSha256:$composeSha256,runnerSha256:$runnerSha256,
        librarySha256:$librarySha256},containers:$containers}' > "${output}"
}

http_matched_prepare_provenance() {
  RUN_PROVENANCE_START_JSON="${RUN_PROVENANCE_START_JSON:-${RUN_REPORT_JSON%.json}-provenance-start.json}"
  BENCHMARK_PROVENANCE_CONTRACT="${BENCHMARK_PROVENANCE_CONTRACT:-unknown}"
  http_matched_write_provenance_snapshot "${RUN_PROVENANCE_START_JSON}"
  echo "[INFO] benchmark provenance start=${RUN_PROVENANCE_START_JSON}"
  if [[ "${BENCHMARK_EVIDENCE_MODE}" == "release-pinned" ]] \
      && ! jq -e '.sourceClean == true' "${RUN_PROVENANCE_START_JSON}" >/dev/null; then
    echo "[ERROR] release-pinned benchmark requires every recorded source repository to be clean." >&2
    jq -r '.repositories[] | select((.available | not) or .dirty) | [.name, .available, .dirty, .dirtyFileCount] | @tsv' \
      "${RUN_PROVENANCE_START_JSON}" >&2
    return 2
  fi
}

http_matched_enrich_provenance() {
  local run_status="$1"
  local benchmark_contract="$2"
  local final_json="${RUN_REPORT_JSON%.json}-provenance-final.json"
  local provenance_json="${RUN_REPORT_JSON%.json}-provenance.json"
  local enriched_result="${RUN_REPORT_JSON}.provenance.tmp.$$"

  BENCHMARK_PROVENANCE_CONTRACT="${benchmark_contract}"
  http_matched_write_provenance_snapshot "${final_json}"
  jq -n \
    --slurpfile start "${RUN_PROVENANCE_START_JSON}" \
    --slurpfile final "${final_json}" \
    --arg evidenceMode "${BENCHMARK_EVIDENCE_MODE}" \
    '($start[0].repositories == $final[0].repositories) as $stable
      | (($start[0].sourceClean == true) and ($final[0].sourceClean == true)) as $clean
      | {
          schemaVersion:1,
          evidenceMode:$evidenceMode,
          capturedAtStart:$start[0].capturedAt,
          capturedAtEnd:$final[0].capturedAt,
          sourceCleanAtStart:$start[0].sourceClean,
          sourceCleanAtEnd:$final[0].sourceClean,
          sourceStable:$stable,
          sourceEligible:($evidenceMode == "release-pinned" and $clean and $stable),
          benchmarkContract:$final[0].benchmarkContract,
          invalidReasons:([
            if $evidenceMode != "release-pinned" then "diagnostic_evidence_mode" else empty end,
            if ($clean | not) then "source_repository_dirty_or_missing" else empty end,
            if ($stable | not) then "source_revision_changed_during_run" else empty end
          ]),
          repositories:$final[0].repositories,
          host:$final[0].host,
          execution:$final[0].execution,
          tooling:$final[0].tooling,
          fingerprints:$final[0].fingerprints,
          containers:$final[0].containers
        }' > "${provenance_json}"

  jq \
    --slurpfile provenance "${provenance_json}" \
    --arg contract "${benchmark_contract}" \
    --argjson processExitStatus "${run_status}" \
    '.benchmarkProvenance = $provenance[0]
      | .provenanceInvalidReasons = $provenance[0].invalidReasons
      | .capacityClaimAllowed = (
          $provenance[0].sourceEligible
          and ($processExitStatus == 0)
          and ($contract == "http-matched-steady-state-chain"
            or $contract == "external-http-matched-steady-state-chain")
          and (.validForSustainedCapacity == true)
          and ((.rabbitMqResourceAlarmObserved // false) | not)
        )
      | .validForCapacityEvidence = .capacityClaimAllowed' \
    "${RUN_REPORT_JSON}" > "${enriched_result}"
  mv "${enriched_result}" "${RUN_REPORT_JSON}"
  rm -f "${final_json}"
  echo "[INFO] benchmark provenance=${provenance_json}"
}

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

http_matched_rabbitmq_alarm_observed() {
  local samples_file="${RUN_DIAG_DIR}/runtime-samples.log"
  [[ -f "${samples_file}" ]] || return 1
  awk -F '\t' '
    /^# rabbitmq alarms$/ { section = 1; next }
    /^#/ { section = 0; next }
    section && NF >= 3 && ($2 == "true" || $3 == "true") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${samples_file}"
}

http_matched_persist_result() {
  local run_status="${1:-1}"
  local benchmark_contract="${2:-unknown}"
  if http_matched_extract_last_json_object "${RUN_REPORT_LOG}" "${RUN_REPORT_JSON}"; then
    echo "[INFO] persisted result JSON=${RUN_REPORT_JSON}"
    if http_matched_rabbitmq_alarm_observed; then
      local temp_json="${RUN_REPORT_JSON}.alarm.tmp.$$"
      jq '
        .rabbitMqResourceAlarmObserved = true
        | .validForCapacityEvidence = false
        | if has("validForSustainedCapacity") then .validForSustainedCapacity = false else . end
        | .capacityInvalidReasons = (((.capacityInvalidReasons // []) + ["rabbitmq_resource_alarm_observed"]) | unique)
      ' "${RUN_REPORT_JSON}" > "${temp_json}"
      mv "${temp_json}" "${RUN_REPORT_JSON}"
      echo "[ERROR] RabbitMQ resource alarm observed; capacity artifact invalidated." >&2
      http_matched_enrich_provenance "${run_status}" "${benchmark_contract}"
      return 3
    fi
  else
    echo "[WARN] could not extract result JSON from ${RUN_REPORT_LOG}" >&2
    jq -n \
      --arg runId "${RUN_ID}" \
      --arg contract "${benchmark_contract}" \
      --arg log "${RUN_REPORT_LOG}" \
      --arg diagnostics "${RUN_DIAG_DIR}" \
      --argjson exitStatus "${run_status}" \
      '{
        benchmarkArtifactType: "harness-failure",
        benchmarkContract: $contract,
        runId: $runId,
        processExitStatus: $exitStatus,
        validForCapacityEvidence: false,
        capacityInvalidReasons: ["benchmark_harness_failed_before_result"],
        runLog: $log,
        diagnosticsDirectory: $diagnostics
      }' > "${RUN_REPORT_JSON}"
    echo "[INFO] persisted rejected harness-failure JSON=${RUN_REPORT_JSON}"
  fi
  http_matched_enrich_provenance "${run_status}" "${benchmark_contract}"
}

http_matched_validate_common() {
  BENCHMARK_EVIDENCE_MODE="${BENCHMARK_EVIDENCE_MODE:-diagnostic}"
  case "${BENCHMARK_EVIDENCE_MODE}" in
    diagnostic|release-pinned)
      ;;
    *)
      echo "[ERROR] unsupported BENCHMARK_EVIDENCE_MODE=${BENCHMARK_EVIDENCE_MODE}" >&2
      return 2
      ;;
  esac
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
  http_matched_prepare_provenance
}

http_matched_assert_environment() {
  if [[ "${ASSERT_LOADTEST_ENVIRONMENT}" != "true" ]]; then
    return 0
  fi
  RABBIT_CONTAINER="${LOADTEST_RABBIT_CONTAINER}" \
    REDIS_CONTAINER="${LOADTEST_REDIS_CONTAINER}" \
    bash "${ROOT_DIR}/scripts/load-test/assert-loadtest-environment.sh"

  local nodes_json
  if ! nodes_json="$(curl -fsS -u "${RABBIT_USER}:${RABBIT_PASSWORD}" \
      "${RABBIT_MANAGEMENT_URL}/api/nodes?columns=name,mem_alarm,disk_free_alarm")"; then
    echo "[ERROR] RabbitMQ resource alarm state is not readable." >&2
    return 2
  fi
  if jq -e 'any(.[]; (.mem_alarm // false) or (.disk_free_alarm // false))' \
      <<< "${nodes_json}" >/dev/null; then
    echo "[ERROR] RabbitMQ resource alarm is active before the benchmark." >&2
    jq -r '.[] | select((.mem_alarm // false) or (.disk_free_alarm // false)) | [.name, .mem_alarm, .disk_free_alarm] | @tsv' \
      <<< "${nodes_json}" >&2
    return 2
  fi
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
