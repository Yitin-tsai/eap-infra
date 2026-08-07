**[English](README.md)** | **中文**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP 是一個 production-style 電力交易後端系統，以 Java / Spring Boot、RabbitMQ、PostgreSQL 與 Redis Lua order book 實作交易流程。專案重點不是 CRUD，而是完整交易鏈路中的 throughput、transaction correctness、idempotent event processing、outbox reliability 與 operational observability。

## 最新 Benchmark 摘要

> 目前不宣稱「完整交易已達 2000 TPS」。benchmark 分開量測 HTTP 排程輸入、accepted response、RabbitMQ broker-confirmed input、isolated core operations 與 fully business-gated completed trades，避免把局部 TPS 當成完整交易容量。

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| 現行安全版本 shuffled 雙邊混合 HTTP 下界，2026-08-06 | `699.31 accepted orders/s` | 同窗 `350.09`；完整流程 `319.97 trades/s` | `14000/14000` HTTP accepted；`7000` 筆三服務相同交易；資產、queue、DLQ 歸零 | 僅為 15 秒現行程式碼回歸；已否決 autocommit 版本的 900 orders/s 結果只保留作歷史診斷 |
| Sequential SELL-then-BUY 30K 上限診斷，TPS169 | SELL `1299.71`、BUY `1298.26 accepted orders/s` | BUY-triggered `922.38 trades/s`；完整兩階段 `530.43 trades/s`；等效 order convergence `1060.85 orders/s` | `30000` 筆 Match/Order/Wallet 相同 `trade_id` + 資產正確 + final drain | 測量 BUY 前已準備賣方流動性，不是雙邊混合容量 |
| Schema-v2 Full HTTP 100K，2026-08-04 | SELL `999.90`、BUY `991.35 accepted orders/s` | 賣單就緒後 `613.33 trades/s`；完整兩階段 `378.86 trades/s` | `200000/200000` HTTP accepted + `100000` 筆三服務相同 `trade_id` + 資產正確 + final drain | 該版 Wallet 固定鎖定順序修正後的可靠性證據；慢於歷史結果，也不是現行程式碼容量紀錄 |
| 歷史 Full HTTP 100K 驗證，TPS168 | SELL `999.95`、BUY `999.84 accepted orders/s` | BUY-triggered `707.43 trades/s`；完整兩階段 `410.16 trades/s` | `200000/200000` HTTP accepted + `100000` 筆三服務相同 `trade_id` + 資產正確 + final drain | 舊量測 schema 下的高資料量正確性證據；throughput 較保守，不作為目前容量 baseline |
| 舊 alternating HTTP staircase，TPS167 | `999.98 scheduled orders/s`、`999.83 accepted responses/s` | `511.85 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + 三服務相同 `trade_id` + final queue drain | 固定 `SELL, BUY` 配對，只保留作 regression 對照 |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| Previous local seeded 10k E2E, TPS93 repeat | median `1,999.22 order confirmations/s` | median `833.58 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + completion marker + final queue drain | 3/3 valid runs，range `729.71-940.93`，final queues / DLQ `0`；不包含完整 HTTP admission |
| Global 10k business-gated E2E, TPS55 repeat | median `1,998.94 order confirmations/s` | median `582.73 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + completion marker + final queue drain | 4/5 valid runs，range `503.11-662.17`，final queues / DLQ `0` |
| TPS169 同 contract A/B | 每個 sequential phase `1300 orders/s` | BUY-triggered completion `664.26 -> 922.38 trades/s` | 前後兩輪都通過三服務 ID、資產與 drain gate | reservation cleanup 從 `30000` 次逐筆 UPDATE 降為約 `32` 次 batch；最大 backlog `14110 -> 6261`，Match-to-Wallet p95 `13.624s -> 4.478s` |

最新證據請看 [Wallet 與重複容量報告](docs/benchmarks/2026-08-05-wallet-settlement-robustness.md)、[balanced mixed staircase report](docs/benchmarks/2026-08-04-balanced-mixed-http-staircase.md)、[docs/performance-report.md](docs/performance-report.md) 與 [full HTTP 100K report](docs/benchmarks/2026-08-03-full-http-100k.md)。原始工作紀錄已凍結在 [docs/archive/performance/2026-06-global-loadtest-2000-tps.md](docs/archive/performance/2026-06-global-loadtest-2000-tps.md)。

## Workload Semantics

- Benchmark 已拆成 order admission、seeded matched completion、full HTTP completion、full HTTP steady-state、full HTTP staircase 與 RabbitMQ publish-only。
- Seeded matched-completion 從已確認訂單開始；full HTTP 則包含 BUY/SELL API、Wallet reservation、matching、settlement 與最終 drain，兩者不可當成同一 workload 比較。
- 一筆 expected completed trade 需要買賣雙側處理，以及下游 Order / Wallet consumer 完成。
- `EVENTS=10000` 代表該 run 預期在 seed sell-side liquidity 後完成 `10000` 筆交易。
- Offered load 量測的是送往 match path 的 order confirmations，不等於 completed trades/s。
- Business timing 只在 completion markers 收斂且受測 RabbitMQ queues 全部 drain 為 0 後結束。

Business E2E TPS 公式：

```text
businessCompletedTradeTps =
  completedTrades /
  (max(completionMarkerReachedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

目前 benchmark 另外拆出三個 TPS：

- `orderbookAdmissionTps`：resting SELL confirmations 進入 Redis order book 的速度。
- `businessCompletedTradeTps`：包含 correctness gate 的完整成交 TPS。
- `blendedMarketFlowTps`：兩階段 benchmark 中 SELL+BUY order confirmations 的整體市場流量。

`DURATION_SECONDS=5` 是 seeded benchmark 的 offered-load publishing window，不是完整 business completion timing window；TPS93 repeat set 的 median completion window 是 `12.00s`，所以 `10000 / 12.00 ~= 833.58 completed trades/s`。

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

2026-07-13 public 10k repeat 是在 benchmark code/config commit `2252e54738d10683894b965c93d93bff32fd8c08` 上執行，service commits 記錄在 `build/load-test-reports/EAP_PUBLIC_10K_20260713-snapshot.json`。但 result artifact 目前仍是本機檔案，若要讓第三方完整重現，還需要 push 並發布 artifact bundle。

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

## AI 工程協作流程

EAP 使用有明確邊界的 AI 角色，把工程問題轉成可否證的假設，而不是把架構、風險、部署或公開宣稱交給 AI。每個修改都需要 baseline、控制變因、實作、測試、監測證據、correctness gate、review 與人工 adopt/reject 決策；被拒絕的實驗也必須保留。

詳見 [evidence-driven AI engineering workflow](docs/ai-engineering-workflow.md) 與 [Hello World Dev Conference 2026 EAP 案例](docs/talks/hello-world-dev-conference-2026-case-study.md)。

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

完整 HTTP 階梯測試：

```bash
START_ORDER_TPS=700 END_ORDER_TPS=1100 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
ARRIVAL_PATTERN=shuffled WORKLOAD_SEED=20260804 \
bash scripts/load-test/run-http-matched-staircase.sh
```

使用相同 seed 加上 `BENCHMARK_RUNTIME_PROFILE=production-equivalent`，可比較最佳化容量設定與正式預設執行行為。

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## 目前驗證缺口

- Full HTTP staircase 有 HTTP latency histogram bounds，但尚未提供 per-trade end-to-end p95/p99。
- 最新 `1300 accepted orders/s` 是同機 sequential SELL/BUY phases，不是 mixed-flow 或 30 分鐘 soak claim。
- 現行安全 Wallet transaction boundary 已通過短時間 `700 total orders/s` mixed 回歸；兩次現行程式碼 900 orders/s 都能正確收斂，但無法重複通過 sustained gate。舊版三 seed 900 結果使用後來已否決的 autocommit boundary。
- 現行 700 orders/s 仍需更長時間與額外 seeds，才能成為穩定容量宣稱。
- load generator、services 與 containers 同機，仍需外部分離 load generator 才能排除共享 CPU 干擾。
- `922.38 trades/s` 是預先準備賣方流動性的 sequential 上限診斷，不是雙邊混合流量容量。
- 2026-08-04 的 schema-v2 100K 已通過所有正確性驗證，但速度低於歷史 100K；後續 Wallet 改動必須重新驗證後才能調整容量 baseline。
- 原始報告屬於 ignored build artifacts；先以 `bash scripts/load-test/prune-loadtest-reports.sh` 預覽 retention，確認 result JSON 已整理到 `docs/benchmarks/results/` 後才設定 `DRY_RUN=false`。
- 歷史 seeded steady-state 不能取代 full HTTP steady-state contract。
- Benchmark result artifact 目前位於本機 `build/load-test-reports/`，仍需發布或附到 release 才能讓第三方直接驗證。
- Failure injection 應另外整理 duplicate delivery、consumer restart、outbox retry、DLQ、projection replay。

Public benchmark runbook 記錄在 [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md)。

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - 服務邊界與事件流程。
2. [docs/ai-engineering-workflow.md](docs/ai-engineering-workflow.md) - 角色契約、證據關卡，以及真實採用／拒絕案例。
3. [docs/talks/hello-world-dev-conference-2026-case-study.md](docs/talks/hello-world-dev-conference-2026-case-study.md) - EAP 如何用 AI 角色完成自我審查、功能擴充與證據決策。
4. [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) - benchmark boundary definitions。
5. [docs/performance-report.md](docs/performance-report.md) - benchmark 定義、最新結果與瓶頸。
6. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - 固定版本的公開 benchmark 計畫。
7. Service READMEs: [Order](https://github.com/Yitin-tsai/eap-order)、[Wallet](https://github.com/Yitin-tsai/eap-wallet)、[MatchEngine](https://github.com/Yitin-tsai/eap-matchEngine)、[MCP](https://github.com/Yitin-tsai/eap-mcp)、[AI Client](https://github.com/Yitin-tsai/eap-ai-client)、[Common](https://github.com/Yitin-tsai/eap-common)、[Trigger](eap-trigger/README.md)。

完整實驗歷史保留在 `docs/archive/performance/`，但不列入一般閱讀順序。
