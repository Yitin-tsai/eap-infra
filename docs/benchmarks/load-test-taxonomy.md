# EAP Load-Test Taxonomy

EAP uses multiple load-test contracts because different parts of the trading workflow answer different engineering questions. Do not compare their TPS numbers as if they were the same unit.

Artifact locations and the promotion checklist are defined in the
[benchmark evidence guide](README.md). Raw runner output under
`build/load-test-reports/` is local working data, not published evidence by itself.

All contracts below exercise the CDA order/trade path. TDA uses separate auction events and currently has no equivalent public completion or capacity contract.

## Benchmark Contracts

| Contract | Status | Entry Point | What It Measures | What It Does Not Measure |
| --- | --- | --- | --- | --- |
| `order-admission-chain` | implemented | `scripts/load-test/run-order-admission-chain-10k.sh` | `Order API -> Order event store/outbox -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission` | trade execution, Order trade application, Wallet settlement |
| `matched-trade-completion-chain` | implemented | `scripts/load-test/run-matched-trade-completion-10k.sh` | seeded confirmed orders entering MatchEngine, `TradeExecuted` persistence, Order trade application, Wallet settlement, durable trade-ID set equality, and final measured queue drain | Order HTTP API, initial order submission persistence, Wallet reservation decision cost |
| `http-matched-trade-completion-chain` | implemented | `scripts/load-test/run-http-matched-trade-completion-10k.sh` | HTTP SELL admission followed by HTTP BUY matching, Match/Order/Wallet durable trade-ID equality, asset settlement, MatchEngine reservation cleanup, and final queue drain | isolated component ceilings; simultaneous mixed-side arrival patterns |
| `http-matched-steady-state-chain` | implemented | `scripts/load-test/run-http-matched-steady-state.sh` | sustained balanced, seeded, mixed-side HTTP traffic; steady accepted-order and completed-trade rates; queue backlog level/slope; three-service durable convergence; asset settlement; and final drain | side-imbalanced, cancellation-heavy, or multi-price market behavior; multi-node failover |
| `http-cancellation-lifecycle` | implemented | `scripts/load-test/run-http-cancellation-lifecycle.sh` | deterministic HTTP cancellation through real RabbitMQ; open-order cancellation; partial-fill remainder cancellation; Match decision, Redis visibility, Order state, Wallet cancellation application/assets, trade-ID equality, outbox debt, queue/DLQ drain | cancellation throughput, broad randomized races, multi-node failover |
| `external-http-matched-steady-state-chain` | implemented diagnostic | `scripts/load-test/run-http-matched-external-open-loop.sh` | the same balanced mixed HTTP business path and final correctness gates, driven by a finite Vegeta open-loop schedule with workload preparation outside the traffic window | automatic CPU or host isolation; automatic promotion of current-worktree diagnostics to release-pinned capacity evidence |
| `http-matched-staircase-chain` | implemented | `scripts/load-test/run-http-matched-staircase.sh` | one uninterrupted balanced, seeded, mixed-side HTTP run with progressively higher total order rates, per-stage throughput/latency/backlog gates, automatic knee detection, and final full-chain convergence | a long-duration guarantee at the provisional knee; side-imbalanced flow; multi-host load generation |
| `reservation-cleanup-isolated` | implemented diagnostic | `scripts/load-test/run-reservation-cleanup-ab.sh` | MatchEngine cleanup task claim, Redis reservation removal, completion update, and batch-size A/B using only Match PostgreSQL and Redis | HTTP admission, RabbitMQ scheduling, trade persistence, Order application, Wallet settlement, or full-chain capacity |
| `match-processor-combined-isolated` | implemented diagnostic | `scripts/load-test/run-match-processor-probe.sh` | shuffled mixed OrderConfirmed processing through the idempotency guard, Redis Lua matching, transactionally persisted trade/outbox/cleanup facts, and a separately timed cleanup drain using only Match PostgreSQL and Redis | RabbitMQ listener delivery/acknowledgement, concurrent cleanup contention, Order, Wallet, HTTP, or full-chain capacity |
| `rabbit-to-match-intake-isolated` | implemented diagnostic | `scripts/load-test/run-rabbit-match-intake-probe.sh` | paced shuffled mixed OrderConfirmed messages through real RabbitMQ publisher confirms, Match listener/acknowledgement, Redis matching, durable trade/outbox/cleanup writes, and concurrent cleanup using only RabbitMQ, Match PostgreSQL, and Redis | Match trade outbox relay, Order, Wallet, HTTP, cross-service completion, or full-chain capacity |
| `trade-consumer-fanout-isolated` | implemented diagnostic | `scripts/load-test/run-trade-consumer-fanout-probe.sh` | seeded locked Wallet balances followed by paced persistent TradeExecuted messages through real RabbitMQ fanout, Order batch application, Wallet single-event settlement, exact downstream trade-ID and asset reconciliation, and final queue drain using only Order, Wallet, RabbitMQ, and their PostgreSQL databases | Match trade outbox relay, Match persistence, Redis matching, HTTP admission, reservation-decision cost, or full-chain capacity |
| `match-relay-downstream-isolated` | implemented diagnostic | `scripts/load-test/run-match-relay-downstream-probe.sh` | pre-seeded durable Match trade/outbox backlog through the real Match relay and RabbitMQ fanout into real Order/Wallet durable application, exact three-service trade IDs, assets, and final drain | HTTP admission, Wallet reservation, Order confirmation, Redis matching, Match trade persistence, simultaneous mixed-flow contention, or full-chain capacity |
| `rabbitmq-publish-only` | implemented diagnostic | `scripts/load-test/run-rabbitmq-publish-only-10k.sh` | RabbitMQ broker-confirmed input ceiling for persistent `OrderConfirmedEvent` messages | service processing, DB writes, matching, settlement |

