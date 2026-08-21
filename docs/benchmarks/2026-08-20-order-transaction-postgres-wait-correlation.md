# Order Transaction and PostgreSQL Wait Correlation - 2026-08-20

## Question

The current mixed HTTP lifecycle can show a full `OrderCommandPool`, HTTP response
timeouts, and PostgreSQL waits at the same time. This investigation asked whether:

1. the initial Order append SQL is intrinsically too slow;
2. the command pool is simply too small; or
3. concurrent durable writes create short PostgreSQL stalls that keep connections
   checked out and make HTTP requests queue at Hikari.

This is a same-host diagnostic, not a new capacity benchmark. All services,
PostgreSQL containers, RabbitMQ, Redis, monitoring, and the Vegeta driver shared one
laptop.

## Measurement Corrections

The first `700 orders/s` run (`ORDER_TX_CORRELATION_700_20260820_R1`) used a deep
sampler that repeatedly enumerated all RabbitMQ connections and channels and fetched
duplicated actuator data. The observer overhead was material: it sampled only 22
times over roughly 494 seconds and accepted only `604.71 orders/s` in the steady
window. That run is rejected as performance evidence.

Before repeating the diagnostic:

- RabbitMQ connection and channel enumeration was removed from every runtime sample;
- actuator metrics were fetched once per service per sample and histogram buckets
  were excluded;
- PostgreSQL activity sampling excluded its own backend and non-client processes;
- Order JDBC pools received distinct PostgreSQL `application_name` values, which
  made the representative query in each wait group identifiable.

The runs still grouped wait counts at database level. After the A/B exposed that a
representative ConsumerPool query could be mistaken for a CommandPool count, the
collector and summary were changed to group future samples by `application_name`.
This prevents Command, Consumer, and Projection sessions from being combined in the
same wait row. Historical aggregate counts below retain that limitation.

## Isolated Current-Path Probe

`orderSubmissionDbCeilingProbe` executed the current initial append CTE directly. It
writes `order_stream_heads`, `order_event_store`, and `order_event_outbox` in one
transaction while bypassing HTTP, Spring, RabbitMQ, Wallet, and MatchEngine.

| Workers | Events | Completed | Append TPS | p50 | p95 | p99 |
|---:|---:|---:|---:|---:|---:|---:|
| 16 | 20,000 | 20,000 | 5,601.14/s | 1.376 ms | 6.616 ms | 30.311 ms |
| 35 | 20,000 | 20,000 | 6,163.82/s | 2.594 ms | 9.637 ms | 58.716 ms |
| 50 | 20,000 | 20,000 | 6,499.42/s | 4.650 ms | 11.842 ms | 30.443 ms |

The short probe is not a capacity claim. It does show that the SQL path in isolation
is several times faster than the `700 orders/s` full-chain input and that higher
writer concurrency increases per-row latency before it becomes a throughput limit.
The initial CTE is therefore not an isolated `700 orders/s` ceiling.

## Full-Chain Pool A/B

Both comparable runs used the same shuffled workload seed `20260899`, `60s` warm-up,
`300s` measurement, one Vegeta CPU, jar-launched services, and the corrected five-second
deep sampler. The only intended service setting change was
`EAP_ORDER_COMMAND_POOL_SIZE=35 -> 24`.

| Signal | Pool 35 baseline | Pool 24 candidate | Reading |
|---|---:|---:|---|
| Steady accepted orders/s | 695.43 | 685.96 | regressed |
| Steady completed trades/s | 307.20 | 306.91 | no improvement |
| Full-convergence trades/s | 310.71 | 308.74 | no improvement |
| CommandPool pending peak | 151 | 170 | regressed |
| Match order-confirmed queue peak | 1,278 | 11,085 | bottleneck moved downstream |
| Match-to-durable p95 | 1,128.73 ms | 1,555.22 ms | regressed |
| Match-to-durable p99 | 1,707.63 ms | 64,478.20 ms | severe tail regression |
| HTTP outcome | 1,345 client timeouts; all 252,000 durable | 3 EOF, 1,180 unscheduled | both invalid for capacity |
| Durable correctness | exact 126,000 three-service trades | exact 125,398 pairable three-service trades | both passed their durable subset |

The pool-24 run was also exposed to higher average host CPU, so the magnitude of the
tail difference cannot be attributed only to pool size. It is still sufficient to
reject pool 24: the candidate produced no throughput or latency benefit under the
same intended workload and introduced scheduling loss.

