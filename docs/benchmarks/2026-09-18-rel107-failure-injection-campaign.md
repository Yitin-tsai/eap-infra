# 2026-09-18 REL-107 failure-injection campaign R1–R5

> 結論：目前已實作的 CDA durable inbox、DB outage circuit、worker lease、Redis
> generation fence 與 recovery action idempotency，在本輪範圍內通過。沒有觀察到重複
> trade、重複資產異動、遺失工作或未被 gate 看見的 debt。REL-107 仍不完全關閉，因為
> shared DLQ 目前為 Wallet／Order `TradeExecutedEvent` 開放 owner-aware conditional replay，任意
> Redis full-book rebuild 與 HTTP 全鏈三 JVM crash 仍未完成。R2 補上 broker confirm 與
> local `SENT` 之間的真實 process crash；R3 補上第一條安全 DLQ replay vertical slice；
> R4 再驗證 MCP 收到 replay publisher confirm、但中央 audit 尚未完成時的真實 JVM crash；
> R5 把相同 owner boundary 擴充到 Order，並以真實 PostgreSQL／RabbitMQ 驗證。

本報告是 failure-injection correctness evidence，不是效能測試。所有 run 都設定
`capacityClaimAllowed=false`；包含故障等待與恢復的秒數不能解讀為 happy-path latency
或 TPS ceiling。機器可讀摘要見
[R1–R3 JSON](results/2026-09-18-rel107-failure-injection-r3.json)、
[R4 JSON](results/2026-09-18-rel107-failure-injection-r4.json)與
[R5 JSON](results/2026-09-18-rel107-failure-injection-r5.json)。

## 驗收矩陣

| Scenario | 注入方式 | 必須成立的結果 | 結果 |
| --- | --- | --- | --- |
| Order／Wallet DB outage | 兩個 load-test PostgreSQL 同時停止至少 60 秒 | consumer pause、訊息留在 source queue、DLQ 不增加、DB 回來自動 drain | PASS |
| Match DB outage | Match PostgreSQL 停止至少 60 秒 | admission consumer pause、200 筆最終 `APPLIED`、DLQ 0 | PASS |
| Order／Wallet consumer crash | active publication 期間對兩個 JVM `SIGKILL`，5 秒後重啟 | broker retained delivery、兩服務 exact-once business effect、queue/debt 歸零 | PASS |
| Match Redis outage | Redis 停止、事件持久化後重啟成新 `run_id` | 未驗證 generation 必須 fail closed；受控 activation 後才 replay inbox | PASS |
| Worker lease expiry／lost lease | PostgreSQL／Redis integration tests | 新 worker 可 reclaim；舊 worker 不得 commit 或覆寫新 owner | PASS |
| Duplicate／late／out-of-order | Order、Wallet、Match integration tests | duplicate 無第二次 effect；trade 早於 reservation confirmation 不回退；取消與 settlement 兩種順序收斂 | PASS |
| Identity conflict | 同 identity 改 payload | durable terminal/audit 可見，domain state 不被錯誤 payload 改寫 | PASS |
| Outbox confirm ambiguity | Match relay 在 200 筆 broker confirm 後、local `SENT` 前進入受控 pause，再 `SIGKILL` | 200 筆保持 `PENDING`；重啟後重送，兩個下游仍只有一份業務結果 | LIVE PASS |
| Recovery response loss | 同一 `actionId` 重送 | owner-side action ledger 回傳第一次結果，不再執行第二次 mutation | PASS |
| Poison → DLQ | 真實 Wallet Rabbit retry exhaustion | poison 進 DLQ，不能誤開 DB outage circuit | PASS |
| DLQ redrive business preflight | shared `order.dlq` | exact owner route、transient-only、owner preflight、direct queue、confirm | Wallet／Order trade PASS；其他 route 保持 fail closed |
| MCP replay confirm→audit crash | owner queue confirm 後、central disposition/action completion 前 `SIGKILL` | 同 action 可恢復；可能重送，但 Wallet inbox 只能產生一次 settlement | LIVE PASS |

