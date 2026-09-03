# Benchmark Evidence Guide

Current worktree entry: [2026-09-03 latest reliability-version full-chain campaign](2026-09-03-current-version-full-chain.md). It separates eventual correctness from sustainable service-owned inbox drain and supersedes the 2026-09-01／02 checkpoints as current status.

This directory separates benchmark definitions, human decisions, and machine-readable
evidence. A high TPS number is not published merely because a runner emitted JSON.

## Layout

```text
benchmarks/
  README.md                    this evidence guide
  load-test-taxonomy.md        stable workload contracts and TPS meanings
  YYYY-MM-DD-topic.md          campaign report, decision, and limitations
  results/
    README.md                  artifact-bundle rules
    YYYY-MM-DD-topic/          new campaign evidence bundle
    <historical flat files>    retained for link stability
```

The dated report is the entry point for a human reader. Its result bundle supports
the report; it does not replace the explanation of workload boundaries, failures, or
the adoption decision. `performance-report.md` is the only canonical summary of
current capacity claims.

Local workload runners also generate `*-report.md` next to their source JSON. This
report is a disposable reading aid with a normalized decision, workload boundary,
throughput, latency/backlog, correctness gates, and evidence-invalid reasons. It does
not replace the JSON and is not promoted automatically.

k6-backed HTTP runs additionally generate a driver-only `*-k6-report.md` and raw
`*-k6-summary.json`. These prove offered-load execution, checks, thresholds, drops,
and HTTP latency only. Use the final EAP report for durable cross-service correctness
and capacity eligibility.

## Promotion Checklist

Promote a local run from `build/load-test-reports/` only when all applicable items are
recorded:

1. run ID, benchmark contract, workload seed, arrival pattern, warm-up, and measurement window;
2. exact source commits, dirty state, runner/config fingerprints, and evidence mode;
3. offered and accepted orders/s, completed and full-convergence trades/s, errors, and latency;
4. exact three-service trade IDs, assets, order-book/reservation state, queue/unacked/DLQ, outbox, and inbox gates;
5. backlog maximum and slope plus the metrics needed for the stated bottleneck conclusion;
6. pass, reject, or inconclusive decision and explicit claim limitations.

A diagnostic dirty-worktree run may be promoted as regression or investigation
evidence, but it cannot become release-pinned capacity evidence. Failed and rejected
runs are promoted only when they explain a decision or prevent a known bad experiment
from being repeated.

Do not publish secrets, credentials, full service logs without a stated need, or bulk
diagnostics unrelated to a claim.
