# HTTP 下單冪等性增量成本量測 — 2026-11-05

## 結論

新 key 路徑有可量測的延遲與 connection hold 成本，但在本次固定
`200 unique orders/s` 比較點，六輪有效測試都完成受理與全鏈收斂，未觀察到 command pool
持續等待或完成吞吐下降。Performance 獨立審查支持保留直接 durable acceptance＋outbox；
本次未實作 command inbox，也未證明 inbox 較差。

| 三輪各自統計後取中位數 | 無 key | 全新 key |
| --- | ---: | ---: |
| 穩態 HTTP p95 | 6.10 ms | 9.64 ms |
| 穩態 HTTP p99 | 32.82 ms | 40.54 ms |
| command connection 平均持有時間 | 1.54 ms | 3.76 ms |
| command connection 平均取得時間 | 0.0030 ms | 0.0086 ms |
| 抽樣 active peak／pool size | 1／35 | 8／35 |
| 抽樣 pending peak | 0 | 0 |
| 六輪各自的 command pool timeout | 0 | 0 |

p95 增量約 `3.54 ms`、p99 約 `7.71 ms`、平均 connection hold 約 `2.22 ms`。
這是相同修改後程式的 **有／無 key 比較**，不是舊 revision 與新版的前後比較。
dirty source、同機、每模式三輪及固定比較點不構成正式容量、ceiling 或 SLA；
`capacityClaimAllowed=false`。

## 方法與口徑

- k6 constant-arrival-rate；每輪 `60s` 暖機＋`180s` 穩態，`200` 筆唯一訂單／秒，
  共 `48000` 單與 `24000` 筆交易；500 個 buyer／500 個 seller，shuffled seed `20260905`。
- 執行順序為 none／unique、unique／none、none／unique。最後一個 unique 原始 run 遭
  已確認的主機休眠中斷，保留失敗證據後以相同 source／設定重跑；不把失敗改標成成功。
- 三個 PostgreSQL configured `synchronous_commit=on`，server setting source 為 command line，
  無 role／database override，應用原始碼未配置 override。這不是直接查詢 command JDBC
  session 的觀測；也未沿用歷史 `synchronous_commit=off` 數字作新版比較。
- 使用 loadtest 預設 **local rate limiter**；Redis sequence、RabbitMQ、三個 PostgreSQL
  與所有正常背景流程為真實實作。Redis 分散式限流未納入。
- key 在 k6 SharedArray 初始化階段依 prepared order UUID 決定，不在計時 request path
  重新產生；價量、使用者分布、arrival schedule 與唯一訂單速率保持相同契約。
- HTTP 穩態延遲取最早觀測 iteration start 後第 `65–235s` 的 completion timestamp，
  排除暖機及兩端 5 秒，共 170 秒；每輪約 34000 筆，R2_NONE 為 33999。
  全部 240 秒 HTTP 統計也保留在各輪原始 result。
- 表中彙總是三輪「各輪分位數／平均值」的中位數，並非合併請求後的分位數或信賴區間。
  Pool sampler 設定間隔 5 秒，加上收集時間，實際約 6–9 秒；每輪穩態 25–26 點，
  因此 pending=0 不能排除短暫等待。Hikari timer 用穩態首尾 counter delta 計算。
- 五個 repo 的 commit／完整 working-tree fingerprint、compose／runner／library／k6 bundle
  在各輪前後及跨有效輪次一致。原始指紋保存在 summary，不因後續新增文件而改寫。

受測來源與驗收提交不同：summary 保存的是 infra base `d496646` 與 Order base `ca2d6db`
加上各自 dirty working-tree fingerprint。後續 Order 實作提交為 `f58b521`，工具／驗收／
證據提交為 infra `bf00dcb`；沒有對這兩個乾淨提交重跑本 campaign，原始 provenance 不改寫。

## 逐輪結果

| Run | HTTP p95 ms | HTTP p99 ms | connection hold ms | steady trades/s |
| --- | ---: | ---: | ---: | ---: |
| R1_NONE | 6.10 | 34.41 | 1.54 | 100.01 |
| R1_UNIQUE | 9.64 | 50.93 | 3.82 | 99.97 |
| R2_UNIQUE | 9.85 | 40.54 | 3.76 | 99.89 |
| R2_NONE | 3.88 | 17.17 | 1.34 | 100.21 |
| R3_NONE | 7.55 | 32.82 | 1.77 | 99.93 |
| R3_UNIQUE_RETRY1 | 8.55 | 36.04 | 3.41 | 99.73 |

六輪共 `288000` 筆唯一訂單與 `144000` 筆交易，每輪都要求：

- schema v4、精確 scheduled／accepted 筆數、無 dropped／out-of-range、driver exit 0。
- Match／Order／Wallet trade ID 集合一致，資產精確對帳，Order projection 與 checkpoint 收斂。
- 穩態與最終 durable-debt observations healthy，完整固定 work 集合都受 gate 檢查，
  最終 inbox／outbox／cleanup／projection 等 debt 歸零，Rabbit／DLQ 與 reservation 收斂。
