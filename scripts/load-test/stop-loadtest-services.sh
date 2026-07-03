#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"

is_safe_loadtest_process() {
  local pid="$1"
  local comm
  local args

  comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"

  if [[ -z "${comm}${args}" ]]; then
    return 1
  fi

  case "${comm} ${args}" in
    *com.docker*|*Docker*|*docker*|*colima*|*orb*|*OrbStack*)
      return 1
      ;;
  esac

  case "${args}" in
    *eap-wallet*|*eap-order*|*eap-matchEngine*|*gradlew*bootRun*|*GradleDaemon*|*org.gradle*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

for repo in eap-wallet eap-order eap-matchEngine; do
  pid_file="${LOG_DIR}/${repo}.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    if ps -p "$pid" >/dev/null 2>&1; then
      echo "[INFO] stopping ${repo} pid=${pid}"
      kill "$pid" || true
    fi
    rm -f "$pid_file"
  fi
done

for port in 8080 8081 8082; do
  pids="$(lsof -ti ":${port}" || true)"
  if [[ -n "$pids" ]]; then
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      if is_safe_loadtest_process "$pid"; then
        echo "[WARN] force stopping loadtest process on port ${port}: ${pid}"
        kill "$pid" || true
      else
        echo "[WARN] skip non-loadtest process on port ${port}: ${pid}"
      fi
    done <<< "$pids"
  fi
done
