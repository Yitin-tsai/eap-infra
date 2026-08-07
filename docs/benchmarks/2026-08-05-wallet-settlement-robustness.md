# Wallet Settlement Robustness Benchmark - 2026-08-05

## Scope

This benchmark separates three questions:

1. Does the full HTTP transaction chain eventually complete without loss?
2. What input rate can the single-host environment sustain without growing backlog?
3. Is Wallet settlement SQL responsible for the observed completion lag?

All runs used the `core-capacity` profile, shuffled BUY/SELL arrivals, 500 users per
side, 128 HTTP workers, and rate limiting disabled.

## Three-run long staircase baseline

Each run executed 30 seconds of warmup plus 180 seconds of measurement at 900,
950, and 1000 total orders/s. Services and data were reset between runs, but not
between stages within a run.

| Target orders/s | Runs passing | Mean offered orders/s | Mean completed trades/s | Completion range | Largest queue backlog |
|---:|---:|---:|---:|---:|---:|
| 900 | 2/3 | 898.34 | 440.39 | 426.47-448.83 | 3,482 |
| 950 | 0/3 | 933.96 | 409.46 | 386.10-431.42 | 11,582 |
| 1000 | 1/3* | 922.60 | 401.44 | 320.12-502.63 | 12,027 |

`*` The 1000 orders/s pass is not valid as an independent capacity result. That
stage consumed backlog created during the failed 950 stage, so its output included
work admitted earlier.

Across the three runs, 1,795,500 HTTP orders produced 897,750 trades. Match, Order,
and Wallet all persisted exactly 897,750 trade IDs, all fingerprints matched, all
queues drained, and the DLQ remained empty. Final business completion was 100% in
all three runs.

The baseline therefore proves reliability under overload, but it does not prove a
repeatable 1000 orders/s sustained capacity. Even 900 orders/s passed only two of
three times on this single host.

## Bottleneck attribution

Persisted timestamp attribution across the three baseline runs showed:

| Stage | Observed range |
|---|---:|
| Match to Order p95 | 18.40-50.86 ms |
| Match to Wallet p50 | 3.57-4.85 s |
| Match to Wallet p95 | 15.29-19.72 s |
| Match to Wallet maximum | 21.62-24.25 s |

Wallet processed 299,250 settlements per run. Its explicit per-event transaction
averaged 18.82-22.80 ms, while the settlement CTE itself averaged 7.22-8.96 ms.
With eight settlement consumers, that transaction duration predicts roughly
351-425 trades/s, which matches the full-chain observations.

GC was not the primary cause: maximum recorded Wallet GC pauses were 26-66 ms.
The Hikari pool had no pending waiters after convergence. PostgreSQL samples did
show WAL, buffer-content, and transaction lock waits during high load.

## Wallet boundary experiment and correction

Wallet settlement uses one PostgreSQL CTE containing the idempotency insert and both
wallet updates. On 2026-08-05, the listener's surrounding `TransactionTemplate` was
removed on the assumption that statement-level autocommit also protected the complete
business postcondition. A forced PostgreSQL integration rerun on 2026-08-06 disproved
that assumption and reproduced a deadlock with reversed buyer/seller wallet roles.

An isolated 30,000-settlement A/B test with eight workers produced:

| Mode | Settlement TPS | p50 | p95 | p99 | Failures |
|---|---:|---:|---:|---:|---:|
| Explicit transaction per row | 11,799.16 | 0.616 ms | 0.940 ms | 1.868 ms | 0 |
| Single-statement autocommit | 20,405.04 | 0.348 ms | 0.613 ms | 0.982 ms | 0 |

Autocommit improved isolated happy-path throughput by 72.9%. In the full chain,
average Wallet transaction time fell from 21.13 ms across the baseline to 9.26 ms,
a 56.2% reduction. These numbers are retained as diagnostic evidence only; the
optimization is rejected and is not a current capacity result.

The earlier validation missed the defect for three reasons:

1. The funded load-test workload guaranteed that both wallets existed and had enough
   balance, so it did not exercise the Java postcondition failure path after the SQL
   statement had autocommitted.
2. Statement atomicity was confused with business-operation atomicity. The affected-row
   validation runs in Java after `JdbcClient.update(...)` returns; without an outer
   transaction, a failed validation cannot roll back the already committed statement.
