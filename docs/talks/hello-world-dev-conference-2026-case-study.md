# EAP AI 工程工作流實踐

Hello World Dev Conference 2026 講題：**用 AI 工作流重整事件驅動交易系統的一致性、效能與監測**

本議程的核心不是介紹 EAP 本身，而是以一個可公開檢查的多 repository 專案，示範個人開發者如何使用 AI 建立結構化反對意見、驗證假設並拒絕錯誤修改。EAP 是承載證據的工程案例，不是演講要推廣的產品。

## 為什麼 EAP 需要 AI 工作流

EAP 是個人開發的事件驅動電力交易後端，支援連續雙向競價（CDA）與定時集合競價（TDA）。本次工程案例聚焦已建立完整證據鏈的 CDA：一次交易跨越三個服務，必須核對 `trade_id`、資產、冪等、DLQ 與 RabbitMQ 佇列是否清空；單一 API 或單一服務 TPS 不代表業務完成。MatchEngine 只擁有成交事實，不保存 Order 或 Wallet 的完成狀態；跨服務結果由交易路徑外的驗證工具核對。TDA 用於說明「功能存在不代表可靠性與容量已被證明」，不沿用 CDA 的壓測數據。

個人開發容易讓同一人提出假設、實作並驗收，最後只尋找支持原始想法的證據。AI 能加快分析與寫程式，也可能放大這種確認偏誤。EAP 因此將 AI 拆成產品範圍、架構審查、效能分析、實作、品質驗證與最終審查等角色，要求它們分別提出限制、反例、失敗條件與證據需求，最後仍由人工負責人決定。AI 只是決策參考，不擁有架構、風險、部署或公開宣稱權限。

## 自我審查與功能擴充

架構、效能、品質驗證與最終審查角色預設只讀；實作角色只執行已接受的規格。已接受的規格、重要反對意見、實際修改、測試命令、benchmark artifact、採用／拒絕決策與公開宣稱邊界都要留下可追溯紀錄。角色以不同觀點挑戰個人直覺，被拒絕、無法判定或尚待下一個實驗的方案也會保留。

這些角色不是簡報中的抽象名稱，而是 repository 內版本控制的 [實際 Codex skills](../../skills/)，每份工件都定義輸入、必要產出、修改權限、禁止事項與停止條件。它們是一套結構化的個人自我審查方法，不等同於組織中的獨立人員審查，也不能取代正式 code review 與 change approval。

流程已用於擴充持久化收件匣、冪等、當機復原、安全的資料庫交易邊界，以及混合 HTTP 壓測與三服務核對。最近的自我審查也發現：TDA 雖已能出價與清算，但直接發布事件、出價重送冪等、驗資拒絕回授與整場收斂尚未達 CDA 證據標準，因此保留功能、公開缺口，而且不沿用 CDA TPS。

