**[English](README.md)** | **中文**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP 是一個支援 Continuous Double Auction（連續雙向競價，CDA）與 Timed Double Auction（定時集合競價，TDA）的 production-style 電力交易後端，以 Java / Spring Boot、RabbitMQ、PostgreSQL 與 Redis Lua 實作。專案重點不是 CRUD，而是完整交易鏈路中的吞吐量、交易正確性、冪等事件處理、outbox 可靠性與監測能力。

## 最新 Benchmark 摘要

> 目前不宣稱「完整交易已達 2000 TPS」。benchmark 分開量測 HTTP 排程輸入、accepted response、RabbitMQ broker-confirmed input、isolated core operations 與 fully business-gated completed trades，避免把局部 TPS 當成完整交易容量。
>
> 現有容量與完整流程壓測數據只適用 CDA。TDA 已有功能流程，但事件合約不同，尚未完成同等的公開容量與故障復原驗證。

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| 最新雙邊混合 HTTP 工作樹回歸，2026-08-07 | `699.98 accepted orders/s` | 同窗 `346.12`；完整流程 `320.47 trades/s` | `17500/17500` HTTP accepted；`8750` 筆三服務相同交易；資產、queue、DLQ 歸零 | 15 秒、單一種子、同機下界診斷；不是已固定版本或長時間容量 |
| Sequential SELL-then-BUY 30K 上限診斷，TPS169 | SELL `1299.71`、BUY `1298.26 accepted orders/s` | BUY-triggered `922.38 trades/s`；完整兩階段 `530.43 trades/s`；等效 order convergence `1060.85 orders/s` | `30000` 筆 Match/Order/Wallet 相同 `trade_id` + 資產正確 + final drain | 測量 BUY 前已準備賣方流動性，不是雙邊混合容量 |
| Schema-v2 Full HTTP 100K，2026-08-04 | SELL `999.90`、BUY `991.35 accepted orders/s` | 賣單就緒後 `613.33 trades/s`；完整兩階段 `378.86 trades/s` | `200000/200000` HTTP accepted + `100000` 筆三服務相同 `trade_id` + 資產正確 + final drain | 該版 Wallet 固定鎖定順序修正後的可靠性證據；慢於歷史結果，也不是現行程式碼容量紀錄 |
| 歷史 Full HTTP 100K 驗證，TPS168 | SELL `999.95`、BUY `999.84 accepted orders/s` | BUY-triggered `707.43 trades/s`；完整兩階段 `410.16 trades/s` | `200000/200000` HTTP accepted + `100000` 筆三服務相同 `trade_id` + 資產正確 + final drain | 舊量測 schema 下的高資料量正確性證據；throughput 較保守，不作為目前容量 baseline |
| 舊 alternating HTTP staircase，TPS167 | `999.98 scheduled orders/s`、`999.83 accepted responses/s` | `511.85 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + 三服務相同 `trade_id` + final queue drain | 固定 `SELL, BUY` 配對，只保留作 regression 對照 |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| 歷史本機 seeded 10k E2E，TPS93 repeat | median `1,999.22 order confirmations/s` | median `833.58 completed trades/s` | 持久化資料筆數 + 舊版 completion marker gate + final queue drain | 3/3 valid runs，range `729.71-940.93`，final queues / DLQ `0`；不包含完整 HTTP admission |
| 歷史固定版本 10k E2E，TPS55 repeat | median `1,998.94 order confirmations/s` | median `582.73 completed trades/s` | 持久化資料筆數 + 舊版 completion marker gate + final queue drain | 4/5 valid runs，range `503.11-662.17`，final queues / DLQ `0`；屬於舊壓測合約 |
| TPS169 同 contract A/B | 每個 sequential phase `1300 orders/s` | BUY-triggered completion `664.26 -> 922.38 trades/s` | 前後兩輪都通過三服務 ID、資產與 drain gate | reservation cleanup 從 `30000` 次逐筆 UPDATE 降為約 `32` 次 batch；最大 backlog `14110 -> 6261`，Match-to-Wallet p95 `13.624s -> 4.478s` |

最新證據請看 [2026-08-07 現行混合流量診斷](docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md)、[Wallet 與重複容量報告](docs/benchmarks/2026-08-05-wallet-settlement-robustness.md)、[雙邊混合階梯報告](docs/benchmarks/2026-08-04-balanced-mixed-http-staircase.md)、[效能報告](docs/performance-report.md) 與 [完整 HTTP 100K 報告](docs/benchmarks/2026-08-03-full-http-100k.md)。原始工作紀錄已凍結在 [docs/archive/performance/2026-06-global-loadtest-2000-tps.md](docs/archive/performance/2026-06-global-loadtest-2000-tps.md)。

## Workload Semantics

- Benchmark 已拆成 order admission、seeded matched completion、full HTTP completion、full HTTP steady-state、full HTTP staircase 與 RabbitMQ publish-only。
- Seeded matched-completion 從已確認訂單開始；full HTTP 則包含 BUY/SELL API、Wallet reservation、matching、settlement 與最終 drain，兩者不可當成同一 workload 比較。
- 一筆 expected completed trade 需要買賣雙側處理，以及下游 Order / Wallet consumer 完成。
- `EVENTS=10000` 代表該 run 預期在 seed sell-side liquidity 後完成 `10000` 筆交易。
- Offered load 量測的是送往 match path 的 order confirmations，不等於 completed trades/s。
- 現行完整流程計時只在 MatchEngine、Order、Wallet 的持久化交易資料一致、資產核對正確，而且受測 RabbitMQ `queue`、DLQ 與持久化積壓全部清空後結束。舊合約若量測完成標記，仍只保留為歷史結果。

Business E2E TPS 公式：

```text
businessCompletedTradeTps =
  completedTrades /
  (fullLifecycleCompletedAt - runPhaseStartedAt)
