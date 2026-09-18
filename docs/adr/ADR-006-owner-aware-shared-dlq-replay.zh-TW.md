# ADR-006：Shared DLQ 的 owner-aware 條件式重播

> Ticket：EAP-REL-107
>
> 狀態：Accepted（Wallet／Order TradeExecuted vertical slices）
>
> 日期：2026-09-18

## 背景

REL-106 先把 shared `order.dlq` 內容 persist-before-ACK 搬進 PostgreSQL quarantine，但當時
只允許 inspect、park、resolve。問題不是 RabbitMQ 能不能把 body 再送一次，而是中央工具若
無法證明是哪一個 consumer 失敗、目前業務狀態是否仍允許執行，就可能讓已成功的其他
consumer 重複收到事件，甚至重複結算。

本 ADR 不一次開放所有 dead letter。第一個可驗證切片處理
`wallet.tradeExecuted.queue` 的暫時性失敗；第二個切片沿用同一安全邊界，加入
`order.tradeExecuted.queue`，其他 route 仍維持 fail closed。

## 決策

### 1. 暫時保留 shared DLQ topology

本次不把既有 fanout `order.dlx` 改成 direct exchange，也不重新宣告所有 production queue。
RabbitMQ 不允許用不同 type／arguments 直接覆蓋既有 exchange／queue；安全遷移需要版本化
topology 與 rollout，不能和 recovery policy 混成同一個變更。

### 2. Owner 來自 broker evidence 與 allowlist，不解析 payload 猜測

Control plane 只接受 broker `x-death` 中的原始 queue，並同時核對固定 registry 裡的
queue、exchange、routing key：

| source queue | original exchange | routing key | owner | work |
|---|---|---|---|---|
| `wallet.tradeExecuted.queue` | `trade.exchange` | `trade.executed` | Wallet | `TradeExecutedEvent` |
| `order.tradeExecuted.queue` | `trade.exchange` | `trade.executed` | Order | `TradeExecutedEvent` |

三個欄位任一不符、route 未登錄，或 failure class 不是明確的 `TRANSIENT`，都不提供
`REPLAY`。schema、identity、invariant、permanent、unknown 仍只能 park／resolve。

Broker case identity 改為 `sourceQueue + messageId`。同一個 fanout message 若在 Order 與
Wallet 各自失敗，必須是兩個獨立 recovery case，不能因共用 messageId 而互相覆蓋。

### 3. Owner 在 dry-run 與 execute 都做 business-state preflight

MCP 依 allowlist 的 owner 以 source token 呼叫 Wallet 或 Order。Owner 都先驗證自己真正使用的
payload 欄位，再檢查本地 durable state；中央工具不替 bounded context 猜業務完成狀態。

Wallet 用與正常 listener 相同的 canonical serialization／payload hash 查 durable inbox：

| Wallet 狀態 | 決策 | Broker publish |
|---|---|---:|
| 沒有 inbox row，payload 合法 | `ELIGIBLE` | 是 |
| `PENDING`／`IN_PROGRESS`／`FAILED_RETRYABLE` 且 payload 相同 | `ALREADY_DURABLE` | 否 |
| `APPLIED` 且 payload 相同 | `ALREADY_APPLIED` | 否 |
| 相同 trade ID、不同 payload 或 conflict evidence | `IDENTITY_CONFLICT` | 否 |
| `FAILED_PERMANENT` | `PERMANENT_FAILURE` | 否 |
| payload／route 不合法 | `INVALID_PAYLOAD`／`UNSUPPORTED_ROUTE` | 否 |

Order 的正常 happy path 會直接寫 `order_trade_applications`，只有 projection lag 或處理失敗
才寫 `order_trade_execution_inbox`，因此不能照搬「沒 inbox 就可以 replay」：

| Order 狀態 | 決策 | Broker publish |
|---|---|---:|
| inbox 與 application 都不存在，payload 合法 | `ELIGIBLE` | 是 |
| `RECEIVED`／`PENDING_PREREQUISITE`／`IN_PROGRESS`／`FAILED_RETRYABLE`，完整 inbox payload 相同 | `ALREADY_DURABLE` | 否 |
| `order_trade_applications` 的 buyer／seller order、price、quantity、appliedAt 都相同 | `ALREADY_APPLIED` | 否 |
| 相同 trade ID 但 inbox payload 或 Order-owned application fact 不同 | `IDENTITY_CONFLICT` | 否 |
| `FAILED_PERMANENT`，或 inbox 宣稱 `APPLIED` 卻沒有 application | `PERMANENT_FAILURE` | 否 |

