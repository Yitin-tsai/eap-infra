# Load-Test Entry Points

Start from this page instead of selecting a script by filename. Different TPS
units and workload boundaries are not interchangeable. Read the
[benchmark taxonomy](../../docs/benchmarks/load-test-taxonomy.md) before comparing
results.

## Primary Entry Points

| Question | Command | Evidence boundary |
| --- | --- | --- |
| What shuffled mixed HTTP load is sustainable? | `run-http-matched-steady-state.sh` | Canonical full-chain capacity contract |
| Can a lower-cost or remote open-loop driver reproduce it? | `run-http-matched-external-open-loop.sh` | Same business gates; driver-placement diagnostic until promoted |
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
   drain, offered load, completion rate, and bounded backlog;
5. repeat a different seed before promoting a sustained boundary.

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

Runners write raw logs, result JSON, samples, and diagnostics to
`build/load-test-reports/`. This is disposable local output and is ignored by Git.
It is useful for investigation and reruns, but a committed report must not depend on
that directory remaining on one machine.

After review, promote only the evidence needed for the decision into
`docs/benchmarks/results/YYYY-MM-DD-topic/`, write or update the dated campaign report
under `docs/benchmarks/`, and update `docs/performance-report.md` only when the
evidence class permits the claim. See the
[benchmark evidence guide](../../docs/benchmarks/README.md).

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
