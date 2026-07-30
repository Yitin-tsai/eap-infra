#!/usr/bin/env bash
set -euo pipefail

RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"
REDIS_CONTAINER="${REDIS_CONTAINER:-eap-redis-loadtest}"
REDIS_MIN_MAXMEMORY_BYTES="${REDIS_MIN_MAXMEMORY_BYTES:-1073741824}"
ORDER_DB_CONTAINER="${ORDER_DB_CONTAINER:-eap-order-postgres-loadtest}"
WALLET_DB_CONTAINER="${WALLET_DB_CONTAINER:-eap-wallet-postgres-loadtest}"
MATCH_DB_CONTAINER="${MATCH_DB_CONTAINER:-eap-match-postgres-loadtest}"

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker daemon is not available." >&2
    echo "[ERROR] Start Docker Desktop and rerun the load test." >&2
    exit 1
  fi
}

container_status() {
  local container="$1"
  docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null || true
}

container_health() {
  local container="$1"
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}" 2>/dev/null || true
}

require_container_running() {
  local container="$1"
  local status
  status="$(container_status "${container}")"
  if [[ "${status}" != "running" ]]; then
    echo "[ERROR] ${container} is not running; status=${status:-missing}" >&2
    exit 1
  fi
}

require_container_healthy() {
  local container="$1"
  local health
  require_container_running "${container}"
  health="$(container_health "${container}")"
  if [[ "${health}" != "healthy" && "${health}" != "none" ]]; then
    echo "[ERROR] ${container} is not healthy; health=${health}" >&2
    exit 1
  fi
}

require_port() {
  local name="$1"
  local port="$2"
  if ! nc -z localhost "${port}" >/dev/null 2>&1; then
    echo "[ERROR] ${name} is not reachable on localhost:${port}" >&2
    exit 1
  fi
}

require_rabbitmq_queryable() {
  if ! docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name >/dev/null; then
    echo "[ERROR] RabbitMQ is running but cannot be queried from ${RABBIT_CONTAINER}" >&2
    exit 1
  fi
}

redis_config_value() {
  local name="$1"
  docker exec "${REDIS_CONTAINER}" redis-cli --raw CONFIG GET "${name}" | awk 'NR == 2 { print }'
}

redis_info_value() {
  local section="$1"
  local name="$2"
  docker exec "${REDIS_CONTAINER}" redis-cli --raw INFO "${section}" \
    | awk -F: -v key="${name}" '$1 == key { gsub(/\r/, "", $2); print $2 }'
}

require_redis_loadtest_safety() {
  local policy
  local maxmemory
  local evicted_keys
  policy="$(redis_config_value maxmemory-policy)"
  maxmemory="$(redis_config_value maxmemory)"
  evicted_keys="$(redis_info_value stats evicted_keys)"

  if [[ "${policy}" != "noeviction" ]]; then
    echo "[ERROR] Redis ${REDIS_CONTAINER} uses maxmemory-policy=${policy}; load tests require noeviction." >&2
    echo "[ERROR] Evicting order detail keys corrupts the Redis order book and can produce false no-match results." >&2
    echo "[ERROR] Start the load-test Redis from docker-compose.loadtest.yml or set REDIS_CONTAINER to the correct container." >&2
    exit 1
  fi

  if [[ "${maxmemory}" != "0" && "${maxmemory}" -lt "${REDIS_MIN_MAXMEMORY_BYTES}" ]]; then
    echo "[ERROR] Redis ${REDIS_CONTAINER} maxmemory=${maxmemory}; load tests require 0 or at least ${REDIS_MIN_MAXMEMORY_BYTES} bytes." >&2
    echo "[ERROR] The 450k steady-state scenario needs substantially more than the development 200MB Redis limit." >&2
    exit 1
  fi

  if [[ "${evicted_keys:-0}" -gt 0 ]]; then
    echo "[ERROR] Redis ${REDIS_CONTAINER} has evicted_keys=${evicted_keys}; this environment is already polluted for correctness benchmarks." >&2
    echo "[ERROR] Restart Redis with noeviction and rerun from a clean state." >&2
    exit 1
  fi
}

print_environment() {
  echo "[INFO] loadtest infrastructure"
  docker ps --format '  {{.Names}} {{.Status}}' \
    | grep -E "(${RABBIT_CONTAINER}|${REDIS_CONTAINER}|${ORDER_DB_CONTAINER}|${WALLET_DB_CONTAINER}|${MATCH_DB_CONTAINER})" || true
}

require_docker

require_container_healthy "${RABBIT_CONTAINER}"
require_container_healthy "${REDIS_CONTAINER}"
require_container_healthy "${ORDER_DB_CONTAINER}"
require_container_healthy "${WALLET_DB_CONTAINER}"
require_container_healthy "${MATCH_DB_CONTAINER}"
require_redis_loadtest_safety

require_port "RabbitMQ AMQP" 5672
require_port "Redis" 6379
require_port "Order loadtest PostgreSQL" 15432
require_port "Wallet loadtest PostgreSQL" 15433
require_port "MatchEngine loadtest PostgreSQL" 15434

require_rabbitmq_queryable
print_environment
