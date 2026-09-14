# 目前可靠性版本全鏈 k6 長窗驗證 - 2026-09-04

## 結論

新增 Wallet `TradeExecutedEvent` durable inbox、Match admission inbox、reservation cleanup
嚴格結果判定與 self-trade prevention 後，目前 worktree 以最新版完整 gate 通過一個
`200 orders/s`、`60s` 暖機加 `900s` 量測的單一 seed 全鏈診斷。

`192000/192000` 筆 HTTP 訂單全數接受，穩態完成 `100.02 trades/s`；最終
MatchEngine、Order、Wallet 各保存完全相同的 `96000` 個 trade ID，資產、Order
雙狀態、CQRS projection、Redis order book／reservation、RabbitMQ、DLQ、三服務
inbox／outbox 與 Match cleanup debt 全部收斂。

這證明目前版本在此 workload 下同時守住 safety 與 liveness，但仍是 dirty-worktree、
同機、單一 seed 的 diagnostic evidence。`capacityClaimAllowed=false`，不能稱為正式容量
上限或 production SLA；也尚未重新搜尋 200 以上的邊界。

## 測試合約

| 項目 | 設定 |
| --- | --- |
| Run ID | `CURRENT_RELIABILITY_20260904_200TPS_15M_R1` |
| Contract／schema | `external-http-matched-steady-state-chain`／`3` |
| Driver | k6 open-loop；有限、checksummed、shuffled BUY／SELL schedule |
| Workload seed | `20260905`，與 2026-09-03 的 200 orders/s baseline 相同 |
| Warm-up／measurement | `60s + 900s` |
| Target | `200 orders/s`，理論上 `100 trades/s` |
| Host | Apple Silicon arm64、10 logical CPUs、16 GiB RAM；driver 與服務同機 |
| Runtime | Java 21 啟動三個 Spring Boot JAR、三個 PostgreSQL、RabbitMQ、Redis；k6 `v2.2.0` |
| PostgreSQL | load-test profile 使用 `synchronous_commit=off` |
| Source | 五個 repo 的 commit 與 working-tree content fingerprint 在 start/end 完全相同；但都有未提交變更 |

Run provenance 保存的來源如下；`workingTreeSha256` 同時涵蓋 tracked binary diff 與
untracked file content，因此不只比較 dirty file count：

| Repository | Base commit | Working-tree SHA-256 |
| --- | --- | --- |
| eap-infra | `26dfa9068a3f06dddc3fae341b05dba516d9bb29` | `1ff1e36cff10a0908507b94038f4b2620a4ae3aa67eb805b7f5cd28381d7957f` |
| eap-common | `f3ebb7f84e73e5e61cb0f0936adbe10433be3976` | `074993e17b5d7cc0216e81da509187f5e90a336307e74877d87cb63486a3675c` |
| eap-order | `12cd15706a525a1b9c29046520f7782623cafaae` | `c5b0ba0923b22f186b6e242223319dc6dc593818467ecaed188d4f74989cebf8` |
| eap-wallet | `0fdcdcd1f513ff590387fbe88d5dde0857bb0f1b` | `291ea66307d59753fd7f715df338aa7a3794fdf9c08985628d9d5b53ea6b7531` |
| eap-matchEngine | `d42ef93d319b41f5102ab2231ab1861b5f342df6` | `5e3c150c61cbf8b3a899c8503978c19ede894742425e2039b6274c22c722129a` |

這些值識別的是實際受測 dirty source，不等同之後形成的 commit SHA。提交後若要建立
release-pinned capacity evidence，仍需在乾淨 revision 重新執行；不能把本次診斷改標。

## 結果

| 指標 | 結果 |
| --- | ---: |
| HTTP scheduled／accepted | `192000 / 192000` |
| HTTP success／dropped／out-of-range | `100% / 0 / 0` |
| 穩態 accepted orders/s | `199.99` |
| 穩態 completed trades/s | `100.02` |
| completion target ratio | `100.02%` |
| k6 HTTP latency avg／p95／p99／max | `2.37 / 4.72 / 32.89 / 342.13 ms` |
| Rabbit backlog max／slope | `128 / -0.0004/s` |
| full convergence | `967.462s`，`99.23 trades/s` |
| Workload correctness | `PASS` |
| Capacity evidence eligibility | `FAIL`：diagnostic mode、dirty source |

與相同 seed、相同 `60s + 900s`、Wallet trade inbox 加入前的 2026-09-03 baseline
相比，兩次都接受 `200.00` 級 orders/s、完成 `100.00` 級 trades/s、並在約
`967.4s` 完整收斂。新版本沒有出現巨大吞吐退化。k6 p95／p99 從
`15.89/74.98 ms` 變為 `4.72/32.89 ms`，但這只是各一輪的同機觀察值，不能把差值
歸因成可靠性改版帶來的效能提升。