## 真實程序／依賴故障結果

### 1. Order＋Wallet PostgreSQL outage

採用的有效 run 是 `REL107_ORDER_WALLET_DB_OUTAGE_R2`：

| Gate | 結果 |
| --- | ---: |
| requested／measured outage | 60／71 秒 |
| consumer pause latency | 24 秒 |
| pause 維持到 DB recovery | PASS |
| publisher ACK／nack／return／timeout／failure | 200／0／0／0／0 |
| Order applications／Wallet settlements | 200／200 |
| missing／unexpected Trade ID | 0／0 |
| locked currency／amount | 0／0 |
| Order queue／Wallet queue／DLQ final | 0／0／0 |
| DLQ peak | 0 |
| Order／Wallet circuit final open | 0／0 |
| 兩服務完整 durable-debt snapshot | 全零 |
| correctness gate | PASS |

`fanoutConvergenceSeconds` 包含 60 秒 outage、probe、staggered resume 與 drain，不是效能
數字。raw evidence：
`build/load-test-reports/trade-consumer-fanout-REL107_ORDER_WALLET_DB_OUTAGE_R2-rel104-evidence.json`。

### 2. Match PostgreSQL outage

`REL107_MATCH_DB_OUTAGE_R1` 停止 Match DB 71 秒。consumer 在 19 秒內完成 pause
驗證，且直到 DB 啟動前仍保持停止；200 筆 admission 最終為 200 inbox／200
`APPLIED`，DLQ before／after 都是 0，circuit 最終關閉，五類 Match durable debt 全零。

raw evidence：
`build/load-test-reports/rel104-match-db-outage-REL107_MATCH_DB_OUTAGE_R1-result.json`。

### 3. Order＋Wallet JVM crash

`REL107_ORDER_WALLET_PROCESS_CRASH_R1` 在 1,000 筆 `TradeExecuted` 以 100 events/s
發布途中，2 秒後同時 `SIGKILL` Order 與 Wallet，5 秒後以相同設定重啟：

- publisher ACK 1,000／1,000，nack、return、timeout、failure 全為 0；
- Order applications 與 Wallet settlements 各 1,000；
- 兩服務 Trade ID 都與 expected set 完全相同，missing／unexpected 都是 0；
- locked asset 歸零，兩條 source queue 與 DLQ 歸零；
- Order 六類、Wallet 四類 durable debt 全零。

`17.24s` 是含 crash/restart 的收斂時間，只是 liveness evidence。raw evidence：
`build/load-test-reports/trade-consumer-fanout-REL107_ORDER_WALLET_PROCESS_CRASH_R1-rel107-process-evidence.json`。

### 4. Match Redis outage 與 generation fence

新增可重現腳本
[`run-rel107-match-redis-outage-recovery.sh`](../../scripts/load-test/run-rel107-match-redis-outage-recovery.sh)。
`REL107_MATCH_REDIS_OUTAGE_R1` 的驗證順序刻意分成兩段：

1. 初始 empty generation 為 `READY` 後停止 Redis；
2. 發布 200 筆 BUY admission，確認 Rabbit source queue 已清空且 PostgreSQL inbox 有
   200 筆，但 `APPLIED=0`、trade=0；
3. Redis 重啟後 `run_id` 確實改變，control 自動進入 `RECOVERING`；
4. 再等待 2 秒，仍為 `APPLIED=0`、trade=0、open order=0，證明不是重連即放行；
5. operator request 同時帶 fence epoch、generation、CAS version、order/trade watermark
   與兩次核對一致的 empty manifest；
6. activation 成功後 worker 才處理 inbox。

最終 200/200 inbox `APPLIED`，Redis buy ZSET、order detail 與 completed bitmap 都精確為
200；reservation、processing claim、source queue、DLQ 與五類 durable debt全為 0。

