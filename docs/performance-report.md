# EAP Performance Report

This report summarizes the current 2000 TPS investigation in a public, interview-readable format. The detailed engineering log is in [docs/features/2026-06-global-loadtest-2000-tps.md](features/2026-06-global-loadtest-2000-tps.md).

## Throughput Definitions

EAP reports multiple throughput numbers because they answer different questions.

| Metric | Meaning | Can It Be Called Completed Business TPS? |
| --- | --- | --- |
| accepted orders/s | order requests accepted or order confirmations published by the load generator | No |
| core matching ops/s | isolated Redis/Lua matching throughput | No |
| trade execution reach TPS | MatchEngine persisted `TradeExecuted` facts | No |
| wallet settlement reach TPS | Wallet settlement records reached target count | Partial |
| completion marker reach TPS | MatchEngine completion view received Order + Wallet markers | Close, but queue drain still matters |
| orderbook admission TPS | resting SELL confirmations admitted into the Redis order book | No, this is order-book admission, not completed trades |
| business completed trade TPS | completion markers reached target count and measured queues drained | Yes |
| blended market flow TPS | total SELL+BUY order confirmations processed across the full two-phase benchmark window | No, useful for workload capacity but it mixes order confirmations and completed trades |

The project intentionally does not report accepted order throughput as completed trading throughput.

## Workload Semantics

The current global 10k benchmark is a controlled matched-trade workload.

| Field | Meaning |
| --- | --- |
| `EVENTS=10000` | target `10000` completed trades after sell-side liquidity is prepared |
| offered load | order confirmations published toward the match path |
| completed trade | `TradeExecuted` persisted, Order applied, Wallet settled, completion markers converged, queues drained |
| timing start | run phase begins after prepare/seed and cleanup |
| timing end | max of completion-marker reach time and final measured queue drain |
| projection | diagnostic read-model lag, not part of business completion |

This means offered order confirmations/s and completed trades/s are intentionally different units. The first is input pressure; the second is fully gated business completion.

## Latest Current 10k Repeat Result

Run set: `GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3`, 3 repeats, 3 valid samples.

This is the latest local interview benchmark after the Order and Wallet batch-path optimization work and the TPS semantic split. It is not yet a pinned public artifact bundle, so use it as current engineering evidence and interview talking material rather than an externally reproducible public release claim.

| Metric | Result |
| --- | ---: |
| target offered load | `2000 order confirmations/s` |
| actual offered load | median `1999.22 order confirmations/s`, range `1998.46-1999.26` |
| completed trades per valid run | `10000` |
| orderbook admission TPS | median `4211.32 order confirmations/s`, range `3696.83-4972.65` |
| business completed trade TPS | median `833.58 completed trades/s`, range `729.71-940.93` |
| blended market flow TPS | median `1391.69 order confirmations/s`, range `1218.84-1582.44` |
| business completion window | median `12.00s`, range `10.63-13.70s` |
| final queue ready / unacked | `0 / 0` |
| DLQ | `0` |

Per-run summary:

| Run | Offered TPS | Business Completed TPS | Blended Market Flow TPS | Completion Window | Final State |
| --- | ---: | ---: | ---: | ---: | --- |
| `R1` | `1998.46` | `833.58` | `1391.69` | `12.00s` | queues/DLQ `0`, all correctness counts reached |
| `R2` | `1999.26` | `940.93` | `1582.44` | `10.63s` | queues/DLQ `0`, all correctness counts reached |
| `R3` | `1999.22` | `729.71` | `1218.84` | `13.70s` | queues/DLQ `0`, all correctness counts reached |

Why this is an effective TPS improvement:

- The load driver was stable across all three runs: actual offered TPS relative spread was only `0.04%`.
- All runs preserved correctness: `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`, final measured backlog `0`.
- The median completed-trade throughput improved from the earlier public repeat median `582.73` to the current local median `833.58` after the Order / Wallet batch-path work became visible in the full chain.
- The result should be reported as median/range, not best run, because service-side local variance remains material: business completed TPS relative spread was about `25.30%`.

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
businessMatchedE2eTps =
  completedTrades /
  (max(completionMarkerReachedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

`DURATION_SECONDS=5` is the offered-load publishing window. It is not the completed-business timing window. In the latest TPS93 repeat set, the median completion window was `12.00s`, so `10000 / 12.00 ~= 833.58 completed trades/s`. That reflects completion convergence plus queue drain after the input burst.

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
| Order / Wallet batch-path validation with split TPS semantics | 3/3 valid 10k repeats; business completed median `833.58` completed trades/s; blended market flow median `1391.69` order confirmations/s | use as current interview benchmark; publish only after clean commit/artifact bundle |
| Outbox batch-confirm A/B probe | Match+Order+Wallet ON: `869.38` single-run completed trades/s but Match confirm timer worsened to `39.534s`; Match OFF + Order/Wallet ON: `822.99` and confirm timers roughly unchanged | rejected as default tuning; flags remain disabled for loadtest A/B |
| OrderTradeApplied application-table relay experiment | Removed generic OrderTradeApplied outbox rows in a 10k run, but business completed TPS regressed to `619.67`; new relay confirm sum was `13.301s` and batch sum `13.855s` | rejected; do not merge relay state into `order_trade_applications` hot fact table |
| Order trade-apply stable `unnest` CTE input | Correctness passed, but 10k completed TPS regressed to `687.76`; Order `batch_total` worsened from TPS-93 R2 `9.256s` to `15.553s` and `batch_append` from `5.164s` to `7.592s` | rejected; keep dynamic `VALUES` CTE path and focus on durable-write semantics |
| Redis user-open-order index OFF repeat | Latest 10k run completed at `749.07` trades/s with final queues/DLQ at zero; `reserve_order.redis_eval` was `19.784s`, not better than TPS-93 R2 `15.888s` | keep as diagnostic flag; not the current TPS fix |
| Integrated stage-lag diagnostics | TPS98 10k run completed at `622.05` trades/s with final queues/DLQ at zero. Wallet insert attribution shows p95 `Match persisted -> Wallet settlement inserted = 2073.250ms`, `Wallet settlement inserted -> WALLET_SETTLED marker = 1172.450ms`, and `Wallet settlement inserted -> relay mark-SENT = 1483.760ms` | keep; Wallet is visible in the convergence cost, but it is not independently slower than Order apply |
| MatchEngine tryMatch outcome attribution | TPS99 10k run completed at `580.10` trades/s with final queues/DLQ at zero. `added_to_book` cost `20.594s / 10000`, `fully_matched` cost `29.333s / 10000`, and `reserve_order.redis_eval` cost `27.705s / 20000` | keep; the common Redis reserve-or-add path is a major integrated cost under full pressure |

## Current Bottleneck

The strongest current signal is DB and outbox write amplification:

- MatchEngine writes `TradeExecuted`, trade outbox rows, and completion marker rows.
- Order applies each trade to command-side order state and outbox/projection paths.
- Wallet settles each trade and relays settlement events back to MatchEngine.
- Completion requires both Order and Wallet markers to converge.

Increasing consumer concurrency alone has repeatedly failed to solve this class of problem. Several runs improved local queue drain but regressed full business TPS. The next useful work is targeted SQL/write-model review, not another broad concurrency increase.

The latest integrated stage-lag report makes the bottleneck more concrete: isolated DB SQL and isolated relay probes are fast, but under full service load the Order and Wallet marker paths take seconds to converge at p95. Wallet now has an immutable settlement insert timestamp for attribution. The latest 10k attribution run shows Wallet settlement insertion and Order trade application arrive at almost the same p95 latency from Match persistence, so the next optimization target should remain the integrated Match intake/trade persistence -> downstream apply/relay/marker pipeline rather than Wallet SQL alone.

MatchEngine was not cleared as "no longer relevant"; previous work cleared narrower hypotheses. Redis orderbook admission and isolated DB/relay probes are fast enough in isolation, but full `tryMatch` still combines two workloads: resting-order admission and incoming-order trade completion. TPS99 separates `added_to_book` from `fully_matched` and shows both outcomes grow under full pressure, with the shared Redis reserve-or-add Lua path dominating reserve time. The next target is MatchEngine intake/Redis orderbook semantics, not another broad concurrency increase.

## Correctness Gates

The current business gate requires:

- target `TradeExecuted` count reached;
- target Order command-side trade application reached;
- target Wallet settlement count reached;
- target completion marker count reached;
- RabbitMQ ready and unacked messages drained to zero;
- DLQ remains zero;
- duplicate and idempotency checks pass in focused tests.

Projection lag is diagnostic only. It is not included in the business gate because projections are rebuildable read models.

## Known Gaps

- The latest global E2E report does not yet publish API p95/p99 or end-to-end p95/p99 latency.
- The strongest 10k runs are short benchmark scenarios, not 30-minute soak claims.
- The latest 10k repeat has one invalid sample caused by local load-driver offered TPS, so the public summary uses valid-runs-only median/range.
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

Use this wording:

> I built a production-style Java/Spring Boot electricity trading platform and defined completed-trade TPS as TradeExecuted persistence plus Order application, Wallet settlement, completion-marker convergence, and final queue drain. After reducing Order and Wallet batch-path overhead, a 3-run 10k local benchmark sustained about 1999 offered order confirmations/s and reached a median fully gated throughput of 833.58 completed trades/s, with a 729.71-940.93 range and final queues/DLQ at zero. I also report orderbook admission and blended market-flow throughput separately to avoid mixing accepted input with completed business throughput.

Avoid this wording:

> The full system handles 2000 TPS.

That would mix accepted input pressure with completed business throughput.
