# EAP Engineering Backlog

> 更新日期：2026-09-18

> 本頁是跨 Order、Wallet、MatchEngine 的唯一優先順序入口。各 feature ticket
> 保存設計與驗收細節；若 ticket 內的排列與本頁不同，以本頁為準。

## 排序原則

1. 先處理可能讓交易結果錯誤、工作遺失或監控誤報成功的問題。
2. 再補 CDA 的 liveness、故障偵測與受控恢復能力。
3. 只有在目前版本通過完整正確性關卡後，才繼續最佳化吞吐量。
4. TDA、read replica 與平台型功能保留為後續學習題，不搶占 CDA 可靠性工作。

## P0：先封版目前的 CDA 可靠性改版

### EAP-REL-001：修正 Match reservation cleanup 假成功（完成）

**原因：** `complete_reserved_order.lua` 會用 `-1`／`-2` 表示 order identity 或
trade ownership 不符；修正前 Java 只記 warning，cleanup worker 仍可能把 task 標成
`COMPLETED`。這會讓 durable debt 看起來已清空，但 Redis reservation 實際仍存在。

**完成條件：**

- [x] cleanup 明確區分 `COMPLETED`、`ALREADY_COMPLETED`、
  `ORDER_ID_MISMATCH`、`NEWER_TRADE_OWNER`。
- [x] 前兩者才可完成 task；identity／ownership conflict 立即保存為 terminal `FAILED`，
  不自動重試。Redis／network／未知回傳等技術錯誤仍使用原有 bounded retry。
- [x] unit 與真實 PostgreSQL／Redis crash-recovery tests 覆蓋正常完成、重送、
  舊 tradeId 對上較新 reservation，以及 order identity mismatch 的零變更保護。

**驗證（2026-09-04）：** `./gradlew --no-daemon test` 與
`./gradlew --no-daemon crashRecoveryIntegrationTest` 均通過。這一項只修正 cleanup
結果判定與稽核語意，不把尚未完成的 Redis full-book rebuild 或集中 recovery control
plane 誤算在內。

### EAP-REL-002：完成目前未提交可靠性變更的 production-style review（完成）

**範圍：** Wallet trade durable inbox、Wallet inspection／metrics、Match self-trade
prevention 與相關 recovery 修改。

**完成條件：**

- 三個服務 unit tests 通過。
- PostgreSQL／Redis／RabbitMQ integration tests 覆蓋 duplicate、payload conflict、
  lease reclaim、lost-lease rollback 與 transaction atomicity。
- 沒有 P0／P1 correctness finding；文件不得把未驗證能力寫成已完成保證。

**已確認的產品決策：** self-trade prevention 採「保留自己的 resting liquidity，略過後
繼續找下一筆 price-time eligible 的其他使用者訂單；沒有其他對手時 incoming order
正常進簿」。這是使用者明確要求的禁止自我成交政策，不宣稱全市場都必須採這一種
self-trade prevention mode。

**驗證（2026-09-04）：** Common、Order、Wallet、MatchEngine unit suites 通過；Wallet
在乾淨一次性 PostgreSQL 上 49 tests 全數通過，隔離 Rabbit retry／DLQ integration
1 test 通過；Match PostgreSQL／Redis crash-recovery 25 tests 全數通過。Reviewer 無
blocker 並核准關閉。既有 settlement null hash、serializer-version fingerprint、worker
token scaling、invalid Redis row quarantine 與非零停機 migration 限制都已明確保留，
不當作本 ticket 已解決。

### EAP-REL-003：以最新版程式重跑完整全鏈正確性與長窗基準（完成）

**原因：** 2026-09-03 的 `200 orders/s` 是 Wallet trade inbox 加入前的比較基準，
不能直接當成目前版本容量。

**完成條件：**

- [x] load-test gate 納入 Order、Wallet、Match 的 inbox level／oldest age／terminal debt。
- [x] 同時核對三服務 trade ID、資產、Order execution／reservation 狀態、CQRS checkpoint、
  Redis order book／reservation、Rabbit ready／unacked／DLQ、outbox 與 cleanup task。
- [x] 先重跑可比較的 200 orders/s 長窗；通過後才決定是否搜尋更高邊界。
- [x] 報告標明 revision、workload、seed、環境與限制，再 commit／push 本次版本。

