# EAP 專案文件索引

> 產生日期：2026-05-06 | 掃描模式：Quick Scan | 模式：full_rescan

> 2026-06-03 整理註記：部分 planning story 的狀態已落後於程式碼。請先閱讀
> [專案狀態總覽](../PROJECT_STATE.md) 與 [BMAD / Claude 文件狀態](./DOCUMENT_STATUS.md)，
> 再判斷哪些文件是目前事實、哪些只是歷史規劃。

---

## 專案概覽

- **類型**：Multi-repo workspace（6 個獨立 Gradle 專案）
- **主要語言**：Java 17
- **框架**：Spring Boot 3.5.3
- **架構**：事件驅動微服務（RabbitMQ + Redis + PostgreSQL）
- **AI 整合**：Spring AI 1.1.1 + Ollama + MCP

## 快速參考

### eap-common（共用函式庫）
- **類型**：library
- **路徑**：`/eap-common`
- **內容**：19 DTO、10 事件、3 常數類別（RabbitMQ、AuctionStatus、TradingMode）

### eap-order（訂單服務，:8080）
- **類型**：backend
- **路徑**：`/eap-order`
- **技術**：Spring Boot + JPA + WebSocket + OpenFeign + Liquibase + OpenAPI Generator
- **功能**：連續撮合下單、密封競標、市場資料推送

### eap-wallet（錢包服務，:8081）
- **類型**：backend
- **路徑**：`/eap-wallet`
- **技術**：Spring Boot + JPA + Outbox Pattern + 樂觀鎖 + Testcontainers
- **功能**：餘額管理、資產鎖定/解鎖、結算、冪等性保護

### eap-matchEngine（撮合引擎，:8082）
- **類型**：backend
- **路徑**：`/eap-matchEngine`
- **技術**：Spring Boot + Redis + Lua Scripts + Redisson
- **功能**：連續撮合、密封競標清算、訂單簿管理

### eap-mcp（MCP Server，:8083）
- **類型**：backend (MCP)
- **路徑**：`/eap-mcp`
- **技術**：Spring AI MCP 1.1.1 + OpenFeign + 交易模擬引擎
- **功能**：11 個 MCP Tools、5 種商人策略模擬

### eap-ai-client（AI Client，:8084）
- **類型**：backend (AI)
- **路徑**：`/eap-ai-client`
- **技術**：Spring AI + Ollama + MCP Client + WebFlux
- **功能**：AI 聊天介面（REST + CLI）

---

## 產生的文件

- [BMAD / Claude 文件狀態](./DOCUMENT_STATUS.md) — 文件分類、過期 story 標記、面試資產清單
- [專案概覽](./project-overview.md) — 專案摘要、架構簡圖、模組一覽、程式碼統計
- [架構文件](./architecture.md) — 完整架構設計、技術棧、RabbitMQ 拓撲、測試策略
- [API 合約](./api-contracts.md) — 所有 REST API、MCP Tools、OpenFeign 呼叫
- [資料模型](./data-models.md) — PostgreSQL 表、Redis 結構、Lua Scripts、事件/DTO
- [整合架構](./integration-architecture.md) — 連續撮合流程、密封競標流程、MCP/AI 整合
- [原始碼樹狀分析](./source-tree-analysis.md) — 完整目錄結構、關鍵檔案標註
- [開發指南](./development-guide.md) — 快速啟動、Make 指令、測試、Schema 管理

## 現有文件

- [專案狀態總覽](../PROJECT_STATE.md) — 目前專案單一入口，說明已完成、文件狀態與面試說法校準
- [README（中文）](../README.md) — 主文件、架構圖、Order Lifecycle
- [README（英文）](../README.en.md) — 英文版本
- [開發指南](../DEV-GUIDE.md) — 原始開發指南
- [使用指南](../user_guide.md) — 使用說明
- [MQ Scaling Notes](../docs/mq-scaling-notes.md) — MQ 擴展筆記
- [eap-common README](../eap-common/README.md) — 共用函式庫說明
- [eap-mcp README](../eap-mcp/README.md) — MCP 技術文件
- [eap-mcp docs/](../eap-mcp/docs/) — MCP 整合、模擬、LLM 指南
- [eap-ai-client README](../eap-ai-client/README.md) — AI Client 說明
- [eap-ai-client docs/](../eap-ai-client/docs/) — AI 建構、設定、實作文件

## 面試資產

- [履歷改善筆記](./resume-improvement-notes.md) — 履歷簡報改版決策與歷程
- [PPTX 修改 Prompt](./resume-prompt-for-claude.md) — Claude Web 產出履歷簡報用
- [PPTX v6 修正 Prompt](./resume-v6-fix-prompt.md) — 架構圖與頁面修正
- [自我介紹稿](./self-intro-scripts.md) — 3/5/10 分鐘中英文版本
- [專案深問準備](./interview-project-deepdive.md) — EAP 架構取捨、深問與反問
- [TSMC 面試準備](../docs/tsmc-interview-prep.md) — AAID IT DevOps 簡報口述稿與 Q&A

## 歷史規劃註記

- `planning/stories/1-*.md` 多數已由後續程式碼與 `cr_outputs` 工作覆蓋，保留為歷史拆解，不直接視為待辦。
- `planning/reliability-adrs.md` 是可靠性設計來源，實作狀態請以程式碼、`DOCUMENT_STATUS.md` 與 `eap-matchEngine/cr_outputs/features/*` 為準。
- 正式 load test、完整 observability、E2E benchmark 目前不列為近期待辦，可作為面試反思或 production 化前工作。

## 快速啟動

```bash
make dev-up      # 啟動 PostgreSQL + RabbitMQ + Redis
make build       # 構建所有服務
make run-all     # 啟動所有應用服務
make quick-test  # 測試交易流程
make ai-start    # 啟動 AI 服務（需 Ollama）
```
