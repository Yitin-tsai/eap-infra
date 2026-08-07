# Feature: Challenge 2000 TPS Global Load Test

## Goal

Challenge the EAP trading platform toward 2000 TPS with reproducible end-to-end load-test evidence.

## Working definition

Final TPS must be explicitly labeled as one of:

- submitted orders per second,
- matched trades per second,
- settled wallet transactions per second,
- or fully completed end-to-end trades per second after queue drain.

For resume/interview value, the strongest target is fully completed end-to-end trades per second with queue drain, p95/p99 latency, and error rate.

## Initial pipeline status

- Product Scope: performance ticket is worth building because it proves system design and scaling judgment.
- Architect Review: pending.
- Performance Review: pending.
- QA Review: pending.
- Implementation: blocked until current bottlenecks and measurement definition are clear.

## Draft Scrum Board

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-001 | Define 2000 TPS target and measurement method | Performance | Metric distinguishes submit/match/settle/E2E completion TPS | None |
| TPS-002 | Map current service ownership and event flow | Architect | Diagram or written flow identifies each service-owned durable fact and the external convergence gate | TPS-001 |
| TPS-003 | Inventory current load-test tooling and configs | Implementation Lead | Key scripts, compose files, profiles, and service configs listed | None |
| TPS-004 | Build cost model per trade | Performance | DB writes, MQ messages, outbox writes, and completion writes estimated | TPS-002 |
| TPS-005 | Identify first bottleneck with baseline run | Performance | Baseline report includes throughput, p95/p99, errors, queue depth, DB/pool stats | TPS-001, TPS-003 |
| TPS-006 | Split remediation work by bottleneck | Architect + Implementation | Each remediation task has scope, risk, and verification command | TPS-005 |
| TPS-007 | Add QA acceptance tests for load-test correctness | QA | Test plan covers duplicates, out-of-order events, retries, DLQ, queue drain | TPS-002 |
| TPS-008 | Run staged load tests: 500/1000/1500/2000 | Performance | Each stage records same metrics and pass/fail result | TPS-005 |
| TPS-009 | Production-style review of changes | Reviewer | Blockers/non-blockers documented before final claim | TPS-006 |
| TPS-010 | Convert result into resume/interview artifact | Product Scope | Resume bullets include metric, architecture tradeoff, and verification method | TPS-008 |

## Definition of Done

- 2000 TPS definition is explicit.
- Load test is reproducible from documented commands.
- Queue drain is verified, not only request publish rate.
- Error rate and p95/p99 latency are reported.
- DB pool, lock, index, and RabbitMQ backlog metrics are captured.
- Reviewer has no blockers.