**驗證（2026-09-04）：** schema v3 gate 的極短 R6 與正式 `60s + 900s` 長窗都通過。
長窗以 seed `20260905` 接受 `192000/192000` 筆訂單，穩態 `199.99 orders/s`、
`100.02 trades/s`；三服務各 `96000` 筆 trade ID 完全相同，資產、Order 雙狀態、
CQRS、Redis、Rabbit／DLQ 與所有 final inbox／outbox／cleanup debt 都收斂。Order、
Wallet、Match inbox 的 oldest age max 為 `1/1/0s`、terminal debt max 都是 `0`。
結果是穩定 dirty-worktree、同機、單一 seed diagnostic，故
`capacityClaimAllowed=false`；完整限制與工具修正見
[2026-09-04 全鏈報告](benchmarks/2026-09-04-current-reliability-full-chain.md)。

## P1：CDA 故障存活與營運恢復

### EAP-REL-101：Redis 全量遺失先 fail closed（完成）

**原因：** 個別 reservation 已有 recovery，但 Redis 整個 order book 遺失時，Match
目前不能證明 runtime state 完整。最小安全措施不是立刻自動重建，而是禁止在未知
generation 上繼續 admission／matching。

**完成條件：**

- [x] 保存並核對 order-book generation／readiness。
- [x] Redis restart 或 generation mismatch 後 Match readiness 失敗並停止新 admission。
- [x] 操作者完成重建與 durable-fact reconciliation 後才能重新開放。

**驗證（2026-09-14）：** PostgreSQL control row 保存 `READY／RECOVERING`、epoch、
generation、Redis `run_id`、CAS version 與 activation manifest；所有 CDA mutation Lua
在原子寫入點同時核對 sentinel 與實際 `run_id`。真實 Redis SAVE＋restart 測試證明即使
舊 sentinel 與資料被保存，舊 worker 仍不能寫入。completed-admission bitmap 另逐 bit
核對 PostgreSQL `APPLIED` inbox，stray／missing marker 不得 reopen；full manifest 只在
`RECOVERING` activation 擁有 promotion 權限。READY runtime 的普通 status 只查 generation
identity，另提供非破壞性 manifest 診斷，避免把合法 in-flight shape 誤判後停撮。
cancellation marker 亦不得與 visible order 共存，且
marker／intent 必須核對 durable cancellation identity；recovery CAS 同時比對 version、
epoch、generation 與 run-id，避免 reset 後 version ABA。activation 的 exclusive advisory
lock 與 cancellation durable intake 的 shared advisory lock 形成共同 barrier，取消彼此
仍可並行，但啟用不能漏看正提交中的 `PENDING` cancellation。Match unit suite、48 項
PostgreSQL／Redis crash-recovery cases 加 1 項真實 restart fence 均通過；最新版 R7 全鏈 correctness smoke 接受 80/80
筆 HTTP 訂單、三服務 40 筆 trade 完全一致、所有 debt 為 0，最終 runtime control 為
`READY` 且 manifest 的 `completedAdmissionCount=80` 精確對應 durable inbox。相同 recovery
token 的並發 activation 也只允許一個 winner。本項完成 fail-closed 與受控 activation
contract，不包含 `EAP-MATCH-202` 的自動 full-book rebuild；R7 短測不作容量宣稱。
`REL101_ORDER_ADMISSION_SAFE_RESET_R3` 另驗證 consumers 停止後才 reset、重啟並
`INITIALIZE_EMPTY`；traffic-only generator 不清資料，20/20 inbox `APPLIED`、20/20
訂單可見且 queue debt 為 0。

### EAP-REL-102：補齊 Match 剩餘 terminal error semantics（完成）

**範圍：** cancellation reconciler 無上限、reservation reconciler 的 ownership conflict
只有 log／metric、invalid reservation 只有 log／metric、missing／invalid order detail
目前共用粗粒度 `UNKNOWN_RETRYABLE`，以及 cleanup lease 尚無 owner token／fencing version。

**完成條件：**

- [x] prerequisite waiting 與 technical retry 分開計時及告警。
- [x] poison／invariant failure 有 durable terminal record，不會無限執行 recovery mutation
  或重複洗掉錯誤現場。
