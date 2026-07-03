#!/usr/bin/env bash
set -euo pipefail

RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq}"

if ! docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name >/dev/null; then
  echo "[ERROR] unable to query RabbitMQ queues from ${RABBIT_CONTAINER}" >&2
  echo "[ERROR] check that Docker is running and the RabbitMQ container is available" >&2
  exit 1
fi

queues="$(docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name | grep -E '^(order|wallet|matchEngine)\.|^order\.dlq$' || true)"

if [[ -z "${queues}" ]]; then
  echo "[INFO] no EAP queues found in ${RABBIT_CONTAINER}"
  exit 0
fi

while IFS= read -r queue; do
  [[ -z "${queue}" ]] && continue
  echo "[INFO] purging ${queue}"
  docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q purge_queue "${queue}" >/dev/null || true
done <<< "${queues}"

echo "[INFO] queue state after purge"
docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers \
  | grep -E '^(order|wallet|matchEngine)\.|^order\.dlq$' || true
