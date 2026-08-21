#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-${ROOT_DIR}/build/load-test-reports}"

usage() {
  cat >&2 <<'EOF'
usage: summarize-runtime-hot-window.sh [DIAG_DIR]

Summarizes runtime sampler output captured by collect-loadtest-diagnostics.sh.
If DIAG_DIR is omitted, the latest diagnostics directory with runtime-samples.log is used.
EOF
}

latest_diag_dir() {
  find "${REPORT_DIR}" -maxdepth 2 -type f -name 'runtime-samples.log' \
    -print0 \
    | xargs -0 ls -t 2>/dev/null \
    | head -1 \
    | xargs dirname 2>/dev/null || true
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

SAMPLES_FILE="${DIAG_DIR}/runtime-samples.log"
OUT_FILE="${DIAG_DIR}/runtime-hot-window-summary.md"
if [[ ! -f "${SAMPLES_FILE}" ]]; then
  echo "[ERROR] runtime samples not found: ${SAMPLES_FILE}" >&2
  exit 2
fi

emit_sample_metadata() {
  awk '
    /^startedAt=/ { started = substr($0, 11) }
    /^stoppedAt=/ { stopped = substr($0, 11) }
    /^diagnosticsLevel=/ { level = substr($0, 18) }
    /^intervalSeconds=/ { interval = substr($0, 17) }
    /^## sample / { samples++ }
    END {
      if (level == "") level = "n/a"
      if (interval == "") interval = "n/a"
      if (started == "") started = "n/a"
      if (stopped == "") stopped = "n/a"
      printf "| diagnosticsLevel | `%s` |\n", level
      printf "| intervalSeconds | %s |\n", interval
      printf "| samples | %d |\n", samples
      printf "| startedAt | `%s` |\n", started
      printf "| stoppedAt | `%s` |\n", stopped
    }
  ' "${SAMPLES_FILE}"
}

emit_rabbitmq_summary() {
  awk -F '\t' '
    /^# rabbitmq$/ { section = "rabbitmq"; next }
    /^#/ && $0 !~ /^# rabbitmq$/ { section = ""; next }
    section == "rabbitmq" && NF >= 4 && $1 != "" {
      queue = $1
      messages = $2 + 0
      ready = $3 + 0
      unacked = $4 + 0
      backlog = ready + unacked
      if (messages > max_messages[queue]) max_messages[queue] = messages
      if (ready > max_ready[queue]) max_ready[queue] = ready
      if (unacked > max_unacked[queue]) max_unacked[queue] = unacked
      if (backlog > max_backlog[queue]) max_backlog[queue] = backlog
      seen[queue] = 1
    }
    END {
      for (queue in seen) {
        printf "%09d\t%s\t%d\t%d\t%d\t%d\n",
          max_backlog[queue], queue, max_messages[queue], max_ready[queue],
          max_unacked[queue], max_backlog[queue]
      }
    }
  ' "${SAMPLES_FILE}" \
    | sort -r \
    | awk -F '\t' '
      BEGIN {
        print "| Queue | Max messages | Max ready | Max unacked | Max backlog |"
        print "|---|---:|---:|---:|---:|"
      }
      NR <= 20 {
        printf "| `%s` | %d | %d | %d | %d |\n", $2, $3, $4, $5, $6
      }
    '
}

emit_rabbitmq_alarm_summary() {
  awk -F '\t' '
    /^# rabbitmq alarms$/ { section = "rabbitmq_alarms"; next }
    /^#/ && $0 !~ /^# rabbitmq alarms$/ { section = ""; next }
    section == "rabbitmq_alarms" && NF >= 7 && $1 != "" {
      node = $1
      samples[node]++
      if ($2 == "true") memory_alarms[node]++
      if ($3 == "true") disk_alarms[node]++
      if (($4 + 0) > max_memory[node]) max_memory[node] = $4 + 0
      if (($5 + 0) > memory_limit[node]) memory_limit[node] = $5 + 0
      if (min_disk[node] == "" || ($6 + 0) < min_disk[node]) min_disk[node] = $6 + 0
      if (($7 + 0) > disk_limit[node]) disk_limit[node] = $7 + 0
    }
    END {
      print "| Node | Samples | Memory alarm samples | Disk alarm samples | Max memory bytes | Memory limit bytes | Min disk free bytes | Disk limit bytes |"
      print "|---|---:|---:|---:|---:|---:|---:|---:|"
      for (node in samples) {
        printf "| `%s` | %d | %d | %d | %d | %d | %d | %d |\n",
          node, samples[node], memory_alarms[node], disk_alarms[node],
          max_memory[node], memory_limit[node], min_disk[node], disk_limit[node]
      }
    }
  ' "${SAMPLES_FILE}"
}

emit_redis_summary() {
  awk -F ':' '
    /^used_memory:/ {
      value = $2 + 0
      if (value > max_used_memory) max_used_memory = value
      seen = 1
    }
    /^used_memory_peak:/ {
      value = $2 + 0
      if (value > max_used_memory_peak) max_used_memory_peak = value
      seen = 1
    }
    /^instantaneous_ops_per_sec:/ {
      value = $2 + 0
      if (value > max_ops) max_ops = value
      seen = 1
    }
    /^evicted_keys:/ {
      value = $2 + 0
      if (value > max_evicted) max_evicted = value
      seen = 1
    }
    END {
      print "| Metric | Max observed |"
      print "|---|---:|"
      if (!seen) {
        print "| n/a | n/a |"
        exit
      }
      printf "| used_memory_bytes | %d |\n", max_used_memory
      printf "| used_memory_peak_bytes | %d |\n", max_used_memory_peak
      printf "| instantaneous_ops_per_sec | %d |\n", max_ops
      printf "| evicted_keys | %d |\n", max_evicted
    }
  ' "${SAMPLES_FILE}"
}

emit_postgres_database_delta() {
  {
    echo "| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |"
    echo "|---|---:|---:|---:|---:|---:|---:|"
    awk -F '\t' '
    /^## (order|wallet|match) pg_stat_database$/ {
      label = $0
      sub(/^## /, "", label)
      split(label, parts, " ")
      service = parts[1]
      section = "pgdb"
      next
    }
    /^## / {
      section = ""
      next
    }
    /^#/ {
      section = ""
      next
    }
    section == "pgdb" && NF >= 10 {
      numbackends = $1 + 0
      commit = $2 + 0
      rollback = $3 + 0
      inserted = $6 + 0
      updated = $7 + 0
      deleted = $8 + 0
      if (!(service in seen)) {
        min_commit[service] = commit
        min_rollback[service] = rollback
        min_inserted[service] = inserted
        min_updated[service] = updated
        min_deleted[service] = deleted
      }
      seen[service] = 1
      if (numbackends > max_backends[service]) max_backends[service] = numbackends
      if (commit < min_commit[service]) min_commit[service] = commit
      if (commit > max_commit[service]) max_commit[service] = commit
      if (rollback < min_rollback[service]) min_rollback[service] = rollback
      if (rollback > max_rollback[service]) max_rollback[service] = rollback
      if (inserted < min_inserted[service]) min_inserted[service] = inserted
      if (inserted > max_inserted[service]) max_inserted[service] = inserted
      if (updated < min_updated[service]) min_updated[service] = updated
      if (updated > max_updated[service]) max_updated[service] = updated
      if (deleted < min_deleted[service]) min_deleted[service] = deleted
      if (deleted > max_deleted[service]) max_deleted[service] = deleted
    }
    END {
      for (service in seen) {
        printf "| %s | %d | %d | %d | %d | %d | %d |\n",
          service,
          max_backends[service],
          max_commit[service] - min_commit[service],
          max_rollback[service] - min_rollback[service],
          max_inserted[service] - min_inserted[service],
          max_updated[service] - min_updated[service],
          max_deleted[service] - min_deleted[service]
      }
    }
    ' "${SAMPLES_FILE}" | sort
  }
}

