# AI Engineering Workflow for EAP

This project uses a role-separated Codex workflow to turn AI assistance into an engineering review system rather than a single code-writing assistant.

## Skill command map

Use these commands in Codex when working on EAP:

```text
使用 eap-product-scope，challenge 這個 feature 是否值得做，並產出履歷價值。
使用 eap-architect-review，只審查 DDD boundary、service ownership、event flow、一致性，不寫 code。
使用 eap-performance-review，分析 TPS、DB pool、RabbitMQ、PostgreSQL、JVM/GC、load-test correctness。
使用 eap-implementation-lead，根據已通過 spec 實作，不重新設計架構。
使用 eap-qa-lead，設計 integration / Testcontainers / edge case / race condition / load-test acceptance criteria。
使用 eap-reviewer，假設 Google L5/L6 production reviewer，嚴格找 blockers。
使用 eap-feature-pipeline，跑完整 Product → Architect → Performance → Implementation → QA → Reviewer → Resume workflow。
```

## Default pipeline

```text
Ticket
  -> Product Scope
  -> Architect Review
  -> Performance Review
  -> Scrum Breakdown
  -> Implementation Lead
  -> QA Lead
  -> Reviewer
  -> Test Result / Resume Notes
```

## Role boundaries

| Role | Owns | Must not do |
| --- | --- | --- |
| Product Scope | MVP value, scope cuts, resume/interview story | Tune implementation |
| Architect | DDD, module boundary, ownership, event flow, consistency | Write code |
| Performance | TPS model, locks, indexes, pools, MQ, JVM, bottlenecks | Change business behavior casually |
| Implementation Lead | Spring Boot/Java/config/scripts/tests | Redefine architecture silently |
| QA Lead | Test matrix, failure injection, correctness gates | Accept happy-path-only proof |
| Reviewer | Production-style blockers and maintainability risks | Own feature implementation |

## Definition of Done for performance tickets

- TPS definition is explicit: submitted orders/s, matched trades/s, settlement/s, or fully completed E2E/s.
- Load generator measures the intended boundary.
- Queue depth, unacked messages, outbox pending/failed, DLQ count, and final DB correctness are captured.
- The system drains after the run.
- Bottleneck evidence is tied to metrics, not guesses.
- Result is documented with exact command, parameters, and environment.

## Agent safety

- Give each specialist one bounded question and only the context/files it needs.
- Architect, Performance, QA, and Reviewer roles do not edit files.
- Review roles do not spawn child agents; Implementation starts only after a decision is accepted.
- A stalled specialist gets one finalize request, then the lead continues locally and records the gap.
- AI output is input to a decision. The developer owns architecture, risk acceptance, verification, and published claims.

Recommended task shape:

```text
Role: Performance
Task: Determine whether Wallet settlement or Order matched append limits full-chain completion.
Allowed files: exact listener, SQL appender, load-test result JSON.
Forbidden: no file edits, no architecture redesign, no child agents.
Output: evidence, bottleneck conclusion, one next experiment, and stop condition.
```

## Resume positioning

Suggested phrasing:

```text
Established a role-based AI engineering workflow using reusable Codex skills, separating product scope, architecture review, performance budgeting, implementation, QA, and production-style review for an event-driven power trading platform.
```

```text
Applied the workflow to a 2000 TPS load-test initiative covering RabbitMQ backpressure, transactional outbox, idempotent consumers, PostgreSQL isolation, and end-to-end completion reconciliation.
```
