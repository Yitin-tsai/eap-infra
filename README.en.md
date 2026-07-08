**English** | **[中文](README.md)**

# EAP Workspace

> Start with [PROJECT_STATE.md](PROJECT_STATE.md) for the canonical project map.

This workspace contains the multi-package EAP project. The root README is an index, not the place for service-level details.

## Read this first

- [PROJECT_STATE.md](PROJECT_STATE.md) - current project state and reading order
- [DEV-GUIDE.md](DEV-GUIDE.md) - local startup and workflow
- [docs/](docs/) - technical notes on sequencing, MQ reliability, and fairness
- [_bmad-output/](./_bmad-output/) - resume, interview, intro, and historical design notes

## Service READMEs

- [eap-order/README.md](eap-order/README.md) - order entry and lifecycle
- [eap-wallet/README.md](eap-wallet/README.md) - validation, reservation, settlement, idempotency
- [eap-matchEngine/README.md](eap-matchEngine/README.md) - Redis matching and auction
- [eap-trigger/README.md](eap-trigger/README.md) - Go conditional-order trigger service
- [eap-mcp/README.md](eap-mcp/README.md) - MCP control plane
- [eap-ai-client/README.md](eap-ai-client/README.md) - LLM orchestration client
- [eap-common/README.md](eap-common/README.md) - shared contracts

## One-line summary

EAP is an event-driven electricity trading platform built with Spring Boot microservices, RabbitMQ, Redis ZSET + Lua, PostgreSQL, and Spring AI + MCP. The project focuses on transaction correctness, idempotency, event reliability, matching atomicity, and auditability rather than CRUD.

## Core themes

- Wallet-first validation
- RabbitMQ choreography saga
- Redis atomic order book
- Outbox + DLQ + idempotency
- Market sequencing and fairness trade-offs

## Quick start

```bash
make dev-env
make dev-up
make run-all
```

## Build checks

```bash
make build
make build-trigger
make test-trigger
```

Use `make build-order`, `make build-wallet`, `make build-match`, `make build-mcp`, or `make build-ai` to validate one service at a time.

`make dev-env` pins Gradle and Go caches to workspace-local `.cache/`, avoiding build failures caused by home-directory permissions on a new machine or restricted shell.

See [DEV-GUIDE.md](DEV-GUIDE.md) for the full workflow.