```

其中 `fullLifecycleCompletedAt` 取三服務持久化資料收斂、資產核對與受測積壓清空之後的完成時間。

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

EAP 以兩種市場模式模擬電力交易。CDA 會持續接收、保留資產並逐筆撮合；TDA 則在競價時段收集階梯式出價，再於排定時間一次清算。

核心流程：

```text
Order API
  -> Order Service append command event + outbox
  -> Wallet Service reserves assets
  -> MatchEngine matches orders with Redis ZSET + Lua
  -> MatchEngine 原子持久化 TradeExecuted + outbox + 延後清理任務
  -> Order Service applies trade result
  -> Wallet Service settles trade
  -> Verify identical trade IDs, reconciled assets, and drained queues
```

完整架構請看 [docs/architecture.md](docs/architecture.md)。

TDA 已串接 Order、Wallet 與 MatchEngine，但目前 Order 的競價出價事件及 MatchEngine 的開標／清算事件直接發布到 RabbitMQ，尚未使用 transactional outbox；Wallet 出價重送冪等、驗資拒絕回授與整場競價收斂也仍有缺口。因此它是已實作但尚未完成同級可靠性驗證的功能，不能套用上方 CDA 容量宣稱。

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
| `eap-order` | 訂單與競價指令生命週期 | CDA 訂單事件流與成交套用；TDA 出價入口與結果檢視 |
| `eap-wallet` | 錢包餘額與結算 | CDA/TDA 資產保留、CDA 成交結算、TDA 競價結算與 wallet outbox |
| `eap-matchEngine` | 撮合與競價清算 | CDA Redis 訂單簿與 `TradeExecuted`；TDA 出價收集、排程與清算 |
| `eap-common` | Shared contracts | DTOs, events, shared integration contracts |
| `eap-mcp` / `eap-ai-client` | Control-plane extension | backend tools for controlled AI-agent experiments |
| `eap-trigger` | 舊版周邊實驗 | Go 條件單模組仍消費已退役的 `order.matched`，尚未接入現行主流程 |

## Reliability Model

- Message delivery: RabbitMQ at-least-once.
- Publish reliability: CDA 中需要送出整合事件的狀態轉換使用 transactional outbox；Order/Wallet 的最終成交套用不再送完成回授。TDA 現有直接發布點是已知架構缺口。
- Consumer safety: idempotency tables / unique keys / local DB transactions.
- Completion definition: a trade is business-complete only after MatchEngine has `TradeExecuted`, Order has applied the trade, Wallet has settled it, all three services contain the same `trade_id` set, assets reconcile, and measured queues drain.
- Read models: projections are rebuildable and measured as lag, not as the command-side source of truth.
- Completion feedback: Order 與 Wallet 不再發布逐筆完成回授；由交易路徑外核對三服務持久化事實。

## AI 工程協作流程

EAP 使用有明確邊界的 AI 角色，把工程問題轉成可否證的假設，而不是把架構、風險、部署或公開宣稱交給 AI。每個修改都需要基準、控制變因、實作、測試、監測證據、正確性關卡、審查與人工採用／拒絕決策；被拒絕的實驗也必須保留。

詳見 [證據驅動 AI 工程工作流](docs/ai-engineering-workflow.md) 與 [Hello World Dev Conference 2026 EAP 案例](docs/talks/hello-world-dev-conference-2026-case-study.md)。

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
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=none MIN_OFFERED_TPS_RATIO=0.95 \
REPEATS=5 bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_YYYYMMDD
```

