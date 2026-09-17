#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
EVENTS="${EVENTS:-200}"
TARGET_TPS="${TARGET_TPS:-100}"
DB_OUTAGE_SECONDS="${DB_OUTAGE_SECONDS:-60}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
RUN_ID="${RUN_ID:-REL104_MATCH_DB_OUTAGE_$(date +%Y%m%d_%H%M%S)}"
MARKET_ID="${MARKET_ID:-${RUN_ID}}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JAR="${BUILD_JAR:-true}"
SERVICE_LOG="${LOG_DIR}/eap-matchEngine.log"
SERVICE_PID_FILE="${LOG_DIR}/eap-matchEngine.pid"
PUBLISH_LOG="${REPORT_DIR}/rel104-match-db-outage-${RUN_ID}-publisher.log"
RESULT_JSON="${REPORT_DIR}/rel104-match-db-outage-${RUN_ID}-result.json"
MATCH_WORK='["order_admission_inbox","trade_outbox","reservation_cleanup","order_cancellation","reservation_reconciliation"]'
PAUSE_VERIFIED_AT=0

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"
source "${ROOT_DIR}/scripts/load-test/durable-debt-snapshot-lib.sh"

if (( DB_OUTAGE_SECONDS < 60 )); then
  echo "[ERROR] REL-104 Match failure mode requires DB_OUTAGE_SECONDS >= 60" >&2
  exit 2
fi

cleanup() {
  docker start eap-match-postgres-loadtest >/dev/null 2>&1 || true
  if [[ -f "${SERVICE_PID_FILE}" ]]; then
    local pid
    pid="$(cat "${SERVICE_PID_FILE}")"
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${SERVICE_PID_FILE}"
  fi
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" stop \
      order-postgres match-postgres redis rabbitmq >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_healthy() {
  local container="$1"
  local deadline=$(( $(date +%s) + 90 ))
  until [[ "$(docker inspect --format '{{.State.Health.Status}}' "${container}" 2>/dev/null || true)" == "healthy" ]]; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] ${container} did not become healthy" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_http() {
  local url="$1"
  local deadline=$(( $(date +%s) + 120 ))
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "$(cat "${SERVICE_PID_FILE}")" >/dev/null 2>&1; then
      tail -n 120 "${SERVICE_LOG}" >&2 || true
      echo "[ERROR] MatchEngine did not become ready: ${url}" >&2
      exit 1
    fi
    sleep 1
  done
}

queue_total() {
  local queue="$1"
  docker exec eap-rabbitmq-loadtest rabbitmqctl list_queues name messages --quiet 2>/dev/null \
    | awk -v target="${queue}" '$1 == target {print $2; found=1} END {if (!found) print 0}'
}

queue_consumers() {
  local queue="$1"
  docker exec eap-rabbitmq-loadtest rabbitmqctl list_queues name consumers --quiet 2>/dev/null \
    | awk -v target="${queue}" '$1 == target {print $2; found=1} END {if (!found) print 0}'
}

circuit_metric() {
  local metric_name="$1"
  local statistic="$2"
  curl -fsS "http://localhost:8082/match-engine/actuator/metrics/${metric_name}" \
    | jq -er --arg statistic "${statistic}" '.measurements[] | select(.statistic == $statistic) | .value'
}

match_consumer_paused() {
  local messages consumers circuit_open
  messages="$(queue_total matchEngine.orderConfirmed.queue)"
  consumers="$(queue_consumers matchEngine.orderConfirmed.queue)"
  circuit_open="$(circuit_metric eap.rabbit.cda.db.circuit.open VALUE 2>/dev/null || echo -1)"
  (( messages > 0 && consumers == 0 )) && [[ "${circuit_open}" == "1.0" ]]
}

wait_for_match_consumer_paused() {
  local deadline=$(( $(date +%s) + 45 ))
  until match_consumer_paused; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] Match admission consumer did not pause with source backlog before timeout" >&2
      return 1
    fi
    sleep 1
  done
  PAUSE_VERIFIED_AT="$(date +%s)"
}

