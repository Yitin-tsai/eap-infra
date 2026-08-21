#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
REPORT_DIR="${REPORT_DIR:-${ROOT_DIR}/build/load-test-reports}"
MARKET_ID="${MARKET_ID:-GLOBAL_LOADTEST_DIAG}"
PHASE="${1:-snapshot}"
DIAG_DIR="${DIAG_DIR:-${REPORT_DIR}/matched-e2e-two-phase-${MARKET_ID}-diagnostics}"
DIAGNOSTICS_LEVEL="${DIAGNOSTICS_LEVEL:-deep}"
case "${DIAGNOSTICS_LEVEL}" in
  light)
    SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-10}"
    ;;
  deep)
    SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-1}"
    ;;
  *)
    SAMPLE_INTERVAL_SECONDS="${DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS:-5}"
    ;;
esac

mkdir -p "${DIAG_DIR}"

ORDER_DB_CONTAINER="${ORDER_DB_CONTAINER:-eap-order-postgres-loadtest}"
WALLET_DB_CONTAINER="${WALLET_DB_CONTAINER:-eap-wallet-postgres-loadtest}"
MATCH_DB_CONTAINER="${MATCH_DB_CONTAINER:-eap-match-postgres-loadtest}"
RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
REDIS_CONTAINER="${REDIS_CONTAINER:-eap-redis-loadtest}"
RABBIT_MANAGEMENT_URL="${RABBIT_MANAGEMENT_URL:-http://localhost:15672}"
RABBIT_MANAGEMENT_USER="${RABBIT_MANAGEMENT_USER:-admin}"
RABBIT_MANAGEMENT_PASSWORD="${RABBIT_MANAGEMENT_PASSWORD:-admin123}"

psql_exec() {
  local container="$1"
  local db="$2"
  local sql="$3"
  docker exec "${container}" psql -U admin -d "${db}" -v ON_ERROR_STOP=1 -P pager=off -c "${sql}"
}

psql_tsv_exec() {
  local container="$1"
  local db="$2"
  local sql="$3"
  docker exec "${container}" psql -U admin -d "${db}" -v ON_ERROR_STOP=1 -P pager=off -t -A -F $'\t' -c "${sql}"
}

safe_psql_tsv_stdout() {
  local label="$1"
  local container="$2"
  local db="$3"
  local sql="$4"
  echo "## ${label}"
  if ! psql_tsv_exec "${container}" "${db}" "${sql}"; then
    echo "[WARN] ${label} unavailable"
  fi
}

safe_psql_exec() {
  local label="$1"
  local container="$2"
  local db="$3"
  local sql="$4"
  local out_file="$5"
  {
    echo "### ${label}"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! psql_exec "${container}" "${db}" "${sql}"; then
      echo "[WARN] ${label} unavailable"
    fi
  } > "${out_file}" 2>&1
}

service_pid() {
  local repo="$1"
  local pid_file="${LOG_DIR}/${repo}.pid"
  if [[ -f "${pid_file}" ]]; then
    cat "${pid_file}"
  fi
}

reset_db_diagnostics() {
  local label="$1"
  local container="$2"
  local db="$3"
  local out_file="${DIAG_DIR}/${label}-reset.txt"
  {
    echo "### ${label} reset"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    psql_exec "${container}" "${db}" "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" || true
    psql_exec "${container}" "${db}" "SELECT pg_stat_reset();" || true
    psql_exec "${container}" "${db}" "SELECT pg_stat_statements_reset();" || true
    psql_exec "${container}" "${db}" "SELECT pg_stat_reset_shared('wal');" || true
    psql_exec "${container}" "${db}" "SHOW shared_preload_libraries;" || true
    psql_exec "${container}" "${db}" "SHOW synchronous_commit;" || true
    psql_exec "${container}" "${db}" "SHOW fsync;" || true
    psql_exec "${container}" "${db}" "SHOW track_wal_io_timing;" || true
  } > "${out_file}" 2>&1
}

