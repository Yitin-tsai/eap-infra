# Low-Observability and High-Rate Probes

## Purpose

These experiments followed the release-pinned `648 orders/s` sustained campaign.
They asked two separate questions:

1. does disabling the external diagnostics sampler improve the same 648 workload;
2. what happens when the same-host full HTTP chain is offered short bursts at
   `1200` and `2000 orders/s`?

The runs used the same service commits as the accepted 648 campaign: infra
`97ce0b9`, Common `628893a`, Order `fc74688`, Wallet `e538362`, and MatchEngine
`6924a65`. No service code or runtime pool/concurrency setting changed.

None of the three runs is accepted as new sustained-capacity evidence. The two
high-rate runs are overload probes, and the low-observability repeat failed its
steady completion gate.

## 648 Same-Seed Low-Observability Repeat

The repeat used seed `20260821`, a `60s` warm-up, a `900s` measurement window,
release jars, and `DIAGNOSTICS_LEVEL=none`. This disabled the shell diagnostics
sampler but retained the benchmark generator's one-second durable-count and
RabbitMQ sampling.

| Signal | Accepted light run | `none` repeat |
| --- | ---: | ---: |
| steady accepted orders/s | `648.00` | `646.09` |
| steady completed trades/s | `314.84` | `287.96` |
| completion target ratio | `97.17%` | `88.88%` |
| backlog start / end / maximum | `9 / 1136 / 4907` | `109 / 138 / 3148` |
| backlog slope | `+1.1820/s` | `+0.8449/s` |
| full-lifecycle trades/s | `301.14` | `271.39` |
| exact final three-service trades | `311040` | `311040` |
| sustained gate | `PASS` | `FAIL` |

The repeat does not show that external monitoring caused the 648 pressure. Its
first `60-540s` interval completed `321.77 trades/s`, essentially identical to
the accepted run's `321.57 trades/s`. The difference appeared later: from
`540-960s`, the repeat fell to `249.98 trades/s`, while the accepted run retained
`307.71 trades/s`.

The run collected no CPU, pool, WAL, or PostgreSQL wait samples, so the late
degradation cannot be attributed to one resource. It is classified as
inconclusive for observer-effect attribution and rejected as capacity evidence.
It does show that the external sampler is not the dominant cost during the first
half of the run.

The inspection also found a remaining measurement cost: `DIAGNOSTICS_LEVEL=none`
does not disable the generator's internal monitor. Every second it executes exact
`count(*)` queries against the growing Match, Order, and Wallet durable trade
tables and reads RabbitMQ queue state. At this workload those tables reach
`311040` trades each. The steady-state and staircase scripts now expose
`SAMPLE_INTERVAL_SECONDS` and `PROGRESS_INTERVAL_SECONDS` so a future controlled
low-observability comparison can reduce this cost explicitly. Changing the
sample interval changes the observation contract and must be recorded with the
result.

## 1200 and 2000 Short Overload Probes

Both probes used seed `20260822`, `10s` warm-up, `30s` measurement,
`DIAGNOSTICS_LEVEL=none`, `128` synchronous HTTP workers, and at most `256`
in-flight requests. The target rate determines the number of scheduled orders;
it does not prove that the same-host driver delivered that rate.

| Signal | 1200 target | 2000 target |
| --- | ---: | ---: |
| HTTP accepted / failures / unscheduled | `48000 / 0 / 0` | `80000 / 0 / 0` |
| total accepted orders/s | `950.42` | `1264.82` |
| steady accepted orders/s | `1013.36` | `1249.33` |
| offered-load ratio | `84.45%` | `62.47%` |
| steady completed trades/s | `138.72` | `170.46` |
| completed / target trade rate | `23.12%` | `17.05%` |
| completed / actually accepted pair rate | `27.38%` | `27.29%` |
| backlog start / end / maximum | `2993 / 21310 / 21310` | `6501 / 26655 / 26655` |
| backlog slope | `+649.1614/s` | `+685.4301/s` |
| full convergence | `74.1327s`, `323.74 trades/s` | `95.7222s`, `417.88 trades/s` |
| exact final three-service trades | `24000` | `40000` |
| sustained gate | `FAIL` | `FAIL` |