Scripts named `run-global-matched-e2e*` are lower-level seed/project/run drivers used by the backend wrapper and isolated diagnostics. Their publisher fan-out and phase controls do not define additional public capacity contracts. Use the entry points in the table for comparable results.

## Source Provenance Contract

The full HTTP lifecycle runners distinguish experiment results from release-pinned
capacity evidence with `BENCHMARK_EVIDENCE_MODE`:

- `diagnostic` is the default. It permits an uncommitted experiment, preserves its
  business correctness and capacity-gate outcome, but always records
  `capacityClaimAllowed=false`.
- `release-pinned` fails before setup unless `eap-infra`, `eap-common`, `eap-order`,
  `eap-wallet`, and `eap-matchEngine` are present and clean. It captures them again
  after the run and rejects capacity eligibility if a commit or dirty state changed.

Every persisted full HTTP result includes a `benchmarkProvenance` object with full
repository commits, branch and dirty state, host OS/architecture/CPU/memory,
Java/Docker/Vegeta versions, load-generator placement, service launch mode,
diagnostics level, runner/library/Compose SHA-256 fingerprints, and the configured
plus resolved infrastructure container image IDs. It contains no JDBC, RabbitMQ,
SSH, or service credentials.

`validForSustainedCapacity` answers whether the measured business and backlog gates
passed. `capacityClaimAllowed` additionally requires a supported steady-state
contract, zero process failure, at least `60` seconds of warm-up and `900` seconds
of measurement, complete and stable release-pinned source fingerprints, and no
RabbitMQ resource alarm. `capacityEvidenceInvalidReasons` records which evidence
gate failed. One eligible artifact can contribute to a capacity claim; the promotion
ladder still requires another seed before changing a repeatable sustained boundary.

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

The steady-state runner supports a `prepared-sync` HTTP driver. Before the
traffic clock starts, it builds the seeded BUY/SELL schedule, deterministic
order IDs, user assignments, and serialized request bodies. During the measured
window it retains the existing bounded worker pool and synchronous HTTP
transport. This removes workload construction from the timed path without
changing the request protocol or bypassing any service. The prepared bodies
consume generator heap, and the generator still shares the host with the
services; this is lower measurement interference, not CPU or host isolation.

The canonical default remains `legacy-sync` so the accepted 15-minute 648
evidence stays reproducible. `prepared-sync` must be selected and recorded with
`HTTP_DRIVER_MODE=prepared-sync` until reverse-order repeats and a long-window
validation justify changing the contract default. Results from different driver
modes are not interchangeable. The staircase runner also retains the legacy
synchronous stage driver because its uninterrupted per-stage preparation
boundary has not yet been redesigned or validated.

