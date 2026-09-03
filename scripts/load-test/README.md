# Load-Test Entry Points

Start from this page instead of selecting a script by filename. Different TPS
units and workload boundaries are not interchangeable. Read the
[benchmark taxonomy](../../docs/benchmarks/load-test-taxonomy.md) before comparing
results.

## Primary Entry Points

| Question | Command | Evidence boundary |
| --- | --- | --- |
| What shuffled mixed HTTP load is sustainable? | `run-http-matched-steady-state.sh` | Canonical full-chain capacity contract |
| Can an external open-loop driver reproduce it? | `run-http-matched-external-open-loop.sh` | k6 by default; same business gates; driver-placement diagnostic until promoted |
| Where is the first unsustainable rate? | `run-http-matched-staircase.sh` | Full-chain knee search, not a soak guarantee |
| What is the sequential full-HTTP upper bound? | `run-http-matched-trade-completion-10k.sh` | SELL then BUY; not mixed-flow capacity |
| Does cancellation converge across all three services? | `run-http-cancellation-lifecycle.sh` | Open, partial-fill, and bounded match/cancel race correctness; not capacity evidence |
| Is the Order-to-orderbook front half the bottleneck? | `run-order-admission-chain-10k.sh` | No trade execution or settlement |
| Is the seeded Match-to-settlement back half the bottleneck? | `run-matched-trade-completion-10k.sh` | No Order HTTP or initial Wallet reservation |

The default capacity workflow is:

1. use the staircase to locate a provisional knee;
2. use the external driver for low-cost, same-seed A/B diagnostics;
3. verify a candidate with the canonical mixed steady-state contract;
4. require exact trade IDs, assets, order-book and reservation cleanup, queue/DLQ
   drain, Order read-model convergence, offered load, completion rate, bounded RabbitMQ
   backlog, and bounded Order reservation-result inbox backlog;
5. repeat a different seed before promoting a sustained boundary.

## Test Types

The common k6 names describe workload shape, not interchangeable evidence:

| Test type | EAP entry point | Decision it supports |
| --- | --- | --- |
| Smoke | short `run-http-matched-external-open-loop.sh` | harness and correctness wiring only |
| Load / soak | `run-http-matched-steady-state.sh` | sustained mixed-flow capacity candidate |
| Stress | `run-http-matched-staircase.sh` | first unsustainable rate and provisional knee |
| Focused diagnostic | scripts under Focused Probes below | one component or transport boundary |
| Spike | not implemented | do not relabel a staircase or short overload as spike evidence |

## k6 External Driver

The external open-loop runner uses k6 by default while retaining Vegeta for
historical A/B comparisons. Both drivers consume the same finite, checksummed
request schedule and hand their request-level results to the same Java monitor
and verifier. A k6 summary alone is not EAP correctness evidence.

Run a short local harness smoke:

```bash
docker compose -f docker-compose.loadtest.yml up -d --wait --wait-timeout 120

TARGET_ORDER_TPS=100 \
WARMUP_SECONDS=2 \
DURATION_SECONDS=10 \
K6_PRE_ALLOCATED_VUS=100 \
RUN_ID=K6_SMOKE_100_R1 \
bash scripts/load-test/run-http-matched-external-open-loop.sh

docker compose -f docker-compose.loadtest.yml down
```

The runner starts and stops the three application processes by default. The
dedicated PostgreSQL, RabbitMQ, and Redis containers must already be healthy;
the final `down` keeps their named volumes.

k6 uses the `constant-arrival-rate` executor. `K6_PRE_ALLOCATED_VUS` must be
large enough for the observed response latency; any `dropped_iterations` or
missing prepared request invalidates the run. Increase VUs only after checking
driver CPU and memory, because dynamic VU allocation can distort a benchmark.
`K6_MAX_P95_MS` optionally adds a driver-side p95 threshold; leave it unset when
the workload contract has not defined an HTTP latency SLO.

The 2026-08-25 co-located 648 long-window calibration established a practical
stop condition for this laptop. 648 VUs dropped `11563` of `622080` prepared
iterations; 2048 and 4096 VUs still dropped traffic, while 4096 also introduced
request timeouts and host-monitor stalls. Do not keep increasing VUs on this
16 GiB host. Use the existing remote Vegeta placement, or implement equivalent
remote k6 preflight and artifact transfer, before repeating that long-window
comparison. See the
[campaign report](../../docs/benchmarks/2026-08-25-k6-full-lifecycle-648.md).

The k6 code is split into configuration, prepared-workload, and reporting modules.
See [the k6 module guide](k6/README.md). The entry script contains only the request
execution flow.

For a same-workload Vegeta control, set `HTTP_LOAD_DRIVER=vegeta`. Remote-host
placement remains Vegeta-only until the remote helper has an equivalent k6
preflight and artifact-transfer contract.

## Evidence Mode and Provenance

Full HTTP lifecycle runners default to `BENCHMARK_EVIDENCE_MODE=diagnostic`.
Diagnostic runs may use a dirty worktree, but their result JSON always sets
`capacityClaimAllowed=false`.