The apparent completion-ratio collapse at 2000 is mostly a denominator effect.
The driver delivered only `1249.33 orders/s` in the steady window, not 2000.
Relative to the actually accepted pair rate, the 1200 and 2000 runs completed
almost the same fraction during traffic: `27.38%` and `27.29%`.

The driver uses synchronous Java HTTP calls. The scheduling thread acquires an
in-flight permit before submitting each request, and the executor has `128`
workers. Once request latency consumes those workers and permits, scheduling
falls behind the nominal open-loop deadlines. Because driver, services, three
PostgreSQL instances, RabbitMQ, and Redis share one host, this result combines
driver capacity and service admission latency. It cannot isolate an Order HTTP
ceiling.

The growing backlog and stage counts locate the overload before durable trade
fanout. At the last traffic sample, Match, Order, and Wallet differed by only
`80-89` trades, while aggregate RabbitMQ backlog was `25654-40126`. Once a trade
was persisted by MatchEngine, Order application and Wallet settlement remained
close. The accumulated work was primarily in the admission, reservation,
confirmation, and matching path, plus durable outbox or in-process work not
represented by RabbitMQ depth.

After sending stopped, the remaining chains drained at approximately `746` and
`900 trades/s`, calculated from the final traffic sample to full convergence.
These are approximate saturated-tail rates, not steady business throughput.
Larger backlogs can keep consumer and relay batches full, while the absence of
concurrent HTTP admission removes shared-host contention. This explains why the
2000 probe's full-convergence average is higher even though its steady gate is
worse.

## Decision

- Keep `648 accepted orders/s` as the current repeatable same-host sustained
  lower-bound class. The failed same-seed repeat reinforces that 648 is a
  pressure boundary, not comfortable headroom.
- Reject `1200` and `2000 orders/s` as sustained-capacity claims. They prove that
  the current revision accepted and eventually reconciled finite bursts without
  HTTP failure, missing trade IDs, asset error, reservation debt, queue debt, or
  DLQ messages.
- Do not publish `417.88 trades/s` as current mixed-flow capacity. It is a
  short burst-plus-drain average after an unattained 2000-order/s target.
- For the next observer-effect comparison, keep code, seed, duration, and host
  setup fixed; record a lower internal sampling frequency explicitly and run the
  order in both directions. For service attribution, move the driver to a
  separate host or CPU domain and collect low-rate pool, WAL, and queue evidence.

Follow-up: the later prepared-sync driver calibration sustained `1999.98
requests/s` against a no-op endpoint and a short 648 full-chain A/B retained
correctness, but did not improve full-convergence throughput. It is therefore a
candidate for cleaner high-rate probes, not evidence that the historical 1200
and 2000 results reached their target or that shared-host interference has been
removed. See the [prepared HTTP driver diagnostic](2026-08-18-prepared-http-driver.md).

Artifacts:

- [648 low-observability result](results/2026-08-18-http-matched-648-15m-seed-20260821-none-r3.json)
- [648 low-observability samples](results/2026-08-18-http-matched-648-15m-seed-20260821-none-r3-samples.csv)
- [1200 overload result](results/2026-08-18-http-matched-1200-10s30s-seed-20260822-r1.json)
- [1200 overload samples](results/2026-08-18-http-matched-1200-10s30s-seed-20260822-r1-samples.csv)
- [2000 overload result](results/2026-08-18-http-matched-2000-10s30s-seed-20260822-r1.json)
- [2000 overload samples](results/2026-08-18-http-matched-2000-10s30s-seed-20260822-r1-samples.csv)
