# EAP 最新版本導覽

> 更新日期：2026-09-03

> 定位：這是本次可靠性大改版的閱讀入口；細節仍以連結的架構、生命週期與實作文件為準。

## 先記住這個版本改了什麼

1. **事件語意變清楚。** Wallet 驗資成功後發布的跨服務事實從語意模糊的 `OrderConfirmedEvent` 改成 `OrderAssetReservationSucceededEvent`。它同時讓 Order 更新 reservation 狀態，也讓 MatchEngine 知道訂單具備 admission 資格。
2. **三個 bounded context 都擁有自己的可靠接收狀態。** Wallet 先 durable intake 下單／取消結果；Order durable intake 驗資結果、真正缺 prerequisite 的成交、取消結果與資產釋放；MatchEngine durable intake 可進訂單簿的訂單。ACK 代表服務已接管工作，不代表業務已完成。
3. **Order 把兩種狀態拆開。** `status` 表示執行生命週期，`assetReservationStatus` 表示 Wallet reservation 進度。`TradeExecutedEvent` 若先到，可以證明 reservation 曾成功並直接推進成交，晚到的成功事件不能把 `MATCHED` 降回 `OPEN`。
4. **取消訂單有真正的完成語意。** MatchEngine 取得未成交剩餘量後，Order 只進入 `CANCELLING`；Wallet 實際釋放資產並發布 `OrderAssetReservationReleasedEvent`，Order 才進入 `CANCELLED`。
5. **CQRS projection 被納入使用者可見正確性。** Command-side 成交不等待 read model，但壓測最後必須驗證 `orders_current` 數量、reservation／execution 狀態與 checkpoint lag。
6. **壓測不再只看 RabbitMQ。** 新 gate 會另外量 Order durable inbox 的 backlog 與 slope。這次因此推翻了工具原本對 300 orders/s 的 PASS。

## 現行能力與誠實邊界

| 面向 | 現在可以說 | 仍不能說 |
| --- | --- | --- |
| 一致性 | local transaction＋outbox＋at-least-once＋idempotency＋durable inbox，使 duplicate、worker crash 與部分亂序可恢復 | exactly-once messaging、跨服務 ACID transaction |
| Saga | CDA choreography 的主要步驟、取消 remainder compensation 與多段 retry state 已實作 | 所有 DB outage、timeout、DLQ／terminal outbox 都會自動修復 |
| CQRS | Order event store 是事實來源；`orders_current` 可重建並為查詢塑形；API 回傳 execution／reservation 雙狀態 | 強 read-your-write、獨立 read replica 已完成 |
| 撮合 | Redis Lua 維持單一 market 內的撮合／取消互斥，PostgreSQL 保存成交與 recovery task | Redis 全量遺失可自動重建並無縫開放 |
| 效能 | 最新 dirty-worktree 單一 seed 在嚴格 gate 下通過 `200 orders/s`、`100 trades/s` 長窗 | 把舊版 648 當成目前版本容量，或把 200 當精確 ceiling／production SLA |

## 最新驗證摘要

- `200 orders/s`：`192000/192000` HTTP accepted，steady `100.00 trades/s`，三服務各 `96000` trades；Order inbox max `791`、slope `+0.0035/s`，projection lag 與 final debt 都是 `0`。
- `300 orders/s`：成交主鏈達 `149.70 trades/s`，但 Order inbox 觀察到至少 `51007` 筆 backlog；完整狀態鏈拒絕。
- `400 orders/s`：只達 `187.75 trades/s`、目標完成率 `93.88%`，Order inbox 至少 `53231`；拒絕。
- 所有三輪最終資料都正確收斂，表示 reliability safety 保住；300／400 暴露的是 worker liveness 與 sustainable capacity。

完整方法、數字與限制見[2026-09-03 全鏈報告](benchmarks/2026-09-03-current-version-full-chain.md)。

## 建議閱讀路線

### 只有 10 分鐘

1. 本文件。
2. [中文 README](../README.zh-TW.md)的 CDA 流程與可靠性表。
3. [最新全鏈壓測報告](benchmarks/2026-09-03-current-version-full-chain.md)的結論與結果表。

### 想完整恢復設計記憶

1. [系統架構](architecture.zh-TW.md)：先抓 bounded context、交易邊界、CQRS 與完成語意。
2. [訂單事件完整生命週期](order-event-lifecycle.zh-TW.md)：逐步看 happy path、亂序、retry、crash window 與取消。
3. [事件一致性的五個問題](event-consistency-five-questions.zh-TW.md)：用 distributed transaction、outbox、at-least-once、business complete、compensation 五題檢查自己。

### 想看這次可靠性實作

1. [Order 驗資結果 durable inbox](order-asset-reservation-result-reliability.zh-TW.md)。
2. [Wallet inbox 與取消最終確認](wallet-inbox-and-cancellation-completion.zh-TW.md)。
3. [Match order-admission inbox](match-order-admission-inbox.zh-TW.md)。
4. 各服務 README，再進對應 listener、inbox、processor、reconciler 與 database changelog。

### 準備面試

先讀[面試快速入口](interview-guide.zh-TW.md)，再用本文件的「現行能力與誠實邊界」回答追問。效能問題一律先說 workload、版本、完成條件與 evidence class，再報數字。
