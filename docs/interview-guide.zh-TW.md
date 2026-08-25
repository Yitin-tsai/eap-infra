# EAP 面試快速入口

這份文件是面試前的導覽，不取代架構與效能報告。EAP 的定位是學習型後端專案：重點不是模擬一間完整交易所，而是用可執行、可測量的系統練習交易處理、微服務責任、非同步事件、一致性與效能工程。

## 30 秒介紹

> 我獨立開發了一套 Java／Spring Boot 的事件驅動電力交易後端。Order、Wallet 與 MatchEngine 分別負責訂單、資產與撮合，透過 RabbitMQ、Transactional Outbox、冪等 Consumer 和 Redis Lua，在沒有分散式交易的前提下處理下單、驗資、撮合、結算與取消訂單。我不只量 HTTP TPS，而是用三個服務的持久化 trade ID、資產、queue、DLQ 與 retry debt 判斷交易是否真正完成。目前可公開支持的是單機、兩個 seed、各 15 分鐘的 `648 accepted orders/s` 壓力邊界，完整流程約 `301–310 trades/s`，不是正式環境 SLA。

## 系統現在能做什麼

| 模組 | 已實作功能 | 主要學習重點 |
| --- | --- | --- |
| Order | HTTP 下單、CDA 訂單生命週期、事件流、可重建 projection、非同步取消訂單；TDA 出價與結果查詢 | Event Sourcing、Outbox、Inbox、樂觀版本、命令／讀取模型 |
| Wallet | 驗資、資產鎖定、CDA 冪等成交結算、取消訂單後釋放未成交資產；TDA 驗資與結算 | 本地交易、鎖順序、冪等、重複與亂序事件 |
| MatchEngine | Redis 訂單簿、價格時間優先、CDA 撮合、成交持久化、取消訂單與撮合競爭判定、reservation 復原；TDA 排程清算 | Redis Lua、單一撮合權威、當機復原、hot path |
| Common | 跨服務 Event 與 DTO 契約 | 相容性與契約測試 |
| MCP／AI Client | 受控工具與 AI 實驗 | Control plane 與核心交易路徑隔離 |

一筆 CDA 交易的主線是：

```text
HTTP 下單
  -> Order 寫入命令事件與 outbox
  -> Wallet 驗資並鎖定資產
  -> MatchEngine 用 Redis Lua 撮合
  -> MatchEngine 寫入 TradeExecuted 與 outbox
  -> Order 套用成交狀態 + Wallet 結算資產
  -> 外部驗證三服務 trade ID、資產與所有處理債務
```

取消訂單不是同步刪除。Order 先回傳 `202 Accepted` 與 `cancellationId`；MatchEngine 確保同一份剩餘數量不會同時被撮合與取消；Wallet 只依成功結果冪等釋放資產；如果取消結果早於成交事件到達 Order，Order 會先保存結果並等待前置成交套用完成。

## 一致性與架構怎麼說

| 問題 | 設計回答 |
| --- | --- |
| 為什麼不用分散式交易？ | 每個服務只提交自己擁有的狀態；跨服務接受最終一致，並用 outbox、重試和對帳補上可靠性。 |
| DB 成功但 MQ 發布失敗怎麼辦？ | 狀態與 outbox 同交易提交，relay 等 publisher confirm 後才標示完成。 |
| RabbitMQ 重複投遞怎麼辦？ | Consumer 假設 at-least-once，以 business ID、唯一約束與本地冪等紀錄吸收重複。 |
| 取消和撮合同時發生怎麼辦？ | MatchEngine 是唯一決策者；Redis Lua 讓兩個動作競爭同一份訂單簿狀態，只有一方能取得剩餘量。 |
| 事件亂序怎麼辦？ | Order 與 Wallet 保存本地處理事實；前置狀態尚未到齊時進入可重試 inbox，而不是覆寫或丟棄。 |
| 怎樣才算完成一筆交易？ | MatchEngine、Order、Wallet 的 durable trade ID 完全一致、資產核對正確，且 queue、DLQ、outbox／inbox 與 cleanup debt 清空。 |
| Redis 掛掉怎麼辦？ | 個別 reservation 有持久化 cleanup／reconciliation；但整個訂單簿遺失的自動重建尚未完成，現行安全做法是停止 admission，從持久化事實重建與驗證後再開放。 |

## 效能怎麼說才精確

