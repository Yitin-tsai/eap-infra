#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/eap-schema-v4-contracts.XXXXXX")"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

render() {
  local input="$1"
  local output="$2"
  bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${input}" "${output}" >/dev/null
}

jq -n '{
  benchmarkSchemaVersion: 4,
  benchmarkContract: "http-matched-trade-completion-chain",
  runId: "sequential-contract-test",
  validForCapacityComparison: true,
  threeServiceTradeIdsEqual: true,
  assetReconciliationPassed: true,
  finalQueueBacklog: 0,
  finalDlqBacklog: 0,
  activeMatchReservations: 0,
  matchTradeRows: 1,
  orderTradeRows: 1,
  walletTradeRows: 1,
  finalDurableDebtObservationsHealthy: true,
  finalDurableDebtComponents: {}
}' > "${TEST_DIR}/sequential-valid.json"
render "${TEST_DIR}/sequential-valid.json" "${TEST_DIR}/sequential-valid.md"
grep -Fq 'PASS — full-chain comparison gates passed' "${TEST_DIR}/sequential-valid.md"

jq '.finalDurableDebtObservationsHealthy = "true"
    | del(.finalDurableDebtComponents)' \
  "${TEST_DIR}/sequential-valid.json" > "${TEST_DIR}/sequential-invalid.json"
render "${TEST_DIR}/sequential-invalid.json" "${TEST_DIR}/sequential-invalid.md"
grep -Fq 'REJECT — a measured gate failed' "${TEST_DIR}/sequential-invalid.md"
grep -Fq 'invalid_required_field:finalDurableDebtObservationsHealthy' \
  "${TEST_DIR}/sequential-invalid.md"
grep -Fq 'missing_required_field:finalDurableDebtComponents' \
  "${TEST_DIR}/sequential-invalid.md"

jq -n '{
  benchmarkSchemaVersion: 4,
  benchmarkContract: "http-matched-staircase-chain",
  runId: "staircase-contract-test",
  validForCapacitySearch: true,
  threeServiceTradeIdsEqual: true,
  assetReconciliationPassed: true,
  orderReadModelConverged: true,
  finalQueueBacklog: 0,
  finalDlqBacklog: 0,
  activeMatchReservations: 0,
  finalOrderProjectionLagEvents: 0,
  finalDurableDebtObservationsHealthy: true,
  finalDurableDebtComponents: {},
  stages: [{
    durableDebtObservationsHealthy: true,
    durableDebtComponents: {},
    passed: true
  }]
}' > "${TEST_DIR}/staircase-valid.json"
render "${TEST_DIR}/staircase-valid.json" "${TEST_DIR}/staircase-valid.md"
grep -Fq 'PASS — staircase search gates passed' "${TEST_DIR}/staircase-valid.md"

jq 'del(.stages[0].durableDebtComponents)' \
  "${TEST_DIR}/staircase-valid.json" > "${TEST_DIR}/staircase-invalid.json"
render "${TEST_DIR}/staircase-invalid.json" "${TEST_DIR}/staircase-invalid.md"
grep -Fq 'REJECT — a measured gate failed' "${TEST_DIR}/staircase-invalid.md"
grep -Fq 'missing_required_field:stages[0].durableDebtComponents' \
  "${TEST_DIR}/staircase-invalid.md"

jq -n '
  def debt: {
    totalCount: 0,
    retryCount: 0,
    terminalCount: 0,
    oldestUnresolvedAgeSeconds: 0
  };
  {
    benchmarkSchemaVersion: 4,
    benchmarkContract: "http-cancellation-lifecycle",
    runId: "cancellation-contract-test",
    valid: true,
    threeServiceTradeIdsEqual: true,
    assetReconciliationPassed: true,
    orderReadModelConverged: true,
    raceMutualExclusionValid: true,
    finalQueueBacklog: 0,
    finalDlqBacklog: 0,
    queueMetricsReadFailures: 0,
    activeMatchReservations: 0,
    finalDurableDebtObservationsHealthy: true,
    finalDurableDebtComponents: {
      "eap-order": {
        asset_reservation_result_inbox: debt,
        trade_execution_inbox: debt,
        cancellation_result_inbox: debt,
        asset_reservation_released_inbox: debt,
        event_outbox: debt,
        orders_current_projection: debt
      },
      "eap-wallet": {
        order_submission_inbox: debt,
        cancellation_result_inbox: debt,
        trade_execution_inbox: debt,
        event_outbox: debt
      },
      "eap-matchEngine": {
        order_admission_inbox: debt,
        trade_outbox: debt,
        reservation_cleanup: debt,
        order_cancellation: debt,
        reservation_reconciliation: debt
      }
    }
  }
' > "${TEST_DIR}/cancellation-valid.json"
http_matched_validate_cancellation_result_schema "${TEST_DIR}/cancellation-valid.json"
render "${TEST_DIR}/cancellation-valid.json" "${TEST_DIR}/cancellation-valid.md"
grep -Fq 'PASS — correctness evidence' "${TEST_DIR}/cancellation-valid.md"

jq '.finalDurableDebtObservationsHealthy = "true"
    | del(.finalDurableDebtComponents["eap-matchEngine"].reservation_cleanup)' \
  "${TEST_DIR}/cancellation-valid.json" > "${TEST_DIR}/cancellation-invalid.json"
if http_matched_validate_cancellation_result_schema \
    "${TEST_DIR}/cancellation-invalid.json" >/dev/null 2>&1; then
  echo "invalid cancellation artifact passed the schema-v4 validator" >&2
  exit 1
fi
render "${TEST_DIR}/cancellation-invalid.json" "${TEST_DIR}/cancellation-invalid.md"
grep -Fq 'REJECT — a measured gate failed' "${TEST_DIR}/cancellation-invalid.md"
grep -Fq 'invalid_required_field:finalDurableDebtObservationsHealthy' \
  "${TEST_DIR}/cancellation-invalid.md"
grep -Fq 'invalid_required_field:finalDurableDebtComponents' \
  "${TEST_DIR}/cancellation-invalid.md"

jq '.finalDurableDebtComponents["eap-matchEngine"].reservation_cleanup = {
      totalCount: 1,
      retryCount: 0,
      terminalCount: 1,
      oldestUnresolvedAgeSeconds: 1
    }' "${TEST_DIR}/cancellation-valid.json" > "${TEST_DIR}/cancellation-terminal.json"
render "${TEST_DIR}/cancellation-terminal.json" "${TEST_DIR}/cancellation-terminal.md"
grep -Fq 'REJECT — a measured gate failed' "${TEST_DIR}/cancellation-terminal.md"
grep -Fq 'invalid_required_field:finalDurableDebtComponents' \
  "${TEST_DIR}/cancellation-terminal.md"

echo "schema-v4 result contract tests passed"