3. The first integration-test invocation was reported up to date. A forced
   `--rerun-tasks` execution exposed the PostgreSQL deadlock, showing that a green cached
   task was not fresh evidence for the changed SQL path.

The corrected listener keeps single-event processing but restores one explicit
transaction per event. The settlement SQL locks both wallet UUIDs in stable order,
distinguishes a true duplicate from missing prerequisites, and throws before commit
when the settlement and both wallet updates are not all present. Forced PostgreSQL
tests now cover reversed-role concurrency, a missing seller wallet, and insufficient
seller balance; all three pass without deadlock or partial state.

## Observer effect

The steady-state monitor queried three growing trade tables every second. At
105,000 trades, `EXPLAIN ANALYZE` measured about 120 ms in aggregate for one sample,
including sequential scans caused by `left(trade_id, ...)` filters. Diagnostic
sampling added more count queries every five seconds. Under a CPU-saturated
single-host test, the observer materially reduced available capacity.

The reset-data path now counts the truncated tables directly and keeps prefix
filtering only for non-reset runs. The runner also fails immediately after HTTP
traffic errors instead of waiting for an impossible original expected count.

## Post-change independent 1000 orders/s result

The final independent run used a 10-second durable sample interval and disabled
continuous diagnostics:

- HTTP accepted: 210,000 / 210,000, with no HTTP errors.
- Final trades: 105,000 in Match, Order, and Wallet with equal trade IDs.
- Final queue backlog and DLQ: zero.
- Steady accepted rate: 984.95 orders/s.
- Same-window completed rate: 443.97 trades/s.
- Same-window target ratio: 88.79%.
- Maximum observed queue backlog: 3,166.
- Full convergence: 222.79 seconds, or 471.30 trades/s end to end.
- Drain tail after traffic: about 12.27 seconds.

The run remains invalid as proof of sustained 1000 orders/s capacity because the
completion ratio was below 95% and backlog grew near the end of the window. It does
prove 100% eventual completion and a higher full-chain convergence rate after the
Wallet change.

## Independent short-window verification

> Historical diagnostic: these runs used the Wallet autocommit boundary that the
> 2026-08-06 rollback/deadlock review rejected. Their throughput remains reproducible
> evidence for that revision, but none is a current-code capacity claim.

Each point below started from reset data and freshly restarted services. Unlike the
staircase runs, no point inherited work from a previous rate. Each run used a
30-second warmup, a 180-second measurement window, a 10-second durable-state sample
interval, no continuous diagnostic sampler, and workload seed `20260805`. The
repeats test runtime variance for one deterministic mixed workload; they are not a
multi-seed or 30-minute soak result.

Three independent 900 orders/s runs all passed:

| Run | HTTP accepted | Steady orders/s | Steady trades/s | Completion ratio | Maximum backlog | Backlog slope | Full-convergence trades/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| R1 | 189,000 / 189,000 | 899.94 | 449.89 | 99.98% | 429 | +0.10/s | 444.11 |
| R2 | 189,000 / 189,000 | 899.97 | 440.01 | 97.78% | 379 | +0.77/s | 444.84 |
| R3 | 189,000 / 189,000 | 900.30 | 449.78 | 99.92% | 806 | +0.05/s | 445.35 |

Across the three runs:

- 567,000 of 567,000 HTTP orders were accepted, with zero HTTP failures.
- 283,500 of 283,500 expected trades were persisted by Match, Order, and Wallet.
- All three trade-ID sets and fingerprints matched in every run.
- All measured queues, the DLQ, active match reservations, and locked wallet
  balances returned to zero.
- Mean steady accepted load was 900.07 orders/s.
- Mean same-window business completion was 446.56 trades/s.
- Mean full-convergence throughput was 444.77 trades/s; run range was
  444.11-445.35 trades/s.
- Mean full convergence time was 212.47 seconds.

The independent 950 orders/s point passed R1 at 950.13 accepted orders/s and
476.67 same-window completed trades/s. R2 accepted only 199,365 of 199,500 orders:
135 HTTP requests failed in two bursts late in the run, so the generator correctly
failed before claiming full business convergence. That makes 950 orders/s a
single-host boundary result, not a repeatable capacity claim.

## Three-seed short-window verification

Two additional independently reset runs changed the shuffled arrival seed to
`20260806` and `20260807`. Together with the `20260805` R3 run, all three seeds
passed the same 30-second warmup plus 180-second measurement contract:

| Seed | Steady orders/s | Steady trades/s | Full-convergence trades/s | Maximum backlog | Result |
|---:|---:|---:|---:|---:|---|
| 20260805 | 900.30 | 449.78 | 445.35 | 806 | pass |
| 20260806 | 899.98 | 449.83 | 445.03 | 390 | pass |
| 20260807 | 899.90 | 449.02 | 445.59 | 451 | pass |

Across the three seeds, all 567,000 HTTP orders were accepted without error and
all 283,500 trades converged with equal three-service IDs, exact assets, and empty
queues. Mean same-window completion was 449.54 trades/s and mean full-convergence
throughput was 445.32 trades/s. This establishes a repeatable **short-window**
900 orders/s point; it does not establish long-duration capacity.

## 950 deep diagnostics

Two 950 orders/s runs sampled process CPU, Rabbit ready/unacked counts, PostgreSQL
activity/commit/WAL counters, Hikari pools, GC, and service metrics every five
seconds. The sampler has a material observer cost, so these runs are attribution
evidence rather than replacements for low-observer capacity results.

- R1 passed at 949.94 steady orders/s and 491.50 same-window trades/s.
- R2 accepted all 199,500 orders but failed sustained gates at 430.94 trades/s,
  90.73% of target, with a +32.48 messages/s backlog slope.
- R2 still converged all 99,750 trades with equal IDs and zero final queues.
- System CPU averaged 86-90% and reached 100% in both runs.
- Order command-pool pending peaked at 85 and 91; Wallet pending peaked at 0 and 1.
- R2 Order PostgreSQL produced about 938 MB of WAL versus Wallet's 348 MB, with
  up to seven active Order sessions waiting on `WALInsert`.
- R2 Rabbit peaks were 8,526 messages on `matchEngine.orderConfirmed.queue` and
  1,743 on `wallet.orderSubmitted.queue`; `wallet.tradeExecuted.queue` peaked at
  only 367.
- Wallet settlement transaction mean was 4.88 ms in R1 and 11.28 ms under the
  heavier R2 host contention. No deadlock, DLQ, or persistent Wallet pool wait was
  observed.

The earlier 135-request HTTP failure burst did not reproduce in these two deep
runs. The reproducible failure was completion/backlog pressure, led by Order and
shared-host CPU/WAL contention rather than Wallet settlement.

## 30-minute 900 orders/s soak

The low-observer soak used seed `20260808`, a 60-second warmup, and a 1,800-second
measurement window. It accepted all 1,674,000 HTTP orders at 899.94 orders/s with
zero HTTP failures, but failed the long-duration completion gate:

| Metric | Result |
|---|---:|
| Steady accepted load | 899.81 orders/s |
| Same-window completion | 301.68 trades/s |
| Completion target ratio | 67.04% |
| Expected trades | 837,000 |
| Match / Order / Wallet at 900-second drain timeout | 619,028 / 618,872 / 619,117 |
| Final unacked messages at timeout | 437 |
| Result | invalid; not converged within timeout |

The incomplete final counts are a timeout snapshot, not proof of message loss.
During drain, Rabbit queues were temporarily empty while Order's event outbox still
contained exactly 471,102 `PENDING` and 1,202,898 `SENT` rows. Three minutes later,
450,602 were still pending, only about 114 events/s of drain. The Order relay had
one scheduled invocation active for roughly 1,564 seconds, and Order PostgreSQL
showed six active `DataFileRead` waits while Wallet PostgreSQL was effectively idle.

The long-run bottleneck was therefore the Order event-outbox relay pipeline as its
durable tables grew, including a single synchronous publisher-confirm path and
Order database read/write amplification. This hypothesis was tested in the
follow-up A/B below.

## 15-minute asynchronous relay A/B

The load-test harness now performs the existing database, Rabbit, and Redis reset
once before consumer startup. This removed two setup-only failures in which live
consumers raced `TRUNCATE` or fetched outbox messages left by the preceding run.

The first 15-minute candidate enabled the bounded Order outbox relay with four
in-flight batches. The run did not reach a valid result because 6,142 HTTP requests
failed after host CPU saturation. It nevertheless established two useful facts:

- Order trade application was no longer the long tail: Match-to-Order p95 was
  79.97 ms.
- All 857,858 accepted orders existed in Wallet and both Order and Wallet outboxes
  eventually reached `SENT`. When services stopped, Rabbit retained exactly
  186,592 pending confirmations in each of the Order and Match queues, equal to
  the durable downstream gap. The timeout snapshot was not message loss.

