**[English](README.md)** | **中文**

# EAP - 事件驅動電力市場交易平台

EAP 是一套獨立開發的事件驅動電力市場後端，支援連續雙向競價（Continuous Double Auction，CDA）與定時集合競價（Timed Double Auction，TDA），使用 Java、Spring Boot、RabbitMQ、PostgreSQL 與 Redis Lua 建置。

專案主要回答三個工程問題：每一項業務事實應由哪個服務負責、交易如何在重試與局部失敗下維持正確，以及工程成果如何用持久化證據驗證。它不是單純的 CRUD 範例，也不是只為了展示壓測數字的專案。

> **目前版本證據（2026-09-03）：** 加入 Order／Wallet／MatchEngine durable inbox 與 Order 雙狀態後，新版 k6 長窗在嚴格計算 RabbitMQ 與 service-owned inbox debt 的 gate 下，單一 seed 通過 `200 accepted orders/s`、`100 completed trades/s`；`192,000` 筆 HTTP 訂單收斂為三服務一致的 `96,000` 筆交易，資產、projection、queue、DLQ 與 reservation 全部正確。300 與 400 雖最終資料也收斂，但 Order reservation-result inbox 會累積到至少 5.1／5.3 萬筆，因此被拒絕為完整系統可持續容量。這是 dirty-worktree 同機診斷下界，不是 production SLA；詳見[最新版本導覽](docs/current-version-guide.zh-TW.md)與[完整報告](docs/benchmarks/2026-09-03-current-version-full-chain.md)。
>
> **歷史證據邊界：** 舊 commits 曾由兩個 release-pinned seed 支持 `648 accepted orders/s` 的 15 分鐘同機壓力邊界，但不能沿用成目前可靠性版本的容量。失敗結果沒有否定 durable inbox 的正確性價值，而是量出它目前的處理成本與下一個瓶頸。

## 系統總覽

CDA 核心由三個各自擁有狀態的服務組成：Order 負責訂單生命週期，Wallet 負責資產與結算，MatchEngine 負責訂單簿與成交決策。RabbitMQ 傳遞整合事件，每個服務只提交自己擁有的資料庫狀態。

```mermaid
flowchart LR
    Client[使用者] -->|提交訂單| Order[Order Service]
    Order --> OrderDB[(Order DB)]
    Order -->|OrderSubmitted| MQ[(RabbitMQ)]
    MQ --> Wallet[Wallet Service]
    Wallet --> WalletDB[(Wallet DB)]
    Wallet -->|OrderAssetReservationSucceeded| MQ
    MQ --> Match[MatchEngine]
    MQ --> Order
    Match <--> Redis[(Redis 訂單簿)]
    Match --> MatchDB[(Match DB)]
    Match -->|TradeExecuted| MQ
    MQ -->|套用成交結果| Order
    MQ -->|結算資產| Wallet
```

服務之間沒有分散式交易。需要發布事件的服務，會在同一筆本地資料庫交易中寫入狀態與 Transactional Outbox，再由 relay 等待 RabbitMQ 確認後發布。Consumer 透過冪等紀錄與本地交易承受 at-least-once delivery。

## CDA 完整業務流程

1. 使用者透過 Order HTTP API 提交 BUY 或 SELL 訂單。
2. Order 驗證命令，在同一筆交易中寫入訂單事件與 outbox。
3. Wallet 接收訂單、保留所需資產，再透過自己的 outbox 發布 `OrderAssetReservationSucceededEvent`。
4. MatchEngine 先把這項事實寫入 durable admission inbox，再由 lease worker 將合格訂單放入 Redis sorted-set 訂單簿，並用 Lua 原子執行撮合。
5. 成交時，MatchEngine 在同一筆資料庫交易中寫入 `TradeExecuted`、trade outbox，以及必要的 reservation cleanup task。
6. Order 將成交結果套用到命令端訂單狀態；Wallet 完成買賣雙方資產結算。
7. 營運驗證在交易路徑之外，比對 MatchEngine、Order、Wallet 各自持久化的 trade ID，核對資產，並確認 queue 與 retry debt 已清空。

取消訂單採用獨立的非同步決策流程：Order 先持久化受理請求，MatchEngine 再確保訂單剩餘數量只會由撮合或取消其中一方取得。MatchEngine 回覆成功後 Order 先進入 `CANCELLING`；Wallet 透過 durable inbox 套用結果、釋放精確未成交資產並發出 `OrderAssetReservationReleasedEvent`，Order 收到這項釋放事實後才成為 `CANCELLED`。若成交、取消結果或資產釋放事件亂序抵達，各自的 durable inbox 會保留並等待前置事實，而不是覆蓋已成立的成交。

MatchEngine 不再維護額外的下游 Completion View，也不等待 Order 或 Wallet 回傳完成事件。各服務擁有自己的處理結果；跨服務收斂是交易路徑之外的驗證，不是新的業務依賴。

完整交易邊界、事件流、復原方式與獨立的 TDA 流程請見[架構文件](docs/architecture.zh-TW.md)。

## 服務責任

