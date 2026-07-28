#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"

RUN_PREFIX="${1:-GLT_$(date +%Y%m%d)_MATCHED_TRADE_COMPLETION_REPEAT}"
REPEATS="${REPEATS:-3}"
TARGET_TPS="${TARGET_TPS:-2000}"
DURATION_SECONDS="${DURATION_SECONDS:-15}"
EVENTS="${EVENTS:-$((TARGET_TPS * DURATION_SECONDS))}"
PUBLISHERS="${PUBLISHERS:-1}"
PUBLISHER_CONNECTION_CACHE_SIZE="${PUBLISHER_CONNECTION_CACHE_SIZE:-}"
PUBLISHER_MAX_IN_FLIGHT="${PUBLISHER_MAX_IN_FLIGHT:-}"
PUBLISHER_CONFIRM_TIMEOUT_MS="${PUBLISHER_CONFIRM_TIMEOUT_MS:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-$((DURATION_SECONDS + 420))}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-baseline}"
RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN:-true}"
MIN_OFFERED_TPS_RATIO="${MIN_OFFERED_TPS_RATIO:-0.95}"

if (( REPEATS < 2 )); then
  echo "[ERROR] REPEATS must be at least 2 for a noise-reduction run." >&2
  exit 2
fi

if (( TARGET_TPS <= 0 || DURATION_SECONDS <= 0 || EVENTS <= 0 )); then
  echo "[ERROR] TARGET_TPS, DURATION_SECONDS, and EVENTS must be positive." >&2
  exit 2
fi

mkdir -p "${REPORT_DIR}"