circuit_opened_and_closed() {
  local open_value opened_value
  open_value="$(circuit_metric eap.rabbit.cda.db.circuit.open VALUE 2>/dev/null || echo -1)"
  opened_value="$(circuit_metric eap.rabbit.cda.db.circuit.opened COUNT 2>/dev/null || echo 0)"
  [[ "${open_value}" == "0.0" ]] && awk -v value="${opened_value}" 'BEGIN {exit !(value >= 1)}'
}

wait_for_recovery() {
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  while true; do
    local rows terminal queue dlq
    rows="$(docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -Atqc \
      "SELECT count(*) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}'")"
    terminal="$(docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -Atqc \
      "SELECT count(*) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}' AND status = 'FAILED_PERMANENT'")"
    queue="$(queue_total matchEngine.orderConfirmed.queue)"
    dlq="$(queue_total order.dlq)"
    if [[ "${rows}" == "${EVENTS}" && "${terminal}" == "0" && "${queue}" == "0" && "${dlq}" == "0" ]] \
        && circuit_opened_and_closed; then
      return 0
    fi
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] MatchEngine recovery did not converge: rows=${rows}, terminal=${terminal}, queue=${queue}, dlq=${dlq}" >&2
      tail -n 160 "${SERVICE_LOG}" >&2 || true
      return 1
    fi
    sleep 2
  done
}

bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
docker compose -p eap-loadtest -f "${COMPOSE_FILE}" up -d rabbitmq redis order-postgres match-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-redis-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-match-postgres-loadtest

RABBIT_CONTAINER=eap-rabbitmq-loadtest bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh" >/dev/null

if [[ "${BUILD_JAR}" == "true" ]]; then
  (
    cd "${ROOT_DIR}/eap-matchEngine"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
  )
fi

MATCH_JAR="$(find "${ROOT_DIR}/eap-matchEngine/build/libs" -maxdepth 1 -type f \
  -name 'eap-matchEngine-*.jar' ! -name '*-plain.jar' | sort | head -n 1)"
if [[ -z "${MATCH_JAR}" ]]; then
  echo "[ERROR] MatchEngine executable jar is missing" >&2
  exit 1
fi

java -jar "${MATCH_JAR}" --spring.profiles.active=loadtest >"${SERVICE_LOG}" 2>&1 &
echo "$!" >"${SERVICE_PID_FILE}"
CONTROL_URL="http://localhost:8082/match-engine/actuator/orderBookRuntime"
wait_for_http "${CONTROL_URL}"
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"action":"INITIALIZE_EMPTY","operator":"rel104-failure-injection","reason":"isolated Match DB outage recovery test"}' \
  "${CONTROL_URL}" >/dev/null
wait_for_http "http://localhost:8082/match-engine/actuator/health"

DLQ_BEFORE="$(queue_total order.dlq)"
OUTAGE_STARTED_AT="$(date +%s)"
echo "[INFO] stopping MatchEngine PostgreSQL for ${DB_OUTAGE_SECONDS}s"
docker stop eap-match-postgres-loadtest >/dev/null

(
  cd "${ROOT_DIR}/eap-order"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoad \
    --args="--phase publish-only-retain --market-id ${MARKET_ID} --events ${EVENTS} --target-tps ${TARGET_TPS} --timeout-seconds ${TIMEOUT_SECONDS}"
) >"${PUBLISH_LOG}" 2>&1

OPEN_DEADLINE=$(( $(date +%s) + 60 ))
until grep -q "Opening MatchEngine CDA database-outage circuit" "${SERVICE_LOG}"; do
  if [[ $(date +%s) -ge ${OPEN_DEADLINE} ]]; then
    tail -n 160 "${SERVICE_LOG}" >&2 || true
    echo "[ERROR] MatchEngine database circuit did not open" >&2
    exit 1
  fi
  sleep 1
