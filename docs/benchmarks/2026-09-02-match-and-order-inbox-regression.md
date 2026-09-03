# Match／Order Durable Inbox 全鏈回歸與 Order Retry 改善 - 2026-09-02

> Historical checkpoint：這是短窗 staircase 與 Order trade-prerequisite 改善證據。Order reservation-result worker、雙狀態與 query projection 納入後的目前版本，請看 [2026-09-03 最新全鏈報告](2026-09-03-current-version-full-chain.md)；本頁的短窗 400 pass 不是目前長窗容量。

## Decision

目前三服務可靠性改動通過短窗全鏈 correctness gate；Order `TradeExecuted` retry 的 ready-only claim 也有可量測的改善，但尚未把 current worktree 的通過邊界推過 `500 orders/s`。

- 相同 seed、相同 `10s warm-up + 30s measurement` staircase 中，`400 orders/s` 通過，完成 `199.96 trades/s`。
- `500 orders/s` 從基準 `181.87 trades/s` 提升到 `218.67 trades/s`，增加 `20.2%`，但只達目標的 `87.47%`，低於 `95%` gate，因此仍判定失敗。
- 最終 `56,000` HTTP orders 全數接受並收斂為 `28,000` 組完全相同的 MatchEngine／Order／Wallet trade IDs；資產、order book、reservation、Rabbit queue、unacked 與 DLQ debt 全部歸零。
- 這是 dirty-worktree、單機、每階 30 秒的 diagnostic evidence，不是 release-pinned 或長時間 capacity claim。現行短窗 diagnostic passing point 仍是 `400 orders/s`。

## Comparable A/B

兩輪皆使用 `http-matched-staircase-chain`、shuffled arrival、seed `20260804`、每階 10 秒 warm-up 與 30 秒 measurement。

| Run | Order retry 設計 | 400 orders/s | 500 orders/s | 判定 |
| --- | --- | ---: | ---: | --- |
| `MATCH_INBOX_STAIRCASE_200_600_20260902_R1` | 原始逐筆 retry | `198.47 trades/s` | `181.87 trades/s` | 400 pass／500 fail |
| `MATCH_INBOX_STAIRCASE_READY_CLAIM_200_600_20260902_R5` | ready-only claim＋批次套用 | `199.96 trades/s` | `218.67 trades/s` | 400 pass／500 fail |

Order 的 Match→durable trade application p95 從 `10,314 ms` 降到 `4,471 ms`，p99 從 `10,725 ms` 降到 `4,643 ms`。相同 56,000-order workload 中，Order PostgreSQL commit delta 從 `287,230` 降為 `200,098`，WAL bytes 從約 `398.3 MB` 降為 `374.2 MB`。Wallet p95 維持約 `113 ms`，因此目前剩餘 full-chain lag 仍在 Order。

## 為什麼「沒有故障」仍會進入 Order Inbox

必須區分兩種經常都被口語稱為 retry 的機制：

| 機制 | 觸發原因 | 是否屬於本輪正常流量 |
| --- | --- | --- |
| `FAILED_RETRYABLE` technical retry | DB outage、lock timeout、network／broker 等暫時性技術故障 | 否；本輪沒有這類 failure debt，也沒有 retry exhaustion |
| `PENDING_PREREQUISITE` deferred coordination | 同一個業務流程經過不同 Rabbit queues，後來的 `TradeExecutedEvent` 可能比 Order 自己的 reservation-confirmation state 更早抵達 | 是；這是非同步 choreography 可預期的正常亂序，不代表服務故障 |

OrderAssetReservationSucceeded 會分別送往 Order 與 MatchEngine。兩個 consumer queue 各自有順序，但 RabbitMQ 不保證 Order queue 與 Match queue 之間的全域先後。MatchEngine 可能先完成 admission、撮合並發布 `TradeExecutedEvent`，此時 Order 尚未把自己的 confirmation 寫入 `order_matching_state`。Order 不能丟掉 trade，也不能在 prerequisite 不完整時硬套用，所以先 durable 保存，等 command state ready 後再處理。

