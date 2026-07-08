# EAP AI Agent Skills

This repository uses role-separated Codex skills to make AI-assisted development look like an engineering workflow, not a single code-generation prompt.

## Command style

Use these prompts directly:

```text
使用 eap-agent-workflow，幫我把 <ticket> 拆成 Architect / Performance / Implementation / QA / Reviewer 工作流。不要 fork 全上下文。
```

```text
使用 eap-architect-review，審查 <feature>。不要寫 code。
```

```text
使用 eap-performance-review，分析 <feature> 的 TPS、DB pool、MQ backlog、JVM/GC 風險。
```

```text
使用 eap-implementation-lead，根據已通過 spec 實作，不重新設計架構。
```

```text
使用 eap-qa-lead，設計 integration / duplicate / out-of-order / queue-drain 驗證。
```

```text
使用 eap-reviewer，假設 production PR review，找 race condition、transaction bug、效能問題與測試缺口。
```

```text
使用 eap-feature-pipeline，把 <feature> 拆成 Scrum tasks，並用多角色 review。
```

## Roles

- `eap-agent-workflow`: orchestrates safe multi-agent workflow and prevents subagent hangs.
- `eap-product-scope`: decide whether the feature is worth building and how it supports MVP/resume value.
- `eap-architect-review`: DDD boundaries, event flow, consistency, service ownership.
- `eap-performance-review`: TPS model, bottleneck prediction, pool/concurrency/index tuning.
- `eap-implementation-lead`: scoped implementation after spec approval.
- `eap-qa-lead`: integration, edge cases, failure injection, acceptance criteria.
- `eap-reviewer`: production-style review.
- `eap-feature-pipeline`: orchestrates the roles and produces Scrum artifacts.

## Resume positioning

This demonstrates a reusable AI-assisted spec review pipeline with separated architecture, performance, implementation, QA, and review responsibilities.

## Subagent safety rules

Use these rules when asking Codex to spawn agents:

- Do not use full conversation context for specialist agents.
- Give each subagent one exact question.
- For Architect / Performance / QA / Reviewer agents, forbid file edits.
- For all review agents, forbid spawning child agents.
- If a subagent does not answer after one wait cycle, send one finalize message. If it still does not answer, continue locally and record it as failed.
- Implementation starts only after the decision is explicit.

Recommended subagent task shape:

```text
Role: Architect
Forbidden: do not spawn subagents; do not modify files; do not inspect unrelated files.
Task: Decide whether MatchEngine completion should move from mutable view updates to append-only markers.
Context: latest 10k E2E business TPS is 361.79; trade_completion_view does 10000 inserts + 20000 updates.
Allowed files: eap-matchEngine/src/main/java/com/eap/eap_matchengine/application/TradeCompletionService.java
Output: max 10 bullets with recommendation, risks, next task.
Deadline: return best effort with assumptions.
```