完整 HTTP 階梯測試：

```bash
START_ORDER_TPS=700 END_ORDER_TPS=1100 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
WORKLOAD_SEED=20260804 \
bash scripts/load-test/run-http-matched-staircase.sh
```

完整 HTTP runner 固定使用雙邊混合亂序流量與各服務自己的 `loadtest` 設定。worker 數、runtime profile 與買賣 phase 順序不再是公開容量開關；需要定位單一元件時，才使用低階診斷腳本。

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## 目前驗證缺口

- MatchEngine 已將交易事件外送與撮合訂單保留維護排程分離。相同隨機種子的受控比較明顯改善 800 階段的積壓與完成量，但後續測試未證明 800 可重複通過，因此公開混合流量下界仍維持 700 orders/s。
- 撮合訂單保留修復已改用精確 `tradeId` 核對；舊清理工作不能釋放或刪除同一訂單的新保留狀態。修正後 52500 筆訂單全部收斂，三服務交易紀錄一致，最終 DLQ 與撮合訂單保留均為 0。
- Full HTTP staircase 有 HTTP latency histogram bounds，但尚未提供 per-trade end-to-end p95/p99。
- 最新 `1300 accepted orders/s` 是同機 sequential SELL/BUY phases，不是 mixed-flow 或 30 分鐘 soak claim。
- 現行安全 Wallet transaction boundary 已通過短時間 `700 total orders/s` mixed 回歸；兩次現行程式碼 900 orders/s 都能正確收斂，但無法重複通過 sustained gate。舊版三 seed 900 結果使用後來已否決的 autocommit boundary。
- 現行程式已通過 15 分鐘 700 orders/s 同機測試；仍需額外隨機種子與外部 load generator，才能視為正式環境 SLA。
- load generator、services 與 containers 同機，仍需外部分離 load generator 才能排除共享 CPU 干擾。
- `922.38 trades/s` 是預先準備賣方流動性的 sequential 上限診斷，不是雙邊混合流量容量。
- 2026-08-04 的 schema-v2 100K 已通過所有正確性驗證，但速度低於歷史 100K；後續 Wallet 改動必須重新驗證後才能調整容量 baseline。
- 原始報告屬於 ignored build artifacts；先以 `bash scripts/load-test/prune-loadtest-reports.sh` 預覽 retention，確認 result JSON 已整理到 `docs/benchmarks/results/` 後才設定 `DRY_RUN=false`。
- 歷史 seeded steady-state 不能取代 full HTTP steady-state contract。
- Benchmark result artifact 目前位於本機 `build/load-test-reports/`，仍需發布或附到 release 才能讓第三方直接驗證。
- Failure injection 應另外整理 duplicate delivery、consumer restart、outbox retry、DLQ、projection replay。

Public benchmark runbook 記錄在 [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md)。

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - 現行服務邊界、事件流程與已退役的完成回授。
2. [docs/ai-engineering-workflow.md](docs/ai-engineering-workflow.md) - 角色契約、證據關卡，以及真實採用／拒絕案例。
3. [docs/talks/hello-world-dev-conference-2026-case-study.md](docs/talks/hello-world-dev-conference-2026-case-study.md) - EAP 如何用 AI 角色完成自我審查、功能擴充與證據決策。
4. [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) - benchmark boundary definitions。
5. [docs/performance-report.md](docs/performance-report.md) - benchmark 定義、最新結果與瓶頸。
6. [docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md](docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md) - 現行工作樹 700/800 診斷與排程競爭證據。
7. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - 固定版本的公開 benchmark 計畫。
8. Service READMEs: [Order](https://github.com/Yitin-tsai/eap-order)、[Wallet](https://github.com/Yitin-tsai/eap-wallet)、[MatchEngine](https://github.com/Yitin-tsai/eap-matchEngine)、[MCP](https://github.com/Yitin-tsai/eap-mcp)、[AI Client](https://github.com/Yitin-tsai/eap-ai-client)、[Common](https://github.com/Yitin-tsai/eap-common)、[Trigger](eap-trigger/README.md)。

完整實驗歷史保留在 `docs/archive/performance/`，但不列入一般閱讀順序。