reset_all() {
  reset_db_diagnostics order "${ORDER_DB_CONTAINER}" eap_order_db
  reset_db_diagnostics wallet "${WALLET_DB_CONTAINER}" eap_wallet_db
  reset_db_diagnostics match "${MATCH_DB_CONTAINER}" eap_match_db
}

snapshot_db() {
  local label="$1"
  local container="$2"
  local db="$3"
  local schema_filter="$4"

  safe_psql_exec "${label} pg_stat_user_tables" "${container}" "${db}" "
SELECT schemaname, relname, n_tup_ins, n_tup_upd, n_tup_del, idx_scan, seq_scan, seq_tup_read, n_dead_tup
FROM pg_stat_user_tables
WHERE ${schema_filter}
ORDER BY schemaname, relname;
" "${DIAG_DIR}/${label}-pg-stat-user-tables.txt"

  safe_psql_exec "${label} pg_stat_user_indexes" "${container}" "${db}" "
SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE ${schema_filter}
ORDER BY schemaname, relname, indexrelname;
" "${DIAG_DIR}/${label}-pg-stat-user-indexes.txt"

  safe_psql_exec "${label} pg_stat_statements top total time" "${container}" "${db}" "
SELECT calls,
       round(total_exec_time::numeric, 2) AS total_exec_ms,
       round(mean_exec_time::numeric, 4) AS mean_exec_ms,
       rows,
       shared_blks_hit,
       shared_blks_read,
       shared_blks_dirtied,
       shared_blks_written,
       wal_records,
       wal_fpi,
       wal_bytes,
       round(blk_read_time::numeric, 3) AS blk_read_ms,
       round(blk_write_time::numeric, 3) AS blk_write_ms,
       left(regexp_replace(query, '\s+', ' ', 'g'), 240) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 30;
" "${DIAG_DIR}/${label}-pg-stat-statements-total-time.txt"

  safe_psql_exec "${label} pg_stat_activity waits" "${container}" "${db}" "
SELECT wait_event_type, wait_event, state, count(*) AS sessions
FROM pg_stat_activity
GROUP BY wait_event_type, wait_event, state
ORDER BY sessions DESC, wait_event_type, wait_event, state;
" "${DIAG_DIR}/${label}-pg-stat-activity-waits.txt"
}

snapshot_all() {
  snapshot_db order "${ORDER_DB_CONTAINER}" eap_order_db "schemaname IN ('order_service', 'public')"
  snapshot_order_trade_executed_inbox
  snapshot_db wallet "${WALLET_DB_CONTAINER}" eap_wallet_db "schemaname IN ('wallet_service', 'public')"
  snapshot_db match "${MATCH_DB_CONTAINER}" eap_match_db "schemaname IN ('match_engine', 'public')"
}

snapshot_order_trade_executed_inbox() {
  safe_psql_exec "order trade-executed inbox status" "${ORDER_DB_CONTAINER}" eap_order_db "
SELECT status,
       count(*) AS rows,
       min(attempt_count) AS min_attempt,
       max(attempt_count) AS max_attempt,
       count(*) FILTER (WHERE applied_at IS NULL) AS unapplied,
       min(received_at) AS first_received_at,
       max(updated_at) AS last_updated_at
FROM order_service.order_trade_execution_inbox
GROUP BY status
ORDER BY status;
" "${DIAG_DIR}/order-trade-executed-inbox-status.txt"
}

