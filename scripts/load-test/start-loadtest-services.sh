#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"

mkdir -p "$LOG_DIR" "$GRADLE_USER_HOME_DIR"

start_service() {
  local repo="$1"
  local port="$2"
  local health_path="$3"
  local log_file="${LOG_DIR}/${repo}.log"
  local pid_file="${LOG_DIR}/${repo}.pid"
  local service_env=""

  if [[ "${repo}" == "eap-matchEngine" ]]; then
    service_env="EAP_MATCH_USER_OPEN_ORDER_INDEX_ENABLED='${EAP_MATCH_USER_OPEN_ORDER_INDEX_ENABLED:-true}'"
  fi
  if [[ "${repo}" == "eap-wallet" ]]; then
    service_env="EAP_WALLET_OUTBOX_ASYNC_RELAY_ENABLED='${EAP_WALLET_OUTBOX_ASYNC_RELAY_ENABLED:-false}' EAP_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES='${EAP_WALLET_OUTBOX_ASYNC_MAX_IN_FLIGHT_BATCHES:-4}' EAP_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS='${EAP_WALLET_OUTBOX_IN_FLIGHT_TIMEOUT_SECONDS:-30}'"
  fi

  if lsof -Pi ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "[WARN] port ${port} is already in use; stop the existing process before starting ${repo}" >&2
    return 1
  fi

  echo "[INFO] starting ${repo} on port ${port}; log=${log_file}"
  nohup bash -lc "cd '${ROOT_DIR}/${repo}' && ${service_env} GRADLE_USER_HOME='${GRADLE_USER_HOME_DIR}' ./gradlew --no-daemon bootRun --args='--spring.profiles.active=loadtest'" >"${log_file}" 2>&1 &
  echo "$!" >"${pid_file}"

  local health_url="http://localhost:${port}${health_path}"
  local deadline=$((SECONDS + ${LOADTEST_SERVICE_START_TIMEOUT_SECONDS:-120}))
  until curl -fsS "${health_url}" >/dev/null 2>&1; do
    if [[ $SECONDS -ge $deadline ]]; then
      echo "[ERROR] ${repo} did not become ready: ${health_url}" >&2
      tail -n 80 "${log_file}" >&2 || true
      return 1
    fi
    if ! kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
      echo "[ERROR] ${repo} exited before becoming ready: ${health_url}" >&2
      tail -n 80 "${log_file}" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "[INFO] ${repo} ready"
}

start_service eap-wallet 8081 /eap-wallet/actuator/health
start_service eap-order 8080 /eap-order/actuator/health
start_service eap-matchEngine 8082 /match-engine/actuator/health

echo "[INFO] loadtest services ready"
echo "[INFO] logs:"
echo "  tail -f ${LOG_DIR}/eap-wallet.log"
echo "  tail -f ${LOG_DIR}/eap-order.log"
echo "  tail -f ${LOG_DIR}/eap-matchEngine.log"