The external open-loop driver separates the lifecycle into four explicit
steps. Java first resets/setup state and writes a finite, checksummed Vegeta
target file plus a secret-free manifest. A low-frequency Java monitor then
samples durable Match/Order/Wallet completion and RabbitMQ backlog while
Vegeta drives fixed-rate HTTP arrivals without waiting for a bounded response
permit. Finally, Java reads the Vegeta results and manifest, reconstructs the
steady window, and applies the existing trade-ID, asset, order-book,
reservation, queue, and DLQ gates.

The finite attack includes one second of EOF grace. Its JSON stream removes
only Vegeta's synthetic `no targets to attack` sentinel; the verifier still
requires one real result for every checksummed target. This avoids
rate-limiter rounding dropping final targets at higher rates.

The command is:

```bash
TARGET_ORDER_TPS=648 \
WARMUP_SECONDS=10 \
DURATION_SECONDS=30 \
DIAGNOSTICS_LEVEL=none \
bash scripts/load-test/run-http-matched-external-open-loop.sh
```

`VEGETA_CPUS`, `VEGETA_WORKERS`, and `VEGETA_MAX_WORKERS` bound the driver.
`SAMPLE_INTERVAL_SECONDS` controls the business monitor and must remain equal
across an A/B. The result records `LOAD_GENERATOR_PLACEMENT`; its default
`co-located` means the process still competes for the same laptop.

`remote-host` is an implemented placement, not a result label. The local
orchestrator checksums the prepared targets, copies only the secret-free target
file and helper over SSH, verifies the remote host can reach Order health, checks
clock skew, executes Vegeta remotely, and copies back a compressed result stream,
report, timing, and host preflight metadata. The Java monitor and final verifier
remain on the orchestrator host. A typical separated-driver run is:

```bash
LOAD_GENERATOR_PLACEMENT=remote-host \
REMOTE_DRIVER_SSH_TARGET=loadtest@192.0.2.20 \
ORDER_URL=http://192.0.2.10:8080/eap-order \
TARGET_ORDER_TPS=648 \
WARMUP_SECONDS=10 \
DURATION_SECONDS=30 \
DIAGNOSTICS_LEVEL=none \
bash scripts/load-test/run-http-matched-external-open-loop.sh
```

The remote host requires `vegeta`, `jq`, `gzip`, `curl`, and SSH access. The
Order URL must be reachable from both hosts and cannot use `localhost`.
`START_SERVICES=true` may still start the EAP services on the orchestrator host.
Use `START_SERVICES=false` and point the HTTP, JDBC, Redis, and RabbitMQ endpoints
at an already running stack when service lifecycle is managed elsewhere. In that
case, setup resets benchmark state by default; set `RESET_DATA_ON_PREPARE=false`
only when the operator has already provided an equivalent clean baseline.

Remote driver placement isolates HTTP generation from the service host; it does
not by itself prove multi-node service scaling, database scaling, or failover.
The remote and co-located runs are different evidence classes and require an A/B
with the same commit, seed, workload, duration, and correctness gates.
See the [distributed capacity and front-half scaling tooling report](2026-08-20-distributed-capacity-and-front-half-scaling.md).

This driver removes the in-JVM driver's response-permit ceiling and sharply
reduces generator CPU cost, but it does not reserve CPU for EAP services on
macOS. A same-seed legacy -> Vegeta -> legacy deep A/B at 648 orders/s found
the external driver throughput-equivalent within about 2.2%, while Vegeta used
about 7.9% of one CPU core. The comparison supports Vegeta as a lower-cost
diagnostic driver; it does not rewrite historical results or prove host
isolation. See the
[external open-loop report](2026-08-19-external-open-loop-driver.md) and the
[unattended validation](2026-08-20-vegeta-unattended-validation.md).

