#!/usr/bin/env bash
set -euo pipefail

RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq}"
REDIS_CONTAINER="${REDIS_CONTAINER:-eap-redis}"
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

require_port "RabbitMQ AMQP" 5672
require_port "Redis" 6379
require_port "Order loadtest PostgreSQL" 15432
require_port "Wallet loadtest PostgreSQL" 15433
require_port "MatchEngine loadtest PostgreSQL" 15434

require_rabbitmq_queryable
print_environment