- [x] operator 可以看見 ownership、payload 與最後一次失敗原因。
- [x] 過期 cleanup worker 不能覆寫已被新 worker 接手的 task 狀態。

**驗證（2026-09-14）：** cancellation decision 新增獨立 prerequisite／technical counter、
起始時間、error type、last error 與 `FAILED_TERMINAL`；Redis order detail invariant 由
admission inbox 直接分類為 `PERMANENT_ORDER_BOOK_DATA_INVARIANT`。Orphan reservation
另以 durable issue table 保存 generation＋trade／payload fingerprint、raw payload、
attempt 與 terminal／resolved 狀態；相同 terminal identity 不再被無限重試，同 Redis
key 的新版 reservation 不受舊 issue 影響。找到 durable trade 時會核對完整 order／user／
market／side／sequence／price／quantity identity，衝突時 Redis 零變更。generation-bound
共享 Redis cursor／buffer 讓每輪 scan 與 action 都受 batch 限制，terminal／fresh／active
cleanup item 不會餓死後續工作。只有 retryable issue 可在 fingerprint 確認消失後自動
收斂；terminal row 必須留給受控處理。Cleanup task 的 renew／完成／重排／失敗
更新都核對 instance owner 與每次 claim token。Match unit suite 與 PostgreSQL／Redis
crash-recovery integration suite（58 tests）通過；詳細流程與 operator SQL 見
[Match terminal error semantics](match-terminal-error-semantics.zh-TW.md)。本項沒有實作
DLQ replay UI、Saga timeout 或 Redis full-book rebuild。

### EAP-REL-103：建立跨服務 durable-debt SLO 與告警

**狀態：已完成（2026-09-15）。**

**範圍：** inbox、outbox、cleanup、cancellation、projection 與 Rabbit DLQ。

**完成條件：**

- [x] 每類工作至少有 count、oldest age、retry／terminal count。
- [x] business-complete gate 與 Prometheus alert 使用相同的 versioned snapshot 定義。
- [x] Rabbit queue 歸零但 service-owned work 累積時仍會失敗並告警。
- [x] snapshot refresh 使用獨立 scheduler；Prometheus scrape／Actuator request 不直接查 DB。
- [x] DB observation failure、stale snapshot、target／metric 消失與契約漂移都 fail closed。

**實作與驗證：** Order、Wallet、MatchEngine 各自從權威本地 table 每 5 秒建立一次
`DurableDebtSnapshot` v1；固定 work allowlist 共同支援 Actuator endpoint、Micrometer 與
schema-v4 full-chain gate。Order projection checkpoint 新增 durable failure metadata；
unresolved partial index 限制 snapshot query 的歷史掃描。RabbitMQ Prometheus plugin
提供 DLQ count／head timestamp，核心 publisher 寫入 AMQP timestamp；缺少 head age 本身
也會告警。`promtool` config 與 rule tests、三服務 unit suites、provider／projection
PostgreSQL/Redis integration tests，以及 100 orders／50 trades 全鏈 smoke 均通過；smoke
只證明 wiring 與 correctness，不更新容量數字。完整定義見
[Durable Debt SLO 與完成關卡](durable-debt-slo.zh-TW.md)。

### EAP-REL-104：處理 inbox commit 前的長時間 DB outage

**狀態：已完成（2026-09-17）。**

**原因：** 現行 Spring listener 約數秒內重試三次，DB outage 稍長就會形成 DLQ
flood；durable inbox 無法保護尚未成功落盤的訊息。

**完成條件：**

- [x] 完成 ADR，比較 delayed retry queue 與 consumer pause／circuit breaker。
- [x] schema／poison error 直接 quarantine；DB connectivity failure 保留在 source queue 並暫停 consumer。
- [x] Order、Wallet、MatchEngine 各自通過 60 秒 DB outage，自動 drain、零遺失且 transient DLQ delta 為 0。

**實作與驗證：** 每個服務擁有自己的 CDA DB circuit 與穩定 listener ID；短期 retry
耗盡且確認為 JDBC／SQL connectivity failure 時 requeue 未 ACK delivery、停止本服務 CDA
consumer，再以 single-flight backoff＋jitter probe 與連續兩次成功判定恢復。Poison
message 的真實 RabbitMQ 測試確認會進 DLQ、不開 DB circuit。完整決策與證據見
[ADR-004](adr/ADR-004-cda-inbox-precommit-db-outage-recovery.zh-TW.md)與
[2026-09-17 REL-104 故障恢復報告](benchmarks/2026-09-17-rel104-db-outage-recovery.md)。