emit_postgres_wal_delta() {
  {
    echo "| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |"
    echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|"
    awk -F '\t' '
    /^## (order|wallet|match) pg_stat_wal$/ {
      label = $0
      sub(/^## /, "", label)
      split(label, parts, " ")
      service = parts[1]
      section = "pgwal"
      next
    }
    /^## / { section = ""; next }
    /^#/ { section = ""; next }
    section == "pgwal" && NF >= 8 {
      records = $1 + 0
      fpi = $2 + 0
      bytes = $3 + 0
      buffers_full = $4 + 0
      writes = $5 + 0
      syncs = $6 + 0
      write_time = $7 + 0
      sync_time = $8 + 0
      if (!(service in seen)) {
        min_records[service] = records
        min_fpi[service] = fpi
        min_bytes[service] = bytes
        min_buffers_full[service] = buffers_full
        min_writes[service] = writes
        min_syncs[service] = syncs
        min_write_time[service] = write_time
        min_sync_time[service] = sync_time
      }
      seen[service] = 1
      max_records[service] = records
      max_fpi[service] = fpi
      max_bytes[service] = bytes
      max_buffers_full[service] = buffers_full
      max_writes[service] = writes
      max_syncs[service] = syncs
      max_write_time[service] = write_time
      max_sync_time[service] = sync_time
    }
    END {
      for (service in seen) {
        printf "| %s | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.3f | %.3f |\n",
          service,
          max_records[service] - min_records[service],
          max_fpi[service] - min_fpi[service],
          max_bytes[service] - min_bytes[service],
          max_buffers_full[service] - min_buffers_full[service],
          max_writes[service] - min_writes[service],
          max_syncs[service] - min_syncs[service],
          max_write_time[service] - min_write_time[service],
          max_sync_time[service] - min_sync_time[service]
      }
    }
    ' "${SAMPLES_FILE}" | sort
  }
}

