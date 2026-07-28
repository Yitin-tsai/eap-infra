**English** | **[中文](README.zh-TW.md)**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP is a production-style electricity market backend built with Java / Spring Boot, RabbitMQ, PostgreSQL, and a Redis Lua order book. The project focuses on completed-transaction throughput, transaction correctness, idempotent event processing, reliable outbox publishing, and operational observability rather than CRUD.

## Latest Benchmark Summary

> The project does not claim 2000 completed TPS yet. The current benchmark contract separates client-side input attempts, RabbitMQ broker-confirmed input, and fully business-gated completed trades. A run is not valid for capacity comparison unless every input message is broker-confirmed and the Order / Wallet / MatchEngine durable trade ID sets are identical.
>
> The implemented 10k benchmark is a `matched-trade-completion-chain` benchmark. It starts after valid Order/Wallet state has been prepared and sends confirmed order events into MatchEngine. It is not the same as a public API order-lifecycle benchmark.

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| Current contract-v2 10k diagnostic run, TPS126 | `1,377.80 broker-confirmed input orders/s` | `1,234.47 completed trades/s` | identical `trade_id` sets across `trade_executions`, `order_trade_applications`, `trade_settlements` + final queue drain | Correctness passed, broker acks `10000/10000`, final queues / DLQ `0`, but not a valid 2000-input capacity run because broker-confirmed input did not reach the 95% offered-load threshold |
| RabbitMQ publish-only diagnostic, TPS126 | `1,994.98 broker-confirmed input orders/s` | N/A | persistent messages broker-acked, queue ready before purge matched target | Proves the load generator and RabbitMQ can confirm near-2000/s when service processing is removed; diagnostic only |
| Previous local 10k business-gated repeat, TPS93 | median `1,999.22 client-side input attempts/s` | median `833.58 completed trades/s` | count-based durable facts + legacy marker gate + final queue drain | Useful performance-improvement history, but superseded by contract-v2 broker-confirmed input semantics |
| Pinned public 10k repeat, 2026-07-13 | median `1,998.94 client-side input attempts/s` | median `582.73 completed trades/s` | count-based durable facts + legacy marker gate + final queue drain | 4/5 valid runs under the older benchmark contract |
| Current bottleneck | N/A | N/A | correctness preserved | DB write amplification and outbox relay cost in Match / Order / Wallet |

See [docs/performance-report.md](docs/performance-report.md) for the curated report. The raw engineering log is preserved in [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md).

## Workload Semantics

- EAP has three benchmark contracts:
  - `order-admission-chain` (planned): `Order API -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission`.
  - `matched-trade-completion-chain` (implemented): seeded confirmed orders enter MatchEngine, then the benchmark waits for MatchEngine, Order, and Wallet durable trade completion.
  - `public-order-lifecycle` (planned): user-facing HTTP order submission through reservation, matching, settlement, durable convergence, and queue drain.
- The current global 10k load-test is the `matched-trade-completion-chain`, not a generic mixed production workload and not a public API lifecycle benchmark.
- One expected completed trade requires matched buy/sell-side processing plus downstream Order and Wallet consumers.
- `EVENTS=10000` means the run expects `10000` completed trades after the seeded sell-side liquidity is prepared.
- Input pressure is reported in two layers:
  - `businessInputAttemptedOrderTps`: client-side publish attempts during the scheduled BUY send window.
  - `businessInputBrokerAckedOrderTps`: BUY messages confirmed by RabbitMQ publisher confirms over the full confirm window.
- Business timing ends only after MatchEngine, Order, and Wallet durable facts converge and measured RabbitMQ queues drain to zero.

Business E2E TPS formula:

```text
businessCompletedTradeTps =
  completedTrades /
  (max(durableTradeFactConvergedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

The current benchmark also reports:

- `orderbookAdmissionTps`: resting SELL confirmations admitted into Redis order book.
- `businessInputAttemptedOrderTps`: scheduled client-side BUY publish attempts/s.
- `businessInputBrokerAckedOrderTps`: RabbitMQ-confirmed BUY input/s.
- `businessCompletedTradeTps`: fully correctness-gated completed trades.
- `blendedMarketFlowTps`: total SELL+BUY order confirmations processed across the full two-phase benchmark window.

`DURATION_SECONDS=5` is the scheduled BUY publish window. It is not the completed-business timing window. In the latest TPS126 diagnostic run, the business completion window was `8.10s`, so `10000 / 8.10 ~= 1234.47 completed trades/s`.

## Benchmark Environment

| Item | Current Local Benchmark Environment |
| --- | --- |
| Machine | MacBook Pro, Apple M5, 10 cores, 16 GB RAM |
| OS | macOS 26.5.1 |
| Docker | Docker 29.5.3 |
| JDK | Temurin OpenJDK 21.0.10 |
| PostgreSQL | `postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647`, three service-owned DB containers, `pg_stat_statements` enabled |
| RabbitMQ | `rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281` |
| Redis | `redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`, append-only disabled for load-test profile |
| Load generator | runs on the same local machine as services and containers |

Official benchmark claims should cite the machine-readable snapshot generated by `scripts/load-test/collect-benchmark-snapshot.sh`, including infra, Order, Wallet, MatchEngine, and Common commits. The repository still needs a clean five-run repeat bundle on the current contract before the current `1200/s` class result can be treated as an externally reproducible public claim.

## What The System Does

EAP simulates an electricity trading market: orders enter the market, assets are reserved, orders are matched, trade facts are persisted, order state converges, wallet settlement runs, and integration events are published reliably.

Core flow:

```text
Order API
  -> Order Service append command event + outbox
  -> Wallet Service reserves assets
  -> MatchEngine matches orders with Redis ZSET + Lua
  -> MatchEngine persists TradeExecuted + outbox
  -> Order Service applies trade result
  -> Wallet Service settles trade
  -> Benchmark verifies the same trade IDs exist in MatchEngine, Order, and Wallet durable tables