### EAP-REL-105：Order Saga timeout detector（warning-only）

**狀態：已完成（2026-09-17）。**

**原因：** queue 或 inbox 都可能沒有明顯 backlog，但訂單仍長時間停在
`PENDING_ASSET_CHECK`、`CANCELLING` 或其他非終止狀態。

**完成條件：**

- [x] 依 lifecycle state 與 last-progress time 找出 stuck Saga。
- [x] 產生 metric、告警與可查詢診斷資料。
- [x] 第一版不得自動取消、解鎖資產或捏造業務結果。

**實作與驗證：** Order 每 5 秒以 read-only `REPEATABLE_READ` snapshot 檢查
`PENDING_ASSET_CHECK`（預設 5 分鐘）與 `CANCELLING`（預設 10 分鐘）。有效狀態以
matching state 優先、stream head fallback，最後進度時間則使用 event append 同步推進的
stream-head timestamp；因此不會把 trade hot path 已推進的訂單誤報，也不會被技術性
matching-state upsert 洗掉卡住時間。Actuator 提供最多 100 筆最舊候選，metrics 保留精確
count／oldest age；refresh failure 保留 last-good values 並 fail closed。PostgreSQL 狀態矩陣、
future timestamp、bounded snapshot、partial-index plan 與 `promtool` alert tests 均通過。
完整設計見 [Order Saga Timeout Detector](order-saga-timeout-detector.zh-TW.md)。

### EAP-REL-106：最小 Failure Recovery Control Plane（完成）

**決策：** 已完成最小版本。它管理 transport／terminal debt，不代替 Order、Wallet、
Match 做業務判定，也不把 recovery endpoint 暴露成 LLM tool。

**MVP：**

- [x] 盤點並區分 `BROKER_DEAD_LETTER`、`INBOX_TERMINAL`、`OUTBOX_TERMINAL`、
  `CLEANUP_TERMINAL`、`SAGA_TIMEOUT`。
- [x] list／inspect source queue、routing key、payload、identity、attempt、first／last error。
- [x] transient／permanent／schema／identity／invariant／prerequisite／unknown 分類。
- [x] 只提供受保護的單筆 dry-run、rate-limited replay、park／resolve。
- [x] 保存 operator、reason、時間、attempt／redrive count、前後狀態與結果 audit。
- [x] 第一版不提供 bulk replay，也不 replay permanent／identity／invariant／unknown。

**實作與驗證：** `eap-mcp` 聚合三個 owner 的 recovery source API，但不直接修改 owner
schema。暫時性 terminal work 只會回到原 inbox／outbox／cleanup worker；三個服務各自用
`recovery_source_actions` 在同一筆 local transaction 保存 actionId 與結果，中央另保存
operator audit，處理 source 成功但 response 遺失的 crash window。shared `order.dlq` 在明確
啟用時採 persist-before-ACK quarantine；REL-106 基線只允許 inspect／park／resolve，REL-107
依 [ADR-006](adr/ADR-006-owner-aware-shared-dlq-replay.zh-TW.md) 新增 Wallet／Order
`TradeExecutedEvent` owner-aware conditional replay，其餘 broker case 仍 fail closed。共同
contract、中央 PostgreSQL quarantine／audit、Order／Wallet／Match replay policy 與 actionId
idempotency integration tests 均通過。完整說明見
[Failure Recovery Control Plane](failure-recovery-control-plane.zh-TW.md)與
[ADR-005](adr/ADR-005-failure-recovery-control-plane.zh-TW.md)。

後續再評估將 shared `order.dlq` 改成 per-consumer DLQ、direct/topic DLX、Rabbit
policy 與 quorum queue；這些 topology 變更不能和 control-plane API 一次混做。

### EAP-REL-107：系統化 failure-injection campaign

**狀態：R5 已完成；ticket 僅保留尚未支援的 route／全鏈範圍。**

**完成條件：**

- [x] DB outage、consumer crash、worker lease expiry、Redis outage。
- [x] duplicate、late／out-of-order、identity conflict，以及 component-level outbox
  confirm ambiguity。
