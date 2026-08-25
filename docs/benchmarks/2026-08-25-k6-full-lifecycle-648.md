# k6 648 orders/s 完整生命週期長窗驗證 - 2026-08-25

## 決策

這次 campaign **拒絕**把同機 k6 結果當成新的容量證據，也不取代既有 release-pinned `648 orders/s` 邊界。

完整跑滿的 R1 證明兩件不同的事：

1. k6 driver gate 未通過。準備了 `622080` 個 request，但只執行 `610517` 個，產生 `11563` 個 `dropped_iterations`；實際供載為 `635.93 requests/s`，不是完整的 648。
2. 所有真正送達的 request 都回傳 2xx，而且業務鏈最終正確收斂。MatchEngine、Order 與 Wallet 各有完全相同的 `305240` 個 trade ID，資產核對成立，RabbitMQ queue／DLQ、Match reservation 與 Order inbox unapplied debt 最終皆為 0。

因此這不是「服務資料錯誤」，也不是「k6 沒有真的送 HTTP」；它是明確的 load-generator scheduling failure。後續 2048／4096 VU 校準顯示，在 16 GiB macOS 主機上繼續增加同機 VU 會與三個 JVM、三個 PostgreSQL、RabbitMQ、Redis 與監測程序爭用記憶體及 scheduler，無法得到乾淨的零 drop 長窗。

## 工作負載合約

| 欄位 | 值 |
| --- | ---: |
| Contract | `external-http-matched-steady-state-chain` |
| Driver | k6 `constant-arrival-rate` |
| Placement | co-located |
| Target | `648 total orders/s` |
| Warm-up／measurement | `60s / 900s` |
| Prepared requests／trades | `622080 / 311040` |
| Arrival pattern | shuffled BUY／SELL |
| Workload seed | `20260825` |
| Service launch | Java 21 executable jars |
| Diagnostics | light, 5-second resource samples plus 1-second business monitor |
| Evidence mode | diagnostic |
| Host | Apple Silicon, 10 logical CPUs, 16 GiB physical memory |

此 campaign 使用 dirty worktree，且 R1 執行期間新增了文件，因此 provenance 另有 `source_revision_changed_during_run`。即使 driver gate 通過，也不能升級成 release-pinned capacity claim。

## R1：648 VU，完整 960 秒

Run ID：`K6_FULL_648_60S_900S_SEED_20260825_R1`

### Driver 結果

| Metric | 結果 |
| --- | ---: |
| Expected requests | `622080` |
| Executed／2xx requests | `610517 / 610517` |
| Dropped iterations | `11563` |
| Out-of-range iterations | `0` |
| HTTP failure ratio | `0%` |
| Actual request rate | `635.93/s` |
| Latency p50／p95／p99／max | `9.43 / 870.02 / 1714.82 / 3876.55 ms` |
| Driver decision | **REJECT** |

k6 的 VU 必須涵蓋同時仍在等待 response 的 requests。用 Little's Law 做近似，`648/s * 1.7148s p99` 已需要約 `1111` 個 concurrent VU；R1 只有 648。這不是精確的 sizing 公式，但足以解釋為何 median 很低時仍會在 latency tail 發生 drop。

### Business 結果

| Metric | 結果 |
| --- | ---: |
| Steady accepted | `635.08 orders/s` |
| Steady completed | `310.16 trades/s` |
| Completion target ratio | `95.73%` of the pairable target actually offered |
| Maximum sampled backlog | `2841` |
| Backlog slope | `+0.9992/s` |
| Full convergence | `305240 trades in 996.482s` |
| Full-convergence rate | `306.32 trades/s` |
| Match／Order／Wallet trades | `305240 / 305240 / 305240` |
| Trade-ID equality | **PASS** |
| Final BUY／SELL open remainder | `0 / 37` |
| Final Rabbit queues／DLQ | `0` |
| Active Match reservations | `0` |
| HTTP 429／503／other failures | `0 / 0 / 0` |

37 個 SELL remainder 是 dropped schedule 造成 BUY／SELL 實際接受數不完全相等後的預期結果，不是遺失 trade。Wallet 最終保留 37 單位 seller energy，其他 matched assets 完成核對。

Order 在壓力期間曾把 `4428` 個 trade event 放入 durable retry inbox。最後全部為 `APPLIED`、unapplied 為 0；Match persisted 到 Order application 的 p95／p99 是 `900.38 / 2224.01 ms`，最大值 `109278 ms`。Rabbit queue 清空但 Order durable count 暫時落後，正是 service-owned inbox debt 與 broker backlog 必須分開量測的實例。

## VU 校準實驗

| Run | VU | 執行狀態 | 觀察 |
| --- | ---: | --- | --- |
| R1 | 648 | 完整跑滿 | `11563` drops；所有 `610517` 個已送 request 最終正確收斂 |
| R2 | 2048 | 約 496 秒時 fail-fast 中止 | 中止前已觀察 `1776` drops；`158801` 個已形成的 trades 最終在三服務相等，queue／reservation 歸零 |
| R3 | 4096 | 同機資源失真後中止 | 至少 `25469` drops、實際 request timeout、monitor 約 14 秒停頓；early backlog peak `20693`，不再是乾淨的 capacity experiment |

R2／R3 是 rejected calibration，不是可與 R1 throughput 直接平均的重複實驗。中止後沒有把 raw run 偽裝成完整 summary；它們的作用是阻止下一次在同機上盲目增加 VU。

## 為什麼這仍證明 k6 腳本有用

如果腳本只是一個 `curl` 包裝，不會同時產生以下互相獨立的證據：

- `constant-arrival-rate` 固定到達排程與 `dropped_iterations`；
- exact `http_reqs == 622080` threshold；
- 100% 2xx check、HTTP failure、p50／p90／p95／p99／max latency；
- 預先生成且 checksummed 的有限 request schedule；
- 每秒比對 Match／Order／Wallet durable progress 與 Rabbit backlog；
- 結束後比對完整 `trade_id` 集合、資產、order-book remainder、reservation、queue、DLQ 與 inbox debt。

R1 被拒絕正代表 gate 有作用：HTTP 全部成功、業務資料正確仍不足以掩蓋 11563 個未排程 request。報表把 driver health 與 service correctness 分開，避免用一個好看的平均 TPS 取代完整判斷。

## 架構與工具結論

- k6 已通過 100 orders/s 模組化 smoke；它適合 workload module、threshold 與 request-level latency 分析。
- k6 沒有在這台同機環境通過 648 orders/s 的完整 long-window driver gate。
- 648 個 VU 太少；2048／4096 個 VU 又開始干擾被測服務。繼續增加到 HTTP timeout 所需的理論上限，只會測主機 swap／scheduler，不會得到更真實的 EAP 容量。
- 現有 release-pinned 648 capacity boundary 仍由既有 Java／Vegeta campaign 支持，不因本次 k6 diagnostic 上調或下調。
- 下一個可判定實驗不是再加本機 VU，而是實作 remote-host k6 preflight／artifact transfer，或使用已存在的 remote Vegeta path 做同 commit、seed、window 的 control。

## Artifact 邊界

版本庫只保留[精簡 summary](results/2026-08-25-k6-full-lifecycle-648/summary.json)。完整 `k6.jsonl`、monitor、diagnostics、manifest 與自動產生報表仍位於本機 `build/load-test-reports/`，屬於可丟棄原始資料，不應整包 commit。

本次不修改服務 business logic、不放寬 threshold，也不變更現行公開容量宣稱。
