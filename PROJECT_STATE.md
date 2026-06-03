# EAP 專案狀態總覽

> 最後整理：2026-06-03  
> 用途：作為目前 workspace 的單一入口，避免 `_bmad-output`、`.blackboard`、`cr_outputs` 與 `docs` 的歷史文件互相衝突。

## 一句話定位

EAP 是一個事件驅動的電力交易平台，以 Spring Boot 微服務、RabbitMQ、Redis ZSET + Lua、PostgreSQL、Spring AI + MCP 建立可展示的交易系統工程作品。重點不是 CRUD，而是交易流程中的一致性、冪等性、事件可靠性、撮合原子性與可審計性。

## 目前架構主線

| 區塊 | 狀態 | 說明 |
|------|------|------|
| 連續撮合 CDA | 已完成 | `eap-order -> eap-wallet -> eap-matchEngine -> eap-order/eap-wallet` 的 RabbitMQ Choreography Saga |
| Wallet-first 驗資 | 已完成 | 訂單先經 wallet 驗證與鎖定，成功後才進入撮合 |
| Redis 撮合引擎 | 已完成 | Redis ZSET + Lua script 維持訂單簿原子操作 |
| Timed Double Auction | 已完成 | 每小時固定視窗密封競標，Uniform Price 清算，支援階梯式出價與 pro-rata |
| MQ Reliability | 已完成 | Outbox Pattern、DLX/DLQ、prefetch、retry 設定已落地 |
| Wallet 冪等與並發 | 已完成 | `@Version` 樂觀鎖、TransactionTemplate retry、settlement idempotency |
| Orders async backup | 已完成 | `orders` 表恢復為非同步 snapshot/materialized view |
| Audit Trail / Replay | 已完成 | `audit_events`、hash chain、order replay API，將 SSE 降級為即時通知 |
| Market sequencing | 已完成 MVP | `marketId + marketSequence` 已進 order event flow，order service 可多 pod 共享 Redis atomic sequence |
| MCP / AI 整合 | 已完成 | MCP tools、AI client、模擬交易入口 |
| eap-trigger | 新增中 | Go 服務，與主 Java 微服務群不同，需要另行補文件與定位 |

## 文件狀態判斷

### 保留且優先閱讀

| 文件 | 用途 |
|------|------|
| `README.md` | 對外介紹與快速理解主架構 |
| `DEV-GUIDE.md` | 本地啟動、Makefile、開發流程 |
| `_bmad-output/index.md` | BMAD 文件總索引 |
| `_bmad-output/architecture.md` | 目前架構與可靠性設計摘要 |
| `_bmad-output/integration-architecture.md` | 事件流、RabbitMQ routing、MCP/AI 整合 |
| `_bmad-output/data-models.md` | PostgreSQL / Redis / DTO / Event 模型 |
| `_bmad-output/source-tree-analysis.md` | 模組與關鍵檔案導覽 |
| `docs/mq-scaling-notes.md` | MQ 水平擴充與 Super Stream 評估紀錄 |
| `docs/exchange-architecture-reading-list.md` | 交易所 matching engine、sequencing、market data feed 閱讀清單 |
| `docs/market-sequencing-plan.md` | marketId / marketSequence、price-time priority 與 audit 重構規劃 |
| `docs/tsmc-interview-prep.md` | TSMC 面試簡報與 Q&A 準備 |

### 面試資產，必須保存

| 文件 | 用途 |
|------|------|
| `_bmad-output/resume-improvement-notes.md` | 履歷簡報改版決策與歷程 |
| `_bmad-output/resume-prompt-for-claude.md` | Claude Web 修改 PPTX 用 prompt |
| `_bmad-output/resume-v6-fix-prompt.md` | v6 PPTX 修正 prompt |
| `_bmad-output/self-intro-scripts.md` | 3/5/10 分鐘中英文自我介紹 |
| `_bmad-output/interview-project-deepdive.md` | EAP 專案深問、架構取捨、反問準備 |
| `_bmad-output/linkedin-03-mq-scaling-tradeoff.md` | MQ 擴充取捨的公開敘事素材 |
| `docs/tsmc-interview-prep.md` | TSMC AAID 面試簡報口述稿與 Q&A |

### 歷史工作紀錄，不當作目前待辦

| 文件群 | 判斷 |
|--------|------|
| `_bmad-output/planning/stories/1-*.md` | 早期 ADR 拆出的 story，多數已被後續實作；狀態欄仍寫 `ready-for-dev`，不可直接當待辦 |
| `_bmad-output/planning/reliability-adrs.md` | 可靠性設計來源，保留為決策背景；實作狀態需以程式碼與 `cr_outputs` 為準 |
| `.blackboard/features/*` | Ghostwriter/Claude 工作流的 impact analysis，保留為需求與風險推理紀錄 |
| `eap-matchEngine/cr_outputs/features/*` | timed-double-auction 與 auction-risk-fixes 的需求、設計、review、測試結果，是較可信的後期紀錄 |
| `_bmad-output/brainstorming/*` | 未來功能發想，不代表目前 roadmap 承諾 |

## 面試說法校準

以下點可以講，但要保持精準：

| 主題 | 建議說法 | 避免說法 |
|------|----------|----------|
| Matching Engine 單實例 | 這是 correctness over scale 的架構取捨，未來可 sharded matching | 不要說已正式壓測證明 MQ 是瓶頸 |
| MQ Reliability | Outbox Pattern + Manual ACK/Prefetch + DLX/DLQ | 不要說有 Publisher Confirm，除非程式碼真的補上 |
| 測試數量 | 面試前以實際 `./gradlew test` 結果為準 | 不要死背 102 tests，除非當天已確認 |
| Super Stream / Kafka | 已評估，但目前問題可由 optimistic lock retry 解決 | 不要說已遷移或已在 production 驗證 |
| Observability | 國泰有 production 經驗；EAP 可列為如果重做會更早加入 | 不要宣稱 EAP 已有完整 tracing stack |
| Load Test / Benchmark | 可列為未來補強或 production 化前工作 | 不需要列成近期待辦 |

## 不列為近期待辦

這些方向有價值，但目前不是這個專案的關鍵工作：

| 項目 | 理由 |
|------|------|
| 正式 load test | 面試可以誠實說尚未做；目前專案價值在架構取捨與一致性設計 |
| 完整 observability | 可作為反思點，不必為了 side project 強行補齊 |
| E2E benchmark | 若沒有明確面試或文章需求，不急著做 |
| Kafka / Super Stream 遷移 | 已有評估文件；目前不需要實作 |

## 建議下一步

1. 將本文件當作新 AI 或未來自己接手時的第一入口。
2. 面試前只讀「面試資產」與「面試說法校準」，不要重新翻全部 story。
3. 若要繼續開發，優先補 `eap-trigger` 的定位與與主系統的關係。
4. 若要整理到更乾淨，可將早期 `ready-for-dev` story 改標 `implemented-by-later-work`，但不需要刪除。
