# EAP Performance Report

This report is the canonical current EAP capacity summary. The append-only experiment history is frozen in [archive/performance/2026-06-global-loadtest-2000-tps.md](archive/performance/2026-06-global-loadtest-2000-tps.md).

## Throughput Definitions

EAP reports multiple throughput numbers because they answer different questions.

The current benchmark suite is split into contracts:

- `order-admission-chain` (implemented): `Order API -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission`.
- `matched-trade-completion-chain` (implemented): seeded confirmed orders enter MatchEngine and the benchmark waits for MatchEngine, Order, and Wallet durable trade completion.
- `http-matched-trade-completion-chain` (implemented): BUY and SELL use the public HTTP path, followed by reservation, matching, settlement, three-service trade-ID convergence, and queue drain.
- `http-matched-steady-state-chain` (implemented): the same public lifecycle under a warmup plus fixed-rate measurement window with backlog trend sampling.
- `http-matched-staircase-chain` (implemented): progressively increases full-lifecycle order load to locate the first unsustainable stage.
- `rabbitmq-publish-only` (implemented diagnostic): RabbitMQ broker-confirmed input ceiling with service processing removed.

| Metric | Meaning | Can It Be Called Completed Business TPS? |
| --- | --- | --- |
| accepted orders/s | order requests accepted or order confirmations published by the load generator | No |
| input attempted orders/s | client-side BUY publish attempts during the scheduled send window | No |
| broker-confirmed input orders/s | BUY messages acknowledged by RabbitMQ publisher confirms | No, but required before capacity comparisons |
| core matching ops/s | isolated Redis/Lua matching throughput | No |
| trade execution reach TPS | MatchEngine persisted `TradeExecuted` facts | No |
| wallet settlement reach TPS | Wallet settlement records reached target count | Partial |
| orderbook admission TPS | resting SELL confirmations admitted into the Redis order book | No, this is order-book admission, not completed trades |
| business completed trade TPS | MatchEngine, Order, and Wallet durable trade facts reached the same `trade_id` set and measured queues drained | Yes |
| blended market flow TPS | total SELL+BUY order confirmations processed across the full two-phase benchmark window | No, useful for workload capacity but it mixes order confirmations and completed trades |

The project intentionally does not report accepted order throughput as completed trading throughput.

## Current Worktree Diagnostic - 2026-08-07

The latest canonical shuffled mixed HTTP regression retained the current short-window lower-bound class without increasing the public capacity claim:

- `700.00 offered / 699.98 accepted orders/s`;
- `346.12 same-window trades/s`;
- `320.47 full-lifecycle trades/s`;
- `17500/17500` HTTP requests accepted and `8750/8750/8750` MatchEngine, Order, and Wallet durable trades;
- exact assets, no remaining orders or reservations, and final queue/DLQ backlog `0`.

A deep `700..1300 orders/s` staircase passed 700 and failed the 800 stage's completion-rate gate. All `37500` accepted orders still converged to `18750` exact three-service trades. Diagnostics showed MatchEngine's Spring scheduler running with one thread while reservation cleanup reached a `9.380s` maximum batch duration; Match-to-Order and Match-to-Wallet p95 lag rose together to `7.382s` and `7.354s`. This is a code-level scheduler-contention hypothesis plus same-host resource contention, not evidence of data loss.

The controlled follow-up isolated trade-outbox polling from reservation maintenance. With the same seed and deep settings, the 800 stage improved from `167.93` to `383.45 trades/s`, maximum backlog fell from `4090` to `246`, and all `18750` trades passed the final correctness gate. A wider repeat later passed 900 but failed correctness at final convergence because one BUY order was matched twice; that entire run, including its 900 stage, is invalid as capacity evidence. MatchEngine reservation recovery had used a cross-process timestamp to infer the durable trade and could release an already consumed order. Reservations now carry their exact `tradeId`, and cleanup/recovery Lua operations reject a different reservation generation.

After the correctness fix, a light `600..800 orders/s` staircase passed 600 and 700, then failed the 800 completion/backlog gate. All `52500` orders still converged into `26250` identical three-service trades with exact assets and zero final queue, DLQ, order-book, or reservation debt. Scheduler isolation is adopted; 800 and 900 are not promoted. At that point the short-window public mixed-flow lower-bound class remained 700 orders/s; the newer sustained recheck below adds a stricter boundary.

Because the repositories contained uncommitted changes and deep monitoring affects a saturated single host, these runs are current-worktree diagnostics rather than a release-pinned capacity record. See [the 2026-08-07 diagnostic report](benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md).

## Release-Pinned 700 Sustained Recheck - 2026-08-11

The next release-pinned shuffled mixed-HTTP repeat used a `60s` warmup, `900s`
measurement window, target `700 orders/s`, and seed `20260811`. All `672000` HTTP
orders were accepted and converged into `336000` identical MatchEngine, Order, and
Wallet trades with exact assets and zero final queue, DLQ, order-book, or
reservation debt. Reliability passed, but sustained capacity failed:

- `699.69 accepted orders/s` and `330.90 completed trades/s` in the steady window;
- `94.54%` completion target ratio;
- `+27.5602/s` backlog slope and `33751` maximum backlog;
- `311.78 trades/s` across full convergence.

A same-seed follow-up verified a MatchEngine ownership fix that prevents the
reservation reconciler and cleanup worker from processing the same normal cleanup.
Reconciler completions of worker-owned work fell from `22521` to `0`, `44397`
entries were explicitly deferred, redundant cleanup warnings fell from `22521` to
`0`, and focused, crash-window, and full MatchEngine tests passed. The change is
adopted for correctness and recovery ownership.

The follow-up run is not a clean throughput comparison. It encountered `477`
Wallet RabbitMQ publisher-confirm batch timeouts while the shared host was near
CPU saturation. It still converged exactly, but failed the sustained gate at
`691.28 accepted orders/s`, `303.22 completed trades/s`, a `+31.5123/s` backlog
slope, and `28004` maximum backlog. No TPS improvement or regression is attributed
to the ownership change from this run.

The short-window mixed-HTTP lower-bound class remains about `700 accepted
orders/s`, but the current release-pinned revision does not have a repeatable
15-minute sustained 700 result. See the
[release-pinned 700 and recovery ownership report](benchmarks/2026-08-11-release-pinned-700-and-recovery-ownership.md).

## Current Release-Pinned Sustained Lower Bound - 2026-08-13

The downward search established a passing same-host point at `600 orders/s` with
the same `60s` warmup, `900s` measurement window, and seed `20260811`:

- all `576000` HTTP orders accepted with zero `429`, `503`, or other failures;
- `597.12 accepted orders/s` and `292.74 completed trades/s` in the steady window;
- `97.58%` completion target ratio;
- `+3.6169/s` backlog slope and `8918` maximum backlog, both within their gates;
- `288000` identical MatchEngine, Order, and Wallet trade IDs, exact assets, and zero final queue, DLQ, order-book, or reservation debt;
- `288.19 full-lifecycle trades/s` across `999.3486s` full convergence.

An earlier R1 attempt is rejected rather than averaged into this result. The host
stopped scheduling for about `7m29s`, causing HTTP and RabbitMQ management
timeouts. Durable facts still reconciled correctly, but the interruption invalidated
capacity measurement and exposed a `Long.MAX_VALUE` queue-backlog sentinel bug in
the harness. `eap-order` `c95381c` corrected the diagnostic calculation without
relaxing the metrics-failure invalidation gate.

