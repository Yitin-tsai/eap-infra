# EAP-PLAT-201：HTTP 下單冪等性

> 狀態：**Accepted（2026-11-05，CDA BUY／SELL HTTP 限定功能）**。最終 QA：ACCEPT；
> Reviewer：Approve，無阻擋項目。保留直接 durable acceptance＋outbox；正式容量／SLA
> 驗證另列後續工作。Order 實作提交為 `f58b521`；量測工具、驗收與證據保存於 infra `bf00dcb`。

> 2026-10-29：Architect／Performance 接受限定範圍；實作、157 項一般測試與 12 項 PostgreSQL
> 整合測試通過，Reviewer 無阻擋項目；當時的受測來源為尚未提交的工作樹。

## 問題與目標

本功能要解決的原始問題：Order 已提交訂單、event store 與 outbox，但 HTTP response 遺失時，client 原先無法
使用穩定 request key 取得第一次結果。重送會再次配置 market sequence／timestamp；
即使指定相同 orderId，也不等於具備 HTTP 重送契約。

## 接受的最小範圍

- 第一版涵蓋 CDA `POST /eap-order/bid/buy`、`POST /eap-order/bid/sell`。
- 可選 `Idempotency-Key`；未提供者保持既有行為。有提供但格式不合法者拒絕。
- key 以使用者分隔；買／賣、market、client orderId、price、amount 都納入 request identity。
- 同 key 同 request 回傳第一次 submission result；同 key 不同 request 回傳明確 conflict。
- Order 自己保存 durable ledger，與既有 command event／outbox 使用同一個本地 DB transaction。
- 只有獲勝的新 request 執行 admission 與 sequence 配置；已提交結果的重送不依賴 Redis、
  rate limit 或 Wallet backpressure。失敗的新 request 可能消耗 Redis sequence，但 SQL
  ledger／event／outbox 全部 rollback；允許 sequence gap。
- key 為大小寫敏感的 1～128 個 ASCII 字母、數字、`.`、`_`、`:`、`-`；空白、空值、
  多個 header 都回 400。未提供 header 才走原有無 key 路徑。
- Order HTTP facade 取代買賣 Controller 原本的兩個 rate-limit annotation；未提供 key
  時仍先檢查原本每 user 每秒 5 次 admission，keyed request 僅首次執行相同檢查。
- 使用 command datasource／`orderCommandTransactionManager` 的 READ COMMITTED 交易，
  先以帶 namespace 的穩定 hash 取得 `pg_try_advisory_xact_lock`，再以獨立 statement
  查 ledger。未取得鎖回 409 `IDEMPOTENCY_IN_PROGRESS`＋`Retry-After: 1`。
- 完整 `(user_id, idempotency_key)` primary key 與 versioned request fingerprint 才是身分
  約束；advisory hash collision 最多暫時回 busy。不同 payload 回 409 `IDEMPOTENCY_KEY_REUSED`。
- 保存原始 HTTP 200 submission response JSON 與 response version；查回的是原受理結果，
  不會因後續成交／拒絕改成當前訂單狀態。
- **保留／過期策略：第一版不過期、不自動刪除、不允許重用 key。** 回應與 reservation
  跟訂單事實一起保留；測試一天、一年及新建 service instance 後仍可重送。Ledger 隨成功 key 數線性
  成長，未宣稱 TTL 或儲存容量有界。後續歸檔須先定義歷史重送契約。
- 新 keyed submission 僅支援 `current_order_path`，實驗性的 `event_store_intake` 回 503；
  已提交 receipt 的 replay 優先於此模式檢查。
- SQL 使用交易內 lock／statement timeout；HTTP wrapper 量測包含最外層 commit 的時間與
  created／replayed／busy／conflict 等低基數結果，不把 user 或 key 當 metric label。
- Keyed 新提交會在 command connection 持有期間做既有外部 admission／sequence 呼叫；
  Redis／Rabbit RPC 設定明確 timeout。沒有 key 不增加 ledger query 或 transaction。
- MCP wrapper、取消、TDA、通用平台化與大規模效能調校不在這個切片。

## 驗收

真實 PostgreSQL 驗證同 key 同／不同 payload、並行競爭、失敗 rollback、不同使用者隔離、
response 遺失後再次讀回、event store／outbox 僅一份、key 長期保留邊界；HTTP 層驗證
header、狀態碼、買賣兩路與未提供 key 的相容性。完成後由唯讀 Reviewer 檢查修改。

使用者隔離沿用 request 中的 bidder／seller UUID；本項沒有把既有未驗證的 ID_TOKEN
升級成 authentication，也不宣稱 client 自報的 UUID 是已認證身分。

## 效能成本與 2026-10-29 測試邊界

以下測試限制描述十月功能驗證；十一月後續真實全鏈負載與 Order JVM restart 證據見下節。

- 兩次 `SET LOCAL` 也有成本：新 keyed submission 相較原 append 多 5 次 SQL 執行
  （包含 receipt INSERT）與 1 筆 row；replay 4 次 SQL、busy 3 次。沒有 key 不增加 ledger SQL。
- 10 秒 transaction timeout 不是 HTTP 或 command connection 持有時間的硬上限：它不會
  中斷 Java monitor 等待或外部 RPC。既有 backpressure guard 的同步 cache refresh 在依賴
  變慢時可能使不同 key 的 request 堆積；不能據此宣稱已完成 keyed capacity 驗證。
