# External Open-Loop HTTP Driver - 2026-08-19

## Problem

The existing Java steady-state drivers prepare valid mixed BUY/SELL requests,
send HTTP, and verify the full business lifecycle in one JVM. At high response
latency, their bounded workers and in-flight permits turn the requested
open-loop rate into a partially closed loop. On the same laptop, the generator
also competes with Order, Wallet, MatchEngine, PostgreSQL, RabbitMQ, Redis, and
monitoring for CPU.

Pre-serializing request bodies removed preparation cost but did not remove the
response-permit ceiling. The `1200` and `2000 orders/s` prepared-sync probes
therefore remained driver-limited overload diagnostics, not service-capacity
measurements.

## Implementation

`scripts/load-test/run-http-matched-external-open-loop.sh` keeps the established
business and correctness contract while moving timed HTTP generation to
Vegeta:

1. `httpMatchedExternalPrepare` registers/funds wallets, captures durable
   baselines, and writes the complete shuffled request schedule before timing.
2. The target file is finite and its SHA-256 is recorded in a secret-free
   manifest. The manifest contains run identity, workload boundaries, users,
   balance snapshots, and database baselines, but no JDBC or RabbitMQ password.
3. A direct low-frequency Java monitor records durable three-service completion
   and RabbitMQ backlog without retaining the HTTP worker pool.
4. Vegeta sends the finite targets at a fixed rate. The attack window includes
   one second of EOF grace so rate-limiter rounding cannot omit the last few
   targets. Vegeta's single `no targets to attack` EOF sentinel is removed from
   the result stream; every real target must still produce exactly one result.
   Results are encoded and filtered as the attack runs, so post-run conversion
   is not counted as service convergence tail.
5. A direct Java verifier merges HTTP completion timestamps with monitor
   samples, waits for full convergence, and applies the existing trade-ID,
   asset, order-book, reservation, queue, and DLQ gates.

Monitor and verifier JVMs use a precomputed runtime classpath instead of
starting another Gradle process inside or after the traffic window. This avoids
counting Gradle startup as service convergence tail. The monitor polls its stop
signal every 50 ms even when the business sample interval is longer, avoiding a
full sample interval of artificial drain time.

## Smoke Validation

The accepted harness smoke used `100 orders/s`, `2s` warm-up, `10s`
measurement, one Vegeta CPU, four initial workers, and 128 maximum workers.
This is deliberately below the known capacity boundary.

- Vegeta produced exactly `1200` results and reported `100%` HTTP success.
- Vegeta attack process time was `0.12s user` and `0.10s sys` over `12.03s`
  wall time.
- The steady window reached `99.98 accepted orders/s` and a `101.42%`
  completion-to-target ratio.
- MatchEngine, Order, and Wallet converged to the same `600` trade IDs.
- Asset reconciliation passed; order books, Match reservations, measured
  queues, and DLQ drained to zero.

This proves the harness and correctness handoff work. A short `100 orders/s`
smoke is not a current capacity result and does not change the documented 648
same-host sustained boundary.

Published smoke artifacts:

- [full lifecycle result](results/2026-08-19-external-open-loop-smoke-r1.json)
- [business samples](results/2026-08-19-external-open-loop-smoke-r1-samples.csv)
- [Vegeta report](results/2026-08-19-external-open-loop-smoke-r1-vegeta-report.json)
- [Vegeta attack process time](results/2026-08-19-external-open-loop-smoke-r1-vegeta-time.txt)

The public result explicitly sets `capacityClaimAllowed=false` and labels its
boundary as a 100 orders/s, 10-second harness smoke.

## 648 Driver-Equivalence A/B

The next experiment used the same `20260804` seed, `10s` warm-up, `30s`
measurement, one-second business samples, canonical service settings, and no
deep diagnostics. The order was external R1, legacy-sync, external R2.

| Signal | External R1 | Legacy-sync | External R2 |
| --- | ---: | ---: | ---: |
| HTTP accepted | 25,920 | 25,920 | 25,920 |
| Steady accepted orders/s | 648.00 | 648.09 | 647.97 |
| Steady completed trades/s | 323.79 | 323.75 | 323.28 |
| Completion target ratio | 99.94% | 99.92% | 99.78% |
| Maximum sampled backlog | 400 | 262 | 185 |
| Backlog slope/s | -2.5835 | -2.4278 | +0.5448 |
| HTTP p95 upper bound | 100 ms | 100 ms | 50 ms |
| HTTP p99 upper bound | 200 ms | 200 ms | 500 ms |
| Full-convergence trades/s | 304.34 | 308.70 | 305.57 |

