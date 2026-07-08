#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"

RUN_PREFIX="${1:-GLT_$(date +%Y%m%d)_MARKER_REPEAT}"
REPEATS="${REPEATS:-3}"
TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-15}"
EVENTS="${EVENTS:-$((TARGET_TPS * DURATION_SECONDS))}"
PUBLISHERS="${PUBLISHERS:-128}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-$((DURATION_SECONDS + 420))}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-baseline}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-true}"

if (( REPEATS < 2 )); then
  echo "[ERROR] REPEATS must be at least 2 for a noise-reduction run." >&2
  exit 2
fi

if (( TARGET_TPS <= 0 || DURATION_SECONDS <= 0 || EVENTS <= 0 )); then
  echo "[ERROR] TARGET_TPS, DURATION_SECONDS, and EVENTS must be positive." >&2
  exit 2
fi

mkdir -p "${REPORT_DIR}"

echo "[INFO] repeated 2000 TPS marker load test"
echo "[INFO] runPrefix=${RUN_PREFIX}"
echo "[INFO] repeats=${REPEATS}, targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, publishers=${PUBLISHERS}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, timeoutSeconds=${TIMEOUT_SECONDS}"

RESULT_FILES=()
for run_index in $(seq 1 "${REPEATS}"); do
  MARKET_ID="${RUN_PREFIX}_R${run_index}"
  RESULT_JSON="${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-result.json"

  echo
  echo "[INFO] repeat ${run_index}/${REPEATS}: marketId=${MARKET_ID}"
  TARGET_TPS="${TARGET_TPS}" \
  DURATION_SECONDS="${DURATION_SECONDS}" \
  EVENTS="${EVENTS}" \
  PUBLISHERS="${PUBLISHERS}" \
  TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
  DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
  RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
    bash "${ROOT_DIR}/scripts/load-test/run-2000-ticket-marker-10k.sh" "${MARKET_ID}"

  if [[ ! -s "${RESULT_JSON}" ]]; then
    echo "[ERROR] expected result json was not created: ${RESULT_JSON}" >&2
    exit 1
  fi
  RESULT_FILES+=("${RESULT_JSON}")
done

SUMMARY_JSON="${REPORT_DIR}/matched-e2e-repeat-${RUN_PREFIX}-summary.json"
jq -s \
  --arg runPrefix "${RUN_PREFIX}" \
  --argjson repeats "${REPEATS}" \
  --argjson targetTps "${TARGET_TPS}" \
  --argjson durationSeconds "${DURATION_SECONDS}" \
  --argjson events "${EVENTS}" \
  --argjson publishers "${PUBLISHERS}" \
  --arg diagnosticsLevel "${DIAGNOSTICS_LEVEL}" '
  def nums(k): map(. [k] | select(type == "number"));
  def avg(a): if (a | length) == 0 then null else (a | add) / (a | length) end;
  def minv(a): if (a | length) == 0 then null else (a | min) end;
  def maxv(a): if (a | length) == 0 then null else (a | max) end;
  def stat(k):
    nums(k) as $values
    | avg($values) as $avg
    | minv($values) as $min
    | maxv($values) as $max
    | {
        count: ($values | length),
        avg: $avg,
        min: $min,
        max: $max,
        spread: (if $min == null or $max == null then null else $max - $min end),
        relativeSpreadPct: (
          if $avg == null or $avg == 0 or $min == null or $max == null
          then null
          else (($max - $min) * 100 / $avg)
          end
        )
      };
  {
    runPrefix: $runPrefix,
    config: {
      repeats: $repeats,
      targetTps: $targetTps,
      durationSeconds: $durationSeconds,
      events: $events,
      publishers: $publishers,
      diagnosticsLevel: $diagnosticsLevel
    },
    runs: map({
      marketId,
      actualBuyPublishTps,
      businessMatchedE2eTps,
      businessCompletionSeconds,
      tradeExecutionReachTps,
      orderCommandMatchReachTps,
      walletSettlementReachTps,
      completionMarkerReachTps,
      maxMatchEngineQueueUnacked,
      maxOrderTradeExecutedQueueUnacked,
      maxOrderTradeAppliedQueueUnacked
    }),
    metrics: {
      actualBuyPublishTps: stat("actualBuyPublishTps"),
      businessMatchedE2eTps: stat("businessMatchedE2eTps"),
      businessCompletionSeconds: stat("businessCompletionSeconds"),
      tradeExecutionReachTps: stat("tradeExecutionReachTps"),
      orderCommandMatchReachTps: stat("orderCommandMatchReachTps"),
      walletSettlementReachTps: stat("walletSettlementReachTps"),
      completionMarkerReachTps: stat("completionMarkerReachTps"),
      maxMatchEngineQueueUnacked: stat("maxMatchEngineQueueUnacked")
    }
  }
  ' "${RESULT_FILES[@]}" > "${SUMMARY_JSON}"

echo
echo "[INFO] repeat summary json=${SUMMARY_JSON}"
jq '.metrics' "${SUMMARY_JSON}"