Use `BENCHMARK_EVIDENCE_MODE=release-pinned` only for a capacity candidate. The
runner fails before setup if any recorded source repository is dirty or missing,
then verifies that the same commits remain checked out through the end of the run.
The result records full commit hashes for infra, common, Order, Wallet, and
MatchEngine; host and tool versions; execution placement; runner/config hashes;
and the actual infrastructure container image IDs. A successful business gate is
eligible for a public capacity claim only when this provenance gate also passes and
the run includes at least 60 seconds of warm-up plus 15 minutes of measurement.
Short release-pinned smoke tests validate the harness but remain ineligible for a
capacity claim.

## Artifact Lifecycle

Workload runners write raw logs, result JSON, generated Markdown, samples, and diagnostics to
`build/load-test-reports/`. This is disposable local output and is ignored by Git.
It is useful for investigation and reruns, but a committed report must not depend on
that directory remaining on one machine.

The external k6/Vegeta runner deletes request-level JSONL, generated targets,
samples, diagnostics, monitor logs, and other temporary runtime files after the
final EAP result has been persisted. The JSONL files can be many times larger than
the order count because the driver emits multiple metric records per request. The
runner retains the compact result, readable reports, driver summary, manifest, and
provenance. Set
`KEEP_RAW_LOADTEST_ARTIFACTS=true` only for a run that needs request-level diagnosis.
If a run fails before it can persist a result, the raw files are preserved.

Use the retention tool to remove interrupted-run leftovers and older diagnostics.
It is a dry run unless `DRY_RUN=false` is supplied:

```bash
PRUNE_ALL_RAW=true bash scripts/load-test/prune-loadtest-reports.sh
PRUNE_ALL_RAW=true DRY_RUN=false bash scripts/load-test/prune-loadtest-reports.sh
```

After review, promote only the evidence needed for the decision into
`docs/benchmarks/results/YYYY-MM-DD-topic/`, write or update the dated campaign report
under `docs/benchmarks/`, and update `docs/performance-report.md` only when the
evidence class permits the claim. See the
[benchmark evidence guide](../../docs/benchmarks/README.md).

For k6-backed runs, read artifacts in this order:

1. `*-report.md`: final EAP decision, throughput, durable correctness, and claim limits;
2. `*-result.json`: machine-readable source for the final decision;
3. `*-k6-report.md`: HTTP driver-only checks, offered load, and latency;
4. `*-k6-summary.json`: aggregated driver data; `*-k6.jsonl` exists only when raw retention is enabled;
5. `*-manifest.json`: workload identity; samples and diagnostics exist only when raw retention is enabled.

For current external full-chain results, the latency/backlog section must contain both
`steadyBacklog*` (RabbitMQ ready＋unacked) and
`steadyOrderReservationInboxBacklog*` (Order service-owned non-`APPLIED` work).
RabbitMQ at zero with a growing inbox is a failed whole-system sustained result even
when all accepted orders eventually converge after traffic stops.

Primary workloads, focused probes, and experiment summaries automatically call
`render-loadtest-report.sh`. To render an older JSON result without rerunning load:

```bash
bash scripts/load-test/render-loadtest-report.sh \
  build/load-test-reports/<run>-result.json
```

Generated Markdown improves local review but does not promote an artifact or make it
capacity evidence.

## Focused Probes

Use a focused probe only after a specific bottleneck hypothesis exists.

| Boundary | Command |
| --- | --- |
| Match reservation cleanup | `run-reservation-cleanup-ab.sh` |
| Match processor without RabbitMQ | `run-match-processor-probe.sh` |
| RabbitMQ into Match | `run-rabbit-match-intake-probe.sh` |
| Trade fanout into Order and Wallet | `run-trade-consumer-fanout-probe.sh` |
| Match outbox relay into downstream services | `run-match-relay-downstream-probe.sh` |
| RabbitMQ publisher confirms only | `run-rabbitmq-publish-only-10k.sh` |

An isolated probe may reject a candidate cheaply. It cannot establish complete
business TPS or adopt a service setting by itself.

## Experiment Orchestrators

- `run-order-admission-repeat.sh` and
  `run-matched-trade-completion-repeat.sh` repeat existing contracts and aggregate
  results. They do not define new workloads.
- `run-front-half-pool-budget-matrix.sh` is a plan-first Order connection-budget
  experiment. A surviving candidate still requires a mixed full-chain A/B.
- `run-prepared-http-driver-calibration.sh` tests the driver against a no-op endpoint;
  it does not test EAP capacity.

## Internal and Support Scripts

Do not start routine benchmarks from `run-global-matched-e2e.sh` or
`run-global-matched-e2e-two-phase.sh`. They are internal seed/project/run machinery
used by the seeded completion and isolated downstream probes.

Files such as `http-matched-loadtest-lib.sh`, `remote-vegeta-driver.sh`, environment
assertions, service lifecycle scripts, diagnostics collectors, summarizers, queue
purge, snapshot, and report pruning are support code rather than benchmark methods.