The second candidate kept Order async relay enabled and added Wallet batch
publisher confirms. It accepted all 864,000 requests without HTTP failures, but
failed both throughput and correctness gates:

| Metric | Result |
|---|---:|
| Accepted HTTP orders | 864,000 / 864,000 |
| Accepted throughput | 875.32 orders/s |
| Same-window completion | 253.79 trades/s |
| Completion target ratio | 56.40% |
| Match / expected trades | 432,190 / 432,000 |
| Match / Order / Wallet trade facts | 432,190 / 431,783 / 432,190 |
| Full convergence wait | 1,592.47 seconds; invalid |

The excess Match trades exposed a correctness defect rather than harmless metric
noise. In `amount=1` traffic, 431 order IDs appeared in two different Match trade
facts. Rabbit's ten-minute acknowledgement timeout can redeliver an
`OrderConfirmed` message while the original consumer invocation is still active;
MatchEngine currently has no atomic incoming-order idempotency claim, so the same
incoming order can match twice. Order's matching-state invariant rejected those
contradictory trades. Its batch listener then persisted 451
`FAILED_PERMANENT` inbox rows because one rejected event causes the whole listener
batch to be classified as permanent failure.

Therefore both relay candidates are rejected as defaults. The next correctness
work is an atomic, crash-recoverable MatchEngine `OrderConfirmed` idempotency
boundary plus per-event isolation when an Order trade batch contains one invalid
event. A lower 30-minute capacity knee must wait until those gates pass.

The historical statement was: **that revision reached 900 orders/s across three
three-minute local runs averaging 445 fully converged trades/s, but did not sustain
900 orders/s for 30 minutes.** The later Wallet transaction-boundary correction
invalidates it as a current-code capacity statement.

## OrderConfirmed redelivery correction

The correctness defect from the 15-minute candidate was corrected at both service
boundaries:

- MatchEngine now claims each incoming order atomically inside the existing Redis
  reserve-or-add Lua operation. A completed redelivery returns before changing the
  order book. An interrupted claim is recovered under a per-order lock by comparing
  the visible order and durable matched quantity, so multi-fill orders resume only
  their remaining amount.
- The claim timestamp is refreshed by each reserve-or-add Lua call. This prevents a
  legitimate long multi-fill attempt from being mistaken for a crashed owner without
  adding another Redis round trip.
- Order keeps its fast batch append, but a contradictory trade now triggers
  idempotent per-event isolation. Only the actual invalid event is marked permanent;
  unrelated events in the Rabbit batch continue.

Two rejected implementations are retained as negative evidence. A Redisson watchdog
lock on every incoming order and a separate Redis HGET/HSETNX guard both preserved
correctness but failed the 900 orders/s steady-state gate at 385.74 and 387.37
trades/s respectively, with backlog growth above 100 messages/s. Moving the atomic
claim into reserve-or-add Lua removed those extra claim round trips.

The final fixed-seed 60-second candidate passed:

| Metric | Result |
|---|---:|
| Accepted HTTP orders | 67,500 / 67,500 |
| Steady accepted load | 900.40 orders/s |
| Steady completed throughput | 455.81 trades/s |
| Steady backlog slope | -0.36 messages/s |
| Match / Order / Wallet trade facts | 33,750 / 33,750 / 33,750 |
| Full convergence | 76.79 s; 439.53 trades/s |
| Final queues / DLQ / reservations | 0 / 0 / 0 |
| Sustained-capacity contract | valid |

Compared with the separate-guard R2 candidate, the listener time outside
`tryMatch` fell from approximately 10.65 to 2.51 ms/order and steady completed
throughput improved 17.7%. A real RabbitMQ duplicate injection then replayed one
completed `OrderConfirmed`: the broker consumed it, total Match trades remained
33,750, the target order remained in exactly one trade, and the DLQ stayed empty.

This closes the observed duplicate-redelivery defect for the short-window gate. It
does not retroactively make 900 orders/s a 30-minute sustained claim; the corrected
long-duration capacity knee remains below 900 orders/s.

## Corrected 15-minute reliability run

Run `GLT_20260806_MATCH_LUA_IDEMPOTENCY_900_15M_SEED20260810_R1` exercised the
corrected Lua claim for 60 seconds of warmup plus 900 seconds of shuffled traffic.
The run is a **reliability pass but a sustained-capacity fail**:

| Metric | Result |
|---|---:|
| HTTP accepted | 864,000 / 864,000; zero 429/503/other failures |
| Accepted BUY / SELL | 432,000 / 432,000 |
| Match / Order / Wallet trade facts | 432,000 / 432,000 / 432,000 |
| Three-service trade fingerprint | equal; `a5e4f027...6d40d3` |
| Incoming order IDs used by multiple trades | 0 |
| Final queues / DLQ / reservations / books | 0 / 0 / 0 / 0 |
| Pending Match / Order / Wallet outboxes | 0 / 0 / 0 |
| Steady accepted / completed | 821.08 orders/s / 277.98 trades/s |
| Backlog slope / maximum | +0.6795 messages/s / 46,451 |
| Full convergence | 1,717.39 s; 251.54 trades/s |

The final trade-ID sets and SHA-256 fingerprint were identical across all three
state-owning services. Rabbit queues, DLQ, Redis reservations, order books, and
pending outboxes drained completely. The Order inbox also contained 52 successful
redeliveries with two attempts and no unapplied row. This closes the previously
observed duplicate-trade failure for this 864K-order workload.

The capacity contract failed because the local driver delivered only 91.23% of the
target during the steady window, completion throughput remained below input, and
the backlog exceeded its limit. A focused Gradle suite also overlapped roughly the
first minute, so the throughput numbers are host-contaminated and must not be used
as a clean capacity comparison. The correctness result remains usable because the
run ultimately reached exact facts, balances, fingerprints, and empty durable and
broker state. This run validates the service-owned durable facts and final
convergence. The downstream completion-marker projection was not part of this
contract and has since been retired.

## Deterministic crash-recovery gates

`IncomingOrderCrashRecoveryPostgresRedisIT` now runs against real Testcontainers
PostgreSQL and Redis and covers the three state boundaries around a match:

- crash after Redis reserves the resting order but before the trade commit;
- crash after the trade and outbox commit but before Redis reservation cleanup;
- crash after matching completes but before the incoming-order completed bitmap bit is written.

Each case forces stale recovery, replays the same `OrderConfirmed` event twice, and
asserts quantity conservation, one trade per resting order, unique trade facts,
completed cleanup tasks, a completed incoming-order state, and zero active
reservations. All three cases and the complete MatchEngine test suite pass. These
are deterministic state-equivalent crash tests; a real Rabbit listener/JVM kill is
covered by the following runtime test.

## Real MatchEngine JVM kill and broker redelivery

Run `GLT_20260806_MATCH_JVM_KILL_900_60S_SEED20260811_R1` sent shuffled mixed
HTTP traffic while MatchEngine had in-flight Rabbit deliveries. PID 13196 received
SIGKILL with 28 messages still unacknowledged, and the ready backlog reached 42,279.
A new MatchEngine process started with the same profile and drained the redelivery.

| Metric | Result |
|---|---:|
| HTTP accepted / failures | 58,500 / 0 |
| Expected / Match / Order / Wallet trades | 29,250 / 29,250 / 29,250 / 29,250 |
| Duplicate order use / maximum use | 0 / 1 |
| Match outbox / cleanup | 29,250 SENT / 29,250 COMPLETED |
| Final queues / DLQ / reservations / processing claims | 0 |
| Full convergence | 217.89 s |

The three trade fingerprints were identical. This closes the real listener/JVM
termination and Rabbit redelivery gate for MatchEngine.

## Current saturation and long-duration boundary

The current code was compared with the earlier `1000 orders/s x 180s` runs using
the same seed and core-capacity profile. This is a saturation comparison, not a
sustained claim:

| Run | Steady accepted | Steady completed | Backlog max | Result |
|---|---:|---:|---:|---|
| Previous R1 | 997.03 orders/s | 442.28 trades/s | 8,182 | saturation baseline |
| Previous R2 | 984.95 orders/s | 443.97 trades/s | 3,166 | saturation baseline |
| Current | 1000.00 orders/s | 497.48 trades/s | 19,062 | correctness pass; sustained fail |

The current saturation throughput improved 12.05-12.48%. All 105,000 trades
converged across Match, Order, and Wallet with no duplicate order use. The strict
sustained gate still rejected 1000 orders/s because backlog growth exceeded the
limit.

