#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
EVENTS="${EVENTS:-200}"
TARGET_TPS="${TARGET_TPS:-100}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-240}"
RUN_ID="${RUN_ID:-REL107_MATCH_REDIS_OUTAGE_$(date +%Y%m%d_%H%M%S)}"
MARKET_ID="${MARKET_ID:-${RUN_ID}}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JAR="${BUILD_JAR:-true}"
SERVICE_LOG="${LOG_DIR}/eap-matchEngine.log"
SERVICE_PID_FILE="${LOG_DIR}/eap-matchEngine.pid"
PUBLISH_LOG="${REPORT_DIR}/rel107-match-redis-outage-${RUN_ID}-publisher.log"
RESULT_JSON="${REPORT_DIR}/rel107-match-redis-outage-${RUN_ID}-result.json"
CONTROL_URL="http://localhost:8082/match-engine/actuator/orderBookRuntime"
MATCH_WORK='["order_admission_inbox","trade_outbox","reservation_cleanup","order_cancellation","reservation_reconciliation"]'
EMPTY_DIGEST="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"
source "${ROOT_DIR}/scripts/load-test/durable-debt-snapshot-lib.sh"

if (( EVENTS < 1 || TARGET_TPS < 1 || TIMEOUT_SECONDS < 30 )); then
  echo "[ERROR] EVENTS and TARGET_TPS must be positive; TIMEOUT_SECONDS must be at least 30" >&2
  exit 2