sample_db_hot_window() {
  local label="$1"
  local container="$2"
  local db="$3"

  safe_psql_tsv_stdout "${label} pg_stat_activity waits" "${container}" "${db}" "
SELECT COALESCE(wait_event_type, 'none') AS wait_event_type,
       COALESCE(wait_event, 'none') AS wait_event,
       state,
       count(*) AS sessions,
       round(max(GREATEST(
           0,
           EXTRACT(EPOCH FROM clock_timestamp() - COALESCE(query_start, xact_start, backend_start))
       ))::numeric, 3)
           AS max_age_seconds,
       COALESCE(NULLIF(application_name, ''), 'unknown') AS application_name,
       left((array_agg(
           '[' || COALESCE(NULLIF(application_name, ''), 'unknown') || '] '
           || regexp_replace(COALESCE(query, ''), '\s+', ' ', 'g')
           ORDER BY COALESCE(query_start, xact_start, backend_start)
       ))[1], 160) AS sample_query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND backend_type = 'client backend'
GROUP BY COALESCE(wait_event_type, 'none'), COALESCE(wait_event, 'none'), state,
         COALESCE(NULLIF(application_name, ''), 'unknown')
ORDER BY sessions DESC, wait_event_type, wait_event, state;
"

  safe_psql_tsv_stdout "${label} pg_stat_database" "${container}" "${db}" "
SELECT numbackends,
       xact_commit,
       xact_rollback,
       blks_read,
       blks_hit,
       tup_inserted,
       tup_updated,
       tup_deleted,
       deadlocks,
       temp_files,
       temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
"

  safe_psql_tsv_stdout "${label} pg_stat_wal" "${container}" "${db}" "
SELECT wal_records,
       wal_fpi,
       wal_bytes,
       wal_buffers_full,
       wal_write,
       wal_sync,
       wal_write_time,
       wal_sync_time
FROM pg_stat_wal;
"

  safe_psql_tsv_stdout "${label} pg_stat_bgwriter" "${container}" "${db}" "
SELECT checkpoints_timed,
       checkpoints_req,
       checkpoint_write_time,
       checkpoint_sync_time,
       buffers_checkpoint,
       buffers_clean,
       maxwritten_clean,
       buffers_backend,
       buffers_backend_fsync,
       buffers_alloc
FROM pg_stat_bgwriter;
"
}

sample_all_dbs_hot_window() {
  echo "# postgres hot-window"
  sample_db_hot_window order "${ORDER_DB_CONTAINER}" eap_order_db
  sample_db_hot_window wallet "${WALLET_DB_CONTAINER}" eap_wallet_db
  sample_db_hot_window match "${MATCH_DB_CONTAINER}" eap_match_db
}

sample_actuator_hot_window() {
  echo "# actuator hot-window"
  local metric_pattern='^(hikaricp_connections_(active|idle|pending|max|min)|hikaricp_connections_(acquire|usage)_seconds_(count|sum|max)|process_cpu_usage|system_cpu_usage|jvm_gc_pause_seconds_(count|sum|max)).*'
  if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
    metric_pattern='^(hikaricp_connections_(active|idle|pending|max|min)|hikaricp_connections_(acquire|usage)_seconds_(count|sum|max)|jvm_threads_live_threads|jvm_gc_pause_seconds_(count|sum|max)|process_cpu_usage|system_cpu_usage|eap_order_submission_append_duration_seconds_(count|sum|max)|eap_order_trade_apply_duration_seconds_(count|sum|max)|eap_order_trade_batch_total|eap_order_trade_batch_.*_total|eap_order_outbox_.*|eap_order_asset_reservation_.*|eap_wallet_order_submitted_.*|eap_wallet_trade_settlement_.*|eap_wallet_outbox_.*|match_engine_.*|trade_outbox_.*).*'
  fi
  for spec in \
    "wallet http://localhost:8081/eap-wallet/actuator/prometheus" \
    "order http://localhost:8080/eap-order/actuator/prometheus" \
    "match http://localhost:8082/match-engine/actuator/prometheus http://localhost:8082/actuator/prometheus"; do
    name="${spec%% *}"
    urls="${spec#* }"
    echo "## ${name}"
    for url in ${urls}; do
      echo "# url=${url}"
      if curl -fsS "${url}" \
        | grep -E "${metric_pattern}" \
        | grep -v '_bucket{'; then
        break
      fi
    done
  done
}

rabbitmq_queue_lines_http() {
  local queues_json
  queues_json="$(curl -fsS -u "${RABBIT_MANAGEMENT_USER}:${RABBIT_MANAGEMENT_PASSWORD}" \
    "${RABBIT_MANAGEMENT_URL}/api/queues?disable_stats=true&enable_queue_totals=true&columns=name,messages,messages_ready,messages_unacknowledged,consumers")" || return 1

  jq -r '
    .[]
    | select(.name | test("^(order|wallet|matchEngine)\\.|^order\\.dlq$"))
    | [.name, .messages, .messages_ready, .messages_unacknowledged, .consumers]
    | @tsv
  ' <<< "${queues_json}"
}

