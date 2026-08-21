# Release-Pinned 700 Provenance Validation - 2026-08-21

## Purpose

This run tested two independent claims:

1. a full HTTP lifecycle artifact can prove exactly which clean source revisions,
   runner/configuration fingerprints, host boundary, tools, and container images
   produced it;
2. the reviewed and committed revision can sustain `700 total orders/s` under the
   same 20-minute shuffled mixed-HTTP contract as the earlier unattended matrix.

The provenance implementation was committed before traffic. The capacity run used
infra `d1ca766`, Order `c90de19`, Wallet `e538362`, MatchEngine `113d7a4`, and
Common `628893a`. All five repositories were clean before and after the run. The
host was one Apple Silicon laptop with 10 logical CPUs and 16 GiB memory; EAP,
three PostgreSQL containers, RabbitMQ, Redis, and Vegeta remained co-located.

## Provenance Gate

Full HTTP runners now default to `BENCHMARK_EVIDENCE_MODE=diagnostic`, which always
sets `capacityClaimAllowed=false`. `release-pinned` mode requires:

- clean infra, Common, Order, Wallet, and MatchEngine repositories before setup;
- identical repository revisions and source fingerprints after final verification;
- a supported steady-state contract and successful process exit;
- at least 60 seconds of warm-up and 900 seconds of measurement;
- all business capacity gates and no RabbitMQ resource alarm.

The result embeds repository commits, host/tool versions, execution placement,
PostgreSQL durability settings, SHA-256 hashes for the runner, shared library and
Compose file, and resolved infrastructure image IDs. Credentials are excluded.

## 700 Orders/s Result

The run used seed `20260842`, 60 seconds of warm-up, 1,200 seconds of measurement,
one-second business samples, jar-launched services, no deep sampler, and one Vegeta
CPU. Vegeta supplied the requested schedule accurately:

| Signal | Result |
| --- | ---: |
| Scheduled and HTTP-successful orders | `882000 / 882000` |
| Scheduled request rate | `700.001 orders/s` |
| HTTP response throughput | `699.993 responses/s` |
| HTTP p50 / p95 / p99 / max | `157.61 / 2924.90 / 3998.02 / 6151.91 ms` |
| Same-window completed trades | `287783` |
| Same-window completed trades/s | `240.01` |
| Completion target ratio | `68.57%` |
| Maximum sampled RabbitMQ backlog | `2041` |
| RabbitMQ backlog slope | `-0.2027/s` |
| Full convergence time | `2104.941s` |
| Full-lifecycle trades/s | `209.51` |

The low RabbitMQ backlog did not mean the business pipeline was caught up. During
traffic, durable Wallet reservation and later Match cleanup work lagged before
reaching RabbitMQ-ready state. After input stopped, the system required about
`844.93s` of additional drain time.

Final correctness passed completely: Order accepted and durably recorded all
`882000` submissions and confirmations; MatchEngine, Order, and Wallet contained
the same `441000` trade IDs; balances reconciled; all locks, order-book entries,
Match reservations, queues, unacknowledged deliveries, and DLQ debt were zero.

The run was nevertheless rejected by `steady_completion_rate_below_minimum`.
`capacityClaimAllowed=false`, so it is high-volume correctness and overload
evidence, not a 700 orders/s capacity result. The release-pinned same-host lower
bound remains the two-seed 648 orders/s class.

## Collector Correction and Smoke

The first provenance implementation resolved its runner path from `$0`. The runner
changes directory to `eap-order` before final verification, so the 700 result's
final `runnerSha256` was empty. Repository revisions, clean state and container
images were still captured, and the business gate had already rejected the run;
therefore this defect cannot turn it into capacity evidence.

Commit `085a326` resolves relative runner paths against the workspace root and also
requires source fingerprints to be complete and unchanged. A release-pinned
`100 orders/s`, 2-second warm-up, 10-second measurement smoke then passed all
business correctness gates with exact 600-trade convergence. Its repositories and
fingerprints were clean, complete, and stable, but
`capacityClaimAllowed=false` with `insufficient_warmup_window` and
`insufficient_measurement_window`. This verifies that a harness smoke cannot be
misrepresented as sustained capacity evidence.

## Decision

- Adopt the provenance and evidence-mode gate.
- Retain the failed 700 run; rejected committed evidence is part of the record.
- Do not repeat 700 immediately. First extend the monitor from one aggregate
  RabbitMQ backlog to per-stage durable debt so reservation, confirmation, Match
  intake, trade relay, downstream application, and cleanup slopes are visible.
- Keep 648 as the public release-pinned lower-bound class.
- Keep the 16/16 prior 700 matrix classified as current-worktree evidence for that
  session, not as the current committed capacity boundary.

Artifacts:

- [700 full lifecycle result](results/2026-08-21-release-pinned-provenance/release-pinned-700-seed-20260842-r1-result.json)
- [700 business samples](results/2026-08-21-release-pinned-provenance/release-pinned-700-seed-20260842-r1-samples.csv)
- [700 Vegeta report](results/2026-08-21-release-pinned-provenance/release-pinned-700-seed-20260842-r1-vegeta-report.json)
- [700 Vegeta process time](results/2026-08-21-release-pinned-provenance/release-pinned-700-seed-20260842-r1-vegeta-time.txt)
- [corrected provenance smoke](results/2026-08-21-release-pinned-provenance/provenance-smoke-seed-20260843-r1-result.json)