```

See [docs/architecture.md](docs/architecture.md) for the full architecture overview.

## Core Engineering Problems

- Separating accepted throughput, core matching throughput, and business completed throughput.
- Preserving idempotent side effects under RabbitMQ at-least-once delivery through unique constraints, transaction boundaries, manual ACK, and DLX/DLQ.
- Using transactional outbox to avoid a successful DB commit with a lost integration event.
- Using Redis Lua to keep order book add / match / partial fill operations atomic.
- Measuring projection lag separately from command-side business completion.
- Using PostgreSQL stats, RabbitMQ queue metrics, and application timers to identify DB write amplification and outbox relay cost.

## Service Boundaries

| Service | Ownership | Primary Responsibility |
| --- | --- | --- |
| `eap-order` | Order command lifecycle | order submission, command-side event store, order trade application, query projection |
| `eap-wallet` | Wallet balance and settlement | asset reservation, settlement, idempotent wallet ledger, wallet outbox |
| `eap-matchEngine` | Matching and trade fact | Redis order book, `TradeExecuted` fact, trade outbox |
| `eap-common` | Shared contracts | DTOs, events, shared integration contracts |
| `eap-mcp` / `eap-ai-client` | Control-plane extension | backend tools for controlled AI-agent experiments |
| `eap-trigger` | Future trigger module | Go-based conditional-order trigger service |

## Reliability Model

- Message delivery: RabbitMQ at-least-once.
- Publish reliability: transactional outbox per owning service.
- Consumer safety: idempotency tables / unique keys / local DB transactions.
- Completion definition: a trade is business-complete only after MatchEngine has `TradeExecuted`, Order has applied the trade, Wallet has settled it, all three services contain the same completed `trade_id` set, and measured queues drain.
- Read models: projections are rebuildable and measured as lag, not used as the command-side source of truth.

## Reproduce Locally

```bash
make dev-env
make dev-up
make run-all
```

Build and test:

```bash
make build
make test
```

Focused load-test scripts live under [scripts/load-test/](scripts/load-test/). The 2000 TPS investigation currently uses:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=1 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=baseline MIN_OFFERED_TPS_RATIO=0.95 \
REPEATS=5 bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_YYYYMMDD
```

The direct `matched-trade-completion-chain` entrypoint is:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=1 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-matched-trade-completion-10k.sh GLT_MATCHED_TRADE_COMPLETION_10K
```

RabbitMQ input ceiling is measured separately:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
bash scripts/load-test/run-rabbitmq-publish-only-10k.sh GLT_RABBITMQ_PUBLISH_ONLY_10K
```

See [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) for the benchmark boundary definitions.

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## Current Validation Gaps

- The latest global E2E report does not yet include API p95/p99 or end-to-end p95/p99 latency.
- The latest 10k result is a short benchmark run, not a 30-minute soak claim.
- The latest contract-v2 result is a single diagnostic 10k run. It passed correctness but is not a valid 2000-input capacity comparison because broker-confirmed input reached `1377.80/s`, below the configured threshold.
- A contract-v2 five-run repeat is still needed before updating the public benchmark median/range.
- A first 15-minute steady-state attempt was rejected because the environment used an evicting development Redis. After switching to clean `noeviction` Redis, near-500 offered-load repeats produced 2 valid 450k runs with valid-sample median `487.66` fully gated completed trades/s; a third repeat exposed a 19-trade correctness miss and is the next investigation target.
- The benchmark result artifact is local under `build/load-test-reports/`; it still needs to be published or attached to a release for third-party reproduction.
- The current valid steady-state evidence is near-500 offered order confirmations/s, not a 2000 completed TPS claim, and not yet a three-run stable correctness claim.
- Failure-injection coverage should be summarized separately for duplicate delivery, consumer restart, outbox retry, DLQ, and projection replay.

The public benchmark runbook is tracked in [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md).

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - system boundaries and event flow.
2. [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) - benchmark boundary definitions.
3. [docs/performance-report.md](docs/performance-report.md) - benchmark definitions, latest results, and bottlenecks.
4. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - pinned public benchmark plan.
5. [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md) - detailed engineering log.
6. [PROJECT_STATE.md](PROJECT_STATE.md) - historical workspace status and migration notes.
7. Service READMEs: [Order](eap-order/README.md), [Wallet](eap-wallet/README.md), [MatchEngine](eap-matchEngine/README.md), [MCP](eap-mcp/README.md), [AI Client](eap-ai-client/README.md), [Common](eap-common/README.md).