echo "[INFO] repeated matched-trade-completion-chain load test"
echo "[INFO] runPrefix=${RUN_PREFIX}"
echo "[INFO] repeats=${REPEATS}, targetTps=${TARGET_TPS}, durationSeconds=${DURATION_SECONDS}, events=${EVENTS}, publishers=${PUBLISHERS}"
echo "[INFO] publisherConnectionCacheSize=${PUBLISHER_CONNECTION_CACHE_SIZE:-default}, publisherMaxInFlight=${PUBLISHER_MAX_IN_FLIGHT:-default}, publisherConfirmTimeoutMs=${PUBLISHER_CONFIRM_TIMEOUT_MS:-default}"
echo "[INFO] diagnosticsLevel=${DIAGNOSTICS_LEVEL}, timeoutSeconds=${TIMEOUT_SECONDS}, minOfferedTpsRatio=${MIN_OFFERED_TPS_RATIO}"

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
  PUBLISHER_CONNECTION_CACHE_SIZE="${PUBLISHER_CONNECTION_CACHE_SIZE}" \
  PUBLISHER_MAX_IN_FLIGHT="${PUBLISHER_MAX_IN_FLIGHT}" \
  PUBLISHER_CONFIRM_TIMEOUT_MS="${PUBLISHER_CONFIRM_TIMEOUT_MS}" \
  TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
  DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL}" \
  MIN_OFFERED_LOAD_RATIO="${MIN_OFFERED_TPS_RATIO}" \
  RESET_PG_STATS_BEFORE_RUN="${RESET_PG_STATS_BEFORE_RUN}" \
    bash "${ROOT_DIR}/scripts/load-test/run-matched-trade-completion-10k.sh" "${MARKET_ID}"

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
  --argjson minOfferedTpsRatio "${MIN_OFFERED_TPS_RATIO}" \
  --arg reportDir "${REPORT_DIR}" \
  --arg diagnosticsLevel "${DIAGNOSTICS_LEVEL}" '
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
  def finalQueueBacklog:
    (
      (.matchEngineQueueReady // 0)
      + (.orderTradeExecutedQueueReady // 0)
      + (.walletTradeExecutedQueueReady // 0)
      + (.orderTradeAppliedQueueReady // 0)
      + (.walletTradeSettledQueueReady // 0)
      + (.matchEngineQueueUnacked // 0)
      + (.orderTradeExecutedQueueUnacked // 0)
      + (.walletTradeExecutedQueueUnacked // 0)
      + (.orderTradeAppliedQueueUnacked // 0)
      + (.walletTradeSettledQueueUnacked // 0)
    );
  def schemaValid: (.benchmarkSchemaVersion // 0) == 2;
  def validRun:
    (
      schemaValid
      and (.businessInputOrderTps // 0) >= ($targetTps * $minOfferedTpsRatio)
      and (.buyPublishFailures // 0) == 0
      and (.sellPublishFailures // 0) == 0
      and (.buyPublishBrokerAcked // 0) == $events
      and (.sellPublishBrokerAcked // 0) == $events
      and (.buyPublishBrokerNacked // 0) == 0
      and (.sellPublishBrokerNacked // 0) == 0
      and (.buyPublishReturned // 0) == 0
      and (.sellPublishReturned // 0) == 0
      and (.buyPublishConfirmTimedOut // 0) == 0
      and (.sellPublishConfirmTimedOut // 0) == 0
      and (.completedTrades // 0) == $events
      and (.tradeExecutions // 0) == $events
      and (.walletTradeSettlements // 0) == $events
      and (.completedTradeIdSetsEqual // false) == true
      and (.orderCommandMatchedRows // 0) == ($events * 2)
      and (.remainingSellOrders // 0) == 0
      and (.remainingBuyOrders // 0) == 0
      and (.activeReservations // 0) == 0
      and (.queueMetricsReadFailures // 0) == 0
      and finalQueueBacklog == 0
    );
  def invalidReasons:
    [
      (if schemaValid | not then "unsupported_benchmark_schema" else empty end),
      (if (.businessInputOrderTps // 0) < ($targetTps * $minOfferedTpsRatio) then "driver_offered_tps_below_threshold" else empty end),
      (if (.buyPublishFailures // 0) != 0 then "buy_publish_failures" else empty end),
      (if (.sellPublishFailures // 0) != 0 then "sell_publish_failures" else empty end),
      (if (.buyPublishBrokerAcked // 0) != $events then "buy_publish_broker_ack_mismatch" else empty end),
      (if (.sellPublishBrokerAcked // 0) != $events then "sell_publish_broker_ack_mismatch" else empty end),
      (if (.buyPublishBrokerNacked // 0) != 0 or (.sellPublishBrokerNacked // 0) != 0 then "publish_broker_nacks" else empty end),
      (if (.buyPublishReturned // 0) != 0 or (.sellPublishReturned // 0) != 0 then "publish_returns" else empty end),
      (if (.buyPublishConfirmTimedOut // 0) != 0 or (.sellPublishConfirmTimedOut // 0) != 0 then "publish_confirm_timeouts" else empty end),
      (if (.completedTrades // 0) != $events then "completed_trades_mismatch" else empty end),
      (if (.tradeExecutions // 0) != $events then "trade_executions_mismatch" else empty end),
      (if (.walletTradeSettlements // 0) != $events then "wallet_settlements_mismatch" else empty end),
      (if (.completedTradeIdSetsEqual // false) != true then "completed_trade_id_set_mismatch" else empty end),
      (if (.orderCommandMatchedRows // 0) != ($events * 2) then "order_command_rows_mismatch" else empty end),
      (if (.remainingSellOrders // 0) != 0 then "remaining_sell_orders" else empty end),
      (if (.remainingBuyOrders // 0) != 0 then "remaining_buy_orders" else empty end),
      (if (.activeReservations // 0) != 0 then "active_reservations" else empty end),
      (if (.queueMetricsReadFailures // 0) != 0 then "queue_metrics_read_failures" else empty end),
      (if finalQueueBacklog != 0 then "final_queue_backlog" else empty end)
    ];
  def withValidity:
    . + {
      validForPublicSummary: validRun,
      invalidReasons: invalidReasons,
      finalQueueBacklog: finalQueueBacklog
    };
  map(withValidity) as $runs
  | ($runs | map(select(.validForPublicSummary))) as $validRuns
  | {
    runPrefix: $runPrefix,
    config: {
      repeats: $repeats,
      targetTps: $targetTps,
      durationSeconds: $durationSeconds,
      events: $events,
      publishers: $publishers,
      diagnosticsLevel: $diagnosticsLevel,
      minOfferedTpsRatio: $minOfferedTpsRatio
    },
    validity: {
      validRuns: ($validRuns | length),
      invalidRuns: (($runs | length) - ($validRuns | length)),
      invalidRunIds: ($runs | map(select(.validForPublicSummary | not) | {marketId, invalidReasons}))
    },
    runs: ($runs | map({
      marketId,
      validForPublicSummary,
      invalidReasons,
      resultJson: ($reportDir + "/matched-e2e-two-phase-" + .marketId + "-result.json"),
      metaTxt: ($reportDir + "/matched-e2e-two-phase-" + .marketId + "-meta.txt"),
      runLog: ($reportDir + "/matched-e2e-two-phase-" + .marketId + "-run.log"),
      benchmarkSchemaVersion,
      publisherMode,
      publisherConnectionCacheSize,
      publisherMaxInFlight,
      businessInputAttemptedOrderTps,
      businessInputBrokerAckedOrderTps,
      businessInputOrderTps,
      buyPublishSendWindowSeconds,
      buyPublishAttempts,
      buyPublishBrokerAcked,
      buyPublishBrokerNacked,
      buyPublishReturned,
      buyPublishConfirmTimedOut,
      buyPublishConfirmWaitSeconds,
      buyPublishMaxConfirmWaitMs,
      sellPublishSendWindowSeconds,
      sellPublishAttempts,
      sellPublishBrokerAcked,
      sellPublishBrokerNacked,
      sellPublishReturned,
      sellPublishConfirmTimedOut,
      sellPublishConfirmWaitSeconds,
      sellPublishMaxConfirmWaitMs,
      businessOrderbookAdmissionTps,
      orderbookAdmissionSeconds,
      businessCompletedTradeTps,
      businessMarketFlowTps,
      businessMarketFlowSeconds,
      businessMarketFlowOrders,
      businessCompletionSeconds,
      matchEngineTradeExecutionReachTps,
      orderTradeApplicationReachTps,
      walletTradeSettlementReachTps,
      businessConvergenceReachTps,
      completedTrades,
      tradeExecutions,
      walletTradeSettlements,
      completedTradeIdSetsEqual,
      matchTradeIdCount,
      orderTradeIdCount,
      walletTradeIdCount,
      tradeIdUnionCount,
      tradeIdsMissingInMatch,
      tradeIdsMissingInOrder,
      tradeIdsMissingInWallet,
      tradeIdSetFingerprint,
      orderCommandMatchedRows,
      finalQueueBacklog,
      queueMetricsReadFailures,
      activeReservations,
      maxMatchEngineQueueUnacked,
      maxOrderTradeExecutedQueueUnacked,
      maxOrderTradeAppliedQueueUnacked
    })),
    metrics: {
      allRuns: {
        businessInputAttemptedOrderTps: ($runs | stat("businessInputAttemptedOrderTps")),
        businessInputBrokerAckedOrderTps: ($runs | stat("businessInputBrokerAckedOrderTps")),
        businessInputOrderTps: ($runs | stat("businessInputOrderTps")),
        buyPublishSendWindowSeconds: ($runs | stat("buyPublishSendWindowSeconds")),
        buyPublishConfirmWaitSeconds: ($runs | stat("buyPublishConfirmWaitSeconds")),
        buyPublishMaxConfirmWaitMs: ($runs | stat("buyPublishMaxConfirmWaitMs")),
        businessOrderbookAdmissionTps: ($runs | stat("businessOrderbookAdmissionTps")),
        businessCompletedTradeTps: ($runs | stat("businessCompletedTradeTps")),
        businessMarketFlowTps: ($runs | stat("businessMarketFlowTps")),
        businessCompletionSeconds: ($runs | stat("businessCompletionSeconds")),
        matchEngineTradeExecutionReachTps: ($runs | stat("matchEngineTradeExecutionReachTps")),
        orderTradeApplicationReachTps: ($runs | stat("orderTradeApplicationReachTps")),
        walletTradeSettlementReachTps: ($runs | stat("walletTradeSettlementReachTps")),
        businessConvergenceReachTps: ($runs | stat("businessConvergenceReachTps")),
        maxMatchEngineQueueUnacked: ($runs | stat("maxMatchEngineQueueUnacked"))
      },
      validRunsOnly: {
        businessInputAttemptedOrderTps: ($validRuns | stat("businessInputAttemptedOrderTps")),
        businessInputBrokerAckedOrderTps: ($validRuns | stat("businessInputBrokerAckedOrderTps")),
        businessInputOrderTps: ($validRuns | stat("businessInputOrderTps")),
        buyPublishSendWindowSeconds: ($validRuns | stat("buyPublishSendWindowSeconds")),
        buyPublishConfirmWaitSeconds: ($validRuns | stat("buyPublishConfirmWaitSeconds")),
        buyPublishMaxConfirmWaitMs: ($validRuns | stat("buyPublishMaxConfirmWaitMs")),
        businessOrderbookAdmissionTps: ($validRuns | stat("businessOrderbookAdmissionTps")),
        businessCompletedTradeTps: ($validRuns | stat("businessCompletedTradeTps")),
        businessMarketFlowTps: ($validRuns | stat("businessMarketFlowTps")),
        businessCompletionSeconds: ($validRuns | stat("businessCompletionSeconds")),
        matchEngineTradeExecutionReachTps: ($validRuns | stat("matchEngineTradeExecutionReachTps")),
        orderTradeApplicationReachTps: ($validRuns | stat("orderTradeApplicationReachTps")),
        walletTradeSettlementReachTps: ($validRuns | stat("walletTradeSettlementReachTps")),
        businessConvergenceReachTps: ($validRuns | stat("businessConvergenceReachTps")),
        maxMatchEngineQueueUnacked: ($validRuns | stat("maxMatchEngineQueueUnacked"))
      }
    }
  }
  ' "${RESULT_FILES[@]}" > "${SUMMARY_JSON}"

echo
echo "[INFO] repeat summary json=${SUMMARY_JSON}"
jq '{validity, metrics}' "${SUMMARY_JSON}"
