# Order 驗資結果：Durable Inbox、錯誤重試與 Crash Recovery

> 更新日期：2026-08-31
>
> 實作範圍：CDA 的 `OrderAssetReservationSucceededEvent／OrderFailedEvent → Order lifecycle`

> 對應追蹤：[Order 驗資結果可靠性 ticket](features/order-asset-reservation-result-reliability.zh-TW.md)

## 先說結論

這次不是替 `OrderAssetReservationSucceededEvent` 多加幾次 Rabbit retry，而是把「訊息曾經到過、目前處理到哪裡、失敗原因、誰正在處理、何時可以重試」變成 Order 自己擁有的 durable database fact。

改造後的核心保證是：

1. Rabbit message 只有在驗資結果已寫入 Order inbox 後才 ACK。
2. consumer 在 inbox commit 後、ACK 前 crash，redelivery 只會被判定為 duplicate。
3. worker claim 後 crash，lease 過期後其他 instance 可以接手。
4. Order lifecycle event 與 inbox `APPLIED` 在同一 transaction；不會只成功一半。
5. transient technical failure 有 durable retry state、exponential backoff 與 jitter。
6. 同一 order 同時出現 confirmed／failed 不會靜默覆蓋，而會留下 consistency incident。

這仍不是 exactly-once messaging。Rabbit 仍可能重送；我們保證的是相同業務效果安全地收斂一次，也就是 effectively-once business effect。

## 改造前的問題

Wallet 的兩種結果原本走不同處理方式。

### Confirmation

```text
OrderAssetReservationSucceededEvent
    → Order listener 直接 append domain event
    → 成功後 manual ACK
    → 失敗時 basicNack(requeue=true)
```

`requeue=true` 沒有 attempt budget、backoff 或 durable error record。Order DB outage 時，message 可能形成：

```text
consume → DB failure → immediate requeue → consume → DB failure → ...
```

資料可能因 event ID 冪等而沒有重複，但 Rabbit、consumer CPU、DB connection、log 仍會被 hot loop 放大。

### Rejection

```text
OrderFailedEvent
    → listener 直接 append failure domain event
    → exception 交給 Spring Rabbit retry
    → 約 3 attempts 後 DLQ
```

因此同一個 Wallet 驗資階段存在兩種互相矛盾的技術政策：confirmation 可能無限 requeue，rejection 則很快變成 DLQ 人工債務。

### Saga liveness

如果 Wallet 已形成結果，但 Order consumer 一直失敗，Order 可能永久停在 `PENDING_ASSET_CHECK`。Rabbit queue 或 DLQ 只能表示 transport 狀態，無法回答：

- Order 是否已 durable 收到結果？
- 結果是否尚未處理？
- 是暫時 DB 問題還是永久 identity conflict？
- 哪個 worker 正在處理？
- worker 是否已經死掉？

這就是新增 processing record 的原因。

## 改造後的流程

```text
Wallet outbox
    ↓
RabbitMQ
    ↓
Order reservation-result listener
    ↓
INSERT / duplicate / conflict detection
    ↓
order_asset_reservation_result_inbox commit
    ↓
ACK RabbitMQ
    ↓
lease worker claim
    ↓
Order consumer transaction
    ├─ append OrderAssetReservationConfirmedV1 或 FailedV1
    └─ inbox IN_PROGRESS → APPLIED
    ↓
commit
```

Rabbit listener 不再負責完整業務處理。它只做「可靠接收」；真正的 Order state transition 交由可恢復的 worker 執行。

這會把兩種時間尺度分開：

- Rabbit listener：短、快，只負責 durable intake。
- Inbox worker：可長期 retry，負責業務收斂。

## 新增的資料庫紀錄

新增 PostgreSQL table：

```text
order_service.order_asset_reservation_result_inbox
```

### Identity 與 payload

| 欄位 | 用途 |
| --- | --- |
| `order_id` | Primary key；一個 order 只能接受一個 Wallet terminal result |
| `result_type` | `CONFIRMED` 或 `FAILED` |
| `payload` | 保存收到的完整 event，供非同步 worker 重建輸入 |
| `payload_hash` | 判定安全 duplicate 或 same-ID/different-payload |
| `schema_version` | 未來 event schema 演進時的解碼依據 |

為什麼 primary key 使用 `order_id`，不是另外產生 inbox row ID？因為這個階段的業務不變量是：同一張訂單只能有一個 Wallet 驗資終止結果。如果 confirmed 和 failed 各有不同 row identity，資料庫可能同時接受兩者，直到 worker 才發現矛盾。以 `order_id` 作 primary key，可以在 intake boundary 就辨識衝突。