- 新 key 恰有 48000 筆 receipt、48000 個 response orderId，各自對應 48000 個初始 Order
  事實；無 key 的 receipt 為 0，沒有無對應 Order 的 receipt。

## 獨立重啟／重送驗證

完成有效最後一輪後保留資料，重新啟動 **Order JVM**，再送出 12000 次已有 receipt 的請求，
200 replay requests/s、60 秒。每個選取 key 各重送一次；本階段沒有新的唯一訂單。
此階段只有 Order JVM 與基礎設施運行，不能把其延遲與三服務全鏈負載直接比較。

- 12000 次都回傳與持久化原 receipt 相同的 JSON 欄位；expected response 以
  user／key／orderId 關聯取得。原始成功 HTTP bytes 未另行保存，不能宣稱逐 byte 比較。
- outcome delta 只有 `replayed=12000`；`created`、busy、conflict、error 等沒有增量。
- Order head `48000`、event `96000`、outbox `48000`、receipt `48000`、trade application
  `24000` 在前後保持相同；Wallet 全表 fingerprint、Match `24000` 筆 trade 與
  Redis market sequence `48000` 都不變。
- Order durable-debt snapshot 在前後均 fresh、exact、zero；其他 owner 的完整 gate 來自
  前一輪全鏈結果，replay 不宣稱執行三服務混合負載或全系統 crash campaign。
- Receipt relation 的 `pg_total_relation_size` 為 `22896640` bytes／48000 筆；本次未量測
  長期保留、歸檔或儲存容量上限。

這證明已提交 receipt 的重送不依賴舊 Order JVM 記憶體，且沒有重複業務效果。
Replay HTTP p95／p99 為 `4.02／23.16 ms`，僅作此獨立階段的觀察值。

## 排除的環境中斷

原 `R3_UNIQUE` 的 monitor 出現 `460.997s` gap；macOS power log 記錄相同時段的
Idle Sleep／後續休眠，多個 JVM 同時報 housekeeper clock leap。該輪 accepted 為
`47407/48000`，driver 有 `499` 個 dropped iterations、`94` 個其他 HTTP failure，
gate 正確拒絕。其 final 資產與 trade ID 核對通過，仍不符合正常量測的完整契約。

原始結果與 power／clock 證據保存在 [interrupted](results/2026-11-05-http-idempotency/interrupted/evidence.json)。
重跑使用 scoped `caffeinate`，不更動應用程式、pool、gate 或交易語意。

## 工具變更與驗證

- k6 新增可選 `HTTP_IDEMPOTENCY_MODE=none|unique`，預設 none，並保存 mode／traffic class。
- 測試資料 reset 納入新 receipt table；這只影響專用 loadtest reset。
- diagnostics 納入 idempotency／submission phase metrics，保留 Hikari、依賴與 debt 觀測。
- 修正既有 provenance 漏讀中文／空白 untracked filename 的問題，改採 NUL 分隔檔名。
- campaign 逐輪檢查 schema4、精確數量、receipt invariant 與 source equality；分析器也從
  raw result 重新驗證完整 gates，避免固定寫入成功標記。
- 4 項 JavaScript driver／receipt 測試、schema-v4 result-contract suite、中文檔名 fingerprint
  regression 與分析器 5 個失敗／缺欄負例通過；Order `testClasses` 編譯成功。
  本輪未變更業務執行程式。

正常比較的啟動方式：

```bash
caffeinate -dimsu env python3 scripts/load-test/run-http-idempotency-comparison.py \
  --campaign-id HTTP_IDEMPOTENCY_20261105_B --duration 180 --warmup 60 --repeats 3
```

實際本輪因原始休眠另有 `R3_UNIQUE_RETRY1` 重跑；確切 run ID、原始結果、逐秒 business／
debt samples 與 pool counter CSV 見 [summary.json](results/2026-11-05-http-idempotency/summary.json)。
請使用新的 campaign ID 重跑，避免覆寫證據。request-level JSONL 與完整日誌保留於本機
`build/load-test-reports`；repository 保存約 1 MB 的精簡證據與執行過的分析腳本快照。
發佈副本的 pool CSV 統一為 LF 換行，power log 摘錄去除行尾空白；資料值不變，本機原始檔保留。
測試 JVM 與本次五個 loadtest 容器已停止，資料卷保留，原有三個資料庫容器未受影響。

## 後續決策

保留 [ADR-007](../adr/ADR-007-cda-http-order-intake-mode.zh-TW.md) 的模式選擇。
取消、排序與新增命令狀態可透過工程設計處理，不視為否決 inbox 的理由；目前考量的是
額外 durable handoff／worker 管理能否換得所需延遲、可用性或排程收益。

若要繼續改善，優先更密集觀測 pool，以及在真實依賴慢化時量測 connection-hold 尾延遲，
再評估局部減少 SQL 往返／交易內等待，或另做 command inbox 原型 A/B。本輪未量測
慢依賴、同 key 風暴、live mixed replay、跨機 RTT、更高負載或乾淨 revision 長窗容量；
尚未提供數值化 latency／availability SLO，因此不直接判定 SLA 達標。