- Replay 與新 key 在 admission rate limit 前會取得 DB connection；pool 飽和時不保證
  每次 busy response 都低延遲。永久 receipt 的容量成長也是明確接受的成本。
- PostgreSQL、Liquibase、command appender、transaction manager 與 Spring HTTP/AOP 使用真實
  實作；Redis sequence、Rabbit backpressure 與 rate limiter 使用受控替身。RPC timeout 的
  實際依賴故障行為不在這輪測試證據內。
- Response loss 是在 Controller 已完成／DB 已 commit 後，以 servlet filter 注入 IOException；
  它證明無成功回應的重送能查回原 receipt，未宣稱實際 socket disconnect 或 JVM crash campaign。
- 當日的新 service instance／舊 receipt 測試證明不依賴記憶體 cache；當日尚未執行整個應用 JVM 的 restart。2026-11-05 已另完成 Order JVM restart 後 replay，未擴及全系統 crash。

## 2026-10-29 功能測試

在 `eap-order` 執行：

```bash
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test postgresIntegrationTest --tests com.eap.eap_order.application.OrderHttpIdempotencyPostgresIT
```

- `test`：227 cases，實際執行 157，70 個 integration cases 依 task 分流 skipped，0 failures／errors。
- 指定 `postgresIntegrationTest`：12 cases 全執行，0 failures／errors／skipped；一次性 PostgreSQL 14.6。
- 本次沒有重跑其他 58 個既有 PostgreSQL cases；它們不算入已通過數。
- 驗證 BUY／SELL replay、逐欄 payload 衝突、user／大小寫隔離、非法／空白／多 header、
  無 key 相容性與 rate limit、同 key 併行 busy、append 後失敗與 receipt INSERT 失敗的完整 rollback、
  commit 後 response loss、永久保留與新 instance、模式切換、不同 key 競爭同一 orderId 的
  PostgreSQL `55P03` lock timeout，以及失敗後同一條 pooled connection 不殘留 `SET LOCAL`。
- Reviewer 找到單一 header 轉 `List<String>` 會被 Spring trim 的問題；改成讀原始 servlet
  header enumeration，空白與重複 header 測試通過後核准。Performance／QA 無 correctness blocker，
  上列外部依賴等待與容量限制保留。
- 機器可讀結果與 source fingerprint：
  [summary.json](../benchmarks/results/2026-10-29-http-idempotency/summary.json)。

## HTTP 入口模式評估

2026-11-05 由 Architect／Performance 分別評估後，保留目前直接提交 Order 初始事實、
outbox 與 receipt 的模式。既有結果 inbox 的原則是可靠移交處理責任，不代表 HTTP
必須再增加 command inbox。評估當時尚待補上 keyed connection 持有期間的真實負載量測；
同日後續已完成下述固定比較點，慢依賴／故障時的等待行為仍待另測。
完整比較、量測決策點與改採 command inbox 的前置契約見
[ADR-007：CDA HTTP 下單受理模式](../adr/ADR-007-cda-http-order-intake-mode.zh-TW.md)。

同日後續已完成 [三輪有／無 key 增量量測](../benchmarks/2026-11-05-http-idempotency-comparison.md)：
200 unique orders/s、每輪 60s＋180s、全部 schema-v4 gate 通過。穩態 p95 的跨輪中位數
由 6.10ms 增至 9.64ms，command connection hold 由 1.54ms 增至 3.76ms；目前比較點
未觀察到完成吞吐或持續 pool 等待問題。Order JVM 重啟後另有 12000 次 replay，原 receipt
與業務資料核對通過。已確認的主機休眠失敗輪次另外保留，未納入正常統計；本項仍不宣稱
正式容量、慢依賴或全系統 crash campaign。

## 最終驗收結論（2026-11-05）

本次經 eap-agent-workflow 的獨立 QA／Reviewer 收尾審查，接受 CDA BUY／SELL HTTP
冪等契約與其量測工具。驗收依據為既有 157 項一般／12 項 PostgreSQL 測試、六輪有效
schema-v4 全鏈比較，以及 Order JVM 重啟後的獨立 12000 次 replay；本次收尾不重跑
已通過的測試或負載。Reviewer 未提出新增 P0／P1／P2 finding。

接受既述的交易內依賴等待與永久 receipt 成長成本；限定比較點的效能診斷不提升成
正式容量、SLA 或 production launch 核准。後續仍依 ADR-007 與 backlog 做固定版本
基準及必要的慢依賴量測，不因本次驗收另增 command inbox。

## 提交與證據版本

Order 實作、migration、測試及服務 README：
[`f58b521`](https://github.com/Yitin-tsai/eap-order/commit/f58b521225a208d9f3c3243dae48adb8da5fe20c)。
根目錄的 API snapshot、量測工具、ADR、驗收與精簡證據保存於 infra
[`bf00dcb`](https://github.com/Yitin-tsai/eap-infra/commit/bf00dcb3138369e9e45496702cd10471ffd7b9b2)。

2026-10-29 與 2026-11-05 的原始結果仍保留當時的 base revision、dirty 狀態與 working-tree
fingerprint。提交後只更新文件版本入口，不把已執行的工作樹診斷改標成新 commit 的乾淨版本
容量證據。正式 revision-pinned 長窗基準另列後續工作。