Two 15-minute high-utilization soaks then searched downward:

| Target | Steady completed | Backlog slope / max | Capacity verdict |
|---:|---:|---:|---|
| 800 orders/s | 377.32 trades/s | +18.90/s / 31,748 | fail |
| 700 orders/s R1 | 343.95 trades/s | -0.36/s / 9,004 | backend gates pass; HTTP-invalid |
| 700 orders/s R2 | 343.05 trades/s | +1.05/s / 6,916 | sustained pass |

The 800 run accepted all 768,000 requests and eventually converged exactly 384,000
trades, but failed completion, slope, and backlog limits. The 700 run's service-side
metrics passed, but eight HTTP client requests timed out during one local stall, so
it is not a publishable sustained sample. Six timeout responses were ambiguous:
the server had committed them. Durable input was 335,998 BUY and 336,000 SELL,
producing 335,998 identical three-service trades and two legitimate open SELL
orders with corresponding Wallet locks. No record or asset was lost.

The clean R2 repeat accepted `699.14 orders/s` and completed `343.05 trades/s`
during the 15-minute window. Its completion target ratio was 98.01%, backlog slope
was below the `7/s` limit, maximum backlog stayed below 21,000, and all 336,000
trades converged across the three services. All 672,000 order IDs were used at most
once; final queues, DLQ, order books, reservations, processing claims, and pending
outboxes were zero. This establishes a single-seed local sustained point at 700
orders/s. Additional clean seeds are still required before reporting a range or
production SLA.

The steady-state runner now treats a timeout as an unknown outcome. It records the
event-store position before traffic, waits for durable BUY/SELL counts to stabilize,
uses their minimum as the pairable trade count, and validates any side imbalance
against the final order book and Wallet locks. HTTP failures still invalidate the
capacity sample, but the runner completes convergence and emits JSON instead of
discarding the result. A 2,000-order full HTTP smoke passed the normal zero-timeout
path. The timeout branch was not exercised by that smoke and still requires a targeted
test before it can be called end-to-end validated.

## 2026-08-06 transaction-boundary regression smoke

After restoring the Wallet per-event transaction and deterministic wallet lock order,
`GLT_20260806_WALLET_TX_LOCK_MIXED_SMOKE_R1` ran shuffled mixed BUY/SELL traffic at
`700 total orders/s` for 5 seconds of warmup and 15 seconds of measurement:

| Metric | Result |
|---|---:|
| HTTP accepted | `14000 / 14000` |
| Durable BUY / SELL orders | `7000 / 7000` |
| Match / Order / Wallet trades | `7000 / 7000 / 7000` |
| Measurement-window completion | `439.55 trades/s` |
| Full convergence | `328.57 trades/s` over `21.3047s` |
| Maximum / final queue backlog | `4037 / 0` |
| HTTP failures / DLQ | `0 / 0` |

Trade-ID digests were identical, final assets were exact, and order books,
reservations, queues, and DLQ drained to zero. Service logs contained no settlement
deadlock or listener exception. This is a short correctness regression test at a
previously sustainable offered rate, not a new sustained-capacity or maximum-TPS
claim. The machine-readable result remains in the local load-test report directory.

## 2026-08-06 compact MatchEngine idempotency smoke

`GLT_20260806_MATCH_BITMAP_MIXED_900_R1` validated the sharded completed-order bitmap
under shuffled mixed traffic:

| Metric | Result |
|---|---:|
| Offered / accepted HTTP rate | `900 / 898.35 orders/s` |
| HTTP accepted | `18000 / 18000` |
| Match / Order / Wallet trades | `9000 / 9000 / 9000` |
| Measurement-window completion | `382.56 trades/s` |
| Completion target ratio | `85.01%` |
| Full convergence | `397.16 trades/s` over `22.6607s` |
| Completed bitmap count / Redis memory | `18000 / 3160 bytes` |
| Remaining processing-state keys | `0` |

All correctness and drain gates passed, but the 90% same-window completion gate failed.
This run therefore proves compact idempotency and eventual convergence at 900 orders/s;
it does not establish 900 orders/s as the current sustainable rate.

Two 500-users-per-side controls then separated wallet-row concentration from the
idempotency change. R2 reached `405.96 trades/s` and a `90.21%` completion ratio, but
was generated before steady-state backlog gating was aligned with the staircase's
minimum meaningful-growth rule. R3 used the corrected gate and reached only
`327.86 trades/s` / `72.86%`, so 900 orders/s is not repeatably sustainable.

