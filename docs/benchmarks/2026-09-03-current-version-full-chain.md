# 最新可靠性版本全鏈 k6 長窗驗證 - 2026-09-03

## 結論

目前 worktree 在新增 Order、Wallet、MatchEngine durable inbox、明確事件命名、Order 雙狀態與查詢 projection 修正後，完整 CDA 混合 HTTP 流程的**單一 seed 診斷下界是 `200 orders/s`，即 `100 completed trades/s`**。`300` 與 `400 orders/s` 都會讓 Order 的 reservation-result durable inbox 在穩態累積，因此不能稱為完整系統可持續容量。

三個速率的所有已接受訂單最後都正確收斂，沒有交易遺失、重複成交、資產差異或永久債務。失敗的是 liveness／capacity，不是 safety。這是 dirty-worktree、同機、單一 seed 的 diagnostic evidence；`capacityClaimAllowed=false`，不是 production SLA，也不取代舊 commits 的 release-pinned `648 orders/s` 歷史證據。

## 測試合約

| 項目 | 設定 |
| --- | --- |
| Contract | `external-http-matched-steady-state-chain` |
| Driver | k6 open-loop；有限、checksummed、shuffled BUY／SELL schedule |
| Warm-up／measurement | `60s + 900s` |
| Host | Apple Silicon arm64、10 logical CPUs、16 GiB RAM；driver 與服務同機 |
| Runtime | 三個 Spring Boot service、三個 PostgreSQL、RabbitMQ、Redis |
| 完成條件 | Match／Order／Wallet trade ID 完全相同、資產核對、order book／reservation／queue／DLQ 清空、Order query projection 追平 |
| 新增穩態條件 | RabbitMQ backlog 與 Order reservation-result inbox backlog 分開計算 level／slope |

PostgreSQL load-test profile 使用 `synchronous_commit=off`，來源未提交且 driver 同機，因此數字只用於本機版本回歸與瓶頸定位。

## 結果

| Target | HTTP accepted | Steady trades/s | Target ratio | Rabbit max／slope | Order inbox max／slope | k6 p95／p99 | 判定 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 400 orders/s | `384000/384000` | `187.75` | `93.88%` | `369 / +0.0083/s` | observed `>=53231` | `20.18 / 76.65 ms` | Reject：trade completion 與 Order inbox 都跟不上 |
| 300 orders/s | `288000/288000` | `149.70` | `99.80%` | `195 / -0.0078/s` | observed `>=51007` | `25.12 / 115.99 ms` | Reject：trade path 跟上，但完整狀態鏈持續積壓 |
| 200 orders/s | `192000/192000` | `100.00` | `100.00%` | `123 / -0.0011/s` | `791 / +0.0035/s` | `15.89 / 74.98 ms` | Pass：新版完整 gate 的單一 seed 診斷下界 |

400 與 300 是加入新 inbox gate 前執行；當時 runner 只把 RabbitMQ ready／unacked 視為穩態 backlog。測試期間直接查 Order DB，分別觀察到至少 53,231 與 51,007 筆 non-`APPLIED` inbox debt。300 的舊版 result JSON 因此雖寫著 `validForSustainedCapacity=true`，本報告明確推翻該判定。200 是補完 instrumentation 後的第一輪結果，其 JSON 已直接包含 inbox start／end／maximum／slope 與相應失敗 gate。

## 200 orders/s 正確性

- k6 `192000` requests、100% HTTP success、0 dropped iterations、0 out-of-range iterations。
- MatchEngine／Order／Wallet 各 `96000` 筆 durable trades，trade-ID fingerprint 完全一致。
- `192000` 筆 Order submission、Wallet reservation、Order reservation confirmation 與 Match admission inbox 全數完成。
- `orders_current=192000`；reservation `SUCCEEDED=192000`；user-visible matched rows `192000`。
- projection checkpoint 與 event-store max position 都是 `384000`，lag `0`。
- buyer／seller locked currency 與 energy 都是 `0`，available balance delta 精確。
- remaining BUY／SELL、Match reservation、Rabbit ready／unacked 與 DLQ 全為 `0`。
- full convergence `967.436s`，完整生命週期 `99.23 trades/s`。

## 找到的量測盲點

Rabbit queue 清空只代表 broker 已把訊息交給 consumer。Order listener 可以先把事件持久化到 `order_asset_reservation_result_inbox` 後 ACK，真正的 Order lifecycle event 與 query state 再由 lease worker 套用。因此 Rabbit backlog 為 0 時，服務內仍可能有數萬筆 durable work。

這次把 runner 改成每秒同時查詢：

```text
RabbitMQ ready + unacked
Order reservation-result inbox where status != APPLIED
Match / Order / Wallet durable trade counts
```

兩種 backlog 各自計算 start、end、maximum 與 linear-regression slope；任何一種明顯成長或超過上限，容量結果都被拒絕。這項修正不改業務邏輯，只修正「什麼叫系統跟得上」的證據合約。

## 現行瓶頸與下一步

Order 的 reservation-result reconciler 由單一 scheduler 週期性 claim，逐筆 append lifecycle event；`OrdersCurrentProjector` 也需要 Order DB 與 scheduler 時間。300／400 下，Rabbit 已清空、撮合與結算仍前進，但 Order reservation／查詢狀態的消化速率低於輸入速率。

下一個效能工作應先對 Order worker 做 stage timing、實際 batch size、oldest inbox age 與 scheduler utilization，再比較：

1. reservation-result worker 與 projector scheduler 隔離；
2. 保持 per-order consistency 的 bounded parallelism／partitioning；
3. event append 與 projection 的安全批次化；
4. 多 seed 重新搜尋 200～300 間的邊界。

不能直接增加 thread 或 batch 就宣稱改善；每個候選都必須重新通過 payload conflict、lease fencing、transaction atomicity、trade-ID、資產、projection 與 durable-debt gates。

## 本機 artifacts

- `build/load-test-reports/http-matched-external-LATEST_FULLCHAIN_20260903_400TPS_15M_R1-result.json`
- `build/load-test-reports/http-matched-external-LATEST_FULLCHAIN_20260903_300TPS_15M_R1-result.json`
- `build/load-test-reports/http-matched-external-LATEST_FULLCHAIN_20260903_200TPS_15M_R3-result.json`

Repository 只保存[精簡 summary](results/2026-09-03-current-version-full-chain/summary.json)；request-level JSONL、monitor CSV、logs 與 diagnostics 是可刪除的 local build artifacts。
