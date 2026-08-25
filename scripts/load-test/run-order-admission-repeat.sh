#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"

RUN_PREFIX="${1:-GLT_$(date +%Y%m%d)_ORDER_ADMISSION_REPEAT}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-light}"
REPEATS="${REPEATS:-3}"
WARMUP_ENABLED="${WARMUP_ENABLED:-false}"
WARMUP_TARGET_TPS="${WARMUP_TARGET_TPS:-1000}"
WARMUP_DURATION_SECONDS="${WARMUP_DURATION_SECONDS:-1}"
WARMUP_EVENTS="${WARMUP_EVENTS:-$((WARMUP_TARGET_TPS * WARMUP_DURATION_SECONDS))}"
WARMUP_RUN_ID="${RUN_PREFIX}_WARMUP"
MIN_ORDERBOOK_TPS_RATIO="${MIN_ORDERBOOK_TPS_RATIO:-0}"
STOP_SERVICES_BEFORE_RUN="${STOP_SERVICES_BEFORE_RUN:-true}"
RESTART_SERVICES_EACH_REPEAT="${RESTART_SERVICES_EACH_REPEAT:-true}"

if (( REPEATS < 2 )); then
  echo "[ERROR] REPEATS must be at least 2 for a repeat run." >&2
  exit 2
fi

case "${DIAGNOSTICS_LEVEL}" in
  none|light|deep) ;;
  *)
    echo "[ERROR] DIAGNOSTICS_LEVEL must be one of: none, light, deep" >&2
    exit 2
    ;;
esac

if [[ "${WARMUP_ENABLED}" == "true" && "${RESTART_SERVICES_EACH_REPEAT}" == "true" ]]; then
  echo "[INFO] warm-up mode reuses the warmed service JVMs; overriding restartServicesEachRepeat=false"
  RESTART_SERVICES_EACH_REPEAT=false
fi

SERVICE_METRICS_CUMULATIVE_ACROSS_RUNS=false
if [[ "${RESTART_SERVICES_EACH_REPEAT}" == "false" ]]; then
  SERVICE_METRICS_CUMULATIVE_ACROSS_RUNS=true
fi

mkdir -p "${REPORT_DIR}"

echo "[INFO] repeated order-admission-chain load test"
echo "[INFO] runPrefix=${RUN_PREFIX}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, repeats=${REPEATS}, warmupEnabled=${WARMUP_ENABLED}, warmupTargetTps=${WARMUP_TARGET_TPS}, warmupDurationSeconds=${WARMUP_DURATION_SECONDS}, warmupEvents=${WARMUP_EVENTS}"
echo "[INFO] minOrderbookTpsRatio=${MIN_ORDERBOOK_TPS_RATIO}, stopServicesBeforeRun=${STOP_SERVICES_BEFORE_RUN}, restartServicesEachRepeat=${RESTART_SERVICES_EACH_REPEAT}"
if [[ "${SERVICE_METRICS_CUMULATIVE_ACROSS_RUNS}" == "true" ]]; then
  echo "[WARN] service component metrics are cumulative across the reused JVM lifetime; use adjacent count/sum deltas for per-run component means"
fi

SERVICES_STARTED_BY_REPEAT=false

cleanup_services() {
  if [[ "${SERVICES_STARTED_BY_REPEAT}" == "true" ]]; then
    bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
    SERVICES_STARTED_BY_REPEAT=false
  fi
}
trap cleanup_services EXIT

if [[ "${STOP_SERVICES_BEFORE_RUN}" == "true" ]]; then
  bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"
fi

extract_result_json() {
  local run_id="$1"
  local run_log="${REPORT_DIR}/order-admission-${run_id}.log"
  local result_json="${REPORT_DIR}/order-admission-${run_id}-result.json"
  local tmp_json="${result_json}.tmp"

  if [[ ! -s "${run_log}" ]]; then
    echo "[ERROR] expected run log was not created: ${run_log}" >&2
    return 1
  fi

  awk '
    /^\{/ { capture = 1 }
    capture { print }
    /^\}/ { capture = 0 }
  ' "${run_log}" > "${tmp_json}"

  if ! jq . "${tmp_json}" > "${result_json}"; then
    echo "[ERROR] could not extract result json from run log: ${run_log}" >&2
    rm -f "${tmp_json}" "${result_json}"
    return 1
  fi
  rm -f "${tmp_json}"
}