### Processing lifecycle

| 欄位 | 用途 |
| --- | --- |
| `status` | `PENDING`、`IN_PROGRESS`、`APPLIED`、`FAILED_RETRYABLE`、`FAILED_PERMANENT` |
| `attempt_count` | worker 已 claim 幾次，不等同 Rabbit delivery count |
| `next_retry_at` | 何時才可重新處理，避免 busy loop |
| `claimed_by` | 本次擁有 lease 的 worker instance |
| `claim_until` | lease 期限；worker crash 後的接手機制 |
| `received_at` | Order 首次 durable 收到結果的時間 |
| `applied_at` | Order lifecycle 已完成的時間 |
| `updated_at` | retry／lease／terminal state 最近更新時間 |

狀態轉移：

```text
PENDING
  → IN_PROGRESS
      → APPLIED
      → FAILED_RETRYABLE → IN_PROGRESS
      → FAILED_PERMANENT

expired IN_PROGRESS
  → IN_PROGRESS by another worker
```

`IN_PROGRESS` 不是永久鎖。只有 `claimed_by` 符合、且 lease 尚由該 worker 擁有時，worker 才能完成或重排這筆工作；這是簡化的 fencing。

### Error 與 conflict evidence

| 欄位 | 用途 |
| --- | --- |
| `error_type` | 機器可聚合的 failure category |
| `last_error` | 截斷後的 exception 診斷內容 |
| `conflict_detected_at` | 發現 contradictory result 的時間 |
| `conflicting_result_type` | 衝突輸入是 confirmed 還是 failed |
| `conflicting_payload` | 保存衝突證據，不覆寫第一個 authority payload |

如果第一個 result 尚未 apply，就將 row 標為 `FAILED_PERMANENT`，避免任選一個結果套用。

如果第一個 result 已經 `APPLIED`，後來才收到矛盾 event：

- 保留原本 `APPLIED`，因為已提交的事實不能假裝 rollback。
- 額外保存 conflict incident。
- 不自動 replay conflicting message。
- 要由 verifier／operator 查明為何 Wallet 產生兩個 terminal facts。

## Listener 為什麼先寫 Inbox 再 ACK

ACK 是 transport responsibility 的轉移點。

Rabbit ACK 前，RabbitMQ 還負責保存 message。如果 Order crash 或 DB 寫入失敗，不應 ACK，讓 broker 可以 redeliver。Inbox commit 後，Order 已有自己的 durable copy，可以 ACK Rabbit；後續即使 Rabbit message 消失，Order worker 仍能靠 database record 繼續處理。

| Crash 時點 | 結果 |
| --- | --- |
| Inbox insert 前 | 沒有 ACK；Rabbit redelivery |
| Inbox transaction 中 | DB rollback；沒有 ACK；Rabbit redelivery |
| Inbox commit 後、ACK 前 | Rabbit redelivery；相同 hash 判為 duplicate |
| ACK 後、worker claim 前 | Inbox 保留 `PENDING`；worker稍後處理 |

因此 ACK 不代表 business complete，只代表 Order 已接受這筆訊息的持久化處理責任。

## Lease Worker 如何處理 Crash

Worker 用一個短 transaction claim 到期工作：

```sql
SELECT ...
FOR UPDATE SKIP LOCKED
```

然後更新：

```text
status = IN_PROGRESS
claimed_by = worker UUID
claim_until = now + 30 seconds
attempt_count = attempt_count + 1
```

多個 Order instance 可以同時掃描 inbox：第一個 worker 鎖到的 row 不會讓第二個 worker等待；第二個 worker跳過它，處理下一筆。這使 worker 可水平擴張，不需要全域 scheduler lock。

Worker claim 後死亡時，row 暫留 `IN_PROGRESS`。`claim_until` 到期後，新的 worker 可以取得 owner 並繼續。如果只有 boolean `processing=true` 而沒有 lease，worker 死亡後 row 會永久卡住。

## Order Event 與 Inbox APPLIED 的單一 Transaction

Worker 的關鍵 transaction 包含：

```text
append Order lifecycle domain event
+
update inbox status to APPLIED with owner fencing
```

兩個操作使用 `orderConsumerTransactionManager` 與同一 consumer data source。

如果分成兩次 commit，可能出現 domain event 成功但 inbox 仍是 `IN_PROGRESS`，或 inbox 先標 `APPLIED` 但 domain event 失敗。現在 `markApplied` 必須同時符合：

