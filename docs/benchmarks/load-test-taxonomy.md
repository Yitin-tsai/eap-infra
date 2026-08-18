# EAP Load-Test Taxonomy

EAP uses multiple load-test contracts because different parts of the trading workflow answer different engineering questions. Do not compare their TPS numbers as if they were the same unit.

All contracts below exercise the CDA order/trade path. TDA uses separate auction events and currently has no equivalent public completion or capacity contract.

## Benchmark Contracts

| Contract | Status | Entry Point | What It Measures | What It Does Not Measure |
| --- | --- | --- | --- | --- |
| `order-admission-chain` | implemented | `scripts/load-test/run-order-admission-chain-10k.sh` | `Order API -> Order event store/outbox -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission` | trade execution, Order trade application, Wallet settlement |
| `matched-trade-completion-chain` | implemented | `scripts/load-test/run-matched-trade-completion-10k.sh` | seeded confirmed orders entering MatchEngine, `TradeExecuted` persistence, Order trade application, Wallet settlement, durable trade-ID set equality, and final measured queue drain | Order HTTP API, initial order submission persistence, Wallet reservation decision cost |
| `http-matched-trade-completion-chain` | implemented | `scripts/load-test/run-http-matched-trade-completion-10k.sh` | HTTP SELL admission followed by HTTP BUY matching, Match/Order/Wallet durable trade-ID equality, asset settlement, MatchEngine reservation cleanup, and final queue drain | isolated component ceilings; simultaneous mixed-side arrival patterns |
| `http-matched-steady-state-chain` | implemented | `scripts/load-test/run-http-matched-steady-state.sh` | sustained balanced, seeded, mixed-side HTTP traffic; steady accepted-order and completed-trade rates; queue backlog level/slope; three-service durable convergence; asset settlement; and final drain | side-imbalanced, cancellation-heavy, or multi-price market behavior; multi-node failover |
| `http-matched-staircase-chain` | implemented | `scripts/load-test/run-http-matched-staircase.sh` | one uninterrupted balanced, seeded, mixed-side HTTP run with progressively higher total order rates, per-stage throughput/latency/backlog gates, automatic knee detection, and final full-chain convergence | a long-duration guarantee at the provisional knee; side-imbalanced flow; multi-host load generation |
| `reservation-cleanup-isolated` | implemented diagnostic | `scripts/load-test/run-reservation-cleanup-ab.sh` | MatchEngine cleanup task claim, Redis reservation removal, completion update, and batch-size A/B using only Match PostgreSQL and Redis | HTTP admission, RabbitMQ scheduling, trade persistence, Order application, Wallet settlement, or full-chain capacity |
| `match-processor-combined-isolated` | implemented diagnostic | `scripts/load-test/run-match-processor-probe.sh` | shuffled mixed OrderConfirmed processing through the idempotency guard, Redis Lua matching, transactionally persisted trade/outbox/cleanup facts, and a separately timed cleanup drain using only Match PostgreSQL and Redis | RabbitMQ listener delivery/acknowledgement, concurrent cleanup contention, Order, Wallet, HTTP, or full-chain capacity |
| `rabbit-to-match-intake-isolated` | implemented diagnostic | `scripts/load-test/run-rabbit-match-intake-probe.sh` | paced shuffled mixed OrderConfirmed messages through real RabbitMQ publisher confirms, Match listener/acknowledgement, Redis matching, durable trade/outbox/cleanup writes, and concurrent cleanup using only RabbitMQ, Match PostgreSQL, and Redis | Match trade outbox relay, Order, Wallet, HTTP, cross-service completion, or full-chain capacity |
| `trade-consumer-fanout-isolated` | implemented diagnostic | `scripts/load-test/run-trade-consumer-fanout-probe.sh` | paced persistent TradeExecuted messages through real RabbitMQ fanout, Order batch application, Wallet single-event settlement, exact downstream trade-ID and asset reconciliation, and final queue drain using only Order, Wallet, RabbitMQ, and their PostgreSQL databases | Match trade outbox relay, Match persistence, Redis matching, HTTP admission, initial reservation, or full-chain capacity |
| `match-relay-downstream-isolated` | implemented diagnostic | `scripts/load-test/run-match-relay-downstream-probe.sh` | pre-seeded durable Match trade/outbox backlog through the real Match relay and RabbitMQ fanout into real Order/Wallet durable application, exact three-service trade IDs, assets, and final drain | HTTP admission, Wallet reservation, Order confirmation, Redis matching, Match trade persistence, simultaneous mixed-flow contention, or full-chain capacity |
| `rabbitmq-publish-only` | implemented diagnostic | `scripts/load-test/run-rabbitmq-publish-only-10k.sh` | RabbitMQ broker-confirmed input ceiling for persistent `OrderConfirmedEvent` messages | service processing, DB writes, matching, settlement |

