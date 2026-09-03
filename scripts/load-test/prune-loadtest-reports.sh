#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-${ROOT_DIR}/build/load-test-reports}"
RAW_RETENTION_DAYS="${RAW_RETENTION_DAYS:-14}"
RESULT_RETENTION_DAYS="${RESULT_RETENTION_DAYS:-90}"
DRY_RUN="${DRY_RUN:-true}"
PRUNE_ALL_RAW="${PRUNE_ALL_RAW:-false}"

for days in "${RAW_RETENTION_DAYS}" "${RESULT_RETENTION_DAYS}"; do
  if [[ ! "${days}" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] retention days must be non-negative integers" >&2
    exit 2
  fi
done
if [[ "${DRY_RUN}" != "true" && "${DRY_RUN}" != "false" ]]; then
  echo "[ERROR] DRY_RUN must be true or false" >&2
  exit 2
fi
if [[ "${PRUNE_ALL_RAW}" != "true" && "${PRUNE_ALL_RAW}" != "false" ]]; then
  echo "[ERROR] PRUNE_ALL_RAW must be true or false" >&2
  exit 2
fi
if [[ ! -d "${REPORT_DIR}" ]]; then
  echo "[INFO] report directory does not exist: ${REPORT_DIR}"
  exit 0
fi

prune_path() {
  local path="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] remove ${path}"
  else
    rm -rf -- "${path}"
    echo "[INFO] removed ${path}"
  fi
}

find_raw_artifacts() {
  if [[ "${PRUNE_ALL_RAW}" == "true" ]]; then
    find "${REPORT_DIR}" -mindepth 1 -maxdepth 1 \
      \( -type d -name '*-diagnostics' -o -type f \( \
        -name '*.log' -o \
        -name '*-samples.csv' -o \
        -name '*-stages.csv' -o \
        -name '*-monitor.csv' -o \
        -name '*-k6.jsonl' -o \
        -name '*-vegeta.jsonl' -o \
        -name '*-vegeta.jsonl.gz' -o \
        -name '*-targets.jsonl' -o \
        -name '*-classpath.txt' -o \
        -name '*-k6-time.txt' -o \
        -name '*-vegeta-time.txt' -o \
        -name '*-remote-driver-preflight.txt' -o \
        -name '*.ready' -o \
        -name '*.stop' \
      \) \) -print0
  else
    find "${REPORT_DIR}" -mindepth 1 -maxdepth 1 \
      \( -type d -name '*-diagnostics' -o -type f \( \
        -name '*.log' -o \
        -name '*-samples.csv' -o \
        -name '*-stages.csv' -o \
        -name '*-monitor.csv' -o \
        -name '*-k6.jsonl' -o \
        -name '*-vegeta.jsonl' -o \
        -name '*-vegeta.jsonl.gz' -o \
        -name '*-targets.jsonl' -o \
        -name '*-classpath.txt' -o \
        -name '*-k6-time.txt' -o \
        -name '*-vegeta-time.txt' -o \
        -name '*-remote-driver-preflight.txt' -o \
        -name '*.ready' -o \
        -name '*.stop' \
      \) \) -mtime "+${RAW_RETENTION_DAYS}" -print0
  fi
}

while IFS= read -r -d '' path; do
  prune_path "${path}"
done < <(find_raw_artifacts)

while IFS= read -r -d '' path; do
  prune_path "${path}"
done < <(find "${REPORT_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*-result.json' \
  -mtime "+${RESULT_RETENTION_DAYS}" -print0)

echo "[INFO] retention scan complete: dryRun=${DRY_RUN}, pruneAllRaw=${PRUNE_ALL_RAW}, rawDays=${RAW_RETENTION_DAYS}, resultDays=${RESULT_RETENTION_DAYS}"