## Transaction Envelope

| Mean timing | Pool 35 | Pool 24 | Change |
|---|---:|---:|---:|
| Order submission transaction total | 83.306 ms | 155.926 ms | +87.2% |
| Before transaction callback | 60.782 ms | 132.742 ms | +118.4% |
| Hikari CommandPool acquire | 60.767 ms | 132.727 ms | +118.4% |
| Hikari CommandPool usage | 22.546 ms | 23.178 ms | +2.8% |
| Transaction body | 14.118 ms | 14.937 ms | +5.8% |
| Initial append CTE application timer | 14.055 ms | 14.862 ms | +5.7% |
| PostgreSQL initial CTE executor mean | 5.143 ms | 6.232 ms | +21.2% |
| After transaction body | 8.406 ms | 8.246 ms | -1.9% |

`transaction_before_callback` and Hikari acquire time are effectively identical.
The dominant delay is therefore waiting to obtain a connection, not serialization,
hashing, or Java code inside the callback. Once acquired, the connection remains
checked out across SQL execution and commit for roughly 22-23 ms on average.

## PostgreSQL Wait Relationship

In the pool-35 run, the largest CommandPool pressure samples aligned with aggregated
Order database wait groups whose representative query was the current initial append
CTE or its commit:

- at `01:22:36Z`, CommandPool pending reached `151`; the Order DB sample reported 13
  active `BufferContent` waits, eight `idle in transaction` sessions, and three
  `WALInsert` waits, with initial-append or commit representative queries;
- at `01:24:39Z`, pending reached `149` while the aggregate Order DB sample reported
  22 active `WALInsert` waits with an initial-append representative query;
- interval timers still recorded high acquire time when a five-second point sample
  missed the short stall, which is why cumulative timers and point-in-time gauges
  must be interpreted together.

Reducing the command pool lowered the sampled Order `BufferContent` and `WALInsert`
peaks, but it did not reduce total transaction time. Later samples instead showed
OrderConsumerPool/outbox `extend` lock pressure, a much larger Match queue, and a
higher Hikari wait. The system moved waiting from PostgreSQL command writers to the
pool boundary and downstream durable work.

The evidence supports this working causal model:

```text
overlapping durable writes on a shared host
  -> short buffer/WAL/extension stalls during SQL or COMMIT
  -> connections stay checked out
  -> Order HTTP threads queue at Hikari
  -> response and queue tails grow
```

This is not evidence of a normal row-lock deadlock, nor evidence that the transaction
manager itself consumes 60-130 ms of CPU.

## Write Amplification And Durability Boundary

The load-test Order database retained the rows from the full-chain runs. Its largest
relations were `order_event_store` at `337 MB`, `order_event_outbox` at `147 MB`,
`order_stream_heads` at `65 MB`, `order_matching_state` at `41 MB`, and
`order_trade_applications` at `22 MB`. The actual schema had no duplicate
aggregate/version index to remove. The event ID and aggregate/version uniqueness
constraints are correctness boundaries, while the outbox partial indexes support
relay recovery and retry selection.

An isolated 20,000-row current-path probe generated approximately `86 MB` of WAL, or
`4,519.5 bytes/call`, for the initial head, event, and outbox CTE. That run followed
a PostgreSQL restart and included `9,731` full-page images, so the number is a
write-shape diagnostic rather than a steady-state per-order constant. Marking the
same probe outbox range sent generated approximately `13 MB`, or about `697 bytes`
per updated row. The sent transition changes membership in the pending partial
index, so it cannot be treated as a free heap-only update.

A prior `event_store_only` experiment removed work from the initial HTTP transaction
and more than doubled the isolated append result, but it moved the full-chain
bottleneck into projector and checkpoint relay work and introduced commit-order
safety concerns. That candidate remains rejected; the isolated TPS did not prove a
better business lifecycle.

The benchmark database normally uses `synchronous_commit=off`. A controlled
20,000-row, 35-worker probe measured `7,953.80 appends/s` with that setting and
`6,971.59 appends/s` with session-level `synchronous_commit=on`. The durability-safe
setting was about `12.3%` slower in this short isolated repeat, but remained far
above the full-chain input rate. This rules out durable commit as the isolated
`700 orders/s` ceiling; it does not establish production capacity. A production
durability claim requires a full-chain run with synchronous commit enabled.

