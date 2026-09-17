#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
TRADES="${TRADES:-10000}"
TARGET_TRADE_TPS="${TARGET_TRADE_TPS:-1000}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MARKET_ID="${MARKET_ID:-TRADE_FANOUT_$(date +%Y%m%d_%H%M%S)}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JARS="${BUILD_JARS:-true}"
DB_OUTAGE_SECONDS="${DB_OUTAGE_SECONDS:-0}"
PRE_PUBLISH_DELAY_SECONDS="${PRE_PUBLISH_DELAY_SECONDS:-10}"
OUTPUT="${REPORT_DIR}/trade-consumer-fanout-${RUN_ID}.json"
GENERATOR_LOG="${REPORT_DIR}/trade-consumer-fanout-${RUN_ID}-generator.log"
EVIDENCE_OUTPUT="${REPORT_DIR}/trade-consumer-fanout-${RUN_ID}-rel104-evidence.json"
ORDER_WORK='["asset_reservation_result_inbox","trade_execution_inbox","cancellation_result_inbox","asset_reservation_released_inbox","event_outbox","orders_current_projection"]'
WALLET_WORK='["order_submission_inbox","cancellation_result_inbox","trade_execution_inbox","event_outbox"]'
OUTAGE_STARTED_EPOCH_SECONDS=0
OUTAGE_RECOVERED_EPOCH_SECONDS=0
PAUSE_VERIFIED_EPOCH_SECONDS=0

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"
source "${ROOT_DIR}/scripts/load-test/durable-debt-snapshot-lib.sh"

if (( DB_OUTAGE_SECONDS > 0 && DB_OUTAGE_SECONDS < 60 )); then
  echo "[ERROR] REL-104 failure mode requires DB_OUTAGE_SECONDS >= 60" >&2
  exit 2
fi

find_service_jar() {
  local repo="$1"
  find "${ROOT_DIR}/${repo}/build/libs" -maxdepth 1 -type f \
    -name "${repo}-*.jar" \
    ! -name "*-plain.jar" \
    ! -name "*-stubs.jar" \
    | sort \
    | head -n 1
}

stop_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${pid_file}"
  fi
}

cleanup() {
  docker start eap-order-postgres-loadtest eap-wallet-postgres-loadtest >/dev/null 2>&1 || true
  stop_pid "${LOG_DIR}/eap-order.pid"
  stop_pid "${LOG_DIR}/eap-wallet.pid"
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" stop order-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_healthy() {
  local container="$1"
  local deadline=$(( $(date +%s) + 60 ))
  until [[ "$(docker inspect --format '{{.State.Health.Status}}' "${container}" 2>/dev/null || true)" == "healthy" ]]; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] ${container} did not become healthy" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_http() {
  local service="$1"
  local url="$2"
  local log_file="$3"
  local pid_file="$4"
  local deadline=$(( $(date +%s) + 120 ))
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
      echo "[ERROR] ${service} did not become ready: ${url}" >&2
      tail -n 100 "${log_file}" >&2 || true
      exit 1
    fi
    sleep 1
  done
}

queue_metric() {
  local queue="$1"
  local field="$2"
  docker exec eap-rabbitmq-loadtest rabbitmqctl list_queues name messages consumers --quiet 2>/dev/null \
    | awk -v target="${queue}" -v field="${field}" '
        $1 == target {if (field == "messages") print $2; else print $3; found=1}
        END {if (!found) print 0}'
}

circuit_metric() {
  local actuator_base="$1"
  local metric_name="$2"
  local statistic="$3"
  curl -fsS "${actuator_base}/actuator/metrics/${metric_name}" \
    | jq -er --arg statistic "${statistic}" '.measurements[] | select(.statistic == $statistic) | .value'
}

