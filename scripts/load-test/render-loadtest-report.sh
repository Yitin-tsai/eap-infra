#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "usage: $0 RESULT_JSON [OUTPUT_MARKDOWN]" >&2
  exit 2
fi

RESULT_JSON="$1"
OUTPUT_MARKDOWN="${2:-${RESULT_JSON%.json}-report.md}"

if [[ ! -f "${RESULT_JSON}" ]]; then
  echo "[ERROR] result JSON does not exist: ${RESULT_JSON}" >&2
  exit 2
fi
if ! jq -e 'type == "object"' "${RESULT_JSON}" >/dev/null; then
  echo "[ERROR] result must contain one JSON object: ${RESULT_JSON}" >&2
  exit 2
fi

mkdir -p "$(dirname "${OUTPUT_MARKDOWN}")"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -r \
  --arg source "${RESULT_JSON}" \
  --arg generatedAt "${generated_at}" '
  def pick($items): ($items | map(select(. != null)) | first);
  def show:
    if . == null then "n/a"
    elif type == "boolean" then (if . then "PASS" else "FAIL" end)
    elif type == "number" then ((. * 10000 | round) / 10000 | tostring)
    elif type == "array" or type == "object" then tojson
    else tostring
    end;
  def row($label; $value):
    if $value == null then "" else "| " + $label + " | " + ($value | show) + " |\n" end;
  def required_v3_fields_missing:
    if (.benchmarkSchemaVersion // 0) >= 3
        and (.benchmarkContract == "external-http-matched-steady-state-chain"
          or .benchmarkContract == "http-matched-steady-state-chain") then
      . as $result
      | [
          "validForSustainedCapacity", "threeServiceTradeIdsEqual",
          "assetReconciliationPassed", "orderReadModelConverged",
          "finalQueueBacklog", "finalDlqBacklog", "activeMatchReservations",
          "finalOrderProjectionLagEvents", "steadyOrderInboxBacklogMax",
          "steadyOrderInboxOldestAgeMaxSeconds", "steadyOrderInboxTerminalDebtMax",
          "steadyWalletInboxBacklogMax", "steadyWalletInboxOldestAgeMaxSeconds",
          "steadyWalletInboxTerminalDebtMax", "steadyMatchInboxBacklogMax",
          "steadyMatchInboxOldestAgeMaxSeconds", "steadyMatchInboxTerminalDebtMax",
          "finalOrderInboxBacklog", "finalOrderInboxTerminalDebt",
          "finalWalletInboxBacklog", "finalWalletInboxTerminalDebt",
          "finalMatchInboxBacklog", "finalMatchInboxTerminalDebt",
          "finalOrderOutboxActiveDebt", "finalOrderOutboxTerminalDebt",
          "finalWalletOutboxActiveDebt", "finalWalletOutboxTerminalDebt",
          "finalMatchOutboxActiveDebt", "finalMatchOutboxTerminalDebt",
          "finalMatchCleanupActiveDebt", "finalMatchCleanupTerminalDebt"
        ] + (if ($result.benchmarkSchemaVersion // 0) >= 4 then [
          "steadyDurableDebtObservationsHealthy", "steadyDurableDebtComponents",
          "finalDurableDebtObservationsHealthy", "finalDurableDebtComponents"
        ] else [] end) | map(select($result[.] == null))
    elif (.requiredFieldsMissing | type) == "array" then .requiredFieldsMissing
    else [] end;
  def required_v3_fields_invalid:
    if (.benchmarkSchemaVersion // 0) >= 3
        and (.benchmarkContract == "external-http-matched-steady-state-chain"
          or .benchmarkContract == "http-matched-steady-state-chain") then
      . as $result
      | (([
          "validForSustainedCapacity", "threeServiceTradeIdsEqual",
          "assetReconciliationPassed", "orderReadModelConverged",
          "steadyDurableDebtObservationsHealthy", "finalDurableDebtObservationsHealthy"
        ] | map(select($result[.] != null and ($result[.] | type) != "boolean")))
        + ([
          "finalQueueBacklog", "finalDlqBacklog", "activeMatchReservations",
          "finalOrderProjectionLagEvents",
          "steadyOrderInboxBacklogMax", "steadyOrderInboxOldestAgeMaxSeconds",
          "steadyOrderInboxTerminalDebtMax", "steadyWalletInboxBacklogMax",
          "steadyWalletInboxOldestAgeMaxSeconds", "steadyWalletInboxTerminalDebtMax",
          "steadyMatchInboxBacklogMax", "steadyMatchInboxOldestAgeMaxSeconds",
          "steadyMatchInboxTerminalDebtMax", "finalOrderInboxBacklog",
          "finalOrderInboxTerminalDebt", "finalWalletInboxBacklog",
          "finalWalletInboxTerminalDebt", "finalMatchInboxBacklog",
          "finalMatchInboxTerminalDebt", "finalOrderOutboxActiveDebt",
          "finalOrderOutboxTerminalDebt", "finalWalletOutboxActiveDebt",
          "finalWalletOutboxTerminalDebt", "finalMatchOutboxActiveDebt",
          "finalMatchOutboxTerminalDebt", "finalMatchCleanupActiveDebt",
          "finalMatchCleanupTerminalDebt"
        ] | map(select($result[.] != null and ($result[.] | type) != "number")))
        + (if ($result.benchmarkSchemaVersion // 0) >= 4 then
            ([
              {name:"steadyDurableDebtComponents", value:$result.steadyDurableDebtComponents},
              {name:"finalDurableDebtComponents", value:$result.finalDurableDebtComponents}
            ] | map(select(.value != null and (.value | type) != "object") | .name))
          else [] end))
      | unique
    elif (.requiredFieldsInvalid | type) == "array" then .requiredFieldsInvalid
    else [] end;
  def required_v4_staircase_fields_missing:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-matched-staircase-chain" then
      . as $result
      | ([
          "validForCapacitySearch", "threeServiceTradeIdsEqual",
          "assetReconciliationPassed", "orderReadModelConverged",
          "finalQueueBacklog", "finalDlqBacklog", "activeMatchReservations",
          "finalOrderProjectionLagEvents", "finalDurableDebtObservationsHealthy",
          "finalDurableDebtComponents", "stages"
        ] | map(select($result[.] == null)))
      + (if ($result.stages | type) == "array" then
          [$result.stages | to_entries[]
            | if .value.durableDebtObservationsHealthy == null
              then "stages[\(.key)].durableDebtObservationsHealthy" else empty end,
              if .value.durableDebtComponents == null
              then "stages[\(.key)].durableDebtComponents" else empty end]
        else [] end)
    else [] end;
  def required_v4_staircase_fields_invalid:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-matched-staircase-chain" then
      . as $result
      | ((["validForCapacitySearch", "threeServiceTradeIdsEqual",
           "assetReconciliationPassed", "orderReadModelConverged",
           "finalDurableDebtObservationsHealthy"]
          | map(select($result[.] != null and ($result[.] | type) != "boolean")))
        + (["finalQueueBacklog", "finalDlqBacklog", "activeMatchReservations",
            "finalOrderProjectionLagEvents"]
          | map(select($result[.] != null and ($result[.] | type) != "number")))
        + (["finalDurableDebtComponents"]
          | map(select($result[.] != null and ($result[.] | type) != "object")))
        + (if $result.stages != null and ($result.stages | type) != "array"
            then ["stages"] else [] end)
        + (if ($result.stages | type) == "array" then
            [$result.stages | to_entries[]
              | if .value.durableDebtObservationsHealthy != null
                  and (.value.durableDebtObservationsHealthy | type) != "boolean"
                then "stages[\(.key)].durableDebtObservationsHealthy" else empty end,
                if .value.durableDebtComponents != null
                  and (.value.durableDebtComponents | type) != "object"
                then "stages[\(.key)].durableDebtComponents" else empty end]
          else [] end)) | unique
    else [] end;
  def required_v4_sequential_fields_missing:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-matched-trade-completion-chain" then
      . as $result
      | [
          "validForCapacityComparison", "threeServiceTradeIdsEqual",
          "assetReconciliationPassed", "finalQueueBacklog", "finalDlqBacklog",
          "activeMatchReservations", "matchTradeRows", "orderTradeRows",
          "walletTradeRows", "finalDurableDebtObservationsHealthy",
          "finalDurableDebtComponents"
        ] | map(select($result[.] == null))
    else [] end;
  def required_v4_sequential_fields_invalid:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-matched-trade-completion-chain" then
      . as $result
      | ((["validForCapacityComparison", "threeServiceTradeIdsEqual",
           "assetReconciliationPassed", "finalDurableDebtObservationsHealthy"]
          | map(select($result[.] != null and ($result[.] | type) != "boolean")))
        + (["finalQueueBacklog", "finalDlqBacklog", "activeMatchReservations",
            "matchTradeRows", "orderTradeRows", "walletTradeRows"]
          | map(select($result[.] != null and ($result[.] | type) != "number")))
        + (["finalDurableDebtComponents"]
          | map(select($result[.] != null and ($result[.] | type) != "object")))) | unique
    else [] end;
  def non_negative_integer:
    type == "number" and . >= 0 and . == floor;
  def valid_debt:
    type == "object"
    and (.totalCount | non_negative_integer)
    and (.retryCount | non_negative_integer)
    and (.terminalCount | non_negative_integer)
    and (.oldestUnresolvedAgeSeconds | non_negative_integer)
    and .retryCount <= .totalCount
    and .terminalCount <= .totalCount
    and (.totalCount > 0 or .oldestUnresolvedAgeSeconds == 0);
  def exact_work($names):
    type == "object"
    and (keys | sort) == ($names | sort)
    and all(.[]; valid_debt);
  def valid_cancellation_components:
    type == "object"
    and (keys | sort) == (["eap-order", "eap-wallet", "eap-matchEngine"] | sort)
    and (.["eap-order"] | exact_work([
      "asset_reservation_result_inbox", "trade_execution_inbox",
      "cancellation_result_inbox", "asset_reservation_released_inbox",
      "event_outbox", "orders_current_projection"
    ]))
    and (.["eap-wallet"] | exact_work([
      "order_submission_inbox", "cancellation_result_inbox",
      "trade_execution_inbox", "event_outbox"
    ]))
    and (.["eap-matchEngine"] | exact_work([
      "order_admission_inbox", "trade_outbox", "reservation_cleanup",
      "order_cancellation", "reservation_reconciliation"
    ]))
    and all(.[][]; .totalCount == 0);
  def required_v4_cancellation_fields_missing:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-cancellation-lifecycle" then
      . as $result
      | [
          "valid", "threeServiceTradeIdsEqual", "assetReconciliationPassed",
          "orderReadModelConverged", "raceMutualExclusionValid",
          "finalQueueBacklog", "finalDlqBacklog", "queueMetricsReadFailures",
          "activeMatchReservations", "finalDurableDebtObservationsHealthy",
          "finalDurableDebtComponents"
        ] | map(select($result[.] == null))
    else [] end;
  def required_v4_cancellation_fields_invalid:
    if (.benchmarkSchemaVersion // 0) >= 4
        and .benchmarkContract == "http-cancellation-lifecycle" then
      . as $result
      | (([
          "valid", "threeServiceTradeIdsEqual", "assetReconciliationPassed",
          "orderReadModelConverged", "raceMutualExclusionValid",
          "finalDurableDebtObservationsHealthy"
        ] | map(select($result[.] != null and ($result[.] | type) != "boolean")))
        + ([
          "finalQueueBacklog", "finalDlqBacklog", "queueMetricsReadFailures",
          "activeMatchReservations"
        ] | map(select($result[.] != null and (($result[.] | non_negative_integer) | not))))
        + ([
          "finalQueueBacklog", "finalDlqBacklog", "queueMetricsReadFailures",
          "activeMatchReservations"
        ] | map(select(($result[.] | type) == "number" and $result[.] != 0)))
        + (if $result.finalDurableDebtComponents != null
              and (($result.finalDurableDebtComponents | valid_cancellation_components) | not)
            then ["finalDurableDebtComponents"] else [] end)) | unique
    else [] end;
  def required_fields_missing:
    required_v3_fields_missing + required_v4_staircase_fields_missing
      + required_v4_sequential_fields_missing
      + required_v4_cancellation_fields_missing;
  def required_fields_invalid:
    required_v3_fields_invalid + required_v4_staircase_fields_invalid
      + required_v4_sequential_fields_invalid
      + required_v4_cancellation_fields_invalid;
  def known_failure:
    ((required_fields_missing + required_fields_invalid) | length) > 0
    or ((.externalDriverExitStatus // 0) != 0)
    or any([
      .validForSustainedCapacity,
      .validForCapacitySearch,
      .validForCapacityComparison,
      .valid,
      .threeServiceTradeIdsEqual,
      .completedTradeIdSetsEqual,
      .tradeIdsEqual,
      .assetReconciliationPassed,
      .orderReadModelConverged
      ,.steadyDurableDebtObservationsHealthy
      ,.finalDurableDebtObservationsHealthy
    ][]; . == false);
  def decision:
    if known_failure then "REJECT — a measured gate failed"
    elif .capacityClaimAllowed == true then "PASS — capacity evidence eligible"
    elif .validForSustainedCapacity == true
      then "PASS — workload correctness only; capacity evidence ineligible"
    elif .validForCapacitySearch == true
      then "PASS — staircase search gates passed; capacity evidence ineligible"
    elif .validForCapacityComparison == true
      then "PASS — full-chain comparison gates passed; capacity evidence ineligible"
    elif .valid == true then "PASS — correctness evidence"
    elif .correctness == "PASS" or .correctnessGate == "PASS"
      then "PASS — isolated diagnostic"
    elif (.validity.validRuns // 0) > 0 and (.validity.invalidRuns // 0) == 0
      then "PASS — repeat diagnostic"
    else "REVIEW — no common final gate was found"
    end;
  def invalid_reasons:
    ((pick([.capacityEvidenceInvalidReasons, .capacityInvalidReasons,
      .provenanceInvalidReasons,
      (if (.capacityEvidence | type) == "object"
        then .capacityEvidence.invalidReasons else null end)]) // [])
      + (required_fields_missing | map("missing_required_field:" + .))
      + (required_fields_invalid | map("invalid_required_field:" + .))
      + [if (.externalDriverExitStatus // 0) != 0
          then "external_driver_failed" else empty end]) | unique;
  def limitation:
    pick([.claimBoundary, .measurementBoundary, .evidenceClass,
      (if (.capacityEvidence | type) == "object"
        then .capacityEvidence.classification else null end),
      .benchmarkArtifactType]);

  (pick([.runId, .marketId, .config.runPrefix, .experiment]) // "unnamed-run") as $runId
  | (pick([.benchmarkContract, .experiment, .measurementBoundary, .evidenceClass]) // "unspecified") as $contract
  | invalid_reasons as $invalidReasons
  | "# Load-Test Report: \($runId)\n\n"
    + "> Generated from `\($source)` at \($generatedAt). This Markdown is a reading aid; the JSON remains the machine-readable evidence.\n\n"
    + "## Decision\n\n"
    + "- Result: **\(decision)**\n"
    + "- Contract: `\($contract)`\n"
    + (if limitation == null then "" else "- Boundary: \(limitation | show)\n" end)
    + "- Capacity claim allowed: \((.capacityClaimAllowed // false) | show)\n\n"
    + "## Workload and Throughput\n\n"
    + "| Metric | Value |\n| --- | ---: |\n"
    + row("Target total order TPS"; pick([.targetTotalOrderTps, .targetOrderTps, .targetTps, .config.targetTps]))
    + row("Target trade/event TPS"; pick([.targetTradeEventsPerSecond, .targetTradeTps]))
    + row("Warm-up seconds"; pick([.warmupSeconds, .config.warmupSeconds]))
    + row("Measurement seconds"; pick([.measurementSeconds, .durationSeconds, .config.durationSeconds]))
    + row("Expected HTTP orders"; pick([.expectedHttpOrders, .offeredHttpOrders]))
    + row("Scheduled HTTP orders"; pick([.externalScheduledRequests, .scheduledHttpOrders]))
    + row("Accepted HTTP orders"; pick([.acceptedHttpOrders, .httpAccepted]))
    + row("Accepted HTTP orders/s"; pick([.steadyAcceptedOrderTps, .httpAcceptedTps]))
    + row("Completed trades/s"; pick([.steadyCompletedTradeTps, .businessCompletedTradeTps,
      .fullConvergenceTradeTps, .persistedTradesPerSecond,
      .durableFanoutTradesPerSecond, .fullGateTradesPerSecond]))
    + row("Processed orders/s"; .processedOrdersPerSecond)
    + row("Persisted orders/s"; .persistedOrdersPerSecond)
    + row("Reservation cleanup tasks/s"; .cleanupTasksPerSecond)
    + row("Offered/published events/s"; pick([.offeredOrdersPerSecond,
      .publisherConfirmedEventsPerSecond, .businessInputBrokerAckedOrderTps]))
    + row("Driver response throughput"; .externalResponseThroughput)
    + row("External driver exit status"; .externalDriverExitStatus)
    + row("HTTP success ratio"; pick([.externalHttpSuccessRatio, .httpSuccessRatio]))
    + row("Dropped iterations"; pick([.externalDroppedIterations, .droppedIterations]))
    + row("Out-of-range iterations"; .externalOutOfRangeIterations)
    + "\n## Latency and Backlog\n\n"
    + "| Metric | Value |\n| --- | ---: |\n"
    + row("Driver HTTP p95 ms"; pick([.externalHttpLatencyMs.p95, .k6LatencyMs.p95]))
    + row("Driver HTTP p99 ms"; pick([.externalHttpLatencyMs.p99, .k6LatencyMs.p99]))
    + row("Business monitor HTTP p95 upper bound ms";
      pick([.httpAcceptedP95Ms, .httpLatencyP95Ms, .httpLatencyP95UpperBoundMs]))
    + row("Business monitor HTTP p99 upper bound ms";
      pick([.httpAcceptedP99Ms, .httpLatencyP99Ms, .httpLatencyP99UpperBoundMs]))
    + row("Steady backlog start"; .steadyBacklogStart)
    + row("Steady backlog end"; .steadyBacklogEnd)
    + row("Maximum steady backlog"; pick([.steadyMaxBacklog, .steadyMaximumBacklog]))
    + row("Backlog slope/s"; pick([.steadyBacklogSlopePerSecond, .backlogGrowthPerSecond]))
    + row("Order reservation inbox backlog start"; .steadyOrderReservationInboxBacklogStart)
    + row("Order reservation inbox backlog end"; .steadyOrderReservationInboxBacklogEnd)
    + row("Order reservation inbox maximum backlog"; .steadyOrderReservationInboxBacklogMax)
    + row("Order reservation inbox backlog slope/s";
      .steadyOrderReservationInboxBacklogSlopePerSecond)
    + row("Order inbox backlog start"; .steadyOrderInboxBacklogStart)
    + row("Order inbox backlog end"; .steadyOrderInboxBacklogEnd)
    + row("Order inbox maximum backlog"; .steadyOrderInboxBacklogMax)
    + row("Order inbox backlog slope/s"; .steadyOrderInboxBacklogSlopePerSecond)
    + row("Order inbox maximum oldest age seconds"; .steadyOrderInboxOldestAgeMaxSeconds)
    + row("Order inbox maximum terminal debt"; .steadyOrderInboxTerminalDebtMax)
    + row("Wallet inbox backlog start"; .steadyWalletInboxBacklogStart)
    + row("Wallet inbox backlog end"; .steadyWalletInboxBacklogEnd)
    + row("Wallet inbox maximum backlog"; .steadyWalletInboxBacklogMax)
    + row("Wallet inbox backlog slope/s"; .steadyWalletInboxBacklogSlopePerSecond)
    + row("Wallet inbox maximum oldest age seconds"; .steadyWalletInboxOldestAgeMaxSeconds)
    + row("Wallet inbox maximum terminal debt"; .steadyWalletInboxTerminalDebtMax)
    + row("Match inbox backlog start"; .steadyMatchInboxBacklogStart)
    + row("Match inbox backlog end"; .steadyMatchInboxBacklogEnd)
    + row("Match inbox maximum backlog"; .steadyMatchInboxBacklogMax)
    + row("Match inbox backlog slope/s"; .steadyMatchInboxBacklogSlopePerSecond)
    + row("Match inbox maximum oldest age seconds"; .steadyMatchInboxOldestAgeMaxSeconds)
    + row("Match inbox maximum terminal debt"; .steadyMatchInboxTerminalDebtMax)
    + row("Configured maximum backlog"; .maxSteadyBacklog)
    + row("Configured maximum growth/s"; .maxBacklogGrowthPerSecond)
    + row("Configured maximum inbox oldest age seconds"; .maxInboxOldestAgeSeconds)
    + row("Final queue backlog"; .finalQueueBacklog)
    + row("Final DLQ backlog"; .finalDlqBacklog)
    + row("Active reservations"; pick([.activeMatchReservations, .activeReservations]))
    + row("Order projection lag events"; .finalOrderProjectionLagEvents)
    + row("Final Order inbox backlog"; .finalOrderInboxBacklog)
    + row("Final Order inbox terminal debt"; .finalOrderInboxTerminalDebt)
    + row("Final Wallet inbox backlog"; .finalWalletInboxBacklog)
    + row("Final Wallet inbox terminal debt"; .finalWalletInboxTerminalDebt)
    + row("Final Match inbox backlog"; .finalMatchInboxBacklog)
    + row("Final Match inbox terminal debt"; .finalMatchInboxTerminalDebt)
    + row("Final Order outbox active/terminal debt";
      (if .finalOrderOutboxActiveDebt == null and .finalOrderOutboxTerminalDebt == null
       then null else ((.finalOrderOutboxActiveDebt // 0 | tostring) + "/" +
       (.finalOrderOutboxTerminalDebt // 0 | tostring)) end))
    + row("Final Wallet outbox active/terminal debt";
      (if .finalWalletOutboxActiveDebt == null and .finalWalletOutboxTerminalDebt == null
       then null else ((.finalWalletOutboxActiveDebt // 0 | tostring) + "/" +
       (.finalWalletOutboxTerminalDebt // 0 | tostring)) end))
    + row("Final Match outbox active/terminal debt";
      (if .finalMatchOutboxActiveDebt == null and .finalMatchOutboxTerminalDebt == null
       then null else ((.finalMatchOutboxActiveDebt // 0 | tostring) + "/" +
       (.finalMatchOutboxTerminalDebt // 0 | tostring)) end))
    + row("Final Match cleanup active/terminal debt";
      (if .finalMatchCleanupActiveDebt == null and .finalMatchCleanupTerminalDebt == null
       then null else ((.finalMatchCleanupActiveDebt // 0 | tostring) + "/" +
       (.finalMatchCleanupTerminalDebt // 0 | tostring)) end))
    + row("Steady durable-debt observations healthy"; .steadyDurableDebtObservationsHealthy)
    + row("Steady durable-debt components"; .steadyDurableDebtComponents)
    + row("Final durable-debt observations healthy"; .finalDurableDebtObservationsHealthy)
    + row("Final durable-debt components"; .finalDurableDebtComponents)
    + "\n## Correctness\n\n"
    + "| Gate | Result |\n| --- | ---: |\n"
    + row("Overall validity"; .valid)
    + row("Workload correctness gate"; .validForSustainedCapacity)
    + row("Three-service trade IDs equal"; pick([.threeServiceTradeIdsEqual,
      .completedTradeIdSetsEqual, .tradeIdsEqual]))
    + row("Asset reconciliation"; .assetReconciliationPassed)
    + row("Order read model converged"; .orderReadModelConverged)
    + row("Order projection rows"; .finalOrderProjectionRows)
    + row("Reservation-succeeded projection rows";
      .finalOrderProjectionReservationSucceededRows)
    + row("User-visible matched order rows"; .finalUserVisibleMatchedOrderRows)
    + row("Correctness gate"; pick([.correctnessGate, .correctness]))
    + row("Order book BUY debt"; pick([.remainingBuyOrders, .remainingOrderbookBuyOrders]))
    + row("Order book SELL debt"; pick([.remainingSellOrders, .remainingOrderbookSellOrders]))
    + "\n## Evidence Limitations\n\n"
    + (if ($invalidReasons | length) == 0
      then "- No common invalid-reason field was emitted. Review the workload-specific JSON before making a claim.\n"
      else ($invalidReasons | map("- `" + tostring + "`") | join("\n")) + "\n"
      end)
    + "\n## Artifact Rule\n\n"
    + (if $source | contains("build/load-test-reports/")
      then "This file and its source JSON are disposable local artifacts. Promote only reviewed, minimal evidence to `docs/benchmarks/results/YYYY-MM-DD-topic/`; describe the decision in a dated benchmark report before updating the canonical performance report.\n"
      else "This report was rendered from an explicitly selected artifact. Keep the JSON as the machine-readable source and document any promoted claim in a dated benchmark report.\n"
      end)
  ' "${RESULT_JSON}" > "${OUTPUT_MARKDOWN}"

echo "${OUTPUT_MARKDOWN}"