fi
if [[ ! "${RUN_ID}" =~ ^[A-Za-z0-9_.-]+$ || ! "${MARKET_ID}" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
  echo "[ERROR] RUN_ID or MARKET_ID contains unsupported characters" >&2
  exit 2
fi

stop_match_service() {
  if [[ ! -f "${SERVICE_PID_FILE}" ]]; then
    return
  fi
  local pid
  pid="$(cat "${SERVICE_PID_FILE}")"
  if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${SERVICE_PID_FILE}"
}

cleanup() {
  docker start eap-redis-loadtest >/dev/null 2>&1 || true
  stop_match_service
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

wait_for_control_endpoint() {
  local deadline=$(( $(date +%s) + 120 ))
  until curl -fsS "${CONTROL_URL}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge ${deadline} ]] \
        || ! kill -0 "$(cat "${SERVICE_PID_FILE}" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
      tail -n 160 "${SERVICE_LOG}" >&2 || true
      echo "[ERROR] MatchEngine control endpoint did not become available" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_runtime_state() {
  local expected_state="$1"
  local expected_local_ready="$2"
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  while [[ $(date +%s) -lt ${deadline} ]]; do
    local status
    if status="$(curl -fsS "${CONTROL_URL}" 2>/dev/null)" \
        && jq -e \
          --arg state "${expected_state}" \
          --argjson localReady "${expected_local_ready}" \
          '.control.state == $state and .localReady == $localReady' \
          <<<"${status}" >/dev/null; then
      printf '%s\n' "${status}"
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] MatchEngine runtime did not reach state=${expected_state}, localReady=${expected_local_ready}" >&2
  curl -sS "${CONTROL_URL}" >&2 || true
  tail -n 160 "${SERVICE_LOG}" >&2 || true
  return 1
}

queue_total() {
  local queue="$1"
  docker exec eap-rabbitmq-loadtest rabbitmqctl list_queues name messages --quiet 2>/dev/null \
    | awk -v target="${queue}" '$1 == target {print $2; found=1} END {if (!found) print 0}'
}

match_sql() {
  docker exec eap-match-postgres-loadtest \
    psql -U admin -d eap_match_db -Atqc "$1"
}

inbox_count() {
  local predicate="$1"
  match_sql "SELECT count(*) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}' ${predicate}"
}

wait_for_durable_intake() {
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  while [[ $(date +%s) -lt ${deadline} ]]; do
    local rows queue dlq
    rows="$(inbox_count '')"
    queue="$(queue_total matchEngine.orderConfirmed.queue)"
    dlq="$(queue_total order.dlq)"
    if [[ "${rows}" == "${EVENTS}" && "${queue}" == "0" && "${dlq}" == "0" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] durable intake did not converge while Redis was unavailable" >&2
  return 1
}

wait_for_applied() {
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  while [[ $(date +%s) -lt ${deadline} ]]; do
    local applied terminal queue dlq
    applied="$(inbox_count "AND status = 'APPLIED'")"
    terminal="$(inbox_count "AND status = 'FAILED_PERMANENT'")"
    queue="$(queue_total matchEngine.orderConfirmed.queue)"
    dlq="$(queue_total order.dlq)"
    if [[ "${applied}" == "${EVENTS}" && "${terminal}" == "0" \
        && "${queue}" == "0" && "${dlq}" == "0" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] Match durable inbox did not apply after controlled activation" >&2
  return 1
}

start_match_service() {
  local scheduling_enabled="$1"
  : >"${SERVICE_LOG}"
  java -jar "${MATCH_JAR}" \
    --spring.profiles.active=loadtest \
    --spring.rabbitmq.listener.simple.auto-startup="${scheduling_enabled}" \
    --eap.scheduling.enabled="${scheduling_enabled}" \
    >"${SERVICE_LOG}" 2>&1 &
  echo "$!" >"${SERVICE_PID_FILE}"
  wait_for_control_endpoint
}

bash "${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
docker compose -p eap-loadtest -f "${COMPOSE_FILE}" up -d \
  rabbitmq redis order-postgres match-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-redis-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-match-postgres-loadtest

RABBIT_CONTAINER=eap-rabbitmq-loadtest \
  bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh" >/dev/null

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

# Bootstrap Liquibase without allowing a consumer or worker to touch old test data.
start_match_service false
stop_match_service

# This script is destructive only inside the explicit eap_match_db load-test schema.
MATCH_TABLES="$(match_sql "SELECT string_agg(format('%I.%I', schemaname, tablename), ', ' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'match_engine'")"
if [[ -z "${MATCH_TABLES}" ]]; then
  echo "[ERROR] MatchEngine schema was not created by Liquibase" >&2
  exit 1
fi
match_sql "TRUNCATE TABLE ${MATCH_TABLES} RESTART IDENTITY CASCADE"
docker exec eap-redis-loadtest redis-cli FLUSHALL >/dev/null
RABBIT_CONTAINER=eap-rabbitmq-loadtest \
  bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh" >/dev/null

start_match_service true
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"action":"INITIALIZE_EMPTY","operator":"rel107-failure-injection","reason":"fresh isolated Redis outage recovery campaign"}' \
  "${CONTROL_URL}" >/dev/null
READY_BEFORE="$(wait_for_runtime_state READY true)"
REDIS_RUN_ID_BEFORE="$(docker exec eap-redis-loadtest redis-cli INFO server \
  | awk -F: '$1 == "run_id" {gsub(/\r/, "", $2); print $2}')"

echo "[INFO] stopping Redis and publishing ${EVENTS} Match admission events"
docker stop eap-redis-loadtest >/dev/null
(
  cd "${ROOT_DIR}/eap-order"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoadTest \
    --args="--phase publish-only-retain --market-id ${MARKET_ID} --events ${EVENTS} --target-tps ${TARGET_TPS} --timeout-seconds ${TIMEOUT_SECONDS}"
) >"${PUBLISH_LOG}" 2>&1

wait_for_durable_intake
PRE_ACTIVATION_TOTAL="$(inbox_count '')"
PRE_ACTIVATION_APPLIED="$(inbox_count "AND status = 'APPLIED'")"
PRE_ACTIVATION_TRADES="$(match_sql "SELECT count(*) FROM match_engine.trade_executions WHERE market_id = '${MARKET_ID}'")"
if [[ "${PRE_ACTIVATION_APPLIED}" != "0" || "${PRE_ACTIVATION_TRADES}" != "0" ]]; then
  echo "[ERROR] Match mutated business state while Redis runtime was unavailable" >&2
  exit 1
fi

docker start eap-redis-loadtest >/dev/null
wait_for_healthy eap-redis-loadtest
REDIS_RUN_ID_AFTER="$(docker exec eap-redis-loadtest redis-cli INFO server \
  | awk -F: '$1 == "run_id" {gsub(/\r/, "", $2); print $2}')"
if [[ -z "${REDIS_RUN_ID_BEFORE}" || -z "${REDIS_RUN_ID_AFTER}" \
    || "${REDIS_RUN_ID_BEFORE}" == "${REDIS_RUN_ID_AFTER}" ]]; then
  echo "[ERROR] Redis restart did not produce a new run_id" >&2
  exit 1
fi

RECOVERING_STATUS="$(wait_for_runtime_state RECOVERING false)"
sleep 2
HELD_APPLIED="$(inbox_count "AND status = 'APPLIED'")"
HELD_TRADES="$(match_sql "SELECT count(*) FROM match_engine.trade_executions WHERE market_id = '${MARKET_ID}'")"
HELD_OPEN_ORDERS="$(docker exec eap-redis-loadtest redis-cli ZCARD "orderbook:${MARKET_ID}:buy")"
if [[ "${HELD_APPLIED}" != "0" || "${HELD_TRADES}" != "0" || "${HELD_OPEN_ORDERS}" != "0" ]]; then
  echo "[ERROR] Match did not remain fail-closed before operator activation" >&2
  exit 1
fi

FENCE_EPOCH="$(jq -er '.control.fenceEpoch' <<<"${RECOVERING_STATUS}")"
GENERATION="$(jq -er '.control.generation' <<<"${RECOVERING_STATUS}")"
VERSION="$(jq -er '.control.version' <<<"${RECOVERING_STATUS}")"
ORDER_WATERMARK="$(match_sql "SELECT COALESCE(max(market_sequence), 0) FROM match_engine.order_admission_inbox WHERE market_id = '${MARKET_ID}'")"
TRADE_WATERMARK="$(match_sql "SELECT COALESCE(max(sequence), 0) FROM match_engine.trade_executions")"
ACTIVATION_BODY="$(jq -n \
  --arg manifestId "REL107-${RUN_ID}" \
  --arg generation "${GENERATION}" \
  --arg digest "${EMPTY_DIGEST}" \
  --argjson fenceEpoch "${FENCE_EPOCH}" \
  --argjson version "${VERSION}" \
  --argjson orderWatermark "${ORDER_WATERMARK}" \
  --argjson tradeWatermark "${TRADE_WATERMARK}" \
  '{action:"ACTIVATE_REBUILT",operator:"rel107-failure-injection",
    reason:"verified empty Redis generation; durable inbox remains pending for replay",
    manifestId:$manifestId,expectedFenceEpoch:$fenceEpoch,
    expectedGeneration:$generation,expectedVersion:$version,
    sourceOrderWatermark:$orderWatermark,sourceTradeWatermark:$tradeWatermark,
    expectedOpenOrderCount:0,expectedOpenQuantity:0,expectedIdentityDigest:$digest}')"
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d "${ACTIVATION_BODY}" "${CONTROL_URL}" >/dev/null
wait_for_runtime_state READY true >/dev/null
wait_for_applied

MATCH_DEBT="$(eap_wait_for_zero_durable_debt_snapshot \
  http://localhost:8082/match-engine eap-matchEngine "${MATCH_WORK}" "${TIMEOUT_SECONDS}")"
FINAL_STATUS="$(curl -fsS "${CONTROL_URL}")"
INBOX_TOTAL="$(inbox_count '')"
INBOX_APPLIED="$(inbox_count "AND status = 'APPLIED'")"
INBOX_TERMINAL="$(inbox_count "AND status = 'FAILED_PERMANENT'")"
TRADE_COUNT="$(match_sql "SELECT count(*) FROM match_engine.trade_executions WHERE market_id = '${MARKET_ID}'")"
DISTINCT_TRADE_COUNT="$(match_sql "SELECT count(DISTINCT trade_id) FROM match_engine.trade_executions WHERE market_id = '${MARKET_ID}'")"
OPEN_BUY_ORDERS="$(docker exec eap-redis-loadtest redis-cli ZCARD "orderbook:${MARKET_ID}:buy")"
OPEN_SELL_ORDERS="$(docker exec eap-redis-loadtest redis-cli ZCARD "orderbook:${MARKET_ID}:sell")"
ORDER_DETAIL_KEYS="$(docker exec eap-redis-loadtest redis-cli --scan --pattern 'order:*' \
  | awk -F: 'NF == 2 {count++} END {print count + 0}')"
COMPLETED_BITS="$(docker exec eap-redis-loadtest redis-cli BITCOUNT \
  "match:incoming-order:completed:${MARKET_ID}:0")"
RESERVATION_KEYS="$(docker exec eap-redis-loadtest redis-cli --scan --pattern 'order:reservation:*' \
  | awk 'END {print NR + 0}')"
PROCESSING_KEYS="$(docker exec eap-redis-loadtest redis-cli --scan --pattern 'match:incoming-order:states:*' \
  | awk 'END {print NR + 0}')"
SOURCE_QUEUE="$(queue_total matchEngine.orderConfirmed.queue)"
DLQ="$(queue_total order.dlq)"

jq -n \
  --arg runId "${RUN_ID}" \
  --arg marketId "${MARKET_ID}" \
  --arg redisRunIdBefore "${REDIS_RUN_ID_BEFORE}" \
  --arg redisRunIdAfter "${REDIS_RUN_ID_AFTER}" \
  --argjson published "${EVENTS}" \
  --argjson preActivationTotal "${PRE_ACTIVATION_TOTAL}" \
  --argjson preActivationApplied "${PRE_ACTIVATION_APPLIED}" \
  --argjson preActivationTrades "${PRE_ACTIVATION_TRADES}" \
  --argjson heldApplied "${HELD_APPLIED}" \
  --argjson heldTrades "${HELD_TRADES}" \
  --argjson heldOpenOrders "${HELD_OPEN_ORDERS}" \
  --argjson inboxTotal "${INBOX_TOTAL}" \
  --argjson inboxApplied "${INBOX_APPLIED}" \
  --argjson inboxTerminal "${INBOX_TERMINAL}" \
  --argjson tradeCount "${TRADE_COUNT}" \
  --argjson distinctTradeCount "${DISTINCT_TRADE_COUNT}" \
  --argjson openBuyOrders "${OPEN_BUY_ORDERS}" \
  --argjson openSellOrders "${OPEN_SELL_ORDERS}" \
  --argjson orderDetailKeys "${ORDER_DETAIL_KEYS}" \
  --argjson completedBits "${COMPLETED_BITS}" \
  --argjson reservationKeys "${RESERVATION_KEYS}" \
  --argjson processingKeys "${PROCESSING_KEYS}" \
  --argjson sourceQueue "${SOURCE_QUEUE}" \
  --argjson dlq "${DLQ}" \
  --argjson readyBefore "${READY_BEFORE}" \
  --argjson recoveringStatus "${RECOVERING_STATUS}" \
  --argjson finalStatus "${FINAL_STATUS}" \
  --argjson matchDebt "${MATCH_DEBT}" \
  '{schemaVersion:1,contract:"rel107-match-redis-outage-recovery",
    evidenceClass:"failure-injection-correctness",capacityClaimAllowed:false,
    runId:$runId,marketId:$marketId,published:$published,
    redis:{runIdBefore:$redisRunIdBefore,runIdAfter:$redisRunIdAfter,restartProven:($redisRunIdBefore != $redisRunIdAfter)},
    failClosed:{durableIntake:$preActivationTotal,appliedBeforeActivation:$preActivationApplied,
      tradesBeforeActivation:$preActivationTrades,appliedAfterRestartBeforeActivation:$heldApplied,
      tradesAfterRestartBeforeActivation:$heldTrades,openOrdersBeforeActivation:$heldOpenOrders,
      recoveringStatus:$recoveringStatus},
    recovery:{inboxTotal:$inboxTotal,inboxApplied:$inboxApplied,inboxTerminal:$inboxTerminal,
      tradeCount:$tradeCount,distinctTradeCount:$distinctTradeCount,
      openBuyOrders:$openBuyOrders,openSellOrders:$openSellOrders,
      orderDetailKeys:$orderDetailKeys,completedBits:$completedBits,
      reservationKeys:$reservationKeys,processingKeys:$processingKeys,
      sourceQueue:$sourceQueue,dlq:$dlq,finalStatus:$finalStatus,durableDebt:$matchDebt},
    initialStatus:$readyBefore,
    correctnessGate:(if
      $preActivationTotal == $published and $preActivationApplied == 0 and $preActivationTrades == 0
      and $heldApplied == 0 and $heldTrades == 0 and $heldOpenOrders == 0
      and $inboxTotal == $published and $inboxApplied == $published and $inboxTerminal == 0
      and $tradeCount == 0 and $distinctTradeCount == 0
      and $openBuyOrders == $published and $openSellOrders == 0
      and $orderDetailKeys == $published and $completedBits == $published
      and $reservationKeys == 0 and $processingKeys == 0
      and $sourceQueue == 0 and $dlq == 0
      and $recoveringStatus.control.state == "RECOVERING" and $recoveringStatus.localReady == false
      and $finalStatus.control.state == "READY" and $finalStatus.localReady == true
      then "PASS" else "FAIL" end)}' >"${RESULT_JSON}"

if ! jq -e '.correctnessGate == "PASS"' "${RESULT_JSON}" >/dev/null; then
  jq . "${RESULT_JSON}" >&2
  echo "[ERROR] REL-107 Match Redis outage recovery gate failed" >&2
  exit 1
fi

jq . "${RESULT_JSON}"
echo "[PASS] REL-107 Match Redis outage recovery evidence: ${RESULT_JSON}"