emit_postgres_bgwriter_delta() {
  {
    echo "| Service | Timed checkpoints | Requested checkpoints | Checkpoint write ms | Checkpoint sync ms | Checkpoint buffers | Clean buffers | Maxwritten stops | Backend buffers | Backend fsyncs | Allocated buffers |"
    echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    awk -F '\t' '
    /^## (order|wallet|match) pg_stat_bgwriter$/ {
      label = $0
      sub(/^## /, "", label)
      split(label, parts, " ")
      service = parts[1]
      section = "pgbgwriter"
      next
    }
    /^## / { section = ""; next }
    /^#/ { section = ""; next }
    section == "pgbgwriter" && NF >= 10 {
      for (field = 1; field <= 10; field++) value[field] = $field + 0
      if (!(service in seen)) {
        for (field = 1; field <= 10; field++) min_value[service, field] = value[field]
      }
      seen[service] = 1
      for (field = 1; field <= 10; field++) max_value[service, field] = value[field]
    }
    END {
      for (service in seen) {
        printf "| %s", service
        for (field = 1; field <= 10; field++) {
          delta = max_value[service, field] - min_value[service, field]
          if (field == 3 || field == 4) printf " | %.3f", delta
          else printf " | %.0f", delta
        }
        print " |"
      }
    }
    ' "${SAMPLES_FILE}" | sort
  }
}

emit_postgres_wait_summary() {
  local mode="$1"
  awk -F '\t' -v mode="${mode}" '
    /^## (order|wallet|match) pg_stat_activity waits$/ {
      label = $0
      sub(/^## /, "", label)
      split(label, parts, " ")
      service = parts[1]
      section = "pgwait"
      next
    }
    /^## / {
      section = ""
      next
    }
    /^#/ {
      section = ""
      next
    }
    section == "pgwait" && NF >= 5 && $1 !~ /^\[WARN\]/ {
      wait_type = $1
      wait_event = $2
      state = $3
      sessions = $4 + 0
      max_age = $5 + 0
      application_name = NF >= 7 ? $6 : "legacy-aggregate"
      if (mode == "actionable" && state == "idle" && (wait_type == "Client" || wait_type == "none")) {
        next
      }
      key = service "|" application_name "|" wait_type "|" wait_event "|" state
      seen[key] = 1
      if (sessions > max_sessions[key]) max_sessions[key] = sessions
      if (max_age > max_age_seconds[key]) max_age_seconds[key] = max_age
    }
    END {
      for (key in seen) {
        split(key, parts, "|")
        printf "%09d\t%09.3f\t%s\t%s\t%s\t%s\t%s\n",
          max_sessions[key], max_age_seconds[key], parts[1], parts[2], parts[3], parts[4], parts[5]
      }
    }
  ' "${SAMPLES_FILE}" \
    | sort -r \
    | awk -F '\t' '
      BEGIN {
        print "| Service | Application / pool | Wait type | Wait event | State | Max sessions | Max age seconds |"
        print "|---|---|---|---|---|---:|---:|"
      }
      NR <= 20 {
        printf "| %s | `%s` | `%s` | `%s` | `%s` | %d | %.3f |\n", $3, $4, $5, $6, $7, $1 + 0, $2 + 0
      }
    '
}