這證明 `REL-101` 的 fail-closed／controlled activation contract，沒有證明任意既有
order book 已能自動重建；後者仍屬 `EAP-MATCH-202`。

### 5. Match outbox confirm ambiguity process crash

有效 run 是 `REL107_OUTBOX_CONFIRM_CRASH_R4`。MatchEngine 的 load-test-only probe 只會在
`loadtest` profile 且明確開啟時載入，位置就在 RabbitMQ publisher confirm 全部成功之後、
更新 PostgreSQL outbox `SENT` 之前。probe 先原子寫出 marker，再暫停 relay thread，腳本依
marker 的實際 PID 執行 `SIGKILL`，不是用固定 sleep 猜測 crash window。

| Gate | 結果 |
| --- | ---: |
| marker confirmed count | 200 |
| crash 前 Match outbox `PENDING`／`SENT` | 200／0 |
| crash 前 Order applications／Wallet settlements | 200／200 |
| crash 後仍為 `PENDING` | 200 |
| 正常重啟後 Match outbox `SENT`／`FAILED` | 200／0 |
| Wallet 明確吸收的 duplicate deliveries | 200 |
| 最終 Order／Wallet 業務結果 | 200／200 |
| missing Trade ID／Queue／DLQ | 0／0／0 |
| Order／Wallet／Match durable debt | 全零 |
| correctness gate | PASS |

這證明 at-least-once outbox 在最難避免的 confirm ambiguity window 會選擇安全重送，而
Order／Wallet 的冪等邊界能阻止第二次業務異動。raw evidence：
`build/load-test-reports/match-relay-downstream-REL107_OUTBOX_CONFIRM_CRASH_R4-outbox-confirm-crash-evidence.json`。
其中包含 pause、kill、restart 的收斂時間，`capacityClaimAllowed=false`，不得用於 TPS 宣稱。

### 6. Shared DLQ owner-aware replay vertical slices

R3／R5 沒有把 shared DLQ 改名成「已全面可重播」。目前只開放 Wallet／Order 的
`TradeExecutedEvent` exact topology，且 capture 分類必須是 `TRANSIENT`：

- broker case identity 使用 `sourceQueue + messageId`；相同 fanout message 在 Order／Wallet
  各自失敗時不會互相覆蓋；
- dry-run 與 execute 都呼叫 route owner preflight；Wallet 查 durable inbox；Order 同時查
  recovery inbox 與正常 happy path 的 trade application。只有 owner 證明尚未 durable／applied
  才 publish，payload conflict／permanent／invalid 全部拒絕；
- publish 使用 default exchange direct-to-queue，不讓已成功的 Order consumer 再收到；
- message persistent、mandatory、correlated confirm；return／nack／timeout 不得完成 action；
- confirm 到 audit 之間仍可能 duplicate，最後由 owner-local idempotency boundary 吸收，不宣稱
  exactly-once recovery。

真實 Rabbit integration 已證明 owner queue 收到原始 bytes 與 recovery audit headers，且
`x-death`／exception headers 不會被帶回 poison loop。完整設計見
[ADR-006](../adr/ADR-006-owner-aware-shared-dlq-replay.zh-TW.md)。

### 7. MCP replay confirm→central audit process crash

有效 run 是 `20260918_155857`，由
[`run-rel107-mcp-replay-confirm-crash.sh`](../../scripts/load-test/run-rel107-mcp-replay-confirm-crash.sh)
執行。fixture 不是直接偽造 `x-death`：訊息先經真實 `trade.exchange` 進入
`wallet.tradeExecuted.queue`，再由 RabbitMQ TTL／DLX 產生可相信的 queue／exchange／routing
key。Wallet listener 在 ambiguity 測試期間刻意關閉，讓第一次已 confirm 的訊息停在 owner
queue，避免用「consumer 剛好處理很快」掩蓋 duplicate window。

