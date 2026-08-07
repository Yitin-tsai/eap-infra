**English** | **[中文](README.zh-TW.md)**

# EAP - Event-Driven Auction Platform for Electricity Markets

EAP is a production-style electricity market backend supporting Continuous Double Auction (CDA) and Timed Double Auction (TDA), built with Java / Spring Boot, RabbitMQ, PostgreSQL, and Redis Lua. The project focuses on completed-transaction throughput, transaction correctness, idempotent event processing, reliable outbox publishing, and operational observability rather than CRUD.

## Latest Benchmark Summary

> The project does not claim 2000 completed TPS. Its benchmark contracts separate scheduled HTTP input, accepted responses, RabbitMQ broker-confirmed input, isolated core operations, and fully business-gated completed trades. A completed-trade run is not valid unless Order / Wallet / MatchEngine durable trade ID sets are identical and final queues drain.
>
> The canonical capacity contract sends a seeded, shuffled, balanced BUY/SELL stream through the Order API and waits for reservation, matching, settlement, three-service convergence, and queue drain. Sequential phase and seeded backend results are reported separately because they use different starting conditions.
>
> Current capacity and full-lifecycle benchmark claims cover the CDA path only. TDA is implemented, but it has a different event contract and has not passed an equivalent published capacity and recovery campaign.

| Scenario | Offered Load | Completed / Core Throughput | Correctness Gate | Notes |
| --- | ---: | ---: | --- | --- |
| Latest shuffled mixed HTTP worktree regression, 2026-08-07 | `699.98 accepted orders/s` | `346.12 same-window`; `320.47 full-lifecycle trades/s` | `17500/17500` HTTP accepted; `8750` exact three-service trades; assets/queues/DLQ drained | 15-second, one-seed, same-host lower-bound diagnostic; not release-pinned or long-duration capacity |
| Sequential SELL-then-BUY 30K optimized diagnostic, TPS169 | `1299.71 SELL`, `1298.26 BUY accepted orders/s` | `922.38 BUY-triggered trades/s`; `530.43 full-lifecycle trades/s`; `1060.85 order convergence/s` | `30000` identical Match/Order/Wallet `trade_id` values + exact assets + final drain | Upper-bound workload with sell liquidity prepared before the measured BUY phase; not mixed capacity |
| Schema-v2 full HTTP 100K, 2026-08-04 | `999.90 SELL`, `991.35 BUY accepted orders/s` | `613.33 trades/s` after SELL readiness; `378.86 full-lifecycle trades/s` | `200000/200000` HTTP accepted + `100000` identical three-service `trade_id` values + exact assets + final drain | Reliability proof for that tested revision after its Wallet stable-lock fix; lower than the historical run and not a current-code capacity record |
| Historical full HTTP 100K validation, TPS168 | `999.95 SELL`, `999.84 BUY accepted orders/s` | `707.43 BUY-triggered trades/s`; `410.16 full-lifecycle trades/s` | `200000/200000` HTTP accepted + `100000` identical three-service `trade_id` values + exact assets + final drain | Strong scale-correctness evidence under the older measurement schema; throughput is conservative and is not the current capacity baseline |
| Legacy alternating HTTP staircase, TPS167 | `999.98 scheduled orders/s`, `999.83 accepted responses/s` | `511.85 completed trades/s` | `TradeExecuted` + Order applied + Wallet settled + identical three-service `trade_id` sets + final queue drain | Strict `SELL, BUY` pairing; retained for regression only |
| Redis matching core | N/A | `18,388.25 ops/s` | Redis Lua atomic matching | p50 `2.93ms`, p95 `5.39ms`, p99 `28.25ms` |
| TPS126 seeded contract-v2 diagnostic | `1,377.80 broker-confirmed input orders/s` | `1,234.47 completed trades/s` | identical `trade_id` sets across `trade_executions`, `order_trade_applications`, `trade_settlements` + final queue drain | Correctness passed, broker acks `10000/10000`, final queues / DLQ `0`, but not a valid 2000-input capacity run because broker-confirmed input did not reach the 95% offered-load threshold |
| RabbitMQ publish-only diagnostic, TPS126 | `1,994.98 broker-confirmed input orders/s` | N/A | persistent messages broker-acked, queue ready before purge matched target | Proves the load generator and RabbitMQ can confirm near-2000/s when service processing is removed; diagnostic only |
| Previous local 10k business-gated repeat, TPS93 | median `1,999.22 client-side input attempts/s` | median `833.58 completed trades/s` | count-based durable facts + legacy marker gate + final queue drain | Useful performance-improvement history, but superseded by contract-v2 broker-confirmed input semantics |
| Pinned public 10k repeat, 2026-07-13 | median `1,998.94 client-side input attempts/s` | median `582.73 completed trades/s` | count-based durable facts + legacy marker gate + final queue drain | 4/5 valid runs under the older benchmark contract |
| TPS169 same-contract A/B | `1300 orders/s` per sequential phase | BUY-triggered completion `664.26 -> 922.38 trades/s` | both runs passed exact three-service IDs, assets, and drain gates | Batched reservation cleanup reduced completion SQL from `30000` per-trade updates to about `32` batch statements; max backlog `14110 -> 6261`, Match-to-Wallet p95 `13.624s -> 4.478s` |

