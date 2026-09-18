#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"
REPORT_DIR="${ROOT_DIR}/build/load-test-reports"
LOG_DIR="${TMPDIR:-/tmp}/eap-loadtest-logs"
GRADLE_USER_HOME_DIR="${ROOT_DIR}/.cache/gradle"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
POST_CONFIRM_PAUSE_MS="${POST_CONFIRM_PAUSE_MS:-120000}"
BUILD_JARS="${BUILD_JARS:-true}"
KEEP_INFRA="${KEEP_INFRA:-false}"
DELETE_TEST_DATA="${DELETE_TEST_DATA:-true}"

OPERATOR_TOKEN="rel107-operator-token"
SOURCE_TOKEN="rel107-source-token"
OPERATOR="rel107-failure-injection"
REASON="resume the same action after confirmed replay and MCP process crash"
BUYER_ID="11111111-1111-1111-1111-111111111111"
SELLER_ID="22222222-2222-2222-2222-222222222222"
TRADE_ID="REL107-MCP-${RUN_ID}"
MESSAGE_ID="rel107-mcp-${RUN_ID}"
ACTION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
SOURCE_ID="wallet.tradeExecuted.queue:${MESSAGE_ID}"

MARKER="${LOG_DIR}/mcp-replay-post-confirm-${RUN_ID}.json"
ACTION_BODY="${LOG_DIR}/mcp-replay-action-${RUN_ID}.json"
DRY_RUN_BODY="${LOG_DIR}/mcp-replay-dry-run-${RUN_ID}.json"
FIRST_RESPONSE="${LOG_DIR}/mcp-replay-first-response-${RUN_ID}.json"
RETRY_RESPONSE="${LOG_DIR}/mcp-replay-retry-response-${RUN_ID}.json"
ACTION_VIEW="${LOG_DIR}/mcp-replay-action-view-${RUN_ID}.json"
CASE_VIEW="${LOG_DIR}/mcp-replay-case-view-${RUN_ID}.json"
EVIDENCE="${REPORT_DIR}/rel107-mcp-replay-confirm-crash-${RUN_ID}.json"
FIRST_CURL_PID=""
FIRST_CURL_STATUS="not-started"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}" "${GRADLE_USER_HOME_DIR}"