R5 的量測可直接證明這不是只有錯誤注入才會走到的冷路徑：`28,000` 筆最終 trades 中，`25,746` 筆曾進入 Order trade inbox，占 `91.95%`；這些 row 的 min／max attempt 都是 `2`，表示第一次保存、第二次 ready 後成功，沒有反覆技術失敗。因此本次改善影響的是正常跨 queue 協調與批次成本，不是調低 DB failure retry 次數來換 TPS。

## 採用的改善

原本 Rabbit batch 若遇到某一筆 Order command state 尚未建立，可能先逐筆套用前段交易，再把整批寫成 `PENDING_PREREQUISITE`。reconciler 之後會重做大量已套用或仍未 ready 的 row，破壞 batch fast path 並增加 DB transaction。

本次採用以下行為：

1. batch 發現 `MISSING_HEAD` 時不再部分逐筆套用，整批先進 durable inbox。
2. `PENDING_PREREQUISITE` 只有在 buyer／seller `order_matching_state` 都存在、狀態可撮合且 remaining amount 足夠時才可被 claim；未 ready 的 row 安靜等待，不製造 retry storm。
3. 若 crash 發生在 trade application commit 後、inbox 標記前，worker 會依完整 trade identity 將已存在的 application 收斂成 `APPLIED`。
4. ready rows 使用既有 Order batch append，一次更新 claimed inbox rows 為 `APPLIED`。
5. 永久矛盾或未知技術錯誤才逐筆隔離，避免 poison event 阻塞整批；技術 retry 的 attempt 上限與 exponential backoff 保持不變。

## 被拒絕的實驗

| Run | 實驗 | 結果 | 決策 |
| --- | --- | --- | --- |
| `...BATCH_RETRY...R2` | 只把 reconciler 改成 batch | 500 為 `180.71 trades/s` | 無改善；batch 混入部分已套用 row |
| `...ATOMIC_RETRY...R3` | missing prerequisite 整批延後，但沿用長 backoff | 500 為 `131.03 trades/s` | backoff 放大跨 queue 排序延遲 |
| `...PREREQ_BACKOFF...R4` | prerequisite 改為高頻短 backoff | 400 即降為 `73.43 trades/s` | retry storm 反向拖慢 confirmation；拒絕 |

這三輪只用來排除假設，不可當作容量結果。最終保留的是 R5 的 ready-only claim，不是更積極的輪詢。

## Correctness Evidence

R5 最終狀態：

- `56,000 / 56,000` HTTP accepted；0 個 429、503 與 other failure。
- Match admission inbox `56,000 APPLIED / 0 non-APPLIED`。
- MatchEngine／Order／Wallet 各 `28,000` trades，trade-ID fingerprint 完全一致。
- Order trade inbox `25,746 APPLIED`，min／max attempt 都是 `2`，無 retry／permanent debt。
- buyer／seller locked balance 都是 `0`，最終資產 delta 精確。
- remaining BUY／SELL orders、active Match reservations、Rabbit ready／unacked、DLQ 全部是 `0`。
- RabbitMQ 無 memory／disk alarm；服務 log 沒有 runtime error 或 retry exhaustion。

## Verification

- 完整 `eap-order test`：通過。
- `OrderTradeExecutedInboxPostgresIT` 對隔離 PostgreSQL：通過，涵蓋 prerequisite 未 ready 不可 claim、ready 後 lease、重排、重複 claim 阻擋與 APPLIED。
- 相同條件 full-chain staircase R5：最終 correctness gates 全部通過。

## Next Measurement

不要再以縮短 backoff 猜測效能。下一個瓶頸是 Match 已持久化交易後，Order confirmation command state 仍比 Wallet／Match 落後；R5 的 Match→Order p95 仍有 `4.47s`。後續應先量測 `OrderAssetReservationSucceededEvent` 的 receive→matching-state commit age、實際 batch size 與跨 queue skew，再評估 confirmation listener batching、由 prerequisite state commit 主動喚醒 inbox，或分片 worker。任何候選仍須用相同 seed A/B 與完整 correctness gate 驗證。