Current full HTTP capacity runners use one canonical runtime configuration: each service owns its settings in `application-loadtest.yml`, and normal recovery behavior remains enabled. The public runners do not switch listener concurrency, pools, outbox batching, projections, reservation recovery, or rate limiting. Historical reports retain `core-capacity` and `production-equivalent` labels only to describe the revisions that produced those artifacts; those profiles are no longer selectable and are not current capacity contracts.

The runner's fixed workers and in-flight limits are implementation details, not workload-selection controls. Changing the HTTP driver, service concurrency, pool size, outbox mode, cleanup behavior, rate limiting, arrival pattern, or BUY/SELL phase order creates a different experiment and must be done in a lower-level diagnostic with the override recorded explicitly.

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

`DIAGNOSTICS_LEVEL=none` disables the external runtime sampler; it does not disable the generator's business-progress monitor. That monitor reads RabbitMQ and runs exact durable-count queries against Match, Order, and Wallet at `SAMPLE_INTERVAL_SECONDS` intervals. The default remains `1` second for historical comparability. A resource-sensitive A/B can choose a larger interval, but must use the same interval on both sides and record it because backlog maxima and regression sampling then use a different observation contract.

## Experiment Promotion Ladder

Do not start every A/B experiment with the full sustained chain. That consumes the same host CPU, memory, database, broker, and monitoring budget as a capacity run, which can hide a small code effect behind host contention.

1. Run focused unit and integration tests for correctness.
2. Use the narrowest isolated diagnostic that exercises the proposed primary variable. For reservation cleanup batch sizing, run `scripts/load-test/run-reservation-cleanup-ab.sh`; it starts only Match PostgreSQL and Redis and labels its output `isolated-diagnostic` with `capacityClaimAllowed=false`.
3. If the component result is repeatable and materially different, run a short `2` to `5` minute full-chain A/B with light diagnostics. Reverse or alternate candidate order when cache warming could bias the second run.
4. Run the `15` or `30` minute full lifecycle, final queue drain, and cross-service correctness gates only for a candidate that survives the first three steps.
5. Repeat a different workload seed before promoting a result to the current sustained lower-bound evidence.

An isolated win can reject a weak candidate cheaply, but it cannot adopt a production setting or establish complete-trade TPS. A full-chain loss also overrides an isolated win because the component probe intentionally omits scheduler competition and downstream work.

### Front-half pool-budget diagnostic

`scripts/load-test/run-front-half-pool-budget-matrix.sh` prepares a coordinated
Order JDBC pool-budget experiment around `order-admission-chain`. Its fixed
profiles compare the current maximum allocation of `35 command + 20 consumer + 3
projection` connections with aggregate budgets of `48` and `40`. The primary
variable is the complete budget profile; individual pool changes must not be
attributed independently.

The script defaults to `--plan`. `--execute` performs two clean-start repeats per
profile and writes one matrix summary. This is a one-sided front-half contention
diagnostic: it can reject a poor budget, but it cannot adopt a full-chain setting,
prove horizontal scaling, or change the mixed HTTP capacity boundary. A surviving
candidate still requires a same-seed full-chain A/B and all durable correctness
gates.

## Next Benchmark Work

1. Keep `648 accepted orders/s` as the two-seed, 15-minute same-host sustained
   lower-bound class and treat it as a pressure boundary. The release-pinned
   20-minute 700 repeat supplied every request and converged exactly, but failed at
   `240.01 same-window trades/s` after a long drain.
2. Extend the business monitor with separate durable debt and slope for Order
   submission-to-reservation, reservation-to-confirmation, confirmation-to-Match,
   Match trade-to-relay, downstream Order/Wallet application, and reservation
   cleanup. RabbitMQ ready/unacked alone did not expose the 700 run's debt.
3. After that instrumentation is committed, use a short deep 700 diagnostic to
   capture Hikari, PostgreSQL wait/WAL, outbox, cleanup, and per-stage evidence.
   Do not pay for another 15-20 minute repeat until one stage has a testable
   bottleneck hypothesis.
4. Repeat a surviving boundary with a separate load-generator host. Co-located
   Vegeta reduces driver cost but does not isolate EAP from laptop CPU contention.
5. Add a separate imbalance contract for `60/40`, `40/60`, burst, residual-book,
   and partial-fill behavior. Do not weaken the balanced contract's exact
   completion gates to fit it.
