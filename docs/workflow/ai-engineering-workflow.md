# AI Engineering Workflow for EAP

EAP uses a role-based AI engineering workflow to separate architecture review, performance analysis, implementation, QA, and production-style review.

## Roles

- `eap-product-scope`: validates MVP and interview value.
- `eap-architect-review`: validates boundaries, ownership, event flow, and consistency.
- `eap-performance-review`: validates TPS target, bottlenecks, and load-test design.
- `eap-implementation-lead`: implements approved specs without redesigning them.
- `eap-qa-lead`: designs correctness, integration, and failure tests.
- `eap-reviewer`: performs production-style review.
- `eap-feature-pipeline`: coordinates the whole workflow.

## Default Pipeline

```text
Product Scope
  -> Architect Review
  -> Performance Review
  -> Implementation
  -> QA
  -> Reviewer
  -> Documentation / Resume Notes
```

## Resume Framing

This workflow demonstrates Tech Lead-style engineering behavior: separating decision-making, implementation, performance validation, and production review instead of using AI only as a code generator.
