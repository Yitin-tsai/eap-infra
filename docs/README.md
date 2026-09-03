# EAP Documentation Map

This directory contains the version-controlled project record. Local AI-tool output,
generated build files, and raw benchmark runs are not authoritative documentation.

## Current Sources of Truth

| Area | Location | Purpose |
| --- | --- | --- |
| Latest-version entry | [`current-version-guide.zh-TW.md`](current-version-guide.zh-TW.md) | 2026-09-03 reliability redesign, current evidence, limitations, and reading paths |
| System design | [`architecture.md`](architecture.md) / [`architecture.zh-TW.md`](architecture.zh-TW.md) | Current service ownership, event flows, and transaction boundaries |
| CDA lifecycle deep dive | [`order-event-lifecycle.zh-TW.md`](order-event-lifecycle.zh-TW.md) | End-to-end order, trade, cancellation, retry, outbox, inbox, and Saga failure paths |
| Event consistency FAQ | [`event-consistency-five-questions.zh-TW.md`](event-consistency-five-questions.zh-TW.md) | Distributed transactions, outbox limits, idempotency, business completion, and Saga compensation |
| Order reservation-result reliability | [`order-asset-reservation-result-reliability.zh-TW.md`](order-asset-reservation-result-reliability.zh-TW.md) | Detailed durable inbox schema, transaction, lease, retry, crash windows, costs, and limitations |
| Wallet inbox and cancellation completion | [`wallet-inbox-and-cancellation-completion.zh-TW.md`](wallet-inbox-and-cancellation-completion.zh-TW.md) | Implemented Wallet durable intake/retry and the `CANCELLING → CANCELLED` release-confirmation protocol |
| Match order-admission inbox | [`match-order-admission-inbox.zh-TW.md`](match-order-admission-inbox.zh-TW.md) | Asset-reservation event contract, durable Match intake, lease retry, crash windows, operations, and limits |
| Active Order reliability ticket | [`features/order-asset-reservation-result-reliability.zh-TW.md`](features/order-asset-reservation-result-reliability.zh-TW.md) | Implemented Order reservation-result inbox and remaining intake-outage, Saga timeout, and recovery work |
| Active Wallet reliability ticket | [`features/wallet-reservation-reliability-and-saga-recovery.zh-TW.md`](features/wallet-reservation-reliability-and-saga-recovery.zh-TW.md) | Wallet durable inbox, retry classification, Saga timeout, DLQ recovery, and failure-injection backlog |
| Engineering workflow | [`ai-engineering-workflow.md`](ai-engineering-workflow.md) | Current role boundaries, evidence gates, and human decisions |
| Performance claims | [`performance-report.md`](performance-report.md) | Canonical current capacity claims and limitations |
| Latest full-chain campaign | [`benchmarks/2026-09-03-current-version-full-chain.md`](benchmarks/2026-09-03-current-version-full-chain.md) | k6 400／300 rejection, strict 200 diagnostic pass, and durable-inbox backlog discovery |
| API contracts | [`api/`](api/) | Reviewed OpenAPI snapshots for public service contracts |
| Benchmark methods | [`benchmarks/load-test-taxonomy.md`](benchmarks/load-test-taxonomy.md) | Workload definitions and claim boundaries |
| Benchmark campaigns | [`benchmarks/`](benchmarks/) | Human-readable dated experiment reports |
| Published evidence | [`benchmarks/results/`](benchmarks/results/) | Minimal reviewed artifacts that support committed reports |
| Interview entry | [`interview-guide.zh-TW.md`](interview-guide.zh-TW.md) | Five-minute project, architecture, consistency, performance, and trade-off briefing |
| Conference material | [`talks/`](talks/) | Audience-specific presentations derived from project evidence |
| Frozen history | [`archive/`](archive/) | Superseded plans and append-only historical records |

`features/` is reserved for active feature specifications that have not yet been
absorbed into architecture, workflow, or benchmark reports. A completed or superseded
plan moves to `archive/`; it must not remain beside current sources of truth.

## Artifact Lifecycle

```text
runner / tests
    -> build/load-test-reports/       local raw output, ignored by Git
    -> docs/benchmarks/results/       reviewed portable evidence, version controlled
    -> docs/benchmarks/<date>-*.md    campaign decision and limitations
    -> docs/performance-report.md     current canonical claim, when eligible
```

- `build/` follows the normal Gradle convention: it is reproducible, disposable, and
  may contain logs, samples, diagnostics, binaries, and failed attempts. It is not a
  BMAD directory and must never be the only location supporting a committed claim.
- `_bmad/`, `_bmad-output/`, `.blackboard/`, and `.claude/` are ignored local or
  legacy workflow-tool state. They are not part of the public documentation model.
- Promotion is deliberate. Copy only the result, samples, diagnostics, and provenance
  needed to audit a report; do not commit an entire raw run directory by default.
- New promoted campaigns use `benchmarks/results/YYYY-MM-DD-topic/`. Historical flat
  files remain in place so existing reports and commit history keep working.
- Durable documents should use repository-relative links. Machine-specific absolute
  paths may remain inside preserved raw artifacts, but must not be required to read a
  report.

See the [benchmark evidence guide](benchmarks/README.md) for the promotion checklist.

For this reliability revision, start with the
[latest-version guide](current-version-guide.zh-TW.md). For an upcoming conversation,
continue with the [Traditional Chinese interview guide](interview-guide.zh-TW.md) or
the [Hello World Dev brief](talks/hello-world-dev-conference-2026-brief.zh-TW.md).