- 目前正式文件支持的是同一台 10 logical CPU、16 GiB Apple Silicon 主機上的測試結果，不是 production SLA，也不能外推成叢集容量。
- 兩個 release-pinned seed，各以 `648 accepted orders/s` 跑 60 秒 warm-up 加 900 秒量測；每輪接受 `622,080` 張訂單並收斂成 `311,040` 筆三服務一致交易。
- 兩輪完整流程為 `309.73` 與 `301.14 trades/s`。輸入再提高後，完成速率沒有等比例增加，CPU、連線池、tail latency 與 drain time 反而上升，所以把 648 稱為「已重複驗證的單機壓力邊界」，不稱為舒適容量。
- 2026-08-24 取消責任調整後的單一 dirty-worktree 回歸，在相同 `648 orders/s` 下接受全部 `622,080` 張訂單，完整收斂 `311,040` 筆交易，為 `322.44 trades/s`；它證明未觀察到正常路徑回歸，但因來源未提交且只有一個 seed，不用來改寫正式容量宣稱。
- 元件隔離測試曾量到 Match listener 約 `918.46 persisted trades/s`，直接下游 fanout 約 `1972.77 durable trades/s`，Match relay加下游約 `2125–2521 trades/s`。這些用來定位整合瓶頸，不能和完整 HTTP 流程的 TPS 混用。

## 優點

- 服務邊界依「誰擁有不可爭議的事實」劃分，而不是為了微服務數量而拆分。
- 正面處理 at-least-once、重複、亂序、當機與局部失敗，能展示比 CRUD 更深入的後端能力。
- Redis Lua、PostgreSQL transaction／lock／index、RabbitMQ outbox／DLQ、JVM scheduler 與 connection pool 都有真實案例。
- 效能宣稱有工作負載、版本、完成語意與正確性關卡；失敗和被拒絕的最佳化也保留。
- 能說明人如何用 AI 做角色化自我審查，又不把 AI 當成自動核准者。

## 限制與下一步

- 這是單人、單機學習專案，沒有 production 多區部署、正式 SLO、容量規劃與長期 on-call 證據。
- CDA 的證據最完整；TDA 仍有直接發布、重送冪等、失敗回授與整場收斂缺口，不能沿用 CDA TPS。
- 驗證使用 domain `userId`，尚未建置完整 authentication、authorization、API gateway 與防濫用邊界。
- Redis 全量遺失後的自動訂單簿重建與 readiness gate 尚未實作。
- 同機 648 已出現資源競爭；下一個有效實驗應先補 per-stage durable-debt slope，再考慮分離 load generator 或依 market 分片。

這些限制不是要藏起來，而是面試時可用來展示：知道目前證據能支持什麼，也知道下一個工程投資應解決什麼。

## 三個可展開的面試故事

1. **TPS 定義被推翻。** 一開始容易把「送出 2,000 requests/s」當作系統有 2,000 TPS；後來把完成條件改成三服務持久化一致、資產正確與所有 debt 清空，最終誠實留下 648 accepted orders/s、約 301–310 completed trades/s 的邊界。
2. **快但不安全的最佳化被拒絕。** Wallet autocommit 的隔離吞吐曾從約 `11.8k` 提升到 `20.4k settlements/s`，但錯誤無法 rollback，併行測試也找到死結；因此恢復明確交易與固定 UUID 鎖順序。結論是正確性先於漂亮數字。
3. **人工質疑改變取消設計。** 原設計讓 Wallet 投影每張訂單的剩餘量；重新檢查 ownership 後，讓 MatchEngine 決定精確未成交餘量，Wallet 只記錄取消套用並釋放資產，移除不必要的跨服務狀態複製。

## 建議閱讀順序

- **面試前 5 分鐘：** 本文件。
- **再花 10 分鐘：** [中文 README](../README.zh-TW.md)與[架構文件](architecture.zh-TW.md)。
- **準備效能追問：** [效能報告](performance-report.md)與[壓測分類](benchmarks/load-test-taxonomy.md)。
- **準備取消訂單深挖：** [取消責任與回歸報告](benchmarks/2026-08-24-cancellation-ownership-and-regression.md)。
- **準備 AI／工作方法題：** [AI 工程工作流](ai-engineering-workflow.md)與 [Hello World Dev 案例](talks/hello-world-dev-conference-2026-case-study.md)。
