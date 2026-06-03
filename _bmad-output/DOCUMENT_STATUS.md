# BMAD / Claude 文件狀態

> 最後整理：2026-06-03  
> 原則：面試相關文件完整保留；歷史設計與 story 保留為脈絡，但不再直接視為目前待辦。

## 文件分類

### A. 目前可信的專案理解入口

| 文件 | 狀態 | 備註 |
|------|------|------|
| `project-overview.md` | 保留 | 專案摘要與模組一覽 |
| `architecture.md` | 保留 | 架構、可靠性模式、部署與測試策略 |
| `integration-architecture.md` | 保留 | 連續撮合、拍賣、MCP/AI 整合流程 |
| `data-models.md` | 保留 | DB / Redis / DTO / Event 模型 |
| `api-contracts.md` | 保留 | REST、MCP Tools、Feign 呼叫 |
| `source-tree-analysis.md` | 保留 | 檔案導覽 |
| `development-guide.md` | 保留 | 啟動、測試、schema、audit trail 說明 |

### B. 面試與履歷資產，必須保存

| 文件 | 狀態 | 備註 |
|------|------|------|
| `resume-improvement-notes.md` | 保留 | 履歷策略與改版歷程 |
| `resume-prompt-for-claude.md` | 保留 | PPTX v6 生成 prompt |
| `resume-v6-fix-prompt.md` | 保留 | PPTX v7 修正 prompt |
| `self-intro-scripts.md` | 保留 | 自介稿 |
| `interview-project-deepdive.md` | 保留 | 專案深問與反問 |
| `linkedin-03-mq-scaling-tradeoff.md` | 保留 | MQ 擴充取捨敘事 |

### C. 已落地或被後續工作覆蓋的早期 planning

| 文件 | 判斷 |
|------|------|
| `planning/reliability-adrs.md` | 保留為 ADR 背景；實作狀態已比文件更新 |
| `planning/stories/1-1-dlx-dlq-declaration.md` | 已由後續程式碼落地，狀態欄過期 |
| `planning/stories/1-2-queue-dlx-binding-retry.md` | 已由後續程式碼落地，狀態欄過期 |
| `planning/stories/1-3-outbox-table-entity.md` | 已由後續程式碼落地，狀態欄過期 |
| `planning/stories/1-4-outbox-poller-createorderlistener.md` | 已由後續程式碼落地，狀態欄過期 |
| `planning/stories/1-5-orders-table-restore.md` | 已由後續程式碼落地，狀態欄過期 |
| `planning/stories/1-6-async-backup-write.md` | 已由後續程式碼落地，狀態欄過期 |

### D. 未來發想，不是承諾

| 文件 | 判斷 |
|------|------|
| `brainstorming/brainstorming-session-2026-05-12-1400.md` | 保留為 idea bank；條件單、事件溯源強化、策略回測等不代表近期要做 |
| `planning/research/domain-pjm-market-mechanism-research-2026-04-07.md` | 保留為 domain research，不等於目前實作需求 |

## 目前不要再新增成近期待辦的項目

- 正式 load test
- 完整 observability
- E2E benchmark
- Kafka / RabbitMQ Super Stream 遷移

這些可以作為面試反思或 production 化前的工作，但目前不是 EAP 的核心整理目標。

## 使用建議

1. 新開 AI session 時，先讀 `../PROJECT_STATE.md`，再讀本文件。
2. 要準備面試時，直接讀 B 類文件與 `../docs/tsmc-interview-prep.md`。
3. 要改程式時，使用 C 類文件只能當背景，實際狀態以程式碼與 `eap-matchEngine/cr_outputs/features/*` 為準。
4. 不要根據 `Status: ready-for-dev` 直接開工，這些狀態多數已過期。