Order 要求 `occurredAt` 存在，因為它是已套用成交 identity 的一部分。Order 不驗證 Wallet
專屬的 user／balance 欄位；這不是放寬安全，而是讓每個 bounded context 只對自己持久化與
使用的事實負責。兩張表以單一 SQL statement 讀取快照，不新增第二份正常路徑資料。

Execute 不能沿用稍早的 dry-run 結果；它必須重新檢查 fingerprint、control-plane disposition
與 owner 當下狀態。這降低 TOCTOU 風險，但不宣稱是 distributed lock。

### 4. 重播直接送 owner queue，不回送原 topic exchange

通過 preflight 後，MCP 用 RabbitMQ default exchange 直接把原始 bytes 發到
對應的 `wallet.tradeExecuted.queue` 或 `order.tradeExecuted.queue`。若回送
`trade.exchange`，另一個已成功的 consumer 也會再收到一次，無端放大 duplicate 與耦合。

重播訊息保留安全的 application／trace headers，移除 `x-death`、exception 與既有 recovery
headers，再加入 case ID、action ID 與 redrive 標記。訊息使用 persistent delivery、mandatory
routing 與 correlated publisher confirm；return、nack、timeout 都讓 action 保持失敗／OPEN，
不得標成成功。

### 5. 仍然是 at-least-once recovery

publisher confirm 成功到中央 action audit 完成之間仍有 crash window。相同 actionId 在中央
完成後可回傳原結果；若 crash 發生在結果落盤前，仍可能再 publish 一次。因此 correctness
最後依賴 owner 的本地冪等邊界：Wallet durable inbox 的 trade ID＋payload identity，或
Order 的 trade application／recovery inbox，而不是假裝 recovery 是 exactly-once。

## 已驗證

- Wallet unit tests：合法、格式錯誤、route mismatch、durable、applied、identity conflict。
- Wallet PostgreSQL integration：`ELIGIBLE → ALREADY_DURABLE → ALREADY_APPLIED` 真實狀態轉換，
  以及同 trade ID 不同 payload 的拒絕。
- MCP PostgreSQL integration：allowlisted transient route 才出現 `REPLAY`、schema failure
  fail closed、同 messageId 不同 consumer 產生不同 case。
- 真實 RabbitMQ integration：direct-to-owner queue、persistent message、publisher confirm、
  recovery headers 與 death-header stripping。
- 真實 process-crash campaign：publisher confirm 後、central action/disposition commit 前
  `SIGKILL` MCP；同 actionId 重試由 attempt 1 收斂到 attempt 2。Wallet listener 關閉期間
  owner queue 累積兩份 at-least-once delivery，重啟後仍只有一筆 inbox 與一筆 settlement。
- Order unit／PostgreSQL integration：payload／route validation、missing／durable／applied／
  identity conflict／permanent 判斷，以及 inbox 與 application 的真實資料庫快照。
- MCP owner dispatch：Order dead letter 只呼叫 Order preflight，並以真實 RabbitMQ direct publish
  到 Order queue；Wallet queue 不會收到該次重播。

## 限制與後續

- 目前只有 Wallet／Order 的 `TradeExecutedEvent`，不是「shared DLQ 已全面自動恢復」。
- Match 與 Order／Wallet 其他 queue 必須逐一定義 owner preflight 與業務完成語意，不能只加入
  registry 就算完成。
- production RBAC／雙人 approval、bulk replay、跨 instance quota 仍不在本 ADR 範圍。
- 是否遷移到 per-consumer DLQ 是後續 operational topology 決策；現在的嚴格 registry 已能
  安全支援小範圍 vertical slice，但不取代長期 topology 評估。

## 被拒絕的方案

- **依 event class／JSON 欄位猜 owner：** payload 可損壞、契約可重疊，且不能證明是哪條
  consumer queue 失敗。
- **回送原 exchange：** 會讓已成功 consumer 一起重收。
- **看到 transient 字樣就自動重播：** error string 不是業務授權，仍需 exact route 與 owner
  preflight。
- **已在 inbox 就再送一次：** durable worker 已擁有 retry；重送只增加噪音與 poison loop。