See [the 2026-08-07 canonical mixed diagnostic](docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md), [the Wallet and repeated-capacity report](docs/benchmarks/2026-08-05-wallet-settlement-robustness.md), [the balanced mixed staircase report](docs/benchmarks/2026-08-04-balanced-mixed-http-staircase.md), [docs/performance-report.md](docs/performance-report.md), and [the full HTTP 100K report](docs/benchmarks/2026-08-03-full-http-100k.md). The raw engineering log is frozen under [docs/archive/performance/2026-06-global-loadtest-2000-tps.md](docs/archive/performance/2026-06-global-loadtest-2000-tps.md).

## Workload Semantics

- EAP has separate benchmark contracts:
  - `order-admission-chain` (implemented): `Order API -> Wallet reservation -> OrderConfirmedEvent -> MatchEngine orderbook admission`.
  - `matched-trade-completion-chain` (implemented): seeded confirmed orders enter MatchEngine, then the benchmark waits for MatchEngine, Order, and Wallet durable trade completion.
  - `http-matched-trade-completion-chain` (implemented): BUY/SELL use HTTP and the verifier waits for durable convergence and queue drain.
  - `http-matched-steady-state-chain` (implemented): warmup plus a fixed-rate full HTTP measurement window with backlog trend gates.
  - `http-matched-staircase-chain` (implemented): progressively increases full HTTP order rate to find the first unsustainable stage.
  - `rabbitmq-publish-only` (implemented diagnostic): isolates broker-confirmed input capacity.
- Seeded and full HTTP results use different starting boundaries and must not be compared as the same workload.
- One expected completed trade requires matched buy/sell-side processing plus downstream Order and Wallet consumers.
- `EVENTS=10000` means the run expects `10000` completed trades after the seeded sell-side liquidity is prepared.
- Input pressure is reported in two layers:
  - `businessInputAttemptedOrderTps`: client-side publish attempts during the scheduled BUY send window.
  - `businessInputBrokerAckedOrderTps`: BUY messages confirmed by RabbitMQ publisher confirms over the full confirm window.
- Business timing ends only after MatchEngine, Order, and Wallet durable facts converge and measured RabbitMQ queues drain to zero.

Business E2E TPS formula:

```text
businessCompletedTradeTps =
  completedTrades /
  (max(durableTradeFactConvergedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)
```

The current benchmark also reports:

- `orderbookAdmissionTps`: resting SELL confirmations admitted into Redis order book.
- `businessInputAttemptedOrderTps`: scheduled client-side BUY publish attempts/s.
- `businessInputBrokerAckedOrderTps`: RabbitMQ-confirmed BUY input/s.
- `businessCompletedTradeTps`: fully correctness-gated completed trades.
- `blendedMarketFlowTps`: total SELL+BUY order confirmations processed across the full two-phase benchmark window.

`DURATION_SECONDS=5` is the scheduled BUY publish window. It is not the completed-business timing window. In the TPS126 diagnostic run, the business completion window was `8.10s`, so `10000 / 8.10 ~= 1234.47 completed trades/s`.

## Benchmark Environment

| Item | Current Local Benchmark Environment |
| --- | --- |
| Machine | MacBook Pro, Apple M5, 10 cores, 16 GB RAM |
| OS | macOS 26.5.1 |
| Docker | Docker 29.5.3 |
| JDK | Temurin OpenJDK 21.0.10 |
| PostgreSQL | `postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647`, three service-owned DB containers, `pg_stat_statements` enabled |
| RabbitMQ | `rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281` |
| Redis | `redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99`, append-only disabled for load-test profile |
| Load generator | runs on the same local machine as services and containers |