The corrected lower-bound run `GLT_20260806_MATCH_BITMAP_MIXED_700_USERS500_R1`
passed every gate:

| Metric | Result |
|---|---:|
| Accepted HTTP rate | `699.31 orders/s` |
| Measurement-window completion | `350.09 trades/s` |
| Completion target ratio | `100.03%` |
| Maximum / final queue backlog | `225 / 0` |
| Match / Order / Wallet trades | `7000 / 7000 / 7000` |
| Completed bitmap count / Redis memory | `14000 / 1880 bytes` |
| Remaining processing-state keys | `0` |

This is a short current-code reliability and capacity-lower-bound regression, not a
long-duration SLA.

## 2026-08-06 mixed 800/900 deep diagnostics

The deep runner now resets `pg_stat_statements`, database counters, and shared WAL
counters after service startup. It also records the effective PostgreSQL durability
settings. These runs used `synchronous_commit=off`, `fsync=on`, and
`track_wal_io_timing=off`; WAL byte deltas are valid, but WAL write/sync latency is
not available and the results are core-capacity diagnostics rather than production
durability claims.

| Run | Accepted orders/s | Steady trades/s | Completion ratio | Backlog slope | Result |
|---|---:|---:|---:|---:|---|
| 800, seed `202608061` | 799.59 | 383.83 | 95.96% | +5.13/s | pass |
| 900, seed `202608062` | 899.50 | 470.34 | 104.52% | -1.00/s | pass |
| 900, seed `202608063` | 899.85 | 455.56 | 101.23% | -1.04/s | pass |

The completion ratios above 100% mean that the measurement window discharged a
small warmup backlog; they do not mean more trades were created than the pairable
BUY/SELL input. Both 900 runs accepted 31,500 HTTP orders and converged to 15,750
identical Match, Order, and Wallet trades with exact assets and empty final queues.
They show that 900 is attainable for a 30-second window, but do not erase the
same-code 15-second failure or the historical 30-minute soak failure.

The first diagnostics pass exposed a timestamp defect: Order
`order_trade_applications.applied_at` stores the source event time, not the Order
database insertion time. Order now keeps a database-generated `inserted_at`, and
the integrated lag report uses that value without changing the existing event-time
semantics. The corrected 900 run measured:

| Stage | p50 | p95 | p99 | max |
|---|---:|---:|---:|---:|
| Match persisted -> Order inserted | 108.12 ms | 429.21 ms | 873.32 ms | 1,137.42 ms |
| Match persisted -> Wallet inserted | 81.45 ms | 410.38 ms | 818.23 ms | 1,030.68 ms |
| Durable convergence | 109.11 ms | 441.98 ms | 873.32 ms | 1,137.42 ms |
| Order/Wallet insertion skew | 26.62 ms | 68.07 ms | 107.69 ms | 196.41 ms |

Order and Wallet lag are therefore close, while their p95 skew is only 68 ms. The
dominant tail is in their shared path after Match persistence, principally the Match
trade outbox scheduling/publish-confirm path, rather than Wallet settlement SQL.
The Match relay processed 15,750 events in 218 batches; confirm wall time totaled
5.59 seconds and reached 357.52 ms for one batch. The corrected repeat observed no
Hikari pending connections, no failed publishes, no DLQ messages, and Rabbit queue
peaks below 100 messages. System CPU still reached 95-100%, confirming substantial
same-host interference.

The corrected run generated about 122.5 MB of Order WAL, 48.2 MB of Wallet WAL, and
40.7 MB of Match WAL. Order remains the largest database writer, but the immediate
cross-service completion tail should be investigated with a controlled Match outbox
relay A/B before changing Order or Wallet business logic.

## Evidence