The current public boundary is therefore: `600 accepted orders/s` class for one
release-pinned 15-minute sustained run, plus about `700 accepted orders/s` as a
separate short-window class. A second 600 seed was attempted but is inconclusive:
RabbitMQ remained under a memory alarm, offered load collapsed, and an Order
PostgreSQL server process exited before final correctness could run. It does not
count as either a capacity pass or a capacity failure. Another clean seed is still
required before stepping to 650. See the
[release-pinned 600 sustained report](benchmarks/2026-08-13-release-pinned-600-sustained.md).

## Order-Admission Chain Semantics

`order-admission-chain` is the front-half benchmark. It sends one-sided HTTP limit orders to the Order API and counts the workflow as admitted only after Order has persisted the submission request, Wallet has reserved assets and emitted confirmation, Order has persisted `OrderAssetReservationConfirmedV1`, MatchEngine has admitted the order into the Redis orderbook, and measured RabbitMQ queues have drained.

This benchmark does not execute trades. Its TPS must not be compared directly with `business completed trade TPS`.

### First Order-Admission Diagnostic

Run: `GLT_20260728_ORDER_ADMISSION_10K_R1`, one 10k SELL-only local diagnostic sample.

| Metric | Result |
| --- | ---: |
| target HTTP order rate | `2000 orders/s` |
| HTTP accepted | `10000/10000` |
| HTTP accepted TPS | `1333.68 orders/s` |
| HTTP p95 / p99 | `249.46 ms / 437.53 ms` |
| Order `OrderSubmissionRequestedV1` rows | `10000` |
| Order `OrderAssetReservationConfirmedV1` rows | `10000` |
| MatchEngine orderbook admissions | `10000` |
| order-admission gate window | `24.79s` |
| business order-admission TPS | `403.36 orders/s` |
| final measured queue backlog | `0` |
| queue metrics read failures | `0` |

Interpretation:

- The front-half order path is now measurable as its own contract.
- This run was valid for correctness, but the HTTP load generator only reached `1333.68/s` against a `2000/s` target.
- The first bottleneck to split is the admission chain itself: Order API/event-store/outbox, Wallet reservation/outbox relay, Order confirmation consumer, and MatchEngine Redis admission.

### Order-Admission Split Diagnostic

Run: `GLT_20260728_ORDER_ADMISSION_SPLIT_10K_R1`, one 10k SELL-only local diagnostic sample with stage-reached timings.

| Stage | Reached At |
| --- | ---: |
| HTTP accepted | `7.31s` send window |
| Order `OrderSubmissionRequestedV1` persisted | `7.57s` |
| Order `OrderSubmittedEvent` outbox SENT | `23.43s` |
| Wallet order-submission claim | `23.47s` |
| Order `OrderAssetReservationConfirmedV1` persisted | `23.50s` |
| MatchEngine Redis orderbook admission | `23.50s` |
| final measured queue drain | `26.81s` |

Interpretation:

- Order API persistence completed shortly after the HTTP send window.
- The dominant delay was between Order submission persistence and Order outbox SENT convergence.
- Wallet reservation, Wallet confirmed publication, Order confirmation consumption, and MatchEngine orderbook admission converged almost immediately after Order outbox publication caught up.
- The next tuning target is Order outbox relay confirm/publication strategy, not Wallet settlement or MatchEngine Redis admission.

Order outbox confirm strategy A/B:

| Run | Order outbox relay mode | Order outbox SENT reached | Orderbook admitted | Gate elapsed | Business order-admission TPS |
| --- | --- | ---: | ---: | ---: | ---: |
| `GLT_20260728_ORDER_ADMISSION_SPLIT_10K_R1` | per-message correlated confirm wait, batch `500` | `23.43s` | `23.50s` | `26.81s` | `372.93/s` |
| `GLT_20260728_ORDER_ADMISSION_QUEUE_ATTR_10K_R1` | batch confirm, batch `500`, clean reset | `17.44s` | `18.20s` (`549.42/s`) | `21.38s` | `467.68/s` |
| `GLT_20260728_ORDER_ADMISSION_OPT_DEFAULT_10K_R1` | batch confirm, batch `1000`, clean reset | `16.50s` | `16.57s` (`603.39/s`) | `21.39s` | `467.54/s` |

Decision:

- Load-test Order outbox relay now defaults to batch publisher confirms and batch size `1000`.
- Admission benchmark reset now truncates Order/Wallet test tables and purges RabbitMQ queues after truncation, preventing old outbox rows from being relayed into the next run.
- The next bottleneck is no longer only OrderSubmitted relay. The orderbook-admission stage is now around the `600/s` class, while the full drained gate remains around the `460/s` class because confirmed-event queues still have late unacked tails.
- Latest tail sample: `wallet.orderSubmitted.queue(ready=0,unacked=20)`, `order.orderConfirmed.queue(ready=0,unacked=350)`, `matchEngine.orderConfirmed.queue(ready=0,unacked=87)` shortly before final drain.

## Full HTTP Matched Lifecycle

The full HTTP contract sends both BUY and SELL orders through the user-facing Order API and does not count a trade as complete until:

- MatchEngine has persisted the durable `TradeExecuted` fact;
- Order and Wallet have persisted the same `trade_id`;
- buyer and seller asset balances match the expected settlement;
- all BUY/SELL orderbook entries and active match reservations are gone;
- all measured RabbitMQ queues and the Order DLQ have drained.

The load driver reports request scheduling TPS, accepted-response TPS, response drain tail, and completed trade TPS separately. Its throttle uses fixed open-loop deadlines, so one late scheduler wake-up does not shift every later request deadline.

### 100K Full HTTP Phase Validation

Run: `GLT_20260803_HTTP_MATCHED_TRADE_COMPLETION_100K_R2`.

This single-host run sent `100000` SELL orders through HTTP and waited for admission before sending `100000` BUY orders through the same public path. Both phases were configured for `1000 HTTP orders/s`. The run did not start from seeded confirmed orders.

| Metric | Result |
| --- | ---: |
| SELL / BUY HTTP accepted | `100000 / 100000` |
| SELL / BUY accepted TPS | `999.95 / 999.84 orders/s` |
| SELL HTTP p95 / p99 | `16.78 ms / 56.03 ms` |
| BUY HTTP p95 / p99 | `58.54 ms / 107.91 ms` |
| BUY-triggered completion | `707.43 trades/s` over `141.3566s` |
| Full sequential lifecycle | `410.16 trades/s` over `243.8083s` |
| Full-lifecycle order convergence | `820.32 orders/s` |
| Match / Order / Wallet trade rows | `100000 / 100000 / 100000` |
| Three-service trade-ID equality | `true` |
| Final queue / DLQ / books / reservations / locks | `0` |

Independent post-run database checks found `100000` rows and `100000` distinct trade IDs in every service-owned trade table. Wallet aggregate locked amount and currency were both zero, and a separate RabbitMQ query found no ready or unacked messages.

Interpretation:

- The strongest current phase-completion evidence is `200000/200000` accepted HTTP orders converging into `100000/100000` durable trades with exact final state.
- `707.43 trades/s` starts when BUY traffic begins with SELL inventory already admitted. It is not the full two-phase lifecycle rate.
- `410.16 trades/s` includes SELL HTTP admission, BUY HTTP processing, durable convergence, and final drain.
- This result is one 100K run, not a repeat median or a 30-minute steady-state SLA.
- The sequential per-phase `1000 orders/s` contract is different from the staircase's mixed BUY/SELL `1000 total orders/s` contract.

The complete evidence record is in [docs/benchmarks/2026-08-03-full-http-100k.md](benchmarks/2026-08-03-full-http-100k.md).

The 100K run used benchmark schema v1, which repeatedly queried exact trade-ID sets during drain and included that observer cost in the completion window. Its `100000/100000` correctness evidence remains valid, but its throughput is a conservative historical value. Schema v2 freezes business completion before running exact set verification.

### 2026-08-04 Schema-v2 100K Validation

Run: `GLT_20260804_HTTP_MATCHED_SCHEMA_V2_STABLE_LOCK_C8_100K_R1`.

This schema-v2 run exercised that revision's Wallet bounded-retry/DLQ path and stable batch-settlement wallet locking. It accepted `100000` SELL plus `100000` BUY HTTP orders and converged to `100000` identical Match, Order, and Wallet trade IDs with exact assets and zero final queue, DLQ, orderbook, reservation, or locked balance.

| Metric | Result |
| --- | ---: |
| SELL / BUY accepted rate | `999.90 / 991.35 orders/s` |
| Completion after SELL inventory was ready | `613.33 trades/s` over `163.0433s` |
| Full sequential lifecycle | `378.86 trades/s` over `263.9527s` |
| Full-lifecycle order convergence | `757.71 orders/s` |
| Peak / final queue backlog | `3592 / 0` |
| Match-to-Order p95 | `25.494ms` |
| Match-to-Wallet p95 | `20.534s` |
| Exact post-completion verification | `5.7601s`, excluded from timing |

This is strong high-volume correctness evidence for the tested revision, not a new throughput record or a current-code validation. Its `613.33 trades/s` completion rate is below the historical schema-v1 100K result (`707.43/s`) and the 30K best run (`922.38/s`). A repeat set is required before attributing the difference; the integrated lag pointed to the Wallet settlement/listener transaction tail rather than Match-to-Order persistence. The published artifact is [`2026-08-04-full-http-100k-schema-v2-result.json`](benchmarks/results/2026-08-04-full-http-100k-schema-v2-result.json).

### 30K Schema-v2 Cleanup Optimization

The latest controlled full-HTTP runs use `30000` SELL plus `30000` BUY requests at `1300 orders/s` per sequential phase. MatchEngine reservation cleanup remains durable and retryable, but successful cleanup tasks are now marked `COMPLETED` once per claimed batch instead of one JDBC update per trade.

| Run | BUY accepted | BUY-triggered completion | Full lifecycle | Order convergence | Max backlog | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| baseline `...BASELINE_1300_30K_R2` | `1299.38/s` | `664.26 trades/s` | `434.79 trades/s` | `869.58 orders/s` | `14110` | valid |
| cleanup batch R1 | `1296.43/s` | `842.04 trades/s` | `505.10 trades/s` | `1010.21 orders/s` | `10854` | valid |
| cleanup batch + requeue R3 | `1298.26/s` | `922.38 trades/s` | `530.43 trades/s` | `1060.85 orders/s` | `6261` | valid |

Across the two valid optimized runs, BUY-triggered completion averaged `882.21 trades/s`, `32.8%` above the clean baseline. The equivalent full-lifecycle order-convergence average was `1035.53 orders/s`. Post-run durable timestamp windows independently measured:

| Durable stage | Optimized R1 | Optimized R3 |
| --- | ---: | ---: |
| Match trade persistence | `1056.03/s` | `1158.06/s` |
| Order trade application | `1054.16/s` | `1155.39/s` |
| Wallet settlement | `1041.92/s` | `1154.33/s` |

In R3, Match-to-Wallet settlement p95 fell to `4.478s`, compared with `13.624s` in the clean baseline. The cleanup completion SQL fell from `30000` per-row updates to roughly `32` batch statements in R1 and R3. All valid runs accepted every HTTP request and ended with identical 30K trade-ID sets, exact assets, empty books/reservations, and zero queue/DLQ backlog.

### Wallet Code-vs-Host Attribution

A Wallet-only JFR recording was captured around a correctness-valid 10K full-HTTP run. Deep diagnostics and profiling reduced that run to `564.85 BUY-triggered trades/s`, so it is attribution evidence rather than a replacement capacity result. Machine CPU averaged `86.14%` and reached `100%`; no reservation or settlement application method dominated the `148` Wallet execution samples.

For 20K Wallet reservations in the profiled run, PostgreSQL executed the reservation CTE in `35.978s` cumulative (`1.799ms` mean). The application observed `247.399s` inside the JDBC CTE call and `477.290s` for the complete Spring transaction. The after-body/commit-return segment alone consumed `204.370s`; non-CTE transaction-body work was only `2.422s`. This rejects JSON construction and raw CTE execution as the primary full-chain cost.

The production-shaped reservation and settlement CTEs were then run concurrently against the same 500 buyer and 500 seller hot rows, retaining one commit per operation and a combined 40 workers:

| Run | Reservation TPS | Settlement TPS | Mixed trade cycles/s | Combined DB ops/s | Failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| TPS-171 R1 | `7086.35` | `5307.81` | `5307.62` | `10615.25` | `0` |
| TPS-171 R2 | `7417.90` | `5530.39` | `5530.29` | `11060.59` | `0` |

The two-run mixed SQL floor is about `5.75x` the `922.38 trades/s` sequential upper-bound diagnostic. Concurrent Wallet SQL is therefore not the current ceiling. The remaining gap is in integrated Spring transaction/commit, Rabbit listener and acknowledgement, outbox, cross-service work, and same-host scheduling. A code optimization still needs to reduce those boundaries under the full correctness-gated mixed contract; raising connection or consumer counts is not supported by this evidence.

A follow-up grouped two or five Wallet order reservations into one Spring transaction to amortize commit return. Its first 10K batch-5 attempt produced repeated cross-path Wallet deadlocks. Aligning Java/PostgreSQL UUID ordering and pre-locking settlement wallets eliminated deadlocks, but did not improve throughput: batch 5 completed at `779.98 trades/s`, batch 2 at `677.70 trades/s`, and the contemporaneous restored single-transaction control at `816.15 trades/s`. Every completed run passed exact trade-ID, asset, reservation, and queue-drain gates. The grouped candidate and settlement pre-lock were therefore reverted; longer multi-user lock ownership outweighed commit amortization.

One repeat was invalid after the host reported Hikari scheduler starvation/clock leaps up to `6m16s`. It exposed a Wallet batch recovery gap: exhausted listener retries could return control and ACK an uncommitted batch. A temporary immediate-requeue recoverer prevented that loss but could cycle a poison batch forever and bypass the configured DLQ. The current listener uses bounded retries followed by `AmqpRejectAndDontRequeueException`; a real-broker integration test verifies that the exhausted message reaches the configured DLQ. The invalid repeat is excluded from throughput calculations, and this post-run failure-path hardening does not change the published TPS169 measurement.

