#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
POST_CONFIRM_CRASH_ENABLED="${POST_CONFIRM_CRASH_ENABLED:-false}"
if [[ "${POST_CONFIRM_CRASH_ENABLED}" == "true" ]]; then
  TRADES="${TRADES:-200}"
else
  TRADES="${TRADES:-10000}"
fi
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
MARKET_ID="${MARKET_ID:-MATCH_RELAY_DOWNSTREAM_$(date +%Y%m%d_%H%M%S)}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
KEEP_INFRA="${KEEP_INFRA:-false}"
BUILD_JARS="${BUILD_JARS:-true}"
OUTPUT="${REPORT_DIR}/match-relay-downstream-${RUN_ID}.json"
POST_CONFIRM_PAUSE_MS="${POST_CONFIRM_PAUSE_MS:-120000}"
POST_CONFIRM_MARKER="${LOG_DIR}/match-post-confirm-${RUN_ID}.json"
POST_CONFIRM_EVIDENCE="${REPORT_DIR}/match-relay-downstream-${RUN_ID}-outbox-confirm-crash-evidence.json"
GENERATOR_LOG="${REPORT_DIR}/match-relay-downstream-${RUN_ID}-generator.log"
GENERATOR_PID=""
ORDER_WORK='["asset_reservation_result_inbox","trade_execution_inbox","cancellation_result_inbox","asset_reservation_released_inbox","event_outbox","orders_current_projection"]'
WALLET_WORK='["order_submission_inbox","cancellation_result_inbox","trade_execution_inbox","event_outbox"]'
MATCH_WORK='["order_admission_inbox","trade_outbox","reservation_cleanup","order_cancellation","reservation_reconciliation"]'

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"
source "${ROOT_DIR}/scripts/load-test/durable-debt-snapshot-lib.sh"