if [[ ! "${RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]] || (( ${#RUN_ID} > 48 )); then
  echo "[ERROR] RUN_ID must be <= 48 characters and contain only letters, digits, dot, underscore, and dash" >&2
  exit 2
fi
if ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || (( TIMEOUT_SECONDS < 30 )); then
  echo "[ERROR] TIMEOUT_SECONDS must be an integer >= 30" >&2
  exit 2
fi
if ! [[ "${POST_CONFIRM_PAUSE_MS}" =~ ^[0-9]+$ ]] \
    || (( POST_CONFIRM_PAUSE_MS < 30000 || POST_CONFIRM_PAUSE_MS > 300000 )); then
  echo "[ERROR] POST_CONFIRM_PAUSE_MS must be between 30000 and 300000" >&2
  exit 2
fi

find_service_jar() {
  local repo="$1"
  find "${ROOT_DIR}/${repo}/build/libs" -maxdepth 1 -type f \
    -name "${repo}-*.jar" ! -name "*-plain.jar" ! -name "*-stubs.jar" \
    | sort | head -n 1
}

stop_pid() {
  local repo="$1"
  local pid_file="${LOG_DIR}/${repo}.pid"
  if [[ ! -f "${pid_file}" ]]; then
    return
  fi
  local pid
  pid="$(cat "${pid_file}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pid_file}"
}

cleanup() {
  if [[ -n "${FIRST_CURL_PID}" ]] && kill -0 "${FIRST_CURL_PID}" >/dev/null 2>&1; then
    kill "${FIRST_CURL_PID}" >/dev/null 2>&1 || true
    wait "${FIRST_CURL_PID}" >/dev/null 2>&1 || true
  fi
  stop_pid eap-mcp
  stop_pid eap-wallet
  if [[ "${KEEP_INFRA}" != "true" ]]; then
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" stop \
      mcp-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" rm -f \
      mcp-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
    if [[ "${DELETE_TEST_DATA}" == "true" ]]; then
      docker volume rm \
        eap-loadtest_mcp-pgdata-loadtest \
        eap-loadtest_wallet-pgdata-loadtest \
        eap-loadtest_rabbitmq-data-loadtest >/dev/null 2>&1 || true
    fi
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

wait_http() {
  local repo="$1"
  local url="$2"
  local deadline=$(( $(date +%s) + 120 ))
  local pid_file="${LOG_DIR}/${repo}.pid"
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "$(cat "${pid_file}")" >/dev/null 2>&1; then
      echo "[ERROR] ${repo} did not become ready: ${url}" >&2
      tail -n 160 "${LOG_DIR}/${repo}.log" >&2 || true
      exit 1
    fi
    sleep 1
  done
}

start_wallet() {
  local listener_enabled="$1"
  stop_pid eap-wallet
  local jar
  jar="$(find_service_jar eap-wallet)"
  local args=(
    --spring.profiles.active=loadtest
    --eap.recovery-source.enabled=true
    --eap.recovery-source.token="${SOURCE_TOKEN}"
    --eap.wallet.outbox-relay.enabled=false
    --logging.level.org.springframework.amqp.rabbit.listener=WARN
  )
  if [[ "${listener_enabled}" != "true" ]]; then
    args+=(
      --spring.rabbitmq.listener.simple.auto-startup=false
      --eap.wallet.inbox-reconciler.initial-delay-ms=600000
    )
  else
    args+=(--eap.wallet.inbox-reconciler.initial-delay-ms=100)
  fi
  java -jar "${jar}" "${args[@]}" >"${LOG_DIR}/eap-wallet.log" 2>&1 &
  echo "$!" >"${LOG_DIR}/eap-wallet.pid"
  wait_http eap-wallet http://localhost:8081/eap-wallet/actuator/health
}

start_mcp() {
  local probe_enabled="$1"
  stop_pid eap-mcp
  local jar
  jar="$(find_service_jar eap-mcp)"
  local args=(
    --spring.profiles.active=loadtest
    --spring.datasource.url=jdbc:postgresql://localhost:15435/eap_mcp_db
    --spring.datasource.username=admin
    --spring.datasource.password=admin123
    --spring.liquibase.enabled=true
    --spring.ai.mcp.server.enabled=false
    --eap.recovery-control.enabled=true
    --eap.recovery-control.operator-token="${OPERATOR_TOKEN}"
    --eap.recovery-control.source-token="${SOURCE_TOKEN}"
    --eap.recovery-control.broker-dlq.enabled=true
    --eap.wallet.base-url=http://localhost:8081/eap-wallet
    --logging.level.org.springframework.ai=ERROR
    --logging.level.io.modelcontextprotocol=ERROR
  )
  if [[ "${probe_enabled}" == "true" ]]; then
    args+=(
      --eap.recovery-control.broker-dlq.failure-injection.post-confirm-pause-enabled=true
      --eap.recovery-control.broker-dlq.failure-injection.post-confirm-pause-ms="${POST_CONFIRM_PAUSE_MS}"
      --eap.recovery-control.broker-dlq.failure-injection.marker-path="${MARKER}"
    )
  fi
  java -jar "${jar}" "${args[@]}" >"${LOG_DIR}/eap-mcp.log" 2>&1 &
  echo "$!" >"${LOG_DIR}/eap-mcp.pid"
  wait_http eap-mcp http://localhost:8083/actuator/health
}

mcp_query() {
  docker exec eap-mcp-postgres-loadtest \
    psql -U admin -d eap_mcp_db -Atqc "$1"
}

wallet_query() {
  docker exec eap-wallet-postgres-loadtest \
    psql -U admin -d eap_wallet_db -Atqc "$1"
}

queue_stat() {
  local queue="$1"
  local column="$2"
  docker exec eap-rabbitmq-loadtest rabbitmqctl -q \
    list_queues name messages_ready messages_unacknowledged messages \
    | awk -v queue="${queue}" -v column="${column}" \
      '$1 == queue {if (column == "ready") print $2; else if (column == "unacked") print $3; else print $4}'
}

wait_for_broker_case() {
  local deadline=$(( $(date +%s) + 60 ))
  while [[ $(date +%s) -lt ${deadline} ]]; do
    local row
    row="$(mcp_query "
      SELECT case_id || '|' || fingerprint || '|' || source_id || '|' ||
             COALESCE(source_queue, '') || '|' || COALESCE(original_exchange, '') || '|' ||
             COALESCE(original_routing_key, '')
      FROM recovery_control.broker_dead_letters
      WHERE message_id = '${MESSAGE_ID}'" 2>/dev/null || true)"
    if [[ -n "${row}" ]]; then
      printf '%s\n' "${row}"
      return
    fi
    sleep 1
  done
  echo "[ERROR] MCP did not capture the seeded dead letter" >&2
  exit 1
}

wait_for_marker() {
  local mcp_pid="$1"
  local deadline=$(( $(date +%s) + 90 ))
  until [[ -s "${MARKER}" ]]; do
    if [[ $(date +%s) -ge ${deadline} ]] || ! kill -0 "${mcp_pid}" >/dev/null 2>&1; then
      echo "[ERROR] MCP did not enter the replay confirm/local audit ambiguity window" >&2
      tail -n 180 "${LOG_DIR}/eap-mcp.log" >&2 || true
      exit 1
    fi
    sleep 1
  done
}

wait_for_wallet_completion() {
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
  while [[ $(date +%s) -lt ${deadline} ]]; do
    local inbox settlement ready
    inbox="$(wallet_query "SELECT COUNT(*) FROM wallet_service.message_inbox WHERE message_type = 'TRADE_EXECUTED' AND message_id = '${TRADE_ID}' AND status = 'APPLIED'")"
    settlement="$(wallet_query "SELECT COUNT(*) FROM wallet_service.trade_settlements WHERE trade_id = '${TRADE_ID}'")"
    ready="$(queue_stat wallet.tradeExecuted.queue total)"
    if [[ "${inbox}" == "1" && "${settlement}" == "1" && "${ready:-0}" == "0" ]]; then
      return
    fi
    sleep 1
  done
  echo "[ERROR] Wallet did not converge after duplicate broker delivery" >&2
  exit 1
}

"${ROOT_DIR}/scripts/load-test/stop-loadtest-services.sh" >/dev/null 2>&1 || true
rm -f "${MARKER}" "${MARKER}.tmp" "${FIRST_RESPONSE}" "${RETRY_RESPONSE}" \
  "${ACTION_VIEW}" "${CASE_VIEW}" "${EVIDENCE}"

if [[ "${DELETE_TEST_DATA}" == "true" ]]; then
  echo "[INFO] resetting only Rabbit, Wallet, and MCP REL-107 load-test resources"
  docker compose -p eap-loadtest -f "${COMPOSE_FILE}" stop \
    mcp-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
  docker compose -p eap-loadtest -f "${COMPOSE_FILE}" rm -f \
    mcp-postgres wallet-postgres rabbitmq >/dev/null 2>&1 || true
  docker volume rm \
    eap-loadtest_mcp-pgdata-loadtest \
    eap-loadtest_wallet-pgdata-loadtest \
    eap-loadtest_rabbitmq-data-loadtest >/dev/null 2>&1 || true
fi

echo "[INFO] starting isolated RabbitMQ, Wallet PostgreSQL, and MCP PostgreSQL"
docker compose -p eap-loadtest -f "${COMPOSE_FILE}" up -d \
  rabbitmq wallet-postgres mcp-postgres
wait_for_healthy eap-rabbitmq-loadtest
wait_for_healthy eap-wallet-postgres-loadtest
wait_for_healthy eap-mcp-postgres-loadtest

if [[ "${BUILD_JARS}" == "true" ]]; then
  echo "[INFO] building Wallet and MCP executable jars"
  for repo in eap-wallet eap-mcp; do
    (
      cd "${ROOT_DIR}/${repo}"
      GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon bootJar testClasses
    )
  done
fi

echo "[INFO] starting Wallet with Rabbit listeners intentionally disabled"
start_wallet false
RABBIT_CONTAINER=eap-rabbitmq-loadtest \
  bash "${ROOT_DIR}/scripts/load-test/purge-eap-queues.sh" >/dev/null

wallet_query "
  DELETE FROM wallet_service.message_inbox WHERE message_id = '${TRADE_ID}';
  DELETE FROM wallet_service.trade_settlements WHERE trade_id = '${TRADE_ID}';
  DELETE FROM wallet_service.wallets WHERE user_id IN ('${BUYER_ID}', '${SELLER_ID}');
  INSERT INTO wallet_service.wallets
      (user_id, available_amount, locked_amount, available_currency,
       locked_currency, version, update_time)
  VALUES
      ('${BUYER_ID}', 0, 0, 0, 600, 0, CURRENT_TIMESTAMP),
      ('${SELLER_ID}', 0, 5, 0, 0, 0, CURRENT_TIMESTAMP);"

echo "[INFO] starting MCP with the loadtest-only post-confirm pause"
start_mcp true

echo "[INFO] publishing one deterministic captured-DLQ fixture"
(
  cd "${ROOT_DIR}/eap-mcp"
  GRADLE_USER_HOME="${GRADLE_USER_HOME_DIR}" ./gradlew --no-daemon brokerDeadLetterSeed \
    --args="--message-id ${MESSAGE_ID} --trade-id ${TRADE_ID}"
) >"${LOG_DIR}/mcp-dead-letter-seed-${RUN_ID}.log"

CASE_ROW="$(wait_for_broker_case)"
IFS='|' read -r CASE_ID FINGERPRINT CAPTURED_SOURCE_ID CAPTURED_QUEUE \
  CAPTURED_EXCHANGE CAPTURED_ROUTING_KEY <<<"${CASE_ROW}"
if [[ "${CAPTURED_SOURCE_ID}" != "${SOURCE_ID}" \
    || "${CAPTURED_QUEUE}" != "wallet.tradeExecuted.queue" \
    || "${CAPTURED_EXCHANGE}" != "trade.exchange" \
    || "${CAPTURED_ROUTING_KEY}" != "trade.executed" ]]; then
  echo "[ERROR] captured fixture lost the expected broker-owned route metadata: ${CASE_ROW}" >&2
  exit 1
fi

jq -n --arg fingerprint "${FINGERPRINT}" \
  '{action:"REPLAY",expectedFingerprint:$fingerprint}' >"${DRY_RUN_BODY}"
curl -fsS -X POST \
  -H "${OPERATOR_TOKEN:+X-EAP-Recovery-Operator-Token: ${OPERATOR_TOKEN}}" \
  -H 'Content-Type: application/json' \
  --data-binary "@${DRY_RUN_BODY}" \
  "http://localhost:8083/internal/recovery/v1/cases/${CASE_ID}/dry-run" \
  >"${DRY_RUN_BODY}.response"
jq -e '.allowed == true and .action == "REPLAY"' "${DRY_RUN_BODY}.response" >/dev/null

jq -n \
  --arg actionId "${ACTION_ID}" \
  --arg fingerprint "${FINGERPRINT}" \
  --arg reason "${REASON}" \
  '{actionId:$actionId,action:"REPLAY",expectedFingerprint:$fingerprint,reason:$reason}' \
  >"${ACTION_BODY}"

echo "[INFO] executing replay; request should be interrupted by the intentional MCP SIGKILL"
set +e
curl -sS --max-time 300 -X POST \
  -H "X-EAP-Recovery-Operator-Token: ${OPERATOR_TOKEN}" \
  -H "X-EAP-Operator: ${OPERATOR}" \
  -H 'Content-Type: application/json' \
  --data-binary "@${ACTION_BODY}" \
  "http://localhost:8083/internal/recovery/v1/cases/${CASE_ID}/actions" \
  >"${FIRST_RESPONSE}" 2>"${FIRST_RESPONSE}.error" &
FIRST_CURL_PID="$!"
set -e

MCP_PID="$(cat "${LOG_DIR}/eap-mcp.pid")"
wait_for_marker "${MCP_PID}"

MARKER_PID="$(jq -r '.processId' "${MARKER}")"
MARKER_ACTION="$(jq -r '.actionId' "${MARKER}")"
MARKER_CASE="$(jq -r '.caseId' "${MARKER}")"
if [[ "${MARKER_PID}" != "${MCP_PID}" || "${MARKER_ACTION}" != "${ACTION_ID}" \
    || "${MARKER_CASE}" != "${CASE_ID}" ]]; then
  echo "[ERROR] post-confirm marker identity does not match the target process/action/case" >&2
  exit 1
fi

PRE_ACTION="$(mcp_query "SELECT status || '|' || attempt_count || '|' || (result_json IS NOT NULL)::text FROM recovery_control.recovery_actions WHERE action_id = '${ACTION_ID}'")"
PRE_CASE="$(mcp_query "SELECT disposition FROM recovery_control.recovery_cases WHERE case_id = '${CASE_ID}'")"
PRE_QUEUE_READY="$(queue_stat wallet.tradeExecuted.queue ready)"
if [[ "${PRE_ACTION}" != "STARTED|1|false" || "${PRE_CASE}" != "OPEN" \
    || "${PRE_QUEUE_READY}" != "1" ]]; then
  echo "[ERROR] pre-crash gate failed: action=${PRE_ACTION}, case=${PRE_CASE}, walletReady=${PRE_QUEUE_READY}" >&2
  exit 1
fi

PROCESS_ARGS="$(ps -p "${MCP_PID}" -o args= 2>/dev/null || true)"
if [[ "${PROCESS_ARGS}" != *"eap-mcp"* \
    || "${PROCESS_ARGS}" != *"post-confirm-pause-enabled=true"* ]]; then
  echo "[ERROR] refusing to SIGKILL unexpected process: pid=${MCP_PID}, args=${PROCESS_ARGS}" >&2
  exit 1
fi

echo "[INFO] Rabbit confirmed one owner-queue delivery while central audit is STARTED; SIGKILL MCP pid=${MCP_PID}"
kill -KILL "${MCP_PID}"
wait "${MCP_PID}" >/dev/null 2>&1 || true
rm -f "${LOG_DIR}/eap-mcp.pid"
if kill -0 "${MCP_PID}" >/dev/null 2>&1; then
  echo "[ERROR] MCP survived SIGKILL" >&2
  exit 1
fi
set +e
wait "${FIRST_CURL_PID}"
FIRST_CURL_STATUS="$?"
set -e
FIRST_CURL_PID=""

POST_CRASH_ACTION="$(mcp_query "SELECT status || '|' || attempt_count || '|' || (result_json IS NOT NULL)::text FROM recovery_control.recovery_actions WHERE action_id = '${ACTION_ID}'")"
POST_CRASH_CASE="$(mcp_query "SELECT disposition FROM recovery_control.recovery_cases WHERE case_id = '${CASE_ID}'")"
if [[ "${POST_CRASH_ACTION}" != "STARTED|1|false" || "${POST_CRASH_CASE}" != "OPEN" ]]; then
  echo "[ERROR] crash window was not durable: action=${POST_CRASH_ACTION}, case=${POST_CRASH_CASE}" >&2
  exit 1
fi

echo "[INFO] restarting MCP without failure injection and retrying the exact same actionId"
start_mcp false
curl -fsS -X POST \
  -H "X-EAP-Recovery-Operator-Token: ${OPERATOR_TOKEN}" \
  -H "X-EAP-Operator: ${OPERATOR}" \
  -H 'Content-Type: application/json' \
  --data-binary "@${ACTION_BODY}" \
  "http://localhost:8083/internal/recovery/v1/cases/${CASE_ID}/actions" \
  >"${RETRY_RESPONSE}"

QUEUE_BEFORE_WALLET_RESTART="$(queue_stat wallet.tradeExecuted.queue ready)"
curl -fsS \
  -H "X-EAP-Recovery-Operator-Token: ${OPERATOR_TOKEN}" \
  "http://localhost:8083/internal/recovery/v1/actions/${ACTION_ID}" >"${ACTION_VIEW}"
curl -fsS \
  -H "X-EAP-Recovery-Operator-Token: ${OPERATOR_TOKEN}" \
  "http://localhost:8083/internal/recovery/v1/cases/${CASE_ID}" >"${CASE_VIEW}"

if [[ "${QUEUE_BEFORE_WALLET_RESTART}" != "2" ]]; then
  echo "[ERROR] expected two at-least-once deliveries before Wallet intake, got ${QUEUE_BEFORE_WALLET_RESTART}" >&2
  exit 1
fi
jq -e '.status == "APPLIED"' "${RETRY_RESPONSE}" >/dev/null
jq -e '.status == "APPLIED" and .attemptCount == 2 and .result.status == "APPLIED"' \
  "${ACTION_VIEW}" >/dev/null
jq -e '.disposition == "RESOLVED"' "${CASE_VIEW}" >/dev/null

echo "[INFO] restarting Wallet with consumers enabled; duplicate delivery must converge exactly once"
start_wallet true
wait_for_wallet_completion

WALLET_INBOX_ROWS="$(wallet_query "SELECT COUNT(*) FROM wallet_service.message_inbox WHERE message_type = 'TRADE_EXECUTED' AND message_id = '${TRADE_ID}'")"
WALLET_INBOX_STATUS="$(wallet_query "SELECT status FROM wallet_service.message_inbox WHERE message_type = 'TRADE_EXECUTED' AND message_id = '${TRADE_ID}'")"
WALLET_SETTLEMENT_ROWS="$(wallet_query "SELECT COUNT(*) FROM wallet_service.trade_settlements WHERE trade_id = '${TRADE_ID}'")"
BUYER_BALANCE="$(wallet_query "SELECT available_amount || '|' || locked_amount || '|' || available_currency || '|' || locked_currency FROM wallet_service.wallets WHERE user_id = '${BUYER_ID}'")"
SELLER_BALANCE="$(wallet_query "SELECT available_amount || '|' || locked_amount || '|' || available_currency || '|' || locked_currency FROM wallet_service.wallets WHERE user_id = '${SELLER_ID}'")"
WALLET_DUPLICATES="$(curl -fsS http://localhost:8081/eap-wallet/actuator/prometheus \
  | awk '$1 ~ /^eap_wallet_trade_inbox_duplicate_total($|\{)/ {total += $2} END {print total + 0}')"
FINAL_WALLET_QUEUE="$(queue_stat wallet.tradeExecuted.queue total)"
FINAL_DLQ="$(queue_stat order.dlq total)"
BROKER_CASE_ROWS="$(mcp_query "SELECT COUNT(*) FROM recovery_control.broker_dead_letters WHERE case_id = '${CASE_ID}'")"

jq -n \
  --arg runId "${RUN_ID}" \
  --arg tradeId "${TRADE_ID}" \
  --arg messageId "${MESSAGE_ID}" \
  --arg actionId "${ACTION_ID}" \
  --arg caseId "${CASE_ID}" \
  --argjson crashedPid "${MCP_PID}" \
  --arg firstCurlStatus "${FIRST_CURL_STATUS}" \
  --arg preAction "${PRE_ACTION}" \
  --arg preCase "${PRE_CASE}" \
  --argjson preQueueReady "${PRE_QUEUE_READY}" \
  --arg postCrashAction "${POST_CRASH_ACTION}" \
  --arg postCrashCase "${POST_CRASH_CASE}" \
  --argjson queueBeforeWalletRestart "${QUEUE_BEFORE_WALLET_RESTART}" \
  --argjson marker "$(cat "${MARKER}")" \
  --argjson dryRun "$(cat "${DRY_RUN_BODY}.response")" \
  --argjson retryResponse "$(cat "${RETRY_RESPONSE}")" \
  --argjson actionView "$(cat "${ACTION_VIEW}")" \
  --argjson caseView "$(cat "${CASE_VIEW}")" \
  --argjson inboxRows "${WALLET_INBOX_ROWS}" \
  --arg inboxStatus "${WALLET_INBOX_STATUS}" \
  --argjson settlementRows "${WALLET_SETTLEMENT_ROWS}" \
  --arg buyerBalance "${BUYER_BALANCE}" \
  --arg sellerBalance "${SELLER_BALANCE}" \
  --argjson duplicateDeliveries "${WALLET_DUPLICATES}" \
  --argjson finalWalletQueue "${FINAL_WALLET_QUEUE:-0}" \
  --argjson finalDlq "${FINAL_DLQ:-0}" \
  --argjson brokerCaseRows "${BROKER_CASE_ROWS}" \
  '{schemaVersion:1,contract:"rel107-mcp-replay-confirm-audit-crash",runId:$runId,
    identity:{tradeId:$tradeId,messageId:$messageId,actionId:$actionId,caseId:$caseId},
    crash:{signal:"SIGKILL",processId:$crashedPid,firstHttpExitStatus:$firstCurlStatus,marker:$marker},
    preCrash:{action:$preAction,caseDisposition:$preCase,ownerQueueReady:$preQueueReady},
    postCrash:{action:$postCrashAction,caseDisposition:$postCrashCase},
    retry:{ownerQueueReadyBeforeWalletRestart:$queueBeforeWalletRestart,response:$retryResponse,
      actionAudit:$actionView,caseAudit:$caseView},
    ownerConvergence:{inboxRows:$inboxRows,inboxStatus:$inboxStatus,
      settlementRows:$settlementRows,buyerBalance:$buyerBalance,sellerBalance:$sellerBalance,
      duplicateDeliveries:$duplicateDeliveries,finalWalletQueue:$finalWalletQueue,finalDlq:$finalDlq},
    sourceEvidence:{dryRun:$dryRun,brokerCaseRows:$brokerCaseRows}}' >"${EVIDENCE}"

jq -e '
  .crash.signal == "SIGKILL"
  and .crash.marker.processId == .crash.processId
  and .crash.marker.actionId == .identity.actionId
  and .crash.marker.caseId == .identity.caseId
  and .crash.marker.ownerQueue == "wallet.tradeExecuted.queue"
  and .preCrash.action == "STARTED|1|false"
  and .preCrash.caseDisposition == "OPEN"
  and .preCrash.ownerQueueReady == 1
  and .postCrash.action == "STARTED|1|false"
  and .postCrash.caseDisposition == "OPEN"
  and .retry.ownerQueueReadyBeforeWalletRestart == 2
  and .retry.response.status == "APPLIED"
  and .retry.actionAudit.status == "APPLIED"
  and .retry.actionAudit.attemptCount == 2
  and .retry.caseAudit.disposition == "RESOLVED"
  and .ownerConvergence.inboxRows == 1
  and .ownerConvergence.inboxStatus == "APPLIED"
  and .ownerConvergence.settlementRows == 1
  and .ownerConvergence.buyerBalance == "5|0|50|0"
  and .ownerConvergence.sellerBalance == "0|0|550|0"
  and .ownerConvergence.duplicateDeliveries >= 1
  and .ownerConvergence.finalWalletQueue == 0
  and .ownerConvergence.finalDlq == 0
  and .sourceEvidence.dryRun.allowed == true
  and .sourceEvidence.brokerCaseRows == 1
' "${EVIDENCE}" >/dev/null

echo "[PASS] REL-107 MCP replay confirm/audit crash evidence: ${EVIDENCE}"