```text
order_id match
status = IN_PROGRESS
claimed_by = current worker
```

若 update row count 不是 1，就丟 exception，讓 domain event append 一起 rollback。

| Worker crash 時點 | Transaction 結果 | 恢復方式 |
| --- | --- | --- |
| claim commit 前 | claim rollback | 其他 worker 可 claim |
| claim commit 後、domain tx 前 | row 暫留 `IN_PROGRESS` | lease expiry reclaim |
| domain event append 後、commit 前 | event 與 `APPLIED` rollback | lease expiry後重做 |
| domain tx commit 後 | event 與 `APPLIED` 都成立 | 不需重做 |
| commit response 不明 | DB state 是唯一判定 | `APPLIED` 或 deterministic event ID 收斂 |

## Duplicate 與 Identity Conflict

安全 duplicate 是相同 `order_id`、相同 `result_type`、相同 `payload_hash`。Listener 正常 ACK，不增加第二筆 row，也不再 append 第二個 domain event。

Identity conflict 是相同 `order_id`，但 `result_type` 或 `payload_hash` 不同。這不是 transient failure，重試不會讓兩份資料自行一致，所以直接記錄 `IDENTITY_CONFLICT`。

設計原則是：冪等不能只問「ID 是否看過」，還要問「相同 ID 是否代表相同不可變事實」。

## 技術錯誤如何分類與重試

| 類別 | 範例 | 處理 |
| --- | --- | --- |
| Business result | Wallet 已決定餘額／電量不足 | 正常 append rejection，inbox `APPLIED` |
| Transient database | connection reset、lock、timeout、DB restart | rollback，`FAILED_RETRYABLE`，排定下次時間 |
| Permanent identity | event ID 或 payload contradiction | `FAILED_PERMANENT`，不自動 retry |
| Permanent state | aggregate 已進入互斥狀態 | `FAILED_PERMANENT`，一致性調查 |
| Unknown | 尚未分類的 runtime exception | bounded retry；20 attempts 後 terminal debt |

未知 exception 不能第一次就永久判死，也不能無限 retry。它先得到短暫自癒機會，最後一定形成可觀測的 `RETRY_EXHAUSTED_UNKNOWN_RETRYABLE`。

## Backoff 與 Jitter

基本 backoff：

```text
250 ms → 500 ms → 1 s → 2 s → 4 s ... → capped at 30 s
```

每次再加入 bounded jitter，大約落在 base 的一半到 base 之間。

Backoff 避免 DB 已失敗時立即反覆增加 connection 與 lock 壓力。Jitter 則避免大量 row 在同一秒失敗後，每次都在同一秒醒來形成 synchronized retry wave。

Worker thread 不長時間 `sleep`。重試時間寫在 `next_retry_at`，scheduler 只 claim 已到期的 row。

## 每筆事件增加哪些 DB 成本

改造後 happy path 增加：

1. Listener `INSERT inbox`。
2. Worker claim update。
3. Domain event append transaction中的 `APPLIED` update。
4. Inbox retry index 維護。

成本換來 ACK 後恢復、worker crash 接手、可查 retry state、confirmed／failed conflict 稽核，以及移除 Rabbit hot requeue。

效能報告必須分開量測 Rabbit intake ACK TPS、Inbox completion TPS、oldest pending age 與 full-lifecycle completion TPS。不能把「訊息快速寫進 inbox」宣稱成「訂單已完成驗資」。

## Observability 與人工 Recovery

新增 metrics：

```text
eap_order_asset_reservation_result_inbox_rows{status="PENDING"}
eap_order_asset_reservation_result_inbox_rows{status="IN_PROGRESS"}
eap_order_asset_reservation_result_inbox_rows{status="FAILED_RETRYABLE"}
eap_order_asset_reservation_result_inbox_rows{status="FAILED_PERMANENT"}
eap_order_asset_reservation_result_incident_rows{type="IDENTITY_CONFLICT"}
```

Actuator endpoint `orderAssetReservationResultInbox` 預設關閉。啟用後可查 status count，並對沒有 identity conflict 的 permanent technical debt 做明確 retry。

Identity conflict 不允許一鍵 retry，因為 operator 必須先決定哪個事實正確，避免 recovery control plane 變成「把所有錯誤再送一次」的按鈕。

## 這次解決了什麼