| Gate | 結果 |
| --- | ---: |
| crash signal／first HTTP result | `SIGKILL`／curl 52（server 無回應） |
| crash 前 action／attempt／result | `STARTED`／1／未寫入 |
| crash 前 case／owner queue ready | `OPEN`／1 |
| crash 後 action／case | 仍為 `STARTED`／`OPEN` |
| 同 actionId 重試後 action／attempt | `APPLIED`／2 |
| 重試後 case／owner queue ready | `RESOLVED`／2 |
| Wallet duplicate delivery | 1 |
| Wallet inbox／settlement | 1／1 |
| 最終 Wallet queue／DLQ | 0／0 |
| 買賣雙方資產核對 | 精確符合單次結算 |

這個結果刻意證明「可能送兩次，但只能結算一次」。它沒有把 Rabbit delivery 說成
exactly-once；可靠性來自中央 action ledger 可恢復，加上 owner durable inbox 的 identity／
payload 冪等邊界。完整 machine-readable 摘要在
[R4 JSON](results/2026-09-18-rel107-failure-injection-r4.json)，原始本機 evidence 位於
`build/load-test-reports/rel107-mcp-replay-confirm-crash-20260918_155857.json`。

### 8. Order TradeExecuted owner-specific preflight

R5 新增 `order.tradeExecuted.queue + trade.exchange + trade.executed`。Order 的正常成交
happy path 不一定建立 recovery inbox，而是直接寫 `order_trade_applications`；若只查 inbox，
已完成交易會被誤判成可重播。因此 owner endpoint 用單一 SQL statement 同時讀取：

- `order_trade_execution_inbox`：比對完整 payload 與 retry／terminal state；
- `order_trade_applications`：比對 Order 真正擁有的 buyer／seller order、price、quantity、
  `applied_at`；
- 兩者都不存在才回 `ELIGIBLE`；任一 identity 不一致立即 fail closed；
- MCP 依 owner registry 呼叫 Order，不會誤呼叫 Wallet，publish 只進 Order queue。

這個切片沒有新增正常路徑資料表或 write amplification。Order PostgreSQL suite 與 MCP
PostgreSQL／RabbitMQ integration 都通過；真實 Rabbit test 也驗證 Order replay 不會送進 Wallet
queue。R5 是 owner-state 與 transport correctness evidence，不是新的 process-crash run。

## Deterministic failure matrix

| Suite | Tests | Failures／errors | 主要覆蓋 |
| --- | ---: | ---: | --- |
| Order general `test` task | 213（58 skipped） | 0／0 | integration cases 依 task 分流；其餘含 Order preflight payload／route／state 與 source-token auth regression |
| Order `postgresIntegrationTest` | 58 | 0／0 | duplicate/conflict、late confirmation、lease reclaim/lost lease、outbox rollback/reclaim、recovery action、trade inbox/application preflight snapshot |
| Wallet general `test` task | 113（37 skipped） | 0／0 | integration cases 依 task 分流；其餘覆蓋 preflight payload／route／durable state、source-token auth、既有 listener／processor／recovery regression |
| Wallet `walletPostgresIntegrationTest` | 54 | 0／0 | duplicate reservation、asset invariant rollback、trade/cancel ordering、lease、identity conflict、preflight state transition |
| Wallet `walletRabbitIntegrationTest` | 1 | 0／0 | poison retry exhaustion → DLQ，不開 DB circuit |
| Match `crashRecoveryIntegrationTest` | 60 | 0／0 | Redis full loss、generation mismatch、match/cancel crash windows、reservation ownership、terminal debt |
| MCP general `test` task | 23（9 skipped） | 0／0 | integration cases 依 task 分流；其餘覆蓋 owner route dispatch、preflight coordinator、post-confirm probe、direct publisher confirm/nack、control action |
| MCP `postgresIntegrationTest` | 7 | 0／0 | audit/idempotency/rate limit、broker quarantine、per-consumer case identity、Wallet／Order transient replay metadata |
| MCP `rabbitIntegrationTest` | 2 | 0／0 | 真實 Wallet／Order direct owner queue、publisher confirm、recovery headers、跨 queue 隔離 |
| Wallet outbox focused | 9 | 0／0 | ACK/nack、batch confirm、`IN_FLIGHT`、max attempts |
| Match outbox focused | 8 | 0／0 | ACK/nack、batch confirm、payload rebuild／routing、load-test marker 單次觸發與安全設定 |