A subsequent 30K control run exposed a separate batch-settlement deadlock: concurrent batches locked overlapping buyer/seller wallets in different orders. Bounded retry correctly rejected `377` exhausted messages to the DLQ, making that run invalid instead of silently losing work. Wallet settlement now materializes all involved wallet IDs and locks them in stable user-ID order before applying buyer and seller updates. A PostgreSQL concurrency integration test reproduces reversed buyer/seller roles; after the fix, two 30K controls and the schema-v2 100K run completed with no deadlock, exact assets and trade IDs, and zero final queue/DLQ backlog.

Changing Wallet settlement consumer concurrency from `12` to `8` produced only a small same-host improvement: the two C8 30K controls averaged `822.09 trades/s` after SELL inventory was ready and `496.93 trades/s` across both HTTP phases, versus `807.06` and `491.51 trades/s` in the C12 control. Average peak backlog fell from `15303` to `13614`. C8 is retained as a lower-contention load-test default, not presented as a capacity breakthrough.

### Balanced Mixed HTTP Staircase

The canonical capacity workload now creates equal BUY and SELL populations and shuffles their HTTP arrival order with a recorded seed. It no longer submits strict `SELL, BUY` pairs.

Runs `GLT_20260804_HTTP_MATCHED_SHUFFLED_STAIRCASE_CORE_R1` and `...PRODEQ_R4` used seed `20260804`, `5s` warm-up, and `15s` measurement per stage:

| Target Orders/s | Core Completed Trades/s | Production-Equivalent Completed Trades/s | Result |
| ---: | ---: | ---: | --- |
| `700` | `381.48` | `346.43` | both pass |
| `800` | `402.92` | `227.95` | core pass; production-equivalent fail |
| `900` | `450.58` | not attempted | core pass |
| `1000` | `447.87` | not attempted | core fail |

The core run accepted `68000/68000` HTTP orders and converged to `34000 / 34000 / 34000` Match, Order, and Wallet trade rows. The production-equivalent run stopped earlier, accepted `30000/30000` orders, and converged to `15000 / 15000 / 15000` rows. Both had exact assets, empty books and reservations, and zero final queue/DLQ backlog.

The provisional optimized boundary was `900 pass / 1000 fail`. At that historical revision, restoring normal projection frequency, pools, batching, completion-view writes, and reconcilers produced a provisional production-equivalent boundary of `700 pass / 800 fail`. The completion feedback loop has since been retired, so this profile comparison is historical evidence rather than current-code capacity. Both runs were single-seed, short-stage, same-host results.

The complete evidence record is [docs/benchmarks/2026-08-04-balanced-mixed-http-staircase.md](benchmarks/2026-08-04-balanced-mixed-http-staircase.md).

### 2026-08-05 Wallet Boundary and Repeated Steady State

The 2026-08-05 experiment removed the Wallet listener's outer
`TransactionTemplate`. Its isolated 30K, eight-worker happy-path A/B improved from
`11799.16` to `20405.04 settlements/s` (`+72.9%`), while full-chain average Wallet
transaction time fell from `21.13ms` to `9.26ms` (`-56.2%`). This optimization was
subsequently rejected: statement autocommit occurred before Java verified that the
settlement row and both wallet updates succeeded, so an incomplete outcome could not
be rolled back. A forced PostgreSQL integration rerun also reproduced a reversed-role
wallet deadlock that the cached test invocation had not executed.

The corrected implementation retains single-event consumption, restores one explicit
transaction per event, and locks both wallet UUIDs in deterministic order. Fresh
PostgreSQL tests cover reversed-role concurrency, a missing counterparty wallet, and
insufficient seller balance. The `20405.04 settlements/s` value remains useful as a
rejected happy-path ceiling experiment, not as a safe/current Wallet throughput claim.

### MatchEngine Compact Permanent Idempotency Boundary

`IncomingOrderProcessingStore` previously kept one permanent `COMPLETED` UUID field per
order in 256 Redis hashes. Adding TTL was rejected because an old `OrderConfirmed`
redelivery could then rematch a resting or already completed order.

The 2026-08-06 implementation instead uses the Order-owned `(market_id,
market_sequence)` identity as a permanent Redis bitmap. Each market is split into
10-million-sequence shards, so one full shard consumes about 1.25 MB of bitmap payload
and does not hit Redis's single-bitmap offset limit. UUID hashes now contain only
in-flight `PROCESSING` leases. The guarded reserve-or-add Lua checks the completed bit
before claiming; completion atomically sets the bit and deletes the processing field.
Legacy `COMPLETED` hash entries are migrated lazily by the same Lua operation.

A forced PostgreSQL/Redis crash-recovery suite passed crashes after Lua reservation,
after durable trade commit, and before persisting the completed-order bitmap bit. A 900 orders/s
mixed smoke stored 18,000 permanent markers in 2,250 payload bytes / 3,160 bytes reported
Redis memory, with `BITCOUNT=18000` and no remaining processing-state keys. Production
Redis uses AOF and `noeviction`, matching the existing durable order-book fault model.
Recovering from total Redis data loss remains a broader architecture task: it requires
rebuilding both the active order book and completed identities, not merely adding a
PostgreSQL inbox table.

The following 2026-08-05 short-window results used the Wallet autocommit experiment
that was later rejected for rollback safety. They remain useful historical throughput
diagnostics, but they no longer establish current-code capacity.

The historical short-window test independently reset data and restarted services
for each run. Seeds `20260805`, `20260806`, and `20260807` each used a `30s`
warmup and a `180s` measurement window:

| Evidence | Result |
| --- | ---: |
| HTTP accepted | `567000 / 567000`, zero failures |
| Expected / Match / Order / Wallet trades | `283500 / 283500 / 283500 / 283500` |
| Mean accepted load | `900.06 orders/s` |
| Mean same-window completion | `449.54 trades/s` |
| Mean fully converged throughput | `445.32 trades/s` |
| Full-convergence range | `445.03-445.59 trades/s` |
| Largest sampled backlog | `806` |
| Final queues / DLQ / reservations / locked balances | `0` |
| Three-service trade-ID equality | `true` in 3/3 runs |

The three-seed result showed that revision accepting `900 orders/s`, equivalent to
about `445` fully converged trades/s, for the three-minute window. A 30-minute run
accepted all `1674000` HTTP orders at `899.94/s`, but same-window completion fell
to `301.68 trades/s` and only about `619k/837k` trades had reached each service when
the 900-second drain timeout expired.

The long-run hidden debt was `order_service.order_event_outbox`, not a Rabbit queue:
one drain snapshot contained `471102 PENDING` and `1202898 SENT` rows while all
Rabbit queues were empty. The synchronous Order relay drained only about 114
events/s over the next three minutes. Order PostgreSQL showed active `DataFileRead`
waits; the 950 deep run separately showed Order command-pool pending up to `91`,
about `938 MB` of Order WAL, and seven `WALInsert` waiters, while Wallet pool pending
peaked at `1`.