if [[ ! "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || [[ ! "${MARKET_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "[ERROR] RUN_ID and MARKET_ID may contain only letters, digits, dot, underscore, and dash" >&2
  exit 2
fi
if [[ "${POST_CONFIRM_CRASH_ENABLED}" != "true" && "${POST_CONFIRM_CRASH_ENABLED}" != "false" ]]; then
  echo "[ERROR] POST_CONFIRM_CRASH_ENABLED must be true or false" >&2
  exit 2
fi
if [[ "${POST_CONFIRM_CRASH_ENABLED}" == "true" ]]; then
  if ! [[ "${TRADES}" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] TRADES must be a positive integer" >&2
    exit 2
  fi
  if ! [[ "${POST_CONFIRM_PAUSE_MS}" =~ ^[0-9]+$ ]] || (( POST_CONFIRM_PAUSE_MS < 30000 || POST_CONFIRM_PAUSE_MS > 300000 )); then
    echo "[ERROR] POST_CONFIRM_PAUSE_MS must be between 30000 and 300000" >&2
    exit 2
  fi
  if (( TRADES <= 0 || TRADES > 500 )); then
    echo "[ERROR] post-confirm crash mode requires 1 <= TRADES <= 500 so one confirmed relay batch is fenced" >&2
    exit 2
  fi
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
  if [[ -n "${GENERATOR_PID}" ]] && kill -0 "${GENERATOR_PID}" >/dev/null 2>&1; then
    kill "${GENERATOR_PID}" >/dev/null 2>&1 || true
    wait "${GENERATOR_PID}" >/dev/null 2>&1 || true
  fi
  stop_pid "${LOG_DIR}/eap-order.pid"
  stop_pid "${LOG_DIR}/eap-wallet.pid"
  stop_pid "${LOG_DIR}/eap-matchEngine.pid"
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" stop \
      order-postgres wallet-postgres match-postgres rabbitmq redis >/dev/null 2>&1 || true
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
  if [[ "${repo}" == "eap-matchEngine" ]]; then
    local control_url="http://localhost:8082/match-engine/actuator/orderBookRuntime"
    local deadline=$(( $(date +%s) + 120 ))
    until curl -fsS "${control_url}" >/dev/null 2>&1; do
      if [[ $(date +%s) -ge ${deadline} ]]; then
        echo "[ERROR] MatchEngine runtime control endpoint did not start" >&2
        tail -n 80 "${log_file}" >&2 || true
        exit 1
      fi
      sleep 1
    done
    curl -fsS -X POST \
      -H 'Content-Type: application/json' \
      -d '{"action":"INITIALIZE_EMPTY","operator":"match-relay-probe","reason":"isolated probe runtime"}' \
      "${control_url}" >/dev/null
  fi
  wait_http "${repo}" "${health_url}" "${log_file}" "${pid_file}"
}

start_match_service() {
  local relay_enabled="$1"
  shift
  start_service eap-matchEngine http://localhost:8082/match-engine/actuator/health \
    --spring.rabbitmq.listener.simple.auto-startup=false \
    --eap.match-engine.trade-outbox-relay.enabled="${relay_enabled}" \
    --eap.match-engine.trade-checkpoint-relay.enabled=false \
    --eap.match-engine.reservation-cleanup.enabled=false \
    --eap.match-engine.reservation-reconciler.enabled=false \
    "$@"
}

match_query() {
  docker exec eap-match-postgres-loadtest psql -U admin -d eap_match_db -Atqc "$1"
}

order_query() {
  docker exec eap-order-postgres-loadtest psql -U admin -d eap_order_db -Atqc "$1"
}

wallet_query() {
  docker exec eap-wallet-postgres-loadtest psql -U admin -d eap_wallet_db -Atqc "$1"
}

reset_match_probe_runtime() {
  local match_tables
  match_tables="$(match_query "SELECT string_agg(format('%I.%I', schemaname, tablename), ', ' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'match_engine'")"
  if [[ -n "${match_tables}" ]]; then
    match_query "TRUNCATE TABLE ${match_tables} RESTART IDENTITY CASCADE"
  fi
  docker exec eap-redis-loadtest redis-cli FLUSHALL >/dev/null
}

wait_for_post_confirm_marker() {
  local match_pid="$1"
  local deadline=$(( $(date +%s) + 90 ))
  until [[ -s "${POST_CONFIRM_MARKER}" ]]; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "${match_pid}" >/dev/null 2>&1; then
      echo "[ERROR] Match relay did not enter the post-confirm/pre-SENT window" >&2
      tail -n 160 "${LOG_DIR}/eap-matchEngine.log" >&2 || true
      return 1
    fi
    sleep 1
  done
  jq -e \
    --argjson expectedPid "${match_pid}" \
    --argjson expectedCount "${TRADES}" \
    '.processId == $expectedPid and .confirmedCount == $expectedCount
      and (.confirmedOutboxIds | length) == $expectedCount' \
    "${POST_CONFIRM_MARKER}" >/dev/null
}

assert_expected_match_process() {
  local match_pid="$1"
  local process_args
  process_args="$(ps -p "${match_pid}" -o args= 2>/dev/null || true)"
  if [[ "${process_args}" != *"eap-matchEngine"* \
      || "${process_args}" != *"post-confirm-pause-enabled=true"* \
      || "${process_args}" != *"marker-path=${POST_CONFIRM_MARKER}"* ]]; then
    echo "[ERROR] refusing to SIGKILL unexpected process: pid=${match_pid}, args=${process_args}" >&2
    return 1
  fi
}

wait_for_first_delivery_business_completion() {
  local deadline=$(( $(date +%s) + 60 ))
  local order_count=0
  local wallet_count=0
  while [[ $(date +%s) -lt ${deadline} ]]; do
    order_count="$(order_query "SELECT count(*) FROM order_service.order_trade_applications WHERE trade_id LIKE '${MARKET_ID}-%'")"
    wallet_count="$(wallet_query "SELECT count(*) FROM wallet_service.trade_settlements WHERE trade_id LIKE '${MARKET_ID}-%'")"
    if [[ "${order_count}" == "${TRADES}" && "${wallet_count}" == "${TRADES}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] first confirmed delivery did not complete before forced Match crash: order=${order_count}, wallet=${wallet_count}" >&2
  return 1
}

wallet_duplicate_count() {
  curl -fsS http://localhost:8081/eap-wallet/actuator/prometheus \
    | awk '$1 ~ /^eap_wallet_trade_inbox_duplicate_total($|\{)/ {total += $2} END {print total + 0}'
}

run_with_post_confirm_crash() {
  rm -f "${POST_CONFIRM_MARKER}" "${POST_CONFIRM_MARKER}.tmp" "${POST_CONFIRM_EVIDENCE}"
  start_match_service true \
    --eap.match-engine.trade-outbox-relay.batch-size="${TRADES}" \
    --eap.match-engine.trade-outbox-relay.publish-concurrency=1 \
    --eap.match-engine.trade-outbox-relay.failure-injection.post-confirm-pause-enabled=true \
    --eap.match-engine.trade-outbox-relay.failure-injection.post-confirm-pause-ms="${POST_CONFIRM_PAUSE_MS}" \
    --eap.match-engine.trade-outbox-relay.failure-injection.marker-path="${POST_CONFIRM_MARKER}"

  run_generator relay-downstream-run >"${GENERATOR_LOG}" 2>&1 &
  GENERATOR_PID="$!"
  local match_pid
  match_pid="$(cat "${LOG_DIR}/eap-matchEngine.pid")"
  wait_for_post_confirm_marker "${match_pid}"
  wait_for_first_delivery_business_completion

  local pending_before_crash sent_before_crash order_before_crash wallet_before_crash
  pending_before_crash="$(match_query "SELECT count(*) FROM match_engine.trade_outbox WHERE aggregate_id LIKE '${MARKET_ID}-%' AND status = 'PENDING'")"
  sent_before_crash="$(match_query "SELECT count(*) FROM match_engine.trade_outbox WHERE aggregate_id LIKE '${MARKET_ID}-%' AND status = 'SENT'")"
  order_before_crash="$(order_query "SELECT count(*) FROM order_service.order_trade_applications WHERE trade_id LIKE '${MARKET_ID}-%'")"
  wallet_before_crash="$(wallet_query "SELECT count(*) FROM wallet_service.trade_settlements WHERE trade_id LIKE '${MARKET_ID}-%'")"
  if [[ "${pending_before_crash}" != "${TRADES}" || "${sent_before_crash}" != "0" \
      || "${order_before_crash}" != "${TRADES}" || "${wallet_before_crash}" != "${TRADES}" ]]; then
    echo "[ERROR] pre-crash ambiguity gate failed: pending=${pending_before_crash}, sent=${sent_before_crash}, order=${order_before_crash}, wallet=${wallet_before_crash}" >&2
    return 1
  fi

  assert_expected_match_process "${match_pid}"
  echo "[INFO] broker-confirmed delivery is durable downstream while Match outbox remains PENDING; SIGKILL pid=${match_pid}"
  kill -KILL "${match_pid}"
  wait "${match_pid}" >/dev/null 2>&1 || true
  rm -f "${LOG_DIR}/eap-matchEngine.pid"
  if kill -0 "${match_pid}" >/dev/null 2>&1; then
    echo "[ERROR] MatchEngine survived SIGKILL" >&2
    return 1
  fi

  local pending_after_crash
  pending_after_crash="$(match_query "SELECT count(*) FROM match_engine.trade_outbox WHERE aggregate_id LIKE '${MARKET_ID}-%' AND status = 'PENDING'")"
  if [[ "${pending_after_crash}" != "${TRADES}" ]]; then
    echo "[ERROR] confirmed-but-uncommitted outbox rows did not remain PENDING after crash: ${pending_after_crash}" >&2
    return 1
  fi

  echo "[INFO] restarting MatchEngine without the failure-injection probe"
  start_match_service true \
    --eap.match-engine.trade-outbox-relay.batch-size="${TRADES}" \
    --eap.match-engine.trade-outbox-relay.publish-concurrency=1
  if ! wait "${GENERATOR_PID}"; then
    tail -n 180 "${GENERATOR_LOG}" >&2 || true
    return 1
  fi
  GENERATOR_PID=""

  local duplicate_count
  duplicate_count="$(wallet_duplicate_count)"
  if ! awk -v duplicates="${duplicate_count}" -v expected="${TRADES}" 'BEGIN {exit !(duplicates >= expected)}'; then
    echo "[ERROR] Wallet did not observe the expected replay duplicates: duplicates=${duplicate_count}, expected>=${TRADES}" >&2
    return 1
  fi

  local order_debt wallet_debt match_debt
  order_debt="$(eap_wait_for_zero_durable_debt_snapshot \
    http://localhost:8080/eap-order eap-order "${ORDER_WORK}" "${TIMEOUT_SECONDS}")"
  wallet_debt="$(eap_wait_for_zero_durable_debt_snapshot \
    http://localhost:8081/eap-wallet eap-wallet "${WALLET_WORK}" "${TIMEOUT_SECONDS}")"
  match_debt="$(eap_wait_for_zero_durable_debt_snapshot \
    http://localhost:8082/match-engine eap-matchEngine "${MATCH_WORK}" "${TIMEOUT_SECONDS}")"

  jq -n \
    --arg runId "${RUN_ID}" \
    --arg marketId "${MARKET_ID}" \
    --argjson crashedPid "${match_pid}" \
    --argjson pendingBeforeCrash "${pending_before_crash}" \
    --argjson sentBeforeCrash "${sent_before_crash}" \
    --argjson orderBeforeCrash "${order_before_crash}" \
    --argjson walletBeforeCrash "${wallet_before_crash}" \
    --argjson pendingAfterCrash "${pending_after_crash}" \
    --argjson walletDuplicateCount "${duplicate_count}" \
    --argjson marker "$(cat "${POST_CONFIRM_MARKER}")" \
    --argjson businessResult "$(cat "${OUTPUT}")" \
    --argjson orderDebt "${order_debt}" \
    --argjson walletDebt "${wallet_debt}" \
    --argjson matchDebt "${match_debt}" \
    '{schemaVersion:1,contract:"rel107-match-outbox-confirm-ambiguity",runId:$runId,marketId:$marketId,
      signal:"SIGKILL",crashedPid:$crashedPid,marker:$marker,
      ambiguityWindow:{pendingBeforeCrash:$pendingBeforeCrash,sentBeforeCrash:$sentBeforeCrash,
        orderApplicationsBeforeCrash:$orderBeforeCrash,walletSettlementsBeforeCrash:$walletBeforeCrash,
        pendingAfterCrash:$pendingAfterCrash},
      replay:{walletDuplicateDeliveries:$walletDuplicateCount},businessResult:$businessResult,
      durableDebtSnapshots:{"eap-order":$orderDebt,"eap-wallet":$walletDebt,"eap-matchEngine":$matchDebt}}' \
    >"${POST_CONFIRM_EVIDENCE}"

  jq -e '
    .signal == "SIGKILL"
    and .marker.processId == .crashedPid
    and .marker.confirmedCount == .businessResult.trades
    and .ambiguityWindow.pendingBeforeCrash == .businessResult.trades
    and .ambiguityWindow.sentBeforeCrash == 0
    and .ambiguityWindow.orderApplicationsBeforeCrash == .businessResult.trades
    and .ambiguityWindow.walletSettlementsBeforeCrash == .businessResult.trades
    and .ambiguityWindow.pendingAfterCrash == .businessResult.trades
    and .replay.walletDuplicateDeliveries >= .businessResult.trades
    and .businessResult.correctnessGate == "PASS"
    and .businessResult.matchOutboxPending == 0
    and .businessResult.matchOutboxSent == .businessResult.trades
    and .businessResult.matchOutboxFailed == 0
    and .businessResult.orderApplications == .businessResult.trades
    and .businessResult.walletSettlements == .businessResult.trades
    and .businessResult.missingInOrder == 0
    and .businessResult.missingInWallet == 0
    and .businessResult.orderQueueFinal.total == 0
    and .businessResult.walletQueueFinal.total == 0
    and .businessResult.dlqFinal.total == 0
    and all(.durableDebtSnapshots[].components[]; .totalCount == 0)
  ' "${POST_CONFIRM_EVIDENCE}" >/dev/null
  echo "[INFO] REL-107 outbox confirm-ambiguity gate PASS: ${POST_CONFIRM_EVIDENCE}"
}

run_generator() {
  local phase="$1"
  local output_args=()
  if [[ "${phase}" == "relay-downstream-run" ]]; then
    output_args=(--output "${OUTPUT}")
  fi
  (
    cd "${ROOT_DIR}/eap-order"
    GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon matchedE2eLoad \
      --args="--phase ${phase} --market-id ${MARKET_ID} --events ${TRADES} --timeout-seconds ${TIMEOUT_SECONDS} ${output_args[*]}"
  )
}

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true

echo "[INFO] starting RabbitMQ, Redis, and all three PostgreSQL instances"
docker compose -p eap-loadtest -f "${COMPOSE_FILE}" up -d \
  rabbitmq redis order-postgres wallet-postgres match-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-redis-loadtest
wait_for_healthy eap-order-postgres-loadtest
wait_for_healthy eap-wallet-postgres-loadtest
wait_for_healthy eap-match-postgres-loadtest

echo "[INFO] purging retained RabbitMQ messages before consumers start"
RABBIT_CONTAINER=eap-rabbitmq-loadtest bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh"
echo "[INFO] resetting isolated Match PostgreSQL and Redis runtime state"
reset_match_probe_runtime

if [[ "${BUILD_JARS}" == "true" ]]; then
  echo "[INFO] building Order, Wallet, and MatchEngine executable jars"
  for repo in eap-order eap-wallet eap-matchEngine; do
    (
      cd "${ROOT_DIR}/${repo}"
      GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar
    )
  done
else
  echo "[INFO] reusing existing executable jars"
fi

ORDER_SCHEDULING_ARGS=(--eap.scheduling.enabled=false)
if [[ "${POST_CONFIRM_CRASH_ENABLED}" == "true" ]]; then
  # REL-107 gates consume the scheduled durable-debt snapshot; keep scheduling
  # enabled while independently disabling projection and market-data work below.
  ORDER_SCHEDULING_ARGS=()
fi
start_service eap-order http://localhost:8080/eap-order/actuator/health \
  "${ORDER_SCHEDULING_ARGS[@]}" \
  --eap.order-projection.enabled=false \
  --eap.order.market-data-scheduler.enabled=false \
  --eap.rate-limit.enabled=false \
  --management.health.redis.enabled=false
start_service eap-wallet http://localhost:8081/eap-wallet/actuator/health \
  --eap.wallet.outbox-relay.enabled=false

echo "[INFO] starting MatchEngine once with relay disabled to apply current migrations"
start_match_service false
stop_pid "${LOG_DIR}/eap-matchEngine.pid"

echo "[INFO] seeding durable Match facts/deferred outbox plus legal Order/Wallet state; trades=${TRADES}"
run_generator relay-downstream-seed
echo "[INFO] projecting seeded Order events before relay activation so durable-debt gates start clean"
run_generator project

echo "[INFO] starting the real Match trade outbox relay"
if [[ "${POST_CONFIRM_CRASH_ENABLED}" == "true" ]]; then
  echo "[INFO] activating the deferred Match outbox with deterministic post-confirm crash injection"
  run_with_post_confirm_crash
else
  start_match_service true
  echo "[INFO] activating the deferred Match outbox and measuring durable downstream convergence"
  run_generator relay-downstream-run
fi

echo "[INFO] isolated result=${OUTPUT}"
jq '{
  evidenceClass,
  measurementBoundary,
  trades,
  matchRelaySentPerSecond,
  orderApplicationsPerSecond,
  walletSettlementsPerSecond,
  downstreamDurableTradesPerSecond,
  durableConvergedTradesPerSecond,
  fullGateTradesPerSecond,
  orderQueueMax,
  walletQueueMax,
  dlqMax,
  correctnessGate,
  capacityClaimAllowed
}' "${OUTPUT}"
bash "${ROOT_DIR}/scripts/load-test/render-loadtest-report.sh" "${OUTPUT}" >/dev/null
echo "[INFO] readable report=${OUTPUT%.json}-report.md"
