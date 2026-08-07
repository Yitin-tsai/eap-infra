#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
SERVICE_LAUNCH_MODE="${LOADTEST_SERVICE_LAUNCH_MODE:-boot-run}"
SERVICE_JAVA_BIN="${LOADTEST_SERVICE_JAVA_BIN:-java}"
SERVICE_JAVA_VERSION="managed by Gradle toolchain"
SERVICE_JAVA_BIN_QUOTED=""

mkdir -p "$LOG_DIR" "$GRADLE_USER_HOME_DIR"

find_service_jar() {
  local repo="$1"

  find "${ROOT_DIR}/${repo}/build/libs" -maxdepth 1 -type f \
    -name "${repo}-*.jar" \
    ! -name "*-plain.jar" \
    ! -name "*-stubs.jar" \
    | sort \
    | head -n 1
}

case "${SERVICE_LAUNCH_MODE}" in
  boot-run)
    ;;
  jar)
    if [[ "${SERVICE_JAVA_BIN}" == */* ]]; then
      if [[ ! -x "${SERVICE_JAVA_BIN}" ]]; then
        echo "[ERROR] LOADTEST_SERVICE_JAVA_BIN is not executable: ${SERVICE_JAVA_BIN}" >&2
        exit 2
      fi
    elif ! command -v "${SERVICE_JAVA_BIN}" >/dev/null 2>&1; then
      echo "[ERROR] LOADTEST_SERVICE_JAVA_BIN was not found: ${SERVICE_JAVA_BIN}" >&2
      exit 2
    fi
    SERVICE_JAVA_VERSION="$("${SERVICE_JAVA_BIN}" -version 2>&1 | head -n 1)"
    printf -v SERVICE_JAVA_BIN_QUOTED '%q' "${SERVICE_JAVA_BIN}"
    for repo in eap-wallet eap-order eap-matchEngine; do
      echo "[INFO] preparing ${repo} executable jar"
      (
        cd "${ROOT_DIR}/${repo}"
        GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
      )
      if [[ -z "$(find_service_jar "${repo}")" ]]; then
        echo "[ERROR] executable jar was not produced for ${repo}" >&2
        exit 1
      fi
    done
    ;;
  *)
    echo "[ERROR] unsupported LOADTEST_SERVICE_LAUNCH_MODE=${SERVICE_LAUNCH_MODE}; expected boot-run or jar" >&2
    exit 2
    ;;
esac

start_service() {
  local repo="$1"
  local port="$2"
  local health_path="$3"
  local log_file="${LOG_DIR}/${repo}.log"
  local pid_file="${LOG_DIR}/${repo}.pid"
  local launch_command=""

  if lsof -Pi ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "[WARN] port ${port} is already in use; stop the existing process before starting ${repo}" >&2
    return 1
  fi

  case "${SERVICE_LAUNCH_MODE}" in
    boot-run)
      launch_command="GRADLE_USER_HOME='${GRADLE_USER_HOME_DIR}' ./gradlew --no-daemon bootRun --args='--spring.profiles.active=loadtest'"
      ;;
    jar)
      local boot_jar
      boot_jar="$(find_service_jar "${repo}")"
      launch_command="exec ${SERVICE_JAVA_BIN_QUOTED} -jar '${boot_jar}' --spring.profiles.active=loadtest"
      ;;
  esac

  echo "[INFO] starting ${repo} on port ${port}; launchMode=${SERVICE_LAUNCH_MODE}; log=${log_file}"
  nohup bash -lc "cd '${ROOT_DIR}/${repo}' && ${launch_command}" >"${log_file}" 2>&1 &
  echo "$!" >"${pid_file}"

  local health_url="http://localhost:${port}${health_path}"
  local deadline=$(( $(date +%s) + ${LOADTEST_SERVICE_START_TIMEOUT_SECONDS:-120} ))
  until curl -fsS "${health_url}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge $deadline ]]; then
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
echo "[INFO] service launch mode: ${SERVICE_LAUNCH_MODE}"
echo "[INFO] service Java: ${SERVICE_JAVA_VERSION}; binary=${SERVICE_JAVA_BIN}"
echo "[INFO] logs:"
echo "  tail -f ${LOG_DIR}/eap-wallet.log"
echo "  tail -f ${LOG_DIR}/eap-order.log"
echo "  tail -f ${LOG_DIR}/eap-matchEngine.log"