trade_consumers_paused() {
  local order_messages wallet_messages order_consumers wallet_consumers order_open wallet_open
  order_messages="$(queue_metric order.tradeExecuted.queue messages)"
  wallet_messages="$(queue_metric wallet.tradeExecuted.queue messages)"
  order_consumers="$(queue_metric order.tradeExecuted.queue consumers)"
  wallet_consumers="$(queue_metric wallet.tradeExecuted.queue consumers)"
  order_open="$(circuit_metric http://localhost:8080/eap-order eap.rabbit.cda.db.circuit.open VALUE 2>/dev/null || echo -1)"
  wallet_open="$(circuit_metric http://localhost:8081/eap-wallet eap.rabbit.cda.db.circuit.open VALUE 2>/dev/null || echo -1)"
  (( order_messages > 0 && wallet_messages > 0 \
      && order_consumers == 0 && wallet_consumers == 0 )) \
    && [[ "${order_open}" == "1.0" && "${wallet_open}" == "1.0" ]]
}

wait_for_trade_consumers_paused() {
  local deadline=$(( $(date +%s) + 45 ))
  until trade_consumers_paused; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] Order/Wallet trade consumers did not pause with source backlog before timeout" >&2
      return 1
    fi
    sleep 1
  done
  PAUSE_VERIFIED_EPOCH_SECONDS="$(date +%s)"
}

start_service() {
  local repo="$1"
  local health_url="$2"
  shift 2
  local jar
  local log_file="${LOG_DIR}/${repo}.log"
  local pid_file="${LOG_DIR}/${repo}.pid"
  jar="$(find_service_jar "${repo}")"
  if [[ -z "${jar}" ]]; then
    echo "[ERROR] executable jar missing for ${repo}" >&2
    exit 1
  fi
  java -jar "${jar}" --spring.profiles.active=loadtest "$@" >"${log_file}" 2>&1 &
  echo "$!" >"${pid_file}"
  wait_http "${repo}" "${health_url}" "${log_file}" "${pid_file}"
}

run_generator() {
  local phase="$1"
  local target_tps="$2"
  local output_args=()
  local outage_args=()
  if [[ "${phase}" == "downstream-run" ]]; then
    output_args=(--output "${OUTPUT}")
    if (( DB_OUTAGE_SECONDS > 0 )); then
      outage_args=(--pre-publish-delay-seconds "${PRE_PUBLISH_DELAY_SECONDS}")
    fi
  fi
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoad \
      --args="--phase ${phase} --market-id ${MARKET_ID} --events ${TRADES} --target-tps ${target_tps} --timeout-seconds ${TIMEOUT_SECONDS} ${outage_args[*]} ${output_args[*]}"
  )
}

run_with_database_outage() {
  echo "[INFO] starting downstream generator with a ${PRE_PUBLISH_DELAY_SECONDS}s injection window"
  run_generator downstream-run "${TARGET_TRADE_TPS}" >"${GENERATOR_LOG}" 2>&1 &
  local generator_pid=$!
  local marker_deadline=$(( $(date +%s) + 90 ))
  until grep -q "downstream pre-publish delay active" "${GENERATOR_LOG}" 2>/dev/null; do
    if ! kill -0 "${generator_pid}" >/dev/null 2>&1; then
      wait "${generator_pid}" || true
      cat "${GENERATOR_LOG}" >&2
      echo "[ERROR] downstream generator exited before the outage injection point" >&2
      return 1
    fi
    if [[ $(date +%s) -ge ${marker_deadline} ]]; then
      cat "${GENERATOR_LOG}" >&2
      echo "[ERROR] timed out waiting for downstream pre-publish marker" >&2
      return 1
    fi
    sleep 1
  done

  echo "[INFO] stopping Order and Wallet PostgreSQL for ${DB_OUTAGE_SECONDS}s"
  OUTAGE_STARTED_EPOCH_SECONDS="$(date +%s)"
  docker stop eap-order-postgres-loadtest eap-wallet-postgres-loadtest >/dev/null
  wait_for_trade_consumers_paused
  while (( $(date +%s) - OUTAGE_STARTED_EPOCH_SECONDS < DB_OUTAGE_SECONDS )); do
    sleep 1
  done
  if ! trade_consumers_paused; then
    echo "[ERROR] Order/Wallet trade consumers resumed or circuit closed before DB recovery" >&2
    return 1
  fi
  docker start eap-order-postgres-loadtest eap-wallet-postgres-loadtest >/dev/null
  wait_for_healthy eap-order-postgres-loadtest
  wait_for_healthy eap-wallet-postgres-loadtest
  OUTAGE_RECOVERED_EPOCH_SECONDS="$(date +%s)"
  echo "[INFO] PostgreSQL recovered; waiting for automatic consumer drain"

  local generator_status=0
  wait "${generator_pid}" || generator_status=$?
  cat "${GENERATOR_LOG}"
  if (( generator_status != 0 )); then
    echo "[ERROR] downstream recovery generator failed with status ${generator_status}" >&2
    return "${generator_status}"
  fi
}

