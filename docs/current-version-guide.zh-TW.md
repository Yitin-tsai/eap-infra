# EAP 最新版本導覽

> 更新日期：2026-09-17

> 定位：這是本次可靠性大改版的閱讀入口；細節仍以連結的架構、生命週期與實作文件為準。

## 先記住這個版本改了什麼

1. **事件語意變清楚。** Wallet 驗資成功後發布的跨服務事實從語意模糊的 `OrderConfirmedEvent` 改成 `OrderAssetReservationSucceededEvent`。它同時讓 Order 更新 reservation 狀態，也讓 MatchEngine 知道訂單具備 admission 資格。
2. **三個 bounded context 都擁有自己的可靠接收狀態。** Wallet 先 durable intake 下單、成交與取消結果；Order durable intake 驗資結果、真正缺 prerequisite 的成交、取消結果與資產釋放；MatchEngine durable intake 可進訂單簿的訂單。ACK 代表服務已接管工作，不代表業務已完成。
3. **Order 把兩種狀態拆開。** `status` 表示執行生命週期，`assetReservationStatus` 表示 Wallet reservation 進度。`TradeExecutedEvent` 若先到，可以證明 reservation 曾成功並直接推進成交，晚到的成功事件不能把 `MATCHED` 降回 `OPEN`。
4. **取消訂單有真正的完成語意。** MatchEngine 取得未成交剩餘量後，Order 只進入 `CANCELLING`；Wallet 實際釋放資產並發布 `OrderAssetReservationReleasedEvent`，Order 才進入 `CANCELLED`。
5. **CQRS projection 被納入使用者可見正確性。** Command-side 成交不等待 read model，但壓測最後必須驗證 `orders_current` 數量、reservation／execution 狀態與 checkpoint lag。
6. **壓測不再只看 RabbitMQ。** schema v4 從三服務的同一份 `DurableDebtSnapshot` 讀取 inbox、outbox、cleanup、cancellation、reconciliation 與 projection 的 total／retry／terminal／oldest age；Rabbit queue 歸零但任一 service-owned work 未完成，或 snapshot stale／不可讀，都會 fail closed。2026-09-04 的 200 orders/s 長窗仍是 schema v3 的歷史容量證據；schema v4 已通過短全鏈 correctness smoke，但尚未用來更新容量數字。
7. **Match 本地 recovery 不再用無上限 retry 掩蓋 poison state。** Cancellation prerequisite 與 technical attempt 分開；reservation invalid payload／ownership conflict 有 durable terminal issue；cleanup lease 使用 owner＋claim token fencing。
8. **Durable debt 有統一的可觀測契約。** 各服務每 5 秒用獨立 scheduler 查一次本地權威 table；Actuator 與 Prometheus 只讀記憶體 snapshot。觀測失敗會保留上次值，但同時標記失敗與 stale，不能把舊的 0 誤判成完成。
9. **Inbox commit 前的 DB outage 不再把合法事件灌進 DLQ。** Order、Wallet、MatchEngine 的 CDA consumer 會把 connectivity failure 與 poison 分開；DB outage 經短期 retry 後開啟 service-local circuit、停止自己的 listener，讓未 ACK 訊息留在 durable source queue，再用單一 backoff＋jitter probe 確認 DB 恢復並分批啟動 listener。
10. **Order Saga 卡住不再只能靠人工猜。** warning-only detector 依 effective lifecycle state 與 stream-head progress time 找出長時間停在 `PENDING_ASSET_CHECK`／`CANCELLING` 的訂單，提供 bounded Actuator 明細、低基數 metrics 與 fail-closed 告警；它刻意不自動取消或釋放資產。

## 現行能力與誠實邊界

| 面向 | 現在可以說 | 仍不能說 |
| --- | --- | --- |
| 一致性 | local transaction＋outbox＋at-least-once＋idempotency＋durable inbox，使 duplicate、worker crash 與部分亂序可恢復 | exactly-once messaging、跨服務 ACID transaction |
| Saga | CDA choreography、取消 remainder compensation、多段 retry、inbox commit 前 DB outage 自動恢復，以及 Order warning-only timeout detection 已實作 | 跨服務 timeout 自動判斷補償、DLQ／terminal debt 自動修復 |
| CQRS | Order event store 是事實來源；`orders_current` 可重建並為查詢塑形；API 回傳 execution／reservation 雙狀態 | 強 read-your-write、獨立 read replica 已完成 |
| 撮合 | Redis Lua 維持單一 market 內的撮合／取消互斥，PostgreSQL 保存成交與 recovery task | Redis 全量遺失可自動重建並無縫開放 |
| 效能 | 新版 Wallet trade inbox 加入後，以 dirty-worktree 單一 seed 在完整 gate 下通過 `200 orders/s`、`100.02 trades/s` 長窗，且沒有觀察到相對同 seed baseline 的巨大退化 | 把單次本機結果當成精確 ceiling、release-pinned capacity 或 production SLA；200 以上尚未重測 |

## 目前版本的驗證摘要