The bounded Order async A/B removed the Order trade-application tail
(`Match -> Order p95 79.97 ms`) but did not make 900 orders/s sustainable. One
15-minute run hit 6,142 HTTP failures. A second run with Wallet batch confirms
accepted all 864,000 orders but completed only 253.79 trades/s in the measurement
window. It also exposed a correctness blocker: Match produced 432,190 trades for
432,000 expected trades, with 431 `amount=1` orders reused by two trades. Order
rejected the contradictory facts and retained 451 permanent inbox failures.
Rabbit queues and durable outboxes accounted for the remaining data; this was not
silent message loss. Both experimental relay settings remain disabled by default.

The historical `900 orders/s` number is not a current capacity claim because its Wallet
transaction boundary was later rejected. A lower current-code long-duration knee and
an external load generator remain required.

The corrected atomic incoming-order claim subsequently completed a shuffled
15-minute reliability run with all `864000` HTTP orders accepted and exactly
`432000` identical Match, Order, and Wallet trade facts. No order ID was used in
more than one Match trade; final queues, DLQ, reservations, order books, and pending
outboxes were zero. The run required `1717.39s` to converge, reached only `277.98`
steady completed trades/s, and accumulated a maximum backlog of `46451`, so it
failed the sustained-capacity contract. A focused Gradle run overlapped its first
minute; the result is retained as correctness evidence, not a clean capacity
comparison.

Real PostgreSQL/Redis integration tests now force crashes at three matching
boundaries: before durable trade commit, after commit but before Redis cleanup, and
before the incoming-order completed bitmap bit. Recovery preserves quantity, avoids
duplicate trades on repeated delivery, completes cleanup, and leaves no active
reservation. The complete MatchEngine test suite passes.

A real MatchEngine SIGKILL with 28 unacknowledged Rabbit deliveries also passed.
After restart, all `29250` expected trades converged identically across Match,
Order, and Wallet; duplicate order use, queues, DLQ, reservations, and pending
outboxes were zero.

The clean current-code `1000 orders/s x 180s` saturation run reached `497.48`
completed trades/s, up `12.05-12.48%` from the comparable `442.28-443.97`
baselines. It is not a sustained claim because backlog growth exceeded the limit.
A 15-minute 800 orders/s run reached `377.32` trades/s but accumulated durable debt
and failed the sustained gate. The first 700 orders/s run had eight local HTTP
timeouts and was rejected even though its backend metrics passed. A clean repeat
at that historical revision passed at `699.14` accepted orders/s and `343.05`
completed trades/s with a 98.01% completion ratio, `+1.05/s` backlog slope, and
6,916 maximum backlog. All 336,000 trades and 672,000 order uses converged without
duplication. A newer release-pinned 700 repeat converged with the same exact
correctness but failed the sustained completion and backlog gates; the historical
pass is therefore not promoted as current repeatable capacity.

The steady-state harness now resolves ambiguous HTTP timeouts from durable Order
facts. It derives pairable trades from durable BUY/SELL counts and verifies any
imbalance against open orders and Wallet locks, while retaining HTTP failure as a
capacity-invalid reason and still producing the final JSON artifact.

The complete evidence record is
[docs/benchmarks/2026-08-05-wallet-settlement-robustness.md](benchmarks/2026-08-05-wallet-settlement-robustness.md).

Fresh 30-second deep diagnostics on the corrected Wallet transaction boundary
passed at both 800 and 900 total orders/s. Two 900 seeds accepted `899.50-899.85`
orders/s and completed `455.56-470.34` trades/s in the measurement window, with
negative backlog slopes and exact 15,750-trade three-service convergence. These are
short diagnostics, not a replacement for the failed long-duration 900 soak.

The same work corrected an attribution defect: Order's former stage timestamp was
the source event time. A database-generated Order insertion timestamp now shows
Match-to-Order p95 `429.21ms` and Match-to-Wallet p95 `410.38ms`, with only
`68.07ms` p95 skew. The shared Match trade-outbox publication path is therefore the
next controlled A/B target; Wallet SQL is not independently responsible for the
full convergence tail. The run also reached 95-100% system CPU on the shared host,
so any improvement must be repeated under low-observer diagnostics before being
called a code-path gain.

### Legacy Alternating Staircase

Historical boundary run: `GLT_20260730_HTTP_MATCHED_STAIRCASE_BOUNDARY_700_1100_R3`. It used strict alternating `SELL, BUY` pairs and is retained for regression comparison.

| Target Orders/s | Scheduled Orders/s | Accepted Responses/s | Completed Trades/s | Result |
| ---: | ---: | ---: | ---: | --- |
| `700` | `699.99` | `699.94` | `351.36` | pass |
| `800` | `799.99` | `799.55` | `397.77` | pass |
| `900` | `899.98` | `899.61` | `458.38` | pass |
| `1000` | `999.98` | `999.83` | `511.85` | pass |
| `1100` | `1099.99` | `1098.84` | `431.56` | fail: completion rate and backlog growth |

At `1000 orders/s`, one BUY and one SELL form one trade, so the target is `500 trades/s`, not `1000 trades/s`. The stage completed at `511.85 trades/s`; its backlog peaked at `2011` and returned to `0` by stage end. HTTP p95 and p99 upper bounds were both `200 ms`.

At `1100 orders/s`, all `16500` measured HTTP requests were accepted and the response drain tail was only `16.6 ms`. The driver therefore maintained input. Business completion reached only `431.56 trades/s` against a `550 trades/s` target, while backlog grew from `110` to `4074`.

Final run-wide correctness:

| Signal | Result |
| --- | ---: |
| HTTP orders accepted | `90000/90000` |
| Match / Order / Wallet trade rows | `45000 / 45000 / 45000` |
| Three-service trade-ID equality | `true` |
| Remaining BUY / SELL orders | `0 / 0` |
| Active match reservations | `0` |
| Final queue backlog / DLQ | `0 / 0` |
| Asset settlement | exact |

Interpretation:

- HTTP input generation is not the observed `1100 orders/s` failure.
- The historical alternating boundary was `1000 orders/s`, approximately `500 completed trades/s`; the canonical shuffled workload has replaced this as the current capacity signal.
- Diagnostics at the failed stage showed high shared-host CPU and a growing `wallet.orderSubmitted.queue`, with pressure also visible in the Order command path.
- This is a 15-second-stage capacity search with a co-located load generator. It is not a 30-minute steady-state or production-cluster claim.

## Matched-Trade-Completion Chain Semantics

The current global 10k benchmark is a controlled `matched-trade-completion-chain` workload. It is not the public API order lifecycle.

| Field | Meaning |
| --- | --- |
| `EVENTS=10000` | target `10000` completed trades after sell-side liquidity is prepared |
| input attempted load | client-side BUY publish attempts sent toward the match path |
| broker-confirmed input load | BUY publishes acknowledged by RabbitMQ publisher confirms |
| completed trade | `TradeExecuted` persisted, Order applied, Wallet settled, identical `trade_id` sets across the three service-owned durable tables, queues drained |
| timing start | run phase begins after prepare/seed and cleanup |
| timing end | max of durable trade fact convergence time and final measured queue drain |
| projection | diagnostic read-model lag, not part of business completion |

This means input order confirmations/s and completed trades/s are intentionally different units. The first describes load pressure; the second describes fully gated business completion.

## TPS126 Seeded Contract-v2 Diagnostic

Run: `GLT_TPS126_DIRECT_CONFIRM_LIGHT_10K_R1`, one 10k light diagnostic sample.