本文不把不同日期的程式與效能證據包成同一版本。排程隔離與錯誤高流量案例的實作基準為 [Order `51165d3`](https://github.com/Yitin-tsai/eap-order/commit/51165d3)、[Wallet `3811169`](https://github.com/Yitin-tsai/eap-wallet/commit/3811169)、[MatchEngine `853ac9b`](https://github.com/Yitin-tsai/eap-matchEngine/commit/853ac9b) 與 [infra `00ba2a0`](https://github.com/Yitin-tsai/eap-infra/commit/00ba2a0)。後續 release-pinned `600 orders/s` 長時間證據使用 [Order `c95381c`](https://github.com/Yitin-tsai/eap-order/commit/c95381c)、Wallet `3811169`、[MatchEngine `ed55214`](https://github.com/Yitin-tsai/eap-matchEngine/commit/ed55214) 與 [infra `976114c`](https://github.com/Yitin-tsai/eap-infra/commit/976114c)；第二個 seed 使用測試工具修正版 [Order `d8564b7`](https://github.com/Yitin-tsai/eap-order/commit/d8564b7) 與 [infra `2e95260`](https://github.com/Yitin-tsai/eap-infra/commit/2e95260)，未改變核心業務路徑。2026-08-14 的短窗與隔離診斷另見各自 artifact，不用來回寫前述案例版本。

工作流把講題的三個工程面向連在一起：一致性審查決定服務責任、交易邊界與跨服務正確性關卡；效能分析以 baseline、單一變因及相同工作負載比較修改；監測則綜合 RabbitMQ `ready`／`unacked`、DLQ、PostgreSQL、Hikari 與應用程式計時資料進行歸因，並把低觀測容量測試與可能產生 observer effect 的深度診斷分開。最後只有人工負責人能把這些證據轉成採用、拒絕或下一個實驗。

## 證據決策案例

**採用：撮合訂單保留清理批次化。** TPS169 依序測試的 BUY 觸發完成速率為 `664.26 -> 922.38 trades/s`，清理 SQL 約由 `30000` 次降至 `32` 次批次陳述式，最大積壓為 `14110 -> 6261`，MatchEngine 到 Wallet 的 p95 延遲為 `13.624s -> 4.478s`。修改前後都通過三服務 ID、資產與清空關卡；它仍只是上限診斷。

**拒絕：Wallet 自動提交。** 隔離結算吞吐量為 `11799.16 -> 20405.04 settlements/s`，全鏈 Wallet 資料庫交易平均時間為 `21.13ms -> 9.26ms`；但後置條件發生在自動提交之後，錯誤無法回復，強制重新執行 PostgreSQL 測試又發現買賣角色對調時的死結。因此恢復明確資料庫交易、固定 UUID 鎖定順序，並補上 Wallet 不存在、餘額不足與併行測試。

**採用後仍被正確性關卡推翻高 TPS 宣稱：MatchEngine 排程與撮合訂單保留修復。** 監測先發現 1 條排程執行緒同時承擔撮合訂單保留清理與交易事件外送。相同條件比較中，排程隔離讓 800 階段從 `167.93` 提升到 `383.45 trades/s`、最大積壓從 `4090` 降到 `246`，並通過完整核對，因此採用。後續較高階梯雖一度通過 900，最終卻發現 1 張買單被重複撮合，整次高 TPS 結果因此作廢。修正方式是讓 Redis 撮合訂單保留狀態直接核對預期 `tradeId`；修正後 52500 筆訂單全部收斂，但 800 仍未穩定通過。最新 release-pinned 證據以 2 個 workload seed 各執行 15 分鐘 `648 accepted orders/s`；兩輪皆完整收斂，因此列為目前最高可重複的同機下界。但兩輪完整流程只有 `309.73` 與 `301.14 trades/s`，仍落在先前 624 的範圍，且 CPU、連線池與 tail latency 壓力更高，所以將 648 定義為壓力邊界，不宣稱更高容量或充足餘裕。較舊版本約 `700 accepted orders/s` 的短窗結果保留為歷史診斷，不混成目前容量宣稱。這個案例示範 AI 輔助假設如何被觀測資料採用，也如何被正確性證據限制。

## 30 分鐘分享安排

EAP 的專案背景與架構介紹安排在 3–8 分，共 5 分鐘，約為整場 `16.7%`。後續仍以 EAP 的採用與拒絕案例作為證據，但教學主體是可移植的 AI 工作流、驗證方式與人工決策，不是繼續介紹專案功能。

| 時間 | 內容 |
| --- | --- |
| 0–3 分 | 個人開發的審查缺口與核心主張 |
| 3–8 分 | EAP 架構與完整業務交易定義 |
| 8–14 分 | AI 角色分工、只讀邊界與人工決策 |
| 14–22 分 | 採用、拒絕與尚待驗證案例 |
| 22–26 分 | 對應 Jira、ADR、限定範圍 PR、CI、Code Owner 的企業泛化 |
| 26–28 分 | 可重用模板與正確性關卡 |
| 28–30 分 | 總結與提問 |

## 可帶走的方法

- 問題／假設／單一變因／證據／決策模板。
- AI 角色契約與人工檢查點。
- 正確性關卡。
- 吞吐量邊界定義。
- 已拒絕實驗、回復方式與後續工作的紀錄方法。

流程也能用於同步 API、批次、ETL 與既有系統，並對應 Jira、ADR、PR、CI 與變更核准。

## 公開證據與限制

公開證據：[README](../../README.zh-TW.md)、[系統架構](../architecture.md)、[AI 工程工作流](../ai-engineering-workflow.md)、[效能報告](../performance-report.md)、[Wallet 穩健性報告](../benchmarks/2026-08-05-wallet-settlement-robustness.md)、[歷史混合 HTTP 階梯式壓測](../benchmarks/2026-08-04-balanced-mixed-http-staircase.md)、[排程隔離診斷](../benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md)、[短窗邊界重測](../benchmarks/2026-08-14-canonical-mixed-short-window-boundary.md)與[最新 648 持續壓力邊界](../benchmarks/2026-08-18-release-pinned-648-sustained-boundary.md)。

EAP 不宣稱 `2000 completed TPS`。目前 release-pinned 公開下界是 2 個 workload seed 都通過的單機 `648 accepted orders/s` 等級 CDA 隨機混合 HTTP 15 分鐘證據；兩輪 full-lifecycle 分別為 `309.73` 與 `301.14 trades/s`，而且同機 CPU、連線池與 tail latency 壓力明顯，因此是壓力邊界，不是正式環境容量。較舊版本另有單機短時間 `699.98 accepted orders/s`、`346.12 same-window trades/s`、`320.47 full-lifecycle trades/s` 的歷史診斷。`922.38/s` 是 CDA 依序上限診斷；`20405.04/s` 是已拒絕版本的隔離診斷。已確認訂單、混合流量、短時間窗、長時間、元件隔離、歷史版本、深度診斷與 TDA 必須分開。

內容與數據來自個人公開 EAP 專案，不涉及現職公司的程式碼、架構、資料或機密。