## Durable-debt gate

Listener ACK 只表示工作已被服務接管，因此 schema v3 會在穩態分別量 RabbitMQ 與
Order、Wallet、Match service-owned inbox。Active backlog、oldest unresolved age 與
terminal／identity-conflict debt 必須同時通過：

| Gate | Start | End | Maximum | Slope/s | Oldest age max | Terminal max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Order inbox aggregate | `28` | `0` | `291` | `+0.0079` | `1s` | `0` |
| Wallet inbox aggregate | `42` | `3` | `389` | `+0.0121` | `1s` | `0` |
| Match admission inbox | `0` | `0` | `95` | `+0.0020` | `0s` | `0` |

這些斜率遠低於 `2 rows/s` 的 failure threshold，最大值低於 `6000`，oldest age 低於
`30s`；而且所有 service-owned debt 最終為零。瞬時 backlog 的存在是正常排隊，持續
成長、age 老化或 terminal debt 才代表系統沒有真正跟上。

目前 outbox 與 Match cleanup 只在 final convergence 檢查 active／terminal debt，尚未
納入整段穩態 slope／age。這項誠實邊界保留到 `EAP-REL-103`，不把本輪 PASS 擴張成
所有 durable worker 都有完整 SLO。

## 最終正確性

- MatchEngine／Order／Wallet 各 `96000` 筆 trade，ID set 與 fingerprint 完全一致。
- `192000` 筆 Order submission、Wallet reservation、Order reservation confirmation、
  Match admission 與使用者可見 matched order 全數完成。
- `orders_current=192000`；projection checkpoint 與 event-store max position 都是
  `384000`，lag `0`，reservation／execution 雙狀態正確。
- buyer／seller 的 energy 與 currency available/locked delta 精確；所有 locked value
  最終為 `0`。
- remaining BUY／SELL、Redis active reservation、Rabbit ready／unacked、DLQ 都為 `0`。
- Order／Wallet／Match inbox backlog 與 terminal debt為 `0`；三服務 outbox
  active／terminal debt 與 Match cleanup active／terminal debt也都是 `0`。
- required-field missing／invalid 都是空陣列，external driver exit status 為 `0`。

## 量測工具補強

本輪不是只重跑壓測，也修正了證據合約：

1. 三服務 inbox 以同一 monitor CSV 量 backlog、oldest age 與 terminal debt；已
   `APPLIED` 但發生 identity conflict 的 row 仍算 terminal debt，不會被狀態掩蓋。
2. final gate 加入三服務 outbox 與 Match cleanup active／terminal debt。
3. schema v3 缺欄或型別錯誤會 fail closed；renderer 先判 correctness failure，不能讓
   artifact 中殘留的 `capacityClaimAllowed=true` 蓋過失敗。
4. k6 threshold exit status 在 provenance／persist 前合併，driver 失敗不能產生 PASS。
5. dirty worktree 除 commit 與 dirty file count 外，另保存 tracked diff 與 untracked
   file content 的 fingerprint，並核對測試前後一致。
6. 成功後自動刪除專用 containers／volumes 與 request-level JSONL，只保留 compact
   samples、monitor、result、provenance 與可讀報表；失敗則保留現場供診斷。

## 判定與下一步

目前可誠實表達為：**最新版完整可靠性路徑已在單一 seed 的 200 orders/s 長窗通過；
沒有觀察到 Wallet trade inbox 帶來巨大效能退化。** 不能說 200 是精確 ceiling，也
不能沿用舊版 648 作為目前版本容量。

後續進度（2026-09-14）：`EAP-REL-101` 已完成 order-book generation／`run_id`
fail-closed gate 與受控 activation，且最新版短版全鏈 smoke 再次通過。依
[工程 Backlog](../backlog.zh-TW.md)，下一步是 `EAP-REL-102` 的 Match terminal
semantics；之後再處理跨服務 durable-debt SLO、inbox commit 前長時間 DB outage、
Saga timeout 與受控 DLQ recovery。

## Artifacts

Repository 保存[精簡 summary](results/2026-09-04-current-reliability-full-chain/summary.json)、
[business samples](results/2026-09-04-current-reliability-full-chain/samples.csv)與
[durable-debt monitor](results/2026-09-04-current-reliability-full-chain/monitor.csv)。兩份
CSV 都只有每秒一列，讓 throughput、slope 與 oldest-age 可被重新稽核，不包含每一筆
HTTP request 的巨大明細。本機完整結果位於：

- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-result.json`
- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-result-report.md`
- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-k6-summary.json`
- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-k6-report.md`
- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-samples.csv`
- `build/load-test-reports/http-matched-external-CURRENT_RELIABILITY_20260904_200TPS_15M_R1-monitor.csv`

原始 request-level JSONL、target schedule、logs 與專用資料卷已依成功清理規則移除。