emit_hikari_gauge_summary() {
  awk '
    /^# actuator hot-window$/ {
      section = "actuator"
      next
    }
    /^# / && $0 !~ /^# url=/ && $0 !~ /^# actuator hot-window$/ {
      section = ""
      next
    }
    section == "actuator" && /^## (wallet|order|match)$/ {
      service = $2
      next
    }
    section == "actuator" && /^hikaricp_connections_(active|idle|pending|max|min)/ {
      metric = $1
      value = $2 + 0
      labels = metric
      sub(/^[^{]*\{/, "", labels)
      sub(/\}.*/, "", labels)
      sub(/\{.*/, "", metric)
      key = service "|" metric "|" labels
      seen[key] = 1
      if (value > max_value[key]) max_value[key] = value
    }
    END {
      for (key in seen) {
        split(key, parts, "|")
        printf "%09.3f\t%s\t%s\t%s\n", max_value[key], parts[1], parts[2], parts[3]
      }
    }
  ' "${SAMPLES_FILE}" \
    | sort -r \
    | awk -F '\t' '
      BEGIN {
        print "| Service | Gauge | Labels | Max observed |"
        print "|---|---|---|---:|"
      }
      NR <= 30 {
        printf "| %s | `%s` | `%s` | %.3f |\n", $2, $3, $4, $1 + 0
      }
    '
}

emit_cpu_summary() {
  awk '
    /^# actuator hot-window$/ {
      section = "actuator"
      next
    }
    /^# / && $0 !~ /^# url=/ && $0 !~ /^# actuator hot-window$/ {
      section = ""
      next
    }
    section == "actuator" && /^## (wallet|order|match)$/ {
      service = $2
      next
    }
    section == "actuator" && /^(process_cpu_usage|system_cpu_usage)/ {
      metric = $1
      if ($2 ~ /^[Nn][Aa][Nn]$/) {
        next
      }
      value = $2 + 0
      sub(/\{.*/, "", metric)
      key = service "|" metric
      seen[key] = 1
      count[key]++
      sum[key] += value
      if (value > max_value[key]) max_value[key] = value
    }
    END {
      for (key in seen) {
        split(key, parts, "|")
        average = count[key] > 0 ? sum[key] / count[key] : 0
        printf "%09.6f\t%s\t%s\t%.6f\n", max_value[key], parts[1], parts[2], average
      }
    }
  ' "${SAMPLES_FILE}" \
    | sort -r \
    | awk -F '\t' '
      BEGIN {
        print "| Service | Gauge | Max observed | Average observed |"
        print "|---|---|---:|---:|"
      }
      NR <= 20 {
        printf "| %s | `%s` | %.6f | %.6f |\n", $2, $3, $1 + 0, $4 + 0
      }
    '
}

{
  echo "# Runtime Hot Window Summary"
  echo
  echo "- diagnostics: \`${DIAG_DIR}\`"
  echo "- samples: \`${SAMPLES_FILE}\`"
  echo "- generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Sampler Metadata"
  echo
  echo "| Field | Value |"
  echo "|---|---:|"
  emit_sample_metadata
  echo
  echo "## RabbitMQ Backlog Peaks"
  echo
  emit_rabbitmq_summary
  echo
  echo "## RabbitMQ Resource Alarms"
  echo
  emit_rabbitmq_alarm_summary
  echo
  echo "## PostgreSQL Activity Delta"
  echo
  echo "Deltas are derived from the first and last observed sampler values in this diagnostics window."
  echo
  emit_postgres_database_delta
  echo
  echo "## PostgreSQL WAL Delta"
  echo
  echo "Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here."
  echo
  emit_postgres_wal_delta
  echo
  echo "## PostgreSQL Background Writer Delta"
  echo
  echo "These cluster-level deltas distinguish checkpoint or backend write pressure from in-memory WAL and buffer contention."
  echo
  emit_postgres_bgwriter_delta
  echo
  echo "## PostgreSQL Actionable Wait Peaks"
  echo
  echo "Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot."
  echo
  emit_postgres_wait_summary actionable
  echo
  echo "## PostgreSQL All Wait Peaks"
  echo
  emit_postgres_wait_summary all
  echo
  echo "## Hikari Gauge Peaks"
  echo
  emit_hikari_gauge_summary
  echo
  echo "## JVM CPU Gauges"
  echo
  emit_cpu_summary
  echo
  echo "## Redis Peaks"
  echo
  emit_redis_summary
} > "${OUT_FILE}"

echo "${OUT_FILE}"
