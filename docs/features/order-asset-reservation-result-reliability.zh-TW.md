# Ticket：Order 驗資結果可靠性與技術失敗紀錄

> 狀態：Core implementation complete／operational follow-ups open
>
> 建立日期：2026-08-31
>
> 最近更新：2026-09-03

> 範圍：CDA Wallet `OrderAssetReservationSucceededEvent／OrderFailedEvent → Order lifecycle`。不包含 Wallet intake、Trade 與 Cancellation inbox 重構。

完整設計、資料表欄位、transaction、lease、retry 與 crash window 說明見 [Order 驗資結果：Durable Inbox、錯誤重試與 Crash Recovery](../order-asset-reservation-result-reliability.zh-TW.md)。

## Decision

Order 將 Wallet 的成功與拒絕視為同一個 `AssetReservationResult` 業務階段。兩種結果共用 `order_id` terminal guard，不再各自使用不同的 retry 行為。

技術錯誤不是業務失敗：DB timeout、lock、consumer crash 不得自行產生 `OrderFailedEvent` 或把訂單標成拒絕；它們保存為可重試的 processing debt。只有 Wallet 已 durable commit 的 `OrderFailedEvent` 才能讓 Order 進入 `REJECTED`。

## Implemented Baseline

### Durable processing record

新增 `order_service.order_asset_reservation_result_inbox`：

| 欄位 | 意義 |
| --- | --- |
| `order_id` | 唯一 business identity；同一訂單只能有一個 Wallet terminal result |
| `result_type` | `CONFIRMED` 或 `FAILED` |
| `payload`／`payload_hash`／`schema_version` | duplicate 與 identity conflict 判定 |
| `status` | `PENDING`、`IN_PROGRESS`、`APPLIED`、`FAILED_RETRYABLE`、`FAILED_PERMANENT` |
| `attempt_count`／`next_retry_at` | durable retry lifecycle |
| `claimed_by`／`claim_until` | worker lease、fencing 與 crash reclaim |
| `error_type`／`last_error` | 技術失敗分類與診斷 |
| conflict 欄位 | 保留 confirmed／failed 或 same-ID/different-payload 矛盾證據 |

Rabbit listener 現在只負責 deserialize、寫入 inbox，成功 commit 後才 ACK。相同 result replay 正常 ACK；identity conflict 先 durable 記錄再 ACK，不讓 poison event hot-loop。

### Crash-safe worker transaction

```text
PENDING／FAILED_RETRYABLE／expired IN_PROGRESS
    → FOR UPDATE SKIP LOCKED
    → IN_PROGRESS＋owner＋lease
    → append Order lifecycle event
    → mark inbox APPLIED
    → one orderConsumer transaction commit
```

- transaction commit 前 crash：domain event 與 `APPLIED` 一起 rollback。
- commit 後 crash：inbox 已是 `APPLIED`，不重做。
- claim 後 crash：lease 到期後由其他 worker 接手。
- domain append 已存在：deterministic event ID 吸收 duplicate，再把 inbox 收斂到 `APPLIED`。
- lease 在 transaction 中遺失：`markApplied` 失敗並 rollback domain append。

### Error policy

| 類別 | 例子 | 現行動作 |
| --- | --- | --- |
| Business result | `OrderFailedEvent` 的餘額／電量不足 | 正常 apply 為 `REJECTED`，inbox `APPLIED` |
| Transient database | Spring `DataAccessException` | `FAILED_RETRYABLE`，exponential backoff＋bounded jitter |
| Permanent identity | event ID／payload contradiction | `FAILED_PERMANENT`，不可自動 replay |
| Permanent state | aggregate version contradiction | `FAILED_PERMANENT`，要求一致性調查 |
| Unknown | 未分類 runtime exception | 有界 retry；budget 耗盡後 `FAILED_PERMANENT` |

預設 worker：poll 100 ms、batch 100、lease 30 秒、最多 20 attempts、250 ms 起始且最高 30 秒 backoff。realtime SSE notification 在 durable transaction 之後 best-effort 執行，失敗不會把已成功的業務 transaction 改回 retry。

### Recovery and observability

- `eap_order_asset_reservation_result_inbox_rows{status=...}` 暴露 actionable debt。
- `eap_order_asset_reservation_result_incident_rows{type="IDENTITY_CONFLICT"}` 暴露矛盾結果。
- Actuator endpoint `orderAssetReservationResultInbox` 預設關閉；啟用後可查 status count。
- Admin retry 只接受沒有 identity conflict 的 `FAILED_PERMANENT`；矛盾業務事實不可一鍵 replay。

## Verified Failure Windows

- listener 只有 durable inbox 成功後才 ACK。
- inbox unavailable 時 listener 不 ACK；交回 container retry。
- same ID／same payload 只留一筆 record。
- confirmed／failed conflict 在 apply 前成為 permanent debt。
- result 已 apply 後收到矛盾結果會保留 `APPLIED` 事實並另外記錄 incident，不假裝 rollback。
- expired worker lease 可由另一個 owner reclaim。
- lease lost 時 domain event append 與 inbox status 原子 rollback。

## Remaining Gaps

1. **Inbox commit 前 Order DB outage**：目前仍由 Spring Rabbit 3 attempts／DLQ 接住；需實作 consumer pause 或 Rabbit delayed retry，避免 60 秒 outage 變成大量 DLQ debt。
2. **Order Saga timeout detector**：尚未掃描長時間 `PENDING_ASSET_CHECK`、outbox `FAILED` 與 inbox debt。
3. **Outbox terminal recovery**：Order outbox 十次失敗後仍缺少完整 inspect／rate-limited replay／audit。
4. **Trade identity conflict**：既有 trade inbox 仍需補 same-ID/different-payload guard。
5. **Cancellation classification**：既有 cancellation inbox 仍需一致的 transient／permanent taxonomy 與 jitter。
6. **真實 process-kill test**：目前已驗證 transaction rollback 與 lease reclaim；仍需在 Rabbit＋PostgreSQL end-to-end 測試中直接 kill consumer JVM。

## Next Tasks

- [ ] OAR-201：實作 intake DB outage 的 consumer pause 或 delayed retry queue。
- [ ] OAR-202：新增 `PENDING_ASSET_CHECK` warning detector，不自動改變訂單狀態。
- [ ] OAR-203：補 oldest inbox age、outbox terminal 與 stuck Saga alert。
- [ ] OAR-204：建立受控 outbox／DLQ inspect、replay 與 audit。
- [ ] OAR-301：Rabbit＋PostgreSQL consumer kill／DB outage failure-injection campaign。
- [x] OAR-302：完成 current-worktree full-lifecycle correctness／throughput 回歸；最新版結果與 durable-debt gate 見 [2026-09-03 全鏈報告](../benchmarks/2026-09-03-current-version-full-chain.md)。

## Claim Boundary

目前可以說：

> Order 對 Wallet 驗資成功與拒絕建立統一 durable processing record，以 local transaction、business identity、lease worker、backoff／jitter 和 conflict quarantine 處理 duplicate 與 worker crash；但 inbox commit 前的長時間 DB outage、Saga timeout 與 terminal control plane 仍是明確後續工作。

目前不能說：

- 所有 Order consumer 都已有相同錯誤分類。
- 任何長時間 DB outage 都不需人工介入。
- Saga timeout 已能自動補償或取消訂單。
- 已達 exactly-once messaging。