| 服務 | 擁有的資料 | 主要責任 |
| --- | --- | --- |
| [eap-order](https://github.com/Yitin-tsai/eap-order) | 訂單命令事件與成交套用結果 | HTTP 下單、訂單生命週期、命令端狀態與可重建 projection |
| [eap-wallet](https://github.com/Yitin-tsai/eap-wallet) | 可用／鎖定餘額、結算事實與已套用的訂單取消結果 | 驗資、冪等交易結算與訂單取消後的資產釋放 |
| [eap-matchEngine](https://github.com/Yitin-tsai/eap-matchEngine) | 訂單簿、`TradeExecuted` 與訂單取消結果 | CDA 撮合、確保訂單剩餘數量不會同時被撮合與取消、Redis reservation 復原、成交持久化；TDA 排程與清算 |
| [eap-common](https://github.com/Yitin-tsai/eap-common) | 共用整合契約 | Event 與 DTO 定義，不擁有業務狀態 |
| [eap-mcp](https://github.com/Yitin-tsai/eap-mcp)／[eap-ai-client](https://github.com/Yitin-tsai/eap-ai-client) | 受控 AI 工具 | 實驗性 control-plane 操作，不參與核心交易正確性 |

TDA 是另一條已實作的市場模式，會收集通過驗資的階梯式出價，再依排程統一清算。目前尚未完成與 CDA 同等的可靠性與容量驗證，因此不能把 CDA 的證據直接套用到 TDA。

## 可靠性設計

| 失敗或一致性風險 | 現行控制方式 |
| --- | --- |
| 資料庫提交成功，但事件發布失敗 | Transactional Outbox 與可重試 relay |
| RabbitMQ 重複投遞事件 | 資料庫冪等紀錄、payload identity guard 與唯一約束 |
| Consumer 在 ACK 前停止 | 關鍵 Order／Wallet consumer 先 durable intake；commit 後才 manual ACK 或由 container ACK，後續以 lease worker 恢復 |
| 錯誤事件無法處理 | Retry policy 與 DLX／DLQ |
| Redis reservation 清理中斷 | 持久化 cleanup task、精確 `tradeId` 對應與 reconciliation |
| 讀取 projection 延遲 | Projection 可重建，且不阻擋命令端交易套用 |
| 取消訂單與撮合競爭，或事件亂序抵達 | MatchEngine 決定剩餘量歸屬；Wallet durable inbox 冪等釋放並發布釋放事實；Order 以 `CANCELLING → CANCELLED` 與 prerequisite retry 等待收斂 |
| 局部指標正常，但完整流程尚未完成 | 三服務 trade-ID 一致、資產核對及 queue／retry debt 清空 |

CDA 交易只有在 MatchEngine 已寫入成交、Order 已套用成交、Wallet 已完成結算、三服務持久化 trade-ID 集合一致、資產正確，而且量測範圍內的 queue 與 retry debt 都清空後，才算完整業務完成。

## AI 工程協作流程

EAP 將 AI 限制成不同工程角色，而不是讓 AI 自動產生程式後直接採用。Product Scope 先質疑功能是否值得做；Architect 審查服務責任與一致性；Performance Analyst 定義工作負載與假設；Implementation 只能依人工接受的規格實作；QA 與 Reviewer 主動尋找正確性反例及不成立的宣稱。架構、風險、採用、回復、部署與公開說法，最後都由人工負責人決定。

```mermaid
flowchart TD
    Problem[問題或新功能] --> Scope[功能必要性與範圍]
    Scope --> Architecture[架構與一致性審查]
    Architecture --> Hypothesis[效能或可靠性假設]
    Hypothesis --> Decision[人工接受實驗]
    Decision --> Implementation[範圍內實作]
    Implementation --> QA[測試、壓測與監測]
    QA --> Review[獨立審查]
    Review --> Human[人工決策]
    Human --> Adopt[採用]
    Human --> Reject[拒絕或回復]
    Human --> Next[下一個實驗]
```

每次實驗都要記錄 baseline、單一主要變因、執行命令、觀測資料、正確性關卡與最終決策。即使修改提高局部 TPS，只要交易或 concurrency tests 證明結果無法安全 rollback，仍會被拒絕。被拒絕的實驗也保留，避免未來在沒有新證據時重做相同的不安全最佳化。

角色契約與真實採用／拒絕案例請見 [EAP 證據驅動 AI 工程工作流](docs/ai-engineering-workflow.md)；版本控制的[工作流技能](skills/)則提供文件背後可執行的角色邊界。[Hello World Dev Conference 案例說明](docs/talks/hello-world-dev-conference-2026-case-study.md)整理這套流程如何用於自我審查、功能擴充與企業 SDLC。

## 工程證據

效能資料用來驗證架構，不是首頁的主體。EAP 分開記錄 HTTP 接受速率、元件隔離吞吐量、同窗完成交易、完整流程吞吐量、短時間診斷與長時間測試；每個數字都必須附帶工作負載邊界與正確性結果。

目前權威文件、壓測證據、生成產物與歷史封存的邊界，請先看
[文件地圖](docs/README.md)。

- [效能報告](docs/performance-report.md)：目前宣稱、定義、限制與瓶頸歷程。
- [最新版本全鏈報告](docs/benchmarks/2026-09-03-current-version-full-chain.md)：新版 400／300 拒絕、嚴格 200 通過與 inbox backlog 量測修正。
- [壓測分類](docs/benchmarks/load-test-taxonomy.md)：各種工作負載能證明及不能證明的內容。
- [最新 canonical mixed 短窗邊界](docs/benchmarks/2026-08-14-canonical-mixed-short-window-boundary.md)：目前 CDA 短窗轉折區與限制。
- [624 持續測試證據](docs/benchmarks/2026-08-18-release-pinned-624-sustained-candidate.md)：2 個有效的 15 分鐘 seed，支持前一級持續下界。
- [648 持續壓力邊界](docs/benchmarks/2026-08-18-release-pinned-648-sustained-boundary.md)：2 個有效的 15 分鐘 seed，建立最高可重複點及其壓力限制。
- [版本鎖定的 700 可追溯性驗證](docs/benchmarks/2026-08-21-release-pinned-700-provenance.md)：完整記錄來源與環境，並保留被拒絕的 700 orders/s 結果；648 邊界不變。
- [低觀測與高輸入探針](docs/benchmarks/2026-08-18-low-observability-and-high-rate-probes.md)：被拒絕的 648 重跑，以及受 driver 限制的 1200／2000 短時間過載診斷；不提高容量宣稱。
- [預先準備 HTTP driver 診斷](docs/benchmarks/2026-08-18-prepared-http-driver.md)：將 request 資料準備移出流量計時、2,000 requests/s driver-only 校準，以及短時間 full-chain A/B 的證據邊界。
- [外部 open-loop driver](docs/benchmarks/2026-08-19-external-open-loop-driver.md)：低成本固定速率送流量、lifecycle 交接、正確性關卡，以及尚未解決的主機隔離邊界。
- [k6 648 完整長窗驗證](docs/benchmarks/2026-08-25-k6-full-lifecycle-648.md)：完整保留 dropped iterations、三服務正確收斂、VU 校準失敗與需要 remote driver 的決策。
- [排程隔離診斷](docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md)：較早的採用修正與被拒絕高流量證據。
- [Wallet 穩健性報告](docs/benchmarks/2026-08-05-wallet-settlement-robustness.md)：交易安全、混合流量、長時間及故障證據。
- [取消責任與回歸報告](docs/benchmarks/2026-08-24-cancellation-ownership-and-regression.md)：說明 Wallet 為何不投影每張訂單，以及競態、亂序與正常流程回歸證據。

## 本機執行

```bash
make dev-env
make dev-up
make run-all
```

建置與測試：

```bash
make build
make test
```

Repository 初始化與服務操作請見 [DEV-GUIDE.md](DEV-GUIDE.md)。壓測入口位於 [scripts/load-test/](scripts/load-test/)；比較數據前請先閱讀[公開壓測 runbook](docs/benchmarks/2026-07-public-benchmark.md)。

## 建議閱讀順序

1. [最新版本導覽](docs/current-version-guide.zh-TW.md)：先掌握這次可靠性大改版、目前數據、限制與分流閱讀入口。
2. [面試快速入口](docs/interview-guide.zh-TW.md)：五分鐘掌握功能、架構、一致性、效能、優缺點與可展開故事。
3. [架構文件](docs/architecture.zh-TW.md)：服務責任、CDA／TDA 流程、交易邊界與完成語意。
4. [CDA 訂單事件完整生命週期](docs/order-event-lifecycle.zh-TW.md)：從下單、驗資、撮合、結算到取消訂單，包含 retry、outbox／inbox、DLQ、Saga 與非 happy path。
5. [事件驅動一致性的五個核心問題](docs/event-consistency-five-questions.zh-TW.md)：詳細回答 distributed transaction、Outbox、at-least-once、business complete 與 Saga compensation 的邊界。
6. [Wallet Inbox 與取消最終確認](docs/wallet-inbox-and-cancellation-completion.zh-TW.md)：本次 durable intake、錯誤分類、lease retry、資料表與 `CANCELLING → CANCELLED` 的實作證據。
7. [AI 工程工作流](docs/ai-engineering-workflow.md)：角色契約、人工檢查點、證據關卡與 rejected experiments。
8. [研討會快速說明](docs/talks/hello-world-dev-conference-2026-brief.zh-TW.md)：一分鐘開場、中文故事與後續討論問題。
9. [研討會案例說明](docs/talks/hello-world-dev-conference-2026-case-study.md)：工作流如何實際運作與泛化。
10. [效能報告](docs/performance-report.md)：壓測合約與目前證據。
11. [壓測分類](docs/benchmarks/load-test-taxonomy.md)：詳細工作負載邊界。
12. 各服務 repository：[Order](https://github.com/Yitin-tsai/eap-order)、[Wallet](https://github.com/Yitin-tsai/eap-wallet)、[MatchEngine](https://github.com/Yitin-tsai/eap-matchEngine) 與 [Common](https://github.com/Yitin-tsai/eap-common)。

`docs/archive/performance/` 下的凍結實驗歷史會保留供追溯，但不屬於一般讀者的專案介紹路徑。
