# EAP Documentation Map

This directory contains the version-controlled project record. Local AI-tool output,
generated build files, and raw benchmark runs are not authoritative documentation.

## Current Sources of Truth

| Area | Location | Purpose |
| --- | --- | --- |
| System design | [`architecture.md`](architecture.md) | Current service ownership, event flows, and transaction boundaries |
| Engineering workflow | [`ai-engineering-workflow.md`](ai-engineering-workflow.md) | Current role boundaries, evidence gates, and human decisions |
| Performance claims | [`performance-report.md`](performance-report.md) | Canonical current capacity claims and limitations |
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

For an upcoming conversation rather than a deep document review, start with the
[Traditional Chinese interview guide](interview-guide.zh-TW.md) or the
[Hello World Dev brief](talks/hello-world-dev-conference-2026-brief.zh-TW.md).
