**English** | **[中文](README.zh-TW.md)**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP is a production-style electricity market backend built with Java / Spring Boot, RabbitMQ, PostgreSQL, and a Redis Lua order book. The project focuses on completed-transaction throughput, transaction correctness, idempotent event processing, reliable outbox publishing, and operational observability rather than CRUD.

## Latest Benchmark Summary

> The project does not claim 2000 completed TPS yet. The load generator can offer about 2000 order confirmations/s, while fully business-gated completed trades/s is still limited by database write amplification and outbox relay cost.

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| Global 10k business-gated E2E, TPS55 repeat | median `1,998.94 order confirmations/s` | median `582.73 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + completion marker + final queue drain | 4/5 valid runs, range `503.11-662.17`, final queues / DLQ `0` |
| Current bottleneck | N/A | N/A | correctness preserved | DB write amplification and outbox relay cost in Match / Order / Wallet |

See [docs/performance-report.md](docs/performance-report.md) for the curated report. The raw engineering log is preserved in [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md).

## Workload Semantics

- The current global 10k load-test is a matched-trade scenario, not a generic mixed production workload.
- One expected completed trade requires matched buy/sell-side processing plus downstream Order and Wallet consumers.
- `EVENTS=10000` means the run expects `10000` completed trades after the seeded sell-side liquidity is prepared.
- Offered load is measured as order confirmations published toward the match path; it is not the same unit as completed trades/s.
- Business timing ends only after completion markers converge and measured RabbitMQ queues drain to zero.

Business E2E TPS formula:

```text
businessMatchedE2eTps =
  completedTrades /
  (max(completionMarkerReachedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

`DURATION_SECONDS=5` is the offered-load publishing window. It is not the completed-business timing window; in the latest valid repeat set, the median completion window was `17.29s`, so `10000 / 17.29 ~= 582.73 completed trades/s`.

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

The latest 10k repeat result was run against benchmark code/config commit `2252e54738d10683894b965c93d93bff32fd8c08` with service commits recorded in `build/load-test-reports/EAP_PUBLIC_10K_20260713-snapshot.json`. The repository still needs a pushed public artifact bundle before this can be treated as externally reproducible by a third party.

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
  -> MatchEngine completion view receives Order/Wallet markers
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
| `eap-matchEngine` | Matching and trade fact | Redis order book, `TradeExecuted` fact, trade outbox, completion markers |
| `eap-common` | Shared contracts | DTOs, events, shared integration contracts |
| `eap-mcp` / `eap-ai-client` | Control-plane extension | backend tools for controlled AI-agent experiments |
| `eap-trigger` | Future trigger module | Go-based conditional-order trigger service |

## Reliability Model

- Message delivery: RabbitMQ at-least-once.
- Publish reliability: transactional outbox per owning service.
- Consumer safety: idempotency tables / unique keys / local DB transactions.
- Completion definition: a trade is business-complete only after MatchEngine has `TradeExecuted`, Order has applied the trade, Wallet has settled it, completion markers converge, and queues drain.
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
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=baseline MIN_OFFERED_TPS_RATIO=0.95 \
REPEATS=5 bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_YYYYMMDD
```

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## Current Validation Gaps

- The latest global E2E report does not yet include API p95/p99 or end-to-end p95/p99 latency.
- The latest 10k result is a short benchmark run, not a 30-minute soak claim.
- The latest 10k repeat has 4 valid public samples out of 5; one run was excluded because the local driver did not maintain the required offered TPS.
- The benchmark result artifact is local under `build/load-test-reports/`; it still needs to be published or attached to a release for third-party reproduction.
- A 10-15 minute steady-state benchmark is still pending.
- Failure-injection coverage should be summarized separately for duplicate delivery, consumer restart, outbox retry, DLQ, and projection replay.

The public benchmark runbook is tracked in [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md).

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - system boundaries and event flow.
2. [docs/performance-report.md](docs/performance-report.md) - benchmark definitions, latest results, and bottlenecks.
3. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - pinned public benchmark plan.
4. [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md) - detailed engineering log.
5. [PROJECT_STATE.md](PROJECT_STATE.md) - historical workspace status and migration notes.
6. Service READMEs: [Order](eap-order/README.md), [Wallet](eap-wallet/README.md), [MatchEngine](eap-matchEngine/README.md), [MCP](eap-mcp/README.md), [AI Client](eap-ai-client/README.md), [Common](eap-common/README.md).