This was the first 10k run after hardening the seeded benchmark contract with RabbitMQ publisher confirms and trade-ID set equality across MatchEngine, Order, and Wallet. It is not a valid 2000-input capacity comparison because broker-confirmed input did not reach the configured `95%` offered-load threshold. It remains useful historical evidence because the correctness gate passed cleanly and the seeded completed-trade path reached the `1200/s` class under contract-v2 validation.

| Metric | Result |
| --- | ---: |
| target BUY send rate | `2000 order confirmations/s` |
| broker-confirmed BUY input | `1377.80 order confirmations/s` |
| broker acked input count | `10000/10000` BUY, `10000/10000` SELL |
| business completed trade TPS | `1234.47 completed trades/s` |
| MatchEngine trade execution reach TPS | `1340.37/s` |
| Order trade application reach TPS | `1234.47/s` |
| Wallet trade settlement reach TPS | `1234.47/s` |
| business completion window | `8.10s` |
| final measured queue ready / unacked | `0 / 0` |
| DLQ | `0` |

Correctness checks:

- `completedTrades=10000`.
- `tradeExecutions=10000`.
- `walletTradeSettlements=10000`.
- `orderCommandMatchedRows=20000`.
- `completedTradeIdSetsEqual=true`.
- `tradeIdsMissingInMatch=0`, `tradeIdsMissingInOrder=0`, `tradeIdsMissingInWallet=0`.
- final measured queues and DLQ drained to `0`.
- Redis orderbook ended with `remainingSellOrders=0`, `remainingBuyOrders=0`, and `activeReservations=0`.

Interpretation:

- The benchmark harness now distinguishes client-side attempted input from broker-confirmed input.
- The previous "near 2000 input TPS" wording should be treated as client-side send pressure unless the run includes broker-confirm metrics.
- The current 10k diagnostic run proves correctness under the hardened gate, but it should not be reported as a valid 2000-input capacity run.
- The next public step is a clean five-run repeat on contract v2, then a steady-state run at a conservative broker-confirmed target.

Additional TPS126 measurement split:

- `rabbitmq-publish-only` with service processing removed reached `1994.98` broker-confirmed persistent messages/s for 10k messages.
- `matched-trade-completion-chain` with aggressive `PUBLISHERS=128` / `PUBLISHER_CONNECTION_CACHE_SIZE=16` reached only `1171.38` broker-confirmed input/s and `1046.34` completed trades/s.
- `matched-trade-completion-chain` with low-interference `PUBLISHERS=1` reached `1531.96` broker-confirmed input/s and `1385.10` completed trades/s.

Interpretation: RabbitMQ input confirms are not the isolated ceiling. Under integrated service load, input publisher confirms compete with MatchEngine relay and downstream Order/Wallet consumer traffic. The matched-trade-completion benchmark therefore fixes publisher count at `1`, while high publisher fan-out is reserved for the `rabbitmq-publish-only` diagnostic.

## Previous Local 10k Repeat Result

Run set: `GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3`, 3 repeats, 3 valid samples under the older input-attempt contract.

This run set remains useful as performance-improvement history after the Order and Wallet batch-path optimization work and the TPS semantic split. It is superseded by contract v2 for public capacity claims because it did not yet require RabbitMQ broker-confirmed input and trade-ID set equality.

| Metric | Result |
| --- | ---: |
| target client-side input pressure | `2000 order confirmations/s` |
| client-side input attempts | median `1999.22 order confirmations/s`, range `1998.46-1999.26` |
| completed trades per valid run | `10000` |
| orderbook admission TPS | median `4211.32 order confirmations/s`, range `3696.83-4972.65` |
| business completed trade TPS | median `833.58 completed trades/s`, range `729.71-940.93` |
| blended market flow TPS | median `1391.69 order confirmations/s`, range `1218.84-1582.44` |
| business completion window | median `12.00s`, range `10.63-13.70s` |
| final measured queue ready / unacked | `0 / 0` |
| DLQ | `0` |

## Previous Public 10k Repeat Result

Run set: `EAP_PUBLIC_10K_20260713`, 5 repeats, 4 valid public samples.

Snapshot:

| Repo | Commit |
| --- | --- |
| benchmark infra | `2252e54738d10683894b965c93d93bff32fd8c08` |
| eap-order | `5f7f6e18bb40c1e17e565de6377ea1eef77ed165` |
| eap-wallet | `f5ac2916a6443c7f7c577db379712b4df34df545` |
| eap-matchEngine | `012a5c488aeb0da503eb6897abb6afcbafc5cc69` |
| eap-common | `8cce7cd93d1e6cfde3fcf715894a01678b96ff76` |

| Metric | Result |
| --- | ---: |
| target offered load | `2000 order confirmations/s` |
| valid actual offered load | median `1998.94 order confirmations/s`, range `1998.54-1999.13` |
| completed trades per valid run | `10000` |
| business completed trade TPS | median `582.73 completed trades/s`, range `503.11-662.17` |
| business completion window | median `17.29s`, range `15.10-19.88s` |
| wallet settlement reach TPS | median `843.92/s`, range `825.46-974.14` |
| legacy completion marker reach TPS | median `745.60/s`, range `701.99-803.90` |
| final queue ready / unacked | `0 / 0` |
| DLQ | `0` |

One repeat, `EAP_PUBLIC_10K_20260713_R3`, completed the business gate but is excluded from the public median because the local load driver only achieved `733.79` buy confirmations/s, below the `95%` offered-load threshold.

Interpretation: the system can accept near-2000/s input pressure in valid short 10k runs, but the fully gated completed-trade throughput is currently in the `503-662/s` range on the local benchmark environment.

## Benchmark Environment

| Item | Value |
| --- | --- |
| Machine | MacBook Pro, Apple M5, 10 cores, 16 GB RAM |
| OS | macOS 26.5.1 |
| Docker | Docker 29.5.3 |
| JDK | Temurin OpenJDK 21.0.10 |
| PostgreSQL | `postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647`, three service-owned DB containers, `max_connections=120`, `shared_buffers=512MB`, `synchronous_commit=off`, `pg_stat_statements` enabled |
| RabbitMQ | `rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281` |
| Redis | `redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`, append-only disabled, `maxmemory=1024mb`, `noeviction` |
| Load generator | same local machine as services and containers |

The latest numbers are documented local benchmark results against the pinned snapshot above. Treat them as externally reproducible only after the result bundle under `build/load-test-reports/` is published with the corresponding commits.

## Timing Formula

