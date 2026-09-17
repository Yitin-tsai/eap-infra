# Order Saga Timeout Detector（REL-105）

> 更新日期：2026-09-17
>
> 定位：這是 **warning-only、read-only** 的卡單偵測器。它負責把「很久沒有業務進度」
> 變成可查詢、可告警的候選清單；它不會自動取消訂單、解鎖資產或捏造跨服務結果。

## 它補的是哪一個洞

Rabbit queue 為 0、inbox 為 `APPLIED`，只代表已知工作沒有堆積，不能證明每張 Order Saga
都走到終止狀態。例如 Wallet confirmation 遺失、terminal outbox 尚未恢復，可能讓訂單長期
停在 `PENDING_ASSET_CHECK`；取消流程缺少後續事實時，則可能長期停在 `CANCELLING`。

REL-103 的 durable-debt snapshot 是「工作容器裡還欠多少」；REL-105 從 Order 的業務生命
週期反向問「哪些訂單本身太久沒有前進」。兩者互補，不能互相取代。

## 判斷來源與權威

偵測器沒有新增一張 Saga table，也不複製整條 workflow。它每 5 秒唯讀既有資料：

| 用途 | 資料來源 | 理由 |
| --- | --- | --- |
| 目前有效狀態 | 有 `order_matching_state` 時以其 `status` 為準，否則回退到 `order_stream_heads.status` | trade hot path 可能先推進 matching state，不能把已成交訂單誤報成仍在驗資 |
| 最後業務進度時間 | `order_stream_heads.updated_at` | 事件 append 與 stream head 同 transaction 推進；matching state 的技術性 upsert 可能更新自己的時間，不適合作為 Saga 時鐘 |
| 歷史事實 | `order_event_store` | 需要調查時仍由 append-only event stream 解釋狀態如何形成；detector snapshot 不是新的事實來源 |

掃描在 read-only、`REPEATABLE_READ` transaction 內完成，因此 summary、候選明細與未來時間
異常使用同一個資料庫快照。migration `order-es-031` 新增 partial index：

```sql
CREATE INDEX idx_order_stream_heads_saga_timeout
    ON order_service.order_stream_heads(status, updated_at, aggregate_id)
    WHERE status IN ('PENDING_ASSET_CHECK', 'CANCELLING');
```

這只增加索引，不在下單 hot path 多寫一份 Saga record。

## 第一版監看哪些狀態

| 狀態 | 預設 deadline | 為何合理 |
| --- | ---: | --- |
| `PENDING_ASSET_CHECK` | 300 秒 | 正常情況應由 Wallet 的 reservation success／rejection 推進，不應無限等待 |
| `CANCELLING` | 600 秒 | 正常情況應由 Wallet 釋放未成交 reservation，再以 release fact 完成取消 |

`OPEN` 與 `PARTIALLY_MATCHED` 沒有 deadline：等待市場流動性可以是合法的無限期狀態。
`MATCHED`、`CANCELLED`、`REJECTED` 是終止或已完成狀態，也不應報 timeout。

deadline、refresh interval 與明細上限都可由 `eap.order-saga-timeout.*` 設定。判定使用
PostgreSQL `CURRENT_TIMESTAMP`；剛好等於 deadline 即成為候選。若資料時間晚於 DB time，
該 row 不會被誤算成 timeout，而會計入 clock-anomaly metric。

## Snapshot 與失敗語意

`GET /eap-order/actuator/orderSagaTimeouts` 回傳 versioned snapshot，核心欄位是：

- `observationSuccess`：最近一次 DB scan 是否成功。
- `snapshotAgeSeconds`：距離上一次成功 scan 多久。
- `states`：兩個固定狀態的精確 candidate count、oldest age 與 threshold。
- `candidates`：依最舊進度排序的診斷明細，最多 100 筆。
- `truncated`：精確 count 超過明細上限；不是資料遺失。
- `futureProgressTimestampCount`：時間在 DB 現在之後的異常 row 數。

DB scan 失敗時不把 count 清成 0，而是保留 last-good values，同時把
`observationSuccess=false` 並持續增加 snapshot age。如此 dashboard 不會把「看不到資料」
誤解成「沒有卡單」。這個 snapshot 在記憶體中；服務重啟後會從既有 Order tables 重建，
不保存 timeout episode 的歷史或 operator audit。後者屬於 REL-106 control plane。

## Metrics 與告警

主要低基數 metrics：

- `eap_order_saga_timeout_candidates{state=...}`
- `eap_order_saga_timeout_oldest_age_seconds{state=...}`
- `eap_order_saga_timeout_observation_success`
- `eap_order_saga_timeout_snapshot_age_seconds`
- `eap_order_saga_timeout_refresh_failures_total`
- `eap_order_saga_timeout_snapshot_truncated`
- `eap_order_saga_timeout_future_progress_timestamps`
- `eap_order_saga_timeout_contract_version`

order ID 只存在 Actuator 診斷內容，不放進 metric label，避免高基數。候選持續 2 分鐘才發
warning；scan failure、snapshot stale、metric missing／incomplete 或 contract mismatch 會
fail closed。規則在 `observability/prometheus/rules/eap-order-saga-timeout.yml`。

## Operator 看到告警後怎麼做

1. 先確認 `observationSuccess=true`、snapshot 未 stale，排除 detector 自己故障。
2. 從 endpoint 取得 order ID、effective/head/matching state、version 與 last-progress time。
3. 查該 order 的 `order_event_store`，再查相關 inbox、outbox、Rabbit DLQ 與 Wallet／Match
   durable facts，判斷缺的是事件、consumer 套用、terminal publication 或真正的業務前置。
4. 本 ticket 到此停止。不可因為 timeout 就直接把狀態改成 `CANCELLED` 或釋放資產。
5. 由 REL-106 提供受保護、可 dry-run、可稽核的 replay／park／resolve 操作。

timeout 是「需要調查的症狀」，不是足以產生業務結果的新事實。這也是第一版刻意不做
自動 compensation 的原因。

## 驗證與邊界

已覆蓋：

- matching state 不存在時回退 stream head。
- head 仍為 `PENDING_ASSET_CHECK`、但 matching 已因 trade 推進時不誤報。
- aged／fresh、`PENDING_ASSET_CHECK`／`CANCELLING`／非監看狀態矩陣。
- same-state progress 重設 deadline、未來 timestamp 隔離。
- bounded details、精確 summary、partial-index query plan。
- refresh failure 保留 last-good values，並暴露 failure／staleness。
- `promtool` 規則語法與告警等待時間。

仍未提供：跨三服務的全域 Saga record、自動判斷補償、timeout 歷史與 operator audit、
受控 DLQ／terminal replay。REL-105 讓 liveness 問題可見；REL-106 才處理如何安全恢復。

此外 migration 使用一般 `CREATE INDEX`，符合目前資料量有限的本機學習環境；正式大表部署
應安排 maintenance window，或採 Liquibase 非 transaction changeSet 搭配
`CREATE INDEX CONCURRENTLY` 的獨立發布流程，避免建立索引時長時間阻塞寫入。

## 程式入口

- `OrderSagaTimeoutRepository`：一致性 DB snapshot 與有效狀態判斷。
- `OrderSagaTimeoutSnapshotProvider`：排程、last-good cache 與 Micrometer metrics。
- `OrderSagaTimeoutEndpoint`：唯讀 Actuator 診斷入口。
- `OrderSagaTimeoutDetectorPostgresIT`：真實 PostgreSQL 狀態矩陣、邊界與 index plan。
