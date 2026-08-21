# Vegeta Unattended Full-Chain Validation - 2026-08-20

## Purpose and Boundary

This session tested whether the external Vegeta driver gives EAP a more
reliable full-chain workload source and whether the current worktree remains
correct and stable across repeated same-host runs. It did not test hardware
isolation or production capacity.

All runs used the canonical shuffled mixed HTTP lifecycle, jar-launched Order,
Wallet, and MatchEngine services, one Vegeta CPU, 16 initial workers, 2,048
maximum workers, and a co-located single laptop. A run passed only when offered
load, completion, and backlog gates passed together with exact three-service
trade IDs, asset reconciliation, empty order books and Match reservations, and
zero final queue/DLQ debt.

The session ran from `2026-08-19 16:58 +08:00` to `2026-08-20 04:05 +08:00`,
about 11 hours 7 minutes. Low-observation capacity runs and the final deep
diagnostic are separate evidence classes.

## Test Plan

1. Run five-minute low-observation stages at 700, 750, 800, and 850 orders/s.
2. Repeat the capped 800 orders/s candidate for 15 minutes with three seeds.
3. Run one uninterrupted hour at 500 orders/s for longer JVM and connection-pool
   behavior.
4. Run 16 independent 20-minute measurements at 700 orders/s with distinct
   seeds and ten-minute cooldowns. Each run resets data and restarts services.
5. Finish with a 15-minute 700 orders/s deep diagnostic using a 15-second
   diagnostic interval.

The controller would lower later rates after two consecutive rejects and stop
if free disk fell below 30 GiB. Neither condition triggered.

## Aggregate Result

| Signal | Result |
| --- | ---: |
| Runs | 25 |
| Capacity-valid runs | 24 |
| Correctness-valid runs | 25 |
| Scheduled orders | 19,941,000 |
| HTTP successes | 19,940,986 |
| Durable orders | 19,941,000 |
| Durable three-service trades | 9,970,500 |
| HTTP timeouts | 14, all in one 800 orders/s run |

All 25 runs reached exact MatchEngine, Order, and Wallet trade-ID equality,
correct assets, zero remaining orders or Match reservations, and zero final
queue/DLQ debt. This is a reliability result across the exercised clean-start
workloads. It does not mean the rejected 800 orders/s run passed its API or
capacity contract.

## Staircase and 800 Confirmation

All four five-minute stages passed:

| Orders/s | Same-window trades/s | Max backlog | Backlog slope/s | Full-lifecycle trades/s |
| ---: | ---: | ---: | ---: | ---: |
| 700 | 366.87 | 13,814 | -16.0397 | 344.83 |
| 750 | 375.11 | 359 | +0.0566 | 370.04 |
| 800 | 400.20 | 626 | +0.0602 | 394.44 |
| 850 | 424.93 | 543 | +0.0072 | 419.03 |

The 700 stage began its measurement window with warm-up debt and caught up, so
its elevated same-window rate is not a capacity improvement. The 850 stage is
a single short diagnostic and is not promoted.

At 800 orders/s, two 15-minute seeds passed at `399.39` and `399.61`
same-window trades/s. The third scheduled all `768,000` requests but 14 clients
timed out waiting for response headers after 10 seconds. Vegeta reported
`99.998177%` success, p50 `5.417 ms`, p95 `2.078 s`, p99 `4.169 s`, and a
`10.019 s` maximum. Durable resolution later proved that all `768,000` orders
and `384,000` trades completed correctly, but the run failed
`http_accepted_count_mismatch` and `http_other_failures`. Therefore 800 is not
a repeatable current capacity boundary.

## One-Hour Continuity

The uninterrupted 500 orders/s run scheduled and accepted all `1,830,000`
orders and converged `915,000` trades. It measured `499.99 accepted orders/s`,
`249.71 same-window trades/s`, a maximum backlog of `1,168`, a `+0.0175/s`
slope, and `247.35 full-lifecycle trades/s`. All correctness and drain gates
passed.

This is the longest continuous run in the session. The later 700 evidence is a
repeat matrix, not one continuous multi-hour soak.

## Repeated 700 Orders/s Result

All 16 independent 20-minute 700 orders/s runs passed. Together they scheduled
`14,112,000` orders and converged `7,056,000` exact three-service trades.