if [[ "${WARMUP_ENABLED}" == "true" ]]; then
  echo
  echo "[INFO] warm-up: runId=${WARMUP_RUN_ID}"
  SERVICES_STARTED_BY_REPEAT=true
  bash "${ROOT_DIR}/scripts/load-test/run-order-admission-chain-10k.sh" \
    --run-id "${WARMUP_RUN_ID}" \
    --target-tps "${WARMUP_TARGET_TPS}" \
    --duration-seconds "${WARMUP_DURATION_SECONDS}" \
    --events "${WARMUP_EVENTS}" \
    --diagnostics-level none \
    --stop-services-after-run false
fi

RESULT_FILES=()
for run_index in $(seq 1 "${REPEATS}"); do
  RUN_ID="${RUN_PREFIX}_R${run_index}"
  RESULT_JSON="${REPORT_DIR}/order-admission-${RUN_ID}-result.json"

  echo
  echo "[INFO] repeat ${run_index}/${REPEATS}: runId=${RUN_ID}"
  if [[ "${run_index}" != "1" && "${RESTART_SERVICES_EACH_REPEAT}" == "true" ]]; then
    bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh"
    SERVICES_STARTED_BY_REPEAT=false
  fi
  START_SERVICES_FOR_REPEAT=false
  if [[ "${WARMUP_ENABLED}" != "true" && "${run_index}" == "1" ]]; then
    START_SERVICES_FOR_REPEAT=true
  elif [[ "${RESTART_SERVICES_EACH_REPEAT}" == "true" ]]; then
    START_SERVICES_FOR_REPEAT=true
  fi
  if [[ "${START_SERVICES_FOR_REPEAT}" == "true" ]]; then
    SERVICES_STARTED_BY_REPEAT=true
  fi
  RUN_ARGS=(
    --run-id "${RUN_ID}"
    --start-services "${START_SERVICES_FOR_REPEAT}"
    --stop-services-after-run false
    --diagnostics-level "${DIAGNOSTICS_LEVEL}"
  )
  bash "${ROOT_DIR}/scripts/load-test/run-order-admission-chain-10k.sh" \
    "${RUN_ARGS[@]}"

  extract_result_json "${RUN_ID}"
  if [[ ! -s "${RESULT_JSON}" ]]; then
    echo "[ERROR] expected result json was not created: ${RESULT_JSON}" >&2
    exit 1
  fi
  RESULT_FILES+=("${RESULT_JSON}")
done

