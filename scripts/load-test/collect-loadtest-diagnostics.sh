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
RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq}"
RABBIT_MANAGEMENT_URL="${RABBIT_MANAGEMENT_URL:-http://localhost:15672}"
RABBIT_MANAGEMENT_USER="${RABBIT_MANAGEMENT_USER:-admin}"
RABBIT_MANAGEMENT_PASSWORD="${RABBIT_MANAGEMENT_PASSWORD:-admin123}"

psql_exec() {
  local container="$1"
  local db="$2"
  local sql="$3"
  docker exec "${container}" psql -U admin -d "${db}" -v ON_ERROR_STOP=1 -P pager=off -c "${sql}"
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
    psql_exec "${container}" "${db}" "SHOW shared_preload_libraries;" || true
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
  snapshot_db wallet "${WALLET_DB_CONTAINER}" eap_wallet_db "schemaname IN ('wallet_service', 'public')"
  snapshot_db match "${MATCH_DB_CONTAINER}" eap_match_db "schemaname IN ('match_engine', 'public')"
}

rabbitmq_queue_lines_http() {
  local queues_json
  queues_json="$(curl -fsS -u "${RABBIT_MANAGEMENT_USER}:${RABBIT_MANAGEMENT_PASSWORD}" \
    "${RABBIT_MANAGEMENT_URL}/api/queues?columns=name,messages,messages_ready,messages_unacknowledged,consumers")" || return 1

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

snapshot_rabbitmq() {
  {
    echo "### rabbitmq queues"
    echo "capturedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    rabbitmq_queue_lines
  } > "${DIAG_DIR}/rabbitmq-queues.txt" 2>&1
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
        | grep -E '^(hikaricp_connections|hikaricp_connections_(active|idle|pending|max|min)|jvm_threads_live_threads|jvm_gc_pause_seconds_(count|sum|max)|process_cpu_usage|system_cpu_usage|process_uptime_seconds|executor_|eap_order_trade_apply_duration_seconds_(count|sum|max)|eap_order_trade_batch_total|eap_order_trade_batch_.*_total).*'; then
        return 0
      fi
    done
    echo "[WARN] ${name} actuator prometheus unavailable"
  } > "${out_file}" 2>&1
}

snapshot_runtime() {
  snapshot_rabbitmq
  snapshot_processes
  snapshot_actuator wallet "http://localhost:8081/eap-wallet/actuator/prometheus"
  snapshot_actuator order "http://localhost:8080/eap-order/actuator/prometheus"
  snapshot_actuator match "http://localhost:8082/match-engine/actuator/prometheus" "http://localhost:8082/actuator/prometheus"
}

snapshot_runtime_light() {
  snapshot_rabbitmq
  snapshot_processes
  snapshot_actuator order "http://localhost:8080/eap-order/actuator/prometheus"
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
      echo "# processes"
      for repo in eap-wallet eap-order eap-matchEngine; do
        local_pid="$(service_pid "${repo}")"
        if [[ -n "${local_pid}" ]]; then
          ps -p "${local_pid}" -o pid,%cpu,%mem,rss,etime,command || true
        else
          echo "${repo}: pid missing"
        fi
      done
      if [[ "${DIAGNOSTICS_LEVEL}" == "deep" ]]; then
        echo "# actuator"
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
              | grep -E '^(hikaricp_connections_(active|idle|pending|max|min)|jvm_threads_live_threads|jvm_gc_pause_seconds_(count|sum|max)|process_cpu_usage|system_cpu_usage|eap_order_trade_apply_duration_seconds_(count|sum|max)|eap_order_trade_batch_total|eap_order_trade_batch_.*_total).*'; then
              break
            fi
          done
        done
      fi
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
    ;;
  after-run-light)
    snapshot_runtime_light
    ;;
  sample)
    sample_loop
    ;;
  stop-sample)
    touch "${DIAG_DIR}/sampler.stop"
    ;;
  *)
    echo "usage: $0 {reset|before-run|after-run|sample|stop-sample}" >&2
    exit 2
    ;;
esac