2026-09-04 以與前一版相同 seed、`60s + 900s`、k6 open-loop 與 shuffled
BUY／SELL workload 重跑目前程式：

- `192000/192000` HTTP accepted，steady `199.99 orders/s`、`100.02 trades/s`，三服務各 `96000` trades 且 ID set 完全一致。
- Order／Wallet／Match inbox max 為 `291/389/95`，oldest age max `1/1/0s`，terminal debt max 全為 `0`；最終 inbox、outbox 與 cleanup debt 全為 `0`。
- 資產、Order execution／reservation 雙狀態、CQRS checkpoint、Redis order book／reservation、Rabbit 與 DLQ 全數通過。
- k6 HTTP p95／p99 為 `4.72/32.89 ms`；相同 seed baseline 是 `15.89/74.98 ms`，但各只有一輪，不把差值宣稱成效能提升。
- 五個 repo 的 commit 與 working-tree content fingerprint 在測試前後一致；來源仍未提交、driver 與服務同機、PostgreSQL `synchronous_commit=off`，因此只能說 current-worktree diagnostic lower bound。

完整方法、數字與限制見[2026-09-04 全鏈報告](benchmarks/2026-09-04-current-reliability-full-chain.md)；
[2026-09-03 報告](benchmarks/2026-09-03-current-version-full-chain.md)保留為加入 Wallet trade inbox 前的比較基準。

## 建議閱讀路線

### 只有 10 分鐘

1. 本文件。
2. [中文 README](../README.zh-TW.md)的 CDA 流程與可靠性表。
3. [最新全鏈壓測報告](benchmarks/2026-09-04-current-reliability-full-chain.md)的結論與結果表。

### 想完整恢復設計記憶

1. [系統架構](architecture.zh-TW.md)：先抓 bounded context、交易邊界、CQRS 與完成語意。
2. [訂單事件完整生命週期](order-event-lifecycle.zh-TW.md)：逐步看 happy path、亂序、retry、crash window 與取消。
3. [事件一致性的五個問題](event-consistency-five-questions.zh-TW.md)：用 distributed transaction、outbox、at-least-once、business complete、compensation 五題檢查自己。

### 想看這次可靠性實作

1. [Order 驗資結果 durable inbox](order-asset-reservation-result-reliability.zh-TW.md)。
2. [Wallet inbox 與取消最終確認](wallet-inbox-and-cancellation-completion.zh-TW.md)。
3. [Wallet 成交結算 durable inbox](wallet-trade-settlement-inbox.zh-TW.md)。
4. [Match order-admission inbox](match-order-admission-inbox.zh-TW.md)。
5. [Match terminal error semantics](match-terminal-error-semantics.zh-TW.md)。
6. [Durable Debt SLO 與完成關卡](durable-debt-slo.zh-TW.md)：理解 queue=0 為何不夠、每類 debt 如何分類，以及 schema v4 如何 fail closed。
7. [ADR-004：inbox commit 前 DB outage recovery](adr/ADR-004-cda-inbox-precommit-db-outage-recovery.zh-TW.md)：理解為何保留 source queue、何時開 circuit，以及為何本次不做 delayed retry queue。
8. [REL-104 故障恢復報告](benchmarks/2026-09-17-rel104-db-outage-recovery.md)：看 60 秒 outage、consumer pause、probe、DLQ 與 durable debt 的正式證據。
9. [Order Saga Timeout Detector](order-saga-timeout-detector.zh-TW.md)：理解 queue／inbox 無 debt 為何仍可能卡單、有效狀態與 last-progress 如何判斷，以及為何 timeout 不等於可以自動補償。
10. 各服務 README，再進對應 listener、inbox、processor、reconciler 與 database changelog。

### 準備面試

先讀[面試快速入口](interview-guide.zh-TW.md)，再用本文件的「現行能力與誠實邊界」回答追問。效能問題一律先說 workload、版本、完成條件與 evidence class，再報數字。

## 接下來做什麼

跨服務待辦已集中到[工程 Backlog](backlog.zh-TW.md)，並依交易正確性、故障存活、
可驗證性、效能與延伸功能排序。Match reservation cleanup 假成功、Wallet trade
durable inbox、Match admission inbox 與完整 schema v3 gate 都已通過 200 orders/s
長窗；`EAP-REL-101` 也已完成 Redis generation／`run_id` fail-closed gate、受控
activation 與真實 restart fence 測試。`EAP-REL-102` 也已補齊 Match cancellation、
reservation issue 與 cleanup lease 的 terminal semantics。`EAP-REL-103` 也已把跨服務
durable debt 的 count、oldest age、retry／terminal、Prometheus 告警與 schema-v4
business-complete gate 統一定義。`EAP-REL-104` 也已完成 CDA inbox commit 前的長時間
DB outage 自動恢復，三個服務各自通過 60 秒 PostgreSQL outage。`EAP-REL-105` 也已用
warning-only detector 補上 Order Saga 卡住的可見性；下一步是 `EAP-REL-106` 的
DLQ／terminal recovery control plane。