wait_for_circuit_recovery() {
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  until circuit_opened_and_closed "http://localhost:8080/eap-order" \
      && circuit_opened_and_closed "http://localhost:8081/eap-wallet"; do
    if [[ $(date +%s) -ge ${deadline} ]]; then
      echo "[ERROR] Order/Wallet database circuits did not fully resume before timeout" >&2
      tail -n 120 "${LOG_DIR}/eap-order.log" >&2 || true
      tail -n 120 "${LOG_DIR}/eap-wallet.log" >&2 || true
      return 1
    fi
    sleep 1
  done
}

circuit_opened_and_closed() {
  local actuator_base="$1"
  local open_value opened_value
  open_value="$(circuit_metric "${actuator_base}" eap.rabbit.cda.db.circuit.open VALUE 2>/dev/null || echo -1)"
  opened_value="$(circuit_metric "${actuator_base}" eap.rabbit.cda.db.circuit.opened COUNT 2>/dev/null || echo 0)"
  [[ "${open_value}" == "0.0" ]] && awk -v value="${opened_value}" 'BEGIN {exit !(value >= 1)}'
}

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true

echo "[INFO] starting only RabbitMQ and the Order/Wallet PostgreSQL instances"
docker compose -p eap-loadtest -f "${COMPOSE_FILE}" up -d rabbitmq order-postgres wallet-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-wallet-postgres-loadtest

echo "[INFO] purging retained RabbitMQ messages before consumers start"
RABBIT_CONTAINER=eap-rabbitmq-loadtest bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"

if [[ "${BUILD_JARS}" == "true" ]]; then
  echo "[INFO] building only Order and Wallet executable jars"
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
  )
  (
    cd "${ROOT_DIR}/eap-wallet"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
  )
else
  echo "[INFO] reusing existing Order and Wallet executable jars"
fi

start_service eap-order http://localhost:8080/eap-order/actuator/health \
  --eap.order.market-data-scheduler.enabled=false \
  --eap.rate-limit.enabled=false \
  --management.health.redis.enabled=false
start_service eap-wallet http://localhost:8081/eap-wallet/actuator/health \
  --eap.wallet.outbox-relay.enabled=false

echo "[INFO] seeding legal Order and Wallet state; trades=${TRADES}, marketId=${MARKET_ID}"
run_generator downstream-seed 0

echo "[INFO] publishing TradeExecuted at target=${TARGET_TRADE_TPS} events/s"
if (( DB_OUTAGE_SECONDS > 0 )); then
  run_with_database_outage
else
  run_generator downstream-run "${TARGET_TRADE_TPS}"
fi