Scripts named `run-global-matched-e2e*` are lower-level seed/project/run drivers used by the backend wrapper and isolated diagnostics. Their publisher fan-out and phase controls do not define additional public capacity contracts. Use the entry points in the table for comparable results.

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

The runner always shuffles BUY and SELL arrivals. Within each side, users rotate by actual send order so the workload does not create artificial per-user bursts that violate the normal Order API rate limit. `WORKLOAD_SEED` must be recorded with every result and changed across repeat runs. Sequential SELL-then-BUY behavior belongs to the separate upper-bound diagnostic and cannot be enabled in the mixed-flow capacity runner.

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

Current full HTTP capacity runners use one canonical runtime configuration: each service owns its settings in `application-loadtest.yml`, and normal recovery behavior remains enabled. The public runners do not switch listener concurrency, pools, outbox batching, projections, reservation recovery, or rate limiting. Historical reports retain `core-capacity` and `production-equivalent` labels only to describe the revisions that produced those artifacts; those profiles are no longer selectable and are not current capacity contracts.

The runner's fixed workers and in-flight limits are implementation details, not workload-selection controls. Changing service concurrency, pool size, outbox mode, cleanup behavior, rate limiting, arrival pattern, or BUY/SELL phase order creates a different experiment and must be done in a lower-level diagnostic with the override recorded explicitly.

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

## Experiment Promotion Ladder

Do not start every A/B experiment with the full sustained chain. That consumes the same host CPU, memory, database, broker, and monitoring budget as a capacity run, which can hide a small code effect behind host contention.

1. Run focused unit and integration tests for correctness.
2. Use the narrowest isolated diagnostic that exercises the proposed primary variable. For reservation cleanup batch sizing, run `scripts/load-test/run-reservation-cleanup-ab.sh`; it starts only Match PostgreSQL and Redis and labels its output `isolated-diagnostic` with `capacityClaimAllowed=false`.
3. If the component result is repeatable and materially different, run a short `2` to `5` minute full-chain A/B with light diagnostics. Reverse or alternate candidate order when cache warming could bias the second run.
4. Run the `15` or `30` minute full lifecycle, final queue drain, and cross-service correctness gates only for a candidate that survives the first three steps.
5. Repeat a different workload seed before promoting a result to the current sustained lower-bound evidence.

An isolated win can reject a weak candidate cheaply, but it cannot adopt a production setting or establish complete-trade TPS. A full-chain loss also overrides an isolated win because the component probe intentionally omits scheduler competition and downstream work.

## Next Benchmark Work

1. The canonical short-window recheck now has three valid staircase seeds: `600 orders/s` passed all three, while `624` passed two and failed one. Run a longer fixed-rate `624` candidate with a new seed before promoting it; the single short `648` pass is exploration evidence only.
2. Keep service concurrency and pool sizes fixed while capturing Order command-pool wait, HTTP latency, RabbitMQ ready/unacked, PostgreSQL/WAL, and system/process CPU. Reject runs with host starvation, broker alarms, HTTP count mismatch, or missing diagnostics.
3. Establish a passing 30-minute `http-matched-steady-state-chain` rate at or below the current release-pinned `600 orders/s` sustained class before testing a higher soak.
4. Add a separate imbalance contract for `60/40`, `40/60`, burst, residual-book, and partial-fill behavior. Do not weaken the balanced contract's exact completion gates to fit it.
5. Repeat the boundary run with the load generator on a separate CPU domain or host before attributing the final same-host knee to a service.