Future deep diagnostics now rank `pg_stat_statements` entries by generated WAL in
addition to executor time. The compose file keeps the historical default for
comparability but exposes `EAP_LOADTEST_SYNCHRONOUS_COMMIT` and
`EAP_LOADTEST_TRACK_IO_TIMING` / `EAP_LOADTEST_TRACK_WAL_IO_TIMING` for explicitly
labeled durability and storage diagnostics.

The pool-35 full-chain window generated about `1.06 GB` of Order WAL while
`wal_buffers_full` stayed at `0`; spread over the several-minute run, this is not an
SSD bandwidth ceiling. The simultaneous peaks of 30 `BufferContent` and 22
`WALInsert` waiters instead point to contention among concurrent writers inside the
same PostgreSQL instance. The Order pools can expose up to 58 application
connections in total (`35` command, `20` consumer, `3` projection), even though they
are separated at Hikari. Docker containers do not give those writers exclusive CPU,
memory bandwidth, or storage.

Historical collector-count probes already tested reducing the asset-confirmation
consumer concurrency from `16` to `8`, `4`, and `2`. They produced larger batches
but no stable full-chain improvement; the two-collector run made connection acquire
and upstream timings worse. Do not repeat that tuning without new pool-attributed
evidence.

## Short Pool-Attributed Recheck

`ORDER_POOL_ATTRIBUTION_648_20260820_R1` used the same shuffled seed `20260899`, a
20-second warm-up, a 60-second measurement window, one Vegeta CPU, five-second deep
sampling, and PostgreSQL I/O timing. The harness accepted all `51,840` requests and
the three services converged on the same `25,920` trades with correct assets, empty
queues, zero DLQ rows, and zero active reservations.

This short window did not reproduce the sustained-700 collapse:

| Signal | Short 648 diagnostic |
|---|---:|
| Steady accepted orders/s | 647.89 |
| Steady completed trades/s | 325.48 |
| Full-convergence trades/s | 311.74 |
| Order CommandPool active / pending peak | 13 / 0 |
| Order ConsumerPool active / pending peak | 10 / 0 |
| Order ProjectionPool active / pending peak | 0 / 0 |
| Initial CTE PostgreSQL / application mean | 0.611 / 3.998 ms |
| Order transaction acquire / usage / total mean | 3.281 / 6.735 / 10.049 ms |
| Match-to-durable-convergence p95 | 264.471 ms |
| Order WAL delta | 202,027,432 bytes |
| Order WAL buffer-full delta | 0 |

No `BufferContent` or `WALInsert` peak was sampled. The pool-attributed actionable
rows were short `ClientRead` transaction gaps in ConsumerPool and CommandPool, plus
one CommandPool `extend` sample. No checkpoint, backend-buffer write, or backend
fsync delta occurred during the short window. This rejects the claim that the Order
database is continuously saturated at `648 orders/s`.

The comparison instead shows a nonlinear sustained-overload boundary. At 648, the
pipeline remains mostly caught up; at the earlier sustained 700 load, unfinished
work overlaps across more stages, PostgreSQL writer concurrency rises, Hikari queues
grow, and the host enters a feedback loop. The exact turn cannot be assigned to an
individual pool from the old aggregate 700 samples. A fresh sustained-700 diagnostic
is required before implementing an aggregate writer budget.

The WAL ranking also narrows any future write-model review. The initial append
generated `94,919,549` bytes (`1,831 bytes/order`), while the asset-confirmation CTE
generated `72,044,747` bytes across `8,641` batches (`8,337.5 bytes/batch`). Together
they accounted for about 82.6% of the Order WAL captured by `pg_stat_statements`.
Outbox mark-sent statements were not the primary WAL producer. These numbers are
diagnostic write-shape evidence, not capacity or storage-bandwidth claims.

## Sustained 700 Pool-Attributed Reproduction

`ORDER_POOL_ATTRIBUTION_700_20260820_R1` then attempted a 60-second warm-up plus
15-minute shuffled measurement at `700 orders/s` using the co-located Vegeta driver
and five-second deep diagnostics. The run was stopped after `684.761s`, before the
workload and final correctness gate completed, because HTTP transport errors and
cross-stage connection pressure were already accumulating. It is therefore an
interrupted diagnostic and cannot be used as throughput or reliability evidence.

