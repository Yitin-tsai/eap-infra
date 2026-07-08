**[English](README.en.md)** | **中文**

# EAP Workspace

> 專案總入口請先看 [PROJECT_STATE.md](PROJECT_STATE.md)。

這個 workspace 是 EAP 電力交易平台的多包專案集合。根目錄 README 只做導覽，不承擔各服務細節說明。

## 先看哪些文件

- [PROJECT_STATE.md](PROJECT_STATE.md) - 目前專案狀態與閱讀順序
- [DEV-GUIDE.md](DEV-GUIDE.md) - 本地啟動、Makefile、開發流程
- [docs/](docs/) - 交易公平性、MQ 可靠性、sequencing 等技術筆記
- [_bmad-output/](./_bmad-output/) - 履歷、面試、自介與歷史設計文件

## 各服務 README

- [eap-order/README.md](eap-order/README.md) - 訂單入口與狀態流轉
- [eap-wallet/README.md](eap-wallet/README.md) - 驗資、鎖額、結算與冪等
- [eap-matchEngine/README.md](eap-matchEngine/README.md) - Redis 撮合與 auction
- [eap-trigger/README.md](eap-trigger/README.md) - Go 條件單觸發服務
- [eap-mcp/README.md](eap-mcp/README.md) - MCP control plane
- [eap-ai-client/README.md](eap-ai-client/README.md) - LLM orchestration client
- [eap-common/README.md](eap-common/README.md) - Shared contracts

## 一句話定位

EAP 是一個事件驅動的電力交易平台，以 Spring Boot 微服務、RabbitMQ、Redis ZSET + Lua、PostgreSQL、Spring AI + MCP 建立可展示的交易系統工程作品。重點不是 CRUD，而是交易流程中的一致性、冪等性、事件可靠性、撮合原子性與可審計性。

## 核心主線

- Wallet-first validation
- RabbitMQ choreography saga
- Redis atomic order book
- Outbox + DLQ + idempotency
- Market sequencing 與 fairness trade-off

## 目錄結構

```text
eap-workspace/
├── eap-order/
├── eap-wallet/
├── eap-matchEngine/
├── eap-trigger/
├── eap-mcp/
├── eap-ai-client/
├── eap-common/
├── docs/
├── _bmad-output/
├── PROJECT_STATE.md
└── DEV-GUIDE.md
```

## 快速啟動

```bash
make dev-env
make dev-up
make run-all
```

## 建置檢查

```bash
make build
make build-trigger
make test-trigger
```

單一服務可用 `make build-order`、`make build-wallet`、`make build-match`、`make build-mcp`、`make build-ai` 逐個驗證。

`make dev-env` 會把 Gradle / Go cache 固定到 workspace 的 `.cache/`，避免新電腦或受限環境因為家目錄權限造成建置失敗。

詳細流程請看 [DEV-GUIDE.md](DEV-GUIDE.md)。
