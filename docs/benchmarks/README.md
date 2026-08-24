# Benchmark Evidence Guide

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
