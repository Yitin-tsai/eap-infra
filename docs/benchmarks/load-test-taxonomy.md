# EAP Load-Test Taxonomy

EAP uses multiple load-test contracts because different parts of the trading workflow answer different engineering questions. Do not compare their TPS numbers as if they were the same unit.

## Benchmark Contracts

| Contract | Status | Entry Point | What It Measures | What It Does Not Measure |
| --- | --- | --- | --- | --- |
| `order-admission-chain` | implemented | `scripts/load-test/run-order-admission-chain-10k.sh` | `Order API -> Order event store/outbox -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission` | trade execution, Order trade application, Wallet settlement |
| `matched-trade-completion-chain` | implemented | `scripts/load-test/run-matched-trade-completion-10k.sh` | seeded confirmed orders entering MatchEngine, `TradeExecuted` persistence, Order trade application, Wallet settlement, durable trade-ID set equality, and final measured queue drain | Order HTTP API, initial order submission persistence, Wallet reservation decision cost |
| `http-matched-trade-completion-chain` | implemented | `scripts/load-test/run-http-matched-trade-completion-10k.sh` | HTTP SELL admission followed by HTTP BUY matching, Match/Order/Wallet durable trade-ID equality, asset settlement, MatchEngine reservation cleanup, and final queue drain | isolated component ceilings; simultaneous mixed-side arrival patterns |
| `http-matched-steady-state-chain` | implemented | `scripts/load-test/run-http-matched-steady-state.sh` | sustained balanced, seeded, mixed-side HTTP traffic; steady accepted-order and completed-trade rates; queue backlog level/slope; three-service durable convergence; asset settlement; and final drain | side-imbalanced, cancellation-heavy, or multi-price market behavior; multi-node failover |
| `http-matched-staircase-chain` | implemented | `scripts/load-test/run-http-matched-staircase.sh` | one uninterrupted balanced, seeded, mixed-side HTTP run with progressively higher total order rates, per-stage throughput/latency/backlog gates, automatic knee detection, and final full-chain convergence | a long-duration guarantee at the provisional knee; side-imbalanced flow; multi-host load generation |
| `rabbitmq-publish-only` | implemented diagnostic | `scripts/load-test/run-rabbitmq-publish-only-10k.sh` | RabbitMQ broker-confirmed input ceiling for persistent `OrderConfirmedEvent` messages | service processing, DB writes, matching, settlement |

## Implemented Contracts

### `order-admission-chain`

The order-admission benchmark sends one-sided HTTP limit orders through the public Order API, then waits for:

- HTTP acceptance from Order;
- `OrderSubmissionRequestedV1` in the Order event store;
- `OrderAssetReservationConfirmedV1` in the Order event store, proving Wallet reservation completed and Order consumed the confirmation;
- the expected side's Redis orderbook count in MatchEngine;
- measured RabbitMQ ready/unacked queues and DLQ drained to zero.

It intentionally uses one-sided orders so the workload measures orderbook admission without forcing trade execution.

### `matched-trade-completion-chain`

The current 10k TPS work uses `matched-trade-completion-chain`.

It prepares valid Order and Wallet state, publishes confirmed SELL orders to the MatchEngine order book, then publishes confirmed BUY orders into the same MatchEngine queue. A trade is counted only after:

- MatchEngine persisted the `TradeExecuted` fact;
- Order persisted its durable trade-application fact;
- Wallet persisted its durable settlement fact;
- the three service-owned durable trade-ID sets are identical;
- measured RabbitMQ ready/unacked queues drained to zero.

This is intentionally a backend hot-path benchmark. It is not a public API lifecycle benchmark.

### `http-matched-trade-completion-chain`

This benchmark registers buyer and seller wallets through HTTP, then sends both sides through the public Order API. SELL orders are sent first and must converge to confirmed resting orders before the BUY phase begins. This produces deterministic one-to-one trades while keeping both sides on the real HTTP, event-store, reservation, matching, and settlement path.

A run is valid only after:

- all SELL and BUY requests were accepted without `429`, `503`, or other HTTP failures;
- both sides persisted submission, Wallet reservation, and Order confirmation facts;
- MatchEngine, Order, and Wallet contain the same complete `trade_id` set;
- buyer and seller asset deltas match the executed price and quantity, with all locks released;
- both Redis order books and all MatchEngine reservations are empty;
- all measured RabbitMQ ready/unacked queues and the DLQ are zero.

The result reports two non-interchangeable throughput values:

- `buyTriggeredTradeCompletionTps` starts at the BUY phase after SELL orders are resting;
- `businessHttpMatchedTradeCompletionTps` includes SELL HTTP submission, SELL admission, BUY HTTP submission, three-service convergence, settlement, and final drain.

### `http-matched-steady-state-chain`

This contract answers whether the full system can sustain continuous matched traffic without a growing queue. It creates equal BUY and SELL populations, shuffles their HTTP arrival order with a reproducible seed, and sends the resulting mixed stream at a target expressed as total orders per second. One eventual trade therefore requires two units of offered load.

`ARRIVAL_PATTERN=shuffled` is the canonical capacity workload. `WORKLOAD_SEED` must be recorded with every result and changed across repeat runs. `ARRIVAL_PATTERN=alternating` preserves the former `SELL, BUY` sequence only for regression comparison; it is not the default capacity claim.

The standard local profile uses:

- `60` seconds of warm-up;
- `1800` seconds of measured traffic;
- `300` total orders/s, equivalent to a target of `150` completed trades/s;
- one-second business samples and five-second host diagnostics.

In addition to final correctness and drain gates, a sustained run is valid only when:

- measured HTTP input reaches at least `95%` of target;
- measured completed-trade rate reaches at least `95%` of the target order rate divided by two;
- aggregate queue backlog stays below the configured ceiling;
- linear queue backlog growth stays below the configured messages/s ceiling;
- per-second RabbitMQ management samples are readable throughout the steady window.

Registered load-test wallets are funded during setup according to the planned run length. Registration and funding are outside the measurement window; every measured order, reservation, match, trade application, and settlement still uses the real service path.

The runner also records one of these runtime profiles:

- `core-capacity` uses the optimized load-test listener, batch, pool, and completion-view settings. It locates an implementation ceiling but is not a production-profile claim.
- `production-equivalent` retains local split databases and quiet load-test logging while restoring the normal application defaults for transaction pools, listeners, batching, outbox polling, completion-view writes, and reconcilers.
- `custom` leaves runtime tuning to explicitly supplied environment variables and must be reported with its configuration overrides.

`production-equivalent` is a local configuration comparison, not evidence of a deployed cloud topology. Results from different runtime profiles are not interchangeable.

### `http-matched-staircase-chain`

This contract locates the full HTTP chain's sustained-capacity knee without restarting services or clearing data between rates. Each phase uses the same balanced seeded shuffle as the steady-state contract. The default profile runs from `100` to `2000` total orders/s in increments of `100`. Each stage has `30` seconds of warm-up followed by `60` seconds of measurement, for a nominal 30-minute run if every stage passes.

Each stage reports:

- request scheduling TPS, accepted-response TPS, response drain tail, and offered-load ratio;
- completed trade TPS and completion-target ratio;
- HTTP p50/p95/p99 upper bounds;
- queue backlog start, end, maximum, and linear regression slope;
- an explicit pass/fail reason list.

The default runner stops after the first failed stage, then waits for all traffic already accepted to converge. A usable capacity-search result still requires exact Match/Order/Wallet trade-ID equality, exact aggregate asset deltas, empty order books and reservations, and final RabbitMQ ready/unacked plus DLQ drain.

Queue growth is treated as sustained debt only when both the regression and net-growth rates exceed the configured limit and the net increase is larger than one second of offered load. This prevents a short RabbitMQ sampling spike from being mislabeled as a capacity knee; the independent maximum-backlog ceiling still rejects large oscillations.

`END_ORDER_TPS` can be raised above `2000`. Because each trade consumes one SELL and one BUY, a stage target of `2000` total orders/s means a target of `1000` completed trades/s.

The load driver uses fixed open-loop deadlines. A late scheduler wake-up does not move later deadlines, so timer oversleep cannot accumulate into artificial offered-load drift. `ORDER_URL`, `WALLET_URL`, the three JDBC URLs, Redis, and RabbitMQ management endpoints are environment-configurable for a separate load-generator host. For a remote run, disable local service lifecycle and local Docker assertions; collect host diagnostics on the service host separately.

## Next Benchmark Work

1. Re-establish the staircase knee with `ARRIVAL_PATTERN=shuffled` across at least three seeds under `core-capacity`.
2. Repeat the same seed and rates under `production-equivalent` to quantify the cost of normal completion and recovery behavior.
3. Confirm the lower repeated knee with `http-matched-steady-state-chain` for 30 minutes.
4. Add a separate imbalance contract for `60/40`, `40/60`, burst, residual-book, and partial-fill behavior. Do not weaken the balanced contract's exact completion gates to fit it.
5. Repeat the knee run with the load generator on a separate CPU/host before attributing the same-host offered-load failure to a service.
