# k6 External Open-Loop Driver Smoke - 2026-08-25

## Decision

k6 is accepted as the default local driver for the existing
`external-http-matched-steady-state-chain` diagnostic. Vegeta remains available
for historical A/B controls and is still required for the implemented
`remote-host` path. This decision changes load-generation tooling, not EAP
business behavior or the current capacity claim.

## Design

The runner retains the established measurement contract:

1. Java prepares a deterministic shuffled BUY/SELL workload and writes a
   checksummed, secret-free manifest and finite target set.
2. k6 uses the open-model `constant-arrival-rate` executor and a fixed
   pre-allocated VU budget.
3. A separate Java monitor samples durable three-service progress and RabbitMQ
   backlog without participating in HTTP generation.
4. The Java verifier reads request-level k6 JSON metrics, reconstructs request
   start and completion times, waits for convergence, and applies the existing
   trade-ID, asset, order-book, reservation, queue, and DLQ gates.

The driver must produce one result for every prepared target. Missing requests,
HTTP failures, or k6 `dropped_iterations` invalidate the run. k6 summary metrics
are recorded in the final artifact but never replace business correctness
verification.

The k6 code now has three reusable modules: environment/scenario configuration,
finite prepared-workload materialization, and driver summary rendering. The runner
uses `handleSummary()` to produce machine-readable JSON plus a concise Markdown
driver report instead of relying on the legacy summary-export flag. A separate
generic renderer turns the final EAP JSON into a human report, so driver health and
business correctness remain visibly separate.

## Latest Modular Smoke

Run ID: `K6_MODULAR_SMOKE_100_20260825_R5`

| Setting | Value |
| --- | ---: |
| Evidence mode | diagnostic |
| Workload seed | `20260804` |
| Target | `100 total orders/s` |
| Warm-up / measurement | `2s / 10s` |
| Pre-allocated VUs | `100` |
| Prepared / sent / accepted | `1200 / 1200 / 1200` |
| Dropped iterations | `0` |
| HTTP success | `100%` |
| Out-of-range iterations | `0` |
| k6 p50 / p90 / p95 / p99 | `2.2935 / 4.915 / 6.8903 / 22.6990 ms` |
| Steady accepted | `99.96 orders/s` |
| Steady completed | `49.81 trades/s` |
| Completion target ratio | `99.62%` |
| Full convergence | `600 trades in 14.328s` |
| k6 process time | `0.50s user / 0.23s sys / 12.37s wall` |

MatchEngine, Order, and Wallet each persisted the same `600` trade IDs. Asset
reconciliation passed; remaining BUY/SELL orders, Match reservations, final
queue backlog, and DLQ were all zero. The maximum sampled steady backlog was
`16`. Its short-window regression slope was `+1.0193 messages/s`, while backlog
started and ended at zero and the run fully drained; this smoke is not sustained
backlog evidence.

The compact promoted evidence is in
[the result summary](results/2026-08-25-k6-open-loop-driver/summary.json).

## Harness Corrections Found by the Smoke

The first implementation attempt exposed two driver-adapter issues rather than a service
failure. A whole-second k6 duration admitted one boundary iteration beyond the
finite target set, and k6 2.2 summary fields differed from the older nested
shape expected by the enrichment step. The accepted runner shortens only the
scheduling boundary by one millisecond, still verifies the exact prepared
request count, and reads both summary shapes. R2 completed with driver exit
status zero and exact metrics. R3 repeated the same contract after the k6 module
and report refactor. R4 added an explicit zero out-of-range-iteration threshold.
R5 verified the final EAP result enrichment and readable report; all five driver
thresholds and all business gates passed.

## Claim Limit

This was a short dirty-worktree integration smoke. It is not eligible for a
capacity claim and does not replace the release-pinned `648 orders/s` boundary.
Before comparing k6 with Vegeta, run a controlled same-commit, same-seed,
same-window A/B and compare offered load, dropped requests, process cost,
latency, steady business completion, backlog, full convergence, and all final
correctness gates.

The later 648 long-window attempt is recorded separately in the
[full k6 lifecycle report](2026-08-25-k6-full-lifecycle-648.md). It preserved
cross-service correctness for delivered traffic but rejected the co-located
k6 driver gate after 648, 2048, and 4096 VU trials exposed drops and host
interference. That result keeps this smoke decision valid while rejecting a
same-host long-window capacity promotion.

## Artifact Reading Order

1. Read the final `*-report.md` for the EAP decision and evidence limitations.
2. Use `*-result.json` to audit the exact machine-readable business gates.
3. Read `*-k6-report.md` for offered load, dropped iterations, checks, and latency.
4. Open raw k6 JSONL, samples, manifest, or diagnostics only when investigating a
   rejected run or a bottleneck hypothesis.
