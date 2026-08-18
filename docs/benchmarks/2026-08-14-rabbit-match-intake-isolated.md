# RabbitMQ-to-Match Intake Isolated Diagnostic

## Purpose

The combined Match processor probe showed that Redis matching plus the durable
trade transaction was not the sole full-chain bottleneck, but it omitted the
real RabbitMQ listener. This diagnostic adds the next boundary:

`RabbitMQ publisher confirm -> Match OrderConfirmed listener/ack -> Redis matching -> TradeExecuted + outbox + cleanup task -> concurrent reservation cleanup`

It starts only RabbitMQ, Match PostgreSQL, Redis, and one real MatchEngine
application context. The Match trade outbox relay is disabled because Order and
Wallet are deliberately absent. This is an isolated diagnostic, not a full-chain
or production capacity claim.

## Workload And Gates

- `10000` BUY/SELL pairs, or `20000` total OrderConfirmed messages;
- paced, shuffled mixed arrival with a recorded seed;
- real persistent RabbitMQ messages, publisher confirms, `12` configured Match
  listener consumers, Redis Lua matching, database transaction, outbox write,
  completion bitmap, and concurrent reservation cleanup;
- exact trade rows, distinct trade IDs, matched quantity, outbox rows, cleanup
  tasks, and incoming completion markers;
- empty BUY/SELL books, no remaining workload reservations, empty final Match
  queue and DLQ, and zero publisher nack/return.

The publisher and service share one JVM and host to keep the diagnostic cheap.
RabbitMQ management statistics are sampled every `100ms`, but broker statistics
can refresh more slowly. Sampled ready/unacked peaks can therefore be
undercounted and are not used as a capacity or correctness claim.

## Valid Results

| Signal | `1200 orders/s`, seed `20260815` | `2000 orders/s`, seed `20260814` |
| --- | ---: | ---: |
| offered orders/s | `1200.04` | `2000.07` |
| confirmed orders/s | `1199.88` | `1996.86` |
| durable Match persistence window | `17.22s` | `10.89s` |
| persisted orders/s | `1161.77` | `1836.92` |
| persisted trades/s | `580.88` | `918.46` |
| full cleanup window | `17.22s` | `10.89s` |
| cleanup-converged trades/s | `580.88` | `918.46` |
| listener mean / max | `2.30 / 264.69ms` | `3.28 / 93.66ms` |
| trade transaction mean / max | `1.75 / 122.87ms` | `2.42 / 57.87ms` |
| correctness | `PASS` | `PASS` |

Both runs produced exactly `10000` trade rows, distinct trade IDs, outbox rows,
and completed cleanup tasks, plus `20000` incoming completion markers. Final
order books, workload reservations, Match queue, and DLQ were empty.

Artifacts:

- [1200 orders/s result](results/2026-08-14-rabbit-match-intake-20k-1200-seed-20260815-r1.json)
- [2000 orders/s result](results/2026-08-14-rabbit-match-intake-20k-2000-seed-20260814-r1.json)

Both declare `evidenceClass=isolated-diagnostic` and
`capacityClaimAllowed=false`.

## Rejected Measurements

Earlier probe revisions checked all `20000` workload reservation keys on Redis
every `200ms`. That monitoring work competed with the real Redis path and made a
`1200 orders/s` run appear to persist only `919.61 orders/s`. The same issue also
affected the earlier `2000 orders/s` result. Those measurements are rejected.

The corrected probe polls aggregate database and bitmap state during the run,
performs the per-order reservation scan only once in the final correctness gate,
and excludes RabbitMQ management-statistics refresh waiting from throughput
timing. The rejected results remain part of the experiment history but are not
published as performance evidence.

An intermediate revision moved the per-order scan to the final gate but still
included that scan in `fullCleanupConvergenceSeconds`, creating a false
`2.4-2.6s` cleanup tail. The final revision captures the cleanup-complete
timestamp before running the expensive final reservation scan. The valid runs
show persistence and cleanup completing in the same sampled interval.

## Interpretation

The corrected boundary can nearly track a paced `1200 orders/s` input at durable
Match persistence. Under the short `2000 orders/s` overload, it persists
`918.46 trades/s`, with cleanup converged in the same measured window. This remains well above
the current shuffled full-chain result of roughly `350 trades/s`.

This rejects Rabbit delivery, Redis matching, Match trade/outbox persistence,
and reservation cleanup as the sole current full-chain limit. It does not clear
shared-host contention or the omitted Match trade-outbox relay plus downstream
Order and Wallet consumers. That integrated downstream boundary is the next
useful diagnostic before another long full-chain run.
