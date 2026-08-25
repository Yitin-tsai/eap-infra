#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
MODE="${1:---plan}"
RUN_PREFIX="${RUN_PREFIX:-GLT_$(date +%Y%m%d_%H%M%S)_FRONT_HALF_POOL_BUDGET}"
TARGET_TPS="${TARGET_TPS:-1300}"
EVENTS="${EVENTS:-10000}"
DURATION_SECONDS="${DURATION_SECONDS:-$(( (EVENTS + TARGET_TPS - 1) / TARGET_TPS ))}"
REPEATS="${REPEATS:-2}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-light}"
MIN_ORDERBOOK_TPS_RATIO="${MIN_ORDERBOOK_TPS_RATIO:-0.90}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/load-test/run-front-half-pool-budget-matrix.sh --plan
  bash scripts/load-test/run-front-half-pool-budget-matrix.sh --execute

The matrix changes one coordinated variable: the Order service JDBC connection
budget split across command, consumer, and projection workloads. It is a
front-half contention experiment, not a full-chain capacity claim.
EOF
}

case "${MODE}" in
  --plan|--execute) ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for value_name in TARGET_TPS EVENTS DURATION_SECONDS REPEATS; do
  value="${!value_name}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] ${value_name} must be a positive integer: ${value}" >&2
    exit 2
  fi
done
if (( REPEATS < 2 )); then
  echo "[ERROR] REPEATS must be at least 2" >&2
  exit 2
fi

# name:commandMax:commandMin:consumerMax:consumerMin:projectionMax:projectionMin
PROFILES=(
  "baseline-58:35:35:20:5:3:1"
  "balanced-48:30:20:16:4:2:1"
  "balanced-40:26:16:12:3:2:1"
)

print_profile() {
  local profile="$1"
  IFS=: read -r name command_max command_min consumer_max consumer_min projection_max projection_min <<< "${profile}"
  local total_max=$((command_max + consumer_max + projection_max))
  printf '%-12s command=%s/%s consumer=%s/%s projection=%s/%s totalMax=%s\n' \
    "${name}" "${command_max}" "${command_min}" "${consumer_max}" "${consumer_min}" \
    "${projection_max}" "${projection_min}" "${total_max}"
}

echo "[INFO] front-half Order JDBC pool-budget matrix"
echo "[INFO] mode=${MODE}, runPrefix=${RUN_PREFIX}"
echo "[INFO] targetTps=${TARGET_TPS}, events=${EVENTS}, durationSeconds=${DURATION_SECONDS}, repeats=${REPEATS}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, minOrderbookTpsRatio=${MIN_ORDERBOOK_TPS_RATIO}"
for profile in "${PROFILES[@]}"; do
  print_profile "${profile}"
done

if [[ "${MODE}" == "--plan" ]]; then
  echo "[INFO] plan only; pass --execute to run the matrix"
  exit 0
fi

mkdir -p "${REPORT_DIR}"
MATRIX_ROWS="${REPORT_DIR}/front-half-pool-budget-${RUN_PREFIX}-rows.jsonl"
MATRIX_SUMMARY="${REPORT_DIR}/front-half-pool-budget-${RUN_PREFIX}-summary.json"
rm -f "${MATRIX_ROWS}" "${MATRIX_SUMMARY}"
overall_status=0