Before interruption, `467292` of `467780` retained HTTP results were `200`; `488`
were EOF/reset-style transport failures. The sampled Order CommandPool reached
`35 active / 161 pending`, ConsumerPool reached `20 / 5`, and Wallet reached
`40 / 24`. Maximum sampled business backlog was `5458`. The Order database generated
about `1.81 GB` of WAL, while samples included short `BufferContent`, `WALInsert`,
relation-extension, and idle-in-transaction waits attributed to the command or
consumer pools. Redis reported no evictions and RabbitMQ reported no memory or disk
alarms.

The graceful service shutdown lines in the logs came from operator cleanup after the
interrupt; this run does not prove that an Order JVM crashed. It does reproduce the
nonlinear long-window pool pressure absent from the short 648 run and justified one
bounded pool-budget experiment. See the compact
[interrupted result](results/2026-08-20-order-transaction-correlation/pool-attribution-700-interrupted-r1.json).

## Coordinated Front-Half Pool-Budget Matrix

The follow-up changed one coordinated load-test-only variable: the total Order JDBC
budget across command, consumer, and projection pools. Each profile ran twice with
the same one-sided front-half workload, `1300 orders/s` offered target, `10400`
accepted orders, light diagnostics, and clean JVM restarts.

| Profile | Total max | HTTP accepted/s | Order-book admission/s | Convergence/s | Two-run spread |
|---|---:|---:|---:|---:|---:|
| `baseline-58` | 58 | 1102.62 | 1042.99 | 1041.78 | 0.02% |
| `balanced-48` | 48 | 1068.45 | 999.05 | 998.11 | 3.45% |
| `balanced-40` | 40 | 1079.73 | 996.15 | 995.24 | 17.21% |

All six underlying runs accepted all orders, reached exact durable front-half counts,
drained queues, and reported no capacity-invalid reason. All six nevertheless missed
the predeclared `1170 order-book admissions/s` repeat threshold, so the matrix is a
saturation diagnostic, not a capacity result. Relative to baseline, the 48-connection
profile regressed order-book throughput by about `4.2%`; the 40-connection profile
regressed it by about `4.5%` and was substantially less repeatable.

Baseline repeat 1 inherited cumulative service timer history from the preceding
interrupted full-chain run before its reset. Its current-run counters and throughput
converged, but detailed timer comparisons exclude that repeat. The uncontaminated
baseline repeat 2 still reached `1043.09 order-book admissions/s`, above every
candidate repeat except the volatile `balanced-40` repeat 1 (`1081.86/s`), whose
repeat 2 fell to `910.44/s`. There is no evidence that reducing the aggregate pool
budget improves the front half. Both candidates are rejected without spending a
full-chain A/B run.

## Market Sequence and Redis Connection Diagnostics

The next bounded front-half sandwich kept the one-sided `orderAdmissionChain`,
`1300 orders/s` offered target, `10400` accepted orders, light diagnostics, and
clean JVM restarts. It compared the current per-order Redis `INCR` with a local
64-sequence allocation block, then returned to the current setting. Four current
`block-size=1` controls averaged `967.55 order-book admissions/s`, but varied from
`828.38` to `1101.77/s`. Their market-sequence allocation averaged `16.675 ms`.

The two `block-size=64` diagnostics reached `1035.18` and `1037.14 order-book
admissions/s`. Market-sequence allocation averaged `3.194 ms`, pre-event-store time
fell from the four-control average of `17.913 ms` to `3.857 ms`, and mean HTTP p95
fell from `215.88 ms` to `119.12 ms`. This shows that repeated same-host Redis
round trips explain a material part of the variable front-half latency. It does not
prove a higher lifecycle ceiling: healthy `block-size=1` controls still reached
`1072.53` and `1101.77/s`.

The allocation-block candidate is not safe to adopt. `marketSequence` participates
in MatchEngine price-time ordering. With multiple Order replicas, independently
consumed local blocks can assign a higher sequence to an earlier request and a lower
sequence to a later request on another replica. Saving Redis calls cannot override
that ordering contract. The production and load-test defaults therefore remain
`block-size=1` until sequence ownership has an architecture that preserves global
ordering across replicas and restarts.

A second semantic-preserving candidate disabled Lettuce's shared native connection
and enabled a 16-connection pool. Its first run reached `989.70 order-book
admissions/s`, while market-sequence allocation worsened to `38.109 ms`. Repeat 2
then logged 85 pool-borrow timeouts at the Redis `INCR` path and returned HTTP 500:
`Timeout waiting for idle object, borrowMaxWaitDuration=PT0.5S`. The invalid repeat
was interrupted instead of waiting for a final count it could no longer reach. The
Lettuce pool candidate is rejected; the existing shared native connection remains.

