#!/usr/bin/env bash
set -euo pipefail

RABBIT_CONTAINER="${RABBIT_CONTAINER:-eap-rabbitmq-loadtest}"

if ! docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name >/dev/null; then
  echo "[ERROR] unable to query RabbitMQ queues from ${RABBIT_CONTAINER}" >&2
  echo "[ERROR] check that Docker is running and the RabbitMQ container is available" >&2
  exit 1
fi

current_queues=(
  "wallet.orderSubmitted.queue"
  "wallet.tradeExecuted.queue"
  "wallet.auctionBidSubmitted.queue"
  "wallet.auctionCleared.queue"
  "matchEngine.orderConfirmed.queue"
  "matchEngine.auctionBidConfirmed.queue"
  "order.orderConfirmed.queue"
  "order.orderFailed.queue"
  "order.tradeExecuted.queue"
  "order.auctionCreated.queue"
  "order.auctionCleared.queue"
  "order.dlq"
)

for queue in "${current_queues[@]}"; do
  if ! docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name | grep -Fx "${queue}" >/dev/null; then
    continue
  fi
  echo "[INFO] purging ${queue}"
  docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q purge_queue "${queue}" >/dev/null || true
done

echo "[INFO] queue state after purge"
for queue in "${current_queues[@]}"; do
  docker exec "${RABBIT_CONTAINER}" rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers \
    | awk -v queue="${queue}" '$1 == queue { print }'
done