if (( DB_OUTAGE_SECONDS > 0 )); then
  wait_for_circuit_recovery
  jq -e '
    .correctnessGate == "PASS"
    and .dlqMax == 0
    and .dlqFinal.total == 0
    and .databaseObservationReadFailures > 0
  ' "${OUTPUT}" >/dev/null
  grep -q "Opening Order CDA database-outage circuit" "${LOG_DIR}/eap-order.log"
  grep -q "Opening Wallet CDA database-outage circuit" "${LOG_DIR}/eap-wallet.log"

  ORDER_DEBT="$(eap_wait_for_zero_durable_debt_snapshot \
    http://localhost:8080/eap-order eap-order "${ORDER_WORK}" "${TIMEOUT_SECONDS}")"
  WALLET_DEBT="$(eap_wait_for_zero_durable_debt_snapshot \
    http://localhost:8081/eap-wallet eap-wallet "${WALLET_WORK}" "${TIMEOUT_SECONDS}")"
  ORDER_OPENED="$(circuit_metric http://localhost:8080/eap-order eap.rabbit.cda.db.circuit.opened COUNT)"
  WALLET_OPENED="$(circuit_metric http://localhost:8081/eap-wallet eap.rabbit.cda.db.circuit.opened COUNT)"
  ORDER_PROBES="$(circuit_metric http://localhost:8080/eap-order eap.rabbit.cda.db.probe COUNT)"
  WALLET_PROBES="$(circuit_metric http://localhost:8081/eap-wallet eap.rabbit.cda.db.probe COUNT)"
  ORDER_PROBE_FAILURES="$(circuit_metric http://localhost:8080/eap-order eap.rabbit.cda.db.probe.failure COUNT)"
  WALLET_PROBE_FAILURES="$(circuit_metric http://localhost:8081/eap-wallet eap.rabbit.cda.db.probe.failure COUNT)"

  jq -n \
    --arg runId "${RUN_ID}" \
    --arg marketId "${MARKET_ID}" \
    --argjson requestedOutageSeconds "${DB_OUTAGE_SECONDS}" \
    --argjson measuredOutageSeconds "$(( OUTAGE_RECOVERED_EPOCH_SECONDS - OUTAGE_STARTED_EPOCH_SECONDS ))" \
    --argjson pauseLatencySeconds "$(( PAUSE_VERIFIED_EPOCH_SECONDS - OUTAGE_STARTED_EPOCH_SECONDS ))" \
    --argjson businessResult "$(cat "${OUTPUT}")" \
    --argjson orderDebt "${ORDER_DEBT}" \
    --argjson walletDebt "${WALLET_DEBT}" \
    --argjson orderOpened "${ORDER_OPENED}" \
    --argjson walletOpened "${WALLET_OPENED}" \
    --argjson orderProbes "${ORDER_PROBES}" \
    --argjson walletProbes "${WALLET_PROBES}" \
    --argjson orderProbeFailures "${ORDER_PROBE_FAILURES}" \
    --argjson walletProbeFailures "${WALLET_PROBE_FAILURES}" \
    '{rel104EvidenceSchemaVersion:1, contract:"rel104-order-wallet-db-outage-recovery",
      runId:$runId, marketId:$marketId, requestedOutageSeconds:$requestedOutageSeconds,
      measuredOutageSeconds:$measuredOutageSeconds, pauseVerified:true,
      pauseHeldUntilRecovery:true, pauseLatencySeconds:$pauseLatencySeconds,
      circuits:{order:{opened:$orderOpened,probes:$orderProbes,probeFailures:$orderProbeFailures,finalOpen:0},
        wallet:{opened:$walletOpened,probes:$walletProbes,probeFailures:$walletProbeFailures,finalOpen:0}},
      durableDebtSnapshots:{"eap-order":$orderDebt,"eap-wallet":$walletDebt},
      businessResult:$businessResult}' >"${EVIDENCE_OUTPUT}"
  jq -e '
    .requestedOutageSeconds >= 60 and .measuredOutageSeconds >= 60
    and .pauseVerified and .pauseHeldUntilRecovery
    and all(.circuits[]; .opened >= 1 and .probes >= 2 and .probes <= 20
      and .probeFailures <= .probes and .finalOpen == 0)
    and .businessResult.correctnessGate == "PASS"
    and .businessResult.dlqMax == 0 and .businessResult.dlqFinal.total == 0
    and all(.durableDebtSnapshots[].components[]; .totalCount == 0)
  ' "${EVIDENCE_OUTPUT}" >/dev/null
  echo "[INFO] REL-104 Order/Wallet outage recovery gate PASS: ${EVIDENCE_OUTPUT}"
fi

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  measurementBoundary,
  trades,
  targetTradeEventsPerSecond,
  publisherConfirmedEventsPerSecond,
  orderApplicationsPerSecond,
  walletSettlementsPerSecond,
  durableFanoutTradesPerSecond,
  fanoutConvergedTradesPerSecond,
  orderQueueMax,
  walletQueueMax,
  dlqMax,
  correctnessGate,
  capacityClaimAllowed
}' "${OUTPUT}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${OUTPUT}" >/dev/null
echo "[INFO] readable report=${OUTPUT%.json}-report.md"
