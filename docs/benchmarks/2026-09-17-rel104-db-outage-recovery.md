# 2026-09-17 REL-104：CDA inbox commit 前 DB outage recovery

> 證據類型：failure-injection correctness／liveness diagnostic  
> 不可用來宣稱 capacity、TPS ceiling 或 production SLA

## 要回答的問題

RabbitMQ 已投遞合法事件、但 consumer 的 PostgreSQL 在 durable inbox／local transaction
commit 前中斷至少 60 秒時，事件是否會：

1. 留在 durable source queue，而不是大量進 shared DLQ；
2. 讓 consumer 停止拉取，避免無 backoff 的 hot loop；
3. 在 DB 恢復後自動 resume／drain，不需要人工 redrive；
4. 最終只留下正確且不重複的 business effect；
5. 以服務完整固定清單證明 inbox、outbox、projection／cleanup 等 durable debt 都歸零。

## Order＋Wallet TradeExecuted fanout

執行：

```bash
TRADES=200 TARGET_TRADE_TPS=100 TIMEOUT_SECONDS=300 \
DB_OUTAGE_SECONDS=60 PRE_PUBLISH_DELAY_SECONDS=3 \
RUN_ID=REL104_ORDER_WALLET_DB_OUTAGE_60S_R6 \
BUILD_JARS=false KEEP_INFRA=true \
bash scripts/load-test/run-trade-consumer-fanout-probe.sh
```

結果：

| Gate | 結果 |
| --- | ---: |
| Requested／measured outage | 60／73 秒 |
| Consumer pause latency | 24 秒 |
| Pause 維持至 DB recovery | PASS |
| Publisher confirm | 200／200 |
| Order durable application | 200／200 |
| Wallet durable settlement | 200／200 |
| Order／Wallet Trade ID missing／unexpected | 0／0 |
| Order／Wallet source queue peak | 200／200 |
| Source queue final | 0／0 |
| Shared DLQ peak／final | 0／0 |
| Order circuit opened／probe／failure／final open | 1／6／4／0 |
| Wallet circuit opened／probe／failure／final open | 1／6／4／0 |
| Order／Wallet exact durable-debt snapshot | fresh、healthy、全零 |
| Correctness gate | PASS |

`fanoutConvergenceSeconds=94.77` 包含 60 秒故障、偵測、probe、staggered resume 與 drain，
不能解讀成 happy-path latency 或 throughput。測試在 source queue 有 backlog 時要求兩條
queue 的 consumer count 都是 0，並在 DB 啟動前再檢查一次，避免只看到 circuit log 就
誤稱已停止消費。

Order 快照精確核對六項固定工作：reservation result inbox、trade inbox、cancellation
result inbox、reservation released inbox、event outbox、`orders_current` projection。
Wallet 精確核對 order submission／cancellation result／trade inbox 與 event outbox。

提交版 artifact：
[Order／Wallet R6 JSON](results/2026-09-17-rel104-order-wallet-db-outage-r6.json)。本機 raw
輸出仍位於 `build/load-test-reports/trade-consumer-fanout-REL104_ORDER_WALLET_DB_OUTAGE_60S_R6-rel104-evidence.json`。

## MatchEngine order admission

執行：

```bash
EVENTS=200 TARGET_TPS=100 DB_OUTAGE_SECONDS=60 TIMEOUT_SECONDS=240 \
RUN_ID=REL104_MATCH_DB_OUTAGE_60S_R2 KEEP_INFRA=true BUILD_JAR=true \
bash scripts/load-test/run-rel104-match-db-outage-recovery.sh
```

結果：

| Gate | 結果 |
| --- | ---: |
| Requested／measured outage | 60／71 秒 |
| Consumer pause latency | 20 秒 |
| Pause 維持至 DB recovery | PASS |
| Published admission events | 200 |
| Admission inbox／`APPLIED` rows | 200／200 |
| Shared DLQ before／after | 0／0 |
| Circuit opened／probe／failure／final open | 1／6／4／0 |
| Exact durable-debt snapshot | fresh、healthy、五項全零 |
| Final gate | PASS |

Match 快照精確核對 order admission inbox、trade outbox、reservation cleanup、order
cancellation 與 reservation reconciliation。測試使用 `publish-only-retain`：publisher
confirm 後保留 source queue，避免一般 `publish-only` 診斷模式的事後 purge 破壞 outage
recovery 測試。

提交版 artifact：
[Match R2 JSON](results/2026-09-17-rel104-match-db-outage-r2.json)。本機 raw 輸出仍位於
`build/load-test-reports/rel104-match-db-outage-REL104_MATCH_DB_OUTAGE_60S_R2-result.json`。

## Poison path 與回歸測試

`WalletTradeRetryDeadLetterIT` 使用真實 RabbitMQ 與 REL-104 custom recoverer：poison
handler 連續失敗兩次後，原訊息進入設定的 DLQ；DB circuit 從未被開啟。三服務
recoverer unit tests 也驗證 SQL／JDBC connectivity failure 會 requeue＋open circuit，而
schema／invariant／unknown exception 會 reject without requeue。

2026-09-17 完整 unit suites：`eap-common`、`eap-order`、`eap-wallet`、
`eap-matchEngine` 全數通過；Wallet Rabbit integration suite 另行通過。QA 最終判定無
P0／P1 correctness 或 liveness blocker。

## 驗證過程找到並修正的問題

- 並行 delivery 在 circuit probe 期間重複 open，可能重設 recovery generation；現在只由
  `CLOSED` 或恢復中再次失敗的 `RESUMING` 建立新 generation。
- stale resume callback 可能把剛重新開啟的 circuit 覆寫成 `CLOSED`；最後關閉改用
  generation check 加 `compareAndSet(RESUMING, CLOSED)`。
- circuit 只記住並恢復「自己停止」的 listener；原本已被其他 control plane 停止的
  listener 不會被誤啟動。stop／start lifecycle 例外會重試，不會讓 recovery worker 消失。
- standalone `ConnectException` 可能來自 RabbitMQ／Redis；classifier 只把 SQL／JDBC
  cause chain 內的 transport failure 視為 DB outage。
- Order batch 若大於 1，一筆 poison payload 可能拖累同批合法 delivery；REL-104 rollout
  將兩條 CDA manual batch 的預設固定為 1，逐筆 poison isolation 另行優化。
- 原始 focused probe 關閉了 Order scheduler，造成 durable-debt snapshot stale 且 projection
  必然欠帳；正式版保留 scheduler／projection，讓完整 owner-local debt 能真的收斂。
- Java `Instant` 帶小數秒；快照 validator 現在接受合法的 UTC ISO-8601 fractional seconds，
  仍拒絕錯誤 service、work drift、stale、observation failure 或非零 debt。

完整設計、錯誤分類與限制見
[ADR-004](../adr/ADR-004-cda-inbox-precommit-db-outage-recovery.zh-TW.md)。