重要語意包括：

- Order 收到 trade 後，即使 asset confirmation 晚到也不會把已成交狀態退回；
- Wallet 的 cancel-before-trade、trade-before-cancel 與並發版本都收斂到相同資產結果；
- 過期 lease 可被新 worker 接手，但失去 token 的舊 worker transaction 必須 rollback；
- Match 在 trade commit、Redis reservation、completed marker 等不同 crash window 都只產生
  一筆 durable trade，且 orphan reservation 有明確恢復路徑；
- permanent／identity／invariant case 不因 recovery API 存在就變得可 replay。

## Campaign 發現並修正的測試工具問題

第一次 Order／Wallet DB run（`REL107_ORDER_WALLET_DB_OUTAGE_R1`）的 200 筆本輪交易本身
收斂，但完整 gate 拒絕通過，因為 Order 偵測到 1 筆舊的
`asset_reservation_released` terminal debt。根因不是本輪 DB recovery，而是測試隔離漏項：

1. `purge-eap-queues.sh` 與 Java generator 都漏掉
   `order.assetReservationReleased.queue`；
2. generator reset 沒有清除近期新增的 Order reservation-result/released inbox、Wallet
   `message_inbox`、release publication 與 recovery action ledger；
3. Wallet 的 PostgreSQL-only test task 沒有停用 outbox relay，測試用 outbox 有機會被送到
   開發 RabbitMQ，破壞下一個 campaign 的隔離性。

已補齊 queue purge、load-test schema reset，並在 Wallet PostgreSQL task 關閉 Rabbit
listener/outbox relay；`testClasses` 通過，Wallet 52 tests 重跑後所有 EAP queue 仍為 0，
DB outage R2 再跑後完整 debt 全零。R1 不列為有效 PASS。這個案例也證明「本輪
business rows 正確、Rabbit queue=0」仍不足以宣稱完成；owner-local durable-debt gate
必須保留。

R2 的候選 run 也揭露三個 probe repeatability 問題，無效候選都沒有列為 PASS：

1. relay seed 建立 800 個 Order events，原腳本未執行 projection prewarm，完整 debt gate
   正確拒絕通過；現在 activation 前會先跑 `project` phase；
2. 原腳本只 purge Rabbit，未重設 Match load-test schema 與 Redis runtime，第二輪可能被
   舊 generation／durable facts 擋住；現在每輪會先清空明確的 load-test Match schema 與 Redis；
3. Order 以 `eap.scheduling.enabled=false` 啟動時，durable-debt cache 不會 refresh，即使 DB
   已歸零仍回傳 stale snapshot；crash mode 現在保留 debt scheduler，其他 projection／market
   工作仍各自關閉。

`R1` 命中 ambiguity window 但被 projection debt 擋下；`R2` 在注入前被舊 runtime
隔離問題擋下；`R3` 的 DB 已正確但 snapshot stale；只有修正全部三項後的 `R4` 被採用。

DLQ fixture 的第一個候選也被 gate 拒絕：測試程式直接加入的 `x-death` 不會成為可信的
broker ownership evidence，MCP capture 因此只看到 message ID，沒有開放 `REPLAY`。正式 R4
改由 message TTL＋真實 DLX 讓 RabbitMQ 自己產生 `x-death`，再核對 exact topology 後才執行。

## 尚未通過、不能偷換成已完成的能力