- `build/load-test-reports/http-matched-staircase-GLT_20260805_HTTP_MATCHED_ROBUST_900_1000_R1-result.json`
- `build/load-test-reports/http-matched-staircase-GLT_20260805_HTTP_MATCHED_ROBUST_900_1000_R2-result.json`
- `build/load-test-reports/http-matched-staircase-GLT_20260805_HTTP_MATCHED_ROBUST_900_1000_R3-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_WALLET_AUTOCOMMIT_1000_R1-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_WALLET_AUTOCOMMIT_LOWOBS_1000_R2-result.json`
- [`2026-08-05-http-matched-steady-900-r1.json`](results/2026-08-05-http-matched-steady-900-r1.json)
- [`2026-08-05-http-matched-steady-900-r2.json`](results/2026-08-05-http-matched-steady-900-r2.json)
- [`2026-08-05-http-matched-steady-900-r3.json`](results/2026-08-05-http-matched-steady-900-r3.json)
- [`2026-08-05-http-matched-steady-950-r1.json`](results/2026-08-05-http-matched-steady-950-r1.json)
- [`2026-08-05-http-matched-steady-950-r2-failed-samples.csv`](results/2026-08-05-http-matched-steady-950-r2-failed-samples.csv)
- [`2026-08-05-http-matched-steady-900-seed-20260806.json`](results/2026-08-05-http-matched-steady-900-seed-20260806.json)
- [`2026-08-05-http-matched-steady-900-seed-20260807.json`](results/2026-08-05-http-matched-steady-900-seed-20260807.json)
- [`2026-08-05-http-matched-deep-950-r1.json`](results/2026-08-05-http-matched-deep-950-r1.json)
- [`2026-08-05-http-matched-deep-950-r2.json`](results/2026-08-05-http-matched-deep-950-r2.json)
- [`2026-08-05-http-matched-deep-950-r1-hot-window.md`](results/2026-08-05-http-matched-deep-950-r1-hot-window.md)
- [`2026-08-05-http-matched-deep-950-r2-hot-window.md`](results/2026-08-05-http-matched-deep-950-r2-hot-window.md)
- [`2026-08-05-http-matched-soak-900-30m-seed-20260808.json`](results/2026-08-05-http-matched-soak-900-30m-seed-20260808.json)
- [`2026-08-05-http-matched-soak-900-30m-seed-20260808-samples.csv`](results/2026-08-05-http-matched-soak-900-30m-seed-20260808-samples.csv)
- [`2026-08-05-http-matched-order-async4-900-15m-failed-samples.csv`](results/2026-08-05-http-matched-order-async4-900-15m-failed-samples.csv)
- [`2026-08-05-http-matched-order-async4-900-15m-stage-lag.md`](results/2026-08-05-http-matched-order-async4-900-15m-stage-lag.md)
- [`2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m.json`](results/2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m.json)
- [`2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-samples.csv`](results/2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-samples.csv)
- [`2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-stage-lag.md`](results/2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-stage-lag.md)
- [`2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-inbox.txt`](results/2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-inbox.txt)
- [`2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-correctness.md`](results/2026-08-05-http-matched-order-async4-wallet-batch-confirm-900-15m-correctness.md)
- `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_INCOMING_IDEMPOTENCY_900_60S_R1-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_INCOMING_IDEMPOTENCY_HSETNX_900_60S_R2-result.json`
- [`2026-08-06-http-matched-lua-idempotency-900-60s.json`](results/2026-08-06-http-matched-lua-idempotency-900-60s.json)
- `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_LUA_IDEMPOTENCY_900_15M_SEED20260810_R1-result.json`
- `eap-matchEngine/src/test/java/com/eap/eap_matchengine/application/IncomingOrderCrashRecoveryPostgresRedisIT.java`
- `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_JVM_KILL_900_60S_SEED20260811_R1-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260806_CURRENT_SATURATION_1000_180S_SEED20260805_R1-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260806_CURRENT_SOAK_800_15M_SEED20260812_R1-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260806_CURRENT_SOAK_700_15M_SEED20260813_R1-samples.csv`
- `build/load-test-reports/http-matched-steady-GLT_20260806_CURRENT_SOAK_700_15M_SEED20260815_R2-result.json`
- `build/load-test-reports/http-matched-steady-GLT_20260806_DURABLE_OUTCOME_HARNESS_SMOKE_R1-result.json`
- [`2026-08-06-http-matched-deep-800-r1.json`](results/2026-08-06-http-matched-deep-800-r1.json)
- [`2026-08-06-http-matched-deep-900-r2.json`](results/2026-08-06-http-matched-deep-900-r2.json)
- [`2026-08-06-http-matched-deep-900-r2-stage-lag.md`](results/2026-08-06-http-matched-deep-900-r2-stage-lag.md)
- [`2026-08-06-http-matched-deep-900-r2-hot-window.md`](results/2026-08-06-http-matched-deep-900-r2-hot-window.md)