These are short one-sided, same-host diagnostics. They neither change the mixed
full-lifecycle capacity boundary nor justify a production configuration change.
They reinforce, rather than supersede, the historical TPS-152 repeat: block size
`1000` reduced sequence time by `96.94%`, but business convergence improved only
`2.12%`, below the run-to-run spread, while Order connection acquisition worsened.
Both revisions therefore reach the same decision: do not repeat block-size tuning
unless the ordering ownership or deployment boundary changes.

## Decision

- Keep the Order command pool at 35; reject the pool-24 candidate.
- Keep the existing aggregate `35/20/3` command/consumer/projection budget; reject
  the coordinated `30/16/2` and `26/12/2` candidates.
- Do not increase pool or listener concurrency as the first response. The isolated
  probe and historical 16/35/50-worker results already show rising tail cost as DB
  concurrency grows.
- Do not remove the explicit transaction or switch the append to unsafe autocommit.
  The CTE is followed by a Java postcondition check; a failure after statement
  autocommit could not roll back the inserted head, event, and outbox fact.
- Treat deep runs as attribution evidence only. The current low-observation Vegeta
  matrix remains the capacity authority.
- Keep per-order market-sequence allocation and Lettuce's shared native connection.
  Block allocation showed a local latency benefit but fails the multi-replica global
  ordering requirement; the dedicated Lettuce pool introduced HTTP 500 failures.

## Next Bounded Experiment

The next code-oriented investigation needs an architecture decision before another
implementation experiment:

1. define which component owns a globally ordered per-market admission sequence;
2. preserve price-time priority across multiple replicas, restarts, retries, and
   out-of-order event delivery;
3. only then compare a sequence-allocation candidate with the current per-order
   Redis `INCR` at the same pool sizes, seed, duration, and workload;
4. in parallel, retain the implemented pool attribution and per-statement WAL data
   for any future durable-write candidate;
5. accept a change only if ordering correctness, acquire time, PostgreSQL waits,
   backlog, lifecycle latency, and all final gates improve together.

The completed [front-half pool-budget matrix](2026-08-20-distributed-capacity-and-front-half-scaling.md)
eliminated both smaller aggregate budgets without changing current service defaults.
Do not repeat pool sizing without a new causal signal.

Before changing the production write shape, repeat the same diagnostic with the load
generator or services on an independent CPU/host. The present runs show a real
same-host interaction but cannot separate application contention from laptop-wide CPU
and storage scheduling.

## Published Artifacts

- [observer-heavy rejected result](results/2026-08-20-order-transaction-correlation/observer-heavy-r1-result.json)
- [pool-35 result](results/2026-08-20-order-transaction-correlation/pool35-r2-result.json)
- [pool-35 runtime summary](results/2026-08-20-order-transaction-correlation/pool35-r2-runtime.md)
- [pool-35 write-cost summary](results/2026-08-20-order-transaction-correlation/pool35-r2-write-cost.md)
- [rejected pool-24 result](results/2026-08-20-order-transaction-correlation/pool24-r1-result.json)
- [rejected pool-24 runtime summary](results/2026-08-20-order-transaction-correlation/pool24-r1-runtime.md)
- [rejected pool-24 write-cost summary](results/2026-08-20-order-transaction-correlation/pool24-r1-write-cost.md)
- [short 648 pool-attributed result](results/2026-08-20-order-transaction-correlation/pool-attribution-648-r1-result.json)
- [short 648 pool-attributed runtime summary](results/2026-08-20-order-transaction-correlation/pool-attribution-648-r1-runtime.md)
- [short 648 pool-attributed write-cost summary](results/2026-08-20-order-transaction-correlation/pool-attribution-648-r1-write-cost.md)
- [interrupted sustained-700 diagnostic](results/2026-08-20-order-transaction-correlation/pool-attribution-700-interrupted-r1.json)
- [sustained-700 runtime summary](results/2026-08-20-order-transaction-correlation/pool-attribution-700-interrupted-r1-runtime.md)
- [front-half pool-budget matrix](results/2026-08-20-front-half-pool-budget/front-half-pool-budget-r1.json)
- [market-sequence and Lettuce A/B](results/2026-08-20-market-sequence/market-sequence-and-lettuce-ab-r1.json)