Every run converged to the same `12,960` MatchEngine, Order, and Wallet trade
IDs, reconciled assets, emptied both order books and Match reservations, and
drained all measured queues and DLQ. No run had an HTTP failure or unscheduled
target.

At 648 orders/s, the external and legacy drivers are throughput-equivalent.
The external driver does not make EAP faster at this rate; it removes the known
bounded-permit ceiling before higher-rate diagnostics. Backlog and tail
differences changed direction across the external sandwich and are treated as
single-host run variance, not a driver improvement or regression.

Published A/B artifacts:

- [external R1 result](results/2026-08-19-driver-equivalence-external-648-r1.json)
  and [samples](results/2026-08-19-driver-equivalence-external-648-r1-samples.csv)
- [legacy-sync result](results/2026-08-19-driver-equivalence-legacy-648-r1.json)
  and [samples](results/2026-08-19-driver-equivalence-legacy-648-r1-samples.csv)
- [external R2 result](results/2026-08-19-driver-equivalence-external-648-r2.json)
  and [samples](results/2026-08-19-driver-equivalence-external-648-r2-samples.csv)

The external results also retain Vegeta reports and process-time files beside
their lifecycle artifacts. All three lifecycle results explicitly set
`capacityClaimAllowed=false`; this short one-seed A/B validates driver
equivalence, not a new sustained-capacity boundary.

## Deep Diagnostic Driver Check

A later `legacy -> external -> legacy` check repeated the `648 orders/s`,
`10s + 30s`, seed `20260804` contract with jar-launched services and identical
five-second deep diagnostics. The first external attempt was rejected for
full-lifecycle comparison because its runner stopped the diagnostic sampler
before starting the final verifier. Sampler shutdown can wait for the current
sampling cycle and incorrectly add that delay to external
`fullConvergenceSeconds`. The runner now performs final convergence and
correctness verification before stopping diagnostics. No workload or service
setting changed.

| Signal | Legacy R1 | Corrected external | Legacy R2 |
| --- | ---: | ---: | ---: |
| HTTP accepted | 25,920 | 25,920 | 25,920 |
| Steady accepted orders/s | 648.07 | 648.14 | 647.80 |
| Steady completed trades/s | 327.14 | 323.28 | 330.72 |
| Maximum sampled backlog | 234 | 229 | 302 |
| Backlog slope/s | -1.2977 | -2.8277 | -4.7683 |
| Full-lifecycle trades/s | 313.38 | 305.92 | 311.90 |

The legacy mean was `328.93 steady completed trades/s` and `312.64
full-lifecycle trades/s`. Corrected external was respectively `1.72%` and
`2.15%` lower. These short co-located differences are not a significant
service-throughput improvement or regression. All three valid runs converged
to the same `12,960` trade IDs in MatchEngine, Order, and Wallet; assets,
order books, reservations, queues, and DLQ passed their final gates.

Vegeta scheduled every request and consumed `1.79s user + 1.36s sys` over
`40.03s`, approximately `7.87%` of one CPU core on average. Deep diagnostics
showed no RabbitMQ resource alarm, PostgreSQL rollback, Redis eviction, or
final debt. Service and system CPU, pool activity, queue peaks, and stage lag
remained in the range bracketed by the two legacy controls. This confirms that
Vegeta is a low-cost and accurate load source, but it does not isolate EAP from
the laptop CPU, Docker, databases, endpoint protection, or IDE background
work. Its demonstrated benefit remains removal of the high-rate driver
scheduling ambiguity, not higher service capacity at `648 orders/s`.

Published deep artifacts:

- [legacy R1 result](results/2026-08-19-deep-driver-ab-legacy-r1.json),
  [diagnostics](results/2026-08-19-deep-driver-ab-legacy-r1-diagnostics.md),
  and [stage lag](results/2026-08-19-deep-driver-ab-legacy-r1-stage-lag.md)
