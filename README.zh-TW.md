**[English](README.md)** | **中文**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP 是一個 production-style 電力交易後端系統，以 Java / Spring Boot、RabbitMQ、PostgreSQL 與 Redis Lua order book 實作交易流程。專案重點不是 CRUD，而是完整交易鏈路中的 throughput、transaction correctness、idempotent event processing、outbox reliability 與 operational observability。

## 最新 Benchmark 摘要

> 目前不宣稱「完整交易已達 2000 TPS」。壓測工具可提供約 2000 筆 order confirmations/s，但完整 business-gated completed trades/s 仍受 DB write amplification 與 outbox relay 成本限制。

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| Global 10k business-gated E2E, TPS54 | `1,998.55 order confirmations/s` | `468.76 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + completion marker + final queue drain | final queues / DLQ `0` |
| Current bottleneck | N/A | N/A | correctness preserved | DB write amplification and outbox relay cost in Match / Order / Wallet |

完整報告請看 [docs/performance-report.md](docs/performance-report.md)。原始工作紀錄保留在 [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md)。

## Workload Semantics

- 目前 global 10k 壓測是 matched-trade 場景，不是完整混合型 production workload。
- 一筆 expected completed trade 需要買賣雙側處理，以及下游 Order / Wallet consumer 完成。
- `EVENTS=10000` 代表該 run 預期在 seed sell-side liquidity 後完成 `10000` 筆交易。
- Offered load 量測的是送往 match path 的 order confirmations，不等於 completed trades/s。
- Business timing 只在 completion markers 收斂且受測 RabbitMQ queues 全部 drain 為 0 後結束。

Business E2E TPS 公式：

```text
businessMatchedE2eTps =
  completedTrades /
  (max(completionMarkerReachedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

`DURATION_SECONDS=5` 是 offered-load publishing window，不是完整 business completion timing window；例如 `10000 / 468.76 ~= 21.3s`。

## Benchmark Environment

| 項目 | 目前本機 benchmark 環境 |
| --- | --- |
| Machine | MacBook Pro, Apple M5, 10 cores, 16 GB RAM |
| OS | macOS 26.5.1 |
| Docker | Docker 29.5.3 |
| JDK | Temurin OpenJDK 21.0.10 |
| PostgreSQL | `postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647`，三個 service-owned DB containers，啟用 `pg_stat_statements` |
| RabbitMQ | `rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281` |
| Redis | `redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`，load-test profile 關閉 append-only |
| Load generator | 與服務和 containers 跑在同一台本機 |

目前數字是 documented local benchmark results。若要對外宣稱 fully reproducible，應先 commit benchmark code/config，並在該 exact commit 上重跑 benchmark。

## 系統做什麼

EAP 模擬一個電力交易市場，支援買賣單進入市場、資產保留、撮合、成交事實持久化、訂單狀態收斂、錢包結算與事件可靠發布。

核心流程：

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

完整架構請看 [docs/architecture.md](docs/architecture.md)。

## 核心工程問題

- 明確區分 accepted throughput、core matching throughput、business completed throughput。
- 在 RabbitMQ at-least-once delivery 下，用 unique constraints、transaction boundaries、manual ACK、DLX/DLQ 保護 idempotent side effects。
- 用 transactional outbox 避免 DB commit 成功但 integration event 遺失。
- 用 Redis Lua 保證 order book add / match / partial fill 的原子性。
- 將 projection lag 與 command-side business completion 分開量測，避免把 read model 延遲誤判成交易失敗。
- 用 PostgreSQL stats、RabbitMQ queue metrics、application timers 追 DB write amplification 與 outbox relay 成本。

## 服務邊界

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
- Read models: projections are rebuildable and measured as lag, not as the command-side source of truth.

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
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=deep \
bash scripts/load-test/run-2000-ticket-marker-10k.sh
```

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## 目前驗證缺口

- 最新 global E2E report 尚未提供 API p95/p99 或 end-to-end p95/p99 latency。
- 最新 10k 結果是短場景 benchmark，不是 30 分鐘 soak claim。
- 下一版公開 benchmark 應至少跑五輪，公開 median、min/max 與各 run link，而不是只放最好看的單次。
- 下一版公開 benchmark 應固定 exact Git commit 與 container image tags/digests。
- Failure injection 應另外整理 duplicate delivery、consumer restart、outbox retry、DLQ、projection replay。

Public benchmark runbook 記錄在 [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md)。

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - system boundaries and event flow.
2. [docs/performance-report.md](docs/performance-report.md) - benchmark definitions, latest results, and bottlenecks.
3. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - pinned public benchmark plan.
4. [docs/features/2026-06-global-loadtest-2000-tps.md](docs/features/2026-06-global-loadtest-2000-tps.md) - detailed engineering log.
5. [PROJECT_STATE.md](PROJECT_STATE.md) - historical workspace status and migration notes.
6. Service READMEs: [Order](eap-order/README.md), [Wallet](eap-wallet/README.md), [MatchEngine](eap-matchEngine/README.md), [MCP](eap-mcp/README.md), [AI Client](eap-ai-client/README.md), [Common](eap-common/README.md).
