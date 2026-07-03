# EAP AI Agent Skills

This repository uses role-separated Codex skills to make AI-assisted development look like an engineering workflow, not a single code-generation prompt.

## Command style

Use these prompts directly:

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

- `eap-product-scope`: decide whether the feature is worth building and how it supports MVP/resume value.
- `eap-architect-review`: DDD boundaries, event flow, consistency, service ownership.
- `eap-performance-review`: TPS model, bottleneck prediction, pool/concurrency/index tuning.
- `eap-implementation-lead`: scoped implementation after spec approval.
- `eap-qa-lead`: integration, edge cases, failure injection, acceptance criteria.
- `eap-reviewer`: production-style review.
- `eap-feature-pipeline`: orchestrates the roles and produces Scrum artifacts.

## Resume positioning

This demonstrates a reusable AI-assisted spec review pipeline with separated architecture, performance, implementation, QA, and review responsibilities.
