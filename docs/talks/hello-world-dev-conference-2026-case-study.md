# EAP AI 工程工作流實踐

Hello World Dev Conference 2026 講題：**用 AI 工作流重整事件驅動交易系統的一致性、效能與監測**

## 為什麼 EAP 需要 AI 工作流

EAP 是個人開發的事件驅動電力交易後端，涵蓋下單、資產保留、撮合與結算。一次交易跨越三個服務，必須核對 `trade_id`、資產、冪等、DLQ 與 queue drain；單一 API 或單一服務 TPS 不代表業務完成。

個人開發容易讓同一人提出假設、實作並驗收。EAP 將 AI 拆成 Product、Architect、Performance、Implementation、QA 與 Reviewer，最後由 Human Owner 決定。AI 只是 decision input，不擁有架構、風險、部署或公開宣稱權限。

## 自我審查與功能擴充

Architect、Performance、QA 與 Reviewer 預設只讀；Implementation 只執行已接受的 spec。變更必須記錄 baseline、完成定義、一致性限制、單一變因、測試與 correctness gate。角色以不同觀點挑戰個人直覺，被拒絕或無法歸因的方案也會保留。

流程已用於擴充 durable inbox、冪等、crash recovery、安全 transaction boundary，以及 mixed HTTP 與三服務核對。版本：[Order `376a4e1`](https://github.com/Yitin-tsai/eap-order/commit/376a4e181e278d2ab594e7b694aee0b87132f56e)、[Wallet `a5065d6`](https://github.com/Yitin-tsai/eap-wallet/commit/a5065d6b4eb54daead8357495e8b2bfe5f2dbc84)、[MatchEngine `b4caa39`](https://github.com/Yitin-tsai/eap-matchEngine/commit/b4caa39dc4d109de7f13318a8f0fc9439c85c7e9)、[infra `dfcd2dd`](https://github.com/Yitin-tsai/eap-infra/commit/dfcd2dd89b1bff57fd0ef0d7480af953f1ce6d83)。

## 證據決策案例

**採用：reservation cleanup batching。** TPS169 sequential contract 的 BUY-triggered throughput `664.26 -> 922.38 trades/s`、cleanup SQL 約 `30000 -> 32` batch statements、最大 backlog `14110 -> 6261`、Match-to-Wallet p95 `13.624s -> 4.478s`。前後都通過三服務 ID、資產與 drain；它仍只是 upper-bound diagnostic。

**拒絕：Wallet autocommit。** isolated settlement `11799.16 -> 20405.04 settlements/s`，full-chain mean `21.13ms -> 9.26ms`；但 postcondition 發生在 autocommit 後，錯誤不能 rollback，forced PostgreSQL rerun 又發現 reversed-role deadlock。因此恢復 explicit transaction、固定 UUID lock order，並補上 missing wallet、insufficient balance 與 concurrency tests。

## 30 分鐘分享安排

EAP 背景只占 3–8 分，共 5 分鐘，約為整場 `16.7%`；主體是工作流如何促成自我審查、功能擴充與可追溯決策。

| 時間 | 內容 |
| --- | --- |
| 0–3 分 | 個人開發的審查缺口與核心主張 |
| 3–8 分 | EAP 架構與 business-complete 定義 |
| 8–14 分 | AI 角色分工、只讀邊界與人工決策 |
| 14–22 分 | 採用與拒絕案例 |
| 22–26 分 | 對應 Jira、ADR、scoped PR、CI、Code Owner 的企業泛化 |
| 26–28 分 | 可重用模板與 correctness gate |
| 28–30 分 | 總結與提問 |

## 可帶走的方法

- 問題／假設／單一變因／證據／決策模板。
- AI role contract 與人工 checkpoint。
- correctness gate。
- throughput boundary 定義。
- rejected experiment、rollback 與 follow-up 的紀錄方法。

流程也能用於同步 API、批次、ETL 與既有系統，並對應 Jira、ADR、PR、CI 與 change approval。

## 公開證據與限制

公開證據：[README](../../README.zh-TW.md)、[Architecture](../architecture.md)、[AI workflow](../ai-engineering-workflow.md)、[Performance](../performance-report.md)、[Wallet report](../benchmarks/2026-08-05-wallet-settlement-robustness.md)、[Mixed staircase](../benchmarks/2026-08-04-balanced-mixed-http-staircase.md)。

EAP 不宣稱 `2000 completed TPS`。現行安全下界是單機短時間約 `700 accepted orders/s`、`350 completed trades/s` 的 mixed HTTP 證據；`922.38/s` 是 sequential upper bound；`20405.04/s` 是已拒絕的 isolated 診斷。Seeded、mixed、short-window、soak、isolated、historical 與 deep diagnostics 必須分開。

內容與數據來自個人公開 EAP 專案，不涉及現職公司的程式碼、架構、資料或機密。