- [corrected external result](results/2026-08-19-deep-driver-ab-vegeta-r1.json),
  [Vegeta report](results/2026-08-19-deep-driver-ab-vegeta-r1-report.json),
  [process time](results/2026-08-19-deep-driver-ab-vegeta-r1-time.txt),
  [diagnostics](results/2026-08-19-deep-driver-ab-vegeta-r1-diagnostics.md),
  and [stage lag](results/2026-08-19-deep-driver-ab-vegeta-r1-stage-lag.md)
- [legacy R2 result](results/2026-08-19-deep-driver-ab-legacy-r2.json),
  [diagnostics](results/2026-08-19-deep-driver-ab-legacy-r2-diagnostics.md),
  and [stage lag](results/2026-08-19-deep-driver-ab-legacy-r2-stage-lag.md)

## Corrected 1200 Orders/s Diagnostic

The first 1200 attempt exposed a harness boundary rather than an EAP failure:
with a duration set just below 40 seconds, Vegeta's rate-limiter rounding read
only `47,995` of `48,000` finite targets. That result was discarded. The
harness now adds one second of EOF grace, filters only Vegeta's synthetic EOF
sentinel, and still requires exactly one result per checksummed target.

The corrected rerun produced continuous sequence numbers `0..47999`, exactly
`48,000` results, `48,000` HTTP 200 responses, and a scheduled request rate of
`1200.012 orders/s`. It therefore removes the earlier Java driver's offered
load ambiguity.

| Signal | Corrected result |
| --- | ---: |
| Scheduled requests | 48,000 |
| Scheduled request rate | 1200.012 orders/s |
| HTTP success | 100% |
| Response throughput over response tail | 1170.10 responses/s |
| Steady accepted-response rate | 1145.12 orders/s |
| Steady completed trade rate | 172.06 trades/s |
| Completion target ratio | 28.68% |
| Maximum sampled backlog | 30,270 |
| Backlog slope | +700.9119 messages/s |
| HTTP p50 / p95 / p99 | 1.018s / 4.177s / 4.475s |
| Full-convergence throughput | 390.75 trades/s |

All `24,000` pairable trades eventually converged across MatchEngine, Order,
and Wallet with identical trade IDs, correct assets, empty order books and
reservations, and zero final queue/DLQ debt. The run nevertheless failed the
steady completion and growing-backlog gates. Its full-convergence throughput is
a burst-plus-drain average and is not sustained capacity.

This separates the two limitations cleanly. The external driver can schedule
1200 requests/s with low CPU overhead, while the same-host EAP chain cannot
consume that rate during the measurement window. `steadyAcceptedOrderTps` is a
response-completion-window metric inherited from the legacy contract; the
external scheduled rate is recorded separately and must be used when deciding
whether the driver supplied the requested workload.

Published diagnostic artifacts:

- [full lifecycle result](results/2026-08-19-external-open-loop-1200-overload-r1.json)
- [business samples](results/2026-08-19-external-open-loop-1200-overload-r1-samples.csv)
- [Vegeta report](results/2026-08-19-external-open-loop-1200-overload-r1-vegeta-report.json)
- [Vegeta attack process time](results/2026-08-19-external-open-loop-1200-overload-r1-vegeta-time.txt)

The result sets `capacityClaimAllowed=false`. It is a valid overload diagnostic
and correctness result, not evidence that EAP sustains 1200 orders/s.

## Boundary and Next Decision

`external` describes process/tool separation, not hardware isolation. With the
default `LOAD_GENERATOR_PLACEMENT=co-located`, Vegeta still consumes the same
laptop CPU and network stack as EAP. The result artifact records this placement
along with the Vegeta CPU and worker limits.

The 648 sandwich allows the external driver to be used for higher-rate
diagnostics, but does not yet replace legacy-sync as the historical capacity
contract. The corrected 1200 run proves the next same-host limitation is
growing service-chain debt rather than driver scheduling. The next capacity
search should bracket the knee between 648 and 1200 before spending resources
on another 2000 overload. A later run on a genuinely separate host must be
labeled `remote-host`; it is a different hardware boundary from all current
single-laptop evidence.

The subsequent [11-hour unattended validation](2026-08-20-vegeta-unattended-validation.md)
completed 25 full-chain runs. Sixteen independent 20-minute runs passed at 700
orders/s, while one of three 15-minute 800 orders/s confirmations was rejected
for 14 HTTP timeouts despite exact durable convergence. This strengthens the
current-worktree 700 candidate and confirms the driver's usefulness, but does
not promote 800, the short 850 stage, or a new release-pinned boundary.
