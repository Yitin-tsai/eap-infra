# Release-Pinned 650 Sustained Boundary Probe

## Purpose

After two workload seeds passed the release-pinned `600 orders/s` sustained
contract, this run tested the next step at `650 orders/s`. It used the same
single-host shuffled mixed-HTTP lifecycle, correctness gates, and resource-alarm
checks. Dedicated RabbitMQ, Redis, and PostgreSQL containers were restarted before
the run to provide an independent clean start.

Repository versions:

| Repository | Commit |
| --- | --- |
| `eap-infra` | `7136608` |
| `eap-common` | `628893a` |
| `eap-order` | `d8564b7` |
| `eap-wallet` | `3811169` |
| `eap-matchEngine` | `ed55214` |

## Contract

- `60s` warmup and `900s` measurement window;
- target `650 total orders/s`, seed `20260813`, and `500` users per side;
- at least `95%` offered load and completion target ratio;
- backlog slope at most `+7 messages/s` and maximum backlog at most `21000`;
- traffic scheduling may overrun the fixed workload window by at most `30s`;
- exact MatchEngine, Order, and Wallet trade IDs and asset reconciliation;
- final queues, DLQ, order books, and active reservations drained to zero;
- no RabbitMQ memory or disk alarm during the run.

## Result: Rejected for Sustained Capacity

| Signal | Result |
| --- | ---: |
| expected / accepted HTTP orders | `624000 / 614207` |
| unscheduled orders | `9793` |
| HTTP `429 / 503 / other` | `0 / 0 / 0` |
| steady accepted orders/s | `623.08` |
| offered-load ratio | `95.86%` |
| steady completed trades/s | `281.80` |
| completion target ratio | `86.71%` |
| completion-to-accepted ratio | `90.45%` |
| backlog start / end | `21660 / 2422` |
| backlog slope | `+2.3459/s` |
| maximum backlog | `27384` |
| full convergence | `1315.5580s` |
| full-convergence trades/s | `233.40` |
| Match / Order / Wallet trades | `307050 / 307050 / 307050` |
| final queue / DLQ / reservation debt | `0` |
| capacity decision | reject |

The result failed four predeclared gates:

- `http_accepted_count_mismatch`;
- `traffic_scheduling_deadline_exceeded`;
- `steady_completion_rate_below_minimum`;
- `steady_queue_backlog_above_limit`.

The offered-load ratio itself remained just above `95%`, but the generator could
not schedule the complete workload within the fixed window plus `30s` grace. The
run therefore cannot be presented as a 650 sustained-capacity pass.

[Rejected result JSON](results/2026-08-13-http-matched-releasepin-650-seed-20260813-r1-rejected.json)

## Correctness Outcome

The incomplete offered workload still converged correctly. Durable accepted
orders consisted of `307050` BUY and `307157` SELL orders. They produced `307050`
identical three-service trades, leaving exactly `107` unmatched SELL orders and
`107` locked seller units. Buyer and seller balances matched those outcomes. All
measured RabbitMQ queues, the DLQ, and active MatchEngine reservations reached
zero.

This is a capacity failure, not a trade-integrity failure.

## Diagnostics

RabbitMQ reported no memory or disk alarm in `80` samples. Redis peaked at about
`105 MB`, reached `19019 ops/s`, and had no eviction. The largest queue was
`matchEngine.orderConfirmed.queue` at `26144`; `wallet.orderSubmitted.queue`
peaked at `2514`, while downstream trade queues remained below `221`.

The host was saturated: sampled system CPU averaged `97.4%` from Order's view,
`97.0%` from Wallet's view, and `94.5%` from MatchEngine's view. Order's command
pool reached `35` active connections with `92` pending; Wallet reached `40` active
with `24` pending. PostgreSQL WAL growth was approximately `2.87 GB` for Order,
`1.09 GB` for Wallet, and `0.92 GB` for MatchEngine. Order also exposed a long
running trade-application batch during a late pressure interval.

These signals support two simultaneous limits: MatchEngine order-confirmed intake
accumulated the largest broker backlog, while Order and Wallet database pools and
the shared host were also saturated. This run does not isolate one of them as the
sole cause.

Wallet also logged a Micrometer warning for a `-9000ns` timer value. Its Outbox
relay measured process-local latency by subtracting two wall-clock instants, which
can move backward slightly. Wallet commit
[`e538362`](https://github.com/Yitin-tsai/eap-wallet/commit/e538362) changed those
stage measurements to the JVM monotonic clock and added a non-negative elapsed-time
test. This post-run observability fix does not change the rejected 650 result or
claim a throughput improvement.

## Decision

- keep the two-seed `600 accepted orders/s` class as the current release-pinned
  15-minute sustained lower bound;
- reject 650 as current sustained capacity even though final correctness passed;
- do not increase pool sizes or concurrency without an isolated hypothesis;
- use the corrected Wallet monotonic latency instrumentation in the next
  attribution run, while tracking the same pattern in other services separately;
- use a targeted diagnostic or an even step between 600 and 650 only after the
  measurement evidence remains trustworthy.