for profile in "${PROFILES[@]}"; do
  IFS=: read -r name command_max command_min consumer_max consumer_min projection_max projection_min <<< "${profile}"
  candidate_prefix="${RUN_PREFIX}_${name}"
  candidate_summary="${REPORT_DIR}/order-admission-repeat-${candidate_prefix}-summary.json"
  total_max=$((command_max + consumer_max + projection_max))

  echo
  echo "[INFO] executing ${name}; coordinated Order JDBC max budget=${total_max}"
  set +e
  EAP_ORDER_COMMAND_POOL_SIZE="${command_max}" \
  EAP_ORDER_COMMAND_POOL_MIN_IDLE="${command_min}" \
  EAP_ORDER_CONSUMER_POOL_SIZE="${consumer_max}" \
  EAP_ORDER_CONSUMER_POOL_MIN_IDLE="${consumer_min}" \
  EAP_ORDER_PROJECTION_POOL_SIZE="${projection_max}" \
  EAP_ORDER_PROJECTION_POOL_MIN_IDLE="${projection_min}" \
  TARGET_TPS="${TARGET_TPS}" \
  EVENTS="${EVENTS}" \
  DURATION_SECONDS="${DURATION_SECONDS}" \
  REPEATS="${REPEATS}" \
  DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
  MIN_ORDERBOOK_TPS_RATIO="${MIN_ORDERBOOK_TPS_RATIO}" \
  WARMUP_ENABLED=false \
  RESTART_SERVICES_EACH_REPEAT=true \
    bash "${ROOT_DIR}/scripts/load-test/run-order-admission-repeat.sh" "${candidate_prefix}"
  candidate_status=$?
  set -e
  if (( candidate_status != 0 )); then
    overall_status=1
  fi

  if [[ -s "${candidate_summary}" ]]; then
    candidate_invalid_runs="$(jq -r '.validity.invalidRuns // 0' "${candidate_summary}")"
    if (( candidate_invalid_runs > 0 )); then
      overall_status=1
    fi
    jq -c \
      --arg profile "${name}" \
      --arg summary "${candidate_summary}" \
      --argjson commandMax "${command_max}" \
      --argjson commandMin "${command_min}" \
      --argjson consumerMax "${consumer_max}" \
      --argjson consumerMin "${consumer_min}" \
      --argjson projectionMax "${projection_max}" \
      --argjson projectionMin "${projection_min}" \
      --argjson totalMax "${total_max}" \
      --argjson exitStatus "${candidate_status}" \
      '{profile:$profile, pools:{command:{max:$commandMax,minIdle:$commandMin},
        consumer:{max:$consumerMax,minIdle:$consumerMin},
        projection:{max:$projectionMax,minIdle:$projectionMin}, totalMax:$totalMax},
        exitStatus:$exitStatus, summary:$summary, validity:.validity,
        metrics:{allRuns:.metrics.allRuns,
          validRunsOnly:.metrics.validRunsOnly}}' "${candidate_summary}" >> "${MATRIX_ROWS}"
  else
    jq -cn \
      --arg profile "${name}" \
      --arg summary "${candidate_summary}" \
      --argjson totalMax "${total_max}" \
      --argjson exitStatus "${candidate_status}" \
      '{profile:$profile, pools:{totalMax:$totalMax}, exitStatus:$exitStatus,
        summary:$summary, validity:null, metrics:null}' >> "${MATRIX_ROWS}"
  fi
done

jq -s \
  --arg runPrefix "${RUN_PREFIX}" \
  --argjson targetTps "${TARGET_TPS}" \
  --argjson events "${EVENTS}" \
  --argjson durationSeconds "${DURATION_SECONDS}" \
  --argjson repeats "${REPEATS}" \
  --arg diagnosticsLevel "${DIAGNOSTICS_LEVEL}" \
  --argjson minOrderbookTpsRatio "${MIN_ORDERBOOK_TPS_RATIO}" \
  '{schemaVersion:1, experiment:"order-front-half-jdbc-pool-budget",
    claimBoundary:"front-half contention diagnostic only; full-chain validation required",
    config:{runPrefix:$runPrefix,targetTps:$targetTps,events:$events,
      durationSeconds:$durationSeconds,repeats:$repeats,
      diagnosticsLevel:$diagnosticsLevel,minOrderbookTpsRatio:$minOrderbookTpsRatio},
    candidates:.}' "${MATRIX_ROWS}" > "${MATRIX_SUMMARY}"

echo
echo "[INFO] matrix summary=${MATRIX_SUMMARY}"
jq '{claimBoundary, config, candidates: [.candidates[] | {profile, pools, exitStatus, validity}]}' "${MATRIX_SUMMARY}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${MATRIX_SUMMARY}" >/dev/null
echo "[INFO] readable report=${MATRIX_SUMMARY%.json}-report.md"
exit "${overall_status}"