Official benchmark claims should cite the machine-readable snapshot generated by `scripts/load-test/collect-benchmark-snapshot.sh`, including infra, Order, Wallet, MatchEngine, and Common commits. The 2026-08-04 schema-v2 revision passed every 100K correctness gate, but it reached `613.33 trades/s` after SELL readiness, below the historical 100K result. Later Wallet changes mean it is no longer a current-code validation. The 30-minute 900 orders/s run has now been executed and failed the completion gate; the repository still needs a repeated 100K set, a passing lower-rate soak, and an external load generator before any result can be treated as an externally reproducible long-duration claim.

## What The System Does

EAP simulates an electricity trading market through two market modes. CDA continuously reserves and matches individual orders; TDA collects stepped bids during a session and clears them together at a scheduled time.

Core flow:

```text
Order API
  -> Order Service append command event + outbox
  -> Wallet Service reserves assets
  -> MatchEngine matches orders with Redis ZSET + Lua
  -> MatchEngine persists TradeExecuted + outbox + deferred cleanup task atomically
  -> Order Service applies trade result
  -> Wallet Service settles trade
  -> Benchmark verifies the same trade IDs exist in MatchEngine, Order, and Wallet durable tables
```

See [docs/architecture.md](docs/architecture.md) for the full architecture overview.

The TDA path is implemented across Order, Wallet, and MatchEngine, but its Order bid submission and MatchEngine auction lifecycle publications currently bypass a transactional outbox. Wallet bid redelivery idempotency, reservation rejection feedback, and whole-auction convergence also remain open. TDA is therefore documented as a functional capability with reliability gaps, not as part of the CDA capacity claims above.

## Core Engineering Problems

- Separating accepted throughput, core matching throughput, and business completed throughput.
- Preserving idempotent side effects under RabbitMQ at-least-once delivery through unique constraints, transaction boundaries, manual ACK, and DLX/DLQ.
- Using transactional outbox to avoid a successful DB commit with a lost integration event.
- Using Redis Lua to keep order book add / match / partial fill operations atomic.
- Measuring projection lag separately from command-side business completion.
- Using PostgreSQL stats, RabbitMQ queue metrics, and application timers to identify DB write amplification and outbox relay cost.

## Service Boundaries

| Service | Ownership | Primary Responsibility |
| --- | --- | --- |
| `eap-order` | Order and auction command lifecycle | CDA order event stream/application; TDA bid entry and result view |
| `eap-wallet` | Wallet balance and settlement | CDA/TDA reservation, CDA trade settlement, TDA auction settlement, wallet outbox |
| `eap-matchEngine` | Matching and auction clearing | CDA Redis order book and `TradeExecuted`; TDA bid collection, scheduling and clearing |
| `eap-common` | Shared contracts | DTOs, events, shared integration contracts |
| `eap-mcp` / `eap-ai-client` | Control-plane extension | backend tools for controlled AI-agent experiments |
| `eap-trigger` | Legacy side experiment | Go conditional-order module; still consumes retired `order.matched` and is not integrated with the current core flow |

## Reliability Model

- Message delivery: RabbitMQ at-least-once.
- Publish reliability: CDA transitions that emit integration events use a transactional outbox; terminal Order/Wallet trade application emits no completion callback. The current TDA direct-publication exceptions are documented architecture gaps.
- Consumer safety: idempotency tables / unique keys / local DB transactions.
- Completion definition: a trade is business-complete only after MatchEngine has `TradeExecuted`, Order has applied the trade, Wallet has settled it, all three services contain the same completed `trade_id` set, and measured queues drain.
- Read models: projections are rebuildable and measured as lag, not used as the command-side source of truth.
- Completion feedback: Order and Wallet do not publish per-trade completion callbacks; external verification compares service-owned durable facts.

## AI-Assisted Engineering Workflow

EAP uses bounded AI roles to turn engineering questions into falsifiable hypotheses, not to delegate architecture, risk, deployment, or public claims. Each change moves through an explicit baseline, controlled implementation, tests, observability evidence, correctness gates, review, and a human adopt/reject decision; rejected experiments remain part of the evidence.

See the [evidence-driven AI engineering workflow](docs/ai-engineering-workflow.md) and the [Hello World Dev Conference 2026 EAP case study](docs/talks/hello-world-dev-conference-2026-case-study.md).

## Reproduce Locally

```bash
make dev-env
make dev-up
make run-all
```

Build and test:

```bash
make build
make test
```

Focused load-test scripts live under [scripts/load-test/](scripts/load-test/). The 2000 TPS investigation currently uses:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=none MIN_OFFERED_TPS_RATIO=0.95 \
REPEATS=5 bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_YYYYMMDD
```

The direct `matched-trade-completion-chain` entrypoint is:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-matched-trade-completion-10k.sh GLT_MATCHED_TRADE_COMPLETION_10K
```

The full HTTP staircase entrypoint is:

```bash
START_ORDER_TPS=700 END_ORDER_TPS=1100 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
WORKLOAD_SEED=20260804 \
bash scripts/load-test/run-http-matched-staircase.sh
```

The full HTTP runners always use shuffled mixed arrivals and the service-owned `loadtest` configuration. Worker counts, runtime profiles, and phase ordering are intentionally not public capacity switches; lower-level component scripts remain available for isolated diagnostics.

RabbitMQ input ceiling is measured separately:

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
bash scripts/load-test/run-rabbitmq-publish-only-10k.sh GLT_RABBITMQ_PUBLISH_ONLY_10K
```

See [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) for the benchmark boundary definitions.

See [DEV-GUIDE.md](DEV-GUIDE.md) for local service operations.

## Current Validation Gaps

- MatchEngine now isolates trade-outbox polling from reservation maintenance. The same-seed A/B materially improved the 800-stage backlog and completion metrics, but later repeats did not make 800 a stable capacity point, so the public mixed-flow lower bound remains 700 orders/s.
- Reservation recovery now correlates Redis state to an exact durable `tradeId`. A stale cleanup cannot release or delete a newer reservation for the same order; the post-fix 52,500-order staircase passed exact three-service convergence with zero final DLQ or reservation debt.
- The full HTTP staircase includes HTTP histogram bounds but not end-to-end per-trade p95/p99 latency.
- The latest `1300 accepted orders/s` result uses sequential SELL and BUY phases on a single machine; it is not a mixed-flow or 30-minute soak claim.
- The current safe Wallet transaction boundary passed a short mixed `700 total orders/s` regression. Two current-code `900 orders/s` repeats converged correctly but were not repeatably sustainable; the older three-seed 900 result used the subsequently rejected autocommit boundary.
- A clean current-code 15-minute 700 orders/s same-host soak passed. Additional seeds and an external load generator are still required before treating it as a production SLA.
- Load generator, services, and containers share one machine; an external load-generator repeat is still required to remove shared-CPU interference.
- The `922.38 trades/s` 30K result is a sequential upper-bound diagnostic with sell-side liquidity prepared before the measured BUY phase; it is not the mixed-flow capacity value.
- The 2026-08-04 schema-v2 100K revision passed all correctness gates but was slower than the historical 100K run; later Wallet changes require fresh validation before changing the capacity baseline.
- Historical seeded steady-state runs are not substitutes for a full HTTP steady-state contract.
- The benchmark result artifact is local under `build/load-test-reports/`; it still needs to be published or attached to a release for third-party reproduction.
- Raw reports are ignored build artifacts. Preview the retention policy with `bash scripts/load-test/prune-loadtest-reports.sh`; set `DRY_RUN=false` only after curated result JSON has been copied to `docs/benchmarks/results/`.
- Failure-injection coverage should be summarized separately for duplicate delivery, consumer restart, outbox retry, DLQ, and projection replay.

The public benchmark runbook is tracked in [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md).

## Reading Order

1. [docs/architecture.md](docs/architecture.md) - current system boundaries, event flow, and retired completion feedback loop.
2. [docs/ai-engineering-workflow.md](docs/ai-engineering-workflow.md) - role contracts, evidence gates, and real adopted/rejected experiments.
3. [docs/talks/hello-world-dev-conference-2026-case-study.md](docs/talks/hello-world-dev-conference-2026-case-study.md) - how EAP uses AI roles for self-review, feature expansion, and evidence-based decisions.
4. [docs/benchmarks/load-test-taxonomy.md](docs/benchmarks/load-test-taxonomy.md) - benchmark boundary definitions.
5. [docs/performance-report.md](docs/performance-report.md) - benchmark definitions, latest results, and bottlenecks.
6. [docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md](docs/benchmarks/2026-08-07-canonical-mixed-http-diagnostic.md) - current-worktree 700/800 diagnostic and scheduler-contention evidence.
7. [docs/benchmarks/2026-07-public-benchmark.md](docs/benchmarks/2026-07-public-benchmark.md) - pinned public benchmark plan.
8. Service READMEs: [Order](https://github.com/Yitin-tsai/eap-order), [Wallet](https://github.com/Yitin-tsai/eap-wallet), [MatchEngine](https://github.com/Yitin-tsai/eap-matchEngine), [MCP](https://github.com/Yitin-tsai/eap-mcp), [AI Client](https://github.com/Yitin-tsai/eap-ai-client), [Common](https://github.com/Yitin-tsai/eap-common), [Trigger](eap-trigger/README.md).

The frozen detailed experiment history is available under `docs/archive/performance/` but is not part of the normal reading path.