rabbitmq_queue_lines_cli() {
  docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name messages messages_ready messages_unacknowledged consumers \
    | grep -E '^(order|wallet|matchEngine)\.|^order\.dlq$' || true
}

rabbitmq_queue_lines() {
  if ! rabbitmq_queue_lines_http; then
    echo "[WARN] RabbitMQ management HTTP API unavailable; falling back to rabbitmqctl" >&2
    rabbitmq_queue_lines_cli
  fi
}

rabbitmq_alarm_lines_http() {
  local nodes_json
  nodes_json="$(curl -fsS -u "${RABBIT_MANAGEMENT_USER}:${RABBIT_MANAGEMENT_PASSWORD}" \
    "${RABBIT_MANAGEMENT_URL}/api/nodes?columns=name,mem_alarm,disk_free_alarm,mem_used,mem_limit,disk_free,disk_free_limit")" || return 1

  jq -r '
    .[]
    | [
        .name,
        (.mem_alarm // false),
        (.disk_free_alarm // false),
        (.mem_used // 0),
        (.mem_limit // 0),
        (.disk_free // 0),
        (.disk_free_limit // 0)
      ]
    | @tsv
  ' <<< "${nodes_json}"
}

rabbitmq_connections_http() {
  local connections_json
  connections_json="$(curl -fsS -u "${RABBIT_MANAGEMENT_USER}:${RABBIT_MANAGEMENT_PASSWORD}" \
    "${RABBIT_MANAGEMENT_URL}/api/connections?columns=name,user,vhost,channels,send_pend,state,recv_oct_details,send_oct_details")" || return 1

  jq -r '
    .[]
    | [
        .name,
        .user,
        .vhost,
        (.channels // 0),
        (.send_pend // 0),
        (.state // ""),
        (.recv_oct_details.rate // 0),
        (.send_oct_details.rate // 0)
      ]
    | @tsv
  ' <<< "${connections_json}"
}

rabbitmq_channels_http() {
  local channels_json
  channels_json="$(curl -fsS -u "${RABBIT_MANAGEMENT_USER}:${RABBIT_MANAGEMENT_PASSWORD}" \
    "${RABBIT_MANAGEMENT_URL}/api/channels?columns=name,user,vhost,connection_details,number,consumer_count,messages_unacknowledged,prefetch_count,state")" || return 1

  jq -r '
    .[]
    | [
        .name,
        .user,
        .vhost,
        (.connection_details.name // ""),
        (.number // 0),
        (.consumer_count // 0),
        (.messages_unacknowledged // 0),
        (.prefetch_count // 0),
        (.state // "")
      ]
    | @tsv
  ' <<< "${channels_json}"
}

snapshot_rabbitmq() {
  {
    echo "### rabbitmq queues"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    rabbitmq_queue_lines
  } > "${DIAG_DIR}/rabbitmq-queues.txt" 2>&1

  {
    echo "### rabbitmq connections"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! rabbitmq_connections_http; then
      echo "[WARN] RabbitMQ management HTTP API connections unavailable"
    fi
  } > "${DIAG_DIR}/rabbitmq-connections.txt" 2>&1

  {
    echo "### rabbitmq channels"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! rabbitmq_channels_http; then
      echo "[WARN] RabbitMQ management HTTP API channels unavailable"
    fi
  } > "${DIAG_DIR}/rabbitmq-channels.txt" 2>&1

  {
    echo "### rabbitmq resource alarms"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! rabbitmq_alarm_lines_http; then
      echo "[WARN] RabbitMQ management HTTP API node alarms unavailable"
    fi
  } > "${DIAG_DIR}/rabbitmq-alarms.txt" 2>&1
}

snapshot_redis() {
  {
    echo "### redis config"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    docker exec "${REDIS_CONTAINER}" redis-cli --raw CONFIG GET maxmemory || true
    docker exec "${REDIS_CONTAINER}" redis-cli --raw CONFIG GET maxmemory-policy || true
    echo
    echo "### redis memory"
    docker exec "${REDIS_CONTAINER}" redis-cli INFO memory \
      | grep -E '^(used_memory:|used_memory_human:|used_memory_peak:|used_memory_peak_human:|maxmemory:|maxmemory_human:|maxmemory_policy:)' || true
    echo
    echo "### redis stats"
    docker exec "${REDIS_CONTAINER}" redis-cli INFO stats \
      | grep -E '^(evicted_keys:|expired_keys:|keyspace_hits:|keyspace_misses:|total_commands_processed:|instantaneous_ops_per_sec:)' || true
  } > "${DIAG_DIR}/redis-state.txt" 2>&1
}

snapshot_processes() {
  {
    echo "### service processes"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for repo in eap-wallet eap-order eap-matchEngine; do
      local_pid="$(service_pid "${repo}")"
      if [[ -n "${local_pid}" ]]; then
        ps -p "${local_pid}" -o pid,ppid,%cpu,%mem,rss,etime,command || true
      else
        echo "${repo}: pid missing"
      fi
    done
  } > "${DIAG_DIR}/service-processes.txt" 2>&1
}

percentile_column() {
  local file="$1"
  local column="$2"
  local percentile="$3"
  awk -F '\t' -v column="${column}" 'NR > 1 && $column != "" { print $column }' "${file}" \
    | sort -n \
    | awk -v percentile="${percentile}" '
      { values[++count] = $1 }
      END {
        if (count == 0) {
          printf "n/a"
          exit
        }
        idx = int((percentile / 100.0) * (count - 1)) + 1
        if (idx < 1) idx = 1
        if (idx > count) idx = count
        printf "%.3f", values[idx]
      }
    '
}

emit_lag_summary_row() {
  local file="$1"
  local label="$2"
  local column="$3"
  local count p50 p95 p99 max
  count="$(awk -F '\t' -v column="${column}" 'NR > 1 && $column != "" { count++ } END { print count + 0 }' "${file}")"
  p50="$(percentile_column "${file}" "${column}" 50)"
  p95="$(percentile_column "${file}" "${column}" 95)"
  p99="$(percentile_column "${file}" "${column}" 99)"
  max="$(awk -F '\t' -v column="${column}" '
    NR > 1 && $column != "" {
      if (!seen || $column > max) {
        max = $column
        seen = 1
      }
    }
    END {
      if (!seen) printf "n/a"
      else printf "%.3f", max
    }
  ' "${file}")"
  printf "| %s | %s | %s | %s | %s | %s |\n" "${label}" "${count}" "${p50}" "${p95}" "${p99}" "${max}"
}

snapshot_integrated_stage_lag() {
  local lag_dir="${DIAG_DIR}/integrated-stage-lag"
  local rows_file="${DIAG_DIR}/integrated-stage-lag.tsv"
  local summary_file="${DIAG_DIR}/integrated-stage-lag.md"
  mkdir -p "${lag_dir}"

  if ! psql_tsv_exec "${MATCH_DB_CONTAINER}" eap_match_db "
SELECT trade_id, EXTRACT(EPOCH FROM created_at) * 1000
FROM match_engine.trade_executions
WHERE market_id = '${MARKET_ID}';
" > "${lag_dir}/match-trade-created.tsv" 2> "${lag_dir}/match-trade-created.err"; then
    echo "[WARN] integrated stage lag unavailable: failed to read match trade_executions" > "${summary_file}"
    return
  fi

  if ! psql_tsv_exec "${ORDER_DB_CONTAINER}" eap_order_db "
SELECT trade_id,
       EXTRACT(EPOCH FROM inserted_at) * 1000
FROM order_service.order_trade_applications
WHERE trade_id LIKE '${MARKET_ID}-%';
" > "${lag_dir}/order-trade-applications.tsv" 2> "${lag_dir}/order-trade-applications.err"; then
    echo "[WARN] integrated stage lag unavailable: failed to read order trade applications" > "${summary_file}"
    return
  fi

  if ! psql_tsv_exec "${WALLET_DB_CONTAINER}" eap_wallet_db "
SELECT trade_id,
       EXTRACT(EPOCH FROM inserted_at) * 1000
FROM wallet_service.trade_settlements
WHERE trade_id LIKE '${MARKET_ID}-%';
" > "${lag_dir}/wallet-trade-settlement-times.tsv" 2> "${lag_dir}/wallet-trade-settlement-times.err"; then
    echo "[WARN] integrated stage lag unavailable: failed to read wallet trade settlements" > "${summary_file}"
    return
  fi

  awk -F '\t' -v OFS='\t' '
    FILENAME ~ /match-trade-created.tsv$/ {
      matchCreated[$1] = $2
      next
    }
    FILENAME ~ /order-trade-applications.tsv$/ {
      orderInserted[$1] = $2
      next
    }
    FILENAME ~ /wallet-trade-settlement-times.tsv$/ {
      walletSettlementInserted[$1] = $2
      next
    }
    END {
      print "trade_id",
            "match_created_ms",
            "order_application_inserted_ms",
            "wallet_settlement_inserted_ms",
            "match_to_order_application_ms",
            "match_to_wallet_settlement_inserted_ms",
            "durable_convergence_ms",
            "order_wallet_durable_skew_ms"
      for (tradeId in matchCreated) {
        if (!(tradeId in orderInserted) || !(tradeId in walletSettlementInserted)) {
          continue
        }
        maxDurable = orderInserted[tradeId] > walletSettlementInserted[tradeId] ? orderInserted[tradeId] : walletSettlementInserted[tradeId]
        convergence = maxDurable - matchCreated[tradeId]
        durableSkew = orderInserted[tradeId] > walletSettlementInserted[tradeId] \
          ? orderInserted[tradeId] - walletSettlementInserted[tradeId] \
          : walletSettlementInserted[tradeId] - orderInserted[tradeId]
        print tradeId,
              matchCreated[tradeId],
              orderInserted[tradeId],
              walletSettlementInserted[tradeId],
              orderInserted[tradeId] - matchCreated[tradeId],
              walletSettlementInserted[tradeId] - matchCreated[tradeId],
              convergence,
              durableSkew
      }
    }
  ' "${lag_dir}/match-trade-created.tsv" \
    "${lag_dir}/order-trade-applications.tsv" \
    "${lag_dir}/wallet-trade-settlement-times.tsv" > "${rows_file}"

  {
    echo "# Integrated Stage Lag"
    echo
    echo "- marketId: \`${MARKET_ID}\`"
    echo "- rows: \`${rows_file}\`"
    echo "- generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation."
    echo
    echo "Notes:"
    echo
    echo '- Match time uses `trade_executions.created_at`.'
    echo '- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.'
    echo '- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.'
    echo '- Business completion is measured directly from the three service-owned durable tables.'
    echo
    echo "| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |"
    echo "|---|---:|---:|---:|---:|---:|"
    emit_lag_summary_row "${rows_file}" "Match persisted -> Order trade application" 5
    emit_lag_summary_row "${rows_file}" "Match persisted -> Wallet settlement inserted" 6
    emit_lag_summary_row "${rows_file}" "Match persisted -> durable convergence" 7
    emit_lag_summary_row "${rows_file}" "Order/Wallet durable skew" 8
  } > "${summary_file}"
}

snapshot_actuator() {
  local name="$1"
  shift
  local out_file="${DIAG_DIR}/${name}-actuator-prometheus.txt"
  {
    echo "### ${name} actuator prometheus selected metrics"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for url in "$@"; do
      echo "# url=${url}"
      if curl -fsS "${url}" \
        | grep -E '^(hikaricp_connections|hikaricp_connections_(active|idle|pending|max|min)|jvm_threads_live_threads|jvm_gc_pause_seconds_(count|sum|max)|process_cpu_usage|system_cpu_usage|process_uptime_seconds|executor_|eap_order_submission_append_duration_seconds_(count|sum|max)|eap_order_trade_apply_duration_seconds_(count|sum|max)|eap_order_trade_batch_total|eap_order_trade_batch_.*_total|eap_order_outbox_.*|eap_order_asset_reservation_.*|eap_wallet_order_submitted_.*|eap_wallet_trade_settlement_.*|eap_wallet_outbox_.*|trade_outbox_.*|match_engine_.*).*'; then
        return 0
      fi
    done
    echo "[WARN] ${name} actuator prometheus unavailable"
  } > "${out_file}" 2>&1
}

snapshot_runtime() {
  snapshot_rabbitmq
  snapshot_redis
  snapshot_processes
  snapshot_actuator wallet "http://localhost:8081/eap-wallet/actuator/prometheus"
  snapshot_actuator order "http://localhost:8080/eap-order/actuator/prometheus"
  snapshot_actuator match "http://localhost:8082/match-engine/actuator/prometheus" "http://localhost:8082/actuator/prometheus"
}

snapshot_runtime_light() {
  snapshot_rabbitmq
  snapshot_redis
  snapshot_processes
  snapshot_actuator wallet "http://localhost:8081/eap-wallet/actuator/prometheus"
  snapshot_actuator order "http://localhost:8080/eap-order/actuator/prometheus"
  snapshot_actuator match "http://localhost:8082/match-engine/actuator/prometheus" "http://localhost:8082/actuator/prometheus"
}

sample_loop() {
  local stop_file="${DIAG_DIR}/sampler.stop"
  local out_file="${DIAG_DIR}/runtime-samples.log"
  rm -f "${stop_file}"
  {
    echo "### runtime sampler"
    echo "startedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "diagnosticsLevel=${DIAGNOSTICS_LEVEL}"
    echo "intervalSeconds=${SAMPLE_INTERVAL_SECONDS}"
  } > "${out_file}"
  while [[ ! -f "${stop_file}" ]]; do
    {
      echo
      echo "## sample $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "# rabbitmq"
      rabbitmq_queue_lines
      echo "# rabbitmq alarms"
      rabbitmq_alarm_lines_http || echo "[WARN] RabbitMQ management HTTP API node alarms unavailable"
      echo "# redis"
      docker exec "${REDIS_CONTAINER}" redis-cli INFO memory \
        | grep -E '^(used_memory:|used_memory_peak:|maxmemory:|maxmemory_policy:)' || true
      docker exec "${REDIS_CONTAINER}" redis-cli INFO stats \
        | grep -E '^(evicted_keys:|keyspace_hits:|keyspace_misses:|instantaneous_ops_per_sec:)' || true
      sample_all_dbs_hot_window
      sample_actuator_hot_window
      echo "# processes"
      for repo in eap-wallet eap-order eap-matchEngine; do
        local_pid="$(service_pid "${repo}")"
        if [[ -n "${local_pid}" ]]; then
          ps -p "${local_pid}" -o pid,%cpu,%mem,rss,etime,command || true
        else
          echo "${repo}: pid missing"
        fi
      done
    } >> "${out_file}" 2>&1
    sleep "${SAMPLE_INTERVAL_SECONDS}"
  done
  echo "stoppedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${out_file}"
}

case "${PHASE}" in
  reset)
    reset_all
    ;;
  before-run)
    snapshot_runtime
    ;;
  before-run-light)
    snapshot_runtime_light
    ;;
  after-run)
    snapshot_runtime
    snapshot_all
    snapshot_integrated_stage_lag
    ;;
  after-run-light)
    snapshot_runtime_light
    snapshot_order_trade_executed_inbox
    snapshot_integrated_stage_lag
    ;;
  stage-lag)
    snapshot_integrated_stage_lag
    ;;
  sample)
    sample_loop
    ;;
  stop-sample)
    touch "${DIAG_DIR}/sampler.stop"
    ;;
  *)
    echo "usage: $0 {reset|before-run|before-run-light|after-run|after-run-light|stage-lag|sample|stop-sample}" >&2
    exit 2
    ;;
esac
