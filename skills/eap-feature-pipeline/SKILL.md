---
name: eap-feature-pipeline
description: Run a role-separated EAP feature workflow similar to BMAD: Product Scope, Architect Review, Performance Review, Implementation Lead, QA Lead, Reviewer, and resume documentation. Use when the user asks to run an EAP ticket through a multi-agent/spec-review pipeline, create scrum tasks, coordinate subagents, or turn a feature into evidence for resume/interview value.
---

# EAP Feature Pipeline

Run EAP features through a repeatable role-separated workflow.

## Default pipeline

1. Product Scope: decide whether to build and how small the MVP should be.
2. Architect Review: challenge boundaries, ownership, event flow, and consistency.
3. Performance Review: define TPS target, cost model, bottlenecks, metrics.
4. Implementation Lead: implement only the accepted scope.
5. QA Lead: define and run reliability/load-test acceptance checks.
6. Reviewer: production-style review and request changes.
7. Documentation: capture decisions, results, and resume/interview bullets.

## Routing rules

- For pure performance tickets, Product Scope may be lightweight but still capture career value.
- For MQ, DB, transactions, or outbox changes, include Architect, Performance, QA, and Reviewer.
- For new product features, run Product Scope before architecture.
- Do not code until architecture/performance blockers are resolved unless the user explicitly asks for a spike.
- When subagents are available and the user asks for parallel work, assign independent read-only reviews first.

## Scrum output

Break the ticket into:

- Epic goal and success metric.
- Sprint 0 discovery tasks.
- Implementation tasks.
- QA/performance validation tasks.
- Documentation/resume tasks.
- Definition of Done.

## Output format

```md
## Feature Pipeline

### Epic
- ...

### Role Reviews
- Product:
- Architect:
- Performance:
- QA:
- Reviewer:

### Scrum Board
| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |

### Definition of Done
- ...

### Resume Evidence
- ...
```