SUMMARY_JSON="${REPORT_DIR}/order-admission-repeat-${RUN_PREFIX}-summary.json"
jq -s \
  --arg runPrefix "${RUN_PREFIX}" \
  --arg diagnosticsLevel "${DIAGNOSTICS_LEVEL}" \
  --argjson repeats "${REPEATS}" \
  --argjson minOrderbookTpsRatio "${MIN_ORDERBOOK_TPS_RATIO}" \
  --argjson warmupEnabled "${WARMUP_ENABLED}" \
  --argjson restartServicesEachRepeat "${RESTART_SERVICES_EACH_REPEAT}" \
  --argjson serviceMetricsCumulativeAcrossRuns "${SERVICE_METRICS_CUMULATIVE_ACROSS_RUNS}" \
  --arg reportDir "${REPORT_DIR}" '
  def nums(k): map(. [k] | select(type == "number"));
  def avg(a): if (a | length) == 0 then null else (a | add) / (a | length) end;
  def median(a):
    if (a | length) == 0 then null
    else
      (a | sort) as $s
      | ($s | length) as $n
      | if ($n % 2) == 1
        then $s[(($n - 1) / 2)]
        else (($s[($n / 2) - 1] + $s[($n / 2)]) / 2)
        end
    end;
  def minv(a): if (a | length) == 0 then null else (a | min) end;
  def maxv(a): if (a | length) == 0 then null else (a | max) end;
  def stat(k):
    nums(k) as $values
    | avg($values) as $avg
    | median($values) as $median
    | minv($values) as $min
    | maxv($values) as $max
    | {
        count: ($values | length),
        avg: $avg,
        median: $median,
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
  def validRun:
    (
      (.benchmarkSchemaVersion // 0) == 2
      and (.validForCapacityComparison // false) == true
      and ((.capacityInvalidReasons // []) | length) == 0
      and (.httpAccepted // 0) == (.events // -1)
      and (.finalQueueBacklog // 0) == 0
      and (.queueMetricsReadFailures // 0) == 0
      and (
        $minOrderbookTpsRatio <= 0
        or ((.businessOrderbookAdmissionTps // 0) >= ((.targetTps // 0) * $minOrderbookTpsRatio))
      )
    );
  def invalidReasons:
    [
      (if (.benchmarkSchemaVersion // 0) != 2 then "unsupported_benchmark_schema" else empty end),
      (if (.validForCapacityComparison // false) != true then "capacity_comparison_invalid" else empty end),
      (if ((.capacityInvalidReasons // []) | length) != 0 then "capacity_invalid_reasons_present" else empty end),
      (if (.httpAccepted // 0) != (.events // -1) then "http_accepted_mismatch" else empty end),
      (if (.finalQueueBacklog // 0) != 0 then "final_queue_backlog" else empty end),
      (if (.queueMetricsReadFailures // 0) != 0 then "queue_metrics_read_failures" else empty end),
      (if $minOrderbookTpsRatio > 0 and ((.businessOrderbookAdmissionTps // 0) < ((.targetTps // 0) * $minOrderbookTpsRatio)) then "orderbook_tps_below_threshold" else empty end)
    ];
  def withValidity:
    . + {
      validForRepeatSummary: validRun,
      repeatInvalidReasons: invalidReasons
    };
  map(withValidity) as $runs
  | ($runs | map(select(.validForRepeatSummary))) as $validRuns
  | {
    runPrefix: $runPrefix,
    diagnosticsLevel: $diagnosticsLevel,
    config: {
      repeats: $repeats,
      minOrderbookTpsRatio: $minOrderbookTpsRatio,
      warmupEnabled: $warmupEnabled,
      restartServicesEachRepeat: $restartServicesEachRepeat,
      serviceMetricsCumulativeAcrossRuns: $serviceMetricsCumulativeAcrossRuns
    },
    validity: {
      validRuns: ($validRuns | length),
      invalidRuns: (($runs | length) - ($validRuns | length)),
      invalidRunIds: ($runs | map(select(.validForRepeatSummary | not) | {runId, repeatInvalidReasons, capacityInvalidReasons}))
    },
    runs: ($runs | map({
      runId,
      validForRepeatSummary,
      repeatInvalidReasons,
      serviceMetricsCumulativeAcrossRuns: $serviceMetricsCumulativeAcrossRuns,
      resultJson: ($reportDir + "/order-admission-" + .runId + "-result.json"),
      benchmarkSchemaVersion,
      targetTps,
      events,
      httpAccepted,
      httpAcceptedTps,
      httpAcceptedP95Ms,
      httpAcceptedP99Ms,
      businessOrderbookAdmissionTps,
      businessOrderAdmissionConvergenceTps,
      orderAdmissionGateElapsedSeconds,
      businessOrderAdmissionQueueDrainTailSeconds,
      orderCommandConnectionAcquireMeanMs,
      orderCommandConnectionAcquireMaxMs,
      orderCommandConnectionUsageMeanMs,
      orderCommandConnectionUsageMaxMs,
      orderSubmissionControllerBuyTotalMeanMs,
      orderSubmissionControllerSellTotalMeanMs,
      orderSubmissionControllerAfterServiceMeanMs,
      orderSubmissionTotalMeanMs,
      orderSubmissionTotalMaxMs,
      orderSubmissionPreEventStoreMeanMs,
      orderSubmissionPreEventStoreMaxMs,
      orderSubmissionRateLimitCheckMeanMs,
      orderSubmissionRateLimitAspectMeanMs,
      orderSubmissionRateLimitKeyExtractionMeanMs,
      orderSubmissionMarketSequenceMeanMs,
      orderSubmissionMarketSequenceMaxMs,
      orderSubmissionEventStoreRequestMeanMs,
      orderSubmissionEventStoreRequestMaxMs,
      orderSubmissionServiceUnattributedMeanMs,
      orderSubmissionPreEventStoreUnattributedMeanMs,
      orderSubmissionEventStoreEnvelopeGapMeanMs,
      orderSubmissionAppendTransactionUnattributedMeanMs,
      orderSubmissionAppendDbPoolGapMeanMs,
      orderSubmissionAppendTransactionBeforeCallbackMeanMs,
      orderSubmissionAppendTransactionBeforeCallbackMaxMs,
      orderSubmissionAppendInitialAppendCteMeanMs,
      orderSubmissionAppendInitialAppendCteMaxMs,
      orderAssetReservationConfirmedBatchSizeMean,
      orderAssetReservationConfirmedBatchSizeCount,
      orderAssetReservationConfirmedBatchSizeSum,
      orderAssetReservationAppendTransactionTotalMeanMs,
      orderAssetReservationAppendTransactionBeforeCallbackMeanMs,
      orderAssetReservationAppendTransactionBodyMeanMs,
      orderAssetReservationAppendTransactionAfterBodyMeanMs,
      orderAssetReservationAppendLockHeadsMeanMs,
      orderAssetReservationAppendExecuteCteMeanMs,
      orderAssetReservationAppendFallbackIndividualCount,
      walletOrderSubmittedTransactionMeanMs,
      walletOrderSubmittedReservationCteMeanMs,
      matchEngineReserveRedisEvalMeanMs,
      finalQueueBacklog,
      queueMetricsReadFailures
    })),
    metrics: {
      allRuns: {
        httpAcceptedTps: ($runs | stat("httpAcceptedTps")),
        httpAcceptedP95Ms: ($runs | stat("httpAcceptedP95Ms")),
        httpAcceptedP99Ms: ($runs | stat("httpAcceptedP99Ms")),
        businessOrderbookAdmissionTps: ($runs | stat("businessOrderbookAdmissionTps")),
        businessOrderAdmissionConvergenceTps: ($runs | stat("businessOrderAdmissionConvergenceTps")),
        orderAdmissionGateElapsedSeconds: ($runs | stat("orderAdmissionGateElapsedSeconds")),
        orderCommandConnectionAcquireMeanMs: ($runs | stat("orderCommandConnectionAcquireMeanMs")),
        orderCommandConnectionAcquireMaxMs: ($runs | stat("orderCommandConnectionAcquireMaxMs")),
        orderCommandConnectionUsageMeanMs: ($runs | stat("orderCommandConnectionUsageMeanMs")),
        orderCommandConnectionUsageMaxMs: ($runs | stat("orderCommandConnectionUsageMaxMs")),
        orderSubmissionControllerBuyTotalMeanMs: ($runs | stat("orderSubmissionControllerBuyTotalMeanMs")),
        orderSubmissionControllerSellTotalMeanMs: ($runs | stat("orderSubmissionControllerSellTotalMeanMs")),
        orderSubmissionControllerAfterServiceMeanMs: ($runs | stat("orderSubmissionControllerAfterServiceMeanMs")),
        orderSubmissionTotalMeanMs: ($runs | stat("orderSubmissionTotalMeanMs")),
        orderSubmissionTotalMaxMs: ($runs | stat("orderSubmissionTotalMaxMs")),
        orderSubmissionPreEventStoreMeanMs: ($runs | stat("orderSubmissionPreEventStoreMeanMs")),
        orderSubmissionPreEventStoreMaxMs: ($runs | stat("orderSubmissionPreEventStoreMaxMs")),
        orderSubmissionRateLimitCheckMeanMs: ($runs | stat("orderSubmissionRateLimitCheckMeanMs")),
        orderSubmissionRateLimitAspectMeanMs: ($runs | stat("orderSubmissionRateLimitAspectMeanMs")),
        orderSubmissionRateLimitKeyExtractionMeanMs: ($runs | stat("orderSubmissionRateLimitKeyExtractionMeanMs")),
        orderSubmissionMarketSequenceMeanMs: ($runs | stat("orderSubmissionMarketSequenceMeanMs")),
        orderSubmissionMarketSequenceMaxMs: ($runs | stat("orderSubmissionMarketSequenceMaxMs")),
        orderSubmissionEventStoreRequestMeanMs: ($runs | stat("orderSubmissionEventStoreRequestMeanMs")),
        orderSubmissionEventStoreRequestMaxMs: ($runs | stat("orderSubmissionEventStoreRequestMaxMs")),
        orderSubmissionServiceUnattributedMeanMs: ($runs | stat("orderSubmissionServiceUnattributedMeanMs")),
        orderSubmissionPreEventStoreUnattributedMeanMs: ($runs | stat("orderSubmissionPreEventStoreUnattributedMeanMs")),
        orderSubmissionEventStoreEnvelopeGapMeanMs: ($runs | stat("orderSubmissionEventStoreEnvelopeGapMeanMs")),
        orderSubmissionAppendTransactionUnattributedMeanMs: ($runs | stat("orderSubmissionAppendTransactionUnattributedMeanMs")),
        orderSubmissionAppendDbPoolGapMeanMs: ($runs | stat("orderSubmissionAppendDbPoolGapMeanMs")),
        orderSubmissionAppendTransactionBeforeCallbackMeanMs: ($runs | stat("orderSubmissionAppendTransactionBeforeCallbackMeanMs")),
        orderSubmissionAppendTransactionBeforeCallbackMaxMs: ($runs | stat("orderSubmissionAppendTransactionBeforeCallbackMaxMs")),
        orderSubmissionAppendInitialAppendCteMeanMs: ($runs | stat("orderSubmissionAppendInitialAppendCteMeanMs")),
        orderSubmissionAppendInitialAppendCteMaxMs: ($runs | stat("orderSubmissionAppendInitialAppendCteMaxMs")),
        orderAssetReservationConfirmedBatchSizeMean: ($runs | stat("orderAssetReservationConfirmedBatchSizeMean")),
        walletOrderSubmittedTransactionMeanMs: ($runs | stat("walletOrderSubmittedTransactionMeanMs")),
        orderAssetReservationAppendTransactionTotalMeanMs: ($runs | stat("orderAssetReservationAppendTransactionTotalMeanMs")),
        orderAssetReservationAppendTransactionBeforeCallbackMeanMs: ($runs | stat("orderAssetReservationAppendTransactionBeforeCallbackMeanMs")),
        orderAssetReservationAppendTransactionBodyMeanMs: ($runs | stat("orderAssetReservationAppendTransactionBodyMeanMs")),
        orderAssetReservationAppendTransactionAfterBodyMeanMs: ($runs | stat("orderAssetReservationAppendTransactionAfterBodyMeanMs")),
        orderAssetReservationAppendLockHeadsMeanMs: ($runs | stat("orderAssetReservationAppendLockHeadsMeanMs")),
        orderAssetReservationAppendExecuteCteMeanMs: ($runs | stat("orderAssetReservationAppendExecuteCteMeanMs")),
        orderAssetReservationAppendFallbackIndividualCount: ($runs | stat("orderAssetReservationAppendFallbackIndividualCount")),
        matchEngineReserveRedisEvalMeanMs: ($runs | stat("matchEngineReserveRedisEvalMeanMs"))
      },
      validRunsOnly: {
        httpAcceptedTps: ($validRuns | stat("httpAcceptedTps")),
        httpAcceptedP95Ms: ($validRuns | stat("httpAcceptedP95Ms")),
        httpAcceptedP99Ms: ($validRuns | stat("httpAcceptedP99Ms")),
        businessOrderbookAdmissionTps: ($validRuns | stat("businessOrderbookAdmissionTps")),
        businessOrderAdmissionConvergenceTps: ($validRuns | stat("businessOrderAdmissionConvergenceTps")),
        orderAdmissionGateElapsedSeconds: ($validRuns | stat("orderAdmissionGateElapsedSeconds")),
        orderCommandConnectionAcquireMeanMs: ($validRuns | stat("orderCommandConnectionAcquireMeanMs")),
        orderCommandConnectionAcquireMaxMs: ($validRuns | stat("orderCommandConnectionAcquireMaxMs")),
        orderCommandConnectionUsageMeanMs: ($validRuns | stat("orderCommandConnectionUsageMeanMs")),
        orderCommandConnectionUsageMaxMs: ($validRuns | stat("orderCommandConnectionUsageMaxMs")),
        orderSubmissionControllerBuyTotalMeanMs: ($validRuns | stat("orderSubmissionControllerBuyTotalMeanMs")),
        orderSubmissionControllerSellTotalMeanMs: ($validRuns | stat("orderSubmissionControllerSellTotalMeanMs")),
        orderSubmissionControllerAfterServiceMeanMs: ($validRuns | stat("orderSubmissionControllerAfterServiceMeanMs")),
        orderSubmissionTotalMeanMs: ($validRuns | stat("orderSubmissionTotalMeanMs")),
        orderSubmissionTotalMaxMs: ($validRuns | stat("orderSubmissionTotalMaxMs")),
        orderSubmissionPreEventStoreMeanMs: ($validRuns | stat("orderSubmissionPreEventStoreMeanMs")),
        orderSubmissionPreEventStoreMaxMs: ($validRuns | stat("orderSubmissionPreEventStoreMaxMs")),
        orderSubmissionRateLimitCheckMeanMs: ($validRuns | stat("orderSubmissionRateLimitCheckMeanMs")),
        orderSubmissionRateLimitAspectMeanMs: ($validRuns | stat("orderSubmissionRateLimitAspectMeanMs")),
        orderSubmissionRateLimitKeyExtractionMeanMs: ($validRuns | stat("orderSubmissionRateLimitKeyExtractionMeanMs")),
        orderSubmissionMarketSequenceMeanMs: ($validRuns | stat("orderSubmissionMarketSequenceMeanMs")),
        orderSubmissionMarketSequenceMaxMs: ($validRuns | stat("orderSubmissionMarketSequenceMaxMs")),
        orderSubmissionEventStoreRequestMeanMs: ($validRuns | stat("orderSubmissionEventStoreRequestMeanMs")),
        orderSubmissionEventStoreRequestMaxMs: ($validRuns | stat("orderSubmissionEventStoreRequestMaxMs")),
        orderSubmissionServiceUnattributedMeanMs: ($validRuns | stat("orderSubmissionServiceUnattributedMeanMs")),
        orderSubmissionPreEventStoreUnattributedMeanMs: ($validRuns | stat("orderSubmissionPreEventStoreUnattributedMeanMs")),
        orderSubmissionEventStoreEnvelopeGapMeanMs: ($validRuns | stat("orderSubmissionEventStoreEnvelopeGapMeanMs")),
        orderSubmissionAppendTransactionUnattributedMeanMs: ($validRuns | stat("orderSubmissionAppendTransactionUnattributedMeanMs")),
        orderSubmissionAppendDbPoolGapMeanMs: ($validRuns | stat("orderSubmissionAppendDbPoolGapMeanMs")),
        orderSubmissionAppendTransactionBeforeCallbackMeanMs: ($validRuns | stat("orderSubmissionAppendTransactionBeforeCallbackMeanMs")),
        orderSubmissionAppendTransactionBeforeCallbackMaxMs: ($validRuns | stat("orderSubmissionAppendTransactionBeforeCallbackMaxMs")),
        orderSubmissionAppendInitialAppendCteMeanMs: ($validRuns | stat("orderSubmissionAppendInitialAppendCteMeanMs")),
        orderSubmissionAppendInitialAppendCteMaxMs: ($validRuns | stat("orderSubmissionAppendInitialAppendCteMaxMs")),
        orderAssetReservationConfirmedBatchSizeMean: ($validRuns | stat("orderAssetReservationConfirmedBatchSizeMean")),
        walletOrderSubmittedTransactionMeanMs: ($validRuns | stat("walletOrderSubmittedTransactionMeanMs")),
        orderAssetReservationAppendTransactionTotalMeanMs: ($validRuns | stat("orderAssetReservationAppendTransactionTotalMeanMs")),
        orderAssetReservationAppendTransactionBeforeCallbackMeanMs: ($validRuns | stat("orderAssetReservationAppendTransactionBeforeCallbackMeanMs")),
        orderAssetReservationAppendTransactionBodyMeanMs: ($validRuns | stat("orderAssetReservationAppendTransactionBodyMeanMs")),
        orderAssetReservationAppendTransactionAfterBodyMeanMs: ($validRuns | stat("orderAssetReservationAppendTransactionAfterBodyMeanMs")),
        orderAssetReservationAppendLockHeadsMeanMs: ($validRuns | stat("orderAssetReservationAppendLockHeadsMeanMs")),
        orderAssetReservationAppendExecuteCteMeanMs: ($validRuns | stat("orderAssetReservationAppendExecuteCteMeanMs")),
        orderAssetReservationAppendFallbackIndividualCount: ($validRuns | stat("orderAssetReservationAppendFallbackIndividualCount")),
        matchEngineReserveRedisEvalMeanMs: ($validRuns | stat("matchEngineReserveRedisEvalMeanMs"))
      }
    }
  }
  ' "${RESULT_FILES[@]}" > "${SUMMARY_JSON}"

echo
echo "[INFO] repeat summary json=${SUMMARY_JSON}"
jq '{config, validity, metrics}' "${SUMMARY_JSON}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${SUMMARY_JSON}" >/dev/null
echo "[INFO] readable report=${SUMMARY_JSON%.json}-report.md"