- [x] 真實 broker confirm 與 local `SENT` 更新邊界的 Match process crash 注入；重啟後
  200 次 duplicate delivery 被 durable inbox 吸收，三服務 debt 歸零。
- [x] 真實 MCP replay publisher confirm 與 central audit completion 邊界的 process crash；
  同 actionId 重試為 attempt 2，兩次 broker delivery 最終只有一筆 Wallet settlement。
- [ ] 逐 consumer 補齊 DLQ redrive business-state preflight。Wallet／Order
  `TradeExecutedEvent` 已用 `x-death.queue`＋exact topology allowlist 證明 owner，並在
  dry-run／execute 查 owner-local durable state；Match 與 Order／Wallet 其他 queue 尚未開放。
- [x] 已執行案例都核對沒有 duplicate trade、重複資產異動、遺失工作或未追蹤 debt。

**R1 驗證（2026-09-18）：** Order／Wallet 與 Match 各自通過至少 60 秒 PostgreSQL
outage；Order／Wallet 在 1,000 筆事件發布途中同時 `SIGKILL` 後自動收斂；Match 在 Redis
重啟、`run_id` 改變後維持 `RECOVERING`，直到帶 generation／fence／watermark／manifest
的受控 activation 才套用 200 筆 durable inbox。Order 57、Wallet 52、Match 60 項
PostgreSQL／Redis integration tests，以及 Rabbit poison、outbox 與 recovery control focused
tests 全數通過。第一輪 DB run 另抓到 load harness 漏 purge release queue／漏 reset 新 inbox
以及 DB-only test 誤啟 outbox relay 的隔離問題；修正後重跑才列為有效 PASS。完整數字、命令與限制見
[REL-107 R1–R5 報告](benchmarks/2026-09-18-rel107-failure-injection-campaign.md)。

**R2 驗證（2026-09-18）：** `REL107_OUTBOX_CONFIRM_CRASH_R4` 在 Match relay 收到 200 筆
RabbitMQ publisher confirm、但 PostgreSQL outbox 尚未標記 `SENT` 時精準 `SIGKILL`。當下
Order／Wallet 已各完成 200 筆；重啟後 Match 重送全部事件，Wallet 記錄 200 次 duplicate，
但兩服務仍各只有 200 筆業務結果。Match outbox 最終 200 `SENT`／0 `FAILED`，Queue、DLQ
以及 Order／Wallet／Match durable debt 全為 0。候選 R1～R3 另抓到 projection prewarm、
Match/Redis reset 與 stale snapshot 三個 harness 問題；只有修正後的 R4 被採用。

**R3 驗證（2026-09-18）：** shared DLQ 第一條安全重播切片只開放 allowlisted transient
`wallet.tradeExecuted.queue`。Wallet 真實 PostgreSQL 驗證 `ELIGIBLE → ALREADY_DURABLE →
ALREADY_APPLIED` 與 payload conflict；MCP PostgreSQL 驗證同 messageId 在不同 consumer queue
不會覆蓋，以及 schema／unknown 不會出現 `REPLAY`；真實 RabbitMQ 驗證只 direct publish 到
owner queue、mandatory routing、correlated confirm 與 death-header stripping。Wallet 一般
test task 113 cases（37 個 integration cases 依 task 分流而 skipped）／54 PostgreSQL、MCP
一般 test task 18 cases（7 個 integration cases依 task 分流而 skipped）／6 PostgreSQL／
1 Rabbit 均為 0 failures／0 errors；分流案例另在 integration task 執行。尚未把其他
consumer 說成已支援。

**R4 驗證（2026-09-18）：** `run-rel107-mcp-replay-confirm-crash.sh` 使用真實 Rabbit
TTL／DLX 產生 broker-owned `x-death`，在 replay confirm 後、central action／disposition commit
前精準 `SIGKILL` MCP。crash 前後 action 都保持 `STARTED` attempt 1、case 保持 `OPEN`；
同 actionId 重試後成為 `APPLIED` attempt 2、case `RESOLVED`。Wallet consumer 停止期間 owner
queue 累積兩份 delivery；重啟後 duplicate metric 為 1，但 durable inbox、settlement 都只有
一筆，資產精確等於單次結算，Queue／DLQ 歸零。MCP 一般 test task 更新為 20 cases
（7 個 integration cases 分流 skipped），另有 6 PostgreSQL／1 Rabbit integration，全部
0 failures／0 errors。