done
wait_for_match_consumer_paused

while (( $(date +%s) - OUTAGE_STARTED_AT < DB_OUTAGE_SECONDS )); do
  sleep 1
done
if ! match_consumer_paused; then
  echo "[ERROR] Match admission consumer resumed or circuit closed before DB recovery" >&2
  exit 1
fi
docker start eap-match-postgres-loadtest >/dev/null
wait_for_healthy eap-match-postgres-loadtest
OUTAGE_RECOVERED_AT="$(date +%s)"
echo "[INFO] MatchEngine PostgreSQL recovered; waiting for automatic drain"
wait_for_recovery

DLQ_AFTER="$(queue_total order.dlq)"
INBOX_ROWS="$(docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -Atqc \
  "SELECT count(*) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}'")"
APPLIED_ROWS="$(docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -Atqc \
  "SELECT count(*) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}' AND status = 'APPLIED'")"
MATCH_DEBT="$(eap_wait_for_zero_durable_debt_snapshot \
  http://localhost:8082/match-engine eap-matchEngine "${MATCH_WORK}" "${TIMEOUT_SECONDS}")"
CIRCUIT_OPENED="$(circuit_metric eap.rabbit.cda.db.circuit.opened COUNT)"
PROBES="$(circuit_metric eap.rabbit.cda.db.probe COUNT)"
PROBE_FAILURES="$(circuit_metric eap.rabbit.cda.db.probe.failure COUNT)"

jq -n \
  --arg runId "${RUN_ID}" \
  --arg marketId "${MARKET_ID}" \
  --argjson outageSeconds "${DB_OUTAGE_SECONDS}" \
  --argjson published "${EVENTS}" \
  --argjson inboxRows "${INBOX_ROWS}" \
  --argjson appliedRows "${APPLIED_ROWS}" \
  --argjson dlqBefore "${DLQ_BEFORE}" \
  --argjson dlqAfter "${DLQ_AFTER}" \
  --argjson measuredOutageSeconds "$(( OUTAGE_RECOVERED_AT - OUTAGE_STARTED_AT ))" \
  --argjson pauseLatencySeconds "$(( PAUSE_VERIFIED_AT - OUTAGE_STARTED_AT ))" \
  --argjson circuitOpened "${CIRCUIT_OPENED}" \
  --argjson probes "${PROBES}" \
  --argjson probeFailures "${PROBE_FAILURES}" \
  --argjson matchDebt "${MATCH_DEBT}" \
  '{schemaVersion:1,contract:"rel104-match-db-outage-recovery",runId:$runId,marketId:$marketId,
    requestedOutageSeconds:$outageSeconds,measuredOutageSeconds:$measuredOutageSeconds,
    pauseVerified:true,pauseHeldUntilRecovery:true,pauseLatencySeconds:$pauseLatencySeconds,
    published:$published,inboxRows:$inboxRows,appliedRows:$appliedRows,
    dlqBefore:$dlqBefore,dlqAfter:$dlqAfter,
    circuit:{opened:$circuitOpened,probes:$probes,probeFailures:$probeFailures,finalOpen:0},
    durableDebtSnapshots:{"eap-matchEngine":$matchDebt},
    valid:($outageSeconds >= 60 and $measuredOutageSeconds >= 60
      and $inboxRows == $published and $appliedRows == $published
      and $dlqBefore == 0 and $dlqAfter == 0
      and $circuitOpened >= 1 and $probes >= 2 and $probes <= 20
      and $probeFailures <= $probes
      and all($matchDebt.components[]; .totalCount == 0))}' >"${RESULT_JSON}"

jq -e '.valid == true' "${RESULT_JSON}" >/dev/null
cat "${RESULT_JSON}"
echo "[INFO] REL-104 MatchEngine outage recovery gate PASS: ${RESULT_JSON}"
