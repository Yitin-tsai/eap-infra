# EAP Performance Report

This report summarizes the current 2000 TPS investigation in a public, interview-readable format. The detailed engineering log is in [docs/features/2026-06-global-loadtest-2000-tps.md](features/2026-06-global-loadtest-2000-tps.md).

## Throughput Definitions

EAP reports multiple throughput numbers because they answer different questions.

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

## Workload Semantics

The current global 10k benchmark is a controlled matched-trade workload.

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

## Latest Contract-v2 Diagnostic Result

Run: `GLT_TPS126_DIRECT_CONFIRM_LIGHT_10K_R1`, one 10k light diagnostic sample.

This is the first 10k run after hardening the benchmark contract with RabbitMQ publisher confirms and trade-ID set equality across MatchEngine, Order, and Wallet. It is not a valid 2000-input capacity comparison because broker-confirmed input did not reach the configured `95%` offered-load threshold. It is still useful because the correctness gate passed cleanly and the completed-trade path reached the current `1200/s` class under contract-v2 validation.

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
| business matched E2E TPS | median `582.73 completed trades/s`, range `503.11-662.17` |
| business completion window | median `17.29s`, range `15.10-19.88s` |
| wallet settlement reach TPS | median `843.92/s`, range `825.46-974.14` |
| completion marker reach TPS | median `745.60/s`, range `701.99-803.90` |
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
| Match completion marker batch SQL using stable `unnest` | marker insert calls dropped from `20000` to `2314`; marker SQL total `1187.94ms -> 970.28ms` | kept as local SQL cleanup |
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

## Current Bottleneck

The strongest current signal is durable write and relay cost across the completed-trade chain:

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

- The latest global E2E report does not yet publish API p95/p99 or end-to-end p95/p99 latency.
- The strongest 10k runs are short benchmark scenarios, not 30-minute soak claims.
- The latest contract-v2 result is a single diagnostic run. A five-run repeat with broker-confirmed input is still required before publishing a new public median/range.
- The first 15-minute steady-state attempt was rejected because Redis eviction invalidated the order-book state. Clean Redis runs now keep `evicted_keys=0`, but the latest three-run steady-state attempt produced `2/3` valid samples and one correctness rejection with `19` missing completed trades.
- Result artifacts are still local and should be attached to a release or otherwise published.
- Failure-injection results should be split into a reliability report: duplicate messages, consumer restart, outbox retry, DLQ, and projection replay.

## Steady-State Stability Evidence

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
| business matched E2E TPS | `487.66/s` | `477.42-497.89/s` |
| business completion window | `923.19s` | `903.81-942.57s` |
| drain after BUY publish | `18.38s` | `3.81-32.95s` |

Rejected sample `R3` matters more than its raw `165.96/s` computed throughput. It failed because the target completion counts never reached `450000`: `tradeExecutions=449981`, `walletTradeSettlements=449981`, `orderCommandMatchedRows=899962`, `remainingBuyOrders=19`, `lockedCurrency=1900`, and `lockedAmount=19`. RabbitMQ queues and DLQ drained to zero, and Redis stayed on `noeviction` with `evicted_keys=0`, so this is not the earlier Redis eviction failure.

Interpretation: EAP can complete near-500 offered-load steady-state runs on the local environment, but it should not yet be described as three-run stable. The next engineering task is to investigate the `19` missing trades in `R3` using the preserved diagnostics.

## Next Measurement Plan

Before pushing for higher completed TPS, the next public-quality benchmark should add:

1. API and end-to-end p50/p95/p99 latency.
2. Published result artifacts for the 10k repeat runs.
3. Investigate the `EAP_STEADY_500TPS_15M_20260714_R3` correctness miss before treating the steady-state result as a stable public median.
4. Queue backlog over time, not only final queue drain.
5. Failure-injection results for retry and restart behavior.

The concrete public benchmark runbook is [docs/benchmarks/2026-07-public-benchmark.md](benchmarks/2026-07-public-benchmark.md).

## Interview-Safe Claim

Historical wording for TPS93 discussions only:

> I built a production-style Java/Spring Boot electricity trading platform and defined completed-trade TPS as TradeExecuted persistence plus Order application, Wallet settlement, completion-marker convergence, and final queue drain. After reducing Order and Wallet batch-path overhead, a 3-run 10k local benchmark sustained about 1999 offered order confirmations/s and reached a median fully gated throughput of 833.58 completed trades/s, with a 729.71-940.93 range and final queues/DLQ at zero. I also report orderbook admission and blended market-flow throughput separately to avoid mixing accepted input with completed business throughput.

Use this contract-v2 wording for current discussions:

> I built a production-style Java/Spring Boot electricity trading platform and define completed-trade TPS as TradeExecuted persistence, Order trade application, Wallet settlement, identical completed trade-ID sets across the three services, and final RabbitMQ queue drain. After hardening the benchmark with RabbitMQ publisher confirms, a 10k local diagnostic run completed 10000 trades at 1234.47 completed trades/s with all measured queues and DLQ at zero, but broker-confirmed input reached only 1377.80/s, so I do not report it as a valid 2000-input capacity result yet.

Avoid this wording:

> The full system handles 2000 TPS.

That would mix accepted input pressure with completed business throughput.