**R5 驗證（2026-09-18）：** shared DLQ 再開放 exact transient
`order.tradeExecuted.queue + trade.exchange + trade.executed`。Order happy path 不一定寫 recovery
inbox，因此 preflight 以單一 SQL snapshot 同時核對 `order_trade_execution_inbox` 與
`order_trade_applications`：兩邊皆無才 `ELIGIBLE`，已 durable／applied 則 no-op，同 trade ID
不同 payload／Order-owned fact 一律 fail closed。MCP 依 route dispatch 到 Order source，並只
direct publish 回 Order queue。Order 一般 `213`（`58` skipped）／PostgreSQL `58`，MCP 一般
`23`（`9` skipped）／PostgreSQL `7`／Rabbit `2`，全部 0 failures／0 errors。R5 是
deterministic owner-state 與真實 transport evidence，不冒充第二次 process-crash campaign。

## P2：正確性穩定後再處理的能力

### EAP-PLAT-201：HTTP idempotency contract

- 由 client 提供穩定 idempotency key。
- DB commit 後 response 遺失時，可查回第一次結果而不是產生新的 sequence／timestamp
  payload conflict。

### EAP-MATCH-202：Redis order book durable rebuild

- 先完成 EAP-REL-101 的 fail-closed gate，再設計 durable open-order facts、rebuild
  checkpoint、generation 切換與驗證。
- 不把 PostgreSQL 做成每次撮合都同步鏡像 Redis 的第二本 order book。

### EAP-PERF-203：Order reservation-result／projection bottleneck

- 先量 stage timing、實際 batch size、oldest age 與 scheduler utilization。
- 再 A/B 比較 scheduler isolation、bounded partitioning、batch append／projection。
- 不以縮短 retry 或放寬 durable-debt gate 換取表面 TPS。

### EAP-OPS-204：Outbox／Inbox terminal recovery 能力對齊（完成於 REL-106）

- Order、Wallet、Match 與 Match cleanup 已使用共同 recovery contract 與 owner-side policy。
- 永久／identity／invariant failure 維持 fail closed，不因介面對齊而開放重播。

## P3：延後，不搶占目前主線

### EAP-TDA-301：TDA reliability parity

將 TDA 的 direct publish、缺少 durable inbox、失敗未發布 rejection、listener
swallow-and-ACK 與缺少完整 benchmark 視為一個獨立 epic。TDA 目前不是主要展示路線，
不逐個零碎修補。

### EAP-CQRS-302：Read replica

目前 CQRS 已完成邏輯上的 command／query model 分離，但沒有證據顯示讀流量正在壓垮
primary DB。等 query load、replication lag 與 read-your-write contract 明確後再做。

### EAP-SCALE-303：更進階的撮合擴展

包含 price-level FIFO 結構、多市場 partition、跨 instance single-writer ownership。
現行瓶頸仍主要在下游 Order 狀態鏈，現在重寫最高速的 Match hot path 價值不高。

### EAP-SEC-304：Production security perimeter

完整 authentication、authorization、API gateway、operator RBAC 與 secret management
很重要，但與目前交易一致性學習主線分開排程；任何 recovery control plane 上線前，
至少必須先有受保護的內部 API 與 operator identity。

## 建議執行順序

```text
REL-001 → REL-002 → REL-003
                     │
                     ├─ REL-101 → REL-102
                     ├─ REL-103 ✓ → REL-104 ✓ → REL-105 ✓ → REL-106 ✓
                     └─ REL-107（持續擴充 failure campaign）

以上每一條都由 REL-107 failure injection 驗證
完成後才進 PLAT-201／MATCH-202／PERF-203
TDA、read replica 與進階 scaling 保持延後
```

## 目前下一件事

**EAP-REL-001／002／003／101／102／103／104／105／106 已完成。REL-107 下一個缺口是：**
把已在 Wallet／Order trade 證明的 owner routing／business-state preflight 模式逐一擴充到其他 queue，
並依每條 route 的 owner state 定義可重播語意；broker-confirm 到中央 action completion 的
process-crash boundary 已用 Wallet route 驗證。任意 Redis full-book rebuild 仍留在 MATCH-202。
