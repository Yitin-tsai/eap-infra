# EAP Load-Test Taxonomy

EAP uses multiple load-test contracts because different parts of the trading workflow answer different engineering questions. Do not compare their TPS numbers as if they were the same unit.

## Benchmark Contracts

| Contract | Status | Entry Point | What It Measures | What It Does Not Measure |
| --- | --- | --- | --- | --- |
| `order-admission-chain` | planned | TBD | `Order API -> Order event store/outbox -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission` | trade execution, Order trade application, Wallet settlement |
| `matched-trade-completion-chain` | implemented | `scripts/load-test/run-matched-trade-completion-10k.sh` | seeded confirmed orders entering MatchEngine, `TradeExecuted` persistence, Order trade application, Wallet settlement, durable trade-ID set equality, and final measured queue drain | Order HTTP API, initial order submission persistence, Wallet reservation decision cost |
| `public-order-lifecycle` | planned | TBD | user-facing HTTP order lifecycle from order submission through reservation, matching, settlement, durable convergence, and queue drain | isolated component ceilings |
| `rabbitmq-publish-only` | implemented diagnostic | `scripts/load-test/run-rabbitmq-publish-only-10k.sh` | RabbitMQ broker-confirmed input ceiling for persistent `OrderConfirmedEvent` messages | service processing, DB writes, matching, settlement |

## Current Implemented Contract

The current 10k TPS work uses `matched-trade-completion-chain`.

It prepares valid Order and Wallet state, publishes confirmed SELL orders to the MatchEngine order book, then publishes confirmed BUY orders into the same MatchEngine queue. A trade is counted only after:

- MatchEngine persisted the `TradeExecuted` fact;
- Order persisted its durable trade-application fact;
- Wallet persisted its durable settlement fact;
- the three service-owned durable trade-ID sets are identical;
- measured RabbitMQ ready/unacked queues drained to zero.

This is intentionally a backend hot-path benchmark. It is not a public API lifecycle benchmark.

## Next Benchmark Work

1. Implement `order-admission-chain` so the front half can be measured without forcing every order to trade.
2. Implement `public-order-lifecycle` so the project can report true API-to-settlement throughput separately from the segmented benchmarks.
3. Keep `rabbitmq-publish-only` as a diagnostic ceiling probe only.
4. Return to Wallet durable convergence after the benchmark contracts are separated, so Wallet work is judged with the right measurement boundary.