| 問題 | 改造後 |
| --- | --- |
| Confirmation apply 失敗無限 immediate requeue | 移除；processing failure 進 durable retry state |
| Confirmed／Failed 使用不同錯誤政策 | 共用同一 inbox、worker 與 terminal guard |
| Consumer commit 後、ACK 前 crash | redelivery 被 payload hash 判為 duplicate |
| Worker claim 後 crash | lease expiry 後自動 reclaim |
| Domain event 與 processing record 半套 commit | 同一 consumer transaction rollback／commit |
| DB 暫時錯誤 | durable retry、backoff、jitter |
| 同 order 出現兩種結果 | 保存 permanent consistency incident |
| 技術錯誤只存在 log | status、attempt、error、payload 都可查 |
| Permanent debt 不可操作 | 預設關閉的受控 Actuator retry operation |

## 這次不能解決什麼

### Inbox commit 前的 DB outage

如果 Order DB 完全不可用，listener 連 inbox 都寫不進去。此時訊息仍由 Rabbit 持有，但目前 Spring listener 約三次後會進 DLQ。

Durable inbox 只能保護「已成功進 inbox」之後的生命週期，不能解決 inbox 自己不可用的窗口。下一步需選擇 pause consumer container，或使用 Rabbit delayed retry queue，避免 immediate requeue 與快速 DLQ。

### Saga timeout

Order 還沒有定期找出長時間 `PENDING_ASSET_CHECK` 的 detector。Inbox 增加了診斷事實，但 detector 與 status protocol 尚未完成。

第一版 detector 應只告警，不直接把訂單改成 failed，更不能直接要求 Wallet 解鎖；confirmation 可能已經送到 MatchEngine 並成交。

### 其他 consumer

Trade 與 Cancellation 各有自己的 inbox contract，但沒有因此自動共用這張表的 payload conflict、error taxonomy 與 jitter。這份文件完成後，Wallet reservation／cancellation 與 Match admission 也分別加入了各自 bounded context 擁有的 durable inbox；它們是後續獨立實作，不是 Order inbox 自動提供的跨服務保證。現況請搭配 [Wallet inbox](wallet-inbox-and-cancellation-completion.zh-TW.md) 與 [Match admission inbox](match-order-admission-inbox.zh-TW.md) 閱讀。

### Distributed transaction

Order inbox transaction 只涵蓋 Order database，不能和 Wallet、MatchEngine 或 RabbitMQ 形成單一 ACID transaction。跨服務仍靠 outbox、at-least-once、idempotency、retry、reconciliation 與 Saga deadline 收斂。

## 驗證證據

已加入自動測試：

- Listener 必須在 inbox durable 成功後才 ACK。
- Inbox unavailable 時不得 ACK。
- malformed confirmation 不 requeue。
- confirmed／failed 使用同一 inbox。
- transient failure 寫 durable retry 與 backoff。
- permanent identity conflict 不進無意義 retry。
- retry budget 耗盡形成 permanent debt。
- same-ID/same-payload duplicate。
- confirmed／failed conflict 前後兩種 crash window。
- expired lease 被其他 worker reclaim。
- lease lost 使 domain event append rollback。
- domain event 與 inbox `APPLIED` 一起 commit。

驗證命令：

```bash
cd eap-order
./gradlew --no-daemon test
./gradlew --no-daemon postgresIntegrationTest
```

2026-09-03 全鏈長窗進一步證明這張 inbox 同時是 reliability 控制與效能容量的一部分：200 orders/s
時最大 non-`APPLIED` backlog 為 791、穩態 slope `+0.0035/s`；300／400 則累積至少
51K／53K，即使 Rabbit queue 為 0 且所有資料最後收斂，也必須拒絕為完整系統持續容量。
詳見[最新全鏈報告](benchmarks/2026-09-03-current-version-full-chain.md)。

## 面試時可以怎麼說

> 我原本的 Order confirmation consumer 在失敗時直接 Rabbit requeue，資料雖然靠 event ID 冪等，但 DB outage 會形成 hot loop，而且 confirmed 和 failed 的 retry policy 不一致。後來我把 Wallet 驗資結果建成 Order-owned durable inbox：listener 只在 inbox commit 後 ACK，worker 用 `SKIP LOCKED` 和 lease claim；Order domain event 與 inbox `APPLIED` 在同一 transaction，lost lease 就整筆 rollback。Transient DB error 走有 jitter 的 backoff，identity conflict 直接 quarantine。這不是 exactly-once，而是用 at-least-once delivery 加上 durable processing state，做到可恢復且 effectively-once 的業務效果。
