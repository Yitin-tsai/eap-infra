#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-${ROOT_DIR}/build/load-test-reports}"

usage() {
  cat >&2 <<'EOF'
usage: summarize-write-costs.sh [DIAG_DIR] [RESULT_JSON]

Summarizes matched-trade-completion-chain write and relay costs captured by collect-loadtest-diagnostics.sh.
If DIAG_DIR is omitted, the latest matched-e2e diagnostics directory is used.
EOF
}

latest_diag_dir() {
  find "${REPORT_DIR}" -maxdepth 1 -type d -name 'matched-e2e-two-phase-*-diagnostics' \
    -print0 \
    | xargs -0 ls -td 2>/dev/null \
    | head -1
}

DIAG_DIR="${1:-}"
if [[ "${DIAG_DIR}" == "-h" || "${DIAG_DIR}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ -z "${DIAG_DIR}" ]]; then
  DIAG_DIR="$(latest_diag_dir)"
fi
if [[ -z "${DIAG_DIR}" || ! -d "${DIAG_DIR}" ]]; then
  echo "[ERROR] diagnostics directory not found: ${DIAG_DIR:-<empty>}" >&2
  usage
  exit 2
fi

RESULT_JSON="${2:-}"
if [[ -z "${RESULT_JSON}" ]]; then
  base="$(basename "${DIAG_DIR}")"
  market="${base#matched-e2e-two-phase-}"
  market="${market%-diagnostics}"
  candidate="${REPORT_DIR}/matched-e2e-two-phase-${market}-result.json"
  if [[ -f "${candidate}" ]]; then
    RESULT_JSON="${candidate}"
  fi
fi

OUT_FILE="${DIAG_DIR}/write-cost-summary.md"

json_value() {
  local key="$1"
  if [[ -n "${RESULT_JSON}" && -f "${RESULT_JSON}" ]] && command -v jq >/dev/null 2>&1; then
    jq -r ".${key} // empty" "${RESULT_JSON}"
  fi
}

emit_result_summary() {
  local market completed orderbook_tps business_completed_tps blended_tps blended_orders blended_seconds legacy_business_tps completion_seconds trade_tps order_tps wallet_tps marker_tps queue_drain last_queue last_queue_seconds external_steady_accepted external_steady_completed external_full_convergence
  market="$(json_value marketId)"
  completed="$(json_value completedTrades)"
  orderbook_tps="$(json_value businessOrderbookAdmissionTps)"
  if [[ -z "${orderbook_tps}" ]]; then
    orderbook_tps="$(json_value orderbookAdmissionTps)"
  fi
  business_completed_tps="$(json_value businessCompletedTradeTps)"
  blended_tps="$(json_value businessMarketFlowTps)"
  if [[ -z "${blended_tps}" ]]; then
    blended_tps="$(json_value blendedMarketFlowTps)"
  fi
  blended_orders="$(json_value businessMarketFlowOrders)"
  if [[ -z "${blended_orders}" ]]; then
    blended_orders="$(json_value blendedMarketFlowOrders)"
  fi
  blended_seconds="$(json_value businessMarketFlowSeconds)"
  if [[ -z "${blended_seconds}" ]]; then
    blended_seconds="$(json_value blendedMarketFlowSeconds)"
  fi
  legacy_business_tps="$(json_value businessMatchedE2eTps)"
  completion_seconds="$(json_value businessCompletionSeconds)"
  trade_tps="$(json_value matchEngineTradeExecutionReachTps)"
  if [[ -z "${trade_tps}" ]]; then
    trade_tps="$(json_value tradeExecutionReachTps)"
  fi
  order_tps="$(json_value orderTradeApplicationReachTps)"
  if [[ -z "${order_tps}" ]]; then
    order_tps="$(json_value orderCommandMatchReachTps)"
  fi
  wallet_tps="$(json_value walletTradeSettlementReachTps)"
  if [[ -z "${wallet_tps}" ]]; then
    wallet_tps="$(json_value walletSettlementReachTps)"
  fi
  marker_tps="$(json_value businessConvergenceReachTps)"
  if [[ -z "${marker_tps}" || "${marker_tps}" == "null" ]]; then
    marker_tps="$(json_value completionMarkerReachTps)"
  fi
  queue_drain="$(json_value queueFullyDrainedSeconds)"
  last_queue="$(json_value lastNonZeroQueue)"
  last_queue_seconds="$(json_value lastNonZeroQueueSeconds)"
  external_steady_accepted="$(json_value steadyAcceptedOrderTps)"
  external_steady_completed="$(json_value steadyCompletedTradeTps)"
  external_full_convergence="$(json_value fullConvergenceTradeTps)"
  if [[ -z "${completed}" ]]; then
    completed="$(json_value finalMatchTradeRows)"
  fi
  if [[ -z "${completion_seconds}" ]]; then
    completion_seconds="$(json_value fullConvergenceSeconds)"
  fi

  if [[ -z "${market}${completed}${legacy_business_tps}${business_completed_tps}" ]]; then
    echo "_No result JSON found._"
    echo
    return
  fi

  cat <<EOF
| Metric | Value |
|---|---:|
| marketId | \`${market}\` |
| completedTrades | ${completed:-n/a} |
| businessOrderbookAdmissionTps | ${orderbook_tps:-n/a} |
| businessCompletedTradeTps | ${business_completed_tps:-${legacy_business_tps:-n/a}} |
| businessMarketFlowTps | ${blended_tps:-n/a} |
| businessMarketFlowOrders | ${blended_orders:-n/a} |
| businessMarketFlowSeconds | ${blended_seconds:-n/a} |
| businessCompletionSeconds | ${completion_seconds:-n/a} |
| matchEngineTradeExecutionReachTps | ${trade_tps:-n/a} |
| orderTradeApplicationReachTps | ${order_tps:-n/a} |
| walletTradeSettlementReachTps | ${wallet_tps:-n/a} |
| businessConvergenceReachTps | ${marker_tps:-n/a} |
| externalSteadyAcceptedOrderTps | ${external_steady_accepted:-n/a} |
| externalSteadyCompletedTradeTps | ${external_steady_completed:-n/a} |
| externalFullConvergenceTradeTps | ${external_full_convergence:-n/a} |
| queueFullyDrainedSeconds | ${queue_drain:-n/a} |
| lastNonZeroQueue | \`${last_queue:-n/a}\` |
| lastNonZeroQueueSeconds | ${last_queue_seconds:-n/a} |

EOF
}

emit_timer_ranking() {
  awk '
    function basename(path, parts) {
      n = split(path, parts, "/")
      return parts[n]
    }
    function service_name(path, name) {
      name = basename(path)
      sub(/-actuator-prometheus.txt$/, "", name)
      return name
    }
    function metric_name(line, tmp) {
      tmp = line
      sub(/\{.*/, "", tmp)
      sub(/[[:space:]].*/, "", tmp)
      return tmp
    }
    function label_text(line, tmp) {
      tmp = ""
      if (match(line, /\{[^}]*\}/)) {
        tmp = substr(line, RSTART + 1, RLENGTH - 2)
      }
      gsub(/application="[^"]*",?/, "", tmp)
      gsub(/,,+/, ",", tmp)
      gsub(/^,|,$/, "", tmp)
      return tmp
    }
    function metric_value(line, parts) {
      split(line, parts, " ")
      return parts[length(parts)] + 0
    }
    function should_keep(metric) {
      if (metric ~ /_bucket$/ || metric ~ /_max$/) return 0
      if (metric ~ /publish_duration_seconds_(sum|count)$/) return 0
      return metric ~ /(_duration_seconds_(sum|count)|hikaricp_connections_(acquire|usage)_seconds_(sum|count))$/
    }
    function printable_metric(metric) {
      sub(/_seconds_(sum|count)$/, "", metric)
      sub(/_duration$/, "", metric)
      return metric
    }
    FILENAME ~ /-actuator-prometheus.txt$/ {
      metric = metric_name($0)
      if (!should_keep(metric)) next
      labels = label_text($0)
      key_metric = metric
      sub(/_sum$/, "", key_metric)
      sub(/_count$/, "", key_metric)
      key = service_name(FILENAME) "|" key_metric "|" labels
      if (metric ~ /_sum$/) sums[key] = metric_value($0)
      if (metric ~ /_count$/) counts[key] = metric_value($0)
    }
    END {
      for (key in sums) {
        split(key, parts, "|")
        svc = parts[1]
        metric = printable_metric(parts[2])
        labels = parts[3]
        count = counts[key] + 0
        sum = sums[key] + 0
        mean = count > 0 ? (sum * 1000.0 / count) : 0
        printf "%.9f\t%s\t%s\t%s\t%d\t%.6f\t%.3f\n", sum, svc, metric, labels, count, sum, mean
      }
    }
  ' "${DIAG_DIR}"/*-actuator-prometheus.txt 2>/dev/null \
    | sort -nr \
    | awk -F '\t' '
      BEGIN {
        print "| Rank | Service | Timer | Labels | Count | Cumulative seconds | Mean ms |"
        print "|---:|---|---|---|---:|---:|---:|"
      }
      NR <= 25 {
        labels = $4 == "" ? "-" : "`" $4 "`"
        printf "| %d | %s | `%s` | %s | %s | %.3f | %.3f |\n", NR, $2, $3, labels, $5, $6, $7
      }
    '
}

emit_pg_ranking() {
  for service in match order wallet; do
    file="${DIAG_DIR}/${service}-pg-stat-statements-total-time.txt"
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    awk -v service="${service}" '
      /^[[:space:]]*[0-9]+[[:space:]]*\|/ {
        n = split($0, fields, "|")
        if (n < 9) next
        calls = fields[1]
        total = fields[2]
        mean = fields[3]
        rows = fields[4]
        query = fields[n]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", calls)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", total)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", mean)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rows)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", query)
        if (query == "") next
        printf "%09.3f\t%s\t%s\t%s\t%s\t%s\n", total + 0, service, calls, total, mean, substr(query, 1, 140)
      }
    ' "${file}"
  done \
    | sort -nr \
    | awk -F '\t' '
      BEGIN {
        print "| Rank | Service | Calls | Total exec ms | Mean exec ms | Query prefix |"
        print "|---:|---|---:|---:|---:|---|"
      }
      NR <= 20 {
        gsub(/\|/, "\\|", $6)
        printf "| %d | %s | %s | %.2f | %.4f | `%s` |\n", NR, $2, $3, $4, $5, $6
      }
    '
}

emit_pg_wal_ranking() {
  for service in match order wallet; do
    file="${DIAG_DIR}/${service}-pg-stat-statements-total-time.txt"
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    awk -v service="${service}" '
      /^[[:space:]]*[0-9]+[[:space:]]*\|/ {
        n = split($0, fields, "|")
        if (n < 12) next
        calls = fields[1]
        wal_records = fields[9]
        wal_fpi = fields[10]
        wal_bytes = fields[11]
        query = fields[n]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", calls)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", wal_records)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", wal_fpi)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", wal_bytes)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", query)
        if (query == "" || wal_bytes + 0 <= 0) next
        per_call = calls + 0 > 0 ? (wal_bytes + 0) / (calls + 0) : 0
        printf "%015.0f\t%s\t%s\t%.0f\t%.1f\t%s\t%s\t%s\n", wal_bytes + 0, service, calls, wal_bytes + 0, per_call, wal_records, wal_fpi, substr(query, 1, 120)
      }
    ' "${file}"
  done \
    | sort -nr \
    | awk -F '\t' '
      BEGIN {
        print "| Rank | Service | Calls | WAL bytes | WAL bytes/call | WAL records | WAL FPI | Query prefix |"
        print "|---:|---|---:|---:|---:|---:|---:|---|"
      }
      NR <= 20 {
        gsub(/\|/, "\\|", $8)
        printf "| %d | %s | %s | %.0f | %.1f | %s | %s | `%s` |\n", NR, $2, $3, $4, $5, $6, $7, $8
      }
    '
}

emit_match_outbox_breakdown() {
  local file="${DIAG_DIR}/match-actuator-prometheus.txt"
  if [[ ! -f "${file}" ]]; then
    echo "_No MatchEngine actuator metrics found._"
    return
  fi

  awk '
    function metric_value(line, parts) {
      split(line, parts, " ")
      return parts[length(parts)] + 0
    }
    function capture(metric, name) {
      if ($0 ~ "^" metric "_count") counts[name] = metric_value($0)
      if ($0 ~ "^" metric "_sum") sums[name] = metric_value($0)
      if ($0 ~ "^" metric "_max") maxes[name] = metric_value($0)
    }
    {
      capture("match_engine_trade_outbox_batch_size", "match_engine_trade_outbox_batch_size")
      capture("match_engine_trade_outbox_confirmed_batch_size", "match_engine_trade_outbox_confirmed_batch_size")
      capture("match_engine_trade_outbox_batch_duration_seconds", "match_engine_trade_outbox_batch_duration_seconds")
      capture("match_engine_trade_outbox_select_duration_seconds", "match_engine_trade_outbox_select_duration_seconds")
      capture("match_engine_trade_outbox_publish_stage_duration_seconds", "match_engine_trade_outbox_publish_stage_duration_seconds")
      capture("match_engine_trade_outbox_publish_enqueue_duration_seconds", "match_engine_trade_outbox_publish_enqueue_duration_seconds")
      capture("match_engine_trade_outbox_message_build_duration_seconds", "match_engine_trade_outbox_message_build_duration_seconds")
      capture("match_engine_trade_outbox_payload_rebuild_duration_seconds", "match_engine_trade_outbox_payload_rebuild_duration_seconds")
      capture("match_engine_trade_outbox_confirm_wall_duration_seconds", "match_engine_trade_outbox_confirm_wall_duration_seconds")
      capture("match_engine_trade_outbox_confirm_duration_seconds", "match_engine_trade_outbox_confirm_duration_seconds")
      capture("match_engine_trade_outbox_first_confirm_duration_seconds", "match_engine_trade_outbox_first_confirm_duration_seconds")
      capture("match_engine_trade_outbox_remaining_confirm_duration_seconds", "match_engine_trade_outbox_remaining_confirm_duration_seconds")
      capture("match_engine_trade_outbox_mark_sent_duration_seconds", "match_engine_trade_outbox_mark_sent_duration_seconds")
      capture("trade_outbox_batch_size", "match_engine_trade_outbox_batch_size")
      capture("trade_outbox_confirmed_batch_size", "match_engine_trade_outbox_confirmed_batch_size")
      capture("trade_outbox_batch_duration_seconds", "match_engine_trade_outbox_batch_duration_seconds")
      capture("trade_outbox_select_duration_seconds", "match_engine_trade_outbox_select_duration_seconds")
      capture("trade_outbox_publish_stage_duration_seconds", "match_engine_trade_outbox_publish_stage_duration_seconds")
      capture("trade_outbox_publish_enqueue_duration_seconds", "match_engine_trade_outbox_publish_enqueue_duration_seconds")
      capture("trade_outbox_message_build_duration_seconds", "match_engine_trade_outbox_message_build_duration_seconds")
      capture("trade_outbox_payload_rebuild_duration_seconds", "match_engine_trade_outbox_payload_rebuild_duration_seconds")
      capture("trade_outbox_confirm_wall_duration_seconds", "match_engine_trade_outbox_confirm_wall_duration_seconds")
      capture("trade_outbox_confirm_duration_seconds", "match_engine_trade_outbox_confirm_duration_seconds")
      capture("trade_outbox_first_confirm_duration_seconds", "match_engine_trade_outbox_first_confirm_duration_seconds")
      capture("trade_outbox_remaining_confirm_duration_seconds", "match_engine_trade_outbox_remaining_confirm_duration_seconds")
      capture("trade_outbox_mark_sent_duration_seconds", "match_engine_trade_outbox_mark_sent_duration_seconds")
    }
    END {
      order[1] = "match_engine_trade_outbox_batch_size"
      order[2] = "match_engine_trade_outbox_confirmed_batch_size"
      order[3] = "match_engine_trade_outbox_batch_duration_seconds"
      order[4] = "match_engine_trade_outbox_select_duration_seconds"
      order[5] = "match_engine_trade_outbox_publish_stage_duration_seconds"
      order[6] = "match_engine_trade_outbox_publish_enqueue_duration_seconds"
      order[7] = "match_engine_trade_outbox_message_build_duration_seconds"
      order[8] = "match_engine_trade_outbox_payload_rebuild_duration_seconds"
      order[9] = "match_engine_trade_outbox_confirm_wall_duration_seconds"
      order[10] = "match_engine_trade_outbox_confirm_duration_seconds"
      order[11] = "match_engine_trade_outbox_first_confirm_duration_seconds"
      order[12] = "match_engine_trade_outbox_remaining_confirm_duration_seconds"
      order[13] = "match_engine_trade_outbox_mark_sent_duration_seconds"

      print "| Metric | Count | Sum | Max | Mean |"
      print "|---|---:|---:|---:|---:|"
      for (i = 1; i <= 13; i++) {
        name = order[i]
        count = counts[name] + 0
        sum = sums[name] + 0
        max = maxes[name] + 0
        mean = count > 0 ? sum / count : 0
        printf "| `%s` | %d | %.6f | %.6f | %.6f |\n", name, count, sum, max, mean
      }
    }
  ' "${file}"
}

emit_hikari_snapshot() {
  awk '
    function basename(path, parts) {
      n = split(path, parts, "/")
      return parts[n]
    }
    function service_name(path, name) {
      name = basename(path)
      sub(/-actuator-prometheus.txt$/, "", name)
      return name
    }
    /^[a-zA-Z_:][a-zA-Z0-9_:]*\{/ {
      metric = $1
      value = $2
      labels = metric
      sub(/^[^{]*\{/, "", labels)
      sub(/\}.*/, "", labels)
      sub(/\{.*/, "", metric)
      if (metric ~ /^hikaricp_connections_(pending|active|max)$/) {
        printf "| %s | `%s` | `%s` | %s |\n", service_name(FILENAME), metric, labels, value
      }
    }
  ' "${DIAG_DIR}"/*-actuator-prometheus.txt 2>/dev/null \
    | sort
}

emit_integrated_stage_lag() {
  local lag_file="${DIAG_DIR}/integrated-stage-lag.md"
  if [[ ! -f "${lag_file}" ]]; then
    echo "_No integrated stage lag report found._"
    return
  fi
  awk 'NR > 1 { print }' "${lag_file}"
}

{
  echo "# Write Cost Summary"
  echo
  echo "- diagnostics: \`${DIAG_DIR}\`"
  if [[ -n "${RESULT_JSON}" && -f "${RESULT_JSON}" ]]; then
    echo "- result: \`${RESULT_JSON}\`"
  fi
  echo "- generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Business Result"
  echo
  emit_result_summary
  echo "## Application Timer Ranking"
  echo
  echo "Cumulative seconds are sums across all observed events, so they show work/cost contribution rather than wall-clock elapsed time."
  echo
  emit_timer_ranking
  echo
  echo "## PostgreSQL Executor Ranking"
  echo
  echo "This is PostgreSQL executor time from pg_stat_statements. Gaps versus application timers usually point to JDBC, transaction, commit, broker confirm, scheduling, or client-side waits."
  echo
  emit_pg_ranking
  echo
  echo "## PostgreSQL WAL Ranking"
  echo
  echo "WAL bytes attribute generated write volume to statements. They do not measure WAL flush latency or storage durability."
  echo
  emit_pg_wal_ranking
  echo
  echo "## Match Trade Outbox Relay Breakdown"
  echo
  echo "This isolates MatchEngine TradeExecuted relay costs. Batch-size rows are counts; duration rows are seconds."
  echo
  emit_match_outbox_breakdown
  echo
  echo "## Integrated Stage Lag"
  echo
  emit_integrated_stage_lag
  echo
  echo "## Hikari Snapshot"
  echo
  echo "| Service | Metric | Labels | Value |"
  echo "|---|---|---|---:|"
  emit_hikari_snapshot
  echo
  echo "## Reading Notes"
  echo
  echo "- Treat app timer ranking as the matched-trade-completion-chain bottleneck view."
  echo "- Treat pg_stat ranking as DB executor cost only; it does not include broker confirm, queue drain, or most client-side transaction gaps."
  echo "- \`*_publish_duration_seconds\` is intentionally excluded because current relay instrumentation can overcount batch lifetime; use enqueue, confirm, select, mark-sent, and batch timers instead."
} > "${OUT_FILE}"

echo "${OUT_FILE}"