```text
businessCompletedTradeTps =
  completedTrades /
  (max(durableTradeFactConvergedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

`DURATION_SECONDS=5` is the scheduled BUY publishing window. It is not the completed-business timing window. In the latest TPS126 diagnostic run, the business completion window was `8.10s`, so `10000 / 8.10 ~= 1234.47 completed trades/s`. The run is still invalid for 2000-input capacity comparison because the broker-confirmed input rate was `1377.80/s`.

## Best Isolated Matching Result

| Metric | Result |
| --- | ---: |
| Redis matching core throughput | `18,388.25 ops/s` |
| p50 latency | `2.93ms` |
| p95 latency | `5.39ms` |
| p99 latency | `28.25ms` |

Interpretation: the core Redis order book is not the current global E2E bottleneck. The lower completed E2E throughput comes from reliable persistence, outbox publishing, settlement, and completion convergence.

## Recent Optimization Summary

| Change | Main Evidence | Decision |
| --- | --- | --- |
| Historical Match completion marker batch SQL using stable `unnest` | marker insert calls dropped from `20000` to `2314`; marker SQL total `1187.94ms -> 970.28ms` | retired with the downstream completion feedback loop |
| Drop redundant Match outbox unique constraint | outbox insert SQL improved only about `58ms` over 10k rows | low-impact cleanup, not the main fix |
| Use `trade_id` as Match `trade_executions` primary key | trade execution insert total `1015.71ms -> 820.40ms`; trade outbox insert total `802.17ms -> 546.88ms` | kept |
| Wallet outbox JDBC projection/update | wallet outbox select SQL `384.24ms -> 59.77ms`; business E2E `384.15 -> 468.76` | kept |
| Public repeat benchmark process | 4/5 valid repeats; valid median `582.73` completed trades/s | use median/range for public claims |
| Order / Wallet batch-path validation with split TPS semantics | 3/3 valid 10k repeats under the older input-attempt contract; business completed median `833.58` completed trades/s; blended market flow median `1391.69` order confirmations/s | keep as performance-improvement history; superseded for public capacity claims by contract v2 |
| Contract-v2 broker-confirmed input and trade-ID equality | Single 10k diagnostic run completed at `1234.47` completed trades/s with all broker acks, final queues/DLQ `0`, and equal Match/Order/Wallet trade-ID sets; broker-confirmed input was `1377.80/s` | keep as hardened measurement baseline; not a valid 2000-input capacity run yet |
| Outbox batch-confirm A/B probe | Match+Order+Wallet ON: `869.38` single-run completed trades/s but Match confirm timer worsened to `39.534s`; Match OFF + Order/Wallet ON: `822.99` and confirm timers roughly unchanged | rejected as default tuning; flags remain disabled for loadtest A/B |
| OrderTradeApplied application-table relay experiment | Removed generic OrderTradeApplied outbox rows in a 10k run, but business completed TPS regressed to `619.67`; new relay confirm sum was `13.301s` and batch sum `13.855s` | rejected; do not merge relay state into `order_trade_applications` hot fact table |
| Order trade-apply stable `unnest` CTE input | Correctness passed, but 10k completed TPS regressed to `687.76`; Order `batch_total` worsened from TPS-93 R2 `9.256s` to `15.553s` and `batch_append` from `5.164s` to `7.592s` | rejected; keep dynamic `VALUES` CTE path and focus on durable-write semantics |
| Redis user-open-order index OFF repeat | Latest 10k run completed at `749.07` trades/s with final queues/DLQ at zero; `reserve_order.redis_eval` was `19.784s`, not better than TPS-93 R2 `15.888s` | keep as diagnostic flag; not the current TPS fix |
| Integrated stage-lag diagnostics | TPS98 10k run completed at `622.05` trades/s with final queues/DLQ at zero. Wallet insert attribution shows p95 `Match persisted -> Wallet settlement inserted = 2073.250ms`, `Wallet settlement inserted -> WALLET_SETTLED marker = 1172.450ms`, and `Wallet settlement inserted -> relay mark-SENT = 1483.760ms` | keep; Wallet is visible in the convergence cost, but it is not independently slower than Order apply |
| MatchEngine tryMatch outcome attribution | TPS99 10k run completed at `580.10` trades/s with final queues/DLQ at zero. `added_to_book` cost `20.594s / 10000`, `fully_matched` cost `29.333s / 10000`, and `reserve_order.redis_eval` cost `27.705s / 20000` | keep; the common Redis reserve-or-add path is a major integrated cost under full pressure |
| Match trade/outbox/cleanup single-CTE A/B | Two correctness-valid 30K full-HTTP runs completed at only `687.48` and `769.27` BUY-triggered trades/s versus the accepted `842.04-922.38` range; the deep run's combined SQL consumed `42.975s` cumulative DB time versus about `18.281s` for the accepted run's two statements | rejected and reverted; keep separate durable inserts plus cleanup-worker batch completion |
| Wallet settlement batch-size 100 A/B | Original overlap fallback produced `5206` singleton transactions and only `644.86/s`; ordered partitioning exposed cross-batch wallet-row deadlocks; deterministic row pre-locking removed deadlocks and reduced singleton work to `12`, but CTE application time rose to `32.556s`, Match-to-Wallet p95 to `9.114s`, and throughput reached only `716.58/s` | runtime candidate rejected and reverted; keep `50/75ms`, retain load-test batch-size/timeout controls |
| Wallet JFR plus concurrent reservation/settlement DB probe | Full-chain Wallet transaction wall was `477.290s` for 20K reservations versus `35.978s` PostgreSQL executor time; two direct mixed-SQL runs reached `5307.62-5530.29 trade cycles/s` with zero failures | raw Wallet SQL interaction rejected as the `922.38/s` ceiling; target transaction/listener/outbox boundary reduction next |
| Wallet reservation grouped-transaction A/B | Initial batch 5 deadlocked repeatedly; deterministic locking restored correctness, but batch 5 reached `779.98/s` and batch 2 `677.70/s` versus the contemporaneous single-transaction control's `816.15/s` | rejected and reverted; commit amortization did not offset longer multi-user lock ownership |

## Seeded Matched-Completion Bottleneck

The strongest current signal is durable write and relay cost across the `matched-trade-completion-chain`:

- MatchEngine writes `TradeExecuted` facts and trade outbox rows.
- Order applies each trade to command-side order state and its durable trade-application table.
- Wallet settles each trade and records durable settlement facts.
- The benchmark now validates that the completed trade IDs are identical across MatchEngine, Order, and Wallet, then requires measured queues to drain.

Increasing consumer concurrency alone has repeatedly failed to solve this class of problem. Several runs improved local queue drain but regressed full business TPS. The next useful work is targeted SQL/write-model review, not another broad concurrency increase.

The latest integrated stage-lag reports make the bottleneck more concrete: isolated DB SQL and isolated relay probes are fast, but under full service load the integrated Match intake -> durable trade persistence -> downstream Order/Wallet apply path takes seconds to converge at p95. Wallet now has immutable settlement insertion timestamps for attribution. The next optimization target should remain the integrated durable write chain rather than a single SQL statement in isolation.

MatchEngine was not cleared as "no longer relevant"; previous work cleared narrower hypotheses. Redis orderbook admission and isolated DB/relay probes are fast enough in isolation, but full `tryMatch` still combines two workloads: resting-order admission and incoming-order trade completion. TPS99 separates `added_to_book` from `fully_matched` and shows both outcomes grow under full pressure, with the shared Redis reserve-or-add Lua path dominating reserve time. The next target is MatchEngine intake/Redis orderbook semantics, not another broad concurrency increase.

## Correctness Gates

The current business gate requires:

- target `TradeExecuted` count reached;
- target Order command-side trade application reached;
- target Wallet settlement count reached;
- identical completed trade-ID sets across MatchEngine, Order, and Wallet;
- RabbitMQ ready and unacked messages drained to zero;
- DLQ remains zero;
- duplicate and idempotency checks pass in focused tests.

Projection lag is diagnostic only. It is not included in the business gate because projections are rebuildable read models.

## Known Gaps

- The latest full HTTP staircase publishes HTTP histogram upper bounds but not end-to-end per-trade p95/p99 latency.
- The full HTTP boundary stages are 15 seconds, not 30-minute soak claims.
- The load generator, services, and containers share one machine. A separate load-generator host is still required to remove shared-CPU interference from a production-style capacity claim.
- A historical revision has a clean 15-minute `700 orders/s` mixed soak, but the 2026-08-11 release-pinned repeat failed the sustained completion and backlog gates despite exact final convergence. The current release-pinned 15-minute lower bound is one passing 600 run; it still requires a second seed before promotion to a repeatable boundary.
- The earlier seeded 15-minute repeat produced `2/3` valid samples and one `19`-trade correctness miss. Match reservation convergence was implemented afterward and passed a 120k correctness run. The later full HTTP 30-minute 900 orders/s run failed because the Order event outbox accumulated durable debt; a lower-rate passing soak remains pending.
- One current-code schema-v2 100K run now passes all correctness gates, but its `613.33 trades/s` completion rate is below the historical 100K result. Repeat runs are required before treating either value as sustained capacity.
- The 2026-08-11 700 recheck and both 2026-08-13 600 attempts have published result JSON files. Several older result artifacts remain local and should be attached to a release or otherwise published.
- Atomic MatchEngine incoming-order redelivery protection now passes a real RabbitMQ duplicate injection, a real MatchEngine SIGKILL/redelivery run, an 864K-order reliability run, and deterministic PostgreSQL/Redis crash-window tests. Outbox crash/retry and projection replay fault injection remain pending.
- RabbitMQ publisher-confirm stalls, resource alarms, PostgreSQL crash recovery, and shared-host CPU saturation can invalidate capacity comparisons. The harness now samples broker alarms and preserves failure artifacts, but a separate load-generator host remains required for production-style capacity evidence.

## Historical Seeded Steady-State Evidence

The clean Redis single-run result `EAP_STEADY_500TPS_15M_20260713_R2` completed successfully and established the first valid near-500 offered-load steady-state signal.

| Signal | Result |
| --- | --- |
| Intended trades | `450000` |
| Completed trades | `450000` |
| Trade executions | `450000` |
| Wallet settlements | `450000` |
| Order command matched rows | `900000` |
| BUY publish failures | `0` |
| SELL publish failures | `0` |
| Actual offered BUY rate | `492.70/s` |
| Fully gated completed throughput | `481.42 trades/s` |
| Full drain after BUY publish ended | `21.40s` |
| Final measured queues / DLQ | `0 / 0` |
| Remaining Redis orderbook entries | `0 BUY`, `0 SELL` |
| Redis eviction | `0` |
| Redis peak memory | `270.77MB / 1GB` |

Runtime sampler stability:

- `102` samples covered the run phase from `2026-07-13T07:49:38Z` to `2026-07-13T08:08:12Z`.
- `order.dlq` stayed `0` throughout the sampled window.
- `matchEngine.orderConfirmed.queue` peaked at `215041` total messages during preload/run pressure and drained to `0`.
- Downstream sampled peak unacked counts stayed bounded: Order trade-executed `262`, Wallet trade-executed `176`, Order-applied marker `464`, Wallet-settled marker `243`.
- Redis stayed on `noeviction`, `evicted_keys=0`, and used only about `26.5%` of configured memory at peak.

## Steady-State Repeat Attempt

Run set: `EAP_STEADY_500TPS_15M_20260714_R1` through `R3`, target `500` offered BUY confirmations/s for `900s`, `450000` intended completed trades per run.

| Run | Valid | Offered BUY TPS | Business E2E TPS | Completion Window | Drain After BUY | Correctness |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `R1` | yes | `494.71` | `477.42` | `942.57s` | `32.95s` | `450000/450000`, queues/DLQ `0`, Redis evictions `0` |
| `R2` | yes | `500.00` | `497.89` | `903.81s` | `3.81s` | `450000/450000`, queues/DLQ `0`, Redis evictions `0` |
| `R3` | no | `494.78` | rejected | rejected | rejected | `449981/450000`, `remainingBuyOrders=19`, queues/DLQ `0`, Redis evictions `0` |

Valid-sample summary:

| Metric | Median | Range |
| --- | ---: | ---: |
| actual BUY publish TPS | `497.36/s` | `494.71-500.00/s` |
| business completed trade TPS | `487.66/s` | `477.42-497.89/s` |
| business completion window | `923.19s` | `903.81-942.57s` |
| drain after BUY publish | `18.38s` | `3.81-32.95s` |

Rejected sample `R3` matters more than its raw `165.96/s` computed throughput. It failed because the target completion counts never reached `450000`: `tradeExecutions=449981`, `walletTradeSettlements=449981`, `orderCommandMatchedRows=899962`, `remainingBuyOrders=19`, `lockedCurrency=1900`, and `lockedAmount=19`. RabbitMQ queues and DLQ drained to zero, and Redis stayed on `noeviction` with `evicted_keys=0`, so this is not the earlier Redis eviction failure.

Interpretation: EAP completed two near-500 seeded matched-flow steady-state runs, but this set was not three-run stable. The later reservation-convergence work addressed the hidden-reservation class exposed by sustained tests and passed a 120k correctness run. This historical set still must not be presented as a successful three-run full HTTP soak.

## Next Measurement Plan

Before pushing for higher completed TPS, the next public-quality benchmark should:

1. Repeat the passing release-pinned `600 orders/s` point with a second workload seed.
2. Require zero reused orders, exact three-service trade IDs, exact assets, and empty inbox/outbox/queue debt in every accepted run.
3. Step to `650` and then `700 orders/s` only after 600 repeats.
4. Capture RabbitMQ publisher-confirm stalls and same-host saturation as explicit comparison-invalidating signals, then run the same contract from a separate load-generator host when one is available.
5. Publish a dedicated failure-injection report for retry, redelivery, ack-timeout, and restart behavior.

The concrete public benchmark runbook is [docs/benchmarks/2026-07-public-benchmark.md](benchmarks/2026-07-public-benchmark.md).

## Interview-Safe Claim

Latest full HTTP lifecycle wording:

> I independently built a Java/Spring Boot electricity trading backend covering order intake, balance checks, matching, trade recording, and settlement. The latest current-worktree shuffled mixed HTTP diagnostic reached 699.98 accepted orders/s, 346.12 same-window trades/s, and 320.47 full-lifecycle trades/s; all 17,500 orders converged into 8,750 identical Match, Order, and Wallet trade records with exact balances and empty final queues. This was a 15-second, one-seed, same-host CDA diagnostic rather than a release-pinned capacity or production SLA. Historical high-volume tests separately validated 100,000 completed trades from 200,000 HTTP orders without record or asset loss.

Sequential diagnostic wording, when the benchmark distinction is relevant:

> With sell-side liquidity prepared before the measured BUY phase, the best 30K sequential diagnostic completed 922 trades/s. This is an optimized upper-bound workload, not the mixed-flow capacity claim.

Historical seeded matched-completion wording:

> A separate seeded matched-completion benchmark reached a three-run median of 833.58 completed trades/s, but it starts from confirmed orders and therefore does not represent the full public HTTP lifecycle.

Avoid this wording:

> The full system handles 2000 TPS.

That would mix accepted input pressure with completed business throughput.