1. **Shared DLQ 其他 route：** Wallet／Order trade 已使用 broker `x-death.queue`、exact topology
   allowlist 與 owner-local preflight 安全開放；Match 與 Order／Wallet 其他 queue
   尚未各自定義 preflight，因此仍只能 inspect／park／resolve，不能外推為全域 redrive。
2. **任意 Redis full-book rebuild：** 本輪只使用原本為空、durable inbox 尚未套用的
   generation，證明 fence 與 activation；不能據此宣稱可從 PostgreSQL 重建任意 open book。
3. **全鏈 process crash：** 真實 `SIGKILL` boundary 是 TradeExecuted → Order/Wallet fanout；
   Match 的細粒度 crash windows 由 60 項 PostgreSQL／Redis integration cases 驗證，尚未在
   HTTP 全鏈同一 run 中 kill 三個 JVM。

## 重現指令

```bash
# Order + Wallet process crash
TRADES=1000 TARGET_TRADE_TPS=100 TIMEOUT_SECONDS=240 \
PROCESS_CRASH_SERVICES=order,wallet PROCESS_CRASH_AFTER_PUBLISH_SECONDS=2 \
PROCESS_RESTART_DELAY_SECONDS=5 RUN_ID=REL107_ORDER_WALLET_PROCESS_CRASH_R1 \
BUILD_JARS=true KEEP_INFRA=true \
bash scripts/load-test/run-trade-consumer-fanout-probe.sh

# Order + Wallet 60-second DB outage
TRADES=200 TARGET_TRADE_TPS=100 TIMEOUT_SECONDS=300 DB_OUTAGE_SECONDS=60 \
PRE_PUBLISH_DELAY_SECONDS=3 RUN_ID=REL107_ORDER_WALLET_DB_OUTAGE_R2 \
BUILD_JARS=false KEEP_INFRA=true \
bash scripts/load-test/run-trade-consumer-fanout-probe.sh

# Match 60-second DB outage
EVENTS=200 TARGET_TPS=100 DB_OUTAGE_SECONDS=60 TIMEOUT_SECONDS=240 \
RUN_ID=REL107_MATCH_DB_OUTAGE_R1 KEEP_INFRA=true BUILD_JAR=false \
bash scripts/load-test/run-rel104-match-db-outage-recovery.sh

# Match Redis loss and controlled generation activation
EVENTS=200 TARGET_TPS=100 TIMEOUT_SECONDS=240 \
RUN_ID=REL107_MATCH_REDIS_OUTAGE_R1 KEEP_INFRA=true BUILD_JAR=true \
bash scripts/load-test/run-rel107-match-redis-outage-recovery.sh

# Match outbox: broker confirm succeeded, local SENT not committed, then SIGKILL
POST_CONFIRM_CRASH_ENABLED=true TRADES=200 TIMEOUT_SECONDS=120 \
POST_CONFIRM_PAUSE_MS=120000 RUN_ID=REL107_OUTBOX_CONFIRM_CRASH_R4 \
MARKET_ID=REL107_OUTBOX_CONFIRM_CRASH_R4 BUILD_JARS=false KEEP_INFRA=false \
bash scripts/load-test/run-match-relay-downstream-probe.sh

# Wallet owner preflight: unit + real PostgreSQL state transitions
cd eap-wallet
./gradlew --no-daemon test walletPostgresIntegrationTest

# Order owner preflight: unit + real PostgreSQL inbox/application snapshot
cd ../eap-order
./gradlew --no-daemon test postgresIntegrationTest

# Control-plane quarantine/audit + real Rabbit direct replay confirm
cd ../eap-mcp
./gradlew --no-daemon test postgresIntegrationTest rabbitIntegrationTest

# MCP replay: broker confirm succeeded, central action/disposition not committed, then SIGKILL
cd ..
bash scripts/load-test/run-rel107-mcp-replay-confirm-crash.sh
```
