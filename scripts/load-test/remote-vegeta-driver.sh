#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  remote-vegeta-driver.sh preflight WORK_DIR TARGETS_FILE EXPECTED_SHA256 HEALTH_URL
  remote-vegeta-driver.sh attack WORK_DIR TARGETS_FILE RATE DURATION_NANOS CPUS WORKERS MAX_WORKERS TIMEOUT EXPECTED_RESULTS
  remote-vegeta-driver.sh cleanup WORK_DIR

This helper is copied to a remote load-generator host by
run-http-matched-external-open-loop.sh. It must not contain service credentials.
EOF
}

require_work_dir() {
  local work_dir="$1"
  if [[ ! "${work_dir}" =~ ^/tmp/eap-loadtest-[A-Za-z0-9_.-]+$ ]]; then
    echo "[ERROR] remote work directory must match /tmp/eap-loadtest-<safe-id>: ${work_dir}" >&2
    exit 2
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[ERROR] required remote command not found: ${command_name}" >&2
    exit 2
  fi
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
    return
  fi
  echo "[ERROR] sha256sum or shasum is required on the remote host" >&2
  exit 2
}

action="${1:-}"
case "${action}" in
  preflight)
    [[ $# -eq 5 ]] || { usage; exit 2; }
    work_dir="$2"
    targets_file="$3"
    expected_sha256="$4"
    health_url="$5"
    require_work_dir "${work_dir}"
    for command_name in vegeta jq gzip curl awk date uname getconf; do
      require_command "${command_name}"
    done
    [[ -f "${targets_file}" ]] || { echo "[ERROR] remote targets missing: ${targets_file}" >&2; exit 2; }
    actual_sha256="$(sha256_file "${targets_file}")"
    if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
      echo "[ERROR] remote target checksum mismatch: expected=${expected_sha256}, actual=${actual_sha256}" >&2
      exit 2
    fi
    curl -fsS --max-time 5 "${health_url}" >/dev/null
    echo "remoteEpochSeconds=$(date +%s)"
    echo "targetsSha256=${actual_sha256}"
    echo "vegetaVersion=$(vegeta --version 2>&1 | head -1)"
    echo "remoteOs=$(uname -s)"
    echo "remoteArchitecture=$(uname -m)"
    echo "remoteLogicalCpus=$(getconf _NPROCESSORS_ONLN)"
    ;;
  attack)
    [[ $# -eq 10 ]] || { usage; exit 2; }
    work_dir="$2"
    targets_file="$3"
    rate="$4"
    duration_nanos="$5"
    cpus="$6"
    workers="$7"
    max_workers="$8"
    timeout="$9"
    expected_results="${10}"
    require_work_dir "${work_dir}"
    for command_name in vegeta jq gzip wc; do
      require_command "${command_name}"
    done
    if [[ ! -x /usr/bin/time ]]; then
      echo "[ERROR] /usr/bin/time is required on the remote host" >&2
      exit 2
    fi
    mkdir -p "${work_dir}"
    results_gz="${work_dir}/results.jsonl.gz"
    report_json="${work_dir}/vegeta-report.json"
    time_file="${work_dir}/vegeta-time.txt"
    metadata_json="${work_dir}/remote-driver-metadata.json"
    rm -f "${results_gz}" "${report_json}" "${time_file}" "${metadata_json}"

    set +e
    /usr/bin/time -p -o "${time_file}" vegeta -cpus="${cpus}" attack \
      -lazy \
      -format=json \
      -targets="${targets_file}" \
      -rate="${rate}/1s" \
      -duration="${duration_nanos}ns" \
      -workers="${workers}" \
      -max-workers="${max_workers}" \
      -timeout="${timeout}" \
      -max-body=0 \
      | vegeta encode --to=json \
      | jq -c 'select(.error != "no targets to attack") | {timestamp, latency, code, url, error}' \
      | gzip -1 > "${results_gz}"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    for status in "${pipeline_status[@]}"; do
      if (( status != 0 )); then
        echo "[ERROR] remote Vegeta pipeline failed: statuses=${pipeline_status[*]}" >&2
        exit "${status}"
      fi
    done

    actual_results="$(gzip -dc "${results_gz}" | wc -l | awk '{print $1}')"
    if [[ "${actual_results}" != "${expected_results}" ]]; then
      echo "[ERROR] remote result count mismatch: expected=${expected_results}, actual=${actual_results}" >&2
      exit 1
    fi
    gzip -dc "${results_gz}" | vegeta report -type=json > "${report_json}"
    jq -n \
      --argjson expectedResults "${expected_results}" \
      --argjson actualResults "${actual_results}" \
      --argjson rate "${rate}" \
      --argjson durationNanos "${duration_nanos}" \
      --argjson cpus "${cpus}" \
      --argjson workers "${workers}" \
      --argjson maxWorkers "${max_workers}" \
      --arg timeout "${timeout}" \
      --arg completedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{expectedResults:$expectedResults, actualResults:$actualResults, rate:$rate,
        durationNanos:$durationNanos, cpus:$cpus, workers:$workers,
        maxWorkers:$maxWorkers, timeout:$timeout, completedAt:$completedAt}' \
      > "${metadata_json}"
    ;;
  cleanup)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    work_dir="$2"
    require_work_dir "${work_dir}"
    rm -rf -- "${work_dir}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