| Signal | Minimum | Mean | Maximum |
| --- | ---: | ---: | ---: |
| Accepted orders/s | 699.96 | 699.9969 | 700.00 |
| Same-window trades/s | 349.80 | 349.9719 | 350.09 |
| Maximum backlog | 486 | 778.69 | 1,967 |
| Backlog slope/s | +0.0190 | +0.0524 | +0.3453 |
| Full-lifecycle trades/s | 338.66 | 345.7056 | 346.65 |

Run 10 had the largest backlog and lowest full-lifecycle rate, but the effect
did not persist in later runs. This supports transient shared-host variation
rather than progressive service degradation. The 16/16 result substantially
strengthens 700 as a current-worktree repeatable lower-bound candidate. It does
not create a release-pinned claim until the worktree is reviewed and committed,
and it does not prove a continuous five-hour soak.

## Final Deep Diagnostic

The final 700 orders/s run used a 60-second warm-up, 900-second measurement,
and 15-second deep sampling interval. It accepted all `672,000` orders and
converged `336,000` trades:

- `700.00 accepted orders/s` and `350.05 same-window trades/s`;
- `347.03 full-lifecycle trades/s`;
- maximum backlog `767`, slope `+0.0123/s`, and zero final debt;
- actual Vegeta p50/p95/p99 `1.492 / 16.782 / 49.597 ms`, maximum `306.519 ms`;
- Match-to-durable-convergence p50/p95/p99 `94.304 / 191.101 / 290.961 ms`;
- RabbitMQ sampled queue peaks at or below `101`, with no memory or disk alarm;
- PostgreSQL rollbacks `0`, Redis evictions `0`, and Redis peak `13,225 ops/s`.

Vegeta consumed `35.44s user + 35.15s sys` over `960.09s`, approximately
`7.35%` of one CPU core on average. It is a low-cost and accurate generator.
It did not remove same-host contention: sampled system CPU averaged roughly
`65.3-77.1%` and reached `100%`; the Order consumer pool briefly had six
pending connections; Order PostgreSQL showed active waits up to `7.662s`, a
sampled `DataFileRead` wait up to `4.545s`, and autovacuum delay. Those signals
coexisted with a passing business flow and are diagnostic leads, not proof that
one component alone limits capacity.

## Decision

- **Adopt Vegeta as the preferred high-rate diagnostic driver.** It supplies
  the requested schedule with low generator cost and removes the legacy
  response-permit ambiguity.
- **Do not claim that Vegeta increases EAP service throughput.** At 648 the
  controlled deep A/B was throughput-equivalent, and all processes still share
  one laptop.
- **Retain 700 as a current-worktree candidate, not a new release-pinned public
  boundary yet.** Sixteen medium-window runs passed, but 800 failed 1 of 3
  longer confirmations and 850 has only a short result.
- **Keep the 800 failure.** Its 14 client timeouts with complete durable
  outcomes demonstrate why API success, durable business completion, and
  correctness must remain separate gates.
- **A remote generator remains necessary for hardware attribution.** Only a
  different CPU host can determine how much current tail variation belongs to
  the co-located driver, Docker, endpoint protection, and the EAP services.

## Artifacts

- [session summary](results/2026-08-20-vegeta-unattended/summary.csv)
- [aggregate result](results/2026-08-20-vegeta-unattended/aggregate.json)
- [all 25 final result JSON files](results/2026-08-20-vegeta-unattended/)
- [rejected 800 Vegeta report](results/2026-08-20-vegeta-unattended/rejected-800-seed-20260824-vegeta-report.json)
- [final deep result](results/2026-08-20-vegeta-unattended/http-matched-external-VEGETA_UNATTENDED_20260819_R1_FINAL_DEEP_700_SEED_20260899-result.json)
- [final deep diagnostics](results/2026-08-20-vegeta-unattended/final-deep-700-diagnostics.md)
- [final deep stage lag](results/2026-08-20-vegeta-unattended/final-deep-700-stage-lag.md)
- [final deep Vegeta report](results/2026-08-20-vegeta-unattended/final-deep-700-vegeta-report.json)
  and [process time](results/2026-08-20-vegeta-unattended/final-deep-700-vegeta-time.txt)

The finite target files and per-request Vegeta JSONL are retained locally but
not published because they total about 16 GiB. The manifest checksum and final
reports preserve the evidence needed for the claims above without adding raw
load-generator bulk to Git.
