# Feature: 2000 TPS Global E2E Load-Test Challenge

## Goal

Challenge the EAP trading flow toward 2000 fully completed trades/s by isolating Order, Wallet, and MatchEngine PostgreSQL databases, then measuring the full `MatchEngine -> TradeExecuted -> Order/Wallet -> completion` path.

This is not a pure publish-rate test. A run is only successful when messages are consumed, outboxes drain, completion state is correct, and final database invariants hold.

## Current Baseline

Evidence from `docs/order-wallet-e2e-load-test.md`:

- Short Order → Wallet HTTP test reached about 1000 accepted orders/s after increasing Order Hikari pool and reducing per-order logging.
- A 10-minute 1000 TPS soak sustained about 618 accepted orders/s because Order Hikari saturated (`20 / 20 active`, pending peak around `109`).
- Wallet queue/outbox drained successfully; data correctness held with no duplicate order IDs and no negative wallets.
- Initial audit direct insert reduced one lookup, but Order still had pool pressure because follow-up audit events still need lookup + insert.

Existing load-test infra:

- `docker-compose.loadtest.yml` already provides separate Postgres containers:
  - Order: `localhost:15432/eap_order_db`
  - Wallet: `localhost:15433/eap_wallet_db`
  - MatchEngine: `localhost:15434/eap_match_db`
- `application-loadtest.yml` exists for Order, Wallet, and MatchEngine.
- `MatchedE2eLoadGenerator` already accepts separate `--order-jdbc-url`, `--wallet-jdbc-url`, and `--match-jdbc-url` defaults.

## Target Definition

Primary target:

```text
2000 fully completed matched trades/s
```

Minimum evidence:

- Trade execution created in MatchEngine.
- Trade event published and consumed by Order and Wallet.
- Wallet settlement completed.
- Order command-side state updated.
- Completion view/reconciliation marks the trade complete.
- RabbitMQ queues drain to zero or expected steady-state floor.
- Outbox pending/failed return to zero after drain window.
- Order projection/read model catch-up is measured separately as lag; it is not part of the hot-path business TPS gate.

Secondary targets:

- Ramp target: 500 → 1000 → 1500 → 2000 completed trades/s.
- Soak target: sustain the highest stable step for 10 minutes.
- Recovery target: no duplicate settlement or incorrect completion after duplicate/retry events.

## Scrum Backlog

### Epic 0: Spec and Measurement Boundary

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-00-01 | Define exact TPS metric and completion boundary | Architect + Performance | Document whether the target is matched trades/s or completed settlements/s; define success/failure counters | None |
| TPS-00-02 | Map full E2E event flow for matched trade completion | Architect | Flow includes MatchEngine, Order, Wallet, outboxes, RabbitMQ queues, completion/reconciler | TPS-00-01 |
| TPS-00-03 | Define load-test invariant queries | QA | SQL/checklist covers executions, settlements, status updates, completion, duplicate IDs, negative balances, DLQ | TPS-00-02 |

### Epic 1: Load-test Infrastructure Readiness

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-01-01 | Verify three Postgres loadtest containers are cleanly started and migrated | Implementation Lead | All three services boot with `loadtest` profile and run Liquibase against their own DB | TPS-00-01 |
| TPS-01-02 | Audit cleanup/truncate logic for cross-DB assumptions | Implementation Lead + QA | Generator cleanup only touches the correct DB; no shared-DB assumption remains | TPS-01-01 |
| TPS-01-03 | Add a reproducible environment reset command or runbook | Implementation Lead | Docs include commands for compose up/down, volume reset decision, service boot order | TPS-01-01 |

### Epic 2: Global E2E Load Generator

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-02-01 | Inspect `MatchedE2eLoadGenerator` for correctness under three DBs | Implementation Lead | Confirms defaults and CLI args match `15432/15433/15434`; fixes any hardcoded shared DB | TPS-01-02 |
| TPS-02-02 | Add final correctness summary to generator output if missing | Implementation Lead + QA | Output includes executions, order updates, wallet settlements, completion counts, DLQ, queue depth, outbox pending/failed | TPS-02-01 |
| TPS-02-03 | Add RabbitMQ queue sampling during run | Performance | Captures ready/unacked for trade/order/wallet/completion queues at interval that does not overload broker | TPS-02-01 |

### Epic 3: Baseline and Ramp

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-03-01 | Run smoke test | QA + Implementation Lead | Small run completes with zero DLQ, zero outbox failed, correct final counts | TPS-02-02 |
| TPS-03-02 | Run 500 TPS baseline | Performance | Records throughput, p95/p99, pool active/pending, queue peak, drain time | TPS-03-01 |
| TPS-03-03 | Run 1000 TPS baseline | Performance | Same metrics captured; compare against previous Order → Wallet 1000 TPS data | TPS-03-02 |
| TPS-03-04 | Run 1500 TPS ramp | Performance | Identify first bottleneck and whether it is Order, Wallet, MatchEngine, RabbitMQ, Redis, or generator | TPS-03-03 |
| TPS-03-05 | Attempt 2000 TPS run only if 1500 TPS is stable or known bottleneck is acceptable | Performance | Run result is accepted or rejected with evidence | TPS-03-04 |

### Epic 4: Bottleneck Analysis

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-04-01 | Build write-amplification table per completed trade | Performance | Counts DB writes/reads across MatchEngine, Order, Wallet, outbox, completion, audit | TPS-03-02 |
| TPS-04-02 | Identify DB pool and lock contention | Performance | Uses Hikari active/pending, PostgreSQL activity, slow query/stage timers where available | TPS-03-02 |
| TPS-04-03 | Identify MQ bottleneck | Performance | Uses queue ready/unacked, publish confirm latency, consumer concurrency, prefetch, DLQ | TPS-03-02 |
| TPS-04-04 | Propose next tuning story | Architect + Performance | Tuning is task-sized and preserves domain correctness | TPS-04-01 |

### Epic 5: QA and Reviewer Gates

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-05-01 | Duplicate/retry event test | QA | Duplicate trade or settlement events do not double-settle or double-complete | TPS-03-01 |
| TPS-05-02 | Out-of-order completion test | QA | Completion logic handles Order-before-Wallet and Wallet-before-Order arrival | TPS-03-01 |
| TPS-05-03 | Crash/drain recovery check | QA | After service restart, outbox/reconciler drains without data loss | TPS-03-01 |
| TPS-05-04 | Production-style review | Reviewer | Blockers/non-blockers documented; no acceptance without correctness evidence | TPS-05-01 |

### Epic 7: Completion Marker Convergence Bottleneck

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-07-01 | Review completion-marker ownership and consistency boundary | Architect | Confirms MatchEngine owns `trade_completion_view`; Order/Wallet only emit completion markers; no service reads another service DB as source of truth | TPS-03-04 |
| TPS-07-02 | Build completion-marker cost model | Performance | Documents per-trade writes for `TradeExecuted`, `OrderTradeApplied`, `WalletTradeSettled`, and `completed_at` convergence | TPS-07-01 |
| TPS-07-03 | Add completion marker listener tuning in loadtest profile | Implementation Lead | Explicitly configures `eap.match-engine.listeners.order-trade-applied.concurrency` and `wallet-trade-settled.concurrency`; rerun 1500 and compare queue peaks | TPS-07-02 |
| TPS-07-04 | Add/verify completion-marker observability | Performance + QA | Result output includes completion queues, delayed count, completion lag, and final incomplete count | TPS-07-03 |
| TPS-07-05 | Decide whether SQL write model needs optimization | Architect + Performance | Only proceed to code/model change if listener tuning does not reduce `maxOrderTradeAppliedQueueReady` and completion lag | TPS-07-04 |
| TPS-07-06 | Run guarded 1500/2000 comparison | QA + Performance | 1500 remains PASS with final queues/DLQ `0`; 2000 attempt is accepted or rejected with explicit bottleneck evidence | TPS-07-03 |

### Epic 8: Projection Lag Observability Boundary

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-08-01 | Split business TPS gate from Order projection lag | QA + Implementation Lead | Load generator accepts business completion through command-side facts, queue ack drain, Wallet settlement, and completion view; `orders_current` is reported as lag only | TPS-03-01 |
| TPS-08-02 | Fix projection schema mismatch exposed by long loadtest market IDs | Implementation Lead | `orders_current.market_id` accepts current loadtest identifiers; no projection `value too long` error remains | TPS-08-01 |
| TPS-08-03 | Add projection lag metrics to result output | QA + Performance | Result includes `projectionIncludedInBusinessGate=false`, projection caught-up seconds, stale rows, completion ratio, and stale ratio | TPS-08-02 |

## Architect Review

Initial decision: Conditional.

The ticket is valuable, but the spec must keep the target as end-to-end completion TPS, not message publish TPS. The source of truth should remain service-owned:

- MatchEngine owns trade execution and completion tracking.
- Order owns order status/projection/audit.
- Wallet owns reservation and settlement.
- RabbitMQ transports events; it is not the source of truth.

Must-fix before coding:

- [ ] Confirm whether 2000 TPS means completed matched trades/s or accepted orders/s.
- [ ] Confirm which table/view is authoritative for completion.
- [ ] Confirm generator cleanup is safe across three DBs.
- [ ] Confirm completion accepts eventual consistency and measures drain time.

## Performance Review

Initial hypothesis:

1. Order audit/status update is likely to remain a bottleneck if every completed trade creates multiple audit writes.
2. Wallet settlement can become the next bottleneck when trade completion rate exceeds previous Order → Wallet submission rate.
3. MatchEngine outbox relay and completion reconciliation may become the hidden bottleneck if publish/confirm is still per-row or completion writes are single-threaded.
4. RabbitMQ is probably not first bottleneck, but prefetch/concurrency can amplify DB contention.

Initial tuning budget:

- Order DB pool: start from current loadtest `35` main + dedicated consumer/projection pools, but watch pending rather than blindly increasing.
- Wallet DB pool: current `40`; validate active/pending and settlement lock time before increasing.
- Match DB pool: current `35`; validate trade execution/outbox/completion write latency.
- RabbitMQ prefetch: avoid excessive prefetch that hides backlog inside consumers; current Wallet `20`, MatchEngine `50` need evidence.
- Outbox relay: batch size `500`, poll `100ms` is aggressive; measure confirm latency and DB update batch cost.

Metrics to capture:

- Hikari active/pending per datasource.
- Queue ready/unacked and DLQ per relevant queue.
- Outbox pending/failed/oldest age.
- Completion delayed count and reconciliation lag.
- PostgreSQL transaction time, lock waits, slow queries, table/index size.
- JVM heap/GC/thread count.
- Generator offered rate, accepted/completed rate, p95/p99, failure count.

## Implementation Plan

Phase 1 should avoid speculative tuning. First make measurement trustworthy:

1. Verify service startup against three DBs.
2. Verify `MatchedE2eLoadGenerator` uses separate JDBC URLs correctly. ✅
3. Add or document final invariant checks. ✅
4. Run smoke → 500 → 1000 → 1500 → 2000 gradient.
5. Tune only the first measured bottleneck.

## QA Plan

Acceptance criteria:

- [ ] No message loss: published/consumed/completed counts reconcile.
- [ ] No duplicate settlement for duplicate events.
- [ ] No negative wallet balance.
- [ ] No unresolved DLQ messages.
- [ ] Outbox pending/failed return to zero after drain window.
- [ ] Completion delayed count returns to zero or documented expected floor.
- [ ] Load-test result includes exact command, environment, target, duration, and observed metrics.

## Reviewer Findings

Initial review risks:

- A 2000 TPS headline is misleading unless it is explicitly end-to-end completed TPS.
- Raising consumers/pools can reduce apparent queue depth while increasing DB lock contention.
- Separate DBs remove shared PostgreSQL contention but do not remove per-service hot rows, audit write amplification, or outbox relay cost.
- Short runs can hide queue accumulation; soak and drain evidence are mandatory.

## Test Results

- `eap-order testClasses`: PASS.
- `eap-wallet testClasses`: PASS.
- `eap-matchEngine testClasses`: PASS.

Runtime results against the three-DB loadtest environment:

| Time | Scenario | Result | Notes |
| --- | --- | --- | --- |
| 2026-06-30 12:02 | 10 matched trades, 2 publishers | PASS | `tradeExecutions=10`, `orderMatchedEvents=20`, `walletTradeSettlements=10`, `completedTrades=10`, all measured queues drained to `0`. |
| 2026-06-30 12:03 | 500 matched trades, 32 publishers | REJECTED | Correctness passed, but `maxWalletTradeExecutedQueueReady=10005`; the run was polluted by stale queue backlog because the generator used asynchronous purge and did not purge DLQ. |
| 2026-06-30 13:31 | 500 matched trades, 32 publishers | PASS | After synchronous queue purge fix: `elapsedSeconds=2.50`, `matchedE2eTps=199.77`, `tradeExecutions=500`, `orderMatchedEvents=1000`, `walletTradeSettlements=500`, `completedTrades=500`, all measured queues drained to `0`. |
| 2026-06-30 13:31 | 1000 matched trades, 64 publishers | REJECTED | Timed out waiting for resting SELL orders in Redis. RabbitMQ queue drained but Redis order book stayed empty; treat as test-environment/driver reliability issue until service logs and single-driver isolation are guaranteed. |
| 2026-06-30 12:14 | 2000 matched trades, 96 publishers | REJECTED | Not a valid throughput result. The run was polluted by stale `order.failed` / DLQ messages and completion-reconciler requeues. Only `tradeExecutions=500`, `orderMatchedEvents=1000`, `walletTradeSettlements=500`, `completedTrades=500` completed before timeout; `maxOrderTradeExecutedQueueReady=49264`, `maxWalletTradeExecutedQueueReady=49224`, showing a requeue storm rather than normal load. |
| 2026-06-30 13:36 | Clean two-phase 500 matched trades, 64 publishers | PASS | Services stopped during `PHASE=seed`, all EAP queues manually purged, then services restarted for `PHASE=run`. `elapsedSeconds=2.35`, `matchedE2eTps=212.57`, `tradeExecutionsReachedSeconds=1.23`, `orderMatchedReachedSeconds=2.05`, `walletSettlementsReachedSeconds=2.05`, `completedTradesReachedSeconds=2.35`, `tradeExecutions=500`, `orderMatchedEvents=1000`, `walletTradeSettlements=500`, `completedTrades=500`, all final queues `0`. |
| 2026-06-30 13:43 | Clean two-phase 1000 matched trades, 64 publishers | PASS | `elapsedSeconds=3.79`, `matchedE2eTps=263.70`, `sellPublishSeconds=0.16`, `buyPublishSeconds=0.05`, `tradeExecutionsReachedSeconds=1.43`, `orderMatchedReachedSeconds=3.16`, `walletSettlementsReachedSeconds=3.16`, `completedTradesReachedSeconds=3.79`, `tradeExecutions=1000`, `orderMatchedEvents=2000`, `walletTradeSettlements=1000`, `completedTrades=1000`, `maxMatchEngineQueueReady=550`, `maxOrderTradeExecutedQueueReady=126`, `maxWalletTradeExecutedQueueReady=0`. The script stopped services successfully, but the final queue verification was not accepted because Docker socket access disappeared before the last purge check. |
| 2026-06-30 13:49 | Clean two-phase 1500 matched trades, 96 publishers | REJECTED_ENVIRONMENT_UNSTABLE | The in-generator business result completed (`tradeExecutions=1500`, `orderMatchedEvents=3000`, `walletTradeSettlements=1500`, `completedTrades=1500`, `elapsedSeconds=5.16`, `matchedE2eTps=290.90`), but the run is rejected as a benchmark because Docker/RabbitMQ became unavailable before the final external queue verification. After Docker recovered, the three split-DB containers were `Exited (0)` with no OOM. This exposed an environment-lifecycle gap introduced by the split-DB setup. |
| 2026-06-30 14:05 | Guarded two-phase 1500 matched trades, 96 publishers | PASS | After fixing the stop script to avoid killing Docker Desktop port-proxy processes: `elapsedSeconds=6.71`, `matchedE2eTps=223.69`, `tradeExecutionsReachedSeconds=2.93`, `walletSettlementsReachedSeconds=3.49`, `orderMatchedReachedSeconds=6.51`, `completedTradesReachedSeconds=6.71`, `tradeExecutions=1500`, `orderMatchedEvents=3000`, `walletTradeSettlements=1500`, `completedTrades=1500`, final queue verification completed with all EAP queues and DLQ at `0`. Queue peaks: `maxMatchEngineQueueReady=854`, `maxOrderTradeExecutedQueueReady=964`, `maxWalletTradeExecutedQueueReady=100`. |
| 2026-06-30 14:12 | Guarded two-phase 1500 matched trades, Order trade listener tuned | PASS | Added explicit loadtest `eap.order.listeners.trade-executed.concurrency=12` and raised Order consumer pool to `20`. `elapsedSeconds=4.23`, `matchedE2eTps=354.31`, `tradeExecutionsReachedSeconds=3.11`, `orderMatchedReachedSeconds=3.52`, `walletSettlementsReachedSeconds=3.52`, `completedTradesReachedSeconds=4.23`, `tradeExecutions=1500`, `orderMatchedEvents=3000`, `walletTradeSettlements=1500`, `completedTrades=1500`, final queue verification completed with all EAP queues and DLQ at `0`. Queue peaks: `maxOrderTradeExecutedQueueReady=62`, down from `964`; `maxOrderTradeAppliedQueueReady=572`, making completion-marker consumption the next signal to inspect. |
| 2026-06-30 14:28 | Guarded two-phase 1500 matched trades, critical listener concurrency normalized | PASS | Added explicit loadtest concurrency for Wallet `trade-executed=12`, MatchEngine `order-confirmed=12`, `order-trade-applied=12`, and `wallet-trade-settled=6`. `elapsedSeconds=5.06`, `matchedE2eTps=296.63`, `tradeExecutionsReachedSeconds=2.32`, `walletSettlementsReachedSeconds=4.24`, `orderMatchedReachedSeconds=4.42`, `completedTradesReachedSeconds=5.06`, `tradeExecutions=1500`, `orderMatchedEvents=3000`, `walletTradeSettlements=1500`, `completedTrades=1500`, final queue verification completed with all EAP queues and DLQ at `0`. All measured queue peaks were `0`, including `maxOrderTradeAppliedQueueReady=0`; DB invariant confirmed `trade_completion_view completed_at IS NULL = 0`. |
| 2026-06-30 14:38 | Guarded two-phase 1500 matched trades, Order projection invariant added | PASS | Added load-test acceptance for `orders_current` projection and widened `orders_current.market_id` from `VARCHAR(50)` to `VARCHAR(100)`. `elapsedSeconds=5.14`, `matchedE2eTps=291.61`, `tradeExecutionsReachedSeconds=3.24`, `orderMatchedReachedSeconds=4.44`, `walletSettlementsReachedSeconds=4.44`, `completedTradesReachedSeconds=5.14`, `tradeExecutions=1500`, `orderMatchedEvents=3000`, `orderCurrentMatchedRows=3000`, `walletTradeSettlements=1500`, `completedTrades=1500`, final queue verification completed with all EAP queues and DLQ at `0`. Post-run DB check confirmed `orders_current total=3000 matched=3000` and `trade_completion_view incomplete=0`; Order log had no projection errors. |
| 2026-06-30 14:47 | Guarded two-phase 1500 matched trades, run-only PostgreSQL stats reset after seed | PASS | Added optional `RESET_PG_STATS_BEFORE_RUN=true` to reset PostgreSQL stats after seed and before service startup. `elapsedSeconds=5.59`, `matchedE2eTps=268.57`, `tradeExecutionsReachedSeconds=2.83`, `orderMatchedReachedSeconds=3.61`, `walletSettlementsReachedSeconds=3.61`, `completedTradesReachedSeconds=4.25`, `orderCurrentMatchedRows=3000`, `completedTrades=1500`, final queues/DLQ `0`. Run-only DB stats show the remaining bottleneck is write amplification, not queue backlog: MatchEngine `trade_completion_view` had `1500` inserts + `6000` updates; Order had `3000` `order_event_store` inserts, `3000` `order_event_outbox` inserts + `3000` updates, `3000` `order_execution_links` inserts, `3000` stream-head updates, and `orders_current` `3000` inserts + `6000` updates; Wallet had `1500` settlements, `1500` outbox inserts + `1500` updates, and `3000` wallet row updates. |
| 2026-06-30 14:55 | Guarded two-phase 1500 matched trades, DB optimization pass 1 | PASS | Moved Order projection stale repair out of the high-frequency projector path and disabled repair in loadtest; merged MatchEngine completion marker update with `completed_at` convergence. `elapsedSeconds=7.41`, `matchedE2eTps=202.30`, `tradeExecutionsReachedSeconds=2.30`, `orderMatchedReachedSeconds=3.61`, `walletSettlementsReachedSeconds=3.61`, `completedTradesReachedSeconds=4.19`, `orderCurrentMatchedRows=3000`, `completedTrades=1500`, final queues/DLQ `0`. Primary success metric: `trade_completion_view` updates dropped from `6000` to `4500`, reducing one DB update per completed trade while preserving out-of-order marker handling. Throughput did not improve in this short run, so treat this as write-amplification reduction rather than a new TPS baseline. |
| 2026-06-30 15:07 | Guarded two-phase 1500 matched trades, Order projection prewarm | PASS | Added `PHASE=project` to prewarm `orders_current` from seeded event store before run and before resetting PostgreSQL stats. `projection prewarm complete; openOrders=3000`. `elapsedSeconds=7.14`, `matchedE2eTps=209.96`, `tradeExecutionsReachedSeconds=2.95`, `orderMatchedReachedSeconds=3.82`, `walletSettlementsReachedSeconds=3.82`, `completedTradesReachedSeconds=4.38`, final queues/DLQ `0`. Run-only stats confirmed cleaner measurement: `orders_current` changed from `3000 inserts + 6000 updates` to `0 inserts + 3000 updates`. TPS did not improve, proving historical projection catch-up was not the main runtime limiter. |
| 2026-06-30 15:11 | Guarded two-phase 1500 matched trades, Order fast match from caught-up projection | PASS | Added loadtest-only Order fast path: if `orders_current` is caught up with `order_stream_heads`, apply `OrderMatchedV1` using projection state instead of full event stream replay; otherwise fallback to original event replay path. `elapsedSeconds=4.80`, `matchedE2eTps=312.35`, `tradeExecutionsReachedSeconds=3.15`, `orderMatchedReachedSeconds=4.33`, `walletSettlementsReachedSeconds=4.33`, `completedTradesReachedSeconds=4.80`, `orderCurrentMatchedRows=3000`, `completedTrades=1500`, final queues/DLQ `0`. `order_event_store idx_scan` dropped from about `6054` to `3011`, confirming less stream replay. This is the first DB optimization in this pass that materially improved throughput while preserving correctness gates. |
| 2026-06-30 16:10 | Guarded two-phase 1500 matched trades, Order idempotency unique insert gate | PASS | Replaced Order `TradeExecuted` pre-read idempotency check (`existsByTradeIdAndOrderId`) with `INSERT ... ON CONFLICT DO NOTHING` gate on `order_execution_links(trade_id, order_id)`. Successful insert enters domain match; duplicate insert count `0` skips the order. `elapsedSeconds=4.85`, `matchedE2eTps=309.49`, `tradeExecutionsReachedSeconds=2.49`, `orderMatchedReachedSeconds=4.00`, `walletSettlementsReachedSeconds=3.80`, `completedTradesReachedSeconds=4.30`, `orderCurrentMatchedRows=3000`, final queues/DLQ `0`. Throughput stayed near fast-match run (`312.35 -> 309.49`), so this is not a major no-duplicate TPS win; value is removing one read-before-write pattern and preserving duplicate redelivery safety through the database unique constraint. |
| 2026-07-06 08:36 | MatchEngine core benchmark after Redis hot-path cleanup | PASS | Removed redundant `match:processed:{id}` `SETNX` after Redis `INCR` match-id generation, and replaced fully matched resting-order cleanup from full `remove_order.lua` (`ZREM + DEL + SREM`) to `SREM` only because `getAndRemoveBestMatchOrderLua` already removes the orderbook entry and order detail. Core benchmark: `events=50000`, `workers=64`, correctness `PASS`, `actualTps=18388.25`, `p50=2.93ms`, `p95=5.39ms`, `p99=28.25ms`. Conclusion: Redis/Lua matching itself is not the current global bottleneck. |
| 2026-07-06 08:45 | 10000 matched trades, Redis hot-path cleanup, old projection hard gate | REJECTED_METRIC_SEMANTICS | The run produced strong business facts (`tradeExecutions=10000`, `completedTrades=10000`, `walletTradeSettlements=10000`, `orderMatchedEvents=20000`) and `matchedE2eTps=1707.48` under the old queue-ready timing model, but failed because `orders_current=19999` while command-side `order_stream_heads=20000 MATCHED`. Investigation showed the missing row already had `OrderMatchedV1` and stream head `MATCHED`; the issue was projection lag/staleness, not failed business execution. |
| 2026-07-06 09:00 | 10000 matched trades, projection lag metrics and command-side hard gate | PASS_WITH_MEASUREMENT_GAP | Load-test acceptance was split into source-of-truth hard gates and read-model lag metrics. Hard gates now use `order_stream_heads`, `order_event_store`, `trade_executions`, `trade_completion_view`, and Wallet settlement. Projection is reported separately through `orderCurrentMatchedRows`, `orderProjectionStaleRows`, `orderProjectionCaughtUpSeconds`, and `orderProjectionLagSeconds`. Result: `buyPublishSeconds=5.00`, `actualBuyPublishTps=1999.37`, `queueReadyDrainedSeconds=8.85`, `completedTradesReachedSeconds=22.79`, `matchedE2eTps=438.79`, `orderProjectionCaughtUpSeconds=23.42`, `orderProjectionLagSeconds=0.63`, `orderCommandMatchedRows=20000`, `orderCurrentMatchedRows=20000`, final queues/DLQ `0`. Important caveat: `queueReadyDrainedSeconds` only measures RabbitMQ `messages_ready`, not `messages_unacknowledged`; the gap between ready-drain and business verification likely represents in-flight consumer/DB transaction work. |
| 2026-07-06 09:18 | 10000 matched trades, RabbitMQ ready+unacked final gate | PASS | Added RabbitMQ management API sampling to report `messages_ready` and `messages_unacknowledged`, and changed the accepted run gate to require final queues to have both ready and unacked at `0`. Result: `buyPublishSeconds=5.02`, `actualBuyPublishTps=1993.99`, `elapsedSeconds=30.13`, `matchedE2eTps=331.89`, `queueReadyDrainedSeconds=30.13`, `queueFullyDrainedSeconds=30.13`, `completedTradesReachedSeconds=30.13`, `orderProjectionLagSeconds=0.00`, `orderCommandMatchedRows=20000`, `orderCurrentMatchedRows=20000`, final queue ready/unacked `0`. Bottleneck signal: `maxMatchEngineQueueReady=2125`, `maxMatchEngineQueueUnacked=650`, while downstream unacked peaks were much smaller (`Order=37`, `Wallet=26`, completion markers `26/15`). Conclusion: the first sustained-load bottleneck is MatchEngine `orderConfirmed` consumption and trade persistence, not Order projection or Wallet settlement. |
| 2026-07-06 09:29 | 10000 matched trades, business gate excludes projection | PASS | Corrected the benchmark semantics: business E2E TPS includes MatchEngine trade execution, Order command-side matched application, Wallet settlement, MatchEngine completion view, and final RabbitMQ ready/unacked drain. Order `orders_current` projection is diagnostic only. Result: `buyPublishSeconds=5.00`, `actualBuyPublishTps=1999.09`, `elapsedSeconds=29.90`, `businessMatchedE2eTps=334.50`, `completedTrades=10000`, `orderCommandMatchedRows=20000`, `walletTradeSettlements=10000`, final queue ready/unacked `0`. Projection lag signal: `orderCurrentMatchedRows=19998`, `orderProjectionStaleRows=2`, `orderProjectionCaughtUpSeconds=-1`; this is read-model catch-up lag, not failed business completion. Bottleneck signal remains MatchEngine intake/persistence: `maxMatchEngineQueueReady=1120`, `maxMatchEngineQueueUnacked=650`, downstream unacked peaks around `26-32`. |
| 2026-07-06 09:41 | 10000 matched trades, corrected business completion time | PASS | Fixed a measurement bug where `elapsedSeconds` used `completedTradesReachedSeconds` and ignored later RabbitMQ `messages_unacknowledged` drain. Business completion now uses `max(completedTradesReachedSeconds, queueFullyDrainedSeconds)`. Result: `buyPublishSeconds=5.00`, `actualBuyPublishTps=1999.32`, `businessCompletionSeconds=27.64`, `businessMatchedE2eTps=361.79`, `tradeExecutionsReachedSeconds=8.98`, `orderMatchedReachedSeconds=22.61`, `walletSettlementsReachedSeconds=22.61`, `completedTradesReachedSeconds=22.97`, `queueFullyDrainedSeconds=27.64`, projection caught up after `27.30s` with `4.33s` lag. Conclusion: completion facts are done around `435 TPS`, but final queue ack/drain lowers business-gated TPS to about `362 TPS`. |
| 2026-07-06 09:46 | 10000 matched trades, lower DB observation overhead | PASS_WITH_DRIVER_LIMIT | Reduced load-test DB observation overhead: RabbitMQ queue sampling remains high-frequency, but full DB invariant snapshots now run at most once per second plus final verification. Result: `buyPublishSeconds=9.24`, `actualBuyPublishTps=1082.77`, `businessCompletionSeconds=29.45`, `businessMatchedE2eTps=339.54`, `tradeExecutionsReachedSeconds=10.91`, `orderMatchedReachedSeconds=24.91`, `walletSettlementsReachedSeconds=24.91`, `completedTradesReachedSeconds=25.94`, `queueFullyDrainedSeconds=29.45`. This run is accepted for correctness but not ideal as a throughput baseline because the driver failed to sustain the intended 2000 publish TPS. DB stats still show write amplification as the dominant issue: Order performs roughly `20000` stream-head updates, `20000` event inserts, `20000` idempotency-link inserts, `20000` projection updates, and `10000 insert + 10000 update` outbox writes; Wallet and MatchEngine show similar per-trade write amplification. |

Load-test driver fix applied:

- `MatchedE2eLoadGenerator.purgeQueues` now uses synchronous purge (`noWait=false`) and skips missing queues using `getQueueProperties`.
- `order.dlq` is purged as part of each run setup.
- Rationale: queue cleanup must complete before publishing, otherwise stale messages dominate queue peaks and invalidate TPS numbers.

Current accepted baseline:

- The highest historical small-run baseline remains `~354 completed matched trades/s` for 1500 matched trades after fixing the Order `trade-executed` listener concurrency.
- The latest 10000-trade sustained run with final ready+unacked gating is the current strongest scale/correctness run because it verifies source-of-truth command state (`order_stream_heads`), trade execution, Wallet settlement, completion view, projection lag, and final RabbitMQ in-flight drain.
- Treat the old `1707 TPS` and `438 TPS` runs as measurement-gap evidence, not accepted E2E baselines. They were useful because they exposed projection lag and ready-vs-unacked ambiguity, but they did not use the final ready+unacked acceptance gate.
- Current accepted sustained business baseline: `361.79 completed matched trades/s` for 10000 matched trades with final queue ready/unacked `0`; projection lag is reported separately and does not block this TPS number.
- Do not claim 2000 TPS yet; the next task is to inspect DB write amplification and tune concurrency against measured throughput, not just zero queue depth.

Projection correctness finding:

- A previous guarded run could have been incorrectly accepted because the load generator checked `OrderMatchedV1` events, Wallet settlement, completion view, and queues, but did not check the rebuildable Order read model `orders_current`.
- The Order projector was failing on long loadtest market IDs with `ERROR: value too long for type character varying(50)`.
- This means the event-store fact existed, but the user-facing projection could lag or fail while the benchmark still reported success.
- Fix applied:
  - `orders_current.market_id` changed to `VARCHAR(100)` through Liquibase changeset `order-es-006`.
  - `MatchedE2eLoadGenerator` now reports both command-side matched rows and read-model projection state.
- Updated benchmark rule:
  - Source-of-truth facts are hard gates: Order command state/event store, MatchEngine trade facts/completion view, Wallet settlement, wallet balances, Redis orderbook, and DLQ/queue state.
  - `orders_current` is a rebuildable projection and is measured as lag (`orderProjectionLagSeconds`, `orderProjectionStaleRows`) rather than blocking business TPS.
  - A projection that never catches up remains a correctness issue, but it should be reported separately from hot-path business completion.

RabbitMQ measurement finding:

- Earlier load-test versions used `RabbitAdmin.QUEUE_MESSAGE_COUNT`, which tracks ready messages.
- Ready messages reaching `0` does not mean processing is complete; consumers may already hold messages as unacknowledged while still executing DB transactions.
- Fix applied:
  - `MatchedE2eLoadGenerator` now samples RabbitMQ management API `/api/queues/%2F/{queue}`.
  - The report includes per-queue ready/unacked and max ready/unacked values for the hot queues.
  - The accepted run gate now waits for final ready and unacked counts to reach `0`.
- The report can now distinguish:
  - publisher pressure,
  - broker ready backlog,
  - consumer in-flight backlog,
  - DB completion lag.

Current bottleneck hypothesis from the 2026-07-06 final-gate run:

- Publisher can produce near the target (`actualBuyPublishTps=1993.99`).
- MatchEngine `orderConfirmed` queue is the first visible backlog:
  - `maxMatchEngineQueueReady=2125`
  - `maxMatchEngineQueueUnacked=650`
- Downstream Order/Wallet queues did not build comparable backlog:
  - `maxOrderTradeExecutedQueueUnacked=37`
  - `maxWalletTradeExecutedQueueUnacked=26`
  - completion marker unacked peaks `26/15`
- Run-only DB stats show MatchEngine still performs heavy write amplification per 10000 trades:
  - `trade_executions`: `10000` inserts.
  - `trade_outbox`: `10000` inserts + `10000` updates.
  - `trade_completion_view`: `10000` inserts + `20000` updates.
- Next optimization target: MatchEngine trade persistence/outbox/completion path, before spending effort on Order projection or Wallet settlement.

Run-only PostgreSQL stats finding:

- `RESET_PG_STATS_BEFORE_RUN=true` was added to `scripts/load-test/run-global-matched-e2e-two-phase.sh` so stats can be reset after seeding. Resetting before seed is not useful for bottleneck diagnosis because seed writes pollute the run phase counts.
- The 1500-trade run confirms the current bottleneck is write amplification:
  - MatchEngine:
    - `trade_executions`: `1500` inserts.
    - `trade_outbox`: `1500` inserts + `1500` updates.
    - `trade_completion_view`: `1500` inserts + `6000` updates.
  - Order:
    - `order_event_store`: `3000` inserts.
    - `order_event_outbox`: `3000` inserts + `3000` updates.
    - `order_execution_links`: `3000` inserts.
    - `order_stream_heads`: `3000` updates.
    - `orders_current`: `3000` inserts + `6000` updates.
  - Wallet:
    - `trade_settlements`: `1500` inserts.
    - `wallets`: `3000` updates.
    - `outbox`: `1500` inserts + `1500` updates.
- Queue peaks stayed bounded (`maxOrderTradeExecutedQueueReady=57`, completion marker queues `0`), so increasing consumer concurrency alone is unlikely to move the system toward 2000 TPS.
- Next optimization should reduce per-trade database round trips or write count while preserving idempotency and event-source correctness.

Candidate optimization tasks:

| ID | Task | Owner | Definition of Done |
| --- | --- | --- | --- |
| TPS-09-01 | Design Order idempotency gate without pre-read amplification | Architect + Implementation Lead | Replace or reduce `existsByTradeIdAndOrderId` hot-path reads without allowing duplicate `TradeExecuted` redelivery to re-run `aggregate.match()`. |
| TPS-09-02 | Review Order stream load cost on `TradeExecuted` | Architect + Performance | Decide whether matched application can use stream-head/current projection safely, or whether full stream replay must remain for correctness. |
| TPS-09-03 | Optimize MatchEngine completion view updates | Implementation Lead | Reduce `trade_completion_view` updates per trade from current `4` update statements where possible; preserve out-of-order marker handling. |
| TPS-09-04 | Move projection repair out of hot poll loop | Implementation Lead + QA | `OrdersCurrentProjector` no longer runs broad stale repair on every empty poll; repair remains available through scheduled slower job or explicit recovery path. |
| TPS-09-05 | Add DB round-trip counters to load-test report | Performance | Report per-run inserts/updates/index scans by service after `RESET_PG_STATS_BEFORE_RUN=true`; no manual psql required for diagnosis. |

## DB Optimization Story for Interview

Problem:

- The global matched E2E path initially looked like a queue/consumer problem because RabbitMQ queues were visible during the run.
- After tuning consumer concurrency, queues drained to zero, but completed TPS stopped improving.
- This showed that the next bottleneck was not message transport. The system was spending too much work per trade on database writes.

How it was diagnosed:

- The load-test harness was changed to reset PostgreSQL stats after seed and before the real run phase.
- This avoided mixing setup writes with runtime writes.
- For 1500 completed trades, the run showed high write amplification:
  - MatchEngine completion view: `1500` inserts + `6000` updates.
  - Order event sourcing path: `3000` event inserts, `3000` outbox inserts, `3000` stream-head updates, `3000` idempotency link inserts, and `6000` projection updates.
  - Wallet settlement path: `1500` settlement inserts, `1500` outbox inserts + updates, and `3000` wallet updates.
- Queue peaks were already low, so adding more consumers would mostly increase concurrent database pressure instead of solving the root issue.

Design decision:

- Keep the correctness model:
  - `TradeExecuted` remains the canonical trade fact.
  - Order and Wallet remain service-owned and emit completion markers.
  - MatchEngine owns `trade_completion_view`.
  - No service writes another service's database directly.
- Optimize the database hot path without weakening idempotency or eventual consistency.

Optimization pass 1:

1. Order projection repair isolation
   - Before: when the projector found no new events, it ran stale projection repair from the same high-frequency projection loop.
   - After: normal projection only follows `order_event_store -> orders_current`; stale repair is moved to a separate scheduled path and disabled in loadtest.
   - Reason: repair is a recovery concern, not part of the steady-state hot path.

2. MatchEngine completion update merge
   - Before: marker handling wrote the marker column, then issued another `UPDATE` to set `completed_at` if all markers were present.
   - After: marker update and completion convergence happen in the same SQL statement.
   - Result: `trade_completion_view` updates dropped from `6000` to `4500` for 1500 trades.
   - Reason: one completed trade no longer needs an extra database update just to mark completion.

Tradeoff:

- This pass reduces DB write amplification but does not claim a new TPS high-water mark.
- Short-run TPS still has noise from service startup, JVM warmup, queue drain timing, and remaining Order-side event-sourcing writes.
- The important engineering result is that the system now has evidence-backed DB pressure reduction while preserving business invariants:
  - `orderCurrentMatchedRows = 3000`
  - `walletTradeSettlements = 1500`
  - `completedTrades = 1500`
  - final queues and DLQ = `0`

Interview wording:

> During the 2000 TPS challenge, I found that the bottleneck moved from RabbitMQ queue backlog to database write amplification. Instead of blindly increasing consumer concurrency, I reset PostgreSQL stats between seed and run phases and measured writes per completed trade. The data showed that MatchEngine completion tracking and Order event sourcing were doing many writes per trade. I first optimized the safest part: moved projection repair out of the hot projector loop and merged completion marker updates with completion convergence, reducing MatchEngine completion-view updates from 6000 to 4500 for a 1500-trade run. The key point is that I preserved event-driven ownership, idempotent consumers, out-of-order marker handling, and final consistency while reducing hot-path database pressure.

Optimization pass 2:

1. Projection prewarm for fair benchmark boundary
   - Before: seed wrote Order Event Store while projection was disabled, so the measured run also paid the cost of projecting historical `OrderSubmissionRequestedV1` and `OrderAssetReservationConfirmedV1` events.
   - After: the two-phase script runs `PHASE=project` after seed and before run. This makes `orders_current` reach `OPEN` for all buyer/seller orders before matching starts.
   - Result: run-only projection writes became cleaner: `orders_current` dropped from `3000 inserts + 6000 updates` to `0 inserts + 3000 updates`.
   - Important finding: TPS did not improve materially, proving that historical projection catch-up was not the main runtime bottleneck.

2. Fast match from caught-up projection
   - Before: every `TradeExecuted` caused Order to process buyer and seller by replaying each order's event stream before appending `OrderMatchedV1`.
   - After: when `orders_current.aggregate_version` equals `order_stream_heads.current_version`, Order uses the caught-up projection as a validated snapshot to build the matched event and append with optimistic expected version.
   - Safety rule: if projection is missing, stale, not matchable, or insufficient quantity, the code falls back to full event stream replay.
   - Result: `order_event_store` index scans dropped from about `6054` to `3011` for 1500 trades, and measured throughput improved to `312.35` completed trades/s.
   - Tradeoff: this introduces a read-model-assisted fast path. It does not replace the event store as source of truth; it only avoids replay when the projection is provably caught up with the stream head.

Updated interview wording:

> After reducing completion-view writes, I found Order was still replaying event streams for both buyer and seller on every trade. I did not replace event sourcing with direct state mutation. Instead, I added a guarded fast path: when the Order projection version equals the stream-head version, the consumer can use the projection as a validated snapshot and append the next event with optimistic concurrency. If the projection is stale, it falls back to full replay. This cut event-store index scans roughly in half and improved a 1500-trade E2E run to about 312 completed trades/s while keeping event store ownership and final correctness checks intact.

Optimization pass 3:

1. Idempotency gate as unique insert
   - Before: Order used `existsByTradeIdAndOrderId` before applying a trade to buyer/seller orders, then inserted `order_execution_links` after domain match.
   - After: Order attempts `INSERT INTO order_execution_links ... ON CONFLICT DO NOTHING` first. If insert count is `1`, this consumer owns the processing attempt; if `0`, it is a duplicate and is skipped.
   - Safety: the listener transaction wraps the gate insert and event append. If event append fails, the gate insert rolls back too, so a retry can process again.
   - Result: the no-duplicate 1500-trade workload stayed near the previous TPS (`312.35 -> 309.49`), which means this was not the dominant bottleneck in the clean path.
   - Value: removes a read-before-write pattern and makes duplicate redelivery handling rely on the database uniqueness guarantee instead of a race-prone check-then-insert pattern.

Updated interview wording:

> I also replaced a read-before-write idempotency check with a unique insert gate. The old listener queried whether `(tradeId, orderId)` existed, then applied the domain event, then inserted the link. Under retries, check-then-insert is both extra DB work and a weaker concurrency pattern. I changed it to `INSERT ... ON CONFLICT DO NOTHING`: insert success means this consumer owns the work; conflict means duplicate delivery and skip. Because the gate and event append are in one transaction, failures roll back the gate and remain retryable. It did not move clean-path TPS much, but it improved the reliability model and removed unnecessary hot-path reads.

Current bottleneck signal from the clean 500 run:

- MatchEngine persisted all trades first (`tradeExecutionsReachedSeconds=1.23`).
- Order and Wallet completed their DB updates together later (`2.05s`).
- MatchEngine completion view converged last (`2.35s`).
- This points away from raw RabbitMQ publish throughput and toward downstream DB-write/completion-marker cost as the first real optimization area, but only after test isolation is made repeatable.

Current bottleneck signal from the clean 1000 run:

- MatchEngine reached all `TradeExecuted` rows in `1.43s`, so the core matching/write path is not the immediate limiter at this size.
- Order and Wallet reached their downstream writes at `3.16s`.
- Completion view reached all completed trades at `3.79s`.
- Queue peaks stayed bounded (`matchEngine.order.confirmed=550`, `order.trade.executed=126`, `wallet.trade.executed=0`), so the accepted bottleneck hypothesis remains downstream persistence plus completion marker convergence rather than RabbitMQ capacity.
- The final Docker-based queue verification failed because Docker socket access disappeared after service shutdown. The run's in-generator final queue snapshot was zero, but the post-run script verification is treated as incomplete.

Order-side diagnosis from the guarded 1500 runs:

- Initial suspicion was correct in direction: Order has significant DB write amplification on the `TradeExecuted` path.
- For each `TradeExecutedEvent`, Order applies both buyer and seller orders, so `1500` trades become `3000` local order applications.
- Each local order application performs idempotency lookup/linking, stream load, event-store append, stream-head update, outbox insert, and later projection update.
- However, the first measured bottleneck was not the write model itself. The loadtest profile did not configure `eap.order.listeners.trade-executed.concurrency`, so `TradeExecutedListener` used its default concurrency `4`.
- After setting `trade-executed.concurrency=12` and increasing the Order consumer pool to `20`, `orderMatchedReachedSeconds` improved from `6.51s` to `3.52s`, and `maxOrderTradeExecutedQueueReady` fell from `964` to `62`.
- Interpretation: the previous Order lag was mostly under-consumption of `order.trade.executed`, amplified by heavy per-message DB work. The next bottleneck signal moved to completion-marker processing (`maxOrderTradeAppliedQueueReady=572`).

## TPS-07 Multi-Agent Review: Completion Marker Convergence Bottleneck

### Trigger

After the Order `trade-executed` listener tuning, the guarded 1500-trade run improved from `223.69` to `354.31` completed trades/s. The previous Order queue backlog was mostly resolved:

```text
maxOrderTradeExecutedQueueReady: 964 -> 62
orderMatchedReachedSeconds:     6.51s -> 3.52s
```

The next visible queue signal moved to MatchEngine completion-marker consumption:

```text
maxOrderTradeAppliedQueueReady=572
maxWalletTradeSettledQueueReady=0
completedTradesReachedSeconds=4.23
```

### Architect Review Prompt

Decision needed:

- Keep `trade_completion_view` owned by MatchEngine.
- Treat `TradeExecuted` as the canonical trade fact.
- Treat `OrderTradeApplied` and `WalletTradeSettled` as downstream completion markers, not new trade facts.
- Do not let Order or Wallet update MatchEngine DB directly.

Architecture question:

- If `orderTradeApplied` queue piles up, should the fix be listener capacity, completion-view write model, or service-boundary redesign?

Current architecture hypothesis:

- This is still a MatchEngine-owned completion view concern.
- Order/Wallet should remain decoupled and only emit completion markers.
- Completion view can be eventually consistent, but the load-test target measures its convergence time.
- Direct cross-service DB writes would reduce queue lag at the cost of service ownership and recovery semantics, so it should not be the first fix.

### Performance Review Prompt

Current cost model per completed trade:

- MatchEngine:
  - insert `trade_executions`
  - insert/update `trade_completion_view` for trade execution
  - insert `trade_outbox`
  - update `trade_outbox` to `SENT`
  - consume two Order completion markers and one Wallet marker
  - update `trade_completion_view` until `completed_at` is set
- Order:
  - consume one `TradeExecuted`
  - apply buyer and seller order streams (`2` local order applications)
  - emit two `OrderTradeApplied` markers
- Wallet:
  - consume one `TradeExecuted`
  - settle wallet balances
  - emit one `WalletTradeSettled` marker

Current bottleneck hypothesis:

1. `TradeCompletionListener.handleOrderTradeApplied` defaults to concurrency `2` unless explicitly configured.
2. Loadtest profile configures general Rabbit listener concurrency, but not the specific `eap.match-engine.listeners.order-trade-applied.concurrency` key.
3. Since each trade emits two Order markers but only one Wallet marker, the Order completion-marker queue has twice the message volume and currently less explicit consumer tuning.
4. The first experiment should mirror the Order-side fix: explicitly tune completion-marker listener concurrency before changing DB schema or SQL logic.

Metrics required:

- `maxOrderTradeAppliedQueueReady`
- `maxWalletTradeSettledQueueReady`
- `completedTradesReachedSeconds`
- final incomplete rows:
  - `count(*) from match_engine.trade_completion_view where completed_at is null`
- delayed rows:
  - `trade_completion_delayed`
- optional DB stats:
  - `pg_stat_user_tables` for `trade_completion_view`
  - update count / dead tuple growth

### Implementation Lead Review

Relevant files:

- `eap-matchEngine/src/main/java/com/eap/eap_matchengine/application/TradeCompletionListener.java`
- `eap-matchEngine/src/main/java/com/eap/eap_matchengine/application/TradeCompletionService.java`
- `eap-matchEngine/src/main/resources/application-loadtest.yml`
- `eap-matchEngine/src/main/resources/db/changelog/db.changelog-trade-execution.xml`
- `eap-order/src/main/resources/application-loadtest.yml`

Minimal config-only experiment:

```yaml
eap:
  match-engine:
    listeners:
      order-trade-applied:
        concurrency: 12
      wallet-trade-settled:
        concurrency: 6
```

Rationale:

- `OrderTradeApplied` has `2x` the message volume of `WalletTradeSettled`.
- Current annotation defaults are `2` for both listeners.
- The previous bottleneck was fixed by explicitly configuring the missing listener concurrency, so repeat the same measurement-first approach here.

Do not change yet:

- `trade_completion_view` schema.
- Cross-service DB ownership.
- Reconciler repair logic.
- Batch SQL update model.

Acceptance criteria for TPS-07-03:

- guarded 1500 run remains PASS;
- final queues and DLQ are `0`;
- `maxOrderTradeAppliedQueueReady` drops materially from `572`;
- `completedTradesReachedSeconds` improves from `4.23s` or remains stable while queue peak drops;
- no new delayed completion rows remain after final drain.

TPS-07-03 result:

- Status: PASS for queue convergence, mixed for throughput.
- `maxOrderTradeAppliedQueueReady` dropped from `572` to `0`.
- `trade_completion_view completed_at IS NULL` was `0`.
- Throughput decreased from `354.31` to `296.63` completed trades/s, likely because higher consumer concurrency removed visible queue backlog but increased concurrent DB update pressure.
- Next decision: tune down/up MatchEngine completion listener concurrency and inspect MatchEngine DB write amplification before increasing to 2000.

Critical loadtest listener concurrency matrix:

| Service | Listener | Config key | Loadtest concurrency |
| --- | --- | --- | --- |
| Order | asset reservation confirmed | `eap.order.listeners.asset-reservation-confirmed.concurrency` | `16` |
| Order | asset reservation failed | `eap.order.listeners.asset-reservation-failed.concurrency` | `4` |
| Order | legacy order matched | `eap.order.listeners.order-matched.concurrency` | `16` |
| Order | trade executed | `eap.order.listeners.trade-executed.concurrency` | `12` |
| Wallet | order submitted | `eap.wallet.listeners.order-submitted.concurrency` | `32` |
| Wallet | legacy order matched | `eap.wallet.listeners.order-matched.concurrency` | `16` |
| Wallet | trade executed | `eap.wallet.listeners.trade-executed.concurrency` | `12` |
| MatchEngine | order confirmed | `eap.match-engine.listeners.order-confirmed.concurrency` | `12` |
| MatchEngine | order trade applied marker | `eap.match-engine.listeners.order-trade-applied.concurrency` | `12` |
| MatchEngine | wallet trade settled marker | `eap.match-engine.listeners.wallet-trade-settled.concurrency` | `6` |

Important test-harness finding:

- Do not run `TRUNCATE` while services are consuming from RabbitMQ. A previous 2000 attempt deadlocked Order DB cleanup with live service writes.
- Do not seed while the live Order outbox poller is running. It can publish seed outbox records to Wallet and create invalid `order.failed` messages.
- Valid global runs should use two phases:
  1. stop services;
  2. purge all EAP queues and DLQ;
  3. run `PHASE=seed`;
  4. start services;
  5. run `PHASE=run`.

Queue-cleanup script fix:

- `scripts/load-test/purge-eap-queues.sh` now fails explicitly when Docker/RabbitMQ cannot be queried.
- Previous behavior masked Docker errors with `|| true` and could incorrectly print `no EAP queues found`.
- This matters because stale queues and DLQ messages were the root cause of the rejected 2000-trade result.

Environment-lifecycle fix after split DB:

- Root cause 1: after moving from a shared DB to three split loadtest DB containers, the load-test workflow did not re-validate environment assumptions. RabbitMQ/Redis were still long-lived dev containers, while Order/Wallet/MatchEngine DBs were separate loadtest containers with different lifecycle behavior.
- Root cause 2: `scripts/load-test/stop-loadtest-services.sh` force-killed every process listening on ports `8080`, `8081`, and `8082`. On macOS + Docker Desktop, `lsof` can return Docker Desktop port-proxy processes for host ports. This caused the script to kill Docker Desktop itself, making RabbitMQ/PostgreSQL unavailable before final verification.
- Failure mode: Docker Desktop/daemon became unavailable around the final verification step. When Docker recovered, RabbitMQ/Redis/dev Postgres were back, but the three split-DB containers had exited and did not automatically restart. This created a partial environment that could make the next benchmark invalid.
- `docker-compose.loadtest.yml` now sets `restart: unless-stopped` for the three split DB containers.
- `scripts/load-test/assert-loadtest-environment.sh` now validates Docker, RabbitMQ, Redis, Order DB, Wallet DB, MatchEngine DB, required ports, and RabbitMQ queryability.
- `scripts/load-test/run-global-matched-e2e-two-phase.sh` now runs this validation before seed, before queue purge, after seed, before service startup, before run, and before final queue verification.
- `scripts/load-test/run-global-matched-e2e-two-phase.sh` now has a driver-level single lock at `.loadtest-lock/global-matched-e2e-two-phase-driver.lock`; the lock records PID, `MARKET_ID`, events, publishers, timeout, and `startedAt` so a second two-phase driver run refuses to start with enough owner context to diagnose safely.
- `scripts/load-test/run-global-matched-e2e-two-phase.sh` persists a per-run report bundle under `build/load-test-reports/`: run log, extracted JSON result, and metadata manifest. The metadata includes `MARKET_ID`, events, publishers, timeout, `startedAt`, Order/Wallet/MatchEngine DB endpoints, RabbitMQ endpoint, and report file paths.
- `scripts/load-test/stop-loadtest-services.sh` now only force-kills processes that match the loadtest service/Gradle/bootRun whitelist and explicitly skips Docker/Colima/OrbStack-style processes.
- Benchmark rule: if environment validation fails at any point, the result must be marked as rejected due to environment instability, even if the in-generator business counters look correct.

Next Scrum tasks:

| ID | Task | Owner | Definition of Done |
| --- | --- | --- | --- |
| TPS-06-01 | DONE - Add a single-driver lock for two-phase global load tests | Implementation Lead | The two-phase driver refuses to start if another two-phase global load-test driver is active; prevents concurrent truncate/purge/publish interference for accepted guarded runs. Direct single-phase runs still use their existing phase-local lock. |
| TPS-06-02 | Capture service process identity and profiles before each run | QA + Performance | Output includes Order/Wallet/MatchEngine PID, DB port, active profile, and RabbitMQ consumer count. |
| TPS-06-03 | Add SELL-book stage diagnostics | Performance | If `waitForRedisSellBook` times out, output queue depth, Redis zset size, MatchEngine consumer count, and recent MatchEngine error clue. |
| TPS-06-04 | DONE - Persist load-test JSON results, log, and metadata to files | Implementation Lead | Every two-phase run writes a `MARKET_ID`-scoped report bundle under `build/load-test-reports/` for comparison and documentation. |
| TPS-06-05 | Re-run accepted matrix after isolation | Performance + QA | Run 500/1000/1500 only after TPS-06-01~04 pass; reject any run with stale queue backlog, DLQ messages, or service restart during execution. |

## TPS-08 Order Event Sourcing Hot Path

Problem statement:

- After split DB, the global matched E2E path no longer has one shared PostgreSQL bottleneck.
- The remaining Order-side cost is internal write amplification:
  - `order_execution_links` idempotency gate insert;
  - `order_event_store` append;
  - `order_stream_heads` optimistic version update;
  - `order_event_outbox` insert and later SENT update;
  - `orders_current` projection update.
- This is the expected cost of a high-integrity event-sourced Order service, but it limits how far the current implementation can scale toward 2000 TPS.

Accepted optimization: Order idempotency unique insert gate.

- Changed duplicate handling from read-before-write to `INSERT ... ON CONFLICT DO NOTHING`.
- The unique key `(trade_id, order_id)` is now the concurrency gate.
- If insert returns `0`, the TradeExecuted message is a duplicate and the listener skips business mutation.
- If insert returns `1`, the listener appends the OrderMatched event.
- The listener transaction still covers the idempotency marker and event append path, so a failed append rolls back the marker and RabbitMQ retry remains safe.
- Guarded 1500 run remained PASS:
  - `tradeExecutions=1500`
  - `orderMatchedEvents=3000`
  - `orderCurrentMatchedRows=3000`
  - `completedTrades=1500`
  - final queues and DLQ were `0`.

Rejected experiment: remove the Order fast-path join against `order_stream_heads`.

- Hypothesis:
  - The fast path read `orders_current JOIN order_stream_heads` to prove projection catch-up.
  - The append step then locked `order_stream_heads` again with `SELECT ... FOR UPDATE`.
  - Removing the join could reduce one head-index read per OrderMatched append.
- Result:
  - `order_stream_heads idx_scan` improved from roughly `12000` to `9000` for 1500 matched trades.
  - But one guarded run ended with only `2998 / 3000` `orders_current` rows marked `MATCHED`, while `order_event_store`, Wallet settlement, and MatchEngine completion all reached the correct count.
  - Adding batch-level projection repair restored correctness but dropped observed throughput to `162.92 TPS` because projection completion became the slowest condition.
- Decision:
  - Rejected. Reducing one read is not worth weakening the projection/head consistency boundary or adding repair work into the hot projection loop.
  - The safe fast path must keep the `orders_current` + `order_stream_heads` catch-up check until the validation and append can be merged inside the same transaction.

Restored safe-path verification:

- Run: `GLT_20260630_RESTORED_SAFE_1500`
- Result: PASS
- `matchedE2eTps=262.04`
- `tradeExecutions=1500`
- `orderMatchedEvents=3000`
- `orderCurrentMatchedRows=3000`
- `completedTrades=1500`
- final queues and DLQ were `0`.
- Note: this run was lower than the earlier `~309 TPS` accepted run, but it restored correctness after rejecting the unsafe optimization. Treat this as a safety verification run, not a new best throughput baseline.

Next viable Order optimization:

- Build a specialized append path for matched trades inside the `OrderEventAppender` consumer transaction.
- Target design:
  1. lock `order_stream_heads` once;
  2. read the matching `orders_current` snapshot in the same transaction;
  3. validate remaining amount/status against the locked stream version;
  4. append `OrderMatchedV1`;
  5. update stream head;
  6. insert `OrderTradeApplied` outbox record.
- This preserves correctness while removing duplicated head reads.
- Do not push business logic into SQL stored procedures; keep domain validation in Java, but execute the required reads/writes under one transaction boundary.

TPS-08-02 result: specialized appender transaction fast path.

- Status: ACCEPTED.
- Implementation:
  - `OrderEventSourcingService` no longer performs the fast-path DB read itself.
  - It builds `OrderMatchedV1` and `OrderTradeApplied`, then calls `OrderEventAppender.appendMatchedFromCaughtUpProjection(...)`.
  - `OrderEventAppender` opens the consumer transaction, locks `order_stream_heads`, reads the caught-up `orders_current` row, validates `status` and `remaining_amount`, appends `OrderMatchedV1`, updates the stream head, and inserts the outbox row.
  - The normal append path and the specialized matched append path now share the same locked-head append helper.
- Why this is safer than the rejected experiment:
  - The rejected experiment removed the head/projection consistency check before append.
  - This accepted version keeps the check, but moves it into the same transaction that performs append.
  - There is still exactly one canonical Order event append path; the optimization changes transaction shape, not business semantics.
- Verification:
  - `TradeExecutedListenerTest`: PASS.
  - `testClasses`: PASS.
  - Run `GLT_20260630_APPENDER_FAST_1500`: PASS.
    - `matchedE2eTps=377.84`
    - `tradeExecutions=1500`
    - `orderMatchedEvents=3000`
    - `orderCurrentMatchedRows=3000`
    - `completedTrades=1500`
    - final queues and DLQ were `0`.
  - Recheck run after helper refactor `GLT_20260630_APPENDER_FAST_RECHECK_1500`: PASS.
    - `matchedE2eTps=243.48`
    - `completedTradesReachedSeconds=3.76`
    - `tradeExecutions=1500`
    - `orderMatchedEvents=3000`
    - `orderCurrentMatchedRows=3000`
    - `completedTrades=1500`
    - final queues and DLQ were `0`.
- DB stats:
  - `order_stream_heads idx_scan=9000` for 1500 matched trades.
  - Previous safe fast path was roughly `12000`.
  - Net reduction: about `3000` head index scans per 1500 trades, i.e. one less head read per buyer/seller OrderMatched append.
- Performance note:
  - End-to-end TPS still has local-machine variance, but the completion milestone improved/stayed healthy.
  - The stronger signal is the DB stats reduction plus maintained correctness gates.

Reviewer follow-up for next working day:

1. Align Order idempotency marker and event append transaction boundary.

   Status: DONE on 2026-07-03.

   Previous state:

   - `TradeExecutedListener` inserts into `order_execution_links` through Spring Data JPA under the default `JpaTransactionManager`.
   - `OrderEventAppender.appendMatchedFromCaughtUpProjection(...)` appends `OrderMatchedV1` through `orderConsumerTransactionManager`.
   - Both point to the same Order database, but they are not the same Spring transaction.

   Risk:

   - In the common case this works and passed load tests.
   - In a production-grade failure scenario, the appender transaction could commit while the outer JPA transaction later rolls back.
   - That would leave `OrderMatchedV1` committed but the `order_execution_links` idempotency marker missing.
   - A redelivered `TradeExecuted` could then attempt to apply the same trade/order again.
   - The event id/version conflict path should still protect the event stream, but the idempotency marker would no longer be the first-line gate.

   Implemented action:

   - Moved `order_execution_links INSERT ... ON CONFLICT DO NOTHING` into `OrderEventAppender`.
   - `TradeExecutedListener` no longer owns idempotency or transaction control; it only dispatches buyer/seller order application.
   - Removed the repository-level `existsByTradeIdAndOrderId` / `insertIfAbsent` entry points to avoid a second idempotency path.
   - Added `OrderTradeExecutionLink` as the explicit value object passed into appender methods.

   Implemented design:

   ```text
   TradeExecutedListener
     -> OrderEventSourcingService.match(...)
       -> OrderEventAppender.appendMatchedFromCaughtUpProjectionIfTradeLinkAbsent(...)
          same orderConsumerTransactionManager transaction:
            INSERT order_execution_links ON CONFLICT DO NOTHING
            if inserted = 0, skip duplicate
            lock order_stream_heads
            read caught-up orders_current
            append OrderMatchedV1
            update order_stream_heads
            insert OrderTradeApplied outbox
   ```

   Fallback behavior:

   ```text
   if projection is not caught up:
     OrderEventSourcingService loads aggregate from event stream
     -> OrderEventAppender.appendFromConsumerIfTradeLinkAbsent(...)
          same orderConsumerTransactionManager transaction:
            INSERT order_execution_links ON CONFLICT DO NOTHING
            append OrderMatchedV1
            update order_stream_heads
            insert OrderTradeApplied outbox
   ```

   Completed Definition of Done:

   - Idempotency marker and event append commit/rollback together.
   - Duplicate `TradeExecuted` still skips without appending another event.
   - Appender fallback/full replay behavior remains intact when projection is stale.
   - `testClasses`: PASS.
   - `TradeExecutedListenerTest`: PASS.
   - Guarded 1500 matched E2E run `GLT_20260703_TX_BOUNDARY_1500`: PASS.
     - `matchedE2eTps=359.71`
     - `tradeExecutions=1500`
     - `orderMatchedEvents=3000`
     - `orderCurrentMatchedRows=3000`
     - `completedTrades=1500`
     - final queues and DLQ were `0`.
   - Post-run consistency check:
     - `order_execution_links=3000`
     - `OrderMatchedV1=3000`
     - `orders_current MATCHED=3000`
   - Post-run Order DB stats:
     - `order_execution_links n_tup_ins=3000`
     - `order_event_store n_tup_ins=3000`
     - `order_stream_heads idx_scan=9000`
     - `orders_current idx_scan=6000`

2. Add focused tests for specialized matched append path.

   Missing test coverage:

   - caught-up projection + sufficient remaining amount -> appends `OrderMatchedV1` and outbox;
   - stale projection -> returns empty / falls back to full event replay;
   - insufficient remaining amount or invalid status -> does not append from fast path;
   - metadata includes `userId`;
   - duplicate event id remains idempotent;
   - transaction rollback does not leave partial event/outbox/head changes.

   Current coverage:

   - `TradeExecutedListenerTest` verifies duplicate marker behavior at listener level.
   - `testClasses` passes.
   - 1500-trade global E2E passes.

   Gap:

   - E2E proves the happy path under load, but it is too broad to catch small transaction-boundary regressions.
   - Add focused appender tests before pushing toward larger 2000 TPS experiments.

Interview framing:

- A performance optimization was rejected because it improved a local metric while violating the global consistency requirement.
- The important engineering decision was not "reduce DB calls at any cost"; it was "preserve canonical event integrity, then optimize transaction boundaries."
- This is a good example of production-style performance work: measure, reject unsafe wins, document the failure mode, then design a safer next iteration.

## TPS-09 MatchEngine Completion View Hot Path

Problem statement:

- After Order-side matched append optimization, a guarded 1500 matched E2E run still showed large MatchEngine DB work around `trade_completion_view`.
- Run `GLT_20260703_DIAG_LOCK_1500` was functionally correct but slow:
  - `matchedE2eTps=205.11`
  - `tradeExecutions=1500`
  - `completedTrades=1500`
  - final queues and DLQ were `0`
- PostgreSQL stats showed the hot table:
  - `trade_completion_view n_tup_ins=1500`
  - `trade_completion_view n_tup_upd=4500`
  - `trade_completion_view idx_scan=18987`
  - `trade_completion_view seq_scan=33`
  - `trade_completion_view seq_tup_read=47321`
- Index-level stats showed most index work came from the primary key:
  - `trade_completion_view_pkey idx_scan=18941`
  - `idx_trade_completion_incomplete idx_scan=46`

Root cause:

- `trade_completion_view` is a correctness view, not the canonical trade fact.
- It tracks whether downstream Order and Wallet consumers have applied a `TradeExecuted` fact.
- The previous implementation carried technical debt from multiple reliability iterations:
  - `markTradeExecuted(...)` inserted or updated the completion row.
  - `markOrderApplied(...)` first executed `INSERT ... ON CONFLICT DO NOTHING`.
  - `markOrderApplied(...)` then executed a separate `UPDATE ... WHERE trade_id = ?`.
  - `markWalletSettled(...)` used an upsert and completed the row if ready.
  - The load-test profile also kept the completion reconciler enabled, so delayed-repair scans ran beside the hot path.
- In the normal event order, `TradeExecuted` already creates the completion row before Order markers arrive.
- Therefore the `INSERT ... DO NOTHING` inside `markOrderApplied(...)` was usually a redundant primary-key probe.
- Because every trade has buyer and seller Order markers, this added roughly two extra primary-key probes per trade.

Implemented action:

- Changed `markOrderApplied(...)` from two DB statements to one upsert:

  ```text
  before:
    INSERT trade_completion_view ... ON CONFLICT DO NOTHING
    UPDATE trade_completion_view SET buyer/seller_order_applied_at = ? WHERE trade_id = ?

  after:
    INSERT trade_completion_view(trade_id, trade_executed_at, buyer/seller_order_applied_at, updated_at)
    ON CONFLICT (trade_id) DO UPDATE
      SET buyer/seller_order_applied_at = EXCLUDED.buyer/seller_order_applied_at,
          completed_at = CASE WHEN the other order marker and wallet marker already exist THEN now ELSE completed_at END,
          updated_at = now
  ```

- Kept out-of-order tolerance:
  - If an Order marker arrives before `TradeExecuted`, the upsert can still create the row.
  - If `TradeExecuted` already exists, the conflict update handles the normal path with one round trip.
- Disabled `trade-completion-reconciler` in the load-test profile:
  - The reconciler is a repair mechanism.
  - It should not compete with the benchmark hot path unless the test is specifically measuring repair behavior.

Verification:

- `eap-matchEngine testClasses`: PASS.
- Guarded 1500 matched E2E run `GLT_20260703_MATCH_COMPLETION_OPT_1500`: PASS.
  - `matchedE2eTps=388.91`
  - `tradeExecutions=1500`
  - `orderMatchedEvents=3000`
  - `orderCurrentMatchedRows=3000`
  - `walletTradeSettlements=1500`
  - `completedTrades=1500`
  - final queues and DLQ were `0`
- Completion view consistency:
  - `total=1500`
  - `completed=1500`
  - `missing_buyer=0`
  - `missing_seller=0`
  - `missing_wallet=0`
- Post-run MatchEngine DB stats:
  - `trade_completion_view n_tup_ins=1500`
  - `trade_completion_view n_tup_upd=4500`
  - `trade_completion_view idx_scan=6159`
  - `trade_completion_view seq_scan=15`
  - `trade_completion_view seq_tup_read=17672`
  - `trade_completion_view_pkey idx_scan=6159`
  - `idx_trade_completion_incomplete idx_scan=0`

Scale-up verification:

- Guarded 2000 matched E2E run `GLT_20260703_MATCH_COMPLETION_OPT_2000`: PASS.
  - `matchedE2eTps=385.87`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `orderCurrentMatchedRows=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`
- Completion view consistency:
  - `total=2000`
  - `completed=2000`
  - `missing_buyer=0`
  - `missing_seller=0`
  - `missing_wallet=0`
- Post-run MatchEngine DB stats:
  - `trade_completion_view n_tup_ins=2000`
  - `trade_completion_view n_tup_upd=6000`
  - `trade_completion_view idx_scan=8174`
  - `trade_completion_view seq_scan=21`
  - `trade_completion_view seq_tup_read=34948`
  - `trade_completion_view_pkey idx_scan=8174`
  - `idx_trade_completion_incomplete idx_scan=0`
- Post-run Order DB stats:
  - `order_event_store n_tup_ins=4000`
  - `order_execution_links n_tup_ins=4000`
  - `order_stream_heads idx_scan=12000`
  - `orders_current idx_scan=8000`

Result:

- TPS improved from `205.11` to `388.91` on the comparable guarded 1500-run.
- `trade_completion_view` index scans dropped from `18987` to `6159`.
- The incomplete-row index was not touched during the hot-path run after disabling the reconciler.
- Correctness gates remained green.
- The 2000-run sustained the same throughput class (`385.87 TPS`) while preserving all completion and queue-drain correctness gates.

Design decision:

- Keep `trade_completion_view` because it provides cross-service completion visibility.
- Do not treat it as the canonical trade fact; `trade_executions` remains the canonical MatchEngine fact.
- Keep repair/reconciliation behavior, but isolate it from load-test hot path and eventually from production hot partitions through lower frequency, batch windows, or separate worker capacity.

Next checks:

- Add focused tests around out-of-order completion marker arrival:
  - Order marker before `TradeExecuted`;
  - Wallet marker before both Order markers;
  - duplicate Order marker should remain idempotent;
  - completion should be set exactly once when all markers exist.
- Compare 1500 and 2000 runs after this change to decide whether the next bottleneck is MatchEngine order-confirmed ingestion, RabbitMQ consumer concurrency, or database write amplification.

## Load-Test Observer Effect: DB Polling Interference

Problem statement:

- During the 2000 TPS investigation, a run with the same business logic unexpectedly dropped from the `~385-389 TPS` class to `220.79 TPS`.
- The run was still functionally correct:
  - `GLT_20260703_LIGHT_POLLING_2000`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `orderCurrentMatchedRows=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`
- The drop was caused by the load-test verifier, not by a regression in the trading flow.

Root cause:

- The generator waited for completion by polling database aggregate counts every `100ms`.
- Even after removing some expensive wallet balance checks from the polling loop, the progress loop still executed repeated `count(*)` queries against hot tables:
  - `match_engine.trade_executions`
  - `match_engine.trade_completion_view`
  - `wallet_service.trade_settlements`
  - `order_service.order_event_store`
- These queries competed with the actual hot path for database CPU, buffer cache, and connection time.
- This is a benchmark observer effect: the measurement tool changed the system behavior being measured.

Evidence from the polluted run:

- `GLT_20260703_LIGHT_POLLING_2000`: PASS but slow.
  - `matchedE2eTps=220.79`
  - `elapsedSeconds=9.06`
  - `maxMatchEngineQueueReady=512`
- Run-only PostgreSQL stats showed verifier-driven scans:
  - `match_engine.trade_executions seq_tup_read=105844`
  - `match_engine.trade_completion_view seq_tup_read=105911`
  - `wallet_service.trade_settlements seq_tup_read=97325`
  - `wallet_service.wallets seq_tup_read=272000`

Implemented action:

- Changed `MatchedE2eLoadGenerator.waitForDownstream(...)` to use queue-only polling during the hot run.
- During the hot run, the generator now checks only RabbitMQ queue depth:
  - `matchEngine.orderConfirmed.queue`
  - `order.orderMatched.queue`
  - `wallet.orderMatched.queue`
  - `order.tradeExecuted.queue`
  - `wallet.tradeExecuted.queue`
  - `matchEngine.orderTradeApplied.queue`
  - `matchEngine.walletTradeSettled.queue`
- Full database invariants are checked only after queues drain.
- This preserves correctness checks while avoiding repeated database scans during the throughput window.

Verification:

- `eap-order testClasses`: PASS.
- Guarded 2000 matched E2E run `GLT_20260703_QUEUE_ONLY_POLLING_2000`: PASS.
  - `matchedE2eTps=389.14`
  - `elapsedSeconds=5.14`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `orderCurrentMatchedRows=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`
  - `maxMatchEngineQueueReady=943`
- The reported intermediate milestone times are now conservative upper bounds because the generator no longer polls DB counts during the run.

DB stats after queue-only polling:

- MatchEngine:
  - `trade_executions seq_tup_read=25280`, down from `105844`
  - `trade_completion_view seq_tup_read=25305`, down from `105911`
  - `trade_completion_view idx_scan=8183`
- Wallet:
  - `trade_settlements seq_tup_read=20504`, down from `97325`
  - `wallets seq_tup_read=208000`
- Order:
  - `order_event_store seq_tup_read=94480`
  - `orders_current seq_tup_read=52000`
  - `order_event_outbox seq_tup_read=137829`

Interpretation:

- Queue-only polling restored throughput to the previous accepted 2000-run class (`~386-389 TPS`).
- The `220.79 TPS` run should be rejected as a polluted benchmark.
- A later experiment requiring several consecutive zero-ready queue samples before verification was also rejected as an over-conservative timing boundary because it counted broker/consumer tail fluctuation into elapsed time and reported `197.14 TPS` without showing a business correctness regression.
- Remaining `seq_tup_read` is mostly from post-drain correctness checks and outbox polling, not from verifier queries inside the hot completion loop.
- The next benchmark improvement should separate "hot-path timing" and "post-run invariant verification" even more clearly:
  - measure hot-path completion with low-cost queue/metrics signals;
  - run heavy SQL consistency checks after the timed window;
  - keep PostgreSQL stats reset immediately before the timed run.

Benchmark rule added:

- A TPS number is not accepted if the verifier repeatedly scans hot service tables during the measured window.
- Database correctness is mandatory, but it should be verified after the measured throughput window unless the test is explicitly measuring query-side load.
- Monitoring overhead is a real production concern, but benchmark monitoring must be proportional to production-style metrics, not repeated ad-hoc full-table SQL checks.

## Cross-Service Projection Boundary Audit

Problem statement:

- The original design goal was that projections/read models should not slow down the main business chain.
- The 2000 TPS work exposed that the word "projection" had become too loose in discussion:
  - some tables are business-critical state;
  - some tables are reliability/idempotency markers;
  - some tables are query/read projections that can safely lag.
- Treating all of them as removable projections would create wrong architecture decisions.

Decision rule:

- A table can be moved out of the hot path only if all three are true:
  1. it is not the source of business truth;
  2. it is not required to safely process or deduplicate the current command;
  3. it can be rebuilt or caught up later from canonical facts/events.
- If a write is required to make money, inventory, order execution, or trade fact correct, it is not a projection even if it looks like a derived table.

Service audit:

| Service | Table / flow | Classification | Hot-path decision |
|---|---|---|---|
| Order | `order_event_store` | Canonical order facts | Must stay in hot path. |
| Order | `order_stream_heads` | Command-side aggregate head / lock state | Must stay in hot path; used to validate remaining amount and status without reading projection. |
| Order | `order_execution_links` | Idempotency / trade-to-order application link | Must stay in hot path to prevent duplicate `TradeExecuted` application. |
| Order | `order_event_outbox` | Reliable publish marker | Must stay in hot path if Order must publish `OrderTradeApplied` reliably. |
| Order | `orders_current` | Query projection | Should not be command hot path. It can lag and be rebuilt from `order_event_store`. |
| Wallet | `wallets` | Business state: balances and locked assets | Must stay in hot path. User-visible money/asset correctness depends on it. |
| Wallet | `trade_settlements` | Idempotency / settlement fact | Must stay in hot path to avoid double settlement. |
| Wallet | `outbox` | Reliable publish marker | Must stay in hot path if Wallet must publish `WalletTradeSettled` reliably. |
| MatchEngine | `trade_executions` | Canonical trade fact | Must stay in hot path. This is the durable fact that a match happened. |
| MatchEngine | `trade_outbox` | Reliable publish marker | Must stay in hot path if MatchEngine must publish `TradeExecuted` reliably. |
| MatchEngine | `trade_completion_view` | Cross-service completion read view | Candidate to move out of hot path or replace with append-only markers + async projector. |

Current state after the Order command-state change:

- Order no longer uses `orders_current` to decide whether a `TradeExecuted` can be applied.
- The hot path now locks `order_stream_heads`, validates command-side remaining amount/status, appends `OrderMatchedV1`, updates the head, inserts idempotency links, and writes outbox.
- `orders_current` remains a projection updated by `OrdersCurrentProjector`.
- The benchmark still verifies `orders_current` after the run, which is correct for end-to-end acceptance, but it should not be interpreted as business hot-path completion.

Important distinction for load testing:

- Business completion should mean:
  - MatchEngine persisted `TradeExecuted`;
  - Order applied buyer/seller matched events;
  - Wallet settled balances;
  - required completion markers were accepted.
- Read-model catch-up should mean:
  - `orders_current` reflects the matched status;
  - any completion/status view has converged.
- These two timings should be reported separately.
- Otherwise, a delayed projection can make the business chain look slower than it really is, and a fast projection can hide business write amplification.

Next design target:

- MatchEngine `trade_completion_view` is the remaining projection-like table still receiving high-frequency mutable updates from completion events.
- Safer direction:
  - keep `trade_executions` as the canonical trade fact;
  - keep Order and Wallet completion events for distributed consistency visibility;
  - change completion tracking from mutable view updates to append-only completion markers, for example `(trade_id, marker_type, occurred_at, source_event_id)`;
  - build `trade_completion_view` asynchronously from those markers;
  - make the load test report both marker acceptance and view convergence.
- This preserves correctness while moving the read/convenience view away from the critical business chain.

## Order Write-Amplification Review After Projection Isolation

Clarification:

- The earlier statement that projection could affect throughput was only true for benchmark acceptance timing and read-model catch-up.
- After the command-state change, Order command handling no longer reads `orders_current` to decide whether a `TradeExecuted` can be applied.
- Therefore, the remaining Order-side bottleneck should not be described as "projection lookup cost".
- It is now mostly event-sourcing write amplification.

Current Order `TradeExecuted` hot path:

```text
TradeExecutedEvent
  -> lock buyer/seller order_stream_heads
  -> validate status/remaining amount from command-side head state
  -> insert buyer/seller order_execution_links in one multi-row statement
  -> append buyer OrderMatchedV1 to order_event_store
  -> update buyer order_stream_heads
  -> append seller OrderMatchedV1 to order_event_store
  -> update seller order_stream_heads
  -> insert one shared OrderTradeApplied outbox row
  -> scheduled outbox relay publishes marker and later updates outbox to SENT
  -> scheduled projector eventually updates orders_current
```

What improved already:

- `orders_current` is no longer used by the command path.
- Buyer/seller stream heads are locked in one stable-order query.
- Buyer/seller idempotency links are inserted in one multi-row statement.
- `OrderTradeApplied` outbox is trade-level, not per-order marker; this avoids one extra outbox row per trade.
- Idempotency marker and event append now commit/rollback in the same consumer transaction.

Remaining write cost per completed trade:

| Component | Writes per trade | Why it exists |
|---|---:|---|
| `order_execution_links` | 2 inserts | Idempotency marker for buyer/seller order application. |
| `order_event_store` | 2 inserts | Canonical buyer/seller `OrderMatchedV1` facts. |
| `order_stream_heads` | 2 updates | Command-side aggregate version/hash/status/remaining state. |
| `order_event_outbox` | 1 insert + 1 update | Reliable publish of one `OrderTradeApplied` marker. |
| `orders_current` | 2 async updates | Query projection; should be measured as read-model catch-up, not command completion. |

Important non-goals:

- Do not move Wallet balance correctness or Order event-store correctness into projection.
- Do not remove `order_stream_heads`; it is now the explicit command-side concurrency guard.
- Do not push matching business rules into SQL stored procedures only to reduce Java round trips; that would make the system harder to reason about and less portable.

Viable next optimizations:

1. Batch buyer/seller event-store append and head update inside `OrderEventAppender`.
   - Current code calls the locked-head append helper twice.
   - Both events are already in the same transaction and both previous hashes are known after the head lock.
   - A specialized trade append method could:
     - compute both hashes in Java;
     - insert both `OrderMatchedV1` rows using one multi-row SQL statement;
     - update both stream heads using one multi-row or `CASE` update;
     - keep one shared outbox row.
   - Expected benefit: fewer JDBC round trips and fewer repeated statement executions.
   - Correctness constraint: event version/hash chain must remain per-order and deterministic.

2. Re-evaluate whether `order_execution_links` can become a projection from `order_event_store`.
   - The deterministic `event_id(orderId, MATCHED:matchId)` already gives one idempotency key per order/trade append.
   - In theory, duplicate `TradeExecuted` could be detected from existing `OrderMatchedV1` events instead of a separate link table.
   - Risk: the link table is currently a clear first-line idempotency gate and gives a simple consistency check `links == matched events`.
   - Decision pending: only remove it if focused tests prove duplicate delivery, partial failure, and redelivery behavior stay safe without it.

3. Separate benchmark timing:
   - business completion: event-store append + Wallet settlement + required completion markers;
   - read-model catch-up: `orders_current` projector convergence.
   - This does not reduce real writes, but prevents projection lag from being mislabeled as command-chain TPS loss.

Current assessment:

- Order projection lookup is no longer the main issue.
- Order write amplification is real and mostly intentional because each trade affects two independent order aggregates.
- The safest next implementation target is buyer/seller append batching inside `OrderEventAppender`, not removing correctness tables first.

Implemented action: specialized buyer/seller trade append batching.

- Scope:
  - Only changed the `TradeExecuted -> Order trade application` path.
  - User order submission path remains a single-order append path.
  - Fallback full-replay append path remains unchanged.
- Before:

  ```text
  lock buyer/seller heads once
  insert buyer/seller links once
  append buyer OrderMatchedV1
  update buyer head
  append seller OrderMatchedV1
  update seller head
  insert one shared OrderTradeApplied outbox
  ```

- After:

  ```text
  lock buyer/seller heads once
  insert buyer/seller links once
  compute buyer/seller next versions and hash chain in Java
  multi-row insert buyer/seller OrderMatchedV1 events
  multi-row update buyer/seller stream heads
  insert one shared OrderTradeApplied outbox
  ```

- What this optimizes:
  - Reduces JDBC/SQL round trips on the successful trade-application path.
  - Keeps two canonical Order events because buyer and seller are still two independent order aggregates.
  - Keeps two stream-head updates because each order has its own version, hash chain, remaining amount, and status.
  - Keeps one shared outbox marker per trade.
- What this does not optimize:
  - It does not remove event-store writes.
  - It does not move business correctness into projection.
  - It does not merge buyer/seller into one aggregate.
- Verification:
  - `OrderEventAppenderPostgresIT`: PASS.
  - `TradeExecutedListenerTest`: PASS.

Follow-up: fix benchmark observer effect in matched E2E.

- Problem:
  - The first 2000-run after batch append was functionally correct but reported only `182.74 TPS`.
  - PostgreSQL stats showed the generator was still repeatedly scanning hot tables during the measured window:
    - `order_event_store seq_scan=40`, `seq_tup_read=472696`;
    - `orders_current seq_scan=40`, `seq_tup_read=160000`;
    - `wallets seq_scan=160`, `seq_tup_read=640000`;
    - `trade_completion_view seq_scan=40`, `seq_tup_read=79496`.
  - This was a benchmark observer effect, not an accepted performance baseline.
- Implemented action:
  - Changed `MatchedE2eLoadGenerator.waitForDownstream(...)` so the hot wait loop polls RabbitMQ queue depth only.
  - It now requires three consecutive queue-drained samples before leaving the timed hot window.
  - Database invariant checks still run, but only after queue drain; they validate correctness without defining the TPS window.
- Verification run:
  - Run: `GLT_20260703_QUEUE_ONLY_ORDER_BATCH_2000`.
  - Result: PASS.
  - `matchedE2eTps=827.76`.
  - `elapsedSeconds=2.42`.
  - `drainSecondsAfterBuyPublish=1.88`.
  - `tradeExecutions=2000`.
  - `orderMatchedEvents=4000`.
  - `orderCurrentMatchedRows=4000`.
  - `walletTradeSettlements=2000`.
  - `completedTrades=2000`.
  - final queues and DLQ were `0`.
- Post-run DB stats:
  - `order_event_store seq_scan=0`, down from `40`.
  - `orders_current seq_scan=12`, down from `40`.
  - `wallets seq_scan=48`, down from `160`.
  - `trade_completion_view seq_scan=12`, down from `40`.
- Interpretation:
  - The batch append change preserved full E2E correctness.
  - The previous low TPS run is rejected as a polluted benchmark.
  - The current clean 2000-run baseline is `827.76 TPS` for queue-drain business completion with post-drain DB correctness verification.

Sustained verification:

- Run: `GLT_20260703_ORDER_BATCH_SUSTAINED_10K`.
- Load shape:
  - `EVENTS=10000`
  - `TARGET_TPS=2000`
  - `DURATION_SECONDS=5`
  - `PUBLISHERS=128`
- Result: PASS.
  - `actualBuyPublishTps=1996.31`.
  - `buyPublishSeconds=5.01`.
  - `drainSecondsAfterBuyPublish=7.21`.
  - `elapsedSeconds=12.22`.
  - `matchedE2eTps=818.39`.
  - `tradeExecutions=10000`.
  - `orderMatchedEvents=20000`.
  - `orderCurrentMatchedRows=20000`.
  - `walletTradeSettlements=10000`.
  - `completedTrades=10000`.
  - `remainingSellOrders=0`.
  - `remainingBuyOrders=0`.
  - final queues and DLQ were `0`.
- Queue signal:
  - `maxMatchEngineQueueReady=3406`.
  - downstream TradeExecuted / OrderTradeApplied / WalletTradeSettled queues did not build meaningful backlog.
- Interpretation:
  - The publisher can feed the system at ~2000 TPS.
  - The full system drains at about `818 TPS` on this local environment.
  - The largest backlog appears at `matchEngine.orderConfirmed.queue`, so the next investigation should focus on MatchEngine ingestion/matching throughput before further Order-side micro-optimizations.
- Post-run DB stats:
  - Order:
    - `order_event_store n_tup_ins=20000`.
    - `order_execution_links n_tup_ins=20000`.
    - `order_stream_heads n_tup_upd=20000`, `idx_scan=60000`.
    - `order_event_outbox n_tup_ins=10000`, `n_tup_upd=10000`.
    - `orders_current n_tup_upd=20000`.
  - MatchEngine:
    - `trade_executions n_tup_ins=10000`.
    - `trade_outbox n_tup_ins=10000`, `n_tup_upd=10000`.
    - `trade_completion_view n_tup_ins=10000`, `n_tup_upd=20000`.
  - Wallet:
    - `wallets n_tup_upd=20000`.
    - `trade_settlements n_tup_ins=10000`.
    - `outbox n_tup_ins=10000`, `n_tup_upd=10000`.

## Friday Wrap-Up / Monday Resume Plan

Date: 2026-07-03 Friday.

Current accepted state:

- Order `TradeExecuted -> Order trade application` path now uses a specialized buyer/seller batch append path:
  - one lock query for buyer/seller stream heads;
  - one multi-row insert for buyer/seller idempotency links;
  - one multi-row insert for buyer/seller `OrderMatchedV1` events;
  - one multi-row update for buyer/seller stream heads;
  - one shared `OrderTradeApplied` outbox row.
- User order submission path was not changed.
- `order_event_store` remains canonical Order fact storage.
- `order_stream_heads` remains command-side lock/state/hash/version guard.
- `orders_current` remains async read projection.
- The load-test observer effect was fixed:
  - hot window now polls RabbitMQ queues only;
  - DB invariants run after queue drain;
  - the old `182.74 TPS` result is rejected as polluted.

Accepted verification:

- `OrderEventAppenderPostgresIT`: PASS.
- `TradeExecutedListenerTest`: PASS.
- `eap-order test`: PASS.
- Clean 2000 matched E2E:
  - Run `GLT_20260703_QUEUE_ONLY_ORDER_BATCH_2000`.
  - `matchedE2eTps=827.76`.
  - correctness gates all passed.
- Sustained 10k matched E2E:
  - Run `GLT_20260703_ORDER_BATCH_SUSTAINED_10K`.
  - `actualBuyPublishTps=1996.31`.
  - `matchedE2eTps=818.39`.
  - `tradeExecutions=10000`.
  - `orderMatchedEvents=20000`.
  - `walletTradeSettlements=10000`.
  - `completedTrades=10000`.
  - final queues and DLQ were `0`.

Monday first investigation:

1. Focus on MatchEngine ingestion/matching path.
   - Evidence:
     - Sustained 10k run reached publish rate `~1996 TPS`.
     - Full-system drain throughput was `~818 TPS`.
     - `maxMatchEngineQueueReady=3406`.
     - downstream queues did not build meaningful backlog.
   - Initial hypothesis:
     - Bottleneck is before/inside MatchEngine consuming `matchEngine.orderConfirmed.queue` and producing `TradeExecuted`.
     - Order trade application and Wallet settlement are currently not the first backlog point in this run shape.

2. Inspect MatchEngine code path:
   - `OrderConfirmedEvent` listener concurrency and prefetch.
   - Redis ZSET / Lua matching cost.
   - Trade persistence path:
     - `trade_executions`;
     - `trade_outbox`;
     - `trade_completion_view` initial marker.
   - Outbox relay polling cost.
   - Any synchronous logging or per-event serialization overhead.

3. Add/collect focused metrics before changing design:
   - consumed `OrderConfirmedEvent` rate;
   - `TradeExecuted` created rate;
   - Redis matching latency;
   - DB trade persistence latency;
   - MatchEngine listener active/concurrency count;
   - queue ready/unacked split for `matchEngine.orderConfirmed.queue`.

4. Next candidate implementation areas:
   - normalize/increase MatchEngine order-confirmed listener concurrency only if DB/Redis can absorb it;
   - batch or streamline trade persistence/outbox insert if per-trade DB round trips dominate;
   - isolate MatchEngine completion tracking from trade execution hot path if `trade_completion_view` still competes;
   - avoid changing Order or Wallet again until MatchEngine ingestion evidence is clear.

Do not forget:

- Use queue-only timing for TPS numbers.
- Treat DB correctness checks as post-drain invariants, not hot-window polling.
- Do not accept runs with repeated hot-table DB polling as performance baselines.
- Before major code changes, run or preserve:
  - `GLT_20260703_QUEUE_ONLY_ORDER_BATCH_2000` as smoke baseline;
  - `GLT_20260703_ORDER_BATCH_SUSTAINED_10K` as sustained baseline.

## Resume Notes

- Built a role-based AI engineering workflow using reusable Codex skills for architecture review, performance budgeting, implementation, QA, and production-style review.
- Applied the workflow to a 2000 TPS event-driven trading-system load-test initiative with per-service database isolation, transactional outbox, idempotent consumers, and completion reconciliation.
- Converted performance work into a Scrum-style backlog with explicit Definition of Done, queue-drain correctness, and production-review gates.

## Hot-Path Amplification Experiments: Rejected Optimizations

Context:

- After the accepted `GLT_20260703_QUEUE_ONLY_POLLING_2000` baseline (`389.14 completed trades/s`), the next investigation focused on business hot-path amplification rather than listener-count tuning.
- The stable bottleneck shape is fixed per completed trade:
  - MatchEngine persists `TradeExecuted`, publishes outbox, and updates `trade_completion_view`.
  - Order applies buyer and seller `OrderMatchedV1` events and publishes two `OrderTradeApplied` markers.
  - Wallet updates buyer and seller balances, writes settlement marker, and publishes `WalletTradeSettled`.
  - MatchEngine consumes three completion markers and converges `completed_at`.

### Experiment 1: Wallet native idempotency claim

Hypothesis:

- Replace Wallet's `existsByTradeId(...)` pre-read plus `save(...)` with native:
  - `INSERT INTO wallet_service.trade_settlements ... ON CONFLICT (trade_id) DO NOTHING`
- Expected benefit: remove one read-before-write from the `TradeExecuted -> Wallet settlement` path.

Result:

- Run `GLT_20260703_WALLET_NATIVE_CLAIM_2000`: PASS for correctness, rejected for throughput.
  - `matchedE2eTps=326.95`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`
- Compared with accepted baseline `389.14 TPS`, this was a regression.
- Post-run stats still showed the core Wallet cost remained:
  - `wallets n_tup_upd=4000`
  - `trade_settlements n_tup_ins=2000`
  - `outbox n_tup_ins=2000`, `outbox n_tup_upd=2000`

Decision:

- Rejected and reverted.
- Reason: the removed pre-read was not the dominant cost. Wallet settlement remains dominated by two wallet row updates, settlement ledger insert, outbox insert/update, and transaction/WAL cost.
- Interview point: fewer SQL statements is not automatically faster; the measured bottleneck must match the optimized operation.

### Experiment 2: Completion marker duplicate-write guard

Hypothesis:

- Make `trade_completion_view` marker upserts skip duplicate writes by adding `WHERE` guards and `COALESCE(...)`.
- Expected benefit: reduce write amplification under duplicate MQ delivery or replay.

Result:

- Unit tests passed, but global run `GLT_20260703_COMPLETION_DUP_GUARD_2000` was rejected:
  - `matchedE2eTps=191.10`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`
- `trade_completion_view` still had:
  - `n_tup_ins=2000`
  - `n_tup_upd=6000`
- The guard did not reduce clean-path updates because the normal path has no duplicate markers.
- The SQL became heavier while preserving the same number of clean-path writes.

Decision:

- Rejected and reverted.
- Reason: this protects a duplicate/replay scenario but penalizes the primary clean path, and it does not reduce the fixed `3 marker updates per trade` design cost.

### Current conclusion

- The remaining throughput problem is not a small SQL micro-optimization problem.
- To materially improve completed-trade TPS, the next design-level options are:
  1. reduce completion-marker count or combine marker semantics safely;
  2. move completion convergence to a lower-priority/batched worker if "completed TPS" does not need to include reconciliation latency;
  3. redesign completion tracking from row mutation per marker into append + batch compaction;
  4. keep current consistency model and accept the current `~385-389 completed trades/s` class as the reliable baseline until a larger architecture change is justified.

Interview story:

> I tested two plausible hot-path optimizations and rejected both based on evidence. A Wallet `ON CONFLICT DO NOTHING` claim looked cleaner than pre-read idempotency, but it regressed the 2000-trade E2E run from the accepted `389 TPS` class to `327 TPS` because the dominant cost was still wallet row updates, settlement insert, outbox writes, and WAL. I also tried guarding duplicate completion marker updates, but clean-path traffic still required the same `6000` completion-view updates for `2000` trades and throughput dropped to `191 TPS`. The lesson was that this bottleneck is architectural write amplification, not a missing index or one inefficient query.

## Order Per-Trade Completion Marker

Problem:

- The previous `TradeExecuted -> Order` flow applied buyer and seller orders independently:
  - buyer order append transaction;
  - buyer `OrderTradeApplied` outbox marker;
  - seller order append transaction;
  - seller `OrderTradeApplied` outbox marker.
- This preserved correctness but amplified the completed-trade path:
  - `2` Order marker outbox rows per trade;
  - `2` Order marker MQ messages per trade;
  - `2` MatchEngine order-marker updates per trade.
- Since a trade is only Order-complete when both buyer and seller order streams have been updated, the two external markers were more granular than the completion model needed.

Design change:

- Keep Order's internal event sourcing model:
  - buyer order stream still receives `OrderMatchedV1`;
  - seller order stream still receives `OrderMatchedV1`.
- Change the external completion marker from per-order to per-trade:
  - one `OrderTradeAppliedEvent` now represents "Order service applied this trade to both buyer and seller order streams."
- The Order listener now handles a `TradeExecutedEvent` through one `applyTrade(...)` call.
- The appender writes both order events and both `order_execution_links` in the same consumer transaction, then writes one shared outbox marker.
- Lock ordering is deterministic by `orderId` to reduce deadlock risk.
- Duplicate redelivery is handled by the existing link uniqueness model:
  - both links already exist -> duplicate skip;
  - only one link exists -> treated as inconsistent partial application and rolled back.

Schema / event impact:

- `OrderTradeAppliedEvent` is now trade-level:
  - `tradeId`
  - `buyerOrderId`
  - `sellerOrderId`
  - `legacyMatchId`
  - `dealPrice`
  - `quantity`
  - `buyerAppliedAt`
  - `sellerAppliedAt`
  - `appliedAt`
- MatchEngine `trade_completion_view` now tracks:
  - `trade_executed_at`
  - `order_applied_at`
  - `wallet_settled_at`
  - `completed_at`
- The old `buyer_order_applied_at` / `seller_order_applied_at` columns were collapsed into `order_applied_at` through Liquibase changeSet `match-trade-006`.

Verification:

- Unit tests:
  - `eap-order test`: PASS.
  - `eap-matchEngine test`: PASS.
- Smoke E2E run `GLT_20260703_ORDER_TRADE_MARKER_SMOKE_10`: PASS.
  - `tradeExecutions=10`
  - `orderMatchedEvents=20`
  - `OrderTradeAppliedEvent outbox=10`
  - `walletTradeSettlements=10`
  - `completedTrades=10`
  - final queues and DLQ were `0`
- Guarded 2000 matched E2E run `GLT_20260703_ORDER_TRADE_MARKER_2000`: PASS.
  - `matchedE2eTps=422.12`
  - `elapsedSeconds=4.74`
  - `tradeExecutions=2000`
  - `orderMatchedEvents=4000`
  - `orderCurrentMatchedRows=4000`
  - `walletTradeSettlements=2000`
  - `completedTrades=2000`
  - final queues and DLQ were `0`

Run-only DB stats after the 2000-trade run:

- Order:
  - `order_event_store n_tup_ins=4000`
  - `order_execution_links n_tup_ins=4000`
  - `order_event_outbox n_tup_ins=2000`, down from the previous per-order-marker `4000` class.
  - `order_event_outbox n_tup_upd=2000`, down from the previous `4000` class.
- MatchEngine:
  - `trade_completion_view n_tup_ins=2000`
  - `trade_completion_view n_tup_upd=4000`, down from the previous `6000` class.
- Completion invariant:
  - `total=2000`
  - `order_applied=2000`
  - `wallet_settled=2000`
  - `completed=2000`

Result:

- The accepted completed-trade baseline improved from `389.14 TPS` to `422.12 TPS`.
- This is a real clean-path write-amplification reduction:
  - one fewer Order outbox insert per trade;
  - one fewer Order outbox SENT update per trade;
  - one fewer MQ marker per trade;
  - one fewer MatchEngine completion-view update per trade.

Interview story:

> I found that the completed-trade path was not just slow because of PostgreSQL tuning; it was doing unnecessary cross-service completion work. A single `TradeExecuted` caused Order to emit separate buyer and seller completion markers even though MatchEngine only needed to know whether the Order side as a whole had applied the trade. I changed the Order consumer to append buyer and seller `OrderMatchedV1` events in one transaction, with deterministic lock ordering and idempotent link inserts, then emit one trade-level `OrderTradeApplied` marker. That reduced Order outbox writes from the `4000` class to `2000` for a 2000-trade run, reduced MatchEngine completion-view updates from `6000` to `4000`, and improved full completed-trade throughput from `389.14 TPS` to `422.12 TPS` while keeping final queues and DLQ at zero.

## Sustained Fixed-Rate Load Test

Problem:

- The guarded 2000-trade runs are useful regression benchmarks, but they are burst-drain tests:
  - the generator publishes the BUY leg as fast as possible;
  - the system drains the broker and downstream services;
  - TPS is calculated as `matches / elapsedSeconds`.
- This does not prove that the system can sustain a target rate for a longer interval.

Added test mode:

- Added `scripts/load-test/run-global-matched-e2e-sustained.sh`.
- Added fixed-rate BUY publishing to `MatchedE2eLoadGenerator`.
- The SELL leg is still published first without pacing to preload the resting order book.
- The BUY leg is paced by `TARGET_TPS`.

Default sustained test:

```bash
bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

Defaults:

```text
TARGET_TPS=2000
DURATION_SECONDS=40
EVENTS=TARGET_TPS * DURATION_SECONDS = 80000
PUBLISHERS=128
RESET_PG_STATS_BEFORE_RUN=true
```

Important parameter meaning:

- `TARGET_TPS` is the offered load, not a claim that the system can sustain that TPS.
- `EVENTS` controls total trades.
- `DURATION_SECONDS` controls the intended publish window only when `EVENTS` is not explicitly set.
- If `EVENTS=20000 TARGET_TPS=2000 DURATION_SECONDS=40`, the expected publish window is `10s`, not `40s`.
- To truly test `2000 TPS for 40s`, use `EVENTS=80000 TARGET_TPS=2000 DURATION_SECONDS=40`.

New result fields:

- `targetTps`
- `durationSeconds`
- `expectedBuyPublishSeconds`
- `actualBuyPublishTps`
- `drainSecondsAfterBuyPublish`

Smoke verification:

- Run `GLT_20260703_SUSTAINED_SMOKE_20`: PASS.
  - `EVENTS=20`
  - `TARGET_TPS=10`
  - `DURATION_SECONDS=2`
  - `buyPublishSeconds=1.90`
  - `actualBuyPublishTps=10.52`
  - `drainSecondsAfterBuyPublish=4.90`
  - `tradeExecutions=20`
  - `orderMatchedEvents=40`
  - `walletTradeSettlements=20`
  - `completedTrades=20`
  - final queues and DLQ were `0`

Interpretation rule:

- A sustained run passes capacity only if:
  - `actualBuyPublishTps` is close to `TARGET_TPS`;
  - `completedTrades == EVENTS`;
  - final queues and DLQ are `0`;
  - queue peaks and drain time are bounded;
  - `drainSecondsAfterBuyPublish` does not grow unbounded relative to the publish window.
- If `TARGET_TPS=2000` creates growing backlog and long drain time, the test is still useful: it proves the current system cannot yet sustain that offered load.

### Prepare vs Run-Only Mode

Problem found during the first `80000`-event sustained attempt:

- The sustained script originally always executed the full two-phase harness:
  - stop services;
  - purge queues;
  - seed Order Event Store and Wallet rows;
  - prewarm `orders_current`;
  - start services;
  - run the paced load;
  - collect final queue state.
- For `EVENTS=80000`, the prepare phase creates `160000` orders and `160000` wallet rows before the actual sustained run starts.
- This makes the test reproducible, but it mixes dataset preparation cost with the real TPS experiment.

Script change:

- `RUN_MODE=prepare-run` remains the default and preserves the old reproducible behavior.
- `RUN_MODE=prepare` prepares the dataset and exits before starting the load.
- `RUN_MODE=run-only` skips seed/projection and runs against an already prepared, unused dataset.

Examples:

```bash
MARKET_ID=GLT_2000TPS_DATASET_001 \
TARGET_TPS=2000 \
DURATION_SECONDS=40 \
RUN_MODE=prepare \
bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

```bash
MARKET_ID=GLT_2000TPS_DATASET_001 \
TARGET_TPS=2000 \
DURATION_SECONDS=40 \
RUN_MODE=run-only \
bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

Dataset reuse rule:

- The same prepared dataset can be used for one clean `run-only` attempt.
- It is not safely reusable after a successful run because the run mutates:
  - Order Event Store;
  - `orders_current`;
  - Wallet balances;
  - MatchEngine trade tables;
  - Redis order book state.
- Repeated runs should use either:
  - a new `MARKET_ID`;
  - a prebuilt pool of datasets;
  - or a database snapshot/restore taken immediately after `RUN_MODE=prepare`.

Testing-layer distinction:

- `matched-sustained` measures confirmed-order matching and trade settlement throughput.
- `full-system-sustained` should separately measure user order submission through Order, Wallet reservation, MatchEngine, and settlement.
- These two layers cannot fully share the same prepared data because full-system testing must create orders through the normal service path, while matched-sustained starts from already confirmed orders.

### Sustained Hotspot Probe: 10000 Trades at 2000 Offered TPS

Run:

```text
MARKET_ID=GLT_20260703_SUSTAINED_HOTSPOT_10K
EVENTS=10000
TARGET_TPS=2000
DURATION_SECONDS=5
PUBLISHERS=128
RUN_MODE=prepare-run
RESET_PG_STATS_BEFORE_RUN=true
```

Result:

- `actualBuyPublishTps=1999.03`
- `buyPublishSeconds=5.00`
- `drainSecondsAfterBuyPublish=21.89`
- `elapsedSeconds=26.89`
- `matchedE2eTps=371.83`
- `tradeExecutions=10000`
- `orderMatchedEvents=20000`
- `walletTradeSettlements=10000`
- `completedTrades=10000`
- final queues and DLQ were `0`

Interpretation:

- The generator successfully offered roughly `2000 TPS` for the BUY leg.
- The system completed correctly, but it could not sustain that offered load.
- The backlog drained after publishing stopped, so this is a throughput bottleneck rather than correctness failure.

Hot table stats after resetting PostgreSQL stats before the run:

Order DB:

- `order_stream_heads`: `idx_scan=60000`, `n_tup_upd=20000`
- `orders_current`: `idx_scan=40000`, `n_tup_upd=20000`
- `order_execution_links`: `idx_scan=20000`, `n_tup_ins=20000`
- `order_event_store`: `idx_scan=10129`, `n_tup_ins=20000`
- `order_event_outbox`: `idx_scan=9785`, `n_tup_ins=10000`, `n_tup_upd=10000`

Wallet DB:

- `wallets`: `idx_scan=20000`, `n_tup_upd=20000`
- `trade_settlements`: `idx_scan=10000`, `n_tup_ins=10000`
- `outbox`: `n_tup_ins=10000`, `n_tup_upd=10000`

MatchEngine DB:

- `trade_completion_view`: `idx_scan=30191`, `n_tup_ins=10000`, `n_tup_upd=20000`
- `trade_outbox`: `idx_scan=7382`, `n_tup_ins=10000`, `n_tup_upd=10000`
- `trade_executions`: `idx_scan=10000`, `n_tup_ins=10000`

Hotspot ranking:

1. Order DB matched-apply path:
   - `order_stream_heads_pkey idx_scan=60000`
   - `orders_current_pkey idx_scan=40000`
   - buyer and seller orders still create large per-trade DB round trips.
2. MatchEngine completion tracking:
   - `trade_completion_view_pkey idx_scan=30168`
   - completion view still has mutable update pressure.
3. Wallet settlement:
   - `wallets_user_id_key idx_scan=20000`
   - expected because every trade updates buyer and seller wallets.

Next optimization target:

- Inspect Order `TradeExecuted` consumer / matched-apply path first.
- The immediate question is whether buyer and seller matched application still performs avoidable repeated head lookup, projection lookup, idempotency check, or event append work.
- Do not start by optimizing Wallet; its write volume is more business-essential and currently lower-ranked than Order.

### Order CQRS/Event-Sourcing Hot Path Review

Context:

- Order was refactored to event sourcing + CQRS first for correctness.
- The first CQRS version prioritized correctness and replayability, not sustained hot-path write efficiency.
- The sustained hotspot probe showed Order DB as the largest pressure source.

Current `TradeExecuted` flow in Order:

```text
TradeExecutedListener
  -> OrderEventSourcingService.applyTrade
  -> OrderEventAppender.appendTradeMatchedFromCaughtUpProjectionIfTradeLinksAbsent
```

Fast path behavior:

1. Lock buyer and seller rows through `lockCaughtUpProjection`.
2. `lockCaughtUpProjection` joins:
   - `order_stream_heads`
   - `orders_current`
3. It requires:
   - `orders_current.aggregate_version = order_stream_heads.current_version`
   - status is matchable
   - remaining amount is sufficient
4. Insert buyer/seller `order_execution_links`.
5. Insert buyer/seller `OrderMatchedV1` events.
6. Update buyer/seller `order_stream_heads`.
7. Insert one shared `OrderTradeApplied` outbox message.
8. The scheduled projector later consumes `OrderMatchedV1` and updates `orders_current`.

Observed write/read amplification for `10000` trades:

- `order_stream_heads idx_scan=60000`
  - about `20000` from projection/head locking;
  - about `20000` from head updates;
  - about `20000` from FK checks when inserting event-store rows.
- `orders_current idx_scan=40000`
  - about `20000` from fast-path validation;
  - about `20000` from projection updates.
- `orders_current n_tup_upd=20000`
  - caused by the read-model projector catching up during the measured run.
- `order_event_store n_tup_ins=20000`
  - expected: buyer and seller each append one matched event.
- `order_execution_links n_tup_ins=20000`
  - expected: buyer and seller each record idempotency/application link.

Architecture issue:

- `orders_current` is a read projection, but the current fast path uses it for synchronous command-side validation.
- This makes the read model part of the write hot path.
- It helped avoid full event-stream replay, but it also reintroduced `orders_current` as a hot table during matching.
- This weakens the CQRS separation: projection is no longer purely eventually consistent read state.

Immediate optimization options:

1. Split business completion from read-model catch-up in the load test.
   - During measured run, keep projection prewarmed but stop scheduled projection catch-up.
   - Measure business completion from:
     - `OrderMatchedV1` appended;
     - Wallet settled;
     - MatchEngine completion marker received.
   - Measure `orders_current` catch-up as a separate read-model lag metric.
   - Expected impact: removes `orders_current n_tup_upd=20000` from the measured hot path.

2. Batch buyer/seller SQL inside the existing transaction.
   - Replace two separate projection-lock queries with one stable-order `IN (...) FOR UPDATE` query.
   - Replace two separate execution-link inserts with one multi-row insert.
   - Replace two separate event inserts with one multi-row insert if ordering/hash handling remains clear.
   - Replace two separate head updates with one `UPDATE ... FROM (VALUES ...)`.
   - This reduces DB round trips even if row-level write count remains similar.

3. Move command-side matchability state out of `orders_current`.
   - Add or extend a write-side aggregate state/head table with:
     - current version;
     - last hash;
     - user id;
     - status;
     - remaining amount.
   - Use this as the authoritative command-side snapshot.
   - Keep `orders_current` as rebuildable read projection only.
   - This is a larger but cleaner CQRS design.

Recommended next step:

- First implement option 1 in the load test and profile again.
- If TPS improves materially, the projector was competing with the command hot path.
- Then implement option 2 to reduce transaction round trips.
- Keep option 3 as the architectural cleanup if Order remains the dominant bottleneck.

### Order Command-Side State Fix

Decision:

- Do not solve the main bottleneck by only changing the load test.
- The actual architecture issue is that `TradeExecuted` command handling reads `orders_current`, which is supposed to be a read projection.
- Move hot-path validation state into the command-side stream head instead.

Change:

- Extended `order_service.order_stream_heads` with command-side state:
  - `user_id`
  - `remaining_amount`
  - `status`
- `OrderEventAppender` now updates this state whenever it appends an Order event:
  - `OrderSubmissionRequestedV1` -> `PENDING_ASSET_CHECK`, initial remaining amount.
  - `OrderAssetReservationConfirmedV1` -> `OPEN`.
  - `OrderAssetReservationFailedV1` -> `REJECTED`.
  - `OrderMatchedV1` -> decrement remaining amount, set `MATCHED` or `PARTIALLY_MATCHED`.
  - `OrderCancelledV1` -> `CANCELLED`.
- `TradeExecuted` fast path now locks and validates `order_stream_heads` only.
- It no longer joins `orders_current`.
- Buyer/seller stream heads are locked in one stable-order SQL query.
- Buyer/seller `order_execution_links` are inserted with one multi-row insert.

Why this is better:

- `orders_current` returns to being a rebuildable read model.
- Command correctness no longer depends on projection freshness.
- A stale read projection no longer forces fallback to event replay or blocks trade application.
- The write hot path now depends on command-side state owned by the aggregate stream.

Expected impact in the next sustained probe:

- `orders_current idx_scan` caused by Order command handling should drop.
- `orders_current n_tup_upd` may still exist because the projector updates the read model after events are appended.
- `order_stream_heads` remains hot because it is now the explicit command-side aggregate state and concurrency guard.
- The next profiling question becomes whether command-side head writes are acceptable, or whether the state table needs further batching/partitioning.

Verification run:

```text
MARKET_ID=GLT_20260703_COMMAND_STATE_HOTSPOT_10K_R2
EVENTS=10000
TARGET_TPS=2000
DURATION_SECONDS=5
PUBLISHERS=128
RUN_MODE=prepare-run
RESET_PG_STATS_BEFORE_RUN=true
```

Result:

- `actualBuyPublishTps=1999.45`
- `buyPublishSeconds=5.00`
- `drainSecondsAfterBuyPublish=19.70`
- `elapsedSeconds=24.70`
- `matchedE2eTps=404.82`
- `tradeExecutions=10000`
- `orderMatchedEvents=20000`
- `walletTradeSettlements=10000`
- `completedTrades=10000`
- final queues and DLQ were `0`

Comparison with previous sustained hotspot probe:

| Metric | Before command state | After command state |
|---|---:|---:|
| `matchedE2eTps` | `371.83` | `404.82` |
| `elapsedSeconds` | `26.89` | `24.70` |
| `drainSecondsAfterBuyPublish` | `21.89` | `19.70` |
| `orders_current idx_scan` | `40000` | `20000` |
| `orders_current n_tup_upd` | `20000` | `20000` |
| `order_stream_heads idx_scan` | `60000` | `60000` |

Interpretation:

- The command path no longer reads `orders_current`; its index scans dropped by half.
- The remaining `orders_current` scans/updates come from the read-model projector catching up after `OrderMatchedV1`.
- `matchedE2eTps` improved by roughly `8.9%`.
- `order_stream_heads` is still the hottest Order table because it is now the explicit command-side aggregate state and lock point.
- The next optimization should either:
  - remove projection catch-up from the measured business-completion path; or
  - further reduce command-side round trips around stream head update/event append/outbox insert.

## 2026-07-06 Next Bottleneck Ticket: Write Amplification Reduction

Latest accepted business-gated sustained result:

- Run: `GLT_20260706_BUSINESS_GATE_METRICS_10K_R4`
- Target: `10000` matched trades, `TARGET_TPS=2000`, `PUBLISHERS=128`
- Result: `businessMatchedE2eTps=361.79`
- Business boundary:
  - MatchEngine persisted `TradeExecuted`.
  - Order command-side state appended buyer/seller `OrderMatchedV1`.
  - Wallet settled the trade.
  - MatchEngine received completion markers.
  - RabbitMQ relevant queues reached ready/unacked `0`.
  - Order projection is measured as lag only; it is not part of the TPS gate.

Measured stage timings:

| Stage | Seconds | Effective TPS | Interpretation |
|---|---:|---:|---|
| Buy publish | `5.00` | `1999.32` | Driver can offer the target load in the valid R4 run. |
| Trade executions persisted | `8.98` | `1114.02` | MatchEngine matching/trade creation is faster than downstream command application. |
| Order command matched | `22.61` | `442.27` | Order command application is part of the main bottleneck. |
| Wallet settled | `22.61` | `442.27` | Wallet settlement completes at roughly the same pace as Order. |
| Completion markers completed | `22.97` | `435.43` | Completion convergence closely follows Order/Wallet. |
| Queue fully drained | `27.64` | `361.79` | In-flight ack/drain tail defines the final business-gated TPS. |
| Order projection caught up | `27.30` | N/A | Projection lag was `4.33s`; diagnostic only. |

Run-only PostgreSQL write amplification from the lower-observation R5 probe:

| Service | Table | Run-only operations | Meaning |
|---|---|---:|---|
| Order | `order_stream_heads` | `20000 updates` | Two command-side aggregate heads per trade. |
| Order | `order_event_store` | `20000 inserts` | Buyer and seller each append one `OrderMatchedV1`. |
| Order | `order_execution_links` | `20000 inserts` | Buyer/seller idempotency link per trade. |
| Order | `order_event_outbox` | `10000 inserts + 10000 updates` | One shared completion marker outbox per trade plus publish marking. |
| Order | `orders_current` | about `20000 updates` | Async read-model catch-up; not part of business gate but still competes for DB resources. |
| Wallet | `wallets` | `20000 updates` | Buyer and seller balance mutation per trade. |
| Wallet | `trade_settlements` | `10000 inserts` | Settlement idempotency/fact row. |
| Wallet | `outbox` | `10000 inserts + 10000 updates` | One completion marker outbox per trade plus publish marking. |
| MatchEngine | `trade_executions` | `10000 inserts` | Canonical trade fact. |
| MatchEngine | `trade_completion_view` | `10000 inserts + 20000 updates` | One row created, then Order and Wallet markers update it. |
| MatchEngine | `trade_outbox` | `10000 inserts + 10000 updates` | TradeExecuted outbox plus publish marking. |

### Epic 10: Order Command Write Amplification

Problem:

- Each trade affects two independent Order aggregates, so some write amplification is domain-correct.
- Current hot path still writes many rows per trade:
  - two event-store rows;
  - two stream-head updates;
  - two idempotency-link rows;
  - one outbox row plus publish update;
  - async projection updates.
- The current design preserves event sourcing correctness but limits business TPS to roughly `400-440` command applications/s in 10k probes.

Constraints:

- Do not put `orders_current` back into the command hot path.
- Do not remove buyer/seller order events; they are the per-order audit trail and event-sourced truth.
- Keep duplicate `TradeExecuted` redelivery safe.
- Keep buyer/seller partial-fill protection through command-side `remaining_amount` and stable row locking.

Candidate tasks:

| ID | Task | Acceptance Criteria |
|---|---|---|
| TPS-10-01 | Profile Order transaction round trips | Add scoped timing/logging or tests proving how many SQL statements run per `TradeExecuted`; distinguish row count from round-trip count. |
| TPS-10-02 | Batch buyer/seller event append/head update further if gaps remain | Successful trade application uses the minimum safe number of SQL round trips while keeping per-order version/hash chains deterministic. |
| TPS-10-03 | Evaluate `order_execution_links` as append-only marker vs derived projection | Decide whether the link table remains a hot idempotency gate or can be replaced by deterministic event IDs / event-store uniqueness without weakening duplicate safety. |
| TPS-10-04 | Isolate Order read-model projector from business hot path | Projection remains async and measurable; it must not compete with command consumers for critical DB pool capacity during business TPS measurement. |
| TPS-10-05 | Re-run 10k business-gated probe | Compare `order_stream_heads`, `order_event_store`, `order_execution_links`, `order_event_outbox`, `orders_current` stats and stage TPS. |

Initial recommendation:

- Start with `TPS-10-01`.
- Do not remove `order_execution_links` until duplicate/redelivery tests prove event-store uniqueness can replace it.
- If projector competition is material, tune pool isolation or pause projection catch-up during business TPS probes, but keep projection lag measured.

Current code review finding:

- Order buyer/seller command application already performs the obvious batching:
  - buyer/seller heads are locked in one stable-order query;
  - buyer/seller execution links are inserted through one multi-row `WITH input ... INSERT`;
  - buyer/seller `OrderMatchedV1` events are inserted through one multi-row statement;
  - buyer/seller stream heads are updated through one `UPDATE ... FROM input`;
  - one shared `OrderTradeApplied` outbox row is inserted per trade.
- Therefore the next Order optimization should not be another blind batching pass.
- The remaining Order decisions are architectural:
  - whether `order_execution_links` is worth keeping as a hot idempotency gate;
  - whether projection workers should be further isolated from business consumers;
  - whether command-state lock/head writes are acceptable for the target TPS.
- Default stance: keep the link table until duplicate/redelivery tests prove deterministic event IDs and event-store uniqueness can replace it safely.

2026-07-06 ticket update:

- Current accepted business-gated baseline is about `361.79 matched trades/s` for `10000` matched trades.
- `businessMatchedE2eTps` explicitly excludes `orders_current` projection completion.
- Projection lag is still measured, but it is not a pass/fail gate for business TPS because projection was intentionally moved out of the transaction hot path.
- The Order-side bottleneck is therefore not "projection completion is slow"; it is "the command-side matched application still writes too much per trade and competes with other DB work."

Order write amplification work items:

| ID | Priority | Task | Design intent | Acceptance Criteria |
|---|---:|---|---|---|
| TPS-10-06 | P0 | Measure exact SQL round trips in `TradeExecuted` Order apply | Separate unavoidable row writes from avoidable JDBC/transaction round trips. | One focused test/log output shows per trade: head lock count, link insert count, event insert count, head update count, outbox insert count. |
| TPS-10-07 | P0 | Batch buyer/seller append path where hash/version rules allow | Keep one transaction, but reduce duplicated SQL calls for buyer/seller orders. | Buyer/seller links and head updates use set-based SQL where safe; event hash/version chain remains deterministic. |
| TPS-10-08 | P1 | Evaluate replacing `order_execution_links` hot idempotency table with deterministic event uniqueness | Reduce one hot insert per order side if event-store uniqueness can prove duplicate safety. | Duplicate `TradeExecuted` redelivery still creates no duplicate `OrderMatchedV1`, no negative remaining amount, and still emits at most one completion outbox marker per trade. |
| TPS-10-09 | P1 | Isolate Order projector DB pool or throttle during business load | Projection must not steal command-side DB capacity during the business TPS gate. | Business TPS run reports projection lag separately; command consumers keep stable DB wait time while projection catches up later. |
| TPS-10-10 | P2 | Consider command-side snapshot compaction inside `order_stream_heads` only | Keep event sourcing truth while avoiding read-model dependency. | `orders_current` remains rebuildable; command correctness uses stream head state and event-store constraints only. |

Order non-goals:

- Do not remove `OrderMatchedV1` buyer/seller events just to increase TPS; that would damage the per-order event-sourcing story.
- Do not use `orders_current` again for command validation.
- Do not solve the problem by only increasing consumer concurrency; previous probes showed DB write pressure, not only queue starvation.

Architect review questions:

1. Is the remaining Order write volume acceptable as the cost of event-sourced buyer/seller aggregates, or should the matched-apply path introduce a trade-level batch append abstraction?
2. Can `order_execution_links` be replaced by deterministic event-store uniqueness, or does that blur idempotency and audit responsibilities too much?
3. Should Order projection workers be throttled or isolated by DB pool during matched E2E probes, since projection is not part of business TPS?
4. What invariant must remain non-negotiable?
   - A duplicated `TradeExecuted` cannot create duplicate `OrderMatchedV1`.
   - A stale projection cannot block command-side match application.
   - A later trade cannot overfill an order; command-side `remaining_amount` and row locking remain the guard.

### Epic 11: MatchEngine Completion Write Amplification

Problem:

- `trade_completion_view` currently receives one insert and two updates per trade:
  - trade fact creates or initializes completion row;
  - Order completion marker updates `order_applied_at`;
  - Wallet completion marker updates `wallet_settled_at`;
  - completion convergence updates `completed_at` as part of marker handling.
- This makes completion tracking mutable and write-heavy.
- It is not the source of trade truth; `trade_executions` remains the canonical fact.

Constraints:

- `TradeExecuted` must stay durable before Order/Wallet react.
- Order and Wallet must remain independently idempotent.
- The system must tolerate Order-before-Wallet and Wallet-before-Order marker arrival.
- Completion tracking is consistency/reconciliation state, not the canonical trade fact.

Candidate tasks:

| ID | Task | Acceptance Criteria |
|---|---|---|
| TPS-11-01 | Model completion tracking alternatives | Compare mutable `trade_completion_view` vs append-only `trade_completion_markers` plus projector/materialized view. |
| TPS-11-02 | Add append-only completion marker log prototype | Order/Wallet marker consumers insert marker rows with unique `(trade_id, service)` and avoid updating the same completion row on every marker. |
| TPS-11-03 | Build completion projection/reconciler | A lower-priority projector derives completion status from marker rows; business gate can query derived completion only after marker queues drain. |
| TPS-11-04 | Preserve delayed/requeue repair semantics | Delayed completion detection still finds missing Order/Wallet markers and can requeue `TradeExecuted` safely. |
| TPS-11-05 | Re-run 10k business-gated probe | `trade_completion_view` hot updates should drop; completion correctness and final queues remain valid. |

Initial recommendation:

- Start with `TPS-11-01` before code.
- The likely target is append-only marker log + derived completion view, but the exact business gate must be defined carefully:
  - canonical trade truth: `trade_executions`;
  - service completion evidence: marker log;
  - query/read model: completion view/projector.
- Do not move Order/Wallet correctness into MatchEngine SQL.

Current code review finding:

- `TradeCompletionService.markTradeExecuted(...)` inserts or updates `trade_completion_view`.
- `markOrderApplied(...)` inserts or updates the same row and may set `completed_at`.
- `markWalletSettled(...)` inserts or updates the same row and may set `completed_at`.
- This explains the observed `trade_completion_view = 10000 inserts + 20000 updates` for `10000` trades.
- This is a better first architecture target than Order batching because:
  - it is not the canonical trade fact;
  - it is naturally a convergence/read model;
  - Order/Wallet completion evidence can be represented as append-only markers;
  - mutable row contention can be moved out of the hot marker listeners.

### Epic 11 implementation pass 1: append-only completion markers

Decision:

- Move Order/Wallet completion evidence out of the mutable `trade_completion_view` hot listener path.
- Keep `trade_executions` as the canonical trade fact.
- Keep `trade_completion_view` as a derived/reconciliation view for delayed detection and operational visibility.
- Use append-only/idempotent marker rows as the business evidence that Order and Wallet consumed `TradeExecuted`.

Implemented changes:

- Added `match_engine.trade_completion_markers`:
  - `trade_id`
  - `marker_type`
  - `marker_at`
  - `created_at`
  - primary key: `(trade_id, marker_type)`
- Changed `TradeCompletionService.markOrderApplied(...)`:
  - before: upsert `trade_completion_view`, set `order_applied_at`, maybe set `completed_at`;
  - after: insert marker `(trade_id, ORDER_APPLIED, applied_at) ON CONFLICT DO NOTHING`.
- Changed `TradeCompletionService.markWalletSettled(...)`:
  - before: upsert `trade_completion_view`, set `wallet_settled_at`, maybe set `completed_at`;
  - after: insert marker `(trade_id, WALLET_SETTLED, settled_at) ON CONFLICT DO NOTHING`.
- Changed `completeReadyRows()`:
  - now derives `order_applied_at`, `wallet_settled_at`, and `completed_at` from marker rows in batch.
- Changed delayed completion queries:
  - missing markers are now detected from `trade_completion_markers`, not only from nullable columns in `trade_completion_view`.
- Changed matched E2E load-test business gate:
  - `completedTrades` now counts trades that have both `ORDER_APPLIED` and `WALLET_SETTLED` markers and a `trade_executions` row;
  - `trade_completion_view.completed_at` becomes projection/reconciliation state, not the hot-path business completion source.

Expected effect:

- Hot Order/Wallet completion listeners no longer update the same mutable completion row.
- The previous per-10k `trade_completion_view` cost of `10000 inserts + 20000 updates` should move toward:
  - `10000 trade_completion_view inserts` from trade execution;
  - `20000 trade_completion_markers inserts` from Order/Wallet markers;
  - optional/reconciler-driven `trade_completion_view` updates outside the immediate marker listener hot path.
- This does not reduce total durable evidence writes to zero; it changes the shape from mutable convergence updates to append-only marker evidence.

Correctness constraints preserved:

- Duplicate Order/Wallet marker events are idempotent through `(trade_id, marker_type)`.
- Order-before-Wallet and Wallet-before-Order are both valid.
- `TradeExecuted` remains the canonical trade fact.
- Order and Wallet still own their own command correctness.
- Delayed/requeue repair still has a view row to update repair metadata and can detect missing marker types.

Verification:

```text
eap-matchEngine:
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle \
./gradlew --no-daemon test \
  --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest \
  --tests com.eap.eap_matchengine.application.TradeCompletionReconcilerTest
```

Result: PASS.

```text
eap-order:
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle \
./gradlew --no-daemon testClasses
```

Result: PASS.

Next validation:

- Run a fresh 10k matched E2E probe after Liquibase creates `trade_completion_markers`.
- Compare:
  - `trade_completion_view n_tup_upd`;
  - `trade_completion_markers n_tup_ins`;
  - `completionMarkerReachTps`;
  - `businessMatchedE2eTps`;
  - delayed completion count.
- If `businessMatchedE2eTps` does not improve, inspect whether the new marker inserts shifted the bottleneck to marker index writes, outbox publish marking, or Order/Wallet DB paths.

Smoke validation:

```text
MARKET_ID=GLT_20260706_MARKER_SMOKE_10
EVENTS=10
TARGET_TPS=10
DURATION_SECONDS=1
PUBLISHERS=2
RUN_MODE=prepare-run
RESET_PG_STATS_BEFORE_RUN=true
```

Result: PASS.

- `tradeExecutions=10`
- `completedTrades=10` using marker evidence
- `walletTradeSettlements=10`
- `orderCommandMatchedRows=20`
- final queue ready/unacked `0`
- `projectionIncludedInBusinessGate=false`

Run-only MatchEngine DB stats after smoke:

| Table | Inserts | Updates | Meaning |
|---|---:|---:|---|
| `trade_completion_markers` | `20` | `0` | Order + Wallet markers are append-only/idempotent. |
| `trade_completion_view` | `10` | `0` | View row created by TradeExecuted; no hot marker listener updates. |
| `trade_executions` | `10` | `0` | Canonical trade facts. |
| `trade_outbox` | `10` | `10` | TradeExecuted outbox publish marking remains. |

Smoke conclusion:

- The first write-shape goal is achieved.
- The next meaningful benchmark is a 10k business-gated run to compare `businessMatchedE2eTps`, marker insert cost, and whether Order/Wallet DB paths become the clear remaining bottleneck.

10k marker validation:

```text
MARKET_ID=GLT_20260706_MARKER_10K_R1
EVENTS=10000
TARGET_TPS=2000
DURATION_SECONDS=5
PUBLISHERS=128
TIMEOUT_SECONDS=300
RUN_MODE=prepare-run
RESET_PG_STATS_BEFORE_RUN=true
```

Result: PASS.

- `actualBuyPublishTps=1997.69`
- `businessMatchedE2eTps=417.61`, up from the previous accepted `361.79`
- `businessCompletionSeconds=23.95`
- `tradeExecutionReachTps=1105.35`
- `orderCommandMatchReachTps=490.57`
- `walletSettlementReachTps=490.57`
- `completionMarkerReachTps=465.04`
- `completedTrades=10000`
- `orderCommandMatchedRows=20000`
- `orderCurrentMatchedRows=20000`
- `walletTradeSettlements=10000`
- final queue ready/unacked `0`
- `projectionIncludedInBusinessGate=false`

Run-only DB stats:

| Service | Table | Inserts | Updates | Notes |
|---|---:|---:|---:|---|
| MatchEngine | `trade_completion_view` | `10000` | `0` | Hot marker listener no longer mutates the view. |
| MatchEngine | `trade_completion_markers` | `20000` | `0` | Order + Wallet completion evidence is append-only. |
| MatchEngine | `trade_executions` | `10000` | `0` | Canonical trade facts. |
| MatchEngine | `trade_outbox` | `10000` | `10000` | Outbox publish marking remains. |
| Order | `order_event_store` | `20000` | `0` | Two order-domain events per trade. |
| Order | `order_execution_links` | `20000` | `0` | Idempotency gate per order side. |
| Order | `order_stream_heads` | `0` | `20000` | Command-side state update per order side. |
| Order | `orders_current` | `0` | `20000` | Projection lag metric only, not business gate. |
| Order | `order_event_outbox` | `10000` | `10000` | Order-applied marker publish path. |
| Wallet | `trade_settlements` | `10000` | `0` | Wallet settlement facts. |
| Wallet | `wallets` | `0` | `20000` | Buyer/seller balance updates. |
| Wallet | `outbox` | `10000` | `10000` | Wallet-settled marker publish path. |

Conclusion:

- The append-only completion marker change achieved the target write-shape: `trade_completion_view` updates dropped from the previous `10000 inserts + 20000 updates` class to `10000 inserts + 0 updates`.
- Business-gated throughput improved to `417.61 matched trades/s`, but the system is still far from `2000`.
- The remaining end-to-end bottleneck is now broader service write amplification and drain tail, not the mutable MatchEngine completion row:
  - Order reaches command match at about `490 TPS`;
  - Wallet reaches settlement at about `490 TPS`;
  - completion marker evidence reaches about `465 TPS`;
  - final ready+unacked drain defines the accepted `417.61 TPS`.

Operational fix:

- Added `scripts/load-test/run-2000-ticket-marker-10k.sh` as a fixed wrapper for this benchmark.
- Rationale: Codex sandbox can run direct approved `docker` commands, but sandboxed `bash scripts/...` sub-processes cannot reliably access the Docker socket. Running a fixed wrapper as an escalated command is the clean path for Docker/RabbitMQ/Postgres-controlled load tests.

2026-07-06 ticket update:

- Current MatchEngine completion tracking performs roughly:
  - `trade_executions`: `10000 inserts`;
  - `trade_outbox`: `10000 inserts + 10000 updates`;
  - `trade_completion_view`: `10000 inserts + 20000 updates`.
- `trade_executions` is the durable成交事實 and should stay in the MatchEngine hot path.
- `trade_completion_view` is not the trade fact; it is a cross-service completion/reconciliation model.
- Therefore the main candidate is to move completion tracking from mutable-row updates toward append-only markers plus an async or lower-priority completion projector.

MatchEngine completion work items:

| ID | Priority | Task | Design intent | Acceptance Criteria |
|---|---:|---|---|---|
| TPS-11-06 | P0 | Decide business gate source for completion after append-only markers | Avoid accidentally making a read projection the business gate again. | Business gate is based on durable marker evidence and queue drain, not on a slow read-model projection. |
| TPS-11-07 | P0 | Add `trade_completion_markers` design | Order and Wallet completion become append-only facts: one marker per `(trade_id, service)`. | Schema/design has unique `(trade_id, service)`, marker timestamp, event id/correlation id, and duplicate-safe insert semantics. |
| TPS-11-08 | P1 | Replace hot `trade_completion_view` marker updates with marker inserts | Reduce mutable updates against one hot completion row. | For clean 10000-trade run, `trade_completion_view n_tup_upd` drops materially; marker rows equal expected service completions. |
| TPS-11-09 | P1 | Build completion view as derived state | Keep operational visibility without putting it in the hot path. | Completion view can be rebuilt from `trade_executions` + markers; delayed marker detection remains possible. |
| TPS-11-10 | P1 | Preserve requeue/repair semantics | Missing Order/Wallet completion must still be detectable. | A delayed/reconciliation job can identify trades missing one or both markers and requeue/recover safely. |

MatchEngine non-goals:

- Do not let Order or Wallet update the `trade_executions` canonical fact.
- Do not make MatchEngine directly mutate Order or Wallet state.
- Do not remove completion evidence just because queue drain is zero; durable service-completion evidence is still needed for reconciliation and interview defensibility.

Architecture review question opened:

- Ask Architect agent to challenge whether `trade_completion_view` should become:
  1. a purely async projection from append-only markers;
  2. a minimal command-side completion table updated only by a reconciler;
  3. or remain mutable with SQL-level optimizations.
- Ask Architect agent to challenge whether Order can safely reduce `order_execution_links`, or whether that table is still the cleanest idempotency boundary.

Architect review questions:

1. Should business E2E completion be defined by the append-only marker log reaching both `ORDER_APPLIED` and `WALLET_SETTLED`, instead of a mutable `trade_completion_view.completed_at` update?
2. If `trade_completion_view` becomes a projection, should it be removed from the hard TPS gate and replaced by marker-log counts plus queue drain?
3. How should delayed/requeue repair work without making the projector a new source of truth?
4. What invariant must remain non-negotiable?
   - `trade_executions` is the canonical trade fact.
   - Order and Wallet completion evidence must be idempotent and independently durable.
   - MatchEngine must be able to detect missing service completion and trigger repair without owning Order/Wallet business state.

## 2026-07-06 Next Ticket: TPS-12 Hot-Path Bottleneck Ranking and Safe Write-Amplification Reduction

### Trigger

The 10k append-only marker validation passed and improved business-gated throughput:

- Run: `GLT_20260706_MARKER_10K_R1`
- `actualBuyPublishTps=1997.69`
- `businessMatchedE2eTps=417.61`, up from the previous accepted `361.79`
- `tradeExecutionReachTps=1105.35`
- `orderCommandMatchReachTps=490.57`
- `walletSettlementReachTps=490.57`
- `completionMarkerReachTps=465.04`
- final RabbitMQ ready/unacked `0`
- `trade_completion_view`: `10000 inserts + 0 updates`
- `trade_completion_markers`: `20000 inserts + 0 updates`

The MatchEngine completion-row hot update problem is solved for the current benchmark. The system is still far from `2000` business-completed matched trades/s, so the next work must identify the highest-cost remaining hot path before changing domain behavior.

### Agent Workflow Review

Architect decision: Conditional approve.

- Do not move business ownership across bounded contexts to gain TPS.
- Do not bypass `order_stream_heads`, Wallet balance updates, or Order/Wallet source-of-truth invariants.
- Prefer optimizing infrastructure bookkeeping first, especially outbox publish-state updates, because those are not domain truth.
- Keep `orders_current` as a derived projection and outside the business gate.
- Any append-only infrastructure marker needs retention/compaction and unique idempotency keys to avoid moving cost into index bloat.

Performance decision: Measurement-first.

- `businessMatchedE2eTps`, not publish TPS, remains the target metric.
- MatchEngine ingress still shows visible backlog (`maxMatchEngineQueueReady=1583`, `maxMatchEngineQueueUnacked=650`), while downstream ready peaks are `0`.
- DB write amplification is likely capping completion throughput, but current table-level counters do not prove which statement consumes the most elapsed time.
- Before tuning concurrency or replacing outbox state updates, collect per-statement DB time, pool wait, RabbitMQ ack/delivery, and JVM/CPU evidence.

Merged decision:

- TPS-12 starts as a bottleneck-ranking ticket, not a direct refactor ticket.
- The first deliverable is a reproducible 10k marker run with enough DB/MQ/JVM evidence to rank the next single optimization.
- If DB elapsed time confirms outbox status updates dominate, the first safe implementation follow-up is append-only or partitioned outbox publish-state for Order and Wallet.
- If Order stream-head/current-state or Wallet balance updates dominate, optimize those within service ownership boundaries only.
- If MatchEngine consumer/ack/publish path dominates without DB saturation, tune MatchEngine consumer concurrency/prefetch/worker sizing incrementally.

### Target Definition

Primary target:

```text
Increase businessMatchedE2eTps for 10000 matched trades while preserving final ready/unacked drain and source-of-truth correctness.
```

Current accepted target baseline:

```text
businessMatchedE2eTps=417.61
businessCompletionSeconds=23.95
actualBuyPublishTps=1997.69
completedTrades=10000
final queue ready/unacked=0
```

Non-goals:

- Do not claim publish TPS as completed business TPS.
- Do not put `orders_current` projection back into the business gate.
- Do not let MatchEngine mutate Order or Wallet source-of-truth state.
- Do not remove idempotency gates without duplicate/redelivery tests proving equivalent safety.

### Current Cost Model

Run-only DB stats from `GLT_20260706_MARKER_10K_R1`:

| Service | Table | Inserts | Updates | Interpretation |
|---|---:|---:|---:|---|
| MatchEngine | `trade_executions` | `10000` | `0` | Canonical trade facts. |
| MatchEngine | `trade_outbox` | `10000` | `10000` | TradeExecuted outbox publish marking. |
| MatchEngine | `trade_completion_view` | `10000` | `0` | Completion view no longer receives hot marker updates. |
| MatchEngine | `trade_completion_markers` | `20000` | `0` | Append-only completion evidence. |
| Order | `order_event_store` | `20000` | `0` | Buyer/seller matched events. |
| Order | `order_execution_links` | `20000` | `0` | Idempotency gate per order side. |
| Order | `order_stream_heads` | `0` | `20000` | Command-side aggregate state/version. |
| Order | `orders_current` | `0` | `20000` | Async projection; diagnostic only. |
| Order | `order_event_outbox` | `10000` | `10000` | Order-applied marker outbox publish marking. |
| Wallet | `trade_settlements` | `10000` | `0` | Settlement facts. |
| Wallet | `wallets` | `0` | `20000` | Buyer/seller balance mutation. |
| Wallet | `outbox` | `10000` | `10000` | Wallet-settled marker outbox publish marking. |

Known gap:

- `pg_stat_user_tables` counts rows and scans, but it does not rank elapsed time by SQL statement.
- Queue ready/unacked shows where backlog appears, but not whether consumers are DB-bound, CPU-bound, pool-bound, or ack/publish-bound.

### Scrum Backlog

| ID | Priority | Task | Owner Role | Acceptance Criteria |
|---|---:|---|---|---|
| TPS-12-01 | P0 | Enable ranked DB statement diagnostics for the three loadtest PostgreSQL instances | Performance + Implementation Lead | `pg_stat_statements` or equivalent per-statement stats are available for Order, Wallet, and MatchEngine loadtest DBs; stats reset after seed/prewarm and before run; report captures total time, mean time, calls, rows, shared buffers if available. |
| TPS-12-02 | P0 | Add per-service pool and transaction timing to the 10k marker run report | Performance + Implementation Lead | Report includes Hikari active/idle/pending or pool wait proxy for Order, Wallet, MatchEngine during run; output can identify whether DB pool wait exists during the drain tail. |
| TPS-12-03 | P0 | Add RabbitMQ delivery/ack visibility for hot queues | Performance | Report includes ready, unacked, delivery rate, ack rate, consumers, and peak values for MatchEngine order-confirmed, Order trade-executed, Wallet trade-executed, and completion marker queues. |
| TPS-12-04 | P0 | Add JVM/host saturation snapshot for the 10k marker run | Performance | Report captures CPU, heap/GC pause signal, thread count, and process status for all three services; enough to separate DB-bound from CPU-bound consumers. |
| TPS-12-05 | P0 | Re-run the fixed 10k marker benchmark through `run-2000-ticket-marker-10k.sh` | QA + Performance | Run uses same business gate as `GLT_20260706_MARKER_10K_R1`; final ready/unacked `0`; result JSON plus diagnostic bundle are persisted under `build/load-test-reports`. |
| TPS-12-06 | P0 | Produce ranked bottleneck table | Performance | Table ranks top SQL statements / queues / pools by elapsed time and drain impact; identifies one next optimization target with evidence. |
| TPS-12-07 | P1 | Spec append-only outbox publish-state optimization if outbox update cost dominates | Architect + Performance | Design preserves domain event durability and at-least-once publishing; defines unique idempotency key, cleanup/retention, and expected reduction of outbox updates toward `0`. |
| TPS-12-08 | P1 | Spec Order command-state optimization if stream-head/link cost dominates | Architect + Performance | Keeps Order aggregate ownership, version/hash correctness, duplicate `TradeExecuted` safety, and emits at most one Order-applied marker per trade. |
| TPS-12-09 | P1 | Spec Wallet settlement optimization if wallet row/update cost dominates | Architect + Performance | Keeps Wallet balance/reservation truth, no negative balances, duplicate settlement idempotency, and at most one Wallet-settled marker per trade. |
| TPS-12-10 | P1 | Tune MatchEngine consumer path if queue/ack dominates without DB saturation | Performance + Implementation Lead | Incremental concurrency/prefetch/worker change improves `tradeExecutionReachTps` or reduces `queueFullyDrainedSeconds` without raising DLQ/retry or DB pool wait. |

### Acceptance Criteria

TPS-12 is accepted when:

- A reproducible 10k marker benchmark completes with:
  - `completedTrades=10000`
  - `orderCommandMatchedRows=20000`
  - `walletTradeSettlements=10000`
  - `projectionIncludedInBusinessGate=false`
  - final hot queue ready/unacked `0`
  - no DLQ messages
- A diagnostic bundle ranks bottlenecks with evidence, not guesses:
  - top DB statements by total elapsed time;
  - top DB statements by calls and rows;
  - pool wait/active signals by service;
  - RabbitMQ ready/unacked/delivery/ack signals;
  - JVM/CPU/GC/thread signals.
- The next implementation target is explicitly selected from one of:
  - outbox publish-state write reduction;
  - Order command-state write reduction;
  - Wallet settlement write reduction;
  - MatchEngine consumer/ack tuning.
- No architecture boundary is weakened:
  - Order remains source of truth for order state;
  - Wallet remains source of truth for balances/reservations/settlements;
  - MatchEngine remains source of truth for trade execution;
  - projections remain diagnostic/read models unless explicitly accepted otherwise.

### QA Plan

Minimum validation before any TPS-12 implementation is accepted:

- Duplicate `TradeExecuted` redelivery does not create duplicate `OrderMatchedV1`, duplicate Wallet settlement, or duplicate completion markers.
- Out-of-order Order/Wallet completion markers still complete business evidence once both markers exist.
- Outbox relay retry after crash does not lose events and does not double-apply domain state.
- Projection lag remains reported separately and does not block business TPS.
- The same fixed wrapper can reproduce the benchmark:

```text
./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_<date>_TPS12_DIAG_10K
```

### Recommended Next Action

Implement TPS-12-01 through TPS-12-06 first. Do not start TPS-12-07/08/09/10 until the ranked bottleneck table proves which path dominates elapsed time.

### TPS-12 implementation pass 1: diagnostic bundle

Implemented tooling:

- Added `pg_stat_statements` preload settings to the three loadtest PostgreSQL services in `docker-compose.loadtest.yml`.
- Added `scripts/load-test/collect-loadtest-diagnostics.sh`.
- Extended `scripts/load-test/run-global-matched-e2e-two-phase.sh` to:
  - create/reset `pg_stat_statements` after seed/prewarm and before run;
  - sample RabbitMQ queues, service process snapshots, and selected actuator metrics during run;
  - collect post-run `pg_stat_user_tables`, `pg_stat_user_indexes`, `pg_stat_statements`, and `pg_stat_activity` snapshots;
  - persist diagnostics under `build/load-test-reports/matched-e2e-two-phase-<MARKET_ID>-diagnostics/`.
- Added `scripts/load-test/run-2000-ticket-marker-10k.sh` as the fixed benchmark entrypoint for repeated 10k marker probes.

Environment update:

```text
docker compose -f docker-compose.loadtest.yml up -d order-postgres wallet-postgres match-postgres
```

This recreated the three loadtest DB containers while preserving volumes so `shared_preload_libraries=pg_stat_statements` takes effect.

Diagnostic run:

```text
./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_20260706_TPS12_DIAG_10K_R1
```

Result: PASS for correctness, diagnostic-only for throughput.

- `actualBuyPublishTps=1999.39`
- `completedTrades=10000`
- `orderCommandMatchedRows=20000`
- `walletTradeSettlements=10000`
- final hot queue ready/unacked `0`
- `businessMatchedE2eTps=187.61`
- `businessCompletionSeconds=53.30`

Important interpretation:

- This diagnostic run is not a new throughput baseline. The 1s sampler plus `pg_stat_statements` materially increased runtime versus the accepted `417.61 TPS` marker run.
- Use this run for relative bottleneck ranking only.

Ranked SQL evidence:

| Rank | Service | Statement group | Calls | Total exec ms | Interpretation |
|---:|---|---|---:|---:|---|
| 1 | Order | insert buyer/seller `order_event_store` rows | `10000` | `1925.82` | Highest measured SQL cost; domain audit/event truth. |
| 2 | MatchEngine | insert `trade_completion_markers` | `20000` | `1464.22` | Append-only marker write cost is now visible after removing view updates. |
| 3 | Order | insert `order_execution_links` idempotency rows | `10000` | `1188.23` | Strong candidate only if duplicate safety can be preserved. |
| 4 | Order | insert `order_event_outbox` | `10000` | `821.48` | Infrastructure publish path; safer optimization candidate than aggregate state. |
| 5 | MatchEngine | insert `trade_executions` | `10000` | `704.62` | Canonical trade fact; not an easy removal target. |
| 6 | Order | lock buyer/seller `order_stream_heads` | `10000` | `547.91` | Aggregate ownership/version guard; optimize carefully. |
| 7 | Order | update buyer/seller `order_stream_heads` | `10000` | `545.11` | Aggregate command-state update; optimize carefully. |
| 8 | Order | update `orders_current` projection | `20000` | `520.72` | Projection-only but still competes for DB write capacity. |
| 9 | MatchEngine | insert `trade_outbox` | `10000` | `507.63` | Infrastructure publish path. |
| 10 | Wallet | update seller wallet balance | `10000` | `465.75` | Wallet source-of-truth state. |
| 11 | Wallet | insert wallet outbox | `10000` | `398.90` | Infrastructure publish path. |
| 12 | Wallet | update buyer wallet balance | `10000` | `387.90` | Wallet source-of-truth state. |
| 13 | MatchEngine | insert `trade_completion_view` | `10000` | `368.04` | View row creation only; marker updates are gone. |
| 14 | Wallet | insert `trade_settlements` | `10000` | `359.53` | Settlement fact/idempotency. |

Queue and pool evidence:

- Hikari pending stayed `0` for Order command/consumer/projection pools and Wallet pool in all runtime samples.
- Order consumer pool active peaked at `12 / 20` in the sampled data.
- MatchEngine `orderConfirmed` queue remained the visible ingress backlog:
  - sampled peak: `messages=2993`, `ready=2343`, `unacked=650`;
  - result peak: `maxMatchEngineQueueReady=1506`, `maxMatchEngineQueueUnacked=700`.
- Downstream queues had small in-flight peaks only:
  - `order.tradeExecuted.queue` around `26` unacked;
  - `wallet.tradeExecuted.queue` around `26` unacked;
  - completion marker queues around `26` unacked.
- GC pauses were small in the sampled Order/Wallet data; no evidence of GC as primary bottleneck.

First decision from diagnostics:

- The bottleneck is not Hikari pool exhaustion.
- The next safe implementation target should be infrastructure write amplification before domain-state shortcuts:
  1. outbox publish-state write reduction across Order/Wallet/MatchEngine, because it is bookkeeping and appears in all three services;
  2. projection write isolation/throttling for `orders_current`, because it is outside the business gate but still writes heavily;
  3. only then evaluate `order_execution_links` or stream-head changes, because those protect idempotency and aggregate correctness.

Immediate follow-up:

- Open TPS-13 as an architecture/spec ticket for outbox publish-state optimization:
  - current `insert PENDING + update PUBLISHED` cost;
  - append-only published marker or partitioned publish ledger design;
  - unique idempotency key;
  - retry/crash semantics;
  - retention/compaction policy;
  - expected acceptance: outbox update count trends toward `0` without losing at-least-once publish safety.

## 2026-07-06 TPS-13 Re-scope: Order Trade Idempotency Without `order_execution_links`

### Trigger

After reviewing the TPS-12 diagnostic ranking, the outbox path is real overhead but not the primary amplifier. The largest Order-side costs were:

| Statement group | Calls | Total exec ms |
|---|---:|---:|
| Insert buyer/seller `order_event_store` rows | `10000` | `1925.82` |
| Insert buyer/seller `order_execution_links` rows | `10000` | `1188.23` |
| Lock buyer/seller `order_stream_heads` | `10000` | `547.91` |
| Update buyer/seller `order_stream_heads` | `10000` | `545.11` |
| Update `orders_current` projection | `20000` | `520.72` |
| Insert `order_event_outbox` marker | `10000` | `821.48` |

`order_execution_links` is therefore a meaningful write-amplification candidate. It is not the top cost, but it is a separate hot insert/index path that may be redundant if event-store identity can safely own TradeExecuted idempotency.

### Current Design

- `order_execution_links` has unique `(trade_id, order_id)`.
- `TradeExecuted` apply currently:
  1. locks buyer/seller `order_stream_heads`;
  2. validates both orders can match;
  3. inserts buyer/seller execution links with `ON CONFLICT DO NOTHING`;
  4. appends buyer/seller `OrderMatchedV1` events;
  5. updates buyer/seller stream heads;
  6. inserts one shared `OrderTradeApplied` outbox marker.
- Duplicate detection currently short-circuits if both links already exist.
- Event-store already has:
  - `UNIQUE(event_id)`;
  - `UNIQUE(aggregate_id, aggregate_version)`.
- Current matched event IDs are deterministic from `orderId + ':MATCHED:' + legacyMatchId`.

### Agent Workflow Review

Architect decision: Conditional.

- `order_execution_links` can be removed only if TradeExecuted idempotency explicitly moves into the event-store contract.
- Use upstream `tradeId` as the idempotency discriminator, not `legacyMatchId`.
- One `TradeExecuted` must produce exactly two `OrderMatchedV1` events or none.
- Buyer event, seller event, stream-head updates, and shared outbox marker must remain one transaction.
- One-existing-one-missing is partial-apply corruption, not a normal duplicate.
- Duplicate redelivery must recreate byte-equivalent event identity. If `occurredAt` can be null and replaced by `LocalDateTime.now()`, event-store duplicate comparison can fail after links are removed.
- Outbox idempotency must be handled: duplicate `TradeExecuted` must not create another shared outbox marker.

Performance decision: Prototype only the no-pre-read path.

- Likely faster design:
  - generate deterministic buyer/seller event IDs from `tradeId`;
  - attempt event-store insert directly with `ON CONFLICT DO NOTHING`;
  - use affected row counts to distinguish applied vs duplicate;
  - avoid pre-read/count queries and avoid exception-driven duplicate control flow.
- Likely slower design:
  - replacing links with `findByEventId`, `countByLegacyMatchId`, or duplicate-key exceptions;
  - this swaps one cheap conflict insert for extra indexed reads or expensive exception paths.
- Expected upside is bounded: best case saves most of the `order_execution_links` insert cost (`~1188ms` in the diagnostic run) minus any added event-store conflict/check overhead.

### Proposed Direction

Do not drop `order_execution_links` immediately.

Prototype a feature-flagged event-store idempotency path:

```text
eap.order.event-sourcing.trade-idempotency-source=event-store
```

Required behavior:

- Event IDs for TradeExecuted-sourced `OrderMatchedV1` use:

```text
UUID.nameUUIDFromBytes(orderId + ":TRADE_EXECUTED:" + tradeId)
```

- The hot path must not add a pre-read.
- Duplicate detection must be based on insert affected-row counts:
  - buyer inserted + seller inserted = `2`: applied;
  - buyer existing + seller existing = duplicate;
  - exactly one inserted/existing side mismatch = partial application error.
- Shared outbox marker is inserted only when both order events are newly inserted, or is idempotent and verified on duplicate.
- Existing `order_execution_links` path remains available as rollback/default until benchmark evidence is accepted.

### Design Risks

- `legacyMatchId` may not be a stable cross-service event identity. Use `tradeId`.
- Event-store `UNIQUE(aggregate_id, aggregate_version)` is sequencing protection, not TradeExecuted idempotency.
- Duplicate handling via exception or post-read can erase the expected performance gain.
- If event payload includes non-stable timestamps, duplicate `event_id` can conflict with different canonical payload. `occurredAt` must be stable for the same `TradeExecuted`.
- Removing links also removes a convenient query surface for `trade_id -> order_id` unless event payload/metadata or a derived projection replaces that operational visibility.

### Acceptance Criteria

Prototype is accepted for comparison only when:

- Correctness tests pass:
  - first `TradeExecuted` creates exactly two `OrderMatchedV1` events;
  - duplicate `TradeExecuted` creates no additional events;
  - duplicate creates no additional shared outbox marker;
  - one-existing-one-missing is rejected as partial apply;
  - null/missing `occurredAt` is either impossible or normalized to a stable value;
  - concurrent duplicate redelivery still appends at most two order events total.
- Performance test covers:
  - baseline link path;
  - event-store no-pre-read path;
  - duplicate ratio `0%`;
  - duplicate ratio `10%`;
  - high duplicate replay stress.
- The event-store path shows lower total Order SQL time without increasing:
  - `order_event_store` conflict/lookup time;
  - stream-head lock time;
  - outbox duplicate time;
  - final queue drain time.

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-13-01 | P0 | Add architecture note for event-store TradeExecuted idempotency | Documents `tradeId`-based event IDs, no-pre-read rule, duplicate/partial semantics, and rollback flag. |
| TPS-13-02 | P0 | Add tests for deterministic TradeExecuted event IDs | Buyer/seller event IDs use `tradeId`; duplicate redelivery recreates identical event identity and payload. |
| TPS-13-03 | P0 | Prototype event-store idempotency behind feature flag | Existing link path remains default; event-store mode uses affected-row counts, not pre-read or exceptions. |
| TPS-13-04 | P0 | Add duplicate/partial/concurrent tests | Covers duplicate, one-side-existing partial apply, null occurredAt handling, and concurrent redelivery. |
| TPS-13-05 | P1 | Run 10k diagnostic comparison | Compare link path vs event-store path with same wrapper and `pg_stat_statements`; decide whether to remove links. |

### Current Decision

Prototype behind a flag has been implemented in `eap-order`.

- Default remains `eap.order.event-sourcing.trade-idempotency-source=links`.
- Experimental mode is enabled with `eap.order.event-sourcing.trade-idempotency-source=event-store`.
- Event-store mode uses deterministic `TRADE_EXECUTED:{tradeId}` buyer/seller event IDs.
- Hot insert uses `ON CONFLICT (event_id) DO NOTHING`, with no pre-read on the normal apply path.
- Duplicate redelivery is accepted only when both buyer/seller events match and the shared outbox marker already exists with matching exchange/routing/message/payload.
- `order_execution_links` schema and default behavior remain in place as rollback.

Verification completed:

- `./gradlew --no-daemon testClasses` in `eap-order`: PASS.
- `./gradlew --no-daemon test` in `eap-order`: PASS.
- `./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT -Deap.integration.postgres=true`: PASS.

Open before removal:

- Run 10k A/B diagnostic comparison between `links` and `event-store`.
- Add/confirm explicit concurrent redelivery and one-side-existing partial corruption coverage if the event-store path wins performance.
- Do not remove `order_execution_links` until event-store idempotency wins both correctness and diagnostic comparison.

### 2026-07-06 TPS-13 10k A/B Probe

Ran the 10k business-gated marker probe with diagnostics enabled:

| Mode | Market ID | Result | businessMatchedE2eTps | completionMarkerReachTps | businessCompletionSeconds | completedTrades |
|---|---|---|---:|---:|---:|---:|
| `links` | `GLT_20260706_TPS13_LINKS_10K_R1` | PASS | `229.35` | `245.51` | `43.60` | `10000` |
| `event-store` | `GLT_20260706_TPS13_EVENTSTORE_10K_R1` | PASS | `179.49` | `204.89` | `55.71` | `10000` |

Correctness passed in both modes: all `10000` trades completed, queues drained, and final DLQ/ready/unacked counts were `0`.

Order SQL comparison:

| Statement group | `links` total exec ms | `event-store` total exec ms | Notes |
|---|---:|---:|---|
| Insert buyer/seller `order_event_store` rows | `2079.53` | `2517.63` | Event-store idempotency made this insert more expensive due `ON CONFLICT (event_id) DO NOTHING` on the hot event-store insert. |
| Insert buyer/seller `order_execution_links` rows | `1209.62` | `0` | Removed from hot path in event-store mode. |
| Insert shared `order_event_outbox` marker | `821.38` | `1050.29` | Worse in this run. |
| Update buyer/seller `order_stream_heads` | `559.84` | `685.73` | Worse in this run. |
| Lock buyer/seller `order_stream_heads` | `539.14` | `667.41` | Worse in this run. |
| Update `orders_current` projection | `457.48` | `563.61` | Worse in this run. |

Table stats confirmed the intended write-shape change:

- `links` mode: `order_execution_links n_tup_ins=19870`.
- `event-store` mode: `order_execution_links n_tup_ins=0`.

However, the end-to-end result did not improve. The saved `order_execution_links` insert cost was mostly offset by higher event-store insert cost and other Order-side write/lock costs, while the second run also showed slower MatchEngine completion-marker work:

- MatchEngine `trade_completion_markers` insert total exec time:
  - `links`: `1318.39ms`
  - `event-store`: `2058.98ms`
- MatchEngine completed-trades gate query total exec time:
  - `links`: `256.31ms`
  - `event-store`: `522.01ms`

Decision from this probe:

- Do not remove `order_execution_links`.
- Keep `event-store` idempotency behind the rollback flag only.
- The table is redundant in write shape, but removing it does not currently buy measurable E2E throughput.
- Next optimization should move back to the measured dominant paths: MatchEngine completion-marker cost/gate query and Order event-store/head transaction cost, not schema removal of `order_execution_links`.

## 2026-07-06 TPS-14: Reduce MatchEngine Completion Marker Write Cost

### Trigger

After TPS-13 rejected `order_execution_links` removal as the next primary optimization, the remaining measured bottleneck moved back to MatchEngine completion tracking.

Latest 10k diagnostics show `trade_completion_markers` is the largest MatchEngine write cost:

| Run | Market ID | `trade_completion_markers` calls | Total exec ms | Mean exec ms |
|---|---|---:|---:|---:|
| Links baseline | `GLT_20260706_TPS13_LINKS_10K_R1` | `20000` | `1318.39` | `0.0659` |
| Event-store experiment | `GLT_20260706_TPS13_EVENTSTORE_10K_R1` | `20000` | `2058.98` | `0.1029` |

The marker table has one unused secondary index:

```text
idx_trade_completion_markers_type(marker_type, marker_at)
```

Observed index usage in both TPS-13 10k runs:

| Run | idx_scan | idx_tup_read | idx_tup_fetch |
|---|---:|---:|---:|
| Links baseline | `0` | `0` | `0` |
| Event-store experiment | `0` | `0` | `0` |

The primary key `pk_trade_completion_markers(trade_id, marker_type)` is still required for idempotent marker insert:

```sql
INSERT INTO match_engine.trade_completion_markers
    (trade_id, marker_type, marker_at)
VALUES (?, ?, ?)
ON CONFLICT (trade_id, marker_type) DO NOTHING
```

### Decision

Open TPS-14 as the next implementation ticket.

Primary goal: remove unused MatchEngine marker-index write amplification without changing completion semantics.

Do not:

- remove `trade_completion_markers`;
- return to update-heavy `trade_completion_view` marker writes;
- change the business gate semantics;
- optimize `order_execution_links` further as part of this ticket.

### Proposed Change

Add a Liquibase migration in `eap-matchEngine` to drop the unused secondary index:

```sql
DROP INDEX IF EXISTS match_engine.idx_trade_completion_markers_type;
```

Keep:

- `trade_completion_markers` table;
- `pk_trade_completion_markers(trade_id, marker_type)`;
- existing marker insert API;
- existing delayed-completion reconciliation behavior.

### Acceptance Criteria

- Schema:
  - `idx_trade_completion_markers_type` no longer exists after migration.
  - `pk_trade_completion_markers` remains intact.
- Correctness:
  - `TradeCompletionServiceTest` passes.
  - `TradeCompletionReconcilerTest` passes.
  - 10k load test completes `completedTrades=10000`.
  - final queues/DLQ ready and unacked remain `0`.
- Performance:
  - Run the same 10k business-gated marker probe with diagnostics.
  - Compare against `GLT_20260706_TPS13_LINKS_10K_R1`.
  - Primary metric: `trade_completion_markers` total exec ms should decrease.
  - Secondary metrics should not regress materially:
    - `businessMatchedE2eTps`;
    - `completionMarkerReachTps`;
    - `queueFullyDrainedSeconds`;
    - MatchEngine `orderConfirmed` backlog.

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-14-01 | P0 | Add Liquibase migration to drop unused marker secondary index | Migration is idempotent and preserves `pk_trade_completion_markers`. |
| TPS-14-02 | P0 | Run focused MatchEngine tests | `TradeCompletionServiceTest` and `TradeCompletionReconcilerTest` pass. |
| TPS-14-03 | P0 | Run 10k marker probe with diagnostics | Result PASS, `completedTrades=10000`, queues drained. |
| TPS-14-04 | P0 | Compare against TPS-13 links baseline | Document marker insert exec time, business TPS, completion marker TPS, and queue backlog. |

### Expected Outcome

This is a low-risk cleanup, not a guaranteed large TPS jump. The expected win is bounded to removing maintenance cost for an unused index on `20000` marker inserts per 10k matched-trade run.

If TPS-14 does not move E2E throughput, keep the cleanup if marker insert cost decreases and correctness remains unchanged, then move to the next deeper bottleneck: Order event-store/head transaction cost or MatchEngine outbox relay/gate polling.

### 2026-07-06 TPS-14 Implementation and 10k Probe

Implemented in `eap-matchEngine`:

- Added Liquibase changeset `match-trade-008`.
- Migration:

```sql
DROP INDEX IF EXISTS match_engine.idx_trade_completion_markers_type;
```

Verification:

- `./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest --tests com.eap.eap_matchengine.application.TradeCompletionReconcilerTest`: PASS.
- Liquibase applied changeset `db/changelog/db.changelog-trade-execution.xml::match-trade-008::eap` during loadtest service startup.
- Post-run `pg_stat_user_indexes` no longer lists `idx_trade_completion_markers_type`.
- `pk_trade_completion_markers` remains present and active.

10k probe:

```text
./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_20260706_TPS14_DROP_MARKER_IDX_10K_R1
```

Result: PASS for correctness.

| Run | businessMatchedE2eTps | completionMarkerReachTps | businessCompletionSeconds | completedTrades | maxMatchEngineQueueReady |
|---|---:|---:|---:|---:|---:|
| TPS-13 links baseline `GLT_20260706_TPS13_LINKS_10K_R1` | `229.35` | `245.51` | `43.60` | `10000` | `534` |
| TPS-14 drop marker index `GLT_20260706_TPS14_DROP_MARKER_IDX_10K_R1` | `183.44` | `212.64` | `54.51` | `10000` | `2648` |

MatchEngine SQL comparison:

| Statement group | TPS-13 links baseline total exec ms | TPS-14 total exec ms | Interpretation |
|---|---:|---:|---|
| Insert `trade_completion_markers` | `1318.39` | `1462.51` | Did not improve in this run despite dropping the unused secondary index. |
| Insert `trade_executions` | `585.45` | `732.02` | Worse in this run. |
| Insert `trade_outbox` | `498.34` | `579.14` | Worse in this run. |
| Completed-trades gate query | `256.31` | `506.99` | Worse in this run; likely affected by backlog/run variance and repeated polling. |

Decision:

- Keep the migration as a valid schema cleanup: the dropped index had no observed read usage and no correctness role.
- Do not claim TPS improvement from TPS-14.
- The marker secondary index was not the dominant limiter; removing it did not overcome MatchEngine backlog/run variance.
- Next deeper bottleneck remains MatchEngine intake/persistence/outbox and the benchmark's completed-trades polling query, not this unused marker index.

## 2026-07-06 Benchmark Diagnostics Levels

The load-test runner now separates throughput baselines from diagnostic probes.

### Modes

| Mode | Environment | Intended Use | Runtime Sampling | DB Statement Ranking | TPS Baseline? |
|---|---|---|---|---|---|
| Baseline | `DIAGNOSTICS_LEVEL=baseline` | Measure accepted business TPS with minimal observer effect. | None during run. Final correctness and queue purge still run. | No. | Yes. |
| Light | `DIAGNOSTICS_LEVEL=light` | See queue/process shape while keeping observer cost bounded. | RabbitMQ Management HTTP API queue snapshot + service process snapshot every `DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS`, default `10s`. | No. | Maybe, but report it as light-observed TPS. |
| Deep | `DIAGNOSTICS_LEVEL=deep` | Rank SQL/index/table/wait bottlenecks and capture detailed state. | RabbitMQ queue + process + actuator scrape every `DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS`, default `1s`. | Yes, using post-run `pg_stat_statements` and table/index stats. | No. |

The fixed marker probe defaults to baseline:

```bash
./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_<date>_BASELINE_10K
```

Run light diagnostics when the question is queue/consumer shape:

```bash
DIAGNOSTICS_LEVEL=light ./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_<date>_LIGHT_10K
```

Run deep diagnostics when the question is SQL or index ranking:

```bash
DIAGNOSTICS_LEVEL=deep ./scripts/load-test/run-2000-ticket-marker-10k.sh GLT_<date>_DEEP_10K
```

### Comparison Rule

Do not compare deep diagnostic TPS directly against baseline TPS. Deep mode intentionally adds observer overhead:

- `pg_stat_statements` records every SQL statement.
- The sampler runs Docker/RabbitMQ/process/actuator collection during the same workload.
- Actuator Prometheus scrape can include DB-backed gauges.

Use a paired-run workflow instead:

1. Run baseline before a change.
2. Run deep only to rank the bottleneck.
3. Implement one scoped change.
4. Run baseline again to measure real throughput impact.
5. Run deep again only if the baseline moved or the bottleneck ranking is unclear.

For operational observability, prefer light or production-grade Prometheus/RabbitMQ exporters. Deep mode is a profiling tool, not a normal operating profile.

### 2026-07-06 Baseline / Light / Deep Comparison

After replacing `rabbitmqctl list_queues` with RabbitMQ Management HTTP API and changing light sampling from `5s` to `10s`, the 10k marker benchmark was rerun in all three modes.

| Mode | Market ID | businessMatchedE2eTps | businessCompletionSeconds | orderCommandMatchReachTps | walletSettlementReachTps | completionMarkerReachTps |
|---|---|---:|---:|---:|---:|---:|
| Baseline | `GLT_20260706_BASELINE_COMPARE_10K_R1` | `306.06` | `32.67` | `372.80` | `372.80` | `372.80` |
| Light | `GLT_20260706_LIGHT_HTTP_COMPARE_10K_R1` | `241.80` | `41.36` | `313.50` | `313.50` | `303.63` |
| Deep | `GLT_20260706_DEEP_COMPARE_10K_R1` | `264.10` | `37.86` | `345.36` | `358.30` | `345.36` |

Decision:

- Baseline remains the only valid TPS score.
- Light still adds enough observer effect that it must be labeled as light-observed TPS, even after the RabbitMQ HTTP API change.
- Deep is for ranking SQL and queue bottlenecks; it must not be used as the throughput headline.
- The RabbitMQ CLI replacement is still worthwhile because it removes Docker CLI process overhead from sampling, but the latest comparison proves it is not the whole observer-cost problem.

Deep diagnostics from `GLT_20260706_DEEP_COMPARE_10K_R1` showed two separate next tickets:

1. Benchmark measurement overhead: the MatchEngine completed-trades gate query is a large diagnostic statement and can distort probes.
2. Product hot-path amplification: Order command application remains the largest true business write chain.

## 2026-07-06 TPS-15: Reduce Benchmark Measurement Overhead

### Trigger

The load-test business gate is correct semantically, but the repeated completed-trades polling query is now visible in `pg_stat_statements` and can distort diagnostic runs.

In `GLT_20260706_DEEP_COMPARE_10K_R1`, the largest MatchEngine statement by total time was the completed-trades gate query:

| Statement group | Calls | Total exec ms | Mean exec ms | Classification |
|---|---:|---:|---:|---|
| Completed-trades gate query | `30` | `1722.95` | `57.43` | Benchmark measurement, not product hot path. |
| Insert `trade_completion_markers` | `20000` | `1274.09` | `0.064` | Product completion fact. |
| Insert `trade_executions` | `10000` | `685.68` | `0.069` | Product trade fact. |
| Insert `trade_outbox` | `10000` | `583.45` | `0.058` | Reliable publish path. |

### Decision

Open TPS-15 as a benchmark-tooling fix before using diagnostic mode to justify deeper service changes.

Primary goal: make the load-test verifier cheaper without weakening correctness.

Do not:

- remove the final correctness checks;
- return to projection-based business gating;
- hide final RabbitMQ ready/unacked drain;
- claim business TPS from diagnostic-mode runs.

### Proposed Change

Replace high-frequency full completed-trade polling with a cheaper staged verifier:

1. During the hot run, poll lightweight stage counters at a lower cadence.
2. Prefer append-only marker counts for progress:
   - expected `TradeExecuted` rows;
   - expected `ORDER_APPLIED` markers;
   - expected `WALLET_SETTLED` markers.
3. Run the heavier completed-trade correctness query only:
   - at final verification;
   - after queues are fully drained;
   - or when a timeout/debug path needs detailed incomplete-trade rows.
4. Keep final source-of-truth invariants strict.

### Acceptance Criteria

- Baseline mode still produces:
  - `tradeExecutions=10000`;
  - `orderCommandMatchedRows=20000`;
  - `walletTradeSettlements=10000`;
  - `completedTrades=10000`;
  - final RabbitMQ ready/unacked `0`;
  - final DLQ `0`.
- During-run MatchEngine completed-trades gate calls drop materially from the current `30` call class.
- `businessMatchedE2eTps` is computed from the same semantic boundary: completion facts plus final queue drain.
- Timeout/debug output still identifies missing Order or Wallet completion markers.
- Rerun baseline and deep:
  - baseline measures real throughput;
  - deep confirms measurement query no longer dominates MatchEngine SQL ranking.

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-15-01 | P0 | Find the completed-trades polling query in the load-test generator | Document current call cadence and SQL shape before editing. |
| TPS-15-02 | P0 | Add lightweight marker-count progress path | During-run progress can use marker counts without full completed-view aggregation. |
| TPS-15-03 | P0 | Preserve final strict correctness query | Final result still fails on missing trade execution, missing Order marker, missing Wallet marker, queue backlog, or DLQ. |
| TPS-15-04 | P0 | Rerun 10k baseline and deep | Compare completed-trades gate query calls/time, business TPS, and final correctness. |

### TPS-15 Implementation Pass 1

Implemented in `MatchedE2eLoadGenerator`:

- Added progress-vs-strict completion checking in the downstream wait loop.
- During the hot wait loop, completed-trade progress now uses lightweight append-only counts:
  - `trade_executions`;
  - `trade_completion_markers` with `ORDER_APPLIED`;
  - `trade_completion_markers` with `WALLET_SETTLED`.
- The strict completed-trade query using `TradeExecuted + ORDER_APPLIED + WALLET_SETTLED` by `trade_id` still runs before accepting the result and on timeout/final verification.
- `truncateMatchTestData` now also truncates `match_engine.trade_completion_markers`; otherwise marker-count progress could be polluted by stale marker rows from earlier runs.

Verification:

- `eap-order`: `./gradlew --no-daemon testClasses` PASS.
- 10-event E2E smoke: `GLT_20260706_TPS15_SMOKE` PASS.

Smoke result:

| Metric | Value |
|---|---:|
| `tradeExecutions` | `10` |
| `completedTrades` | `10` |
| `orderMatchedEvents` | `20` |
| `orderCommandMatchedRows` | `20` |
| `walletTradeSettlements` | `10` |
| final queue ready/unacked | `0` |
| final DLQ | `0` |

Remaining TPS-15 validation:

- Run a 10k baseline and 10k deep comparison.
- Confirm completed-trades strict gate query calls drop from the current `30` call class toward final-verification only.
- Compare `businessMatchedE2eTps` against `GLT_20260706_BASELINE_COMPARE_10K_R1`.

### TPS-15 10k Validation

10k baseline after TPS-15:

| Run | businessMatchedE2eTps | businessCompletionSeconds | completedTrades | final ready/unacked |
|---|---:|---:|---:|---:|
| Before TPS-15 baseline `GLT_20260706_BASELINE_COMPARE_10K_R1` | `306.06` | `32.67` | `10000` | `0` |
| TPS-15 baseline `GLT_20260706_TPS15_BASELINE_10K_R1` | `314.66` | `31.78` | `10000` | `0` |

This is a modest baseline improvement and should be treated as benchmark-cleanup evidence, not a product hot-path optimization.

10k deep after TPS-15:

| Run | businessMatchedE2eTps | businessCompletionSeconds | completedTrades | final ready/unacked |
|---|---:|---:|---:|---:|
| Before TPS-15 deep `GLT_20260706_DEEP_COMPARE_10K_R1` | `264.10` | `37.86` | `10000` | `0` |
| TPS-15 deep `GLT_20260706_TPS15_DEEP_10K_R1` | `269.34` | `37.13` | `10000` | `0` |

MatchEngine measurement-query impact:

| Statement group | Before TPS-15 deep | TPS-15 deep | Decision |
|---|---:|---:|---|
| Strict completed-trades gate query | `30 calls / 1722.95ms` | `1 call / 5.75ms` | Removed from hot loop. |
| Lightweight completion progress query | N/A | `28 calls / 52.73ms` | Acceptable progress cost. |

TPS-15 decision:

- Keep the progress-vs-strict completion split.
- The strict business completion query is no longer the dominant MatchEngine diagnostic statement.
- The remaining deep ranking is now cleaner and points back to true write amplification.

Latest TPS-15 deep bottleneck ranking:

| Rank | Service | Statement group | Calls | Total exec ms |
|---:|---|---|---:|---:|
| 1 | Order | Insert buyer/seller `order_event_store` rows | `10000` | `2080.29` |
| 2 | MatchEngine | Insert `trade_completion_markers` | `20000` | `1136.71` |
| 3 | Order | Insert buyer/seller `order_execution_links` rows | `10000` | `1124.57` |
| 4 | Order | Insert shared `order_event_outbox` marker | `10000` | `1045.64` |
| 5 | MatchEngine | Insert `trade_executions` | `10000` | `832.74` |
| 6 | MatchEngine | Insert `trade_outbox` | `10000` | `657.28` |
| 7 | Order | Update `order_stream_heads` | `10000` | `595.62` |
| 8 | Order | Update `orders_current` projection | `20000` | `581.70` |
| 9 | Order | Lock `order_stream_heads` | `10000` | `578.36` |

Next implementation target remains TPS-16: Order command write amplification. The first code pass should not remove `order_execution_links`; TPS-13 already showed that path regressed. Start with measuring and reducing Order command apply round trips around event-store append, stream-head lock/update, link insert, and shared outbox insert.

## 2026-07-06 TPS-16: Reduce Order Command Write Amplification

### Trigger

After TPS-13 rejected removing `order_execution_links` as the next throughput win, the latest deep diagnostics still show Order command application as the largest true business write chain.

`GLT_20260706_DEEP_COMPARE_10K_R1` Order SQL ranking:

| Statement group | Calls | Total exec ms | Classification |
|---|---:|---:|---|
| Insert buyer/seller `order_event_store` rows | `10000` | `1943.68` | Domain truth. |
| Insert buyer/seller `order_execution_links` rows | `10000` | `1187.69` | Idempotency marker. |
| Insert shared `order_event_outbox` marker | `10000` | `857.04` | Reliable publish path. |
| Update `order_stream_heads` | `10000` | `570.08` | Domain version/head. |
| Lock `order_stream_heads` | `10000` | `540.23` | Domain concurrency. |
| Update `orders_current` projection | `20000` | `540.44` | Read-model catch-up competing for DB resources. |

### Decision

Open TPS-16 as the next product hot-path optimization ticket.

Primary goal: reduce Order command-side database round trips or DB pool contention without weakening event sourcing, idempotency, or the one shared `OrderTradeApplied` marker per trade.

Do not:

- remove `order_execution_links` immediately;
- move idempotency into `order_event_store` unless a fresh A/B proves it is faster;
- make `orders_current` a business gate again;
- reduce correctness by dropping stream-head locking or event hash/version guarantees.

### Proposed Change

Work in this order:

1. Measure exact Order command apply round trips per `TradeExecuted`.
2. Separate unavoidable row writes from avoidable JDBC calls.
3. Batch or set-base only the parts that preserve deterministic order version/hash rules.
4. Isolate or throttle Order projection so read-model catch-up does not steal command-side DB pool capacity during the business gate.
5. Keep `order_execution_links` as the default hot idempotency gate unless a later benchmark proves a replacement wins.

### Acceptance Criteria

- Duplicate `TradeExecuted` redelivery still:
  - creates no duplicate `OrderMatchedV1`;
  - does not change remaining amount twice;
  - emits at most one shared `OrderTradeApplied` marker per trade.
- Buyer and seller order events stay in one transaction with deterministic lock ordering.
- Stream head version/hash correctness is preserved.
- Projection remains rebuildable and reported as lag only.
- 10k baseline comparison shows one of:
  - lower Order SQL total time;
  - lower Order DB pool wait/transaction time;
  - higher `orderCommandMatchReachTps`;
  - higher business-gated TPS with final queues/DLQ at `0`.

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-16-01 | P0 | Instrument or test exact Order command apply SQL round trips | One focused output lists link insert, head lock, event insert, head update, outbox insert, and projection competition per trade. |
| TPS-16-02 | P0 | Identify safe batch boundaries for buyer/seller apply | Documents which statements can be batched without breaking event version/hash order. |
| TPS-16-03 | P1 | Implement first safe round-trip reduction | Preserves duplicate safety and one shared outbox marker; focused tests pass. |
| TPS-16-04 | P1 | Isolate or throttle Order projector under loadtest profile | Command consumers keep priority over projection during business gate; projection lag remains visible. |
| TPS-16-05 | P0 | Rerun 10k baseline and deep comparison | Compare against `GLT_20260706_BASELINE_COMPARE_10K_R1` and `GLT_20260706_DEEP_COMPARE_10K_R1`. |

### Recommended Order

Start with TPS-15 before TPS-16 implementation. TPS-15 improves measurement trust and prevents the benchmark verifier from being mistaken for a product bottleneck. Then use the cleaner deep ranking to choose the first TPS-16 code change.

### TPS-16 Implementation Pass 1

Change:

- Kept `order_execution_links` as the default idempotency gate.
- Kept buyer/seller `OrderMatchedV1` event rows and stream-head locking.
- Combined the default link-gated Order event insert and `order_stream_heads` update into one CTE after Java computes deterministic buyer/seller versions and hashes.
- Did not change the rollback/experiment path that replaces link idempotency with event-store idempotency.

Validation:

| Check | Result |
|---|---|
| `./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `OrderEventAppenderPostgresIT` | PASS |
| Smoke `GLT_20260706_TPS16_SMOKE` | PASS, `completedTrades=10`, final queue ready/unacked `0` |
| 10k baseline `GLT_20260706_TPS16_BASELINE_10K_R1` | PASS, `businessMatchedE2eTps=313.12`, `completionMarkerReachTps=369.38`, final queue ready/unacked `0` |
| 10k deep `GLT_20260706_TPS16_DEEP_10K_R1` | PASS, `businessMatchedE2eTps=280.81`, `completionMarkerReachTps=376.41`, final queue ready/unacked `0` |

Comparison against TPS-15:

| Run | Business TPS | Completion marker TPS | Notes |
|---|---:|---:|---|
| TPS-15 baseline `GLT_20260706_TPS15_BASELINE_10K_R1` | `314.66` | `370.23` | Pre TPS-16. |
| TPS-16 baseline `GLT_20260706_TPS16_BASELINE_10K_R1` | `313.12` | `369.38` | No material business TPS regression or gain. |
| TPS-15 deep `GLT_20260706_TPS15_DEEP_10K_R1` | `269.34` | `328.97` | Deep diagnostics overhead included. |
| TPS-16 deep `GLT_20260706_TPS16_DEEP_10K_R1` | `280.81` | `376.41` | Slightly better diagnostic-mode result, but not enough to call a major product bottleneck fix. |

Order SQL comparison:

| Statement group | TPS-15 deep | TPS-16 deep | Interpretation |
|---|---:|---:|---|
| Event insert | `2080.29ms` | merged into CTE | No longer a standalone statement. |
| Stream-head update | `595.62ms` | merged into CTE | Standalone round trip removed. |
| Combined event insert + head update CTE | N/A | `2528.90ms` | About `147ms` lower than old insert+update total, but still the largest Order DB statement. |
| Link insert | `1124.57ms` | `1192.23ms` | Still a major hot-path write. |
| Outbox insert | `1045.64ms` | `867.40ms` | Lower in this run, but not directly changed by TPS-16. |
| Head lock | `578.36ms` | `564.60ms` | Still required for command-side concurrency. |
| Projection update | `581.70ms` | `587.68ms` | Still competes for DB resources; diagnostic only for business gate. |

Conclusion:

- Keep TPS-16 pass 1 because it removes one DB round trip without weakening the default correctness path.
- Do not expect this change alone to move global TPS. Baseline remained effectively flat (`314.66 -> 313.12`).
- The remaining Order cost is row-write amplification and DB contention, not just JDBC round-trip count.
- Next fixes should target the larger remaining costs: `order_execution_links`, Order outbox write/publish marking, and projector competition. Any link-table change needs a new A/B because the previous event-store-idempotency replacement regressed.

## 2026-07-06 TPS-17: Validate Order Trade Resource Isolation Before Service Split

### Trigger

TPS-16 reduced one Order command round trip but did not materially improve baseline business TPS. The next question is whether Order is slow because unrelated work shares the same service resources, or because the trade apply write model itself is too heavy.

Proposed service split under discussion:

- `submit-order-service`: accepts user orders and owns initial order creation.
- `order-trade-service`: consumes `TradeExecuted` and applies matched quantity/status changes.

Architectural concern:

- A trade changes the original order's command-side state: remaining quantity, matched quantity, status, version, and event hash chain.
- Splitting this across two independent Order databases would require proving that both databases agree on every order version and status.
- That creates a new distributed consistency problem around the exact invariant the hot path currently protects with row locks and stream-head versions.
- Therefore a service/DB split is rejected as the first validation step.

### Decision

Validate resource isolation inside the existing Order service and database before introducing another service or DB.

The validation goal is narrow:

- Keep one Order source of truth.
- Keep the same `order_event_store`, `order_stream_heads`, `order_execution_links`, and outbox semantics.
- Isolate command trade apply resources from submit/projection/outbox work where possible.
- Measure whether this improves `orderCommandMatchReachTps`, `completionMarkerReachTps`, or business-gated TPS.

### Non-Goals

- Do not split Order into two databases in TPS-17.
- Do not duplicate order command state across services.
- Do not introduce cross-DB reconciliation as part of the 2000 TPS path.
- Do not move `TradeExecuted` apply to a service that cannot atomically update the same order command state.

### Validation Plan

Run an A/B comparison:

| Variant | Description | Purpose |
|---|---|---|
| A: Current TPS-16 baseline | Existing Order resources and pools | Control. |
| B: Trade-isolated Order profile | Trade apply consumer has priority; projector/outbox are isolated or throttled; submit-order endpoints remain available but do not share critical trade pool pressure | Tests whether resource contention, not write model, is the main bottleneck. |

Metrics to compare:

| Metric | Expected signal |
|---|---|
| `businessMatchedE2eTps` | End-to-end accepted throughput. |
| `orderCommandMatchReachTps` | Direct Order trade apply throughput. |
| `completionMarkerReachTps` | Whether downstream completion benefits. |
| Order DB pool active/pending metrics | Confirms whether isolation reduces pool contention. |
| `orders_current` projection lag | May increase if projector is throttled; acceptable if bounded and reported. |
| Order `pg_stat_statements` top total time | Distinguishes reduced contention from unchanged row-write cost. |

Initial resource inventory:

| Workload | Current resource | Notes |
|---|---|---|
| Submit order HTTP/JPA command path | `OrderCommandPool` | `spring.datasource.hikari.maximum-pool-size=35` in loadtest. |
| `TradeExecuted` apply listener | `OrderConsumerPool` | `eap.order.listeners.trade-executed.concurrency=12`; this is the main trade apply path. |
| Order outbox relay | `OrderConsumerPool` | Publishes `OrderSubmittedEvent` and `OrderTradeAppliedEvent`, then marks outbox rows `SENT`; competes with trade apply for the same pool. |
| `orders_current` projector | `OrderProjectionPool` | Loadtest pool size `3`, poll interval `5000ms`; already isolated from command/consumer pool. |
| Projection repair | `OrderProjectionPool` | Disabled in loadtest. |

First validation hypothesis:

- Submit-order vs trade-apply DB pool contention is probably not the main issue because they already use separate pools.
- Projection contention is partly isolated already because it uses `OrderProjectionPool`.
- The remaining resource-isolation candidate is `OrderConsumerPool` contention between `TradeExecuted` apply and `OrderEventOutboxRelay`.
- TPS-17 should first measure and, if needed, split outbox relay onto its own datasource/pool or throttle it during the business gate.

### Acceptance Criteria

- Duplicate `TradeExecuted` redelivery remains safe.
- Final queue ready/unacked counts return to `0`.
- `completedTrades=10000`, `orderCommandMatchedRows=20000`, and `walletTradeSettlements=10000`.
- Projection remains diagnostic only and catches up after the run or reports bounded lag.
- If resource isolation improves Order TPS materially, keep single DB and continue resource isolation.
- If resource isolation does not improve materially, the bottleneck is the write model itself; do not split services until a new command-state model is designed.

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-17-01 | P0 | Inventory Order hot-path resource sharing | Document which consumers/workers use command DB pool, projection DB pool, outbox poller pool, RabbitMQ listener containers, and thread pools under `loadtest`. |
| TPS-17-02 | P0 | Add/confirm DB pool metrics in diagnostics | Deep diagnostics capture Order Hikari active/idle/pending for command, consumer, projection, and outbox pools if exposed. |
| TPS-17-03 | P1 | Create trade-isolated loadtest profile | Trade apply consumers keep priority; projection and outbox are isolated or throttled without changing business semantics. |
| TPS-17-04 | P0 | Run TPS-16 baseline vs TPS-17 isolated A/B | Compare 10k baseline and deep runs using the same business gate. |
| TPS-17-05 | P0 | Architecture decision after evidence | Decide: keep single service with resource isolation, split deployable service with same DB/schema, or reject split and redesign write model. |

### Service Split Rule

Only consider a separate `order-trade-service` if it can keep one authoritative Order command state or if a new model explicitly accepts eventual command-state synchronization.

Current default stance:

- Splitting deployment may be acceptable later.
- Splitting the Order command database is not justified for this hot path yet.

### TPS-17 Validation Result: Outbox Pool Split Rejected

Change tested:

- Added a separate `OrderOutboxPool`.
- Moved `OrderEventOutboxRelay` from `OrderConsumerPool` to `OrderOutboxPool`.
- Kept one Order database and all business semantics unchanged.
- Reverted the code change after validation because the benchmark did not improve.

Validation:

| Check | Result |
|---|---|
| `./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| Smoke `GLT_20260706_TPS17_OUTBOX_POOL_SMOKE_R2` | PASS, `completedTrades=10`, final queue ready/unacked `0` |
| 10k baseline R1 `GLT_20260706_TPS17_OUTBOX_POOL_BASELINE_10K_R1` | PASS but driver-limited: `actualBuyPublishTps=746.18`; not used as throughput evidence |
| 10k baseline R2 `GLT_20260706_TPS17_OUTBOX_POOL_BASELINE_10K_R2` | PASS with valid publish rate: `actualBuyPublishTps=1999.21`, `businessMatchedE2eTps=251.24`, `orderCommandMatchReachTps=307.94` |
| 10k deep `GLT_20260706_TPS17_OUTBOX_POOL_DEEP_10K_R1` | PASS with valid publish rate: `actualBuyPublishTps=1999.00`, `businessMatchedE2eTps=280.69`, `orderCommandMatchReachTps=331.32` |

Comparison:

| Run | Business TPS | Order command TPS | Completion marker TPS | Interpretation |
|---|---:|---:|---:|---|
| TPS-16 baseline `GLT_20260706_TPS16_BASELINE_10K_R1` | `313.12` | `386.32` | `369.38` | Current accepted baseline. |
| TPS-17 outbox-pool baseline R2 | `251.24` | `307.94` | `298.22` | Regression. |
| TPS-16 deep `GLT_20260706_TPS16_DEEP_10K_R1` | `280.81` | `376.41` | `376.41` | Diagnostics overhead included. |
| TPS-17 outbox-pool deep R1 | `280.69` | `331.32` | `331.32` | Business TPS flat vs TPS-16 deep, but Order stage regressed. |

Order SQL deep comparison:

| Statement group | TPS-16 deep | TPS-17 outbox-pool deep | Signal |
|---|---:|---:|---|
| Combined event insert + head update CTE | `2528.90ms` | `2967.04ms` | Worse. |
| Link insert | `1192.23ms` | `1540.66ms` | Worse. |
| Outbox insert | `867.40ms` | `971.76ms` | Worse. |
| Head lock | `564.60ms` | `628.13ms` | Worse. |
| Outbox poll select | `428.81ms` | `454.53ms` | No meaningful improvement. |

Hikari signal from TPS-17 deep:

- `OrderConsumerPool` pending connections: `0`.
- `OrderOutboxPool` pending connections: `0`.
- `OrderProjectionPool` pending connections: `0`.
- `OrderConsumerPool` acquire sum: `0.58s / 10002` acquisitions.
- `OrderOutboxPool` acquire sum: `0.02s / 357` acquisitions.

Conclusion:

- The current Order bottleneck is not Hikari pool starvation between trade apply and outbox relay.
- Splitting the outbox relay to a separate datasource adds no useful relief and coincided with slower Order write statements.
- Keep the original shared `OrderConsumerPool` for outbox relay.
- Continue TPS work on reducing per-trade write volume or changing order-flow semantics, not on pool splitting.

Order-flow shrink candidates after TPS-17:

| Candidate | Recommendation | Reason |
|---|---|---|
| Split submit order and trade apply into two DBs | Reject for now | Trade apply mutates the original order command state; two DBs create a hard order-state reconciliation problem. |
| Split deployable services but keep one Order command DB | Defer | Could isolate deployment/runtime, but will not reduce DB writes by itself. |
| Remove `order_execution_links` | Do not default | Prior event-store idempotency A/B regressed; only revisit with a better uniqueness strategy. |
| Keep per-order `OrderMatchedV1` events | Keep | This is the audit/event-sourcing truth for buyer and seller order streams. |
| Combine event insert + head update | Keep | TPS-16 removed one round trip without correctness loss, although gain was small. |
| Reduce shared outbox writes | Investigate next | One outbox insert plus publish update per trade remains visible cost; optimize without losing reliable publish. |
| Make `orders_current` purely lagging projection | Already done | It is diagnostic only, but projection DB work still competes at the database level. |
| Add a trade-level execution fact inside Order | Consider as design review | Could avoid some duplicated hot-path markers, but must preserve per-order audit and duplicate safety. |

## 2026-07-06 TPS-18: Order Hot-Path Index Write-Amplification Reduction

### Decision

Open TPS-18 as a low-risk schema optimization ticket before any service split or business-flow redesign.

The target is not to remove Order consistency structures. The target is to remove indexes that do not serve current Order hot-path queries but still charge every write to `order_event_store`, `order_execution_links`, and related Order tables.

### Scope

In scope:

- Drop redundant or unused Order indexes after code and diagnostic confirmation.
- Keep the Order service, Order command database, event-store contract, and `order_execution_links` idempotency model unchanged.
- Compare the same 10k business-gated benchmark before and after the migration.

Out of scope:

- Splitting submit-order and trade-apply into separate databases.
- Removing `order_execution_links`.
- Moving idempotency into `order_event_store`.
- Removing event-store canonical payloads or JSONB payloads.
- Removing the outbox FK or changing reliable-publish semantics.

### Current Code Evidence

| Object | Evidence | Decision |
|---|---|---|
| `idx_order_event_stream(aggregate_id, aggregate_version)` | Duplicates the access pattern already covered by unique constraint `uk_order_aggregate_version(aggregate_id, aggregate_version)`. `OrderEventStreamReader` loads by `aggregate_id ORDER BY aggregate_version`. | Drop first. |
| `idx_order_execution_order(order_id)` | Current application hot path writes links and checks duplicates through `uk_order_execution_trade_order(trade_id, order_id)`. No production code query needs `WHERE order_id = ?` on links. | Drop first. |
| `idx_order_event_occurred_at(occurred_at)` | No current Order code path reads event store by occurred time. | Candidate drop if no audit/time-range query is required. |
| `idx_order_event_type_position(event_type, global_position)` | Used by diagnostics/verifier-style event type counts, not by the projector hot path. | Do not drop in first pass unless diagnostics are changed. |
| `idx_orders_current_user_status`, `idx_orders_current_market_sequence` | Unused in matched-trade load test, but likely product read indexes. | Keep until API/read workload proves they are unused. |

### Performance Hypothesis

The TPS-16 combined CTE reduced one event-store/head round trip but did not materially raise business TPS. That implies the remaining Order cost is dominated more by row/index maintenance, WAL, and update churn than by JDBC round trips alone.

Removing redundant indexes should reduce:

- `order_event_store` insert index maintenance.
- `order_execution_links` insert index maintenance.
- WAL volume and checkpoint pressure.
- Secondary index page writes during the trade-apply burst.

Expected gain is moderate, not transformational. This ticket should be judged by lower Order SQL time and lower write amplification first, then by business TPS.

### Acceptance Criteria

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-18-01 | P0 | Add Liquibase migration for safe index drops | Migration drops `idx_order_event_stream` and `idx_order_execution_order`; migration is idempotent or guarded for local reruns. |
| TPS-18-02 | P0 | Decide `idx_order_event_occurred_at` | Either drop it with a documented audit tradeoff, or explicitly keep it because time-range event queries are required. |
| TPS-18-03 | P0 | Verify Order tests | `eap-order` test compilation and relevant event-store integration tests pass. |
| TPS-18-04 | P0 | Run 10k business-gated baseline vs TPS-18 | Compare against TPS-16 accepted baseline using the same business gate and publish target. |
| TPS-18-05 | P0 | Capture deep diagnostics | Compare Order SQL time, `pg_stat_user_indexes`, `pg_stat_user_tables`, business TPS, Order command TPS, and completion marker TPS. |
| TPS-18-06 | P1 | Document keep/drop rules | Record which Order indexes are hot-path required, product-read required, diagnostics-only, or removable. |

### Success Criteria

TPS-18 is accepted if all of the following are true:

- Duplicate `TradeExecuted` redelivery safety remains unchanged.
- Buyer/seller `OrderMatchedV1`, `order_stream_heads`, `order_execution_links`, and shared `OrderTradeApplied` outbox rows remain consistent.
- `businessMatchedE2eTps` does not regress against TPS-16 baseline.
- Deep diagnostics show lower write cost for at least one of:
  - combined event insert + head update CTE;
  - `order_execution_links` insert;
  - total Order DB write time;
  - Order table/index write amplification.

### Rollback Rule

If TPS-18 does not improve Order write cost or causes read/API regressions, revert only the index-drop migration. Do not use a failed TPS-18 result as evidence for splitting the Order command database.

### TPS-18 Implementation Pass 1

Change made:

- Added Liquibase changeset `order-es-008`.
- Dropped `order_service.idx_order_event_stream`.
- Dropped `order_service.idx_order_execution_order`.
- Kept `idx_order_event_occurred_at` for now because audit/time-range event-store query requirements have not been explicitly rejected.

Expected effect:

- `order_event_store` keeps uniqueness and stream-read support through `uk_order_aggregate_version(aggregate_id, aggregate_version)`.
- `order_execution_links` keeps duplicate safety through `uk_order_execution_trade_order(trade_id, order_id)`.
- No business semantics, event IDs, stream-head versioning, outbox publish semantics, or projection behavior changed.

Next validation:

- Run Order migration/tests.
- Run 10k business-gated baseline vs TPS-18 and compare Order SQL time plus index/table write stats.

### TPS-18 Validation Result: Index Drop Did Not Improve Throughput

Validation runs:

| Check | Result |
|---|---|
| 10k baseline `GLT_20260706_TPS18_BASELINE_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1998.82`, but `businessMatchedE2eTps=270.18`, `orderCommandMatchReachTps=348.01`, `completionMarkerReachTps=334.98`. |
| 10k deep `GLT_20260706_TPS18_DEEP_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1998.94`, but `businessMatchedE2eTps=257.94`, `orderCommandMatchReachTps=307.11`, `completionMarkerReachTps=297.67`. |

Index validation:

- `order-es-008` ran successfully during the first TPS-18 baseline startup.
- Deep diagnostics no longer list `idx_order_event_stream`.
- Deep diagnostics no longer list `idx_order_execution_order`.
- `uk_order_aggregate_version` and `uk_order_execution_trade_order` remained in place.

Comparison against TPS-16 deep:

| Statement group | TPS-16 deep | TPS-18 deep | Signal |
|---|---:|---:|---|
| Combined event insert + head update CTE | `2528.90ms` | `3059.17ms` | Worse. |
| Link insert | `1192.23ms` | `1176.92ms` | Tiny improvement, not material. |
| Outbox insert | `867.40ms` | `1025.96ms` | Worse. |
| Projection update | `587.68ms` | `731.52ms` | Worse. |
| Head lock | `564.60ms` | `708.40ms` | Worse. |
| Outbox poll select | `428.81ms` | `58.04ms` | Better, but not the business bottleneck. |

Conclusion:

- Dropping the two unused/redundant indexes is logically clean but did not improve the 10k business-gated run.
- The measurable benefit was limited to a near-noise reduction in `order_execution_links` insert time.
- The main Order cost remains the core trade apply transaction: event-store insert/head update, stream-head locking, outbox insert, and projection competition.
- TPS-18 should not be counted as a successful performance optimization.

Rollback guidance:

- If the goal is strictly TPS improvement, add a rollback changeset that recreates `idx_order_event_stream` and `idx_order_execution_order`.
- If the goal is schema cleanliness, keeping the drop is acceptable only if product/read tests confirm no `order_id` link lookup or named-index dependency exists.
- Do not spend more time on small unused-index drops as the next TPS lever.

## 2026-07-06 TPS-19: Order Payload and Outbox SQL Slimming

### Decision

Open TPS-19 as the next Order SQL tuning ticket.

TPS-18 proved that dropping small unused indexes is not the main lever. The next target is row width and JSONB conversion cost in the Order write path, especially where the runtime only needs canonical text payloads.

### Problem Statement

The top Order write costs after TPS-18 remain:

| Statement group | TPS-18 deep total time | Notes |
|---|---:|---|
| Combined event insert + head update CTE | `3059.17ms / 10000 calls` | Mean `0.3059ms`; cost is cumulative because every trade writes buyer/seller event rows and updates heads. |
| Link insert | `1176.92ms / 10000 calls` | Already set-based; index drop gave only tiny improvement. |
| Outbox insert | `1025.96ms / 10000 calls` | Writes payload as JSONB. |
| Projection update | `731.52ms / 20000 calls` | Async but competes for Order DB resources. |
| Head lock | `708.40ms / 10000 calls` | Required for command-side remaining amount/version safety. |

Important interpretation:

- The `3059.17ms` event/head statement time is cumulative over `10000` calls, not a single 3-second insert.
- The issue is write amplification and row width per trade, not one pathological slow query.

### Scope

In scope:

- Evaluate converting `order_event_outbox.payload` from JSONB to TEXT if no query needs JSONB operators.
- Remove avoidable `CAST(:payload AS jsonb)` / `payload::text` churn from the outbox relay path.
- Evaluate whether `order_event_store.payload JSONB` is necessary on the hot path when replay/projector currently read `payload_canonical`.
- Measure row width, SQL time, and correctness after each change.

Out of scope for TPS-19:

- Removing `order_execution_links`.
- Removing buyer/seller `OrderMatchedV1` events.
- Splitting Order service or Order DB.
- Removing FK constraints before a separate consistency review.
- Reworking the full event-store schema without an accepted compatibility plan.

### Current Code Evidence

| Area | Evidence | TPS-19 direction |
|---|---|---|
| Event replay | `OrderEventStreamReader` selects `payload_canonical`, not `payload`. | `payload_canonical` is required; JSONB payload may be audit/query-only. |
| Projection | `OrdersCurrentProjector` selects `payload_canonical`, not `payload`. | Projection does not need JSONB payload. |
| Event append | `OrderEventAppender` writes both `payload JSONB` and `payload_canonical TEXT`. | Evaluate duplicate storage cost. |
| Outbox insert | `OrderEventAppender` writes outbox payload through `CAST(:payload AS jsonb)`. | Candidate for TEXT payload. |
| Outbox relay | `OrderEventOutboxRelay` reads `payload::text` before deserializing. | TEXT payload avoids read-time cast. |

### Recommended Task Split

| ID | Priority | Task | Acceptance Criteria |
|---|---:|---|---|
| TPS-19-01 | P0 | Inventory JSONB usage in Order event store and outbox | Search confirms whether any production code, tests, diagnostics, or API uses JSONB operators or fields from `order_event_store.payload` / `order_event_outbox.payload`. |
| TPS-19-02 | P0 | Convert Order outbox payload to TEXT if safe | Liquibase migration changes `order_event_outbox.payload` to TEXT or adds a TEXT replacement path; relay no longer uses `payload::text`; reliable publish semantics unchanged. |
| TPS-19-03 | P0 | Verify outbox compatibility | Existing pending/SENT outbox rows remain readable or migration handles conversion; `OrderEventOutboxRelay` tests pass. |
| TPS-19-04 | P1 | Evaluate event-store JSONB slimming | Decide whether to keep both `payload` and `payload_canonical`, remove JSONB, or move JSONB to an audit/cold path. |
| TPS-19-05 | P0 | Run 10k baseline/deep comparison | Compare TPS-18 vs TPS-19: outbox insert time, event/head CTE time, business TPS, completion TPS, final ready/unacked drain. |
| TPS-19-06 | P1 | Document FK decision separately | Record FK costs observed in deep diagnostics but defer FK removal to a consistency review. |

### Success Criteria

TPS-19 is accepted only if:

- `OrderTradeApplied` outbox publish correctness is unchanged.
- Duplicate `TradeExecuted` handling remains unchanged.
- 10k business-gated run completes with final queue ready/unacked `0`.
- Outbox insert total time decreases materially from TPS-18 deep `1025.96ms`.
- Business TPS or Order command TPS does not regress.

### Starting Recommendation For Tomorrow

Start with `order_event_outbox.payload JSONB -> TEXT`.

Reason:

- It is narrower than changing event-store semantics.
- The outbox relay already wants text for deserialization.
- Reliable publish does not require querying inside JSONB payload.
- If this does not help, the next meaningful question is event-store row width, not more small-index cleanup.

### TPS-19 Implementation Pass 1

Change made:

- Added Liquibase changeset `order-es-009`.
- Converted `order_service.order_event_outbox.payload` to `TEXT`.
- Removed `CAST(:payload AS jsonb)` from Order outbox inserts.
- Changed duplicate shared-outbox assertion from JSONB equality to text equality.
- Removed `payload::text` from `OrderEventOutboxRelay` select.

Scope intentionally not changed:

- `order_event_store.payload` remains JSONB.
- `order_event_store.payload_canonical` remains the replay/projection source.
- Order outbox FK, publish status model, retry model, and message type handling are unchanged.
- `order_execution_links` idempotency is unchanged.

Verification:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT` | PASS |

Next validation:

- Run TPS-19 10k baseline and deep.
- Compare against TPS-18 deep outbox insert time `1025.96ms / 10000 calls`.
- Confirm `OrderEventOutboxRelay` SQL no longer appears as `payload::text`.

### TPS-19 Validation Result: Outbox Payload TEXT Accepted

Validation runs:

| Check | Result |
|---|---|
| 10k baseline `GLT_20260707_TPS19_BASELINE_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1998.89`, `businessMatchedE2eTps=344.46`, `orderCommandMatchReachTps=393.22`, `completionMarkerReachTps=377.03`, final queue ready/unacked `0`. |
| 10k deep `GLT_20260707_TPS19_DEEP_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1999.16`, `businessMatchedE2eTps=302.42`, `orderCommandMatchReachTps=352.38`, `completionMarkerReachTps=352.38`, final queue ready/unacked `0`. |

Comparison against TPS-18:

| Metric | TPS-18 baseline | TPS-19 baseline | Signal |
|---|---:|---:|---|
| `businessMatchedE2eTps` | `270.18` | `344.46` | Better. |
| `orderCommandMatchReachTps` | `348.01` | `393.22` | Better. |
| `completionMarkerReachTps` | `334.98` | `377.03` | Better. |
| `businessCompletionSeconds` | `37.01s` | `29.03s` | Better. |

Deep SQL comparison:

| Statement group | TPS-18 deep | TPS-19 deep | Signal |
|---|---:|---:|---|
| Combined event insert + head update CTE | `3059.17ms` | `2315.99ms` | Better, likely helped by lower DB pressure and run variance. |
| Link insert | `1176.92ms` | `1047.28ms` | Better. |
| Outbox insert | `1025.96ms` | `817.18ms` | Direct target improved by about `20%`. |
| Projection update | `731.52ms` | `574.89ms` | Better. |
| Head lock | `708.40ms` | `535.18ms` | Better. |
| Outbox poll select | `58.04ms` | `256.47ms` | Worse than TPS-18 deep, but SQL now reads `payload` directly with no `payload::text`. |

SQL shape validation:

- Order outbox insert now appears as:
  - `INSERT INTO order_service.order_event_outbox (...) VALUES ($1, $2, $3, $4, $5, $6, ...)`
- Order outbox relay now appears as:
  - `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count ...`
- The old `payload::text` cast is gone from diagnostics.

Conclusion:

- TPS-19 pass 1 is accepted.
- Converting Order outbox payload from JSONB to TEXT reduced the targeted outbox insert cost and improved the valid 10k business-gated baseline.
- This supports the broader hypothesis that payload/row-width and conversion overhead are better optimization targets than small unused-index cleanup.

Next candidate:

- Evaluate event-store payload slimming separately.
- Do not immediately remove `order_event_store.payload JSONB`; first quantify code/API/audit usage and migration compatibility.

### TPS-19 Event-Store Payload Inventory

Question:

- Does `order_event_store.payload JSONB` currently provide runtime query value, or is it duplicate storage beside `payload_canonical`?

Code inventory result:

| Area | Current behavior | Uses `payload JSONB`? |
|---|---|---|
| Event append | `OrderEventAppender` writes both `payload JSONB` and `payload_canonical TEXT`. | Writes JSONB, but does not query it later. |
| Event replay | `OrderEventStreamReader` selects `aggregate_version`, `event_type`, and `payload_canonical`. | No. |
| Projection catch-up | `OrdersCurrentProjector` scans by `global_position` and reads `payload_canonical`. | No. |
| Projection repair | `OrdersCurrentProjector` rebuilds a stream by `aggregate_id` / `aggregate_version` and reads `payload_canonical`. | No. |
| Duplicate event identity check | `OrderEventAppender.findByEventId` reads `payload_canonical` and `metadata_canonical`. | No. |
| Load-test correctness | Load generator counts by `event_type` and command-side state; it does not inspect JSON payload. | No. |
| Legacy replay UI/service | `OrderReplayService` reads `audit_events.payload`, not `order_event_store.payload`. | Not applicable. |

No current production code path was found using JSONB operators against `order_event_store.payload`, such as:

- `payload->>'field'`
- `payload->'field'`
- `payload @> ...`
- JSON path functions
- GIN/GiST JSONB payload indexes

Interpretation:

- `payload_canonical` is the operational event payload for replay, projection, duplicate validation, and hash identity.
- `payload JSONB` is currently an audit/debug convenience copy, not an active query model.
- Keeping both columns means each event append pays:
  - Java serialization to canonical text;
  - PostgreSQL JSONB parse/validation/conversion;
  - storage/WAL for both JSONB and canonical text.

Risk boundary:

- Unlike outbox payload, event-store payload is part of the canonical historical fact table.
- Removing or changing `payload JSONB` is still a schema compatibility decision, not just a relay optimization.
- Any change must preserve:
  - replay from `payload_canonical`;
  - projection rebuild;
  - duplicate event identity validation;
  - hash-chain reproducibility;
  - optional audit/debug access if needed.

Recommended next ticket:

- Open a separate `TPS-20` for Order event-store payload slimming.
- First candidate should be a conservative migration that keeps `payload_canonical` as the only operational payload and either:
  - converts `payload JSONB` to `TEXT` for audit readability; or
  - drops `payload JSONB` only after confirming no API/admin/debug requirement depends on it.
- Do not combine this with FK removal or idempotency model changes.

### TPS-20 Implementation Pass 1: Order Event-Store Payload TEXT

Scope:

- Convert `order_service.order_event_store.payload` from `JSONB` to `TEXT`.
- Convert `order_service.order_event_store.metadata` from `JSONB` to `TEXT`.
- Remove `CAST(:payload AS jsonb)` / `CAST(:metadata AS jsonb)` from Order event-store insert hot paths.

Preserved behavior:

- `payload_canonical` remains the operational replay/projection payload.
- `metadata_canonical` remains the operational metadata identity value.
- Event IDs, aggregate version uniqueness, stream-head update, duplicate event validation, outbox FK, and hash-chain inputs are unchanged.
- `audit_events.payload` remains JSONB; this ticket only changes `order_event_store`.

Implementation notes:

- Liquibase `order-es-010` drops the JSONB default before type conversion, converts existing values with `payload::text` / `metadata::text`, then restores the metadata default as text `'{}'`.
- This is intentionally conservative: the event-store still keeps a readable payload copy, but no longer pays JSONB parse/conversion cost on the append path.

Validation target:

- Re-run 10k baseline/deep after code verification.
- Compare against TPS-19 deep event/head CTE time: `2315.99ms / 10000 calls`.
- Primary expected signal is lower Order event insert/head CTE time, not a functional behavior change.

Code verification:

| Check | Result |
|---|---|
| `rg -n "CAST\\(:.* AS jsonb\\)" eap-order/src/main eap-order/src/test` | PASS: no remaining `order_event_store` JSONB casts; only `AuditEventRepository` still writes `audit_events.payload JSONB`. |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT` in `eap-order` | PASS |

### TPS-20 Validation Result: Event-Store Payload TEXT Not Accepted As A Performance Win

Validation runs:

| Check | Result |
|---|---|
| 10k baseline `GLT_20260707_TPS20_BASELINE_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1998.98`, `businessMatchedE2eTps=337.22`, `orderCommandMatchReachTps=431.77`, `completionMarkerReachTps=413.46`, final queue ready/unacked `0`. |
| 10k deep `GLT_20260707_TPS20_DEEP_10K_R1` | PASS, valid publish rate `actualBuyPublishTps=1999.02`, but `businessMatchedE2eTps=265.58`, `orderCommandMatchReachTps=306.44`, `completionMarkerReachTps=306.44`, final queue ready/unacked `0`. |

Schema validation:

| Column | Type after `order-es-010` |
|---|---|
| `order_event_store.payload` | `text` |
| `order_event_store.payload_canonical` | `text` |
| `order_event_store.metadata` | `text`, default `'{}'::text` |
| `order_event_store.metadata_canonical` | `text` |

Comparison against TPS-19:

| Metric | TPS-19 baseline | TPS-20 baseline | Signal |
|---|---:|---:|---|
| `businessMatchedE2eTps` | `344.46` | `337.22` | Slightly worse. |
| `orderCommandMatchReachTps` | `393.22` | `431.77` | Better, but not enough to improve business-gated TPS. |
| `completionMarkerReachTps` | `377.03` | `413.46` | Better. |
| `businessCompletionSeconds` | `29.03s` | `29.65s` | Slightly worse. |

Deep SQL comparison:

| Statement group | TPS-19 deep | TPS-20 deep | Signal |
|---|---:|---:|---|
| Combined event insert + head update CTE | `2315.99ms` | `2788.61ms` | Worse; target did not improve. |
| Link insert | `1047.28ms` | `1083.90ms` | Slightly worse. |
| Outbox insert | `817.18ms` | `1027.59ms` | Worse. |
| Projection update | `574.89ms` | `613.17ms` | Worse. |
| Head lock | `535.18ms` | `619.67ms` | Worse. |
| Outbox poll select | `256.47ms` | `368.41ms` | Worse. |

Interpretation:

- The schema/code change is functionally safe, but the 10k evidence does not prove it is a useful performance optimization.
- Removing JSONB conversion from `order_event_store.payload` did not reduce the measured event/head CTE cost in the deep run.
- TPS-20 deep also showed stronger MatchEngine backlog (`maxMatchEngineQueueReady=2028`, `maxMatchEngineQueueUnacked=700`) than TPS-19 deep (`0` ready, `95` unacked), so this run was globally more stressed.
- Still, the acceptance target was specific: lower Order event/head SQL time. That target failed.

Decision:

- Do not count TPS-20 as accepted performance work.
- Keeping the TEXT conversion is only justified as schema simplification / avoiding unnecessary JSONB semantics, not as a measured TPS improvement.
- The next performance ticket should not continue slimming payload columns. The current evidence points back to per-trade write amplification and completion-marker/write-model costs.

## 2026-07-07 TPS-21: Write Amplification Triage

### Question

Which write-amplification item should be attacked first after payload slimming failed?

Current measured per-10000-trade write model:

| Service | Hot write | Current role | Initial decision |
|---|---|---|---|
| Order | `order_event_store`: about `20000` inserts | Per-order event-sourced truth for buyer/seller `OrderMatchedV1`. | Keep. Domain-important. |
| Order | `order_stream_heads`: about `20000` updates | Command-side version, remaining amount, and status source of truth. | Keep. Required for safe matching. |
| Order | `order_execution_links`: about `20000` inserts in links mode | Duplicate `TradeExecuted` idempotency evidence. | Tested removal via event-store idempotency; not accepted. |
| Order | `order_event_outbox`: about `10000` inserts + `10000` SENT updates | Reliable `OrderTradeApplied` marker publish. | Keep for reliability; optimize relay/write shape separately. |
| Order | `orders_current`: about `20000` updates | Rebuildable read model/projection. | Candidate for throttling/isolating, not business gate. |
| MatchEngine | `trade_completion_view`: `10000` upserts in loadtest; more in reconciliation mode | Completion projection/repair view. | Candidate to move fully out of hot path. |
| MatchEngine | `trade_completion_markers`: `20000` inserts | Append-only Order/Wallet completion evidence. | Keep. Business completion gate depends on it. |
| MatchEngine | `trade_outbox`: `10000` inserts + `10000` SENT updates | Reliable `TradeExecuted` publish. | Keep for reliability; optimize relay/write shape separately. |
| Wallet | `wallets`: `20000` updates | Buyer/seller balance mutation. | Keep. Domain-critical. |
| Wallet | `trade_settlements`: `10000` inserts | Settlement idempotency/fact row. | Keep for audit/idempotency unless a separate Wallet design is accepted. |
| Wallet | `outbox`: `10000` inserts + `10000` SENT updates | Reliable `WalletTradeSettled` marker publish. | Keep for reliability; optimize relay/write shape separately. |

### Experiment: Order Event-Store Idempotency In Loadtest

Hypothesis:

- Since `OrderMatchedV1` event IDs are deterministic from `(orderId, tradeId)`, event-store uniqueness can replace `order_execution_links` as the duplicate gate.
- Removing `order_execution_links` should reduce two inserts per trade.

Temporary change tested:

- Set loadtest profile `eap.order.event-sourcing.trade-idempotency-source=event-store`.
- Production default remained `links`.
- The change was reverted after the experiment because the result regressed.

Verification:

| Check | Result |
|---|---|
| `OrderEventAppenderPostgresIT` | PASS. Existing event-store idempotency tests cover no-link append, duplicate skip, and missing-outbox duplicate failure. |
| 10k baseline `GLT_20260707_TPS21_EVENTSTORE_IDEMPOTENCY_BASELINE_10K_R1` | PASS for correctness, but performance regressed. |
| Post-run DB shape | `order_execution_links=0`, `order_event_outbox=10000`, `order_event_store=60000`, `orders_current=20000`, `order_stream_heads=20000`. |

Comparison:

| Metric | TPS-20 baseline | TPS-21 event-store idempotency baseline | Signal |
|---|---:|---:|---|
| `businessMatchedE2eTps` | `337.22` | `296.04` | Worse. |
| `orderCommandMatchReachTps` | `431.77` | `332.03` | Worse. |
| `completionMarkerReachTps` | `413.46` | `332.03` | Worse. |
| `businessCompletionSeconds` | `29.65s` | `33.78s` | Worse. |
| `maxMatchEngineQueueUnacked` | `267` | `650` | Worse. |
| `maxWalletTradeExecutedQueueUnacked` | `26` | `84` | Worse. |

Interpretation:

- `order_execution_links` is real write amplification, but removing it through the current event-store idempotency path did not improve throughput.
- This likely means the dominant Order cost is not the link insert itself; it is the combined event insert + stream-head mutation + outbox + projection pressure and global queue/DB contention.
- Do not promote event-store idempotency as the loadtest default based on this result.

### Next Candidate

Open the next implementation ticket against MatchEngine completion projection:

- Keep `trade_completion_markers` as append-only business completion evidence.
- Keep load-test `completedTrades` based on `trade_executions + ORDER_APPLIED + WALLET_SETTLED` markers.
- Move `trade_completion_view` fully out of the hot path:
  - `markTradeExecuted` should not upsert `trade_completion_view` during `TradeExecuted` recording in loadtest/performance mode.
  - Reconciliation/projection can backfill `trade_completion_view` on a slower diagnostic/cold cadence.
  - Delayed repair must still be available outside performance mode.

Acceptance target:

- Remove the 10k `trade_completion_view` hot-path upsert from MatchEngine run-only stats.
- Do not change `trade_executions`, `trade_completion_markers`, or reliable outbox semantics.
- 10k baseline must not regress against TPS-20 baseline.
- Deep diagnostics should show lower MatchEngine write time for completion-related statements.

### TPS-22 Implementation Pass 1: Completion View Cold Path

Change made:

- Added `eap.match-engine.trade-completion-view.hot-path-enabled`.
- Production default remains `true`.
- Loadtest profile sets `hot-path-enabled=false`.
- `TradeCompletionService.markTradeExecuted` skips `trade_completion_view` upsert when the flag is disabled.
- `trade_completion_markers`, `trade_executions`, and reliable `trade_outbox` semantics are unchanged.

Verification:

| Check | Result |
|---|---|
| `TradeCompletionServiceTest` + `TradeCompletionReconcilerTest` | PASS |
| 10k baseline `GLT_20260707_TPS22_COMPLETION_VIEW_COLD_BASELINE_10K_R2` | PASS correctness and final queue drain. |
| 10k deep `GLT_20260707_TPS22_COMPLETION_VIEW_COLD_DEEP_10K_R1` | PASS correctness and final queue drain. |
| Post-run MatchEngine table shape | `trade_completion_view=0`, `trade_completion_markers=20000`, `trade_executions=10000`, `trade_outbox=10000`. |

Baseline comparison:

| Metric | TPS-20 baseline | TPS-22 baseline | Signal |
|---|---:|---:|---|
| `businessMatchedE2eTps` | `337.22` | `325.60` | Slightly worse. |
| `businessCompletionSeconds` | `29.65s` | `30.71s` | Slightly worse. |
| `tradeExecutionReachTps` | `1268.14` | `1245.75` | Roughly flat. |
| `orderCommandMatchReachTps` | `431.77` | `371.43` | Worse. |
| `completionMarkerReachTps` | `413.46` | `371.43` | Worse. |

Deep comparison:

| Metric | TPS-20 deep | TPS-22 deep | Signal |
|---|---:|---:|---|
| `businessMatchedE2eTps` | `265.58` | `270.95` | Slightly better under deep diagnostics. |
| `tradeExecutionReachTps` | `663.43` | `1248.69` | Much better; MatchEngine front-half pressure improved. |
| `orderCommandMatchReachTps` | `306.44` | `343.25` | Better than TPS-20 deep, still below TPS-19 deep. |
| `completionMarkerReachTps` | `306.44` | `343.25` | Better than TPS-20 deep, still below TPS-19 deep. |
| `maxMatchEngineQueueUnacked` | `700` | `144` | Better. |

TPS-22 deep MatchEngine SQL:

| Statement group | Calls | Total time |
|---|---:|---:|
| `trade_completion_markers` insert | `20000` | `1363.06ms` |
| `trade_executions` insert | `10000` | `725.35ms` |
| `trade_outbox` insert | `10000` | `583.82ms` |
| `trade_completion_view` upsert | `0` | Not present in top statements. |

TPS-22 deep Order SQL still dominates the command-side path:

| Statement group | Calls | Total time |
|---|---:|---:|
| Combined event append + stream-head update CTE | `10000` | `2293.02ms` |
| `order_execution_links` insert CTE | `10000` | `1202.77ms` |
| `order_event_outbox` insert | `10000` | `902.01ms` |
| `orders_current` projection update | `20000` | `599.62ms` |
| Stream-head lock select | `10000` | `546.12ms` |

Decision:

- TPS-22 is accepted as a local write-amplification cleanup: it removes `trade_completion_view` from the loadtest hot path and materially improves the deep MatchEngine front-half signal.
- TPS-22 is not accepted as the main business TPS fix because the baseline business TPS regressed slightly against TPS-20.
- The dominant amplification problem is now clearly Order-side command application: a single trade still causes buyer/seller event append, stream-head mutation, idempotency link writes, outbox write/update, and projection update pressure.

Next ticket direction:

- Focus on Order command write amplification, not MatchEngine completion view.
- Do not remove `order_execution_links` by switching to event-store idempotency; TPS-21 proved that specific route regresses.
- Evaluate whether the Order apply path can reduce round trips or combine work while keeping:
  - buyer/seller `OrderMatchedV1` event facts;
  - stream-head correctness;
  - duplicate `TradeExecuted` safety;
  - one reliable `OrderTradeApplied` marker per trade.
- Treat `orders_current` projection as a separate cold/async pressure source; it is diagnostic, not part of business gate, but it still competes for DB resources during the run.

### TPS-23 Direction: Bounded Order Projection Catch-Up

Problem:

- Completely disabling `orders_current` projection during performance runs is not a realistic business solution.
- Real operation still needs read models to keep moving.
- The real issue is that the scheduled projector used `projectUntilCaughtUp()`, which loops full batches until caught up.
- During command write bursts, that turns projection into an unbounded catch-up writer competing with `TradeExecuted -> OrderMatchedV1` command application.

Change made:

- Scheduled `OrdersCurrentProjector.project()` now processes at most `eap.order-projection.max-batches-per-tick` batches per scheduler tick.
- Default value is `1`.
- Loadtest profile sets:
  - `eap.order-projection.enabled=true`
  - `eap.order-projection.batch-size=500`
  - `eap.order-projection.max-batches-per-tick=1`
  - `eap.order-projection.poll-interval-ms=5000`
- Manual/prewarm path still calls `projectUntilCaughtUpIgnoringEnabled()`, so seed/prewarm and repair-style catch-up remain available.

Validation:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| 10k baseline `GLT_20260707_TPS23_ORDER_PROJECTION_THROTTLE_BASELINE_10K_R1` | PASS correctness and queue drain, but not a valid throughput baseline because the publisher only reached `actualBuyPublishTps=1160.83`. |

TPS-23 throttle baseline signal:

| Metric | Value |
|---|---:|
| `businessMatchedE2eTps` | `335.99` |
| `orderCommandMatchReachTps` | `395.22` |
| `completionMarkerReachTps` | `380.19` |
| `orderCurrentMatchedRows` | `2788` |
| `orderProjectionStaleRows` | `17212` |
| `orderProjectionCompletionRatio` | `0.1394` |
| final queue ready/unacked | `0` |

Interpretation:

- This validates behavior, not final throughput.
- Projection is still running; it is no longer disabled.
- It intentionally lags under command-write pressure instead of trying to fully catch up during the hot path.
- Because the publisher did not sustain 2000 TPS, rerun baseline/deep before accepting this as a performance win.

Next SQL-focused work:

- Continue with Order apply SQL shape:
  - combine or reduce round trips around `order_execution_links`, event append/head update, and shared outbox insert;
  - inspect table/index/type choices on `order_event_store`, `order_stream_heads`, `order_execution_links`, and `order_event_outbox`;
  - keep projection bounded rather than unlimited during sustained command-write bursts.

### TPS-24/TPS-25 Direction: Order Trade Application Gate and CTE Consolidation

Problem:

- The Order `TradeExecuted -> OrderMatchedV1 + OrderTradeApplied marker` path still dominated the business gate.
- TPS-22 deep showed the Order hot path spending time across separate statements:
  - combined event append + stream-head update CTE;
  - `order_execution_links` idempotency insert;
  - shared `order_event_outbox` insert;
  - stream-head lock select.
- Reducing projection pressure alone is not enough; the command write shape itself needs fewer writes and fewer DB statements.

TPS-24 change:

- Added `order_service.order_trade_applications`.
- Loadtest mode uses one trade-level idempotency row per executed trade instead of two `order_execution_links` rows.
- Old links path is retained; loadtest selects the new path with `eap.order.event-sourcing.trade-idempotency-source=trade-application`.
- Post-run table shape confirmed:
  - `order_trade_applications=10000`
  - `order_execution_links=0`
  - `order_event_store=60000`
  - `order_event_outbox=10000`

TPS-24 result:

| Run | Publish TPS | Business TPS | Order marker reach TPS | Completion marker reach TPS | Signal |
|---|---:|---:|---:|---:|---|
| `GLT_20260707_TPS24_TRADE_APPLICATION_GATE_BASELINE_10K_R1` | `1999.36` | `315.03` | `384.08` | `368.75` | Correct, but only small improvement vs TPS-19/TPS-22. |
| `GLT_20260707_TPS24_TRADE_APPLICATION_GATE_DEEP_10K_R1` | `988.71` | `279.67` | `329.68` | `329.68` | Driver was weak, useful mainly for SQL shape. |

TPS-24 deep Order SQL:

| Statement group | Calls | Total time |
|---|---:|---:|
| Event append + stream-head update CTE | `10000` | `2863.06ms` |
| Shared `order_event_outbox` insert | `10000` | `1113.87ms` |
| `order_trade_applications` insert | `10000` | `738.56ms` |
| Stream-head lock select | `10000` | `621.03ms` |

Interpretation:

- Replacing two link rows with one trade application row is semantically cleaner and removes the links table from the hot path.
- It does not by itself produce a large TPS win because the path still runs multiple DB statements per trade.
- The next change should not abandon the direction after one lower run; it should consolidate the remaining statement overhead.

TPS-25 change:

- Consolidated the trade-application hot path into one CTE statement after stream-head locking:
  - insert `order_trade_applications`;
  - insert buyer/seller `OrderMatchedV1` events;
  - update both `order_stream_heads`;
  - insert one shared `order_event_outbox` marker.
- Duplicate `TradeExecuted` still skips event/head/outbox writes by detecting existing `order_trade_applications` identity.
- Removed the old split trade-application insert helper to avoid accidentally returning to the multi-statement path.

Verification:

| Check | Result |
|---|---|
| `OrderEventAppenderPostgresIT` | PASS |
| 10k baseline `GLT_20260707_TPS25_TRADE_APPLICATION_CTE_BASELINE_10K_R1` | PASS correctness and final queue drain. |
| 10k deep `GLT_20260707_TPS25_TRADE_APPLICATION_CTE_DEEP_10K_R1` | PASS correctness and final queue drain. |
| Post-run Order table shape | `order_trade_applications=10000`, `order_execution_links=0`, `order_event_store=60000`, `order_event_outbox=10000`. |

TPS-25 result:

| Run | Publish TPS | Business TPS | Order marker reach TPS | Wallet settlement reach TPS | Completion marker reach TPS |
|---|---:|---:|---:|---:|---:|
| TPS-25 baseline | `1097.21` | `343.15` | `394.49` | `394.49` | `378.80` |
| TPS-25 deep | `1999.18` | `310.49` | `391.45` | `408.02` | `391.45` |
| TPS-24 baseline | `1999.36` | `315.03` | `384.08` | `384.08` | `368.75` |
| TPS-19 deep | `1999.16` | `302.42` | `352.38` | `352.38` | `352.38` |

TPS-25 deep Order SQL:

| Statement group | Calls | Total time |
|---|---:|---:|
| Trade application + events + heads + outbox CTE | `10000` | `3647.02ms` |
| Stream-head lock select | `10000` | `566.38ms` |
| Outbox poll select | `322` | `450.95ms` |
| `orders_current` projection update | `3516` | `131.42ms` |

SQL comparison:

- TPS-24 split path spent about `4715.49ms` across gate + event/head + outbox inserts.
- TPS-25 consolidated path spent `3647.02ms` for the same logical work.
- This removes about `1068ms / 10k trades` of Order DB statement time.
- It improves the Order marker reach rate from `384.08` to about `391-394 TPS`, and deep completion marker reach from `329.68` to `391.45 TPS`.

Current conclusion:

- The Order write-amplification problem is real, and SQL consolidation helps.
- TPS-25 is not the final 2000 TPS fix; it is an incremental improvement that proves the next work should continue reducing Order hot-path write cost.
- Remaining large cost is now inside the consolidated CTE itself:
  - `order_event_store` still writes duplicated payload/canonical and metadata/canonical columns;
  - event-store and outbox FK checks still show up as hidden `FOR KEY SHARE` lookups;
  - shared outbox insert remains logically required for the completion marker;
  - projection is bounded and still lags intentionally under command pressure.

Next ticket direction:

- Continue with Order event-store row width and constraint/index review.
- Evaluate removing duplicated canonical columns or converting unused JSONB payload columns to a narrower storage strategy where query semantics do not require JSONB.
- Evaluate whether hot-path FK checks on outbox/event-store are worth keeping in loadtest mode or should be replaced by application transaction invariants.
- Keep the business definition unchanged: completed trades require `TradeExecuted + ORDER_APPLIED marker + WALLET_SETTLED marker`; projection remains outside the business gate but must keep running in bounded mode.

### TPS-26/TPS-27 Direction: Order Event-Store Row Width and Unused Index

Problem:

- After TPS-25, the main Order SQL cost moved into one consolidated CTE.
- The CTE still wrote duplicated event-store payload data:
  - `payload`
  - `payload_canonical`
  - `metadata`
  - `metadata_canonical`
- Current replay/projection/duplicate-check paths read only `payload_canonical` and `metadata_canonical`.
- `idx_order_event_occurred_at` had no runtime scans in the measured loadtest but still charged every event-store insert.

TPS-26 change:

- Dropped duplicated `order_event_store.payload` and `order_event_store.metadata` columns.
- Updated Order event-store inserts to write only:
  - `payload_canonical`
  - `metadata_canonical`
- Kept hash computation unchanged; hashes still use canonical payload and metadata.
- Kept projection/replay behavior unchanged because both already read canonical payload.

Verification:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `OrderEventAppenderPostgresIT` | PASS |
| Loadtest Liquibase | `order-es-012` applied; `payload` and `metadata` dropped from `order_event_store`. |
| 10k baseline `GLT_20260707_TPS26_EVENT_STORE_ROW_WIDTH_BASELINE_10K_R1` | PASS correctness and final queue drain. |
| 10k deep `GLT_20260707_TPS26_EVENT_STORE_ROW_WIDTH_DEEP_10K_R1` | PASS correctness and final queue drain, but noisy under diagnostics. |

TPS-26 baseline result:

| Metric | TPS-25 deep | TPS-26 baseline | Signal |
|---|---:|---:|---|
| `actualBuyPublishTps` | `1999.18` | `1999.27` | Comparable publish pressure. |
| `businessMatchedE2eTps` | `310.49` | `317.07` | Slightly better. |
| `businessCompletionSeconds` | `32.21s` | `31.54s` | Slightly better. |
| `orderCommandMatchReachTps` | `391.45` | `422.02` | Better Order marker reach. |
| `completionMarkerReachTps` | `391.45` | `403.48` | Better completion marker reach. |

TPS-26 deep SQL result:

| Statement group | TPS-25 deep | TPS-26 deep | Signal |
|---|---:|---:|---|
| Trade application + events + heads + outbox CTE | `3647.02ms` | `3509.11ms` | About `138ms / 10k trades` lower. |
| Stream-head lock select | `566.38ms` | `569.88ms` | Flat. |
| Outbox poll select | `450.95ms` | `223.49ms` | Lower in this run. |
| Projection update | `131.42ms` | `112.12ms` | Slightly lower. |

Interpretation:

- Dropping duplicated event-store columns is correct and reduces row width.
- It is not the main TPS fix by itself; the consolidated CTE cost only dropped by about `138ms / 10k trades`.
- The stronger TPS26 baseline Order marker result is useful, but the noisy TPS26 deep run means this should be treated as an incremental improvement, not a final bottleneck removal.

TPS-27 change:

- Dropped `idx_order_event_occurred_at`.
- Rationale:
  - `pg_stat_user_indexes` showed `idx_order_event_occurred_at idx_scan=0`.
  - No current Order code path reads event-store rows by occurred-time range.
  - The index still charges every event-store insert.
- Kept `idx_order_event_type_position(event_type, global_position)` because verifier/diagnostic counts use `event_type`.

TPS-27 baseline result:

| Metric | TPS-26 baseline | TPS-27 baseline | Signal |
|---|---:|---:|---|
| `actualBuyPublishTps` | `1999.27` | `1999.45` | Comparable publish pressure. |
| `businessMatchedE2eTps` | `317.07` | `323.40` | Slightly better. |
| `businessCompletionSeconds` | `31.54s` | `30.92s` | Slightly better. |
| `orderCommandMatchReachTps` | `422.02` | `398.73` | Worse than TPS-26 baseline, still above TPS-25 deep. |
| `completionMarkerReachTps` | `403.48` | `398.73` | Roughly flat/slightly worse. |
| `maxMatchEngineQueueUnacked` | `152` | `122` | Slightly lower. |

Post-run index shape:

| Event-store index | Status |
|---|---|
| `idx_order_event_type_position` | Kept; used by event type counts. |
| `order_event_store_pkey` | Kept. |
| `uk_order_aggregate_version` | Kept; event stream invariant. |
| `uk_order_event_id` | Kept; event id invariant and duplicate checks. |
| `idx_order_event_occurred_at` | Dropped. |

TPS-28 change:

- Reworked Wallet `TradeExecuted` settlement hot path from repository/JPA multi-step writes into one JDBC CTE.
- Previous per-trade Wallet path:
  - `trade_settlements existsByTradeId`
  - buyer wallet update
  - seller wallet update
  - `trade_settlements` insert
  - wallet outbox insert through JPA
- New per-trade Wallet path:
  - insert `trade_settlements` as the idempotency gate with `ON CONFLICT DO NOTHING`
  - update buyer and seller wallets only when the idempotency insert succeeds
  - insert `WalletTradeSettledEvent` outbox only when both wallet updates succeed
  - return counts to Java and rollback the transaction if a non-duplicate trade did not update both wallets and outbox
- The listener now serializes the outbox payload before opening the DB transaction, shortening transaction hold time.
- Business semantics remain unchanged:
  - duplicate `TradeExecuted` is a no-op;
  - buyer locked currency and seller locked amount are still validated by guarded updates;
  - `WalletTradeSettledEvent` is still emitted through the wallet outbox.

TPS-28 verification:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest` in `eap-wallet` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-wallet` | PASS |
| 10k baseline `GLT_20260707_TPS28_WALLET_CTE_BASELINE_10K_R1` | PASS correctness and final queue drain. |

TPS-28 baseline result:

| Metric | TPS-27 best valid 2000 offered-load sample | TPS-28 baseline | Signal |
|---|---:|---:|---|
| `actualBuyPublishTps` | `1999.61` | `1998.98` | Comparable publish pressure. |
| `businessMatchedE2eTps` | `387.72` | `386.22` | Flat. |
| `businessCompletionSeconds` | `77.38s` for 30k | `25.89s` for 10k | Comparable after scale difference. |
| `tradeExecutionReachTps` | `1047.06` | `1513.19` | Higher in this run; MatchEngine not the bottleneck. |
| `orderCommandMatchReachTps` | `401.33` | `497.34` | Better downstream apply reach. |
| `walletSettlementReachTps` | `401.33` | `497.34` | Better Wallet settlement reach. |
| `completionMarkerReachTps` | `401.33` | `472.10` | Better completion marker reach. |

Interpretation:

- TPS-28 is a real hot-path improvement, unlike the smaller TPS-26/TPS-27 cleanup deltas.
- The most direct win is Wallet write amplification reduction: duplicate check + two wallet updates + settlement insert + outbox insert now cost one database round trip.
- Completion is still below the old historical `800+ TPS` target, so the next bottleneck is likely still the combined Order apply / Wallet settlement / completion marker chain, not MatchEngine.
- Because this was a single 10k run, confirm with repeat baseline before treating the exact `497 TPS` value as stable.

Current conclusion:

- TPS-26 and TPS-27 are valid cleanup steps that reduce unnecessary event-store write amplification.
- TPS-28 is the first clear downstream apply improvement in this series.
- The next major target should inspect remaining hidden write costs in:
  - Order event-store/outbox FK checks and stream-head locking;
  - Wallet remaining row/index/update cost after the CTE consolidation;
  - MatchEngine completion marker insert/update path;
  - outbox relay polling/update cadence.

### Measurement Update: Repeat Runs Before Small-Difference Decisions

Problem:

- Recent 10k/5s runs show small differences between changes.
- Single-run deltas of a few percent can be caused by local machine noise, JVM warmup, Docker scheduling, PostgreSQL cache state, RabbitMQ timing, or diagnostics overhead.
- A single run should not decide whether a small SQL/index change is a real improvement.

Change:

- Added `scripts/load-test/run-2000-ticket-marker-repeat.sh`.
- The repeat runner executes the existing 2000 TPS marker probe multiple times and writes:
  - per-run result JSONs;
  - one summary JSON with `avg`, `min`, `max`, `spread`, and `relativeSpreadPct`.

Recommended usage:

```bash
REPEATS=3 \
TARGET_TPS=2000 \
DURATION_SECONDS=15 \
EVENTS=30000 \
DIAGNOSTICS_LEVEL=baseline \
  ./scripts/load-test/run-2000-ticket-marker-repeat.sh GLT_20260707_TPS_COMPARE
```

Interpretation rule:

- Use `baseline` repeats for throughput decisions.
- Use `deep` runs for bottleneck attribution, not for final TPS acceptance.
- Treat a change as meaningful only when the delta is larger than the observed repeat spread.
- For small deltas, compare median/average across repeat runs instead of one best or one worst run.
- Prefer longer publish windows such as `30000 events / 15s` or `60000 events / 30s` when validating final performance, because 10k/5s runs are too sensitive to short local noise.

Current practical standard:

| Run type | Purpose | Suggested config |
|---|---|---|
| Quick smoke | Correctness after code edits | `EVENTS=10000`, `DURATION_SECONDS=5`, `REPEATS=1` |
| Baseline comparison | Decide whether a small optimization helped | `EVENTS=30000`, `DURATION_SECONDS=15`, `REPEATS=3`, `DIAGNOSTICS_LEVEL=baseline` |
| Strong acceptance | Confirm final improvement | `EVENTS=60000`, `DURATION_SECONDS=30`, `REPEATS=3-5`, `DIAGNOSTICS_LEVEL=baseline` |
| SQL attribution | Find hot SQL after a candidate change | Single `DIAGNOSTICS_LEVEL=deep` run, then inspect `pg_stat_statements` |

### TPS-29: Order Hot-Path Observation Cost and Phase Attribution

Problem:

- TPS-28 made Wallet cheaper, leaving Order trade apply as the largest remaining SQL hot path in deep diagnostics.
- Order trade apply is not a simple blind write path:
  - it must lock buyer/seller `order_stream_heads`;
  - it needs previous `current_version` and `last_hash` to append hash-chained event-store rows;
  - it writes one trade idempotency row, two OrderMatched event rows, two stream-head updates, and one shared outbox row per trade.
- The load-test sampler still used `order_event_store WHERE event_type = 'OrderMatchedV1'` for repeated progress snapshots, which made `idx_order_event_type_position(event_type, global_position)` look useful even though the production projector reads by `global_position`.

Change:

- Changed non-strict load-test progress snapshots to count OrderMatched progress from `order_trade_applications * 2`.
- Kept strict final correctness verification against `order_event_store WHERE event_type = 'OrderMatchedV1'`.
- Changed command-state progress counting to read `order_stream_heads` directly instead of joining `orders_current`, so the business gate no longer depends on projection catch-up.
- Added `order-es-014` to drop `idx_order_event_type_position` from the Order event-store write hot path.
- Added low-cost Micrometer timer `eap_order_trade_apply_duration` with phase tag:
  - `total`
  - `lock_heads`
  - `prepare_append`
  - `append_cte`

Expected signal:

- Baseline runs should no longer pay per-event write cost for the diagnostic-only `event_type/global_position` index.
- Deep runs should expose whether Order wall-clock time is dominated by DB CTE execution, stream-head lock acquisition, Java serialization/hash preparation, or transaction overhead around the append.

Verification so far:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` in `eap-order` | PASS |
| `bash -n scripts/load-test/collect-loadtest-diagnostics.sh scripts/load-test/run-global-matched-e2e-two-phase.sh scripts/load-test/run-2000-ticket-marker-10k.sh` | PASS |

TPS-29 quick load-test results:

| Run | Diagnostics | Offered load | Business TPS | Completion marker TPS | Result |
|---|---|---:|---:|---:|---|
| `GLT_20260707_TPS29_ORDER_OBS_BASELINE_10K_R1` | baseline | `942.69` | `341.18` | `427.68` | PASS correctness, driver-limited; do not use for TPS comparison. |
| `GLT_20260707_TPS29_ORDER_OBS_BASELINE_10K_R2` | baseline | `1999.32` | `419.73` | `491.72` | PASS correctness; valid 2000 offered-load sample. |
| `GLT_20260707_TPS29_ORDER_OBS_DEEP_10K_R1` | deep | `1998.75` | `312.48` | `406.60` | PASS correctness; use for attribution, not final TPS. |

TPS-29 deep attribution:

| Signal | Value |
|---|---:|
| Order trade apply CTE SQL total | `3285.14 ms / 10k` |
| Order stream-head `FOR UPDATE` SQL total | `598.99 ms / 10k` |
| `eap_order_trade_apply_duration{phase="total"}` sum | `32.1426s / 10k` |
| `phase="append_cte"` sum | `13.5837s / 10k` |
| `phase="lock_heads"` sum | `10.2190s / 10k` |
| `phase="prepare_append"` sum | `0.5212s / 10k` |

Interpretation:

- `idx_order_event_type_position` is gone from `pg_stat_user_indexes`, confirming `order-es-014` applied.
- Repeated progress snapshots no longer need the `event_type/global_position` index; strict final verification still checks `order_event_store`.
- The phase timer shows serialization/hash preparation is not the main wall-clock issue.
- The largest Order-side costs are still the database append CTE, stream-head locking, and transaction/commit overhead around them.
- Next Order fix should focus on reducing event-store/outbox/FK/index work or shortening the stream-head locked transaction, not on payload serialization.

### TPS-30: Order Outbox FK Cost and Transaction Hold Time

Problem:

- TPS-29 showed that `prepare_append` is small, but Order still spends material wall-clock time in `lock_heads` and `append_cte`.
- The stream-head lock cannot be removed just because `order_trade_applications` provides trade idempotency:
  - idempotency prevents the same trade from being applied twice;
  - stream-head locking still protects per-order `remaining_amount`, `current_version`, and hash-chain continuity across different trades for the same order.
- The Order append CTE still paid an outbox FK check against `order_event_store(event_id)` for every shared outbox row.

Change:

- Moved `OrderTradeAppliedEvent` outbox payload serialization before the consumer transaction starts.
- Added `order-es-015` to drop `fk_order_outbox_event`.
- Kept:
  - `uk_order_outbox_event_id`;
  - event-store `event_id` and `(aggregate_id, aggregate_version)` uniqueness;
  - stream-head locking and state checks.

Rationale:

- Outbox rows for this path are inserted by the same append CTE after `inserted_events`; application-level atomicity already guarantees that the outbox row is produced from a successful event append.
- Dropping only the outbox FK removes the per-outbox key-share check without weakening the event-store stream invariants.
- This is expected to be a small write-cost reduction, not a complete Order bottleneck fix.

Verification so far:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT` in `eap-order` | PASS |

TPS-30 load-test results:

| Run | Diagnostics | Offered load | Business TPS | Completion marker TPS | Result |
|---|---|---:|---:|---:|---|
| `GLT_20260707_TPS30_ORDER_FK_BASELINE_10K_R1` | baseline | `1998.14` | `320.76` | `366.29` | PASS correctness, but worse than TPS-29 valid baseline. |
| `GLT_20260707_TPS30_ORDER_FK_DEEP_10K_R1` | deep | `1999.32` | `372.31` | `433.77` | PASS correctness; use for attribution. |

TPS-30 deep attribution:

| Signal | TPS-29 deep | TPS-30 deep |
|---|---:|---:|
| Order trade apply CTE SQL total | `3285.14 ms / 10k` | `2815.47 ms / 10k` |
| Order stream-head `FOR UPDATE` SQL total | `598.99 ms / 10k` | `584.34 ms / 10k` |
| Outbox FK key-share check against `order_event_store` | `53.72 ms / 10k` | removed |
| `eap_order_trade_apply_duration{phase="total"}` sum | `32.1426s / 10k` | `30.0856s / 10k` |
| `phase="append_cte"` sum | `13.5837s / 10k` | `12.2376s / 10k` |
| `phase="lock_heads"` sum | `10.2190s / 10k` | `9.5704s / 10k` |
| `phase="prepare_append"` sum | `0.5212s / 10k` | `0.4944s / 10k` |

Interpretation:

- The FK/write-cost change did what it was supposed to do locally: the outbox FK key-share statement disappeared and Order phase timers improved modestly.
- The end-to-end 10k result did not improve reliably, so TPS-30 should be treated as a small write-cost cleanup, not the primary throughput fix.
- The next meaningful Order change likely needs to address the larger structure:
  - two event-store rows per trade;
  - two stream-head updates per trade;
  - transaction/commit overhead per trade;
  - Rabbit listener/outbox sequencing around OrderTradeApplied.

### TPS-31: Order Trade Apply Non-Overlap Batch Write Path

Problem:

- TPS-30 reduced local FK/write cost, but Order still pays one consumer transaction/commit per `TradeExecutedEvent`.
- A full batch rewrite is risky because multiple trades in the same batch can touch the same order, and Order must preserve per-order `current_version`, `remaining_amount`, and hash-chain continuity.
- Downstream services should not be forced to consume a large batch event just because Order optimizes its internal DB writes.

Change:

- Added a batch listener container for the Order `TradeExecutedEvent` queue.
- `TradeExecutedListener` now receives a `List<TradeExecutedEvent>` and calls `OrderEventSourcingService.applyTrades`.
- Added a batch planner in `OrderEventSourcingService`:
  - `trade-application` idempotency mode can attempt DB batch apply;
  - batches with repeated buyer/seller order ids fallback to the existing single-event path;
  - other idempotency modes fallback to the existing single-event path.
- Added `OrderEventAppender.appendTradeMatchedBatchFromCaughtUpProjectionIfTradeApplicationsAbsent`.
- The batch DB path is intentionally limited to non-overlapping order ids:
  - locks all involved stream heads in stable order;
  - verifies all heads can apply the trade quantity;
  - pre-checks existing trade applications;
  - batch-inserts trade applications;
  - batch-inserts two `OrderMatchedV1` event-store rows per trade;
  - batch-updates stream heads;
  - batch-inserts one outbox row per trade.
- Outbox/MQ contract is unchanged: downstream still receives one `OrderTradeAppliedEvent` per trade.
- Loadtest profile sets `eap.order.listeners.trade-executed.batch-size=50`; default application config stays conservative at `1`.
- Added metrics:
  - `eap_order_trade_batch_total`
  - `eap_order_trade_batch_events_total`
  - `eap_order_trade_batch_applied_events_total`
  - `eap_order_trade_batch_fallback_events_total`
  - `eap_order_trade_batch_overlap_fallback_events_total`
  - additional `eap_order_trade_apply_duration` phases: `batch_total`, `batch_lock_heads`, `batch_prepare_append`, `batch_append`

Expected signal:

- If the load-test batch has mostly non-overlapping order ids, Order should reduce transaction/commit count and DB round trips.
- If overlap is common, metrics should show fallback volume instead of hiding correctness risk.
- RabbitMQ still carries individual events, so downstream consumers do not need batch semantics.

Verification so far:

| Check | Result |
|---|---|
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` in `eap-order` | PASS |
| `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT` in `eap-order` | PASS |
| `bash -n scripts/load-test/collect-loadtest-diagnostics.sh` | PASS |

TPS-31 quick load-test results:

| Run | Diagnostics | Offered load | Business TPS | Completion marker TPS | Result |
|---|---|---:|---:|---:|---|
| `GLT_20260707_TPS31_ORDER_BATCH_BASELINE_10K_R1` | baseline | `1998.93` | `320.89` | `370.64` | PASS correctness; verifies batch listener runtime does not DLQ or break message conversion. |
| `GLT_20260707_TPS31_ORDER_BATCH_LIGHT_10K_R1` | light | `1972.90` | `410.11` | `428.05` | PASS correctness; use as smoke only because light diagnostics still had limited actuator capture during this run. |
| `GLT_20260707_TPS31_ORDER_BATCH_DEEP_10K_R1` | deep | `1999.01` | `445.68` | `487.00` | PASS correctness; confirms batch path is active. |

Observed signal:

- `pg_stat_statements` after TPS-31 light shows both:
  - new batch SQL shapes, including multi-id `order_stream_heads ... WHERE aggregate_id IN (...) FOR UPDATE`, plain `INSERT INTO order_service.order_event_store`, plain `INSERT INTO order_service.order_trade_applications`, and plain `UPDATE order_service.order_stream_heads`;
  - old single-trade CTE shape, meaning fallback still occurs.
- The first TPS-31 baseline run is not a clear throughput win versus TPS-30; the light run is better but not enough to declare success because 10k local runs have known noise.
- `after-run-light` diagnostics now captures Order actuator metrics so the next light/deep run can directly report batch counter totals.
- TPS-31 deep confirms the batch path is active:
  - `eap_order_trade_batch_events_total = 10000`
  - `eap_order_trade_batch_applied_events_total = 9689`
  - `eap_order_trade_batch_fallback_events_total = 311`
  - `eap_order_trade_batch_overlap_fallback_events_total = 0`
  - batch hit ratio: `96.89%`
  - fallback ratio: `3.11%`
- TPS-31 deep phase timers:
  - `batch_total`: `12.3552s / 2089 batch attempts`
  - `batch_append`: `7.5612s / 2089`
  - `batch_lock_heads`: `2.0115s / 2089`
  - `batch_prepare_append`: `0.2454s / 2089`
  - single fallback `total`: `2.0196s / 311`
  - single fallback `append_cte`: `0.6822s / 311`
- TPS-31 deep top Order SQL confirms the write model shifted away from the single CTE for most trades:
  - batch event-store insert: `973.22 ms / 19378 calls`
  - batch trade-application insert: `483.98 ms / 9689 calls`
  - batch stream-head update: `352.62 ms / 19378 calls`
  - batch outbox insert: `322.80 ms / 9689 calls`
  - old single-trade CTE fallback: `128.77 ms / 311 calls`
- TPS-31 fallback reason follow-up (`GLT_20260707_TPS31_FALLBACK_REASON_LIGHT_10K_R1`) confirms the fallback source:
  - `eap_order_trade_batch_events_total = 10000`
  - `eap_order_trade_batch_applied_events_total = 9736`
  - `eap_order_trade_batch_fallback_events_total = 264`
  - `eap_order_trade_batch_fallback_reason_total{reason="singleton_batch"} = 264`
  - `eap_order_trade_batch_overlap_fallback_events_total = 0`
  - `eap_order_trade_batch_total = 2234`
  - average received batch size: `4.48`
  - singleton event ratio: `2.64%`
  - conclusion: the previous `3.11%` fallback was caused by Rabbit listener deliveries that arrived as single-event batches, not by overlapping orders or appender `NOT_BATCHABLE` failures.

Risk / follow-up:

- This first version only batches non-overlap trades. A later version can handle repeated orders inside the same batch by calculating per-order sequential versions/hashes before writing.
- Need baseline/deep load tests to confirm whether batch size `50` is optimal or whether it increases lock hold time under realistic overlap.
- Fallback reason metrics now distinguish singleton listener batches from appender `NOT_BATCHABLE` causes such as missing head, stale/invalid state, or existing trade application.

### TPS-32: Order Trade Apply Hot Path Three-Table Model

Decision:

- TPS-31 proved batching reduced some fixed cost, but did not remove the per-trade row-write model:
  - `order_trade_applications`: one row per trade;
  - `order_event_store`: two rows per trade;
  - `order_stream_heads`: two updates per trade;
  - `order_event_outbox`: one row per trade plus relay status update.
- The larger performance lever is to split trade application command state from per-order event-store audit.

Implemented direction:

- Added `order_service.order_matching_state` as the TradeExecuted hot-path command state:
  - `order_id`
  - `user_id`
  - `remaining_amount`
  - `matched_amount`
  - `status`
  - `last_trade_id`
  - `updated_at`
- General order lifecycle event appends now upsert matching state so confirmed orders can be matched without reading `orders_current` or mutating event-store head state during trade application.
- `trade-application` idempotency mode now applies TradeExecuted through only the business hot-path tables:
  - `order_trade_applications`
  - `order_matching_state`
  - `order_event_outbox`
- The old event-store append paths remain available for non-`trade-application` modes and fallback compatibility.

Semantic boundary:

- `order_trade_applications` means Order accepted and applied a MatchEngine trade fact.
- `order_matching_state` means the buyer/seller orders have command-side matched state and remaining quantity updated.
- `order_event_outbox` means Order will reliably publish `OrderTradeAppliedEvent` to MatchEngine completion.
- `order_event_store` / `order_stream_heads` are no longer required to advance synchronously on the TradeExecuted hot path.

Expected performance effect:

- The TradeExecuted hot path should stop writing:
  - two `OrderMatchedV1` event-store rows per trade;
  - two event-store stream-head version/hash updates per trade.
- The hot path still performs necessary writes:
  - one trade application insert;
  - two matching-state updates;
  - one OrderTradeApplied outbox insert;
  - one outbox relay status update later.
- This is a real write-amplification reduction, unlike further Rabbit listener batch tuning.

Validation requirement:

- Business gate should require:
  - `order_trade_applications` has one row per trade;
  - `order_matching_state` has buyer/seller orders in matched state;
  - Wallet settlement completed;
  - MatchEngine completion markers include `ORDER_APPLIED` and `WALLET_SETTLED`;
  - queues drain ready/unacked to zero.
- `OrderMatchedV1` event-store rows are now audit/replay output, not the synchronous business completion gate.

2026-07-08 30k deep validation:

- Runs:
  - `GLT_20260708_TPS32_HOTPATH3_DEEP_30K_R1C`
  - `GLT_20260708_TPS32_HOTPATH3_DEEP_30K_R2`
  - `GLT_20260708_TPS32_HOTPATH3_DEEP_30K_R3`
  - `GLT_20260708_TPS32_HOTPATH3_DEEP_30K_R4`
- Correctness:
  - all four runs completed `30000` trades;
  - `completedTrades=30000`;
  - `orderCommandMatchedRows=60000`;
  - `walletTradeSettlements=30000`;
  - final ready/unacked queues drained to zero;
  - `projectionIncludedInBusinessGate=false`.
- Throughput:
  - all-run average `businessMatchedE2eTps=391.02`;
  - all-run average `completionMarkerReachTps=425.46`;
  - all-run average `tradeExecutionReachTps=912.81`;
  - excluding R3, where the load driver only reached `1342.91` buy publish TPS, average `businessMatchedE2eTps=411.65` and `completionMarkerReachTps=452.71`.
- Order SQL evidence:
  - `order_event_store` had `0` inserts/updates during the run phase;
  - `order_stream_heads` had `0` inserts/updates during the run phase;
  - the hot path now primarily writes `order_trade_applications`, `order_matching_state`, and `order_event_outbox`.
- Remaining measurement issue:
  - legacy projection diagnostics still run `order_stream_heads` / `orders_current` stale checks even though TPS-32 no longer updates matched projection synchronously;
  - `orderMatchedEvents` in the load-test JSON is now a legacy field name and represents matched `order_matching_state` rows, not `OrderMatchedV1` event-store rows.
- Next bottleneck hypothesis:
  - Order's event-store/head write amplification is no longer the main limiter;
  - next investigation should focus on Wallet's settlement CTE and MatchEngine's per-trade completion marker/outbox writes.

### TPS-33: Order Command/Read Boundary After Matching-State Hot Path

Problem:

- TPS-32 made `order_matching_state` the synchronous command-side truth for TradeExecuted application.
- Some existing Order operations were originally designed before this split and may still treat event-store replay, MatchEngine Redis, legacy matched-order SQL, or `orders_current` projection as if they were safe business-decision sources.
- That is acceptable for display queries, but dangerous for operations that mutate order state or decide whether an order can still be changed.

Architectural decision:

- Read/write separation remains valid, but the split is:
  - business commands use command-side truth;
  - user-facing display queries use read models and tolerate lag.
- Reading `order_matching_state` inside a command handler is not a read-model query. It is part of the write-side consistency boundary.
- Any operation that can change order state, reject/accept a state transition, or call MatchEngine/Wallet based on current order state must be treated as a command/write-side operation.

Current logic to verify:

- `POST /user-orders/cancel` currently:
  - calls MatchEngine cancel;
  - calls `OrderEventSourcingService.cancel(orderId, userId)`;
  - `cancel(...)` currently loads the aggregate from event stream and appends `OrderCancelledV1`.
- MCP `DELETE /orders/{orderId}` currently calls MatchEngine cancel but does not persist the Order cancellation event locally.
- `OrderQueryService` currently combines:
  - pending orders from MatchEngine;
  - matched orders from legacy local matched-order SQL.
- `orders_current` is still a rebuildable projection and should not be used as a hard source for trade-applied command decisions.

Required change:

- Add a command-side guard for order mutations:
  - cancel must check `order_matching_state` for owner, status, and `remaining_amount`;
  - reject cancel for `MATCHED`, `CANCELLED`, `REJECTED`, or `remaining_amount = 0`;
  - allow cancel only when command state says the order is still open/partially open and owned by the actor.
- Make cancellation ordering explicit:
  - avoid telling MatchEngine to cancel before Order has accepted the command-side state transition, unless the flow is intentionally compensating and idempotent;
  - persist local cancellation state through the command path and publish/call downstream through an outbox-style boundary where possible.
- Decide MCP cancel semantics:
  - either persist the same local Order cancellation as the user API;
  - or document it as MatchEngine-only administrative cancellation and do not expose it as normal order cancellation.
- Keep display queries separate:
  - user order list/order detail can read `orders_current`, MatchEngine open-order query, or another read model;
  - if exact command state is required for a user action button, expose a command-state check endpoint or join from `order_matching_state` explicitly.

Acceptance criteria:

- Every Order operation is classified as one of:
  - command/write-side decision;
  - display/read-model query;
  - diagnostic/admin operation.
- Command/write-side decisions do not rely on `orders_current` projection freshness.
- Cancel cannot succeed for an order that `order_matching_state` already shows as fully matched.
- User cancel and MCP cancel semantics are consistent or explicitly separated.
- Tests cover:
  - cancel open order succeeds;
  - cancel matched order fails even if projection is stale;
  - cancel wrong user fails;
  - duplicate cancel is idempotent or returns a stable rejection;
  - MatchEngine cancel call is not made when local command-side guard rejects.

Implementation notes:

- This ticket should not add synchronous projection updates back to the hot path.
- It should not make normal display queries hit command tables by default.
- If a command needs current state, reading `order_matching_state` is part of the command transaction and does not violate read/write separation.

Implemented:

- Added Order cancellation guard against `order_matching_state`.
- User cancel now follows:
  - local command-state guard;
  - MatchEngine cancel request;
  - local `OrderCancelledV1` append with the same guard checked again.
- MCP cancel now requires `userId` and follows the same guarded flow instead of directly calling MatchEngine.
- `CancelOrderReq.orderId` and `CancelOrderReq.userId` are required.
- Added PostgreSQL integration coverage for:
  - open order cancellation updates command state to `CANCELLED`;
  - matched command state rejects cancellation even when stream head/projection is stale open;
  - wrong user rejects cancellation without appending.

Verification:

- `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order`: PASS.
- `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT -Deap.integration.postgres=true` in `eap-order`: PASS.

### TPS-34: Wallet Settlement Attribution and Realistic Flow Benchmark Split

Problem:

- The current 2000 TPS matched E2E benchmark intentionally seeds matched buyer/seller wallet state before the run phase.
- That makes the run phase good for isolating post-match throughput:
  - MatchEngine trade persistence;
  - Order trade application;
  - Wallet trade settlement;
  - completion markers;
  - queue ready/unacked drain.
- It does not measure the full real business flow where new buy/sell orders arrive, Wallet reserves assets, MatchEngine adds open orders to the book, and later trades may partially fill the same order.
- Treating the seeded benchmark as "real market TPS" would overstate realism and under-measure order-submission / reservation pressure.

Experiment design decision:

- Keep two benchmark families instead of merging all complexity into one test:
  - **Isolated matched-settlement benchmark**: seeded wallets/orders, deterministic matching, used to profile post-trade bottlenecks and compare SQL/write-path changes.
  - **Realistic market-flow benchmark**: concurrent buy/sell order submissions, Wallet reservation, MatchEngine orderbook insertion, random/partial matches, and final settlement, used for acceptance realism.
- Do not use the realistic market-flow benchmark as the first tool for SQL attribution; too many variables will make small bottleneck fixes hard to measure.
- Do use it before claiming production-like TPS, because reservation + orderbook + partial-fill behavior changes the load shape.

Wallet attribution scope:

- Add or verify metrics that separate:
  - `TradeExecutedListener` total handling time;
  - Wallet settlement payload serialization time;
  - settlement CTE DB time;
  - duplicate settlement skip count;
  - failed settlement count;
  - outbox relay select/publish/mark-sent time.
- SQL review should inspect:
  - `wallet_service.trade_settlements` unique idempotency insert cost;
  - buyer/seller `wallet_service.wallets` update cost;
  - `wallet_service.outbox` insert and SENT update cost;
  - pending outbox index scan cost;
  - diagnostic-only balance sum queries.

Realistic benchmark follow-up scope:

- Add a separate benchmark mode that can generate:
  - mixed buy/sell order submissions through the normal submit path;
  - Wallet reservation for each submitted order;
  - random price/quantity distribution that produces both unmatched resting orders and matched trades;
  - partial fills where one order can be matched by multiple later orders;
  - final invariants for balances, locked funds, order remaining quantities, completion markers, and queues.
- Start with a controlled scenario before random chaos:
  - fixed seed for deterministic replay;
  - configurable match ratio;
  - configurable partial-fill ratio;
  - report submitted-order TPS, trade-execution TPS, settlement TPS, and full-drain E2E TPS separately.

Acceptance criteria:

- Wallet settlement metrics identify whether time is dominated by DB CTE, serialization, outbox relay, or listener overhead.
- The seeded matched benchmark remains available for regression comparison.
- The realistic market-flow benchmark is clearly labeled and does not replace the seeded benchmark for low-level SQL attribution.
- Documentation distinguishes:
  - post-match settlement TPS;
  - full order-submission-to-settlement TPS;
  - production-like mixed-flow TPS.

Implemented attribution metrics:

- Added Wallet settlement counters:
  - `eap_wallet_trade_settlement_consumed_total`
  - `eap_wallet_trade_settlement_completed_total`
  - `eap_wallet_trade_settlement_duplicate_skipped_total`
  - `eap_wallet_trade_settlement_failed_total`
- Added Wallet settlement timers:
  - `eap_wallet_trade_settlement_processing_duration`
  - `eap_wallet_trade_settlement_serialization_duration`
  - `eap_wallet_trade_settlement_transaction_duration`
  - `eap_wallet_trade_settlement_cte_duration`
- Added Wallet outbox relay timers:
  - `eap_wallet_outbox_select_duration`
  - `eap_wallet_outbox_mark_sent_duration`

Verification:

- `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-wallet`: PASS.
- `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest --tests com.eap.eap_wallet.application.OutboxPollerTest` in `eap-wallet`: PASS.

### TPS-35: RabbitMQ Publisher Path Attribution and Tuning Runbook

Problem:

- After reducing Order and Wallet SQL write amplification, the completion gate started pointing at the return-marker outbox relay path.
- A naive fix was to increase outbox `publish-concurrency`, but the 2026-07-08 R8 experiment showed that this made completion worse.
- This is a common interview trap: RabbitMQ queue backlog does not automatically mean "increase consumer or publisher threads"; the real bottleneck can be channel/connection contention, publisher confirms, serialization, DB transaction time, or downstream processing.

Current RabbitMQ settings:

- All three services use Spring Boot `spring-boot-starter-amqp` and Spring Boot `3.5.3`.
- All three services enable:
  - `spring.rabbitmq.publisher-confirm-type=correlated`
  - `spring.rabbitmq.publisher-returns=true`
  - `spring.rabbitmq.template.mandatory=true`
- Loadtest consumer settings:
  - MatchEngine simple listener: `concurrency=8`, `max-concurrency=32`, `prefetch=50`
  - Wallet simple listener: `concurrency=4`, `max-concurrency=32`, `prefetch=20`
  - Order service-level listeners: trade executed `concurrency=12`, batch size `50`, receive timeout `75ms`
- Outbox relay batch settings:
  - MatchEngine `trade-outbox-relay.batch-size=500`
  - Order `order-event-outbox.batch-size=500`
  - Wallet `outbox-relay.batch-size=500`

Measured finding:

- R7, before Order/Wallet parallel publisher change:
  - `tradeExecutionReachTps=1550.22`
  - `completionMarkerReachTps=492.31`
  - `completedTradesReachedSeconds=20.31`
  - Order outbox enqueue sum about `10.95s`, confirm sum about `1.25s`
  - Wallet outbox enqueue sum about `11.50s`, confirm sum about `1.20s`
- R8, with Order/Wallet `publish-concurrency=8`:
  - `tradeExecutionReachTps=1538.03`
  - `completionMarkerReachTps=432.67`
  - `completedTradesReachedSeconds=23.11`
  - Order outbox enqueue sum jumped to `151.71s`, confirm sum stayed low at `0.85s`
  - Wallet outbox enqueue sum jumped to `157.54s`, confirm sum stayed low at `0.59s`
  - MatchEngine enqueue sum was also high at `166.88s`
- Conclusion:
  - publisher confirm wait is not the dominant cost;
  - DB mark-sent is not the dominant cost;
  - high publisher thread count appears to amplify RabbitTemplate/channel/connection contention on the local loadtest setup;
  - Order and Wallet return-marker outbox `publish-concurrency` should stay at `1`;
  - MatchEngine can keep controlled parallel outbox publishing because earlier runs showed the upstream `TradeExecuted` path benefits from it.

Spring AMQP reference points:

- Spring AMQP's `CachingConnectionFactory` uses one shared connection by default and caches channels; the default channel cache size is `25`.
- The channel cache size is not a hard limit unless `channelCheckoutTimeout` is greater than zero; if more channels are used than the cache size, surplus channels may be physically closed instead of retained.
- Spring AMQP explicitly warns that in high-volume multi-threaded environments a small cache can cause high channel create/close churn and recommends monitoring RabbitMQ channels before increasing the cache.
- Spring AMQP also notes that producers and consumers sharing one connection can be a risk when the broker blocks the connection; a separate publisher connection can mitigate that class of producer/consumer interference.
- Spring Boot exposes the relevant cache properties:
  - `spring.rabbitmq.cache.channel.size`
  - `spring.rabbitmq.cache.channel.checkout-timeout`
  - `spring.rabbitmq.cache.connection.mode`
  - `spring.rabbitmq.cache.connection.size`

Sources:

- Spring AMQP connection/resource management: https://docs.spring.io/spring-amqp/reference/amqp/connections.html
- Spring Boot common RabbitMQ application properties: https://docs.spring.io/spring-boot/appendix/application-properties/index.html

Safe default after R8:

```yaml
eap:
  match-engine:
    trade-outbox-relay:
      publish-concurrency: 8
  order-event-outbox:
    publish-concurrency: 1
  wallet:
    outbox-relay:
      publish-concurrency: 1
```

Controlled next experiment:

- Do not increase publisher concurrency by itself.
- First add Rabbit channel-cache visibility:
  - capture RabbitMQ management API connection/channel counts;
  - capture channel churn if available from the management API;
  - keep `*_outbox_publish_enqueue_duration`, `*_outbox_confirm_duration`, and `*_outbox_batch_duration`.
- Then test one variable at a time:
  - baseline: MatchEngine `publish-concurrency=8`, Order/Wallet `publish-concurrency=1`, current channel cache defaults;
  - cache-only: `spring.rabbitmq.cache.channel.size=128`, same publisher concurrency shape;
  - bounded parallel publish: `spring.rabbitmq.cache.channel.size=128`, `spring.rabbitmq.cache.channel.checkout-timeout=1000ms`, Order/Wallet `publish-concurrency=2`;
  - only if `2` improves, try `4`; do not jump directly to `8`.

Candidate loadtest patch for the cache experiment:

```yaml
spring:
  rabbitmq:
    cache:
      channel:
        size: 128
```

Acceptance criteria for any Rabbit publisher tuning:

- `completionMarkerReachTps` improves over the current valid baseline by more than local run noise.
- `businessMatchedE2eTps` improves or remains flat while completion improves.
- `*_outbox_publish_enqueue_duration_seconds_sum` does not explode relative to single-thread baseline.
- `*_outbox_confirm_duration_seconds_sum` remains low.
- Final queues ready/unacked drain to zero.
- No DLQ, no outbox failed rows, and final DB invariants remain correct.

Interview explanation:

> I initially suspected RabbitMQ outbox publishing because completion markers lagged after the DB SQL optimizations. Instead of guessing, I split the relay into select, enqueue, confirm, mark-sent, and batch wall-time metrics. The data showed publisher confirms were cheap, but enqueue time exploded when I increased publisher threads. That told me the bottleneck was not broker ack latency; it was local publisher path contention, likely around RabbitTemplate/channel/connection resources. I reverted the default concurrency, documented a channel-cache experiment, and kept the reliable outbox semantics unchanged.

2026-07-08 follow-up measurements:

| Run | Rabbit setting | `businessMatchedE2eTps` | `completionMarkerReachTps` | `tradeExecutionReachTps` | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS35_RABBIT_BASELINE_10K_R1` | all outbox publishers `publish-concurrency=1`, default channel cache | `427.80` | `427.80` | `1053.60` | Correctness PASS, but MatchEngine trade execution regressed versus the earlier MatchEngine-parallel runs. |
| `GLT_20260708_TPS35_RABBIT_R7SHAPE_10K_R1` | MatchEngine `publish-concurrency=8`, Order/Wallet `1`, default channel cache | `349.63` | `437.73` | `1173.77` | Correctness PASS. Completion facts reached around `22.84s`, but final ready+unacked drain pushed business gate to `28.60s`. |
| `GLT_20260708_TPS35_RABBIT_CACHE128_10K_R1` | MatchEngine `8`, Order/Wallet `1`, `spring.rabbitmq.cache.channel.size=128` | `399.59` | `478.64` | `962.19` | Correctness PASS. Valid publish pressure: `actualBuyPublishTps=1999.19`. |
| `GLT_20260708_TPS35_RABBIT_CACHE128_10K_R2` | Same as R1 | `394.36` | `474.93` | `1313.74` | Correctness PASS. Valid publish pressure: `actualBuyPublishTps=1998.94`. |
| `GLT_20260708_TPS35_RABBIT_CACHE128_10K_R3` | Same as R1 | `315.85` | `378.05` | `642.49` | Correctness PASS, but driver-limited: `actualBuyPublishTps=753.93`; exclude from service-side tuning average. |
| `GLT_20260708_TPS35_RABBIT_CACHE128_10K_R4` | Same as R1 | `433.78` | `470.93` | `888.80` | Correctness PASS, but driver-limited: `actualBuyPublishTps=908.31`; exclude from service-side tuning average. |
| `GLT_20260708_TPS35_ORDER_WALLET_PUB2_10K_R1` | Cache `128`, MatchEngine `8`, Order/Wallet `publish-concurrency=2` | `333.21` | `418.23` | `1023.57` | Correctness PASS and valid publish pressure (`1998.92`), but worse than PUB1. Revert Order/Wallet publisher concurrency to `1`. |

Cache128 valid-publish average:

- Valid runs: `R1`, `R2`.
- `actualBuyPublishTps=1999.07`.
- `businessMatchedE2eTps=396.98`.
- `completionMarkerReachTps=476.78`.
- `tradeExecutionReachTps=1137.97`.
- `businessCompletionSeconds=25.20`.
- `completedTradesReachedSeconds=20.98`.

All-run average including driver-limited samples:

- `actualBuyPublishTps=1415.09`.
- `businessMatchedE2eTps=385.90`.
- `completionMarkerReachTps=450.64`.
- This number is not a clean service-side benchmark because `R3` and `R4` failed to sustain the 2000 TPS publish input.

Stage timer comparison:

| Stage | R7-shape default cache | Cache size 128 | Signal |
| --- | ---: | ---: | --- |
| MatchEngine outbox batch sum | `22.33s` | `19.71s` | Better. |
| MatchEngine publish enqueue sum | `169.63s` | `138.76s` | Better; supports the channel-cache hypothesis. |
| Order outbox batch sum | `14.39s` | `15.13s` | Roughly flat/slightly worse. |
| Order publish enqueue sum | `11.95s` | `12.64s` | Roughly flat/slightly worse. |
| Wallet outbox batch sum | `14.54s` | `15.33s` | Roughly flat/slightly worse. |
| Wallet publish enqueue sum | `11.57s` | `12.54s` | Roughly flat/slightly worse. |

Order/Wallet `publish-concurrency=2` rejection:

- PUB2 was a valid input-pressure run (`actualBuyPublishTps=1998.92`), so the regression is meaningful.
- Compared with Cache128 PUB1 valid samples:
  - `businessMatchedE2eTps` dropped from about `396.98` to `333.21`.
  - `completionMarkerReachTps` dropped from about `476.78` to `418.23`.
  - business completion stretched from about `25.20s` to `30.01s`.
- Stage timers explain the regression:
  - Order publish enqueue sum increased from about `12-13s` to `27.88s`.
  - Wallet publish enqueue sum increased from about `12-13s` to `27.75s`.
  - Order confirm sum increased to `2.88s`; Wallet confirm sum increased to `3.76s`.
- Conclusion:
  - Order/Wallet return-marker publisher concurrency should remain `1`;
  - the bottleneck is not solved by adding publisher threads;
  - parallel marker publishing increases RabbitTemplate/channel/broker contention in this local benchmark.

RabbitMQ channel observation:

- Default-cache R7-shape snapshot had about `240` channel lines in `rabbitmq-channels.txt`.
- Cache size `128` snapshot had about `549` channel lines.
- Interpretation:
  - increasing channel cache may reduce MatchEngine publisher churn, but it also allows the client to retain many more channels;
  - this is not free and should be evaluated with more runs and RabbitMQ memory/CPU metrics;
  - do not apply the same conclusion blindly to production without broker capacity limits.

Current working hypothesis:

- MatchEngine benefits from controlled parallel outbox publishing because it is the upstream fan-out point for `TradeExecuted`.
- Order and Wallet return-marker relays should stay single-publisher for now; opening them to `2` or `8` created enqueue contention and lowered completion TPS.
- Channel cache size `128` is a plausible loadtest tuning candidate for the MatchEngine-heavy shape, but it increases retained channels substantially and should be documented as a loadtest tuning, not blindly copied to production.
- The next improvement work should avoid publisher-thread fan-out and instead inspect:
  - MatchEngine `TradeExecuted` outbox publish path, because it still dominates enqueue time;
  - final ready+unacked drain after completion markers are already written;
  - whether `TradeExecuted` fan-out can reduce Rabbit payload/conversion/channel overhead without weakening outbox reliability.

### TPS-36 to TPS-38: MatchEngine Hot Path Cleanup

Problem:

- After Order and Wallet write-amplification cleanup, the visible bottleneck moved back to MatchEngine.
- TPS-35 showed Rabbit publisher concurrency is not a generic fix:
  - Order/Wallet `publish-concurrency=2` regressed.
  - MatchEngine still had high publisher enqueue cost and, in some runs, a large `matchEngine.orderConfirmed.queue` backlog.
- The MatchEngine hot path still had two avoidable costs:
  - parallel outbox publishing used one `RabbitTemplate.send(...)` call per worker/message, causing high channel/template overhead;
  - trade persistence used JPA `findByTradeId` + `save(trade)` + `save(outbox)` for every matched trade.

Implemented changes:

- MatchEngine outbox relay:
  - when `publish-concurrency > 1`, partition the pending outbox batch into contiguous chunks;
  - publish each chunk through `RabbitTemplate.invoke(...)` so each worker reuses a dedicated channel for the chunk;
  - keep per-message `CorrelationData` and the existing publisher confirm/mark-sent semantics.
- MatchEngine completion marker listeners:
  - consume `OrderTradeAppliedEvent` and `WalletTradeSettledEvent` as Spring AMQP consumer batches;
  - write markers with JDBC `batchUpdate`;
  - keep the same append-only `trade_completion_markers` table and `ON CONFLICT (trade_id, marker_type) DO NOTHING` idempotency.
- MatchEngine trade recorder:
  - replace the JPA recorder internals with explicit JDBC inserts;
  - remove the per-trade `findByTradeId` preselect;
  - insert `trade_executions` with `ON CONFLICT (trade_id) DO NOTHING` and fail if affected rows is `0`;
  - insert `trade_outbox` in the same transaction with `ON CONFLICT (event_type, aggregate_id) DO NOTHING`;
  - preserve the reliable outbox boundary: `trade_executions` and `trade_outbox` are still committed together.

Verification:

- Focused tests:
  - `TradeOutboxRelayTest`
  - `TradeCompletionServiceTest`
  - `JpaTradeExecutionRecorderTest`
- Command:

```bash
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest
```

- Result: PASS.

10k deep run comparison:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `tradeExecutionReachTps` | `businessCompletionSeconds` | `maxMatchEngineQueueReady` | `maxMatchEngineQueueUnacked` |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Cache128 valid average | Match publish-concurrency `8`, Order/Wallet `1`, channel cache `128` | `1999.07` | `396.98` | `476.78` | `1137.97` | `25.20` | mixed | mixed |
| `GLT_20260708_TPS36_MATCH_INVOKE_10K_R1` | Match outbox chunked `RabbitTemplate.invoke(...)` | `1999.25` | `362.10` | `520.40` | `841.44` | `27.62` | `0` | `74` |
| `GLT_20260708_TPS37_MATCH_MARKER_BATCH_10K_R1` | TPS36 + completion marker batch listener | `1999.30` | `390.38` | `525.21` | `684.92` | `25.62` | `3233` | `700` |
| `GLT_20260708_TPS38_MATCH_JDBC_RECORDER_10K_R1` | TPS37 + JDBC trade recorder | `1794.00` | `454.71` | `621.38` | `968.74` | `21.99` | `0` | `27` |
| `GLT_20260708_TPS38_MATCH_JDBC_RECORDER_10K_R2` | Same as R1 | `1998.40` | `532.93` | `617.32` | `994.10` | `18.76` | `0` | `95` |

Interpretation:

- TPS36 fixed the Match outbox publisher overhead:
  - Match `trade_outbox_publish_enqueue_duration_seconds_sum` fell from the Cache128 `~138-139s` class to about `1.42s`.
  - Match outbox batch wall time improved from roughly `19.7-20.0s` to `14.48s`.
  - This was a real local publisher-path cleanup, but it did not by itself improve business E2E because downstream/final unacked drain still dominated.
- TPS37 completion marker batching reduced transaction overhead but did not solve the main bottleneck:
  - Match DB `BEGIN` count dropped from the `30026` class to about `11440`.
  - `completionMarkerReachTps` improved only slightly (`520.40` to `525.21`).
  - `matchEngine.orderConfirmed.queue` still spiked to `3233`, so marker batching is worth keeping but is not the primary fix.
- TPS38 JDBC recorder is the first clearly effective MatchEngine hot-path fix:
  - the per-trade JPA `findByTradeId` select disappeared from Match DB stats;
  - `matchEngine.orderConfirmed.queue` peak dropped from TPS37 `3933` messages to `0-95`;
  - valid-input R2 reached `businessMatchedE2eTps=532.93`, `completionMarkerReachTps=617.32`, and `businessCompletionSeconds=18.76`.

Current conclusion:

- The previous MatchEngine ingress bottleneck was not PostgreSQL raw statement time alone; it was the Java/JPA recorder path around the DB writes.
- Explicit JDBC made the consumer hot path much cheaper even though the raw insert statements still appear near the top of `pg_stat_statements`.
- The bottleneck has now moved downstream again:
  - `order.tradeExecuted.queue` max unacked was `365` in TPS38 R2;
  - `matchEngine.orderTradeApplied.queue` max unacked was `403`;
  - `matchEngine.walletTradeSettled.queue` max unacked was `110`.
- Next optimization should focus on Order `TradeExecuted` apply and return-marker drain, not further MatchEngine trade recorder micro-optimizations.

Interview explanation:

> I found a case where PostgreSQL statement timing alone was misleading. MatchEngine did not look terrible in `pg_stat_statements`, but RabbitMQ showed `matchEngine.orderConfirmed.queue` consumers saturated and backed up. The code path was doing a JPA duplicate preselect and two JPA saves for every trade. I replaced that with explicit JDBC inserts using unique constraints for idempotency and kept `trade_executions` plus `trade_outbox` in one transaction. The result was a clear drop in MatchEngine queue backlog and a valid 10k run improving business completion from the `~397 TPS` class to `~533 TPS`, while preserving reliable outbox semantics.

### TPS-39 to TPS-41: Completion Tail and Marker Observability

Purpose:

- After TPS38, the main visible backlog moved away from MatchEngine ingress and toward downstream trade application / completion marker drain.
- Two follow-up checks were run:
  - test whether larger Order trade batches reduce business completion time;
  - add Match completion marker metrics and test whether lowering marker listener wait time improves completion visibility.

Order batch-size experiment:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS38_MATCH_JDBC_RECORDER_10K_R2` | Baseline after Match JDBC recorder | `1998.40` | `532.93` | `617.32` | `18.76` | Valid baseline. |
| `GLT_20260708_TPS39_ORDER_BATCH100_10K_R1` | Order `trade-executed.batch-size=100`, `receive-timeout-ms=125` | `1999.10` | `487.29` | `652.28` | `20.52` | Rejected. Larger batches reduced batch count but stretched E2E tail. |

TPS39 interpretation:

- Order batch count dropped from `523` to `262`, and singleton fallback dropped from `47` to `0`.
- Order batch append wall time improved from `6.99s` to `5.50s`.
- But business completion worsened from `18.76s` to `20.52s`.
- Conclusion: larger Order batches reduce local DB transaction overhead but add enough wait/tail latency to hurt this 10k business gate. Keep the smaller `batch-size=50` / `receive-timeout-ms=25` loadtest shape.

Match completion marker experiment:

- Added `TradeCompletionMarkerMetrics` for:
  - `trade_completion_marker_batches`
  - `trade_completion_marker_events`
  - `trade_completion_marker_batch_size`
  - `trade_completion_marker_insert_duration`
- Reduced Match completion marker listener `receive-timeout-ms` from `75` to `25` in the loadtest profile.
- Added focused unit coverage proving the marker metric class records batch count, event count, and insert timer.

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `tradeExecutionReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS40_MATCH_MARKER_METRICS_TIMEOUT25_10K_R1` | marker metrics + timeout `25ms` | `818.13` | `493.60` | `682.73` | `801.07` | `20.26` | Invalid for TPS comparison because publisher only reached `818 TPS`. |
| `GLT_20260708_TPS41_MATCH_MARKER_METRICS_TIMEOUT25_10K_R2` | same as TPS40 | `1999.31` | `502.25` | `674.14` | `1094.19` | `19.91` | Valid input-pressure run. |

TPS41 interpretation:

- Lower marker listener timeout improved completion visibility relative to TPS38 R2:
  - `completionMarkerReachTps`: `617.32` -> `674.14`.
  - `completedTradesReachedSeconds`: `16.20s` -> `14.83s`.
- It did not improve the full business gate:
  - `businessMatchedE2eTps`: `532.93` -> `502.25`.
  - `businessCompletionSeconds`: `18.76s` -> `19.91s`.
- Match DB raw marker insert cost is not the dominant issue:
  - TPS41 `trade_completion_markers` insert total was `899.72ms` for `20000` rows.
  - The bigger remaining Match-side wall-clock cost is still outbox publish/confirm batch time (`trade_outbox_batch_duration_seconds_sum=12.28s`, confirm sum `11.36s`), but this overlaps with downstream drain and is no longer the only bottleneck.
- The new marker metrics did not appear in the TPS41 actuator scrape even though the unit-level registry test passed. Production constructor ambiguity was removed after TPS41 by making Spring use the single production constructor with `TradeCompletionMarkerMetrics`.

Current conclusion:

- Reject Order batch-size `100` / timeout `125ms`; it hides work in a larger wait window and worsens E2E completion.
- Keep Match marker timeout `25ms` as a candidate because it improves `completedTrades` visibility, but validate one more run after the constructor cleanup to confirm metrics are exposed.
- The next real optimization target remains downstream completion:
  - Order `TradeExecuted` apply still writes `order_trade_applications`, updates two `order_matching_state` rows, and inserts `order_event_outbox`.
  - Order outbox return-marker publishing still adds visible select/update/publish work.
  - Wallet settlement is no longer showing a large queue tail in TPS41, but it should still be monitored in mixed-flow tests.

### TPS-42: Rejected Order Outbox Raw JSON Relay

Hypothesis:

- Order return-marker outbox already stores JSON payload in `order_event_outbox.payload`.
- The relay was deserializing JSON into `OrderTradeAppliedEvent` and then letting `RabbitTemplate.convertAndSend(...)` serialize it again.
- A possible fixed-cost cleanup was to publish the stored JSON bytes directly as an AMQP JSON message, preserving publisher confirms and the same outbox table.

Experiment:

- Temporarily changed `OrderEventOutboxRelay` to send raw JSON `Message` payloads with content type `application/json` and the stored message type header.
- Ran `GLT_20260708_TPS42_ORDER_OUTBOX_RAW_JSON_10K_R1`.
- Reverted the code after the result because the experiment regressed.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS41_MATCH_MARKER_METRICS_TIMEOUT25_10K_R2` | previous valid sample | `1999.31` | `502.25` | `674.14` | `19.91` | Baseline for this comparison. |
| `GLT_20260708_TPS42_ORDER_OUTBOX_RAW_JSON_10K_R1` | Order outbox raw JSON send | `1998.99` | `396.71` | `485.46` | `25.21` | Rejected. |

Evidence:

- Order outbox publish enqueue got worse, not better:
  - TPS41 class: about `13s` order outbox publish enqueue sum.
  - TPS42: `eap_order_outbox_publish_enqueue_duration_seconds_sum=18.18s`.
- Order outbox batch wall time also worsened:
  - TPS42: `eap_order_outbox_batch_duration_seconds_sum=19.91s`.
- TPS42 also had Match ingress noise:
  - `maxMatchEngineQueueReady=2070`, `maxMatchEngineQueueUnacked=700`.
  - That makes the full business TPS less clean as an Order-only comparison, but the local Order publish-enqueue timer still rejects the raw JSON hypothesis.

Conclusion:

- Do not switch Order outbox relay to raw JSON message publishing in this shape.
- The deserialize + `convertAndSend` path is not the main fixed-cost problem for Order return markers on this local setup.
- The next Order fixed-cost target should be the DB-side apply model:
  - reducing many small batch fragments in `TradeExecuted` listener;
  - reducing `hasExistingTradeApplications(...)` precheck/fallback cost;
  - or combining trade application insert, matching-state update, and outbox insert into a single set-based SQL statement for the batch path.

### TPS-43: Rejected Order Trade Consumer Concurrency 8

Hypothesis:

- Order `TradeExecuted` apply cost is partly per-batch fixed cost:
  - lock matching states;
  - precheck existing trade applications;
  - insert trade application rows;
  - update matching states;
  - insert return-marker outbox rows.
- With `trade-executed.concurrency=12`, 10k runs often split into many small batches.
- Reducing consumer concurrency to `8` might make batches fuller and reduce DB round-trips without increasing `receive-timeout-ms`.

Experiment:

- Temporarily changed loadtest profile:
  - `eap.order.listeners.trade-executed.concurrency=12` -> `8`
  - kept `batch-size=50`
  - kept `receive-timeout-ms=25`
- Ran `GLT_20260708_TPS43_ORDER_TRADE_CONCURRENCY8_10K_R1`.
- Reverted concurrency to `12` after the run because full business TPS did not improve.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS41_MATCH_MARKER_METRICS_TIMEOUT25_10K_R2` | previous valid sample | `1999.31` | `502.25` | `674.14` | `19.91` | Baseline for this comparison. |
| `GLT_20260708_TPS43_ORDER_TRADE_CONCURRENCY8_10K_R1` | Order trade consumer concurrency `8` | `1998.32` | `458.52` | `703.19` | `21.81` | Rejected for full business TPS. |

Useful evidence:

- Local Order apply fixed cost improved:
  - `eap_order_trade_batch_total`: `1333` -> `841`.
  - `batch_total` sum: `7.22s` -> `5.34s`.
  - `batch_lock_heads` sum: `1.30s` -> `0.95s`.
  - fallback singleton events: `175` -> `49`.
- Order outbox relay also looked slightly better:
  - publish enqueue sum: `12.83s` -> `12.08s`.
  - batch wall time: `14.03s` -> `13.19s`.
- But full E2E got worse:
  - `businessMatchedE2eTps`: `502.25` -> `458.52`.
  - `businessCompletionSeconds`: `19.91s` -> `21.81s`.

Conclusion:

- Lowering Order trade consumer concurrency is not a standalone win.
- It confirms that batch fragmentation is a real fixed-cost driver, but simply reducing concurrency trades away too much parallelism.
- Next work should preserve concurrency while reducing per-batch DB round trips, most likely by replacing the current batch path's multiple statements with one set-based SQL operation:
  - lock/load states for all batch orders;
  - insert non-duplicate trade applications;
  - update matching state rows;
  - insert return-marker outbox rows;
  - return counts for validation.

### TPS-44 to TPS-46: Order Batch Fixed DB Round-Trip Reduction

Hypothesis:

- Order `TradeExecuted` batch hot path had real per-batch fixed DB cost.
- The old batch path did:
  - lock/load `order_matching_state`;
  - preselect `order_trade_applications` for duplicate trade ids;
  - JDBC batch insert `order_trade_applications`;
  - JDBC batch update `order_matching_state`;
  - JDBC batch insert `order_event_outbox`.
- A safer optimization is to keep listener concurrency at `12`, but collapse duplicate detection, application insert, matching-state update, and return-marker outbox insert into one set-based CTE per non-overlapping batch.

Implementation:

- Replaced the batch append section with `insertTradeApplicationsMatchingStatesAndOutboxes(...)`.
- The CTE:
  - builds a batch `input` relation;
  - counts existing trade applications first;
  - inserts all trade applications only when no existing trade id is present;
  - updates buyer and seller `order_matching_state` rows from the same inserted trade set;
  - inserts one return-marker outbox row per trade;
  - returns counts so Java can fail fast on partial writes.
- Removed the previous `hasExistingTradeApplications(...)` preselect from the batch path after the CTE duplicate guard was in place.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS41_MATCH_MARKER_METRICS_TIMEOUT25_10K_R2` | previous valid sample | `1999.31` | `502.25` | `674.14` | `19.91` | Baseline for this comparison. |
| `GLT_20260708_TPS44_ORDER_BATCH_CTE_10K_R1` | batch CTE, old preselect still present | `1999.11` | `463.13` | `593.32` | `21.59` | Local append improved, but full run regressed. |
| `GLT_20260708_TPS45_ORDER_BATCH_CTE_NO_PRESELECT_10K_R1` | batch CTE + no preselect | `535.64` | `383.57` | `475.39` | `26.07` | Invalid: publisher only reached `535 TPS`. |
| `GLT_20260708_TPS46_ORDER_BATCH_CTE_NO_PRESELECT_10K_R2` | batch CTE + no preselect | `1998.71` | `547.45` | `762.91` | `18.27` | Valid candidate. |

TPS46 evidence:

- Order apply fixed cost improved versus TPS41:
  - `eap_order_trade_batch_total`: `1333` -> `1152`.
  - `batch_append` sum: `7.22s` -> `3.28s`.
  - `batch_lock_heads` sum: `1.30s` -> `1.19s`.
  - `batch_total` sum: `7.22s` -> `5.58s`.
  - singleton fallback events: `175` -> `96`.
- Order outbox relay also improved versus TPS41/TPS44:
  - publish enqueue sum: `12.83s` -> `11.10s`.
  - outbox batch wall time: `14.03s` -> `12.04s`.
- Business gate improved:
  - `businessMatchedE2eTps`: `502.25` -> `547.45`.
  - `businessCompletionSeconds`: `19.91s` -> `18.27s`.
  - `completionMarkerReachTps`: `674.14` -> `762.91`.

Conclusion:

- Keep the Order batch CTE/no-preselect change as a candidate.
- TPS46 supports the fixed-cost hypothesis: preserving concurrency while reducing batch DB round trips is better than lowering consumer concurrency.
- The remaining large costs are no longer just Order append:
  - Wallet settlement CTE still spent about `1476ms` total for `10000` settlements in TPS46.
  - Match inserts still spent about `1009ms` on `trade_executions`, `855ms` on `trade_outbox`, and `837ms` on completion markers.
  - Outbox relay select/update/publish work remains visible across services.

### TPS-47: Rejected Match Recorder Combined CTE

Hypothesis:

- MatchEngine trade recording still does two JDBC write statements per trade:
  - `trade_executions` insert;
  - `trade_outbox` insert.
- Combining both into one CTE might reduce one client/server round trip per trade and improve the Match front-half.

Experiment:

- Temporarily changed `JpaTradeExecutionRecorder.record(...)` to one CTE:
  - insert `trade_executions`;
  - insert `trade_outbox` only when `trade_executions` inserted;
  - return inserted counts for the same duplicate/outbox conflict checks.
- Ran focused unit tests successfully.
- Ran `GLT_20260708_TPS47_MATCH_RECORDER_CTE_10K_R1`.
- Reverted the code because the run regressed.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `tradeExecutionReachTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS46_ORDER_BATCH_CTE_NO_PRESELECT_10K_R2` | Order batch CTE candidate | `1998.71` | `547.45` | `1150.05` | `762.91` | `18.27` | Baseline for this comparison. |
| `GLT_20260708_TPS47_MATCH_RECORDER_CTE_10K_R1` | Match recorder combined CTE | `1994.89` | `492.47` | `951.37` | `661.91` | `20.31` | Rejected. |

Evidence:

- Match DB write cost got worse:
  - TPS46 separate statements:
    - `trade_executions` insert total: about `1009ms`.
    - `trade_outbox` insert total: about `855ms`.
    - combined: about `1864ms`.
  - TPS47 combined CTE:
    - `WITH inserted_trade ... inserted_outbox ...`: `2210ms`.
- Match front-half got slower:
  - `tradeExecutionsReachedSeconds`: `8.70s` -> `10.51s`.
  - `tradeExecutionReachTps`: `1150.05` -> `951.37`.
- Business gate regressed:
  - `businessMatchedE2eTps`: `547.45` -> `492.47`.
  - `businessCompletionSeconds`: `18.27s` -> `20.31s`.

Conclusion:

- Do not combine Match `trade_executions` and `trade_outbox` inserts into this CTE shape.
- The extra SQL complexity/planner/write cost outweighed the saved JDBC round trip.
- Keep the existing Match recorder split inserts for now.
- Next better target is not this recorder CTE. Inspect either:
  - batch insertion of completion markers;
  - outbox relay select/update/publish costs;
  - Wallet settlement write cost and wallet outbox relay.

### TPS-48: Rejected Wallet Outbox Chunked Parallel Publish

Hypothesis:

- Wallet settlement SQL is already one CTE, so the next visible fixed cost might be the wallet outbox relay.
- TPS46 wallet outbox relay had `publish-concurrency: 1`; publishing `WalletTradeSettledEvent` back to MatchEngine was serial.
- Changing the relay to chunked parallel publish with `RabbitTemplate.invoke(...)` and `publish-concurrency: 8` might reduce wall-clock outbox relay time.

Experiment:

- Temporarily changed `OutboxPoller.publishBatch(...)` to partition each pending batch into up to eight chunks.
- Each chunk published through `RabbitTemplate.invoke(...)` on a worker thread.
- Set wallet loadtest `eap.wallet.outbox-relay.publish-concurrency: 8`.
- Ran focused wallet tests successfully.
- Ran `GLT_20260708_TPS48_WALLET_OUTBOX_CHUNKED_PUBLISH8_10K_R1`.
- Reverted the code and loadtest config because the run regressed.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `tradeExecutionReachTps` | `walletSettlementReachTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS46_ORDER_BATCH_CTE_NO_PRESELECT_10K_R2` | Order batch CTE candidate | `1998.71` | `547.45` | `1150.05` | `917.20` | `762.91` | `18.27` | Baseline for this comparison. |
| `GLT_20260708_TPS48_WALLET_OUTBOX_CHUNKED_PUBLISH8_10K_R1` | Wallet chunked parallel publish 8 | `1998.74` | `516.98` | `946.26` | `760.59` | `657.55` | `19.34` | Rejected. |

Evidence:

- Wallet outbox batch wall time improved locally:
  - `eap_wallet_outbox_batch_duration_seconds_sum`: `12.32s` -> `10.28s`.
- But publisher confirm cost got much worse:
  - `eap_wallet_outbox_confirm_duration_seconds_sum`: `0.64s` -> `9.39s`.
  - max confirm latency: `0.077s` -> `0.359s`.
- Wallet settlement did not improve:
  - app transaction timer sum: `15.94s` -> `16.66s`.
  - DB CTE total time: `1476ms` -> `1847ms`.
- The front half also got slower:
  - `tradeExecutionsReachedSeconds`: `8.70s` -> `10.57s`.
  - `tradeExecutionReachTps`: `1150.05` -> `946.26`.

Conclusion:

- Do not keep wallet chunked parallel publish with concurrency 8.
- In this local RabbitMQ publisher-confirm setup, extra publish parallelism reduced one local wall timer but increased confirm wait and overall interference.
- Wallet outbox serial publish is not the next confirmed bottleneck fix.
- Next better targets:
  - reduce durable outbox marker write/index cost across services;
  - review completion marker batching in MatchEngine;
  - review Wallet `trade_settlements`/outbox schema write amplification, especially redundant surrogate keys or indexes for append-only idempotency tables.

### TPS-49 to TPS-50: Match Trade Execution Unused Order Index Cleanup

Hypothesis:

- `trade_executions` maintained two secondary indexes that were not used by the current runtime query path:
  - `idx_trade_executions_buyer_order`;
  - `idx_trade_executions_seller_order`.
- Removing them should reduce per-trade B-tree write amplification.

Implementation:

- Added `match-trade-009` to drop both indexes.
- Kept all uniqueness constraints:
  - `trade_id` for idempotency and `ON CONFLICT (trade_id)`;
  - `(market_id, sequence)` for market sequencing uniqueness;
  - `legacy_match_id` for legacy match identity.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `tradeExecutionReachTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS46_ORDER_BATCH_CTE_NO_PRESELECT_10K_R2` | before index cleanup | `1998.71` | `547.45` | `1150.05` | `762.91` | `18.27` | Baseline for this comparison. |
| `GLT_20260708_TPS49_MATCH_DROP_UNUSED_TRADE_ORDER_INDEXES_10K_R1` | drop buyer/seller order indexes | `1999.35` | `486.93` | `1087.47` | `727.46` | `20.54` | Indexes removed, no E2E win. |
| `GLT_20260708_TPS50_MATCH_DROP_UNUSED_TRADE_ORDER_INDEXES_10K_R2` | same change, second run | `1999.08` | `371.33` | `734.87` | `554.40` | `26.93` | Noisy/slow run with Match queue backlog. |

Evidence:

- The indexes were not used in TPS46/TPS48 and disappeared after the migration:
  - before: both buyer/seller order indexes had `idx_scan = 0`;
  - after: both indexes were absent from `pg_stat_user_indexes`.
- `trade_executions` insert DB time did not produce a reliable win:
  - TPS46: about `1009ms`;
  - TPS49: about `1005ms`;
  - TPS50: about `1606ms`.
- The major slowdown in TPS49/TPS50 came from Match outbox relay/confirm rather than this index path:
  - TPS46 `trade_outbox_batch_duration_seconds_sum`: `10.81s`;
  - TPS49: `11.39s`;
  - TPS50: `15.66s`;
  - TPS46 `trade_outbox_confirm_duration_seconds_sum`: `9.92s`;
  - TPS49: `10.43s`;
  - TPS50: `14.42s`.

Conclusion:

- Dropping these two indexes is a reasonable cleanup because they are not tied to current reads.
- It is not a proven TPS fix; do not count it as resolving the main write amplification.
- The next primary target should be Match `trade_outbox` relay/confirm and mark-sent cost, because it dominates the slow runs more consistently than `trade_executions` index maintenance.

### TPS-51 to TPS-52: Match Trade Outbox Publish Concurrency Tuning

Hypothesis:

- Match `trade_outbox` relay was the most consistent slowdown in TPS49/TPS50.
- The relay already used chunked parallel publish with `RabbitTemplate.invoke(...)`.
- `publish-concurrency: 8` may have been too aggressive for the local RabbitMQ publisher-confirm setup, increasing channel/confirm contention instead of improving end-to-end drain.

Experiment:

- Changed Match loadtest `eap.match-engine.trade-outbox-relay.publish-concurrency` from `8` to `4`.
- Ran `GLT_20260708_TPS51_MATCH_OUTBOX_PUBLISH_CONCURRENCY4_10K_R1`.
- Then changed the same setting from `4` to `2`.
- Ran `GLT_20260708_TPS52_MATCH_OUTBOX_PUBLISH_CONCURRENCY2_10K_R1`.
- Restored the setting to `4` after TPS52 because `2` regressed.

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `tradeExecutionReachTps` | `walletSettlementReachTps` | `completionMarkerReachTps` | `businessCompletionSeconds` | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS49_MATCH_DROP_UNUSED_TRADE_ORDER_INDEXES_10K_R1` | publish concurrency 8 | `1999.35` | `486.93` | `1087.47` | `862.84` | `727.46` | `20.54` | Previous comparable run after index cleanup. |
| `GLT_20260708_TPS50_MATCH_DROP_UNUSED_TRADE_ORDER_INDEXES_10K_R2` | publish concurrency 8 | `1999.08` | `371.33` | `734.87` | `630.89` | `554.40` | `26.93` | Slow/noisy run with Match queue backlog. |
| `GLT_20260708_TPS51_MATCH_OUTBOX_PUBLISH_CONCURRENCY4_10K_R1` | publish concurrency 4 | `1997.58` | `574.13` | `987.42` | `799.25` | `679.21` | `17.42` | Best business completion in this sequence. |
| `GLT_20260708_TPS52_MATCH_OUTBOX_PUBLISH_CONCURRENCY2_10K_R1` | publish concurrency 2 | `1999.02` | `520.88` | `752.41` | `637.37` | `561.44` | `19.20` | Rejected: under-parallelized Match relay. |

Evidence:

- TPS51 improved the business gate versus TPS49/TPS50:
  - `businessMatchedE2eTps`: `486.93` / `371.33` -> `574.13`.
  - `businessCompletionSeconds`: `20.54s` / `26.93s` -> `17.42s`.
  - `maxMatchEngineQueueReady`: TPS51 stayed at `0`, while TPS50 hit `1579`.
- TPS51 did not prove that every Match relay local timer got faster:
  - TPS49 `trade_outbox_batch_duration_seconds_sum`: `11.39s`;
  - TPS51: `12.03s`;
  - TPS49 `trade_outbox_confirm_duration_seconds_sum`: `10.43s`;
  - TPS51: `11.16s`.
- TPS52 showed that `2` is too low:
  - business TPS fell from TPS51 `574.13` to `520.88`;
  - completion marker reach TPS fell from `679.21` to `561.44`;
  - Match queue ready peak returned to `500`;
  - `trade_outbox_batch_duration_seconds_sum` worsened from `12.03s` to `15.00s`;
  - `trade_outbox_confirm_duration_seconds_sum` worsened from `11.16s` to `14.06s`.

Conclusion:

- Keep Match loadtest `trade-outbox-relay.publish-concurrency: 4` as the current candidate.
- The useful range is not "more publish threads is always better":
  - `8` was unstable in TPS49/TPS50;
  - `2` underfed the relay and increased backlog;
  - `4` currently gives the best end-to-end business completion among these runs.
- This is a tuning win, not the final write-amplification fix. The remaining fixed write costs are still visible:
  - Match inserts per trade: `trade_executions`, `trade_outbox`, and two completion markers;
  - durable outbox status updates after publish;
  - Wallet settlement CTE plus wallet outbox publish enqueue time;
  - Order trade apply batch fixed cost when batches fragment.
- Next work should focus on reducing durable marker/outbox write count or replacing per-trade completion marker writes with a cheaper aggregate completion model, while preserving the current business gate semantics.

### TPS-53: Match Completion Marker and Outbox SQL Write Amplification

Open TPS-53 as the next SQL/write-model ticket.

Problem statement:

- TPS51/TPS52 confirmed that publisher concurrency tuning can change local drain behavior, but it does not solve the real bottleneck.
- The remaining core problem is fixed durable write cost per completed trade.
- Match currently pays multiple append/status writes for each trade:
  - one `trade_executions` insert;
  - one `trade_outbox` insert for `TradeExecuted`;
  - one `trade_outbox` status update after publish;
  - two `trade_completion_markers` inserts for `ORDER_APPLIED` and `WALLET_SETTLED`;
  - completion/reconciliation reads over `trade_executions` and markers.
- The business gate must still mean `TradeExecuted + ORDER_APPLIED marker + WALLET_SETTLED marker`; do not replace it with "published to Order/Wallet" only.

Scope:

- Inspect and optimize MatchEngine SQL/write model around:
  - `trade_completion_markers`;
  - `trade_outbox`;
  - completion gate queries;
  - indexes supporting marker insert/idempotency and completion reads.
- Prefer reducing row width, redundant indexes, duplicate SQL round trips, or marker write count where correctness allows.
- Keep service ownership intact: Order and Wallet still emit durable completion facts; MatchEngine owns completion aggregation.

Out of scope:

- Further tuning `publish-concurrency` as the main fix.
- Counting `TradeExecuted` publish alone as completed business TPS.
- Moving Order/Wallet state into MatchEngine.
- Removing idempotency without duplicate/redelivery tests.

Acceptance criteria:

| Task | Priority | Acceptance |
| --- | --- | --- |
| TPS-53-01 Inventory Match completion/outbox SQL and indexes | P0 | Document current row writes, unique indexes, non-unique indexes, and `pg_stat_statements` totals for TPS51/TPS52. |
| TPS-53-02 Propose SQL/write-model reduction options | P0 | Compare at least two options: keep append-only markers but slim indexes/SQL, versus derived aggregate completion state with fewer hot writes. |
| TPS-53-03 Implement the smallest safe SQL/schema change | P0 | Change is migration-backed, preserves duplicate-safe marker handling, and keeps business gate semantics unchanged. |
| TPS-53-04 Add/adjust focused tests | P0 | Duplicate and out-of-order Order/Wallet marker tests still pass; completion count remains correct. |
| TPS-53-05 Run 10k deep comparison | P0 | Compare against TPS51 as the current best local candidate and TPS46 as earlier high-water reference. |

Metrics to compare:

- `businessMatchedE2eTps`
- `businessCompletionSeconds`
- `completionMarkerReachTps`
- `trade_outbox` insert total time
- `trade_outbox` status update total time
- `trade_completion_markers` insert total time
- completion gate query total time
- `trade_completion_markers` table/index write stats
- final queue/DLQ correctness

Success bar:

- Primary: reduce Match completion/outbox SQL total time without weakening completion semantics.
- Secondary: improve or at least not regress `businessMatchedE2eTps` versus TPS51 beyond normal local noise.
- If local SQL improves but E2E TPS is noisy, keep the change only if deep diagnostics prove durable write cost was reduced and correctness remains intact.

### TPS-53 Implementation Pass 1: Completion Marker Batch SQL

Hypothesis:

- Match completion marker listeners were already using batch listeners, but the JDBC write used `JdbcTemplate.batchUpdate(...)`.
- TPS51 `pg_stat_statements` showed this still reached PostgreSQL as `20000` marker insert calls:
  - `INSERT INTO match_engine.trade_completion_markers ... ON CONFLICT ...`
  - `calls=20000`, `total_exec_ms=1187.94`, `rows=20000`.
- Keeping the same append-only marker table and idempotency PK, but sending each listener batch as one stable SQL statement, should reduce statement/round-trip overhead without weakening the business gate.

Implementation:

- Changed `TradeCompletionService.insertCompletionMarkers(...)` from per-row JDBC batch execution to one PostgreSQL array/`unnest` insert per listener batch:
  - `unnest(?::varchar[], ?::varchar[], ?::timestamp[])`;
  - `ON CONFLICT (trade_id, marker_type) DO NOTHING` remains unchanged.
- Kept single-event marker methods unchanged for non-batch callers.
- Added focused tests that execute the `ConnectionCallback` against mocked JDBC objects and verify:
  - stable `unnest` SQL shape;
  - `trade_id`, `marker_type`, and `marker_at` arrays are bound;
  - marker metrics still record batch/event counts.

Rejected intermediate:

- A dynamic multi-values version was tested in `GLT_20260713_TPS53_MARKER_MULTI_VALUES_10K_R1`.
- It reduced calls but generated many different SQL shapes by batch size, which made planning/statistics noisier.
- It is not kept; the final implementation uses the stable `unnest` SQL shape.

Verification:

| Check | Result |
| --- | --- |
| Focused tests | PASS: `TradeCompletionServiceTest`, `TradeCompletionReconcilerTest`, `JpaTradeExecutionRecorderTest`. |
| `GLT_20260713_TPS53_MARKER_MULTI_VALUES_10K_R1` | Correctness PASS, but dynamic SQL shape rejected. |
| `GLT_20260713_TPS53_MARKER_UNNEST_10K_R1` | Correctness PASS, final queues/DLQ `0`. |

Result:

| Run | Marker insert SQL | `businessMatchedE2eTps` | `completionMarkerReachTps` | Marker insert calls | Marker insert total time | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260708_TPS51_MATCH_OUTBOX_PUBLISH_CONCURRENCY4_10K_R1` | JDBC `batchUpdate`, PostgreSQL sees per-row insert | `574.13` | `679.21` | `20000` | `1187.94ms` | Best E2E reference. |
| `GLT_20260713_TPS53_MARKER_MULTI_VALUES_10K_R1` | dynamic multi-values | `503.89` | `725.44` | `2083` in top-file sum | `1000.82ms` in top-file sum | Rejected because SQL shape varies by batch size. |
| `GLT_20260713_TPS53_MARKER_UNNEST_10K_R1` | stable array `unnest` | `464.14` | `721.12` | `2314` | `970.28ms` | Kept as local SQL cleanup, not E2E fix. |

Conclusion:

- TPS-53 pass 1 reduces completion marker SQL statement count and total marker insert time:
  - calls: `20000` -> `2314`;
  - total marker insert time: `1187.94ms` -> `970.28ms`.
- It does not solve the E2E TPS bottleneck:
  - `businessMatchedE2eTps` regressed in this single run;
  - `completionMarkerReachTps` improved versus TPS51, so the local marker path did get cheaper;
  - end-to-end completion remains dominated by the broader Order/Wallet/outbox path and local run noise.
- Keep this as a small SQL cleanup because it preserves semantics and reduces marker SQL cost.
- Continue TPS-53 against higher-impact write amplification:
  - Match `trade_outbox` insert/status update and relay select payload cost;
  - Wallet settlement CTE and outbox publish enqueue;
  - Order trade apply write model when batches fragment.

### TPS-53 Implementation Pass 2: Trade Outbox Redundant Unique Constraint

Hypothesis:

- Match `trade_outbox` had a unique constraint on `(event_type, aggregate_id)`.
- The same transaction already inserts `trade_executions` first with `ON CONFLICT (trade_id) DO NOTHING`.
- For normal duplicate delivery, the `trade_executions.trade_id` gate exits before inserting outbox, so the outbox-level uniqueness is redundant on the hot path.

Implementation:

- Removed `ON CONFLICT (event_type, aggregate_id) DO NOTHING` from `JpaTradeExecutionRecorder` outbox insert.
- Added `match-trade-010` to drop `uk_trade_outbox_event_aggregate`.
- Preserved reliable outbox semantics:
  - `trade_executions` and `trade_outbox` are still committed in the same transaction;
  - duplicate trade handling still uses `trade_id`;
  - if outbox insert unexpectedly returns no row, the transaction fails.

Verification:

| Check | Result |
| --- | --- |
| Focused tests | PASS: `JpaTradeExecutionRecorderTest`, `TradeCompletionServiceTest`, `TradeOutboxRelayTest`. |
| `GLT_20260713_TPS53_OUTBOX_DROP_UNIQUE_10K_R1` | Correctness PASS, final queues/DLQ `0`. |
| Index check | `uk_trade_outbox_event_aggregate` absent from `pg_stat_user_indexes`. |

Result:

| Run | `actualBuyPublishTps` | `businessMatchedE2eTps` | `completionMarkerReachTps` | `trade_outbox` insert total | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `GLT_20260713_TPS53_MARKER_UNNEST_10K_R1` | not primary comparison | `464.14` | `721.12` | `860.76ms` | Before dropping outbox unique. |
| `GLT_20260713_TPS53_OUTBOX_DROP_UNIQUE_10K_R1` | `642.23` | `387.58` | `550.04` | `802.17ms` | Driver publish was slow, so E2E is not comparable as a regression signal. |

Conclusion:

- The outbox unique removal is a correct local write-amplification cleanup.
- It only saved about `58ms` over `10000` outbox inserts in this run, so it is not a main TPS fix.
- Keep it because the idempotency gate is still `trade_executions.trade_id`, and the removed index is not needed by the normal runtime path.
- Do not over-interpret the single-run E2E regression because `actualBuyPublishTps` was only `642.23`.

### TPS-53 Implementation Pass 3: Trade Execution `trade_id` Primary Key

Hypothesis:

- `trade_executions` is the canonical trade fact, but the runtime path identifies it by `trade_id`.
- The table still had both:
  - surrogate `id` primary key;
  - unique `trade_id` for idempotency and completion joins.
- Since no runtime code reads `trade_executions` by `id`, the surrogate primary-key index is redundant write amplification.

Implementation:

- Added `match-trade-011`:
  - drop `uk_trade_executions_trade_id`;
  - drop the old `trade_executions_pkey`;
  - add `trade_executions_pkey` on `trade_id`;
  - drop the unused `id` column.
- Updated JPA mapping:
  - `TradeExecutionEntity.tradeId` is now `@Id`;
  - `TradeExecutionRepository` now uses `String` id type.
- Kept the other uniqueness constraints for now:
  - `(market_id, sequence)`;
  - `legacy_match_id`.
- Those two constraints may still be business identity protection, so do not remove them without an architecture decision.

Verification:

| Check | Result |
| --- | --- |
| Focused tests | PASS: `JpaTradeExecutionRecorderTest`, `TradeCompletionServiceTest`, `TradeOutboxRelayTest`. |
| `GLT_20260713_TPS53_TRADE_ID_PK_10K_R1` | Correctness PASS, final queues/DLQ `0`. |
| Index check | `trade_executions` now has `trade_executions_pkey`, `uk_trade_executions_legacy_match_id`, and `uk_trade_executions_market_sequence`; `uk_trade_executions_trade_id` is gone. |

Result:

| Run | `actualBuyPublishTps` | `businessMatchedE2eTps` | `tradeExecutionReachTps` | `completionMarkerReachTps` | `trade_executions` insert total | `trade_outbox` insert total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `GLT_20260713_TPS53_OUTBOX_DROP_UNIQUE_10K_R1` | `642.23` | `387.58` | `622.95` | `550.04` | `1015.71ms` | `802.17ms` |
| `GLT_20260713_TPS53_TRADE_ID_PK_10K_R1` | `1999.36` | `384.15` | `969.86` | `563.35` | `820.40ms` | `546.88ms` |

Additional diagnostics from `GLT_20260713_TPS53_TRADE_ID_PK_10K_R1`:

| Area | Metric | Value |
| --- | --- | ---: |
| Match | `trade_completion_markers` insert total | `1013.77ms` |
| Match | `trade_outbox_batch_duration_seconds_sum` | `15.10s` |
| Match | `trade_outbox_confirm_duration_seconds_sum` | `14.15s` |
| Order | `eap_order_trade_apply_duration_seconds_sum{phase="batch_total"}` | `8.37s` |
| Order | `eap_order_outbox_batch_duration_seconds_sum` | `16.73s` |
| Wallet | settlement CTE SQL total | `1665.92ms` |
| Wallet | `eap_wallet_trade_settlement_transaction_duration_seconds_sum` | `19.59s` |
| Wallet | `eap_wallet_outbox_batch_duration_seconds_sum` | `16.88s` |

Conclusion:

- This pass is a real Match local write improvement:
  - `trade_executions` insert total improved from `1015.71ms` to `820.40ms`;
  - Match front-half reach improved from `622.95` to `969.86` TPS, though the previous run had a weak publisher and is not a clean E2E baseline.
- It still does not solve business E2E TPS:
  - Order and Wallet completion reach stayed around `643.93` TPS;
  - completed-trade marker reach was `563.35` TPS;
  - durable outbox/marker completion flow is now the more important amplification layer than Match trade fact insertion.
- Keep this change because it removes a redundant index/write without weakening the accepted `trade_id` idempotency semantics.
- Next target should not be more Match `trade_executions` micro-optimization. The next ticket should evaluate reliable outbox completion amplification across Order, Wallet, and Match:
  - per-service outbox publish/confirm/mark-sent fixed cost;
  - whether Order/Wallet completion marker events need one durable outbox row per trade;
  - whether marker aggregation can be batched or compacted while preserving `TradeExecuted + ORDER_APPLIED + WALLET_SETTLED` business gate semantics.

### TPS-54 Implementation Pass 1: Wallet Outbox Relay JDBC Projection

Hypothesis:

- The Wallet settlement path had already moved the settlement write itself to explicit SQL, but the Wallet outbox relay still used Spring Data JPA to load pending outbox entities.
- In TPS53, Wallet outbox select was a visible fixed cost:
  - `select oe1_0.id, oe1_0.attempt_count, ... payload ... from wallet_service.outbox ...`
  - `298 calls`, `384.24ms`, `10000 rows`.
- Order relay already uses a lightweight JDBC projection for outbox rows. Matching that pattern in Wallet should reduce relay select/entity materialization overhead without changing reliable outbox semantics.

Implementation:

- Changed `OutboxPoller` pending selection from Spring Data repository entity loading to `JdbcTemplate.query(...)` with a small `OutboxRow` projection:
  - `id`;
  - `event_type`;
  - `routing_key`;
  - `payload`;
  - `attempt_count`.
- Changed Wallet outbox `mark SENT` and failure retry updates to `NamedParameterJdbcTemplate`.
- Kept `OutboxRepository` for gauges, admin/recovery queries, and cleanup.
- Preserved the existing relay semantics:
  - publish first;
  - wait for publisher confirm;
  - only then mark rows `SENT`;
  - nack/timeout increments attempts and schedules retry or marks `FAILED`.
- Added a `status = 'PENDING'` guard to failure updates so a row that was already marked `SENT` by a partial mark-sent operation cannot be moved back to retry state.

Verification:

| Check | Result |
| --- | --- |
| Focused tests | PASS: `OutboxPollerTest`, `TradeExecutedListenerTest`. |
| `GLT_20260713_TPS54_WALLET_OUTBOX_JDBC_10K_R1` | Correctness PASS, final queues/DLQ `0`. |

Result:

| Run | Change | `actualBuyPublishTps` | `businessMatchedE2eTps` | `walletSettlementReachTps` | `completionMarkerReachTps` | Wallet outbox select SQL | Wallet outbox batch sum |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `GLT_20260713_TPS53_TRADE_ID_PK_10K_R1` | Wallet relay still JPA entity select | `1999.36` | `384.15` | `643.93` | `563.35` | `384.24ms` | `16.88s` |
| `GLT_20260713_TPS54_WALLET_OUTBOX_JDBC_10K_R1` | Wallet relay JDBC projection/update | `1998.55` | `468.76` | `788.84` | `631.70` | `59.77ms` | `14.49s` |

Additional metrics:

| Metric | TPS53 | TPS54 |
| --- | ---: | ---: |
| Wallet settlement CTE SQL total | `1665.92ms` | `1536.98ms` |
| `eap_wallet_trade_settlement_transaction_duration_seconds_sum` | `19.59s` | `15.75s` |
| `eap_wallet_outbox_publish_enqueue_duration_seconds_sum` | `15.73s` | `13.27s` |
| Wallet outbox mark-sent SQL total | `59.48ms` | `192.52ms` |

Conclusion:

- Keep the Wallet outbox JDBC projection change.
- The strongest evidence is the outbox select path:
  - SQL total dropped from `384.24ms` to `59.77ms`;
  - this removes JPA entity materialization from a 10k-row relay hot path.
- E2E improved in this comparable run:
  - `businessMatchedE2eTps`: `384.15` -> `468.76`;
  - `walletSettlementReachTps`: `643.93` -> `788.84`;
  - `completionMarkerReachTps`: `563.35` -> `631.70`.
- Caveat: mark-sent SQL total was higher in this single run, while the app timer remained close (`0.211s` -> `0.225s`). Treat mark-sent as not yet improved.
- Next targets:
  - apply the same scrutiny to Match outbox relay, which still shows JPA entity select cost;
  - evaluate whether outbox relay select/update SQL should be stabilized further to reduce dynamic `IN (...)` statement shapes;
  - keep completion semantics unchanged until a separate design ticket explicitly changes the marker model.

### TPS-55 Public Benchmark Reproducibility

Goal:

- Stop treating a single strong local run as the public result.
- Build a pinned, repeatable benchmark release process that can be cited from README and resume.
- Preserve the honest distinction between offered order confirmations/s and completed business trades/s.

Scope:

| Task | Priority | Acceptance |
| --- | --- | --- |
| TPS-55-01 Pin loadtest container images | P0 | `docker-compose.loadtest.yml` uses image digests for PostgreSQL, RabbitMQ, and Redis. |
| TPS-55-02 Add public benchmark runbook | P0 | `docs/benchmarks/2026-07-public-benchmark.md` defines workload, timing formula, validity rules, environment, and publication criteria. |
| TPS-55-03 Add official 10k repeat wrapper | P0 | `scripts/load-test/run-public-benchmark-10k-repeat.sh` runs the existing 10k repeat flow with `REPEATS>=5`, baseline/light diagnostics, and explicit offered-load threshold. |
| TPS-55-04 Improve repeat summary | P0 | Repeat summary reports median, valid/invalid runs, invalid reasons, artifact paths, all-run stats, and valid-runs-only stats. |
| TPS-55-05 Add benchmark snapshot capture | P0 | `scripts/load-test/collect-benchmark-snapshot.sh` records infra/order/wallet/matchEngine/common commits, dirty status, and pinned image digests. |
| TPS-55-06 Run five official 10k repeats | P1 | Produce `matched-e2e-repeat-EAP_PUBLIC_10K_...-summary.json`; publish median/min/max only after invalid run rules are applied. |
| TPS-55-07 Commit/push exact benchmark snapshot | P1 | README can link to an exact commit and result artifacts. |

Validity rules for public summary:

- `actualBuyPublishTps >= TARGET_TPS * MIN_OFFERED_TPS_RATIO`;
- `buyPublishFailures == 0`;
- `sellPublishFailures == 0`;
- `completedTrades == EVENTS`;
- `tradeExecutions == EVENTS`;
- `walletTradeSettlements == EVENTS`;
- `orderCommandMatchedRows == EVENTS * 2`;
- final measured ready/unacked queue backlog is zero.

Current implementation status:

- Done: digest-pinned loadtest compose for local image set.
- Done: public benchmark runbook.
- Done: official 10k repeat wrapper.
- Done: repeat summary now includes median and validity classification.
- Done: snapshot script records multi-repo dirty state and pinned image digests.
- Done: five official repeats on benchmark infra commit `2252e54738d10683894b965c93d93bff32fd8c08`.

2026-07-13 official repeat result:

- Run prefix: `EAP_PUBLIC_10K_20260713`.
- Valid public samples: `4/5`.
- Invalid sample: `R3`, reason `driver_offered_tps_below_threshold` (`actualBuyPublishTps=733.79`).
- Valid offered load median/range: `1998.94`, range `1998.54-1999.13` order confirmations/s.
- Valid business matched E2E median/range: `582.73`, range `503.11-662.17` completed trades/s.
- Valid business completion window median/range: `17.29s`, range `15.10-19.88s`.
- Valid completion marker reach median/range: `745.60`, range `701.99-803.90` markers/s.
- Final correctness: each valid run reached `10000` completed trades, `10000` trade executions, `10000` wallet settlements, `20000` Order command matched rows, zero remaining orders, and final measured queue backlog `0`.

Interpretation:

- TPS-55 changed the public claim from a single 10k result (`468.76` completed trades/s) to a repeat-based valid median (`582.73` completed trades/s).
- The excluded run is not a business correctness failure; it is a load-driver offered-throughput failure and is kept in the artifact bundle for transparency.
- This is still a short 10k burst-style benchmark, not a 10-15 minute steady-state result.

### TPS-56 Steady-State Benchmark

Goal:

- Add one steady-state result after TPS-55 so the README is not only a short 10k burst story.
- Prove whether queues stay bounded under a conservative completed-throughput target.

Initial plan:

| Task | Priority | Acceptance |
| --- | --- | --- |
| TPS-56-01 Choose conservative steady-state target | P0 | Start near current completed capacity; do not start with 2000 offered TPS as the public steady-state claim. |
| TPS-56-02 Run 10-15 minute steady-state | P0 | Capture completed business TPS, queue backlog over time, final drain, DLQ, and resource metrics. |
| TPS-56-03 Summarize backlog trend | P0 | Report whether backlog grows, shrinks, or stays bounded. |
| TPS-56-04 Update performance report | P1 | Add steady-state result or explicitly list it as remaining gap. |

Suggested first command:

```bash
TARGET_TPS=500 \
DURATION_SECONDS=900 \
EVENTS=450000 \
PUBLISHERS=128 \
TIMEOUT_SECONDS=1800 \
DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

Do not update the README headline with stronger claims until TPS-55 has a committed exact SHA and TPS-56 either has a completed result or remains clearly marked as a gap.

2026-07-13 execution result:

- Run ID: `EAP_STEADY_500TPS_15M_20260713_R1`.
- Snapshot: `build/load-test-reports/EAP_STEADY_500TPS_15M_20260713_R1-snapshot.json`.
- Run log: `build/load-test-reports/matched-e2e-two-phase-EAP_STEADY_500TPS_15M_20260713_R1-run.log`.
- Diagnostics: `build/load-test-reports/matched-e2e-two-phase-EAP_STEADY_500TPS_15M_20260713_R1-diagnostics/`.
- Benchmark infra commit captured before the run: `8346b346146ae885c60b718a9c6b614d73ba19a5`.
- Service commits: Order `5f7f6e18a0b07adfbfba9ec36a0275ea0232b40e`, Wallet `f5ac291670c98e939dcc6566dd77d8a99086ee0d`, MatchEngine `012a5c487e8a38417566e957cb9f7292a446d7c2`, Common `8cce7cd20e9a1f54b01feb31f41ff403688948c4`.

Result: **REJECTED_STEADY_STATE_CORRECTNESS**.

Key metrics:

- Target offered BUY rate: `500` order confirmations/s for `900s`.
- Published SELL confirmations: `450000`, failures `0`, publish seconds `58.52`.
- Published BUY confirmations: `450000`, failures `0`, publish seconds `900.00`, actual offered TPS `500.00`.
- Final elapsed/business window: `2700.66s` including post-publish drain wait.
- Reported business matched E2E TPS: `166.63`, but this is not an accepted steady-state claim because the correctness gate failed.
- Completed trades / trade executions / wallet settlements: `25379 / 450000`.
- Order command matched rows: `50758 / 900000`.
- Remaining Redis order book: `remainingSellOrders=0`, `remainingBuyOrders=424621`.
- Final measured queue ready/unacked backlog: `0`; DLQ `0`.
- Runtime sampler peak for `matchEngine.orderConfirmed.queue`: ready `183593`, unacked `182643`, total `1100`, consumers `12`.
- MatchEngine log contained `23930` warnings of `Order ... was not linked in user open orders`.

Interpretation:

- This run proves the load generator can maintain the conservative `500` offered BUY confirmations/s for `15` minutes without publish failures.
- It does **not** prove steady-state completed throughput. Only `25379` of `450000` intended matches reached TradeExecuted/Order/Wallet completion.
- Because final RabbitMQ queues drained to zero and DLQ stayed zero, the immediate failure shape is not a downstream Order/Wallet queue-drain bottleneck.
- The decisive correctness signal is `remainingSellOrders=0` with `remainingBuyOrders=424621`: most BUY orders were accepted into the MatchEngine input queue but did not find resting SELL liquidity.
- Root cause found after the run: the active Redis container was `eap-redis` with `maxmemory=200mb` and `maxmemory-policy=allkeys-lru`. `INFO stats` showed `evicted_keys=1284406`. Redis evicted `order:<id>` detail keys and `user:<id>:orders` set entries while leaving some order IDs in the orderbook ZSET. When a BUY tried to match, the Lua script removed a SELL ZSET member but `GET order:<id>` returned nil, so the Java path treated it as a normal no-match and added the BUY to the buy book.
- This explains the abnormal combination of `remainingSellOrders=0`, `remainingBuyOrders=424621`, `completedTrades=25379`, and thousands of `Order ... was not linked in user open orders` warnings.

Fixes applied:

- `scripts/load-test/assert-loadtest-environment.sh` now rejects Redis unless `maxmemory-policy=noeviction`, maxmemory is `0` or at least `1073741824` bytes, and `evicted_keys=0`.
- `scripts/load-test/collect-loadtest-diagnostics.sh` and `scripts/load-test/run-global-matched-e2e-two-phase.sh` now record Redis memory, policy, and eviction stats.
- MatchEngine matching Lua scripts now return a corruption sentinel when an orderbook ZSET entry points at a missing order detail key.
- `RedisOrderBookService` now throws on missing or unreadable matched order details instead of silently returning null.
- Development `docker-compose.yml` Redis now uses `noeviction`; loadtest Redis remains the required 1GB `noeviction` instance.

Follow-up ticket:

| Task | Priority | Acceptance |
| --- | --- | --- |
| TPS-57-01 Restart loadtest Redis cleanly | P0 | `docker compose -f docker-compose.loadtest.yml up -d redis`; `assert-loadtest-environment.sh` reports `noeviction`, sufficient maxmemory, and `evicted_keys=0`. |
| TPS-57-02 Run a small guard scenario | P0 | A 10k or 30k matched E2E run completes with zero remaining BUY/SELL orders and Redis `evicted_keys=0`. |
| TPS-57-03 Re-run TPS-56 after clean Redis | P0 | Accepted only when `completedTrades == EVENTS`, Order/Wallet completion counts match, remaining BUY/SELL orders are zero, queues/DLQ are zero, and Redis `evicted_keys=0`. |
| TPS-57-04 Add MatchEngine order-book accounting metrics | P1 | During future runs, capture per-side Redis ZSET sizes, add-order count, match count, and missing-detail count by market. |

2026-07-13 validation after Redis fix:

- Redis was recreated with `maxmemory=1073741824`, `maxmemory-policy=noeviction`, and then cleared with `FLUSHDB`.
- Environment gate passed after cleanup; Redis baseline `DBSIZE=0`, used memory about `1.49MB`.
- 10k guard run `GLT_20260713_REDIS_NOEVICT_GUARD_10K` passed:
  - `actualBuyPublishTps=1999.14`;
  - `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`;
  - `orderCommandMatchedRows=20000`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - final measured queues and DLQ `0`;
  - Redis `evicted_keys=0`, peak memory about `201.28MB`.

TPS-56 R2 result:

- Run ID: `EAP_STEADY_500TPS_15M_20260713_R2`.
- Snapshot: `build/load-test-reports/EAP_STEADY_500TPS_15M_20260713_R2-snapshot.json`.
- Result JSON: `build/load-test-reports/matched-e2e-two-phase-EAP_STEADY_500TPS_15M_20260713_R2-result.json`.
- Run log: `build/load-test-reports/matched-e2e-two-phase-EAP_STEADY_500TPS_15M_20260713_R2-run.log`.
- Diagnostics: `build/load-test-reports/matched-e2e-two-phase-EAP_STEADY_500TPS_15M_20260713_R2-diagnostics/`.
- Prepare timing: seed `24m33s`; projection prewarm `4m33s`; `openOrders=900000`.
- Offered BUY load: `450000` BUY confirmations in `913.34s`, actual offered TPS `492.70`, publish failures `0`.
- Business completion: `450000` completed trades in `934.74s`, `businessMatchedE2eTps=481.42`.
- Reach rates:
  - `tradeExecutionReachTps=492.33`;
  - `orderCommandMatchReachTps=486.16`;
  - `walletSettlementReachTps=487.01`;
  - `completionMarkerReachTps=484.09`.
- Correctness:
  - `tradeExecutions=450000`;
  - `completedTrades=450000`;
  - `walletTradeSettlements=450000`;
  - `orderCommandMatchedRows=900000`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - final measured queues and DLQ `0`;
  - Redis `evicted_keys=0`, peak memory about `270.77MB`.

Interpretation:

- The R1 failure was caused by Redis eviction, not by MatchEngine losing most resting liquidity under valid memory settings.
- On clean `noeviction` Redis, the same 450k scenario completes correctly with no remaining orderbook entries.
- The accepted steady-state claim should be worded as near-500 offered order confirmations/s and `481.42` fully gated completed trades/s, not exact 500 completed TPS.
- The next performance work should return to actual service throughput: Order/Wallet/MatchEngine completion rates are clustered around `484-492/s`, so the current sustained ceiling is around this range on the local environment.

Stability evidence from R2 sampler:

- Runtime sampler covered `102` samples from `2026-07-13T07:49:38Z` to `2026-07-13T08:08:12Z`.
- Completion ratio: `450000 / 450000` trades completed; no missing Order application or Wallet settlement.
- Publish reliability: SELL failures `0`, BUY failures `0`.
- Post-publish drain:
  - BUY publish ended at `913.34s`;
  - trade executions reached target at `914.02s`;
  - Wallet settlements reached target at `924.00s`;
  - completed-trade markers reached target at `929.57s`;
  - fully drained queues at `934.74s`;
  - extra full-drain time after BUY publish: `21.40s`.
- Redis stability:
  - `maxmemory-policy=noeviction`;
  - `evicted_keys=0` throughout the run;
  - peak used memory about `270.77MB` of `1GB` (`~26.5%`);
  - post-run used memory about `1.75MB`.
- RabbitMQ stability:
  - `order.dlq` stayed `0`;
  - final measured ready/unacked queues were all `0`;
  - `matchEngine.orderConfirmed.queue` peak total backlog was `215041` during the preload/run window and drained to `0`;
  - downstream peak unacked stayed bounded: `order.tradeExecuted.queue=262`, `wallet.tradeExecuted.queue=176`, `matchEngine.orderTradeApplied.queue=464`, `matchEngine.walletTradeSettled.queue=243`.
- Orderbook stability:
  - sampled mid-run SELL book decreased monotonically in spot checks (`424887 -> 384831 -> 323414 -> 246548 -> 170581 -> 103456 -> 36141`);
  - BUY book stayed `0` in spot checks;
  - final `remainingSellOrders=0`, `remainingBuyOrders=0`.

### TPS-58 Public Steady-State Evidence Hardening

Goal:

- Turn the clean TPS-56 R2 steady-state result into repeat-based public evidence.
- Verify the repaired load-test harness after the RabbitMQ metadata and failure-diagnostics fixes.
- Update the public performance documents with median/range instead of relying on a single steady-state sample.

Scope:

| Task | Priority | Acceptance |
| --- | --- | --- |
| TPS-58-01 Open evidence-hardening ticket | P0 | This ticket records the accepted scope: 10k guard, three steady-state repeats, report update, and commit. |
| TPS-58-02 Run repaired 10k guard | P0 | 10k matched E2E run completes with `completedTrades=EVENTS`, Order/Wallet counts aligned, queues/DLQ zero, remaining BUY/SELL zero, and Redis `evicted_keys=0`. |
| TPS-58-03 Run three steady-state repeats | P0 | Three near-500 offered-load 450k runs complete or are explicitly classified with reasons. Valid runs report median/range for offered TPS, business E2E TPS, completion window, drain time, and correctness counts. |
| TPS-58-04 Update public performance docs | P0 | `docs/performance-report.md` and `docs/benchmarks/2026-07-public-benchmark.md` describe the repeat steady-state result and updated wording. |
| TPS-58-05 Commit the evidence package | P1 | Commit includes load-test harness fix, missing-detail regression test, ticket/docs updates, and references local artifact paths. |

Run IDs:

- 10k guard: `GLT_20260714_TPS58_GUARD_10K`.
- Steady-state repeats: `EAP_STEADY_500TPS_15M_20260714_R1` through `R3`.

Notes:

- Do not strengthen the public claim to 500 completed TPS unless the measured median supports it.
- Keep wording as near-500 offered order confirmations/s plus measured fully gated completed trades/s.
- If a run fails, preserve after-run diagnostics and classify the failure before rerunning.

2026-07-14 execution result:

- 10k guard `GLT_20260714_TPS58_GUARD_10K` completed the correctness gate:
  - `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`;
  - final measured queues and DLQ `0`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - Redis `maxmemory-policy=noeviction`, `evicted_keys=0`;
  - offered BUY rate was only `521.47/s`, so this is a harness/correctness guard, not a public 2000 offered-load sample.
- Three 450k steady-state repeats were attempted:
  - valid samples: `2/3` (`R1`, `R2`);
  - invalid sample: `R3`, reason `steady_state_correctness_miss_19_trades`.

Valid steady-state samples:

| Run | Offered BUY TPS | Business E2E TPS | Completion Window | Drain After BUY | Correctness |
| --- | ---: | ---: | ---: | ---: | --- |
| `EAP_STEADY_500TPS_15M_20260714_R1` | `494.71` | `477.42` | `942.57s` | `32.95s` | `450000/450000`, final queues/DLQ `0`, Redis evictions `0` |
| `EAP_STEADY_500TPS_15M_20260714_R2` | `500.00` | `497.89` | `903.81s` | `3.81s` | `450000/450000`, final queues/DLQ `0`, Redis evictions `0` |

Valid-sample summary:

- Offered BUY TPS median/range: `497.36`, range `494.71-500.00`.
- Business matched E2E TPS median/range: `487.66`, range `477.42-497.89`.
- Completion window median/range: `923.19s`, range `903.81-942.57s`.
- Drain after BUY publish median/range: `18.38s`, range `3.81-32.95s`.

Rejected sample `EAP_STEADY_500TPS_15M_20260714_R3`:

- Offered BUY rate remained near target: `494.78/s`, publish failures `0`.
- Result failed the correctness gate:
  - `completedTrades=449981 / 450000`;
  - `tradeExecutions=449981 / 450000`;
  - `walletTradeSettlements=449981 / 450000`;
  - `orderCommandMatchedRows=899962 / 900000`;
  - `remainingSellOrders=0`, `remainingBuyOrders=19`;
  - `lockedCurrency=1900`, `lockedAmount=19`;
  - final measured queues and DLQ drained to `0`;
  - Redis stayed clean: `noeviction`, `evicted_keys=0`.
- The run log recorded one RabbitMQ client message: `Received a frame on an unknown channel, ignoring it`.
- The repaired two-phase harness preserved the result JSON, Redis/RabbitMQ metadata, after-run diagnostics, service shutdown, and final queue purge despite the failed Gradle task.

Interpretation:

- The clean Redis fix is holding: all TPS-58 runs had `evicted_keys=0`; the R3 failure is not the earlier Redis-eviction false-no-match failure.
- The two valid 2026-07-14 samples support a near-500 offered-load steady-state claim with completed throughput in the `477-498/s` range on the local environment.
- The invalid R3 sample prevents claiming three-run stable correctness. The next engineering task should investigate why 19 trades failed to complete despite broker queues draining and Redis eviction staying at zero.

2026-07-14 R3 follow-up investigation:

- The miss is upstream of Order and Wallet:
  - `tradeExecutions=449981`, `completedTrades=449981`, `walletTradeSettlements=449981`, and `orderCommandMatchedRows=899962`;
  - Order and Wallet are aligned with the number of trades MatchEngine actually produced.
- The 19 remaining BUY orders are real Redis orderbook entries with detail keys:
  - final Redis buy book size was `19`;
  - final Redis sell book size was `0`;
  - remaining BUY details showed valid `BUY`, `price=100`, `amount=1`, and market `EAP_STEADY_500TPS_15M_20260714_R3`.
- The remaining BUY order IDs did not appear as `buyer_order_id` in `match_engine.trade_executions`.
- Their original deterministic SELL partners were not missing; those SELL orders were matched with other BUYs. This is expected under price-time matching and confirms the load generator should not assume fixed pair matching.
- The actual missing SELL market sequences were:
  - `356560`, `356562`, `356564`, `356566`, `356568`, `356572`, `356576`, `356580`, `356584`, `356588`, `356592`, `356596`, `356600`, `356604`, `356608`, `356612`, `356616`, `356620`, `356624`.
- Those missing SELL orders were seeded and asset-confirmed in Order event store, but remained `OPEN` in `order_service.order_matching_state`.
- Those SELL order IDs did not appear in `trade_executions` in any market.
- Redis after-run state for those missing SELL orders:
  - `order:<sellOrderId>` detail keys were gone;
  - sell ZSET entries were gone;
  - `user:<sellerId>:orders` set entries remained.
- Nearby MatchEngine evidence:
  - `trade_executions.sequence` had one missing generated match sequence: `1538280`;
  - the surrounding trade rows were in the same seller-sequence window;
  - MatchEngine logged 13 `was not linked in user open orders` warnings in the same window, but those 13 orders were otherwise `MATCHED` and are not the correctness miss.

Current hypothesis:

- The R3 failure is not a load-generator under-publish, Order delay, Wallet delay, RabbitMQ backlog, DLQ, or Redis eviction issue.
- The likely fault boundary is MatchEngine's destructive Redis pop-before-durable-trade section:
  - `getAndRemoveBestMatchOrderLua(...)` removes the resting SELL from Redis before `tradeExecutionRecorder.record(...)` persists `TradeExecuted`;
  - if an exception, channel retry, shutdown edge, or local processing failure happens after the Redis pop but before durable trade persistence and cleanup, the resting SELL is lost from the orderbook and the incoming BUY can later retry against a different SELL;
  - after enough lost resting SELLs, later BUYs remain open even though all broker queues drain.

Next fix direction:

- Add a focused MatchEngine ticket for Redis orderbook transactional safety:
  - either compensate by re-adding the popped resting order if durable trade persistence fails before the trade fact is committed;
  - or introduce a safer reserve/finalize model so Redis removes a resting order from public matching only after durable trade persistence succeeds.
- Add regression coverage for a failure injected between `getAndRemoveBestMatchOrderLua(...)` and `tradeExecutionRecorder.record(...)`; expected behavior is no lost resting order and no unmatched residual order after retry.
- Add a diagnostic counter for `resting_order_popped`, `trade_recorded`, `resting_order_readded_after_failure`, and `user_order_unlink_miss` by market so future steady-state runs can attribute this class of miss without manual Redis forensics.

Implementation pass:

- `MatchingEngineService` now treats the Redis pop-to-durable-trade section as a compensation boundary.
- The incoming and resting order amounts are no longer mutated before `TradeExecuted` persistence succeeds.
- If match ID generation or durable trade persistence fails after a resting order has been popped from Redis, MatchEngine re-adds the popped resting order with its original amount before rethrowing the exception for RabbitMQ retry.
- Regression tests cover:
  - failure during `tradeExecutionRecorder.record(...)`;
  - failure during Redis `match:id:sequence` increment.
- Focused verification passed:
  - `./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest`.

2026-07-17 reservation/finalize correction:

- The 2026-07-14 compensation-only fix was not sufficient for long steady-state correctness:
  - a later 450k run still ended with missing trades and remaining BUY orders;
  - MatchEngine did re-add some popped resting orders, but the system could still lose a resting SELL if the order was popped again and failed in another uncovered window.
- MatchEngine now uses a Redis reservation model for the resting order:
  - `reserve_match_order_buy.lua` / `reserve_match_order_sell.lua` remove the resting order from the visible orderbook but keep the order detail and write `order:reservation:<orderId>`;
  - `TradeExecuted` is persisted after reservation;
  - on durable-trade failure, `release_reserved_order.lua` restores the original resting order amount to the visible orderbook and removes the reservation key;
  - on full match success, `complete_reserved_order.lua` deletes the order detail, user open-order link, and reservation key;
  - on partial match success, the remaining resting amount is released back to the visible orderbook.
- This makes the dangerous middle state explicit and inspectable. A resting order should no longer disappear from the visible orderbook without either:
  - a durable `TradeExecuted` fact; or
  - a visible `order:reservation:<orderId>` key that can be diagnosed/reconciled.
- Focused verification passed:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest`
- 10k guard `GLT_20260717_TPS56_RESERVATION_GUARD_10K` passed:
  - `sellPublished=10000`, `buyPublished=10000`, publish failures `0`;
  - `actualBuyPublishTps=1999.08`;
  - `tradeExecutions=10000`, `completedTrades=10000`, `walletTradeSettlements=10000`;
  - `orderCommandMatchedRows=20000`;
  - final measured queues and DLQ `0`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - `lockedCurrency=0`, `lockedAmount=0`;
  - Redis `order:reservation:*` count after the run was `0`.
- After removing the old destructive pop Lua entrypoints, smoke E2E `GLT_20260717_TPS56_RESERVATION_SMOKE_10` passed:
  - `tradeExecutions=10`, `completedTrades=10`, `walletTradeSettlements=10`;
  - final measured queues and DLQ `0`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - Redis `order:reservation:*` count after the run was `0`.
- Remaining validation before closing the correctness concern:
  - run at least one long 450k steady-state sample with the reservation model;
  - if any `order:reservation:*` key remains, classify it as known reserved state instead of silent order loss;
  - add reservation-count diagnostics to the load-test report so this does not require manual Redis scans.

2026-07-17 120k steady-state validation:

- Run ID: `EAP_STEADY_500TPS_4M_20260717_RESERVATION_R1`.
- Purpose:
  - validate the reservation/finalize model beyond the 10k guard;
  - avoid paying the full 450k / 15-minute steady-state cost on every implementation iteration.
- Scale:
  - `TARGET_TPS=500`;
  - `DURATION_SECONDS=240`;
  - `EVENTS=120000`;
  - `PUBLISHERS=128`;
  - diagnostics level `deep`.
- Setup cost observed on local machine:
  - seed phase: `6m14s`;
  - Order projection prewarm: `1m11s`;
  - this explains why 450k is expensive in practice: the run is not only the 15-minute publish window, but also 450k matched-pair seed data, projection prewarm, service restart, diagnostics, drain, and final cleanup.
- Result:
  - `sellPublished=120000`, `buyPublished=120000`, publish failures `0`;
  - `actualBuyPublishTps=499.96`;
  - `tradeExecutions=120000`;
  - `completedTrades=120000`;
  - `walletTradeSettlements=120000`;
  - `orderCommandMatchedRows=240000`;
  - `businessMatchedE2eTps=460.71`;
  - `tradeExecutionReachTps=497.91`;
  - `orderCommandMatchReachTps=492.45`;
  - `walletSettlementReachTps=492.45`;
  - `completionMarkerReachTps=472.23`;
  - `drainSecondsAfterBuyPublish=20.45`;
  - final measured queues and DLQ `0`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - `lockedCurrency=0`, `lockedAmount=0`;
  - Redis `evicted_keys=0`;
  - Redis `order:reservation:*` count after the run was `0`;
  - MatchEngine/Order/Wallet logs had no matched `ERROR`, reservation release failure, Redis orderbook inconsistency, unknown channel, or Hikari thread-starvation keyword.
- Interpretation:
  - This is a valid medium steady-state correctness sample for the reservation/finalize fix.
  - It does not replace a 450k / 15-minute formal evidence run because the earlier rare failure appeared only under longer exposure.
  - Use 120k as the default iteration gate after MatchEngine correctness changes; reserve 450k for nightly/formal release evidence.

2026-07-17 load-test seed optimization:

- Problem:
  - The matched steady-state benchmark was paying too much setup cost before the actual run.
  - The 120k / 500 TPS validation spent `6m14s` in seed before only `240s` of offered-load time.
  - The 450k formal run is therefore expensive not only because of the publish window, but because setup writes scale with matched pairs.
- Change:
  - `MatchedE2eLoadGenerator` now supports `--seed-mode=bulk` as the default load-test-only seed path.
  - The old service path is still available with `--seed-mode=service`.
  - Bulk seed writes the minimum service-owned Order state needed for the matched benchmark:
    - `order_service.order_event_store`;
    - `order_service.order_stream_heads`;
    - `order_service.order_matching_state`.
  - Wallet seed remains a direct batch load for benchmark fixture state.
  - Order outbox is still truncated after seed so seed events are not published into the live business path.
- Correctness guard:
  - Bulk seed creates two Order events per seeded order: `OrderSubmissionRequestedV1` and `OrderAssetReservationConfirmedV1`.
  - Event ids are deterministic per order and seed event type.
  - `payload_canonical`, `metadata_canonical`, `prev_hash`, and `hash` are written so projection/replay and event-chain checks remain meaningful.
  - R2 verification query for market `EAP_STEADY_2000TPS_120K_20260717_BULKSEED_R2` showed `240000` seeded event rows, `0` broken hash links, and `0` stream-head mismatches.
- Observed setup improvement:
  - Before: 120k seed via service path took `6m14s`.
  - After: 120k seed via bulk path took `32s`.
  - Projection prewarm remains about `1m11s-1m13s` for `240000` open orders.
- Boundary:
  - This is a benchmark fixture optimization, not a production write-path optimization.
  - Production order submission still goes through the Order service event-sourcing path.

2026-07-17 120k / 2000 offered-TPS validation after bulk seed:

- Purpose:
  - Answer whether the steady-state harness can be run with the same `2000 TPS` input target used by earlier entry-side tests.
  - Confirm the seed optimization does not hide lost trades or leave known reserved state behind.
- Shared settings:
  - `TARGET_TPS=2000`;
  - `DURATION_SECONDS=60`;
  - `EVENTS=120000`;
  - `PUBLISHERS=128`;
  - `RUN_MODE=prepare-run`;
  - diagnostics level `deep`;
  - `RESET_PG_STATS_BEFORE_RUN=true`;
  - default `--seed-mode=bulk`.

| Run | Actual buy publish TPS | Business completed TPS | TradeExecution reach TPS | Order match reach TPS | Wallet settlement reach TPS | Completion marker reach TPS | Drain after buy publish | Max match queue ready | Correctness |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `EAP_STEADY_2000TPS_120K_20260717_BULKSEED_R1` | `1397.11` | `490.54` | `588.65` | `510.97` | `510.97` | `496.41` | `158.74s` | `68826` | PASS |
| `EAP_STEADY_2000TPS_120K_20260717_BULKSEED_R2` | `1999.91` | `454.57` | `592.77` | `480.16` | `483.08` | `469.79` | `203.98s` | `89835` | PASS |

- R2 final correctness counts:
  - `sellPublished=120000`, `buyPublished=120000`, publish failures `0`;
  - `tradeExecutions=120000`;
  - `completedTrades=120000`;
  - `walletTradeSettlements=120000`;
  - `orderCommandMatchedRows=240000`;
  - final measured queues and DLQ `0`;
  - `remainingSellOrders=0`, `remainingBuyOrders=0`;
  - `lockedCurrency=0`, `lockedAmount=0`;
  - Redis `order:reservation:*` count after the run was `0`;
  - Redis `evicted_keys=0`.
- Log check:
  - No matched `ERROR`, reservation release failure, Redis orderbook inconsistency, or Hikari thread-starvation keyword was found in MatchEngine/Order/Wallet logs for the final run logs.
  - Both 2000-TPS attempts emitted one RabbitMQ client `Received a frame on an unknown channel, ignoring it` message during high publish pressure. The tests still completed, but this should be tracked if it repeats in formal evidence runs.
- Interpretation:
  - The harness can run with a `2000 TPS` target, and R2 actually reached `1999.91` buy confirmations/s.
  - Current business-complete capacity is still around `455-491 completed trades/s` for 120k local runs.
  - At 2000 offered TPS, backlog is expected: R2 peaked at `89835` ready messages on the MatchEngine input queue and required `203.98s` to drain after buy publish ended.
  - Therefore `2000` remains a valid offered-load stress profile, but it must not be described as `2000 completed TPS`.

Recommended validation tiers:

| Tier | Size | Purpose | When to run |
| --- | ---: | --- | --- |
| Smoke | `10-500` trades | Service startup, Lua/resource loading, obvious E2E breakage | Every risky local change |
| Guard | `10k` trades | Fast correctness gate: counts, queue drain, orderbook residuals | Before committing MatchEngine/Order/Wallet changes |
| Medium steady-state | `120k` trades, `500 TPS * 240s` or `2000 TPS * 60s` | Multi-minute queue/DB/Redis behavior, backlog/drain behavior, and race exposure | After correctness-sensitive changes |
| Formal steady-state | `450k` trades, `500 TPS * 900s` | Public/README evidence and rare race detection | Nightly, release candidate, or before publishing benchmark |

### TPS-59 MatchEngine Reservation Convergence

Review outcome:

- TPS-56 changed the MatchEngine orderbook model from destructive pop to reserve/finalize.
- This fixed the dangerous silent-loss class where a resting order could disappear from the visible orderbook before a durable `TradeExecuted` fact existed.
- The remaining reliability gap is different:
  - after `TradeExecuted` is durable, RabbitMQ publish, partial release, or reservation completion can still fail;
  - the order is no longer silently lost, but it can remain in a known `order:reservation:<orderId>` state;
  - the system currently exposes this state through diagnostics, but does not yet automatically converge it.

Architecture decision:

- MatchEngine owns Redis orderbook and reservation convergence.
- `TradeExecuted` in MatchEngine PostgreSQL is the durable fact that decides whether a reservation should be completed or released:
  - if a reservation has a matching durable `TradeExecuted`, the reservation should finalize/complete;
  - if a reservation does not have a durable `TradeExecuted`, the reservation should be released back to the visible orderbook using its original amount;
  - if the order was partially filled, the remaining quantity should be released only when the durable trade fact exists and the remaining amount is greater than zero.
- Order and Wallet should not repair MatchEngine Redis orderbook state directly.
- This ticket does not change the business completion gate. It only upgrades MatchEngine from "known stuck state" to "self-converging stuck state".

Required implementation behavior:

- Make reservation Lua operations idempotency-safe:
  - `release_reserved_order.lua` must not resurrect an order unless the reservation key exists and represents that order;
  - `complete_reserved_order.lua` should be safe to call repeatedly after a reservation was already completed;
  - reserve should avoid overwriting an existing reservation for the same order without a clear outcome.
- Add reservation inspection metadata sufficient for reconciliation:
  - order id;
  - market id;
  - side;
  - original reserved amount;
  - current remaining amount when applicable;
  - reserved timestamp;
  - optional trade id / match id once a durable `TradeExecuted` exists.
- Add a MatchEngine reconciler:
  - scans `order:reservation:*`;
  - classifies each reservation as `pending`, `durable_trade_exists`, `orphan_without_trade`, or `invalid_payload`;
  - completes reservations with durable trades;
  - releases orphan reservations without durable trades after a conservative age threshold;
  - emits metrics and logs for every action and every non-actionable invalid reservation.
- Add reservation metrics:
  - active reservation count;
  - reservation age max / p95 if practical;
  - reconciler scanned count;
  - reconciler completed count;
  - reconciler released count;
  - invalid reservation count;
  - release/complete failure count.
- Add load-test diagnostics:
  - include `order:reservation:*` count in the matched E2E result JSON;
  - include active reservation count before final queue purge;
  - fail the correctness gate when reservations remain outside an explicitly allowed failure-injection test.

Acceptance criteria:

- Normal path:
  - 10k guard passes with `completedTrades == EVENTS`;
  - final measured queues and DLQ are `0`;
  - final `order:reservation:*` count is `0`;
  - reservation reconciler metrics show no invalid reservations.
- Failure path before durable trade:
  - inject failure after reserve and before `TradeExecuted` persistence;
  - reservation remains visible as known state;
  - reconciler releases the order back to the visible orderbook after the configured threshold;
  - the order is matchable again;
  - no `TradeExecuted` row is created for the failed attempt.
- Failure path after durable trade:
  - inject failure after `TradeExecuted` persistence and before Redis complete/release;
  - reconciler detects the durable trade;
  - reconciler completes the reservation or releases the remaining partial quantity exactly once;
  - repeated reconciler runs do not duplicate visible orderbook entries.
- Stale compensation safety:
  - calling release for a non-existing reservation must not add the order back to the orderbook;
  - calling complete repeatedly must remain harmless.
- Regression:
  - 120k medium steady-state still passes after the reconciler is enabled;
  - if `2000 TPS * 60s` is used, the run may build backlog, but must still drain with reservations at `0`.

Suggested task split:

| Task | Priority | Owner | Acceptance |
| --- | --- | --- | --- |
| TPS-59-01 Harden reservation Lua idempotency | P0 | Implementation Lead | Lua scripts enforce reservation-key preconditions and repeated complete/release calls are safe. |
| TPS-59-02 Add reservation metadata and metrics | P0 | Implementation Lead | Active count and reconciler action counters are exposed through actuator/Prometheus and diagnostics. |
| TPS-59-03 Implement MatchEngine reservation reconciler | P0 | Implementation Lead | Stuck reservations converge based on durable `TradeExecuted` existence and age threshold. |
| TPS-59-04 Add failure-injection tests | P0 | QA Lead | Tests cover reserve-before-trade failure, trade-after-reserve failure, repeated release/complete, and partial-fill recovery. |
| TPS-59-05 Add load-test reservation gate | P0 | QA Lead | Matched E2E result JSON includes reservation count and fails unexpected residual reservations. |
| TPS-59-06 Run guard and medium steady-state | P1 | Performance | 10k guard and 120k medium steady-state pass with final reservation count `0`. |

Recommended verification commands:

```bash
GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest
```

```bash
TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 TIMEOUT_SECONDS=300 MARKET_ID=GLT_<date>_TPS59_RESERVATION_GUARD_10K RUN_MODE=prepare-run DIAGNOSTICS_LEVEL=deep RESET_PG_STATS_BEFORE_RUN=true bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

```bash
TARGET_TPS=2000 DURATION_SECONDS=60 EVENTS=120000 PUBLISHERS=128 TIMEOUT_SECONDS=1800 MARKET_ID=EAP_STEADY_2000TPS_120K_<date>_TPS59 RUN_MODE=prepare-run DIAGNOSTICS_LEVEL=deep RESET_PG_STATS_BEFORE_RUN=true bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

2026-07-17 implementation pass:

- Implemented reservation convergence in MatchEngine:
  - reservation Lua now stores a metadata envelope with `reservedAtEpochMillis` and nested order JSON;
  - reserve uses `SET ... NX` and reports existing-reservation inconsistency instead of overwriting;
  - release requires a matching reservation key before restoring the orderbook entry;
  - complete requires a matching reservation key before deleting order detail / user open-order link;
  - `RedisOrderBookService` can scan reservation snapshots with backward compatibility for the old raw-order reservation value;
  - `ReservationReconciler` scans `order:reservation:*`, checks durable `trade_executions` since reservation time, completes full fills, releases partial remaining quantity, and releases old orphan reservations without durable trades;
  - `ReservationReconcilerMetrics` exposes active reservation gauge and scanned/completed/released/invalid/failure counters.
- Implemented load-test reservation gate:
  - matched E2E result JSON now includes `activeReservations`;
  - normal matched E2E runs fail if `activeReservations != 0`;
  - load-test cleanup removes stale `order:reservation:*` keys to prevent previous failed runs from polluting the next benchmark.
- Focused verification:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.ReservationReconcilerTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest` passed.
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.EapMatchengineApplicationTests` passed, validating Spring bean wiring and repository query creation.
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed in `eap-order`, validating the load-test harness compile.
- Smoke E2E:
  - Run ID: `GLT_20260717_TPS59_RESERVATION_SMOKE_500`.
  - `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, `orderCommandMatchedRows=1000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Manual Redis scan after the run found `0` `order:reservation:*` keys.
- 10k guard:
  - Run ID: `GLT_20260717_TPS59_RESERVATION_GUARD_10K`.
  - `actualBuyPublishTps=1998.91`, `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`.
  - `businessMatchedE2eTps=393.84`, `completionMarkerReachTps=448.51`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - This run exposed a false-positive reconciler log: SCAN saw reservation keys that normal completion deleted before GET, so the reconciler logged missing values as invalid reservations.
- False-positive fix:
  - `RedisOrderBookService.scanReservations()` now treats SCAN/GET disappearances as transient and skips them.
  - R2 guard `GLT_20260717_TPS59_RESERVATION_GUARD_10K_R2` passed with `completedTrades=10000`, final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, and `activeReservations=0`.
  - R2 was driver-limited (`actualBuyPublishTps=901.30`), so it is accepted as a correctness/log validation run, not as a 2000 offered-load throughput sample.
  - R2 logs had no matched `ERROR`, `Invalid MatchEngine reservation`, reservation release failure, Redis orderbook inconsistency, Hikari thread-starvation, or RabbitMQ unknown-channel keyword. The only matched lines were existing Bean Validation provider INFO messages.
- 120k medium steady-state:
  - Run ID: `EAP_STEADY_2000TPS_120K_20260717_TPS59_R1`.
  - Command: `TARGET_TPS=2000 DURATION_SECONDS=60 EVENTS=120000 PUBLISHERS=128 TIMEOUT_SECONDS=1800 MARKET_ID=EAP_STEADY_2000TPS_120K_20260717_TPS59_R1 RUN_MODE=prepare-run DIAGNOSTICS_LEVEL=deep RESET_PG_STATS_BEFORE_RUN=true bash scripts/load-test/run-global-matched-e2e-sustained.sh`.
  - Bulk seed completed in `28s`; projection prewarm produced `openOrders=240000`.
  - Offered load reached target: `buyPublished=120000`, `buyPublishFailures=0`, `buyPublishSeconds=60.01`, `actualBuyPublishTps=1999.69`.
  - Business completion passed: `completedTrades=120000`, `tradeExecutions=120000`, `walletTradeSettlements=120000`, `orderCommandMatchedRows=240000`.
  - Final drain passed: final ready/unacked queues were `0`; `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput signals: `businessMatchedE2eTps=404.19`, `tradeExecutionReachTps=527.00`, `orderCommandMatchReachTps=425.81`, `walletSettlementReachTps=428.06`, `completionMarkerReachTps=412.28`.
  - Backlog signal: `maxMatchEngineQueueReady=96975`, so 2000 offered TPS still builds a large MatchEngine intake backlog, but it drained cleanly.
  - Manual Redis scan after the run found `0` `order:reservation:*` keys; Redis stats showed `evicted_keys=0` and `rejected_connections=0`.
  - MatchEngine/Order/Wallet log grep had no matched `ERROR`, `Invalid MatchEngine reservation`, reservation release failure, Redis orderbook inconsistency, Hikari thread-starvation, or RabbitMQ unknown-channel keyword. The only matched lines were existing Bean Validation provider INFO messages.
  - Conclusion: TPS-59 closes the previous "completed trade but hidden Redis/orderbook state remains" failure mode for the current medium steady-state gate. This is still a 120k local validation run, not a formal 450k/nightly public benchmark.
- Remaining validation:
  - Consider adding a dedicated failure-injection integration test with Redis/Testcontainers if this becomes production-hardening work rather than benchmark-hardening work.

### TPS-60 MatchEngine Trade Persistence Round-Trip Reduction

2026-07-17 performance review:

- The TPS-59 120k medium run proved correctness, but still showed the first throughput ceiling at MatchEngine intake/persistence:
  - `maxMatchEngineQueueReady=96975`;
  - `tradeExecutionReachTps=527.00`;
  - `businessMatchedE2eTps=404.19`.
- `JpaTradeExecutionRecorder` wrote each trade with two JDBC statements inside one transaction:
  - insert `match_engine.trade_executions`;
  - insert `match_engine.trade_outbox`;
  - the completion view hot path was already disabled in loadtest, so these two writes were the fixed MatchEngine DB round trips before downstream completion.

Implementation:

- Collapsed trade fact persistence and TradeExecuted outbox persistence into one PostgreSQL CTE statement:
  - `WITH inserted_trade AS (INSERT ... RETURNING trade_id) INSERT INTO trade_outbox ... SELECT ... FROM inserted_trade`;
  - duplicate `trade_id` still returns `0` rows and fails before downstream publication;
  - the transactional outbox boundary is preserved: the durable trade fact and its outbox event are still committed atomically.
- Updated `JpaTradeExecutionRecorderTest` to assert the single-statement persistence path and payload/routing-key parameters.

Verification:

- Focused tests:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest` passed.
- 10k guard:
  - Run ID: `GLT_20260717_TPS60_MATCH_CTE_10K_R1`.
  - `actualBuyPublishTps=1999.08`, `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput signal: `tradeExecutionReachTps=645.57`, `orderCommandMatchReachTps=541.40`, `walletSettlementReachTps=541.40`, `completionMarkerReachTps=410.30`, `businessMatchedE2eTps=345.98`.
  - Interpretation: short-run business TPS was dominated by final unacked drain noise, but the MatchEngine trade execution stage improved enough to justify a 120k medium run.
- 120k medium steady-state:
  - Run ID: `EAP_STEADY_2000TPS_120K_20260717_TPS60_MATCH_CTE_R1`.
  - `actualBuyPublishTps=1983.09`, `completedTrades=120000`, `tradeExecutions=120000`, `walletTradeSettlements=120000`, `orderCommandMatchedRows=240000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput improved versus TPS-59 120k:
    - `businessMatchedE2eTps`: `404.19 -> 436.93` (`+8.1%`);
    - `tradeExecutionReachTps`: `527.00 -> 571.76` (`+8.5%`);
    - `orderCommandMatchReachTps`: `425.81 -> 456.82`;
    - `walletSettlementReachTps`: `428.06 -> 456.82`;
    - `completionMarkerReachTps`: `412.28 -> 447.20`;
    - `drainSecondsAfterBuyPublish`: `236.88s -> 214.13s`;
    - `maxMatchEngineQueueReady`: `96975 -> 85587`.
  - Manual Redis scan after the run found `0` `order:reservation:*` keys.
  - MatchEngine/Order/Wallet log grep had no matched `ERROR`, `Invalid MatchEngine reservation`, reservation release failure, Redis orderbook inconsistency, Hikari thread-starvation, or RabbitMQ unknown-channel keyword. The only matched lines were existing Bean Validation provider INFO messages.

Conclusion:

- The CTE merge is a valid hot-path optimization: it reduces MatchEngine trade persistence round trips and improves the 120k business-gated result by about `8%`.
- The system is still not near 600 completed trades/s steady-state; after this change, the next measured floor is downstream convergence around `447 completed-marker/s`, with final queue unacked drain still controlling business E2E TPS.
- Next target should be completion-marker insertion/convergence and MatchEngine outbox publisher confirm behavior, not connection pool size.

### TPS-61 Load-Test Progress Snapshot Cost Reduction

2026-07-17 performance review:

- TPS-60 deep diagnostics showed several top SQL statements were not service hot-path work, but load-test progress polling:
  - Order projection stale count against `orders_current` / `order_stream_heads`;
  - Order projection matched count against `orders_current`;
  - repeated Wallet aggregate `SUM(...)` checks across `wallet_service.wallets`;
  - duplicated Order command matched count from `order_matching_state`.
- These checks are valuable for final correctness, but they do not need to run once per second while the services are trying to drain the queue.
- Keeping them in the progress loop distorted local benchmark results because the load generator shares the same local PostgreSQL containers as the services under test.

Implementation:

- Split `MatchedE2eLoadGenerator` DB snapshots into:
  - lightweight progress snapshot: Order command matched rows, MatchEngine trade executions, completion marker reach, Wallet settlements, and queue depth;
  - strict final snapshot: projection stale count, wallet balance sums, Redis orderbook/reservation checks, queue drain, and full business invariants.
- Reused the current queue sample inside the progress snapshot instead of querying RabbitMQ a second time during the same loop.
- Removed the duplicated Order matched count query by using one `order_matching_state` count for both reported `orderMatchedEvents` and `orderCommandMatchedRows`.
- Preserved correctness gates:
  - the run only returns after core business counts are reached and queues are fully drained;
  - final verification still requires zero locked wallet balances, expected buyer/seller balances, completed trades, Order command rows, Wallet settlements, empty Redis orderbooks, and zero active reservations.

Verification:

- Compile:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order` passed.
- 500 smoke:
  - Run ID: `GLT_20260717_TPS61_LIGHT_SNAPSHOT_SMOKE_500`.
  - `actualBuyPublishTps=1973.87`, `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, `orderCommandMatchedRows=1000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - `pg_stat_statements` confirmed expensive projection and wallet sum checks ran only once at final verification rather than every progress snapshot.
- 10k deep:
  - Run ID: `GLT_20260717_TPS61_LIGHT_SNAPSHOT_10K_R1`.
  - `actualBuyPublishTps=1998.86`, `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`.
  - `businessMatchedE2eTps=320.97`, `tradeExecutionReachTps=572.96`, `orderCommandMatchReachTps=424.71`, `walletSettlementReachTps=424.71`, `completionMarkerReachTps=390.10`.
  - Result is correctness-valid but not a good performance baseline; the service reach rates were lower than TPS-60, indicating local run noise or deep diagnostic interference.
- 10k light:
  - Run ID: `GLT_20260717_TPS61_LIGHT_SNAPSHOT_10K_LIGHT_R1`.
  - `actualBuyPublishTps=1998.44`, `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput signal improved under lighter diagnostics: `tradeExecutionReachTps=770.54`, `orderCommandMatchReachTps=657.09`, `walletSettlementReachTps=657.09`, `completionMarkerReachTps=578.30`, `businessMatchedE2eTps=399.65`.

Conclusion:

- TPS-61 reduces benchmark self-interference and preserves final correctness gates.
- The 10k light run proves the core service stages can reach roughly `580-770/s` on this local machine when heavy diagnostics are removed, but business E2E remains lower because final queue-unacked drain still controls completion time.
- For performance reporting, use light/baseline mode for headline throughput and deep mode only for attribution runs.
- Next optimization target remains final ack/drain behavior and downstream consumer transaction tail latency, not the removed progress polling.

### TPS-62 Final Drain Attribution and Outbox Publish-Concurrency Rejection

2026-07-17 performance review:

- TPS-61 showed the service stages could reach roughly `580-770/s` in light mode, but the accepted business gate stayed lower because `queueFullyDrainedSeconds` lagged behind `completedTradesReachedSeconds`.
- The first drain trace used 1-second light queue sampling:
  - Run ID: `GLT_20260717_TPS62_DRAIN_TRACE_10K_LIGHT_R1`.
  - `actualBuyPublishTps=1999.15`, `businessMatchedE2eTps=461.81`.
  - `tradeExecutionReachTps=1018.54`, `orderCommandMatchReachTps=674.29`, `walletSettlementReachTps=674.29`, `completionMarkerReachTps=586.90`.
  - `completedTradesReachedSeconds=17.04`, but `queueFullyDrainedSeconds=21.65`.
  - Runtime queue samples showed the final tail was not ready backlog; the remaining hot queues were `ready=0` and nonzero `unacked`.
- Light diagnostics had a blind spot: final snapshots only captured Order actuator metrics. That made it hard to attribute Wallet and MatchEngine tail cost without switching to deep mode.

Implementation:

- Updated `scripts/load-test/collect-loadtest-diagnostics.sh` so light mode still keeps the low-cost runtime sampler, but final before/after snapshots now capture all three actuator endpoints:
  - Wallet: `wallet-actuator-prometheus.txt`;
  - Order: `order-actuator-prometheus.txt`;
  - MatchEngine: `match-actuator-prometheus.txt`.
- This is a diagnostics-only change; it does not add hot-path sampling during the run.

Verification:

- Script syntax:
  - `bash -n scripts/load-test/collect-loadtest-diagnostics.sh` passed.
- Focused compile:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed in both `eap-order` and `eap-wallet` while testing rejected config variants.
- 10k light with final three-service actuator metrics:
  - Run ID: `GLT_20260717_TPS62_LIGHT_FINAL_METRICS_10K_R1`.
  - `actualBuyPublishTps=1998.76`, `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput: `businessMatchedE2eTps=456.61`, `tradeExecutionReachTps=876.09`, `orderCommandMatchReachTps=720.25`, `walletSettlementReachTps=720.25`, `completionMarkerReachTps=619.69`.
  - Timing: `completedTradesReachedSeconds=16.14`, `queueFullyDrainedSeconds=21.90`.
  - DB pool signals were healthy: Order, Wallet, and MatchEngine Hikari `pending=0`, `timeout=0`.
  - Order trade apply was not the dominant final tail: batch total `7.86s` summed across `1279` batch calls, max `94ms`.
  - Wallet settlement transaction work summed to `17.87s` across `10000` events, max `36ms`, with no pool wait.
  - Outbox relay fixed cost remained visible:
    - MatchEngine trade outbox: `21` batches, batch duration sum `13.20s`, confirm sum `12.33s`;
    - Order outbox: `21` batches, batch duration sum `15.27s`, publish enqueue sum `14.00s`;
    - Wallet outbox: `22` batches, batch duration sum `15.29s`, publish enqueue sum `14.01s`.

Rejected experiments:

- Order/Wallet outbox `publish-concurrency=4`:
  - Run ID: `GLT_20260717_TPS62_ORDER_WALLET_OUTBOX_PUB4_10K_R1`.
  - Business gate looked better (`businessMatchedE2eTps=544.42`), but the run is not a valid 2000 TPS comparison because the input driver only reached `actualBuyPublishTps=852.68`.
  - Order/Wallet `publish_enqueue` summed time inflated to roughly `54s` each, showing local RabbitMQ/publisher contention rather than a clean relay improvement.
- Order/Wallet outbox `publish-concurrency=2`:
  - Run ID: `GLT_20260717_TPS62_ORDER_WALLET_OUTBOX_PUB2_10K_R1`.
  - Input pressure was valid (`actualBuyPublishTps=1997.71`), but throughput regressed: `businessMatchedE2eTps=380.96`, `completionMarkerReachTps=504.92`.
  - MatchEngine intake backlog reappeared: `maxMatchEngineQueueReady=2569`, `maxMatchEngineQueueUnacked=700`.
  - This indicates Order/Wallet outbox publish parallelism competes with MatchEngine intake and does not improve the accepted 2000 TPS business gate on the current local setup.

Conclusion:

- Keep the TPS-62 diagnostics change; it improves attribution without increasing runtime light-mode cost.
- Do not adopt Order/Wallet outbox publish-concurrency tuning. Both tested variants are rejected:
  - `4` invalidates the offered-load comparison;
  - `2` preserves input TPS but worsens business completion and MatchEngine queue backlog.
- Current accepted short-run reference remains the light final-metrics run around `456.61` business TPS with `619.69` completion-marker TPS.
- Next target should be MatchEngine trade outbox publisher confirm behavior and broker/resource contention measurement, not increasing downstream marker relay concurrency.

### TPS-63 Raw JSON Outbox Relay Rejection

2026-07-17 performance review:

- Hypothesis: Order and Wallet outbox relays might be paying unnecessary JSON deserialize/serialize cost by reading the stored payload into an event object, then calling `RabbitTemplate.convertAndSend(...)`.
- Experiment: change Order and Wallet relays to publish the stored payload bytes directly as an AMQP JSON `Message`, matching the shape already used by MatchEngine `TradeOutboxRelay`.
- The change preserved message correctness in a 500 smoke run:
  - Run ID: `GLT_20260717_TPS63_RAW_OUTBOX_SMOKE_500`.
  - `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`.
  - Final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
- The 10k light comparison rejected the change:
  - Run ID: `GLT_20260717_TPS63_RAW_OUTBOX_10K_R1`.
  - `actualBuyPublishTps=1998.40`, but `businessMatchedE2eTps=294.13` and `completionMarkerReachTps=353.50`.
  - This is materially worse than TPS-62 reference `businessMatchedE2eTps=456.61` and `completionMarkerReachTps=619.69`.
  - MatchEngine input backlog returned: `maxMatchEngineQueueReady=4405`, `maxMatchEngineQueueUnacked=700`.
  - Outbox relay enqueue cost worsened instead of improving:
    - Order `publish_enqueue` sum: `13.997s -> 24.187s`;
    - Wallet `publish_enqueue` sum: `14.006s -> 24.251s`;
    - Match trade outbox confirm sum also worsened: `12.332s -> 22.383s`.

Conclusion:

- Do not switch Order/Wallet outbox relay to direct raw JSON `Message` publishing in this shape.
- The result shows the apparent serialization cost was not the main bottleneck; this path increased local RabbitMQ/send-path contention and hurt full business completion.
- The attempted code change was reverted. No production code from this rejected experiment should be kept.
- Continue with MatchEngine hot-path attribution rather than more outbox relay API micro-tuning.

### TPS-64 MatchEngine Hot-Path Stage Metrics

2026-07-17 performance review:

- TPS-62 and TPS-63 both showed that further consumer/publisher concurrency tuning is not the right next lever.
- The visible bottleneck repeatedly moves back to MatchEngine intake/persistence when local broker or downstream relays are stressed.
- Existing light diagnostics had outbox and downstream timers, but did not split `OrderConfirmed -> match -> TradeExecuted` into measurable MatchEngine stages.

Implementation:

- Added `MatchingEngineMetrics` with low-cost Micrometer timers/counters for:
  - overall `tryMatch`;
  - Redis reserve-best-order Lua call;
  - Redis add-order Lua call for unmatched resting orders;
  - Redis match-id generation;
  - durable `TradeExecuted` record plus transactional outbox insert;
  - Redis reservation completion/release;
  - legacy publish path, if enabled.
- Updated `MatchingEngineService` to record these stages without changing business behavior.
- Updated the load-test diagnostics collector to include `match_engine_*` metrics in final actuator snapshots.

Verification:

- Focused tests:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest` passed.
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed in `eap-matchEngine`.
- 10k light run:
  - Run ID: `GLT_20260717_TPS64_MATCH_STAGE_METRICS_10K_R1`.
  - Correctness: `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, final queues/unacked `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.
  - Throughput: `actualBuyPublishTps=1999.05`, `businessMatchedE2eTps=380.08`, `completionMarkerReachTps=483.12`.
  - Timing: `tradeExecutionsReachedSeconds=16.39`, `completedTradesReachedSeconds=20.70`, `queueFullyDrainedSeconds=26.31`.
  - Queue signal: `maxMatchEngineQueueReady=2062`, `maxMatchEngineQueueUnacked=700`.

Measured MatchEngine stage costs:

| Stage | Count | Sum |
| --- | ---: | ---: |
| `match_engine_try_match_duration` | `20000` | `64.197s` |
| `match_engine_reserve_order_duration` | `20000` | `20.715s` |
| `match_engine_add_order_duration` | `10000` | `10.541s` |
| `match_engine_match_id_duration` | `10000` | `7.515s` |
| `match_engine_trade_record_duration` | `10000` | `16.232s` |
| `match_engine_complete_reservation_duration` | `10000` | `9.041s` |
| `trade_outbox_confirm_duration` | `10000` | `16.498s` |

Interpretation:

- The 10k matched workload is actually `20000` `OrderConfirmed` messages for `10000` trades.
- Resting SELL orders still consume MatchEngine capacity: each no-match SELL pays a Redis reserve attempt and an add-order Lua write before BUY orders can match.
- For each matched BUY, the visible fixed costs are roughly:
  - Redis reserve best order;
  - Redis match-id `INCR`;
  - PostgreSQL durable trade/outbox CTE;
  - Redis reservation completion;
  - later MatchEngine trade outbox publisher confirm.
- The clearest next code target is to remove one Redis round trip per completed trade by combining match-id generation into the reserve Lua operation:
  - reserve the resting order and generate the sequence in one atomic Lua script;
  - return both `matchId` and reserved order payload to Java;
  - keep the sequence distributed and preserve the reservation safety model.

Conclusion:

- Keep TPS-64 metrics. They make the next MatchEngine optimization measurable and avoid another round of blind concurrency tuning.
- Do not optimize by changing service boundaries or moving Order/Wallet state into MatchEngine.
- Next ticket should implement and benchmark "reserve resting order + match-id generation in one Redis Lua operation", then compare against TPS-62/TPS-64 using the new stage timers.

### TPS-65 Combine Redis Reservation and Match Sequence

2026-07-17 implementation:

- Combined the MatchEngine resting-order reservation and match-id sequence generation into the reserve-best-order Lua path.
- The matched path now calls `reserveBestMatchOrderWithSequenceLua(...)`, which returns both:
  - the reserved resting order payload;
  - the generated `matchId`.
- Removed the hot-path Java-side `RedisTemplate.opsForValue().increment("match:id:sequence")` call from `MatchingEngineService`.
- Kept the existing reservation model:
  - no-match incoming orders do not consume a sequence;
  - the resting order is hidden from the visible orderbook only after a sequence is generated successfully;
  - deterministic sequence-key failures happen before the script mutates the reservation/orderbook state;
  - sequence gaps are acceptable if an impossible visible-order-plus-reservation inconsistency is detected.
- Kept the legacy `reserveBestMatchOrderLua(...)` method for compatibility and existing consistency tests.

Verification:

- Focused tests:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest` passed.
- 500 smoke after the safety-ordering fix:
  - Run ID: `GLT_20260717_TPS65_COMBINED_RESERVE_SEQ_SAFE_SMOKE_500`.
  - Correctness: `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, final queues/DLQ `0`, `activeReservations=0`.
  - Throughput: `actualBuyPublishTps=1799.45`, `businessMatchedE2eTps=385.38`, `completionMarkerReachTps=385.38`.
- 10k comparison run before the safety-ordering fix:
  - Run ID: `GLT_20260717_TPS65_COMBINED_RESERVE_SEQ_10K_R1`.
  - Correctness: `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, final queues/unacked `0`, `activeReservations=0`.
  - Throughput: `actualBuyPublishTps=1998.56`, `businessMatchedE2eTps=419.16`, `completionMarkerReachTps=494.97`.
  - Timing: `tradeExecutionsReachedSeconds=15.64`, `completedTradesReachedSeconds=20.20`, `queueFullyDrainedSeconds=23.86`.
  - Queue signal: `maxMatchEngineQueueReady=3750`, `maxMatchEngineQueueUnacked=700`.
- 10k final safety run:
  - Run ID: `GLT_20260717_TPS65_COMBINED_RESERVE_SEQ_SAFE_10K_R1`.
  - Correctness: `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, final queues/DLQ `0`, `activeReservations=0`.
  - This run is not valid for TPS comparison because the load generator only achieved `actualBuyPublishTps=1033.40` instead of the intended `~2000/s`.
  - It is still useful as a correctness run after the Lua safety-ordering fix.

Measured MatchEngine stage comparison:

| Run | Offered BUY TPS | Business TPS | Completion-marker TPS | Reserve sum | Match-id sum | Reserve + match-id | Trade record sum | Complete reservation sum | Match outbox confirm sum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| TPS-64 `GLT_20260717_TPS64_MATCH_STAGE_METRICS_10K_R1` | `1999.05` | `380.08` | `483.12` | `20.715s` | `7.515s` | `28.230s` | `16.232s` | `9.041s` | `16.498s` |
| TPS-65 `GLT_20260717_TPS65_COMBINED_RESERVE_SEQ_10K_R1` | `1998.56` | `419.16` | `494.97` | `27.970s` | `0.000s` | `27.970s` | `17.822s` | `15.054s` | `15.766s` |
| TPS-65 safe `GLT_20260717_TPS65_COMBINED_RESERVE_SEQ_SAFE_10K_R1` | `1033.40` | `319.06` | `454.05` | `27.905s` | `0.000s` | `27.905s` | `18.743s` | `14.008s` | `17.075s` |

Interpretation:

- The intended code effect is confirmed: `match_engine_match_id_duration_count=0`.
- The optimization removed one visible Redis command per completed trade, but the measured `reserve + match-id` total only changed from `28.230s` to about `27.970s`.
- This is a valid cleanup and small fixed-cost reduction, but it is not the dominant TPS lever.
- The remaining high-cost chain is still:
  - MatchEngine durable trade/outbox write;
  - Redis reservation completion;
  - MatchEngine trade outbox relay confirm;
  - Order/Wallet outbox relay;
  - Wallet settlement transaction.
- The final safety run also shows a measurement concern: when the local load generator cannot maintain the target offered load, `businessMatchedE2eTps` must not be treated as a service-capacity regression.

Conclusion:

- Keep TPS-65 because it simplifies the matched hot path and removes a Redis round trip without changing business semantics.
- Do not keep tuning consumer concurrency for this ticket; the repeated evidence says concurrency is not the main lever.
- Next useful target should be fixed write cost:
  - MatchEngine `TradeExecuted` durable write + outbox insert;
  - reservation completion cost;
  - outbox relay publish/confirm path;
  - load-driver stability guardrails so invalid offered-load runs are automatically flagged.

### TPS-66 MatchEngine Trade Outbox JDBC Relay Projection

2026-07-17 implementation:

- Reworked `TradeOutboxRelay` to stop selecting full JPA `TradeOutboxEntity` records in the relay hot path.
- The relay now uses `JdbcTemplate` to select only the columns required for publishing:
  - `id`;
  - `event_type`;
  - `aggregate_id`;
  - `routing_key`;
  - `payload`;
  - `attempt_count`.
- Mark-SENT and failure/retry updates now use `NamedParameterJdbcTemplate` SQL updates, matching the lighter relay style already used by Order and Wallet.
- Delivery semantics are unchanged:
  - publish `TradeExecutedEvent`;
  - wait for RabbitMQ publisher confirm;
  - only confirmed records are marked `SENT`;
  - nack/timeout/unroutable messages stay retryable or become `FAILED` after max attempts.

Verification:

- Focused test:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest` passed.
- Compile surface:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed.
- 500 smoke:
  - Run ID: `GLT_20260717_TPS66_MATCH_OUTBOX_JDBC_SMOKE_500`.
  - Correctness: `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, final queues/DLQ `0`, `activeReservations=0`.
  - Throughput: `actualBuyPublishTps=1977.26`, `businessMatchedE2eTps=417.20`, `completionMarkerReachTps=417.20`.

10k run:

- Run ID: `GLT_20260717_TPS66_MATCH_OUTBOX_JDBC_10K_R1`.
- Correctness: `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, final queues/DLQ `0`, `activeReservations=0`.
- Offered load was invalid for capacity comparison:
  - target: `2000` BUY confirmations/s;
  - actual: `720.25` BUY confirmations/s.
- The business result must therefore not be used as a formal TPS improvement claim.
- Observed values from the invalid run:
  - `businessMatchedE2eTps=491.03`;
  - `completionMarkerReachTps=614.64`;
  - `tradeExecutionsReachedSeconds=14.12`;
  - `completedTradesReachedSeconds=16.27`;
  - `queueFullyDrainedSeconds=20.37`.

Stage metrics from the invalid 10k run:

| Stage | Count | Sum |
| --- | ---: | ---: |
| `match_engine_try_match_duration` | `20000` | `57.614s` |
| `match_engine_reserve_order_duration` | `20000` | `21.159s` |
| `match_engine_add_order_duration` | `10000` | `12.539s` |
| `match_engine_trade_record_duration` | `10000` | `15.344s` |
| `match_engine_complete_reservation_duration` | `10000` | `8.482s` |
| `trade_outbox_batch_duration` | `22` | `13.147s` |
| `trade_outbox_confirm_duration` | `10000` | `12.530s` |
| `trade_outbox_mark_sent_duration` | `22` | `0.248s` |
| `trade_outbox_select_duration` | `299` | `0.825s` |

Interpretation:

- The JDBC relay projection is a reasonable fixed-cost cleanup and aligns MatchEngine with the existing Order/Wallet relay implementation style.
- The 500 smoke proves correctness.
- The 10k run suggests relay wall-clock costs may be lower, but it is not a valid apples-to-apples benchmark because the load generator failed to maintain the target offered load.
- Before using more 10k runs for performance decisions, the load-test tooling should explicitly flag invalid offered-load runs.

Next step:

- Add benchmark validity guardrails:
  - compute `offeredLoadRatio = actualBuyPublishTps / targetTps`;
  - mark runs invalid when target TPS is configured and actual offered load is below the accepted threshold;
  - surface this in JSON and repeat summaries so we stop comparing driver-limited runs against service-limited runs.

### TPS-67 Single-Run Offered-Load Validity Guardrail

2026-07-17 implementation:

- Added single-run validity fields to `MatchedE2eLoadGenerator` result JSON:
  - `minOfferedLoadRatio`;
  - `offeredLoadRatio`;
  - `validForCapacityComparison`;
  - `capacityInvalidReasons`;
  - `finalQueueBacklog`.
- Added `--min-offered-load-ratio`, defaulting to `0.95`.
- Threaded `MIN_OFFERED_LOAD_RATIO` through:
  - `run-global-matched-e2e.sh`;
  - `run-global-matched-e2e-two-phase.sh`;
  - `run-global-matched-e2e-sustained.sh`;
  - `run-2000-ticket-marker-10k.sh`;
  - `run-2000-ticket-marker-repeat.sh`.
- Repeat summaries already filtered invalid runs; this change makes every individual result JSON self-describing.

Validity rule:

- A run is not valid for capacity comparison when:
  - actual BUY offered load is below `targetTps * minOfferedLoadRatio`;
  - publish failures occur;
  - completed trades / trade executions / wallet settlements do not match expected events;
  - Order command rows do not match `events * 2`;
  - final measured queues still have ready/unacked backlog;
  - Redis orderbook or reservation state does not converge.

Verification:

- Compile:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed in `eap-order`.
- Guardrail smoke:
  - Run ID: `GLT_20260717_TPS_GUARDRAIL_SMOKE_10`.
  - Config: `TARGET_TPS=100`, `EVENTS=10`, `PUBLISHERS=4`, `MIN_OFFERED_LOAD_RATIO=0.95`.
  - Result fields:
    - `actualBuyPublishTps=110.44`;
    - `offeredLoadRatio=1.1044`;
    - `validForCapacityComparison=true`;
    - `capacityInvalidReasons=[]`;
    - `finalQueueBacklog=0`;
    - `completedTrades=10`;
    - `activeReservations=0`.

Conclusion:

- Keep this guardrail before doing more TPS comparison.
- Future benchmark interpretation should use:
  - correctness gate first;
  - `validForCapacityComparison` second;
  - throughput metrics only after the above two pass.

### TPS-68 Completion Marker Diagnostics and SQL Reset Hygiene

2026-07-17 implementation:

- Added `trade_completion_marker_*` to the selected actuator metric filters.
- Added an after-run `match-completion-markers.txt` diagnostic snapshot keyed by `MARKET_ID`.
- Extended run-phase DB stats reset so `RESET_PG_STATS_BEFORE_RUN=true` also calls `pg_stat_statements_reset()` for Order, Wallet, and MatchEngine when available.

Why:

- Light diagnostics previously omitted completion-marker metrics, so marker convergence could only be inferred from final business counts.
- Manual SQL review after light runs could mix historical `pg_stat_statements` with the current run because only `pg_stat_reset()` was called.
- The new marker snapshot gives a direct correctness and timing check:
  - marker rows by type;
  - distinct trades by type;
  - first and last marker timestamps.

Verification:

- Script syntax:
  - `bash -n scripts/load-test/run-global-matched-e2e-two-phase.sh` passed.
  - `bash -n scripts/load-test/collect-loadtest-diagnostics.sh` passed.
- Diagnostic snapshot verification:
  - Run ID: `GLT_20260717_TPS68_MARKER_METRICS_10K_R1`.
  - Marker snapshot confirmed `ORDER_APPLIED=10000` and `WALLET_SETTLED=10000`, both with `10000` distinct trades.

Deep attribution run:

- Run ID: `GLT_20260717_TPS68_MARKER_DEEP_10K_R1`.
- Correctness passed, but it is not valid for capacity comparison:
  - `actualBuyPublishTps=612.22`;
  - `offeredLoadRatio=0.3061`;
  - `validForCapacityComparison=false`;
  - reason: `driver_offered_tps_below_threshold`.
- Still useful for SQL attribution because the DB stats were reset before the run.

Clean MatchEngine SQL top from the deep run:

| SQL area | Calls | Total exec time | Mean |
| --- | ---: | ---: | ---: |
| `trade_executions + trade_outbox` CTE | `10000` | `1203.57ms` | `0.1204ms` |
| `trade_completion_markers` batch insert | `2914` | `775.50ms` | `0.2661ms` |
| `trade_outbox` select | `371` | `73.70ms` | `0.1987ms` |
| `trade_outbox` mark SENT, largest grouped shape | `11` | `68.55ms` | `6.2317ms` |

Interpretation:

- The largest business SQL statements are not showing multi-second database execution by themselves.
- Completion marker insertion is not the primary SQL bottleneck, although the observed average marker batch size was only about `6.9` markers per insert in the deep run.
- The bigger wall-clock costs remain relay/publisher path and queue drain behavior rather than raw SQL execution time alone.

### TPS-69 Order/Wallet Direct JSON Outbox Relay

2026-07-17 implementation:

- Changed Order and Wallet outbox relays to publish the stored JSON payload directly as AMQP `Message` instead of:
  - deserializing the JSON into an event object;
  - passing the object through `RabbitTemplate.convertAndSend(...)`;
  - serializing it again through the message converter.
- The relay now sets:
  - `contentType=application/json`;
  - `contentEncoding=UTF-8`;
  - persistent delivery mode.
- Publisher confirms, returned-message checks, retry behavior, and mark-SENT semantics are unchanged.

Reasoning:

- MatchEngine trade outbox already uses direct JSON message publishing and passed E2E correctness.
- Order/Wallet relays do not need to inspect event fields during publish; the payload is already the durable outbox message.
- This removes fixed relay CPU/conversion work without weakening transactional outbox semantics.

Verification:

- Compile/test:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` passed in `eap-order`.
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.OutboxPollerTest` passed in `eap-wallet`.
- 500 smoke:
  - Run ID: `GLT_20260717_TPS69_DIRECT_JSON_SMOKE_500`.
  - `actualBuyPublishTps=994.76`;
  - `validForCapacityComparison=true`;
  - `completedTrades=500`;
  - `tradeExecutions=500`;
  - `walletTradeSettlements=500`;
  - final queues/DLQ `0`;
  - `activeReservations=0`.

10k light runs:

| Run | Offered BUY TPS | Valid | Business TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| TPS-67 `GLT_20260717_TPS67_VALIDATED_10K_R1` | `1999.06` | yes | `457.98` | `629.78` | `21.83s` | `0` |
| TPS-69 R1 `GLT_20260717_TPS69_DIRECT_JSON_10K_R1` | `1998.93` | yes | `536.76` | `604.08` | `18.63s` | `0` |
| TPS-69 R2 `GLT_20260717_TPS69_DIRECT_JSON_10K_R2` | `1999.19` | yes | `440.65` | `605.22` | `22.69s` | `0` |

TPS-69 two-run average:

- Average business E2E TPS: `488.71`.
- Average completion-marker TPS: `604.65`.
- Both runs completed all `10000` trades with final queue backlog `0`.

Selected relay metrics:

| Metric | TPS-69 R1 | TPS-69 R2 |
| --- | ---: | ---: |
| Order outbox batch sum | `15.445s` | `15.347s` |
| Order outbox enqueue sum | `14.117s` | `14.103s` |
| Wallet outbox batch sum | `15.255s` | `15.520s` |
| Wallet outbox enqueue sum | `13.969s` | `14.420s` |
| Match outbox batch sum | `13.296s` | `14.177s` |
| Match outbox confirm sum | `12.602s` | `13.669s` |

Interpretation:

- Direct JSON relay is safe and worth keeping because it removes unnecessary relay conversion work while preserving outbox reliability.
- The two-run average is better than TPS-67, but R1/R2 variance is still large, so this should be treated as a fixed-cost cleanup rather than a proven final capacity breakthrough.
- `completionMarkerReachTps` stayed stable around `605 TPS`, while `businessMatchedE2eTps` moved with final queue drain time. The remaining bottleneck is still downstream relay/drain behavior and publisher path contention, not a single slow SQL statement.

### TPS-70 Scoped RabbitTemplate Channel Experiment

2026-07-20 experiment:

- Tried aligning Order and Wallet outbox relay publish paths with the MatchEngine chunked `RabbitTemplate.invoke(...)` pattern.
- The intent was to reduce per-message `RabbitTemplate.send(...)` fixed cost without changing:
  - transactional outbox semantics;
  - publisher confirms;
  - returned-message checks;
  - retry and mark-SENT behavior;
  - default relay publish concurrency.

Verification:

- Compile/test passed before E2E:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order`;
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.OutboxPollerTest` in `eap-wallet`.
- 500 smoke passed:
  - Run ID: `GLT_20260717_TPS70_SCOPED_CHANNEL_SMOKE_500`;
  - `actualBuyPublishTps=997.74`;
  - `validForCapacityComparison=true`;
  - `completedTrades=500`;
  - final backlog `0`;
  - `activeReservations=0`.

10k result:

| Run | Offered BUY TPS | Valid | Business TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| TPS-70 `GLT_20260717_TPS70_SCOPED_CHANNEL_10K_R1` | `1998.83` | yes | `378.27` | `510.29` | `26.44s` | `0` |

Selected metric comparison:

| Metric | TPS-69 R1 | TPS-70 |
| --- | ---: | ---: |
| Order outbox enqueue sum | `14.117s` | `0.153s` |
| Order outbox confirm sum | `0.920s` | `15.294s` |
| Wallet outbox enqueue sum | `13.969s` | `0.156s` |
| Wallet outbox confirm sum | `0.904s` | `14.973s` |
| Match outbox confirm sum | `12.602s` | `17.050s` |

Conclusion:

- Do not keep this implementation.
- The scoped-channel experiment reduced the measured enqueue timer, but shifted cost into publisher-confirm wait and lowered completed business TPS.
- It was reverted. Direct JSON relay remains in place.

### TPS-71 Wallet Hot-Path Logging Cleanup

2026-07-20 implementation:

- Lowered per-trade wallet settlement success logs from `INFO` to `DEBUG`.
- Lowered duplicate settlement skip logs from `INFO` to `DEBUG`.
- Rationale:
  - successful processing is already captured by metrics;
  - one `INFO` line per `TradeExecutedEvent` creates avoidable I/O and CPU cost;
  - hot-path logging should report anomalies, not every successful event.

Verification:

- Tests passed:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest --tests com.eap.eap_wallet.application.OutboxPollerTest`.
- The runtime wallet log dropped to startup-level volume:
  - `eap-wallet.log` had `73` lines in the TPS-71 light run, instead of one settlement line per trade.

10k runs:

| Run | Diagnostics | Offered BUY TPS | Valid | Business TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: |
| TPS-71 light `GLT_20260717_TPS71_WALLET_LOG_THROTTLE_10K_R1` | light | `612.16` | no | `405.67` | `491.53` | `24.65s` | `0` |
| TPS-71 baseline `GLT_20260717_TPS71_WALLET_LOG_THROTTLE_BASELINE_10K_R1` | baseline | `1997.44` | yes | `400.71` | `522.02` | `24.96s` | `0` |

Interpretation:

- The logging cleanup is correct and should stay, but it is not the main TPS breakthrough.
- The invalid light run proves the offered-load guardrail is still necessary; the driver only reached `30.61%` of target TPS and must not be used for capacity comparison.
- The valid baseline run still trails TPS-69, so current bottleneck work should move back to MatchEngine order-confirmed ingestion, Redis orderbook cost, RabbitMQ delivery/drain behavior, and load-generator stability.

### TPS-72 Redis Lua EVALSHA Dispatch Cleanup

2026-07-20 implementation:

- Changed MatchEngine `RedisOrderBookService` to load Lua scripts into Redis at service startup and execute the hot path with `EVALSHA`.
- Kept a `NOSCRIPT` fallback to the original `EVAL` path so Redis script-cache loss remains retryable without changing business semantics.
- This does not change order-book keys, reservation semantics, match-id generation, durable `TradeExecuted` persistence, completion markers, or final business gates.

Why this target:

- Recent valid 10k runs showed raw PostgreSQL statement time was not the dominant cost.
- Redis slowlog still contained repeated slow `EVAL` entries with full Lua script bodies for add/reserve paths from earlier runs.
- The expected win is fixed-cost cleanup in MatchEngine order-confirmed ingestion: avoid sending and parsing the full Lua script on every order-book operation.

Verification:

- Compile passed:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-matchEngine`.
- 500 smoke passed:
  - Run ID: `GLT_20260717_TPS72_REDIS_EVALSHA_SMOKE_500`;
  - `actualBuyPublishTps=999.04`;
  - `validForCapacityComparison=true`;
  - `completedTrades=500`;
  - final backlog `0`;
  - `activeReservations=0`.

10k baseline runs:

| Run | Offered BUY TPS | Valid | Business TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| TPS-72 R1 `GLT_20260717_TPS72_REDIS_EVALSHA_BASELINE_10K_R1` | `1998.95` | yes | `500.39` | `644.52` | `19.98s` | `0` |
| TPS-72 R2 `GLT_20260717_TPS72_REDIS_EVALSHA_BASELINE_10K_R2` | `745.34` | no | `438.30` | `544.10` | `22.82s` | `0` |
| TPS-72 R3 `GLT_20260717_TPS72_REDIS_EVALSHA_BASELINE_10K_R3` | `1999.07` | yes | `484.94` | `646.80` | `20.62s` | `0` |

Valid-sample summary:

- Valid runs: R1 and R3.
- Average business E2E TPS: `492.67`.
- Average completion-marker TPS: `645.66`.
- Average queue fully drained seconds: `20.30s`.
- Both valid runs completed all `10000` trades with final queue backlog `0`.

Redis slowlog check:

- Redis slowlog was reset before the R2/R3 validation window.
- After R2/R3, `redis-cli slowlog get 20` contained only the `slowlog reset` command.
- No slow `EVAL` or `EVALSHA` entry was recorded for TPS-72.

Interpretation:

- Keep the EVALSHA dispatch cleanup. It removes a measurable Redis fixed cost and eliminates the earlier slowlog symptom without changing business semantics.
- This is a modest hot-path cleanup, not the final 2000 completed-TPS breakthrough.
- R2 must be excluded from capacity comparison because the load driver only offered `37.27%` of target TPS. The benchmark guardrail correctly rejected it with `driver_offered_tps_below_threshold`.
- The next target should be load-driver stability and remaining end-to-end drain tail, then MatchEngine/Order/Wallet stage timers under a valid offered load. Do not return to blind consumer concurrency tuning unless the stage evidence changes.

### TPS-73 Load Driver Publish Attribution

2026-07-20 implementation:

- Added load-driver publish attribution to `MatchedE2eLoadGenerator`.
- The run JSON now includes:
  - `sellPublishAcquireWaitSeconds`, `sellPublishMaxAcquireWaitMs`;
  - `sellPublishSendSeconds`, `sellPublishMaxSendMs`, `sellPublishMaxScheduleLagMs`;
  - `buyPublishAcquireWaitSeconds`, `buyPublishMaxAcquireWaitMs`;
  - `buyPublishSendSeconds`, `buyPublishMaxSendMs`, `buyPublishMaxScheduleLagMs`.
- Purpose: distinguish service-side bottlenecks from load-driver under-offer caused by semaphore pressure, Rabbit publish blocking, or scheduler lag.

Verification:

- `eap-order` compile passed:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses`.
- 500 smoke passed:
  - Run ID: `GLT_20260720_TPS73_DRIVER_PUBLISH_METRICS_SMOKE_500`;
  - `actualBuyPublishTps=998.64`;
  - `validForCapacityComparison=true`;
  - `businessMatchedE2eTps=482.32`;
  - `completionMarkerReachTps=482.32`;
  - `completedTrades=500`;
  - final backlog `0`;
  - `activeReservations=0`.

10k baseline with new driver metrics:

| Run | Offered BUY TPS | Valid | Business TPS | TradeExecution reach TPS | Order/Wallet reach TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TPS-73 R1 `GLT_20260720_TPS73_DRIVER_PUBLISH_METRICS_10K_R1` | `1998.41` | yes | `390.20` | `729.22` | `624.95` | `515.78` | `25.63s` | `0` |
| TPS-73 deep R2 `GLT_20260720_TPS73_DRIVER_PUBLISH_METRICS_DEEP_10K_R2` | `1998.73` | yes | `391.95` | `676.00` | `629.41` | `553.05` | `25.51s` | `0` |

Driver attribution:

- TPS-73 R1 buy publish was healthy:
  - `buyPublishAcquireWaitSeconds=0.0030`;
  - `buyPublishSendSeconds=0.4889`;
  - `buyPublishMaxSendMs=12.366`;
  - `buyPublishMaxScheduleLagMs=7.104`.
- TPS-73 deep R2 buy publish was also acceptable:
  - `buyPublishAcquireWaitSeconds=0.0048`;
  - `buyPublishSendSeconds=0.6707`;
  - `buyPublishMaxSendMs=24.945`;
  - `buyPublishMaxScheduleLagMs=24.545`.
- Therefore the valid TPS-73 samples were service-side limited, not driver limited.

Interpretation:

- Driver metrics are worth keeping because they make invalid samples explainable.
- Under valid offered load, MatchEngine ingress still created a visible tail:
  - TPS-73 R1 `maxMatchEngineQueueReady=1122`, `maxMatchEngineQueueUnacked=700`;
  - TPS-73 deep R2 `maxMatchEngineQueueReady=1352`, `maxMatchEngineQueueUnacked=700`.
- Deep metrics showed the current two-phase workload paid an avoidable Redis fixed cost:
  - `match_engine_try_match_duration_seconds_count=20000`;
  - `match_engine_reserve_order_duration_seconds_count=20000`;
  - `match_engine_add_order_duration_seconds_count=10000`.
- In this workload, all resting SELL confirmations first try to reserve an opposite BUY, observe no match, and then execute a second `add_order.lua` call. The next target is to combine reserve-or-add into one Lua operation without changing durable trade semantics.

### TPS-74 Redis Reserve-Or-Add Hot Path

2026-07-20 implementation:

- Added `reserve_or_add_order_buy.lua` and `reserve_or_add_order_sell.lua`.
- Added `RedisOrderBookService.reserveBestMatchOrAddOrderWithSequenceLua(...)`.
- Changed `MatchingEngineService.tryMatch(...)` to use the new combined Lua result:
  - `__MATCH__` reserves the resting opposite order and returns the reserved order plus match sequence;
  - `__ADDED__` adds the incoming order to the visible order book when no match exists;
  - inconsistency statuses still fail fast when order detail is missing or a visible order is already reserved.
- Removed the Java no-match path that first returned `null` from reserve and then called `add_order.lua`.
- This does not change:
  - `TradeExecuted` persistence;
  - reservation completion/release behavior;
  - Order/Wallet downstream event flow;
  - completion markers;
  - business-gated load-test correctness requirements.

Unit verification:

- MatchEngine targeted tests passed:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.RedisOrderBookServiceTest --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest`.
- Added tests for:
  - matched reserve-or-add returning a reserved order and match id;
  - no-match reserve-or-add adding the incoming order in Redis;
  - `MatchingEngineService` not calling the old second `addOrder` path when no match exists.

Smoke and 10k validation:

| Run | Offered BUY TPS | Valid | Business TPS | TradeExecution reach TPS | Order/Wallet reach TPS | Completion-marker TPS | Queue fully drained | Final backlog |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TPS-74 smoke `GLT_20260720_TPS74_RESERVE_OR_ADD_SMOKE_500` | `994.81` | yes | `364.95` | `614.36` | `413.95` | `364.95` | `1.37s` | `0` |
| TPS-74 R1 `GLT_20260720_TPS74_RESERVE_OR_ADD_10K_R1` | `756.55` | no | `445.66` | `745.02` | `745.02` | `641.85` | `22.44s` | `0` |
| TPS-74 R2 `GLT_20260720_TPS74_RESERVE_OR_ADD_10K_R2` | `1999.19` | yes | `463.42` | `1008.29` | `817.83` | `689.84` | `21.58s` | `0` |
| TPS-74 deep R3 `GLT_20260720_TPS74_RESERVE_OR_ADD_DEEP_10K_R3` | `1998.73` | yes | `466.45` | `763.44` | `649.20` | `570.77` | `21.44s` | `0` |

Load-driver fix during TPS-74:

- TPS-74 R1 was correctness-pass but invalid for capacity comparison because the driver only offered `756.55` BUY TPS.
- The new TPS-73 metrics showed the client-side `RabbitTemplate.convertAndSend` path was blocked:
  - `buyPublishSendSeconds=894.7765`;
  - `buyPublishMaxSendMs=8636.465`;
  - `buyPublishAcquireWaitSeconds=1.7281`.
- Root cause was load-generator client shape:
  - `MatchedE2eLoadGenerator` manually created its own `CachingConnectionFactory`;
  - it did not inherit the Spring Boot Rabbit channel-cache settings used by services;
  - with `128` publisher threads, the default channel cache caused excessive channel churn and occasional publish under-offer.
- Fixed by setting driver `publisherChannelCacheSize` to `max(128, publishers * 2)` and adding the value to run JSON.
- Also removed legacy queues from load-test purge:
  - `order.create.queue`;
  - `order.created.queue`;
  - `order.failed.queue`.
- Those queues no longer exist in the current topology; passive-declaring them produced RabbitMQ channel exceptions and polluted broker logs.

TPS-74 deep evidence:

- The intended Redis hot-path cleanup took effect:
  - `match_engine_add_order_duration_seconds_count=0`;
  - `match_engine_add_order_duration_seconds_sum=0.0`.
- Combined reserve-or-add is now counted under the reserve timer:
  - `match_engine_reserve_order_duration_seconds_count=20000`;
  - `match_engine_reserve_order_duration_seconds_sum=23.651443`.
- MatchEngine DB connection acquisition is not the bottleneck:
  - `hikaricp_connections_acquire_seconds_count=12756`;
  - `hikaricp_connections_acquire_seconds_sum=0.142`;
  - `hikaricp_connections_acquire_seconds_max=0.020`.
- Match DB top statements are still small per call:
  - trade execution/outbox CTE: `10000` calls, `1319.40ms` total, `0.1319ms` mean;
  - completion marker insert: `2354` calls, `1053.59ms` total, `0.4476ms` mean.
- Wallet settlement SQL is not a single slow statement, but it remains a large fixed per-trade cost:
  - settlement CTE: `10000` calls, `1821.39ms` total, `0.1821ms` mean;
  - settlement processing timer: `17.455739s` total;
  - settlement transaction timer: `17.089347s` total.
- Outbox relay/drain is now the main tail candidate:
  - Match outbox batch: `21` batches, `14.490855s` total;
  - Order outbox batch: `21` batches, `16.357323s` total;
  - Wallet outbox batch: `21` batches, `16.405692s` total;
  - business gate is still dominated by final ready+unacked drain, around `21.4s`.

Interpretation:

- Keep TPS-74. It improves the valid 10k sample versus TPS-73 from `390.20` to `463.42` business TPS and from `515.78` to `689.84` completion-marker TPS.
- It also removes the explicit second no-match Redis add call in the two-phase workload.
- R1 must be excluded from service capacity comparison because the driver under-offered; the new driver metrics explain why.
- The next TPS target should be outbox relay/drain cost and completion-tail attribution across MatchEngine, Order, and Wallet. Do not return to blind consumer concurrency tuning unless queue, DB, or outbox timers show under-parallelism rather than publish/confirm/drain tail.

### TPS-75 - Final Queue Drain Attribution

Status: **diagnostic implemented and validated**

Problem:

- TPS-74 showed `businessCompletionSeconds` around `21.4s`, but the result JSON only reported aggregate ready/unacked peaks and final zero backlog.
- That made the final tail hard to attribute:
  - a real ready backlog;
  - in-flight unacked consumer work;
  - RabbitMQ management sampling lag;
  - or a downstream completion-marker bottleneck.
- Re-tuning consumer concurrency without this attribution risks repeating previous invalid/regressed runs.

Implementation:

- Added per-queue final-drain attribution to `MatchedE2eLoadGenerator`.
- New result JSON fields:
  - `lastNonZeroQueue`;
  - `lastNonZeroQueueKind`;
  - `lastNonZeroQueueSeconds`;
  - `lastNonZeroQueueReady`;
  - `lastNonZeroQueueUnacked`;
  - `queueDrainTailAfterCompletedTradesSeconds`;
  - `queueDrainTimeline`.
- The tracker reuses the existing 100ms queue snapshot loop, so it does not add extra RabbitMQ or DB polling.

Verification:

- Compile:
  - `GRADLE_USER_HOME=/Users/cfh00909120/Desktop/eap-workspace/.cache/gradle ./gradlew --no-daemon testClasses` in `eap-order`.
- Smoke:
  - `GLT_20260720_DRAIN_ATTR_SMOKE`;
  - `completedTrades=10`;
  - final backlog `0`;
  - new JSON fields were emitted.
- 10k light attribution:
  - `GLT_20260720_DRAIN_ATTR_10K_R1`;
  - `actualBuyPublishTps=1998.72`;
  - `businessMatchedE2eTps=470.29`;
  - `queueReadyDrainedSeconds=7.11`;
  - `completedTradesReachedSeconds=15.64`;
  - `queueFullyDrainedSeconds=21.26`;
  - `queueDrainTailAfterCompletedTradesSeconds=5.62`;
  - `finalQueueBacklog=0`;
  - `remainingSellOrders=0`;
  - `remainingBuyOrders=0`;
  - `activeReservations=0`.

Attribution result:

- The final tail is not a `messages_ready` backlog:
  - ready queues drained by `7.11s`;
  - the business gate waited until `21.26s` because unacked messages remained.
- The last observed non-zero queue was:
  - `lastNonZeroQueue=matchEngine.walletTradeSettled.queue`;
  - `lastNonZeroQueueKind=unacked`;
  - `lastNonZeroQueueSeconds=20.78`;
  - `lastNonZeroQueueUnacked=96`.
- Other late unacked queues at the same timestamp:
  - `matchEngine.orderTradeApplied.queue`: `68`;
  - `wallet.tradeExecuted.queue`: `29`.
- Earlier queues were already gone:
  - `matchEngine.orderConfirmed.queue` last unacked at `15.79s`;
  - `order.tradeExecuted.queue` last unacked at `15.79s`.

Outbox relay evidence in the same run:

- Match outbox:
  - `trade_outbox_batch_duration_seconds_count=21`;
  - `trade_outbox_batch_duration_seconds_sum=12.634413`;
  - `trade_outbox_confirm_duration_seconds_sum=12.005753`.
- Order outbox:
  - `eap_order_outbox_batch_duration_seconds_count=21`;
  - `eap_order_outbox_batch_duration_seconds_sum=14.468215`;
  - `eap_order_outbox_publish_enqueue_duration_seconds_sum=13.220501`.
- Wallet outbox:
  - `eap_wallet_outbox_batch_duration_seconds_count=22`;
  - `eap_wallet_outbox_batch_duration_seconds_sum=14.422145`;
  - `eap_wallet_outbox_publish_enqueue_duration_seconds_sum=13.258294`.

Interpretation:

- The `21s` run time is no longer an unknown full-chain delay.
- The chain reaches core business facts at `15.64s`, then spends another `5.62s` waiting for measured RabbitMQ unacked messages to reach zero.
- The late tail is concentrated in MatchEngine completion-marker consumers, especially `walletTradeSettled`, plus some `orderTradeApplied`.
- Order/Wallet `TradeExecuted` consumers are not the final tail in this run, although their outbox relay publish/enqueue cost remains large fixed work.
- Next optimization should inspect MatchEngine `TradeCompletionListener` / completion-marker listener work and ack timing before changing broad service concurrency.
- Keep outbox relay as a parallel investigation, but do not treat `*_outbox_publish_duration_seconds_sum` as wall-clock because that metric records per-message batch lifetime and overcounts shared batch time.

### TPS-76 - Strict Completion Timing and Marker Listener Metrics

Status: **diagnostic fixed and 10k light run validated**

Problem:

- TPS-75 showed the final `messages_unacknowledged` tail, but two measurement gaps remained:
  - `completedTradesReachedSeconds` used a lower-bound count:
    `LEAST(trade_executions, ORDER_APPLIED markers, WALLET_SETTLED markers)`;
  - `trade_completion_marker_*` actuator metrics were expected in diagnostics but were missing.
- Without strict per-trade completion timing and marker listener metrics, the `21s` business gate could still be misread as SQL, ACK, or RabbitMQ management lag.

Implementation:

- Added strict completion timing to `MatchedE2eLoadGenerator`:
  - `strictCompletedTradesReachedSeconds`;
  - `strictCompletionMarkerReachTps`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds`.
- The strict check uses the existing per-trade `EXISTS` query for both `ORDER_APPLIED` and `WALLET_SETTLED`, but only after the cheaper lower-bound count reaches the expected event count.
- Added MatchEngine completion-marker listener wall-clock metrics:
  - `trade_completion_marker_listener_duration`.
- Fixed missing marker metrics:
  - `TradeCompletionMarkerMetrics` had both a public `MeterRegistry` constructor and a private no-arg constructor used by `noop()`;
  - Spring selected the no-arg constructor, creating empty metric maps and skipping meter registration;
  - the `MeterRegistry` constructor is now explicitly annotated with `@Autowired`.

Verification:

- Compile:
  - `eap-order`: `./gradlew --no-daemon testClasses`;
  - `eap-matchEngine`: `./gradlew --no-daemon testClasses`.
- Unit test:
  - `./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest`.
- Actuator check after fix:
  - `/match-engine/actuator/metrics/trade_completion_marker_batches` returns `ORDER_APPLIED` and `WALLET_SETTLED` tags;
  - `/match-engine/actuator/metrics/trade_completion_marker_listener_duration` returns `COUNT`, `TOTAL_TIME`, and `MAX`.
- Smoke:
  - `GLT_20260720_MARKER_METRICS_STRICT_SMOKE`;
  - `completedTrades=10`;
  - `strictCompletedTradesReachedSeconds=0.42`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=0.00`;
  - final queues and DLQ were `0`.

10k light run:

- Run:
  - `GLT_20260720_STRICT_MARKER_METRICS_10K_R1`;
  - `EVENTS=10000`;
  - `TARGET_TPS=2000`;
  - `DURATION_SECONDS=5`;
  - `PUBLISHERS=128`;
  - `DIAGNOSTICS_LEVEL=light`.
- Result:
  - `actualBuyPublishTps=1999.12`;
  - `businessMatchedE2eTps=531.30`;
  - `businessCompletionSeconds=18.82`;
  - `tradeExecutionsReachedSeconds=9.81`;
  - `walletSettlementsReachedSeconds=12.37`;
  - `orderMatchedReachedSeconds=13.47`;
  - `completedTradesReachedSeconds=15.48`;
  - `strictCompletedTradesReachedSeconds=15.48`;
  - `queueFullyDrainedSeconds=18.82`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=3.34`;
  - final queues/DLQ `0`;
  - `remainingSellOrders=0`;
  - `remainingBuyOrders=0`;
  - `activeReservations=0`.

Marker listener metrics:

- `ORDER_APPLIED`:
  - batches: `1592`;
  - events: `10000`;
  - insert duration sum: `1.651647s`;
  - listener duration sum: `2.533001s`.
- `WALLET_SETTLED`:
  - batches: `809`;
  - events: `10000`;
  - insert duration sum: `1.020010s`;
  - listener duration sum: `1.390127s`.

Attribution:

- Strict completion and lower-bound completion reached at the same sampled time: `15.48s`.
- Therefore, the previous concern that `completedTradesReachedSeconds` was overly optimistic is not supported in this run.
- Marker listener work is real but not large enough to explain the whole final drain:
  - total listener wall-clock sum across both marker types is about `3.92s`;
  - total insert SQL time across both marker types is about `2.67s`;
  - the final strict-completion-to-drain tail is `3.34s`.
- The last non-zero queue remains:
  - `lastNonZeroQueue=matchEngine.walletTradeSettled.queue`;
  - `lastNonZeroQueueKind=unacked`;
  - `lastNonZeroQueueSeconds=18.41`;
  - `lastNonZeroQueueUnacked=160`.

Interpretation:

- The measured `18.82s` completion time is now better attributed:
  - front half: MatchEngine trade execution/publish plus Order/Wallet apply/settle reaches strict business completion at `15.48s`;
  - tail: about `3.34s` of final RabbitMQ unacked drain, concentrated in MatchEngine completion-marker queues.
- The result is materially better than TPS-75 (`531.30` vs `470.29` business TPS), but treat it as a diagnostic single run, not a new accepted average.
- The next performance work should not be broad concurrency tuning. The useful targets are:
  - reduce completion-marker batch fragmentation (`1592` ORDER batches and `809` WALLET batches for `10000` events);
  - inspect Spring AMQP batch listener receive timeout / batch-size behavior for completion marker queues;
  - compare this against a deep run to see whether DB, RabbitMQ ACK, or listener batching dominates the remaining `3.34s` tail.

### TPS-77 - Completion Marker Batch Tuning and Overfitting Check

Status: **investigated; do not treat marker listener tuning as the main TPS fix**

Question:

- TPS-76 showed completion-marker batch fragmentation, but tuning AMQP batch parameters risks overfitting to the `10k / 5s` burst workload.
- The validation must answer two separate questions:
  - does larger batching reduce marker SQL/listener overhead;
  - does it improve the full business gate across a longer workload, including final ready+unacked queue drain.

10k isolation runs:

| Run | Marker batch / timeout | business TPS | strict completion | final drain | strict-to-drain tail | Marker batches ORDER/WALLET | Interpretation |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_20260720_STRICT_MARKER_METRICS_10K_R1` | `50 / 25ms` | `531.30` | `15.48s` | `18.82s` | `3.34s` | `1592 / 809` | Baseline with fixed strict timing and marker metrics. |
| `GLT_20260720_MARKER_BATCH100_TIMEOUT75_10K_R1` | `100 / 75ms` | `456.40` | `13.74s` | `21.91s` | `8.17s` | `920 / 467` | Bigger batches reduce marker writes but worsen final unacked drain. Reject this timeout. |
| `GLT_20260720_MARKER_BATCH100_TIMEOUT25_10K_R1` | `100 / 25ms` | `532.31` | `17.20s` | `18.79s` | `1.58s` | `1463 / 761` | Similar business TPS; smaller final tail, but no material throughput gain. |

30k cross-workload check:

| Run | Marker batch / timeout | events | offered TPS | business TPS | strict completion | final drain | strict-to-drain tail | Marker batches ORDER/WALLET | Marker listener sum ORDER/WALLET |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `GLT_20260720_MARKER_BASELINE_30K_R1` | `50 / 25ms` | `30000` | `1999.75` | `595.35` | `45.16s` | `50.39s` | `5.23s` | `4793 / 2553` | `10.675766s / 5.514799s` |
| `GLT_20260720_MARKER_BATCH100_TIMEOUT25_30K_R1` | `100 / 25ms` | `30000` | `1999.68` | `613.27` | `45.03s` | `48.92s` | `3.89s` | `4545 / 2413` | `7.714857s / 4.540345s` |

30k result details:

- Baseline:
  - `businessMatchedE2eTps=595.35`;
  - `businessCompletionSeconds=50.39`;
  - `strictCompletedTradesReachedSeconds=45.16`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=5.23`;
  - final queues/DLQ and order/reservation invariants were clean.
- Batch `100 / 25ms`:
  - `businessMatchedE2eTps=613.27`;
  - `businessCompletionSeconds=48.92`;
  - `strictCompletedTradesReachedSeconds=45.03`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=3.89`;
  - final queues/DLQ and order/reservation invariants were clean.

Interpretation:

- The overfitting concern is valid:
  - `100 / 75ms` looks good if only marker batch count is inspected, but it regresses full business TPS because messages remain unacked longer at the tail.
  - Therefore, marker tuning must be judged by strict business completion plus final ready+unacked drain, not by marker insert count alone.
- `100 / 25ms` is a reasonable candidate:
  - it reduced marker batch count and listener wall-clock sums in the `30k` run;
  - it improved full business TPS from `595.35` to `613.27`, about `+3.0%`;
  - it reduced strict-to-drain tail from `5.23s` to `3.89s`.
- The improvement is too small to call this the main TPS fix:
  - marker listener batching reduces local write overhead;
  - the dominant end-to-end path is still MatchEngine `orderConfirmed` consumption, durable `TradeExecuted` persistence/outbox, and Order/Wallet `TradeExecuted` application/settlement.
- Do not tune broad service concurrency from this data. This experiment changed the marker listener batch/timeout behavior only.

Decision:

- Keep `75ms` timeout rejected for completion marker listeners.
- Treat batch size `100` with `25ms` timeout as a candidate low-risk loadtest-profile setting, but require at least one more repeated `30k` run before accepting it as a default.
- Continue the main TPS investigation on fixed durable write cost:
  - MatchEngine order-confirmed consumption and trade execution/outbox writes;
  - Order and Wallet `TradeExecuted` consumer SQL;
  - whether completion marker durability can be made cheaper without weakening the current business completion gate.

### TPS-78 - Durable Write Necessity Audit

Status: **opened**

Problem:

- TPS-77 showed completion-marker batch tuning is only a small local improvement.
- The remaining throughput ceiling is still fixed durable write amplification:
  - each completed trade creates multiple service-owned facts;
  - each fact also creates retry/idempotency/outbox evidence;
  - some of these writes are domain-required, while others may be historical safety tables that can be merged, derived, or moved out of the business hot path.
- The goal is not to remove reliability mechanisms blindly. The goal is to classify each write by business necessity and then remove only redundant durable writes.

Current load-test hot path:

| Service | Current writes per trade | Why it exists | Initial classification |
| --- | --- | --- | --- |
| MatchEngine | `trade_executions` insert | Durable trade fact; source of truth for `TradeExecuted`. | Required. |
| MatchEngine | `trade_outbox` insert + `SENT` update | Reliable publication of `TradeExecuted` to Order/Wallet. | Required unless replaced by an equally reliable publish model. |
| MatchEngine | `trade_completion_markers` inserts `ORDER_APPLIED` + `WALLET_SETTLED` | Completion evidence from downstream services. | Required for current business gate, but may be optimizable. |
| MatchEngine | `trade_completion_view` insert/update | Delayed detection and reconciliation state. | Already disabled in loadtest hot path via `trade-completion-view.hot-path-enabled=false`; not current main bottleneck. |
| Order | `order_trade_applications` insert | One-trade idempotency claim for applying buyer/seller order state in the current `trade-application` loadtest profile. | Required for the current hot path unless another durable claim can prove duplicate `TradeExecuted` redelivery will not re-apply order state. |
| Order | `order_matching_state` updates for buyer and seller | Command-side order state for cancel/business decisions and fast apply. | Required if cancel and matching state must be authoritative without waiting for projection. |
| Order | `order_event_outbox` insert + `SENT` update | Reliable `OrderTradeApplied` completion marker. | Required for current completion gate. |
| Order | `order_event_store` inserts | Event-sourced order lifecycle history. | Not written by the current `TradeExecuted` apply hot path; still used by non-TradeExecuted order lifecycle commands. |
| Order | `order_stream_heads` updates | Aggregate version/hash/state progression. | Not written by the current `TradeExecuted` apply hot path; still used by non-TradeExecuted order lifecycle commands. |
| Wallet | `trade_settlements` insert | Settlement idempotency and durable settlement evidence. | Candidate: necessary evidence, but table shape can be reviewed for redundant surrogate key/index cost. |
| Wallet | `wallets` buyer/seller updates | Actual balance and locked-asset mutation. | Required. |
| Wallet | `outbox` insert + `SENT` update | Reliable `WalletTradeSettled` completion marker. | Required for current completion gate. |

Key observation:

- The current 30k evidence says the full chain is about `595-613` completed trades/s locally with clean final gates.
- Marker listener tuning can reduce tail by about `1-1.3s` in 30k, but does not change the dominant per-trade write shape.
- The next meaningful TPS work must attack one of:
  - one durable write row per trade;
  - one durable status update per published event;
  - one unique-index write per idempotency table;
  - one pair of Order aggregate/event/head writes per trade.

Audit rules:

- A write is **required** if removing it can create one of:
  - duplicate settlement;
  - lost `TradeExecuted` publication;
  - lost Order or Wallet completion evidence;
  - incorrect cancel/business decision;
  - unrebuildable order or wallet state.
- A write is **candidate redundant** if:
  - the same uniqueness guarantee already exists in another hot-path table;
  - the row is only used for diagnostics or projection;
  - the row can be derived from `trade_executions`, Order event store, Wallet settlement evidence, or outbox state;
  - the table has a surrogate primary key plus a unique business key, and runtime code only uses the business key.
- A write is **not removable** just because it is expensive. It needs an alternative correctness proof.

Next tasks:

| Task | Priority | Owner | Acceptance |
| --- | --- | --- | --- |
| TPS-78-01 Confirm runtime hot-path writes from PostgreSQL stats | P0 | Performance | One 10k or 30k light run includes table-level inserts/updates for MatchEngine, Order, Wallet after seed reset. |
| TPS-78-02 Review Order `order_trade_applications` necessity | P0 | Architect + Performance | Decide whether deterministic `OrderMatchedV1` event IDs can replace the trade-application table without duplicate apply or partial-update risk. Include why previous link/idempotency attempts regressed. |
| TPS-78-03 Review Wallet `trade_settlements` schema shape | P0 | Performance | Confirm whether surrogate `id` plus unique `trade_id` creates avoidable extra index writes; propose `trade_id` primary key if runtime never reads by `id`. |
| TPS-78-04 Review completion marker durability model | P1 | Architect | Compare current two marker rows per trade vs one aggregate completion evidence row; preserve out-of-order marker arrival and delayed detection. |
| TPS-78-05 Review outbox status update cost | P1 | Performance | Measure insert and mark-sent update cost for Match/Order/Wallet outboxes; propose cheaper relay state only if recovery semantics remain explicit. |
| TPS-78-06 Pick one smallest safe implementation | P0 | Implementation Lead | Implement only one write-shape reduction, add duplicate/retry tests, then run 10k and 30k comparison. |

Initial preferred target:

- Start with Wallet `trade_settlements` table shape:
  - it is a narrow, isolated idempotency/evidence table;
  - it likely does not need both surrogate `id` primary-key index and unique `trade_id` index;
  - changing it to `trade_id` primary key should reduce one B-tree write per settled trade if no runtime code depends on `id`.
- Second target is Order `order_trade_applications`, but only after an architecture review:
  - it may be redundant with deterministic event IDs;
  - however, it currently gates a multi-row Order state mutation, so removing it incorrectly can reintroduce duplicate application or partial apply risks.

Code inspection update on 2026-07-20:

- Wallet `trade_settlements`:
  - runtime settlement uses `WalletTradeSettlementAppender` JDBC CTE with `ON CONFLICT (trade_id) DO NOTHING`;
  - `TradeSettlementRepository` has no runtime callers in the current code scan;
  - schema still has both `id BIGSERIAL PRIMARY KEY` and `uk_trade_settlements_trade_id`;
  - this matches the old MatchEngine `trade_executions` shape that was already optimized in `match-trade-011` by making `trade_id` the primary key.
- Order `trade-application` loadtest path:
  - Order no longer has a selectable `trade-idempotency-source`; `trade-application` is the only supported `TradeExecuted` apply path;
  - PostgreSQL stats from the latest 30k run showed `order_event_store=0` inserts and `order_stream_heads=0` updates;
  - current hot-path writes were `order_trade_applications=30000` inserts, `order_matching_state=60000` updates, and `order_event_outbox=30000` inserts plus `30000` status updates;
  - therefore, the immediate Order question is not whether to remove event-store writes from this path. They are already absent. The harder future question is whether `order_trade_applications` can be replaced by an equally safe durable idempotency claim.
- MatchEngine completion:
  - `trade_completion_view.hot-path-enabled=false` in the loadtest profile, so the synchronous completion view is not part of current TPS cost;
  - `trade_completion_markers` remain part of the business completion gate and are the main MatchEngine completion-evidence write.

Implementation update on 2026-07-20:

- Implemented Wallet `trade_settlements` schema cleanup:
  - added `wallet-015` Liquibase changeset;
  - dropped redundant `uk_trade_settlements_trade_id`;
  - changed `trade_settlements_pkey` from `id` to `trade_id`;
  - dropped the `id` column;
  - updated `TradeSettlementEntity` and `TradeSettlementRepository` to use `String tradeId` as the JPA identifier.
- Verification:
  - `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest --tests com.eap.eap_wallet.application.OutboxPollerTest` passed;
  - `eap-wallet ./gradlew --no-daemon test` passed;
  - Wallet `bootRun --spring.profiles.active=loadtest` applied `wallet-015` successfully against the local loadtest DB;
  - post-migration DB inspection showed `trade_settlements` columns `trade_id`, `legacy_match_id`, `settled_at` and only one index: `trade_settlements_pkey` on `trade_id`.
- Note:
  - a minimal old smoke command failed before settlement because MatchEngine was not running and left `10` messages in `matchEngine.orderConfirmed.queue`;
  - the queue was purged afterward and confirmed at `messages_ready=0`.

### TPS-79 - Order Hot Path Pruning and Load-Test Mode Definitions

Status: **implemented**

Problem:

- Order still carried multiple retired `TradeExecuted` apply paths:
  - links mode through `order_execution_links`;
  - event-store idempotency mode through deterministic `OrderMatchedV1` event IDs;
  - current trade-application mode through `order_trade_applications`.
- Keeping all three modes made the architecture ambiguous:
  - production defaults and loadtest defaults could diverge;
  - old code paths could be accidentally re-enabled;
  - benchmark numbers were harder to explain because "current hot path" was not the only executable path.

Architecture decision:

- Order `TradeExecuted` apply now has one supported command hot path:
  - insert `order_trade_applications` by `trade_id` as the durable idempotency claim;
  - update buyer/seller `order_matching_state` in the same transaction;
  - insert one `order_event_outbox` row for `OrderTradeApplied`.
- `order_matching_state` is command-side state, not a projection:
  - cancel/business decisions read it before writing;
  - it is allowed to be in the write side because it affects command validity.
- Order event sourcing remains for order lifecycle commands:
  - request;
  - asset reservation confirmed/failed;
  - cancel.
- Order event-store writes are no longer part of the high-throughput `TradeExecuted -> OrderTradeApplied` hot path.

Implementation:

- Removed Order service feature flags:
  - `eap.order.event-sourcing.trade-idempotency-source`;
  - `eap.order.event-sourcing.fast-match-from-projection.enabled`.
- Removed retired Order code:
  - `OrderTradeExecutionLink`;
  - `OrderExecutionLinkEntity`;
  - `OrderExecutionLinkRepository`;
  - Order appender links-mode APIs and private SQL;
  - Order appender event-store-idempotency APIs and private SQL;
  - unused prepared append helpers for the retired trade-application + event-store/head variant.
- Added Liquibase `order-es-017`:
  - drops `order_service.order_execution_links` for upgraded databases.
- Removed `order_execution_links` from loadtest truncation and Order integration tests.

Verification:

- `eap-order ./gradlew --no-daemon testClasses` passed.
- `eap-order ./gradlew --no-daemon test --rerun-tasks` passed.
- `eap-order` loadtest-profile boot applied Liquibase `order-es-017`; `order_service.order_execution_links` no longer exists on the upgraded local database.

Current Order `TradeExecuted` write model:

| Table | Per completed trade | Required role |
| --- | ---: | --- |
| `order_trade_applications` | `1 insert` | Trade-level durable idempotency claim. |
| `order_matching_state` | `2 updates` | Buyer/seller command-side order state. |
| `order_event_outbox` | `1 insert + 1 SENT update` | Reliable `OrderTradeApplied` completion marker publication. |
| `order_event_store` | `0` in this path | Still used by other order lifecycle commands, not by `TradeExecuted` apply. |
| `order_stream_heads` | `0` in this path | Still used by other event-sourced order commands. |
| `order_execution_links` | `0`; table retired | Replaced by `order_trade_applications`. |

Load-test mode definitions:

| Mode | Purpose | Main flags / behavior | Valid claim |
| --- | --- | --- | --- |
| `hot-path baseline` | Measures optimized business hot path with low observer overhead. | `DIAGNOSTICS_LEVEL=baseline` or `light`; Order projection enabled but not a hard business gate; MatchEngine completion view hot-path disabled; completion markers and final queue drain are hard gates. | "marker-gated completed business TPS" for the optimized architecture. |
| `production-like steady` | Checks whether background/read-model work stays healthy under sustained load. | Same business gate, but projection lag, queue lag, outbox pending/failed, and optional reconciler behavior must be reported. | "production-like completed TPS" only if enabled background jobs and lag budgets are disclosed. |
| `diagnostics deep` | Finds bottlenecks, attribution, SQL/Rabbit/JVM signals. | `DIAGNOSTICS_LEVEL=deep`; extra snapshots and metrics may add observer overhead. | Not a headline TPS number; use for bottleneck attribution. |
| `legacy comparison` | Historical only. | Old links/event-store idempotency paths are removed from code. | Not supported going forward. |

Benchmark naming rule:

- Do not call the current result "fully production synchronized TPS" unless the run includes every production-required background/read-model path and reports its lag budget.
- Current headline should be phrased as:
  - `correctness-gated completed trades/s`;
  - with completion defined by durable `TradeExecuted`, Order applied marker, Wallet settled marker, final measured RabbitMQ ready+unacked drain, and DLQ `0`.
- If `trade_completion_view.hot-path-enabled=false`, say explicitly:
  - completion is marker-gated;
  - `trade_completion_view` is a derived/read or reconciliation view, not part of the synchronous business gate.

### TPS-80 - Retire Legacy `OrderMatchedEvent` Runtime Bus

Status: **implemented**

Problem:

- Wallet and MatchEngine still carried the old `order.matched` integration path:
  - MatchEngine could directly publish `OrderMatchedEvent` through `order.exchange / order.matched`;
  - Wallet still declared `wallet.orderMatched.queue` and consumed it through `MatchedOrderListener`;
  - Order still declared `order.orderMatched.queue` and consumed it through `MatchEventListener`;
  - old DB/load-test tasks could still benchmark the retired `OrderMatchedEvent` path.
- This made the active architecture ambiguous because the current business-completion contract is based on:
  - `TradeExecutedEvent`;
  - `OrderTradeAppliedEvent`;
  - `WalletTradeSettledEvent`;
  - completion markers and final queue drain.

Architecture decision:

- `OrderMatchedEvent` is no longer a runtime integration event.
- MatchEngine is the source of durable trade facts through `TradeExecutedEvent`.
- Order and Wallet react to `TradeExecutedEvent` independently and publish trade-completion markers through their current outbox paths.
- The `order.matched` bus, wallet/order matched queues, and old matched DB micro-benchmarks are retired.

Implementation:

- MatchEngine:
  - removed `legacy-order-matched-publish` configuration and direct `RabbitTemplate` publish from `MatchingEngineService`;
  - removed `match_engine_legacy_publish_duration`;
  - removed `matchEngineAmqpLoadTest` and `MatchEngineAmqpLoadGenerator`;
  - changed `MatchEngineCoreLoadGenerator` to count captured `TradeExecutedEvent` records instead of captured legacy `OrderMatchedEvent` publishes.
- Wallet:
  - removed `MatchedOrderListener`;
  - removed `wallet.orderMatched.queue` declaration and binding;
  - removed `walletMatchedDbLoadTest` and `WalletMatchedDbLoadGenerator`;
  - removed loadtest listener/log settings for the retired matched listener.
- Order:
  - removed `MatchEventListener`;
  - removed `order.orderMatched.queue` declaration and binding;
  - removed `orderMatchedDbLoadTest` and `OrderMatchedDbLoadGenerator`;
  - removed the legacy `OrderEventSourcingService.match(UUID, OrderMatchedEvent)` entry point;
  - removed old matched queues from the global E2E load-test queue snapshot, purge, and drain tracker.
- Common:
  - removed `OrderMatchedEvent`;
  - removed retired `order.matched` routing key and matched queue constants.
- Load-test tooling:
  - changed `purge-eap-queues.sh` from broad `order|wallet|matchEngine` queue discovery to a current queue allowlist;
  - removed retired matched queue fields from repeat-run final backlog aggregation.
- Local RabbitMQ environment:
  - deleted empty retired queues `order.orderMatched.queue` and `wallet.orderMatched.queue`.

Current runtime event flow:

```text
OrderSubmitted
  -> Wallet OrderConfirmed
  -> MatchEngine TradeExecuted + trade_outbox
  -> Order TradeExecuted consumer -> OrderTradeApplied outbox
  -> Wallet TradeExecuted consumer -> WalletTradeSettled outbox
  -> MatchEngine completion markers
```

Verification:

- `eap-common ./gradlew --no-daemon testClasses` passed.
- `eap-order ./gradlew --no-daemon testClasses` passed.
- `eap-order ./gradlew --no-daemon test` passed.
- `eap-wallet ./gradlew --no-daemon testClasses` passed.
- `eap-wallet ./gradlew --no-daemon test` passed.
- `eap-matchEngine ./gradlew --no-daemon testClasses` passed.
- `eap-matchEngine ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.MatchingEngineServiceTest --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest` passed.
- `eap-matchEngine ./gradlew --no-daemon test` still has an unrelated `contextLoads()` Redisson test-environment failure; targeted tests and compile pass.
- `EVENTS=10 PUBLISHERS=2 DIAGNOSTICS_LEVEL=light MARKET_ID=GLT_TPS80_SMOKE_10 bash scripts/load-test/run-2000-ticket-marker-10k.sh` passed with `completedTrades=10`, `tradeExecutions=10`, `walletTradeSettlements=10`, `finalQueueBacklog=0`, and no retired matched queue in the in-generator queue gate.
- `TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 DIAGNOSTICS_LEVEL=light RESET_PG_STATS_BEFORE_RUN=true MARKET_ID=GLT_TPS80_LIGHT_10K_R1 bash scripts/load-test/run-2000-ticket-marker-10k.sh` passed after the runtime bus cleanup:
  - `actualBuyPublishTps=1998.98`, `validForCapacityComparison=true`;
  - `businessMatchedE2eTps=417.32`, `businessCompletionSeconds=23.96`, `drainSecondsAfterBuyPublish=18.96`;
  - `tradeExecutionReachTps=719.48`, `orderCommandMatchReachTps=571.54`, `walletSettlementReachTps=571.54`, `completionMarkerReachTps=539.68`;
  - correctness counts matched the expected 10k trades: `tradeExecutions=10000`, `completedTrades=10000`, `orderCommandMatchedRows=20000`, `walletTradeSettlements=10000`;
  - final invariants held: `finalQueueBacklog=0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`;
  - `trade_completion_view` remains disabled in the loadtest hot path and is not the hard business gate; completed business throughput is marker-gated by durable `TradeExecuted` plus `ORDER_APPLIED` and `WALLET_SETTLED` markers.

Post-run bottleneck signal:

- Completion markers reached expected count at `18.53s`, but full ready+unacked drain finished at `23.96s`.
- The queue drain tail after completed markers was `5.43s`.
- The last non-zero queue was `wallet.tradeExecuted.queue` unacked; measured queue peaks were:
  - `maxMatchEngineQueueReady=3699`;
  - `maxMatchEngineQueueUnacked=700`;
  - `maxOrderTradeExecutedQueueUnacked=309`;
  - `maxWalletTradeExecutedQueueUnacked=113`.
- Next investigation should focus on downstream ack/transaction tail latency, especially Wallet `TradeExecuted` listener settlement and outbox mark-sent behavior, rather than re-running broad consumer-concurrency experiments.

### TPS-81 - Wallet Batch-Level Publisher Confirm Experiment

Status: **rejected and reverted**

Hypothesis:

- TPS-80 showed a visible downstream drain tail after completion markers converged.
- Wallet and Order outbox relay metrics showed high cumulative publish/enqueue time compared with broker confirm time.
- A narrower Wallet-only experiment tested whether replacing per-message confirm waiting with a chunk-level `RabbitTemplate.invoke(...) + waitForConfirmsOrDie(...)` confirm could reduce Wallet outbox relay tail latency without changing business semantics.

Temporary implementation:

- Changed Wallet `OutboxPoller` to:
  - partition a pending outbox batch into chunks;
  - publish each chunk through a scoped `RabbitTemplate.invoke(...)`;
  - wait once per chunk with `waitForConfirmsOrDie(confirmTimeoutMs)`;
  - mark the chunk `SENT` only after the batch confirm succeeded;
  - retain retry behavior for the whole chunk on publish/confirm failure.
- The correctness model stayed at-least-once:
  - a crash or failed confirm before `SENT` leaves rows retryable;
  - duplicate downstream delivery remains absorbed by consumer idempotency.

Validation:

- Focused Wallet test passed:
  - `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.OutboxPollerTest`.
- 500-event smoke passed:
  - `EVENTS=500 PUBLISHERS=32 TARGET_TPS=1000 DURATION_SECONDS=1 DIAGNOSTICS_LEVEL=light RESET_PG_STATS_BEFORE_RUN=true MARKET_ID=GLT_TPS81_WALLET_BATCH_CONFIRM_SMOKE_500 bash scripts/load-test/run-2000-ticket-marker-10k.sh`;
  - `businessMatchedE2eTps=451.46`, `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, `orderCommandMatchedRows=1000`, `finalQueueBacklog=0`.

10k comparison:

| Metric | TPS-80 baseline | TPS-81 Wallet batch confirm |
| --- | ---: | ---: |
| `actualBuyPublishTps` | `1998.98` | `1943.72` |
| `validForCapacityComparison` | `true` | `true` |
| `businessMatchedE2eTps` | `417.32` | `344.53` |
| `businessCompletionSeconds` | `23.96s` | `29.02s` |
| `drainSecondsAfterBuyPublish` | `18.96s` | `23.88s` |
| `tradeExecutionReachTps` | `719.48` | `513.59` |
| `orderCommandMatchReachTps` | `571.54` | `460.99` |
| `walletSettlementReachTps` | `571.54` | `460.99` |
| `completionMarkerReachTps` | `539.68` | `440.15` |
| `completedTrades` | `10000` | `10000` |
| `finalQueueBacklog` | `0` | `0` |
| `queueDrainTailAfterCompletedTradesSeconds` | `5.43s` | `6.31s` |
| `lastNonZeroQueue` | `wallet.tradeExecuted.queue` | `matchEngine.orderTradeApplied.queue` |

Decision:

- Reject and revert the Wallet batch-level confirm implementation.
- Correctness held, but the 10k business result regressed materially:
  - completed business throughput dropped from `417.32` to `344.53` trades/s;
  - marker convergence dropped from `539.68` to `440.15` markers/s;
  - full drain expanded from `23.96s` to `29.02s`.
- This confirms that Wallet outbox publisher-confirm API micro-optimization is not the current high-confidence TPS lever.
- The next target should stay on durable write-count and downstream transaction-tail reduction:
  - Wallet `TradeExecuted` settlement/outbox transaction shape;
  - Order `TradeExecuted` apply marker/outbox write shape;
  - MatchEngine completion marker drain and final ack timing;
  - reliable reduction of per-trade outbox/marker writes, not broad consumer concurrency or publish API reshuffling.

### TPS-82 - Current Durable Write Attribution

Status: **diagnostic completed**

Run:

- `TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 TIMEOUT_SECONDS=360 DIAGNOSTICS_LEVEL=deep RESET_PG_STATS_BEFORE_RUN=true MARKET_ID=GLT_TPS82_DURABLE_WRITE_DEEP_10K_R1 bash scripts/load-test/run-2000-ticket-marker-10k.sh`

Result:

- `actualBuyPublishTps=1999.14`, `validForCapacityComparison=true`.
- `businessMatchedE2eTps=523.64`, `businessCompletionSeconds=19.10`.
- `tradeExecutionReachTps=950.21`, `orderCommandMatchReachTps=776.07`, `walletSettlementReachTps=776.07`, `completionMarkerReachTps=666.29`.
- Correctness held:
  - `tradeExecutions=10000`;
  - `completedTrades=10000`;
  - `orderCommandMatchedRows=20000`;
  - `walletTradeSettlements=10000`;
  - `finalQueueBacklog=0`;
  - `remainingSellOrders=0`;
  - `remainingBuyOrders=0`;
  - `activeReservations=0`.
- Final tail:
  - strict completion at `15.01s`;
  - full ready+unacked drain at `19.10s`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=4.09`;
  - last non-zero queue was `matchEngine.walletTradeSettled.queue` unacked.

DB attribution:

| Service | Dominant signal | Evidence |
| --- | --- | --- |
| MatchEngine | `trade_executions + trade_outbox` write CTE | `10000` calls, `1858.34ms` total SQL time. |
| MatchEngine | completion marker inserts | `2298` batch calls, `20000` marker rows, `812.30ms` total SQL time. |
| MatchEngine | trade outbox mark-sent | `19` main updates for `9500` rows, `163.69ms` SQL time. |
| Wallet | settlement CTE | `10000` calls, `1928.88ms` total SQL time; app timer `eap_wallet_trade_settlement_cte_duration_seconds_sum=8.697s`. |
| Wallet | outbox mark-sent | `19` main updates for `9500` rows, `237.72ms` SQL time. |
| Order | trade apply batches | app timer `batch_total=5.690s`; SQL appears split by dynamic batch sizes. |
| Order | outbox mark-sent | `19` main updates for `9500` rows, `298.41ms` SQL time. |

Interpretation:

- Hikari was not the limiter:
  - Wallet acquire sum `0.074s`, pending `0`;
  - Order consumer acquire sum `0.352s`, pending `0`;
  - Match acquire sum `0.210s`, pending `0`.
- The highest-confidence next target is not another pool/concurrency change.
- The current cost is fixed durable write work:
  - one MatchEngine trade fact plus trade outbox row per trade;
  - one Wallet settlement/idempotency row plus two wallet row updates plus wallet outbox row per trade;
  - one Order trade-application claim plus two order state updates plus order outbox row per trade;
  - two MatchEngine completion marker rows per trade.
- Outbox mark-sent SQL is visible but small compared with the transaction/outbox wall-clock tail; changing confirm API was already rejected in TPS-81.

### TPS-83 - MatchEngine Trade Execution Unique-Index Cleanup

Status: **implemented; correctness accepted; no clear headline TPS lift**

Problem:

- TPS-82 showed `match_engine.trade_executions` still had extra uniqueness constraints after `trade_id` became the primary key:
  - `uk_trade_executions_legacy_match_id`;
  - `uk_trade_executions_market_sequence`.
- Code scan found no runtime query or business gate depending on either constraint:
  - `legacy_match_id` is carried for event compatibility/traceability;
  - `market_id, sequence` is persisted sequencing evidence;
  - idempotency is enforced by `trade_id`.
- These constraints create extra B-tree maintenance for every `TradeExecuted` insert.

Implementation:

- Added Liquibase `match-trade-012`:
  - drops `uk_trade_executions_legacy_match_id`;
  - drops `uk_trade_executions_market_sequence`;
  - keeps the columns.
- Verified the upgraded local loadtest DB:
  - `trade_executions` constraints now show only `trade_executions_pkey PRIMARY KEY (trade_id)`;
  - `trade_executions` indexes now show only `trade_executions_pkey`.

Verification:

- Focused tests passed:
  - `eap-matchEngine ./gradlew --no-daemon testClasses test --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest --tests com.eap.eap_matchengine.application.TradeCompletionServiceTest --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest`.
- Smoke passed:
  - `EVENTS=500 PUBLISHERS=32 TARGET_TPS=1000 DURATION_SECONDS=1 DIAGNOSTICS_LEVEL=light RESET_PG_STATS_BEFORE_RUN=true MARKET_ID=GLT_TPS83_MATCH_TRADE_INDEX_DROP_SMOKE_500 bash scripts/load-test/run-2000-ticket-marker-10k.sh`;
  - `completedTrades=500`, `tradeExecutions=500`, `walletTradeSettlements=500`, `orderCommandMatchedRows=1000`, `finalQueueBacklog=0`.
- 10k light passed:
  - `TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=light RESET_PG_STATS_BEFORE_RUN=true MARKET_ID=GLT_TPS83_MATCH_TRADE_INDEX_DROP_10K_R1 bash scripts/load-test/run-2000-ticket-marker-10k.sh`;
  - `actualBuyPublishTps=1998.24`, `validForCapacityComparison=true`;
  - `businessMatchedE2eTps=508.54`, `businessCompletionSeconds=19.66`;
  - `tradeExecutionReachTps=847.85`, `orderCommandMatchReachTps=718.11`, `walletSettlementReachTps=718.11`, `completionMarkerReachTps=620.18`;
  - `completedTrades=10000`, `tradeExecutions=10000`, `walletTradeSettlements=10000`, `orderCommandMatchedRows=20000`;
  - `finalQueueBacklog=0`, `remainingSellOrders=0`, `remainingBuyOrders=0`, `activeReservations=0`.

Decision:

- Keep the schema cleanup because it removes unused write amplification without weakening the current business completion gate.
- Do not claim it as a TPS breakthrough:
  - TPS-83 light was `508.54` completed trades/s;
  - TPS-82 deep was `523.64` completed trades/s before this cleanup;
  - recent run variance is large enough that this single light run cannot prove a capacity gain.
- The result reinforces the current direction:
  - removing small unused indexes is good hygiene;
  - the main bottleneck remains the required per-trade durable write chain and final unacked drain;
  - next work should focus on reducing one durable row/update from Order, Wallet, or completion-marker flow with a correctness proof.

### TPS-84 - Order Outbox Event-ID Unique Cleanup

Status: **implemented; correctness accepted; no headline TPS claim**

Problem:

- `order_service.order_event_outbox` still had `uk_order_outbox_event_id`.
- Current runtime idempotency no longer depends on outbox `event_id` uniqueness:
  - regular order-event append is protected by `order_event_store(event_id)`;
  - TradeExecuted application is protected by `order_trade_applications(trade_id)`;
  - outbox relay selects and marks rows by outbox `id`, not by `event_id`.
- Keeping the unique constraint adds one more B-tree maintenance path to every Order outbox insert.

Implementation:

- Added Liquibase `order-es-018` to drop `uk_order_outbox_event_id`.
- Verified local loadtest DB no longer has the redundant outbox unique constraint.

Verification:

- `eap-order ./gradlew --no-daemon testClasses` passed.
- `eap-order ./gradlew --no-daemon test --tests com.eap.eap_order.eventstore.OrderEventAppenderPostgresIT` passed.
- Smoke passed:
  - `GLT_TPS84_ORDER_OUTBOX_UNIQUE_DROP_SMOKE_500`;
  - `completedTrades=500`;
  - final ready/unacked backlog `0`.
- 10k light passed:
  - `GLT_TPS84_ORDER_OUTBOX_UNIQUE_DROP_10K_R1`;
  - `actualBuyPublishTps=1998.51`;
  - `businessMatchedE2eTps=378.77`;
  - `completionMarkerReachTps=549.79`;
  - `completedTrades=10000`;
  - final ready/unacked backlog `0`.

Decision:

- Keep the schema cleanup because it removes unused write amplification without weakening the business gate.
- Do not treat TPS-84 as a capacity regression by itself:
  - the run was slower than TPS-83, but the removed constraint is not on the observed tail path;
  - the run showed a large unacked tail and order-confirmed ready backlog, so it is a noisy local sample.

### TPS-85 - Order and Wallet Outbox Channel Reuse

Status: **implemented; correctness accepted; targeted relay cost removed**

Problem:

- MatchEngine relay already published chunks through `rabbitTemplate.invoke(...)`, but Order and Wallet relays still called `rabbitTemplate.send(...)` per row.
- In 10k runs, Order/Wallet `*_outbox_publish_enqueue_duration_seconds_sum` was in the `13-15s` class, while MatchEngine enqueue was below `1s`.
- This was a service-side relay implementation cost, not a consumer-concurrency problem.

Implementation:

- Changed Order `OrderEventOutboxRelay` and Wallet `OutboxPoller` to publish each batch/chunk inside `rabbitTemplate.invoke(...)`.
- Kept the existing correctness model:
  - per-message correlated publisher confirms remain;
  - rows are marked `SENT` only after broker confirmation;
  - failed confirms keep rows retryable;
  - downstream idempotency still absorbs duplicate delivery after crash/retry.
- Updated Wallet `OutboxPollerTest` to execute the `RabbitTemplate.invoke(...)` callback through the mocked template.

Verification:

- `eap-order ./gradlew --no-daemon testClasses` passed.
- `eap-wallet ./gradlew --no-daemon testClasses` passed.
- `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.OutboxPollerTest --tests com.eap.eap_wallet.application.TradeExecutedListenerTest` passed.
- Smoke passed:
  - `GLT_TPS85_OUTBOX_INVOKE_SMOKE_500`;
  - `businessMatchedE2eTps=402.43`;
  - `completedTrades=500`;
  - final ready/unacked backlog `0`.
- 10k light passed:
  - `GLT_TPS85_OUTBOX_INVOKE_10K_R1`;
  - `actualBuyPublishTps=1998.51`;
  - `businessMatchedE2eTps=478.77`;
  - `businessCompletionSeconds=20.89`;
  - `tradeExecutionReachTps=935.08`;
  - `orderCommandMatchReachTps=770.17`;
  - `walletSettlementReachTps=770.17`;
  - `completionMarkerReachTps=770.17`;
  - `completedTrades=10000`;
  - final ready/unacked backlog `0`.

Measured relay effect:

| Metric | TPS-83 reference | TPS-85 |
| --- | ---: | ---: |
| `eap_order_outbox_publish_enqueue_duration_seconds_sum` | `13.895584s` | `0.174310s` |
| `eap_wallet_outbox_publish_enqueue_duration_seconds_sum` | `13.564574s` | `0.169720s` |
| `eap_order_outbox_batch_duration_seconds_sum` | `15.440360s` | `10.686216s` |
| `eap_wallet_outbox_batch_duration_seconds_sum` | `15.344121s` | `10.782799s` |

Interpretation:

- The targeted relay cost was removed: Order and Wallet no longer spend tens of cumulative seconds in send/enqueue overhead.
- Full business TPS did not reflect the whole improvement because TPS-85 still reported a large final unacked queue tail:
  - `queueDrainTailAfterCompletedTradesSeconds=7.90s`;
  - last non-zero queue was `matchEngine.walletTradeSettled.queue`.
- That tail needed a measurement audit before doing more service-side tuning.

### TPS-86 - RabbitMQ Queue Totals Observation Fix

Status: **implemented; measurement corrected and validated**

Problem:

- The load generator sampled five RabbitMQ queues every `100ms`.
- Each queue sample called the full management endpoint:
  - `/api/queues/%2F/{queue}`;
  - this returns a large queue object including stats, rates, consumer details, deliveries, and other management data.
- Light/deep diagnostics used HTTP instead of `rabbitmqctl`, but still queried queue statistics.
- TPS-85 showed a suspicious shape:
  - completion markers reached at `12.98s`;
  - full queue drain was reported at `20.89s`;
  - DB had exactly `10000` Match outbox rows, `10000` Order outbox rows, `10000` Wallet outbox rows, all `SENT`, `attempt_count=0`;
  - `trade_completion_markers` had exactly `10000` `ORDER_APPLIED` and `10000` `WALLET_SETTLED` rows.
- This made a pure service-side `7.90s` tail unlikely. The remaining candidate was management API observation overhead/staleness.

Implementation:

- Changed `MatchedE2eLoadGenerator` queue-depth polling to request only queue totals:
  - `/api/queues/%2F/{queue}?disable_stats=true&enable_queue_totals=true`.
- Changed `collect-loadtest-diagnostics.sh` queue snapshot to use:
  - `/api/queues?disable_stats=true&enable_queue_totals=true&columns=name,messages,messages_ready,messages_unacknowledged,consumers`.
- This keeps the correctness gate strict: ready and unacked queues must still drain to zero.
- The change only removes unnecessary RabbitMQ management statistics work from the local benchmark driver.

Verification:

- `eap-order ./gradlew --no-daemon testClasses` passed.
- RabbitMQ management API query was manually verified for both:
  - single queue totals;
  - queue list totals.
- Smoke passed:
  - `GLT_TPS86_RABBIT_TOTALS_SMOKE_500`;
  - `businessMatchedE2eTps=413.37`;
  - `completedTrades=500`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=0.00`;
  - final ready/unacked backlog `0`.
- 10k light passed:
  - `GLT_TPS86_RABBIT_TOTALS_10K_R1`;
  - `actualBuyPublishTps=1998.96`;
  - `validForCapacityComparison=true`;
  - `businessMatchedE2eTps=703.30`;
  - `businessCompletionSeconds=14.22`;
  - `tradeExecutionReachTps=785.39`;
  - `orderCommandMatchReachTps=722.85`;
  - `walletSettlementReachTps=722.85`;
  - `completionMarkerReachTps=722.85`;
  - `strictCompletionMarkerReachTps=722.85`;
  - `queueFullyDrainedSeconds=14.22`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=0.38`;
  - `completedTrades=10000`;
  - `tradeExecutions=10000`;
  - `walletTradeSettlements=10000`;
  - `orderCommandMatchedRows=20000`;
  - final ready/unacked backlog `0`;
  - `remainingSellOrders=0`;
  - `remainingBuyOrders=0`;
  - `activeReservations=0`.

Interpretation:

- The previous `~21s` full business completion time was materially inflated by benchmark observation cost/management API behavior.
- With queue totals polling, the same strict business gate reports:
  - completed business throughput around `703 TPS`;
  - strict completion-to-drain tail only `0.38s`.
- TPS-86 does not mean the service suddenly became faster by `+46%`; it means TPS-85 was partly measuring RabbitMQ management-plane overhead/staleness in the final drain denominator.
- Current credible bottleneck is back to the real durable chain:
  - MatchEngine trade record + trade outbox;
  - Order trade application + outbox;
  - Wallet settlement + outbox;
  - publisher confirm wall-clock across durable queues.
- Continue TPS work from TPS-86 as the valid measurement baseline.

### TPS-87 - Wallet Combined UPDATE CTE Experiment

Status: **rejected**

Hypothesis:

- Wallet settlement updated buyer and seller wallet rows through two separate CTE `UPDATE` steps.
- Combining them into a single `wallet_update` CTE using `CASE` expressions might reduce one SQL subplan and improve the Wallet settlement durable chain.

Result:

- 500 smoke passed:
  - `GLT_TPS87_WALLET_COMBINED_UPDATE_SMOKE_500`;
  - `completedTrades=500`;
  - wallet balances and locks converged;
  - final ready/unacked backlog `0`.
- 10k light passed for correctness but regressed throughput:
  - `GLT_TPS87_WALLET_COMBINED_UPDATE_10K_R1`;
  - `actualBuyPublishTps=1998.05`;
  - `businessMatchedE2eTps=557.87`;
  - `businessCompletionSeconds=17.93`;
  - `completionMarkerReachTps=557.87`;
  - final ready/unacked backlog `0`.

Metric comparison:

| Metric | TPS-86 baseline | TPS-87 combined UPDATE |
| --- | ---: | ---: |
| Business TPS | `703.30` | `557.87` |
| Business completion seconds | `14.22s` | `17.93s` |
| Wallet settlement CTE sum | `8.302888s` | `9.964560s` |
| Wallet settlement transaction sum | `13.377538s` | `15.711209s` |
| Wallet outbox batch sum | `11.697534s` | `13.589941s` |
| Wallet outbox confirm sum | `11.326308s` | `13.136175s` |

Decision:

- Revert the combined `wallet_update` CTE.
- This experiment proved that the issue is not merely "two UPDATE CTEs instead of one".
- The next useful change must reduce durable write count or relay state, not make the existing SQL expression denser.

### TPS-88 - Wallet Settlement-Table Relay for WalletTradeSettled

Status: **implemented; correctness accepted; capacity improved in first 10k run**

Problem:

- Wallet settlement hot path previously wrote:
  - one `wallet_service.trade_settlements` row for idempotent settlement evidence;
  - two `wallet_service.wallets` balance updates;
  - one `wallet_service.outbox` row for `WalletTradeSettledEvent`.
- The outbox row was reliable but redundant with the settlement fact for this specific marker:
  - the marker is derived from the settlement itself;
  - MatchEngine only needs a retryable `WalletTradeSettledEvent`;
  - duplicate delivery is already absorbed by MatchEngine completion-marker idempotency.

Implementation:

- Kept the regular Wallet outbox for order-confirmation and auction events.
- Moved only `WalletTradeSettledEvent` onto `wallet_service.trade_settlements` as an integrated relay source:
  - added event payload fields to `trade_settlements`;
  - added `event_status`, `attempt_count`, `next_retry_at`, `last_error`, and `updated_at`;
  - old settlement rows default to `SENT` so historical rows are not accidentally published after migration;
  - new trade settlements are inserted as `PENDING`.
- Added `WalletTradeSettlementRelay`:
  - selects pending settlement rows;
  - publishes `WalletTradeSettledEvent` to RabbitMQ with publisher confirms;
  - marks settlement rows `SENT` only after confirm;
  - keeps failed rows retryable with backoff;
  - tolerates publish-confirm-then-crash by allowing duplicate marker delivery.
- Removed hot-path JSON serialization from `TradeExecutedListener`; payload is now built by the relay.

Correctness semantics:

- Wallet balance correctness still commits in the original Wallet transaction.
- Settlement idempotency still uses `trade_settlements(trade_id)`.
- Reliable publication is preserved:
  - if Wallet commits but relay has not published, the row remains `PENDING`;
  - if publish succeeds but marking `SENT` fails, the row can be republished;
  - MatchEngine completion-marker idempotency absorbs duplicate `WALLET_SETTLED` events.

Verification:

- Focused tests passed:
  - `TradeExecutedListenerTest`;
  - `OutboxPollerTest`;
  - `WalletTradeSettlementRelayTest`.
- 500 smoke passed:
  - `GLT_TPS88_WALLET_SETTLEMENT_RELAY_SMOKE_500`;
  - `completedTrades=500`;
  - `walletTradeSettlements=500`;
  - `eap_wallet_trade_settlement_relay_published_total=500`;
  - final ready/unacked backlog `0`.
- 10k light passed:
  - `GLT_TPS88_WALLET_SETTLEMENT_RELAY_10K_R1`;
  - `actualBuyPublishTps=1999.13`;
  - `validForCapacityComparison=true`;
  - `businessMatchedE2eTps=761.27`;
  - `businessCompletionSeconds=13.14`;
  - `tradeExecutionReachTps=926.22`;
  - `orderCommandMatchReachTps=771.89`;
  - `walletSettlementReachTps=771.89`;
  - `completionMarkerReachTps=771.89`;
  - `completedTrades=10000`;
  - `walletTradeSettlements=10000`;
  - `queueDrainTailAfterStrictCompletedTradesSeconds=0.18`;
  - final ready/unacked backlog `0`.
- DB verification:
  - TPS88 `trade_settlements`: `SENT=10000`, `PENDING=0`, `FAILED=0`;
  - Wallet `outbox`: `PENDING=0`, `FAILED=0`;
  - MatchEngine completion markers: `ORDER_APPLIED=10000`, `WALLET_SETTLED=10000`.

Metric comparison:

| Metric | TPS-86 baseline | TPS-87 rejected | TPS-88 settlement relay |
| --- | ---: | ---: | ---: |
| Business TPS | `703.30` | `557.87` | `761.27` |
| Business completion seconds | `14.22s` | `17.93s` | `13.14s` |
| Completion marker reach TPS | `722.85` | `557.87` | `771.89` |
| Wallet settlement CTE sum | `8.302888s` | `9.964560s` | `8.024727s` |
| Wallet settlement transaction sum | `13.377538s` | `15.711209s` | `12.882845s` |
| Wallet regular outbox batch sum | `11.697534s` | `13.589941s` | `0.000000s` |
| Wallet settlement relay batch sum | n/a | n/a | `10.444038s` |
| Wallet settlement relay confirm sum | n/a | n/a | `9.961610s` |

Interpretation:

- TPS88 is the first recent change that directly validates the durable-write-count hypothesis:
  - reducing one hot-path durable row insert from Wallet improved the 10k business gate;
  - the improvement is modest, not magic, because publication still needs a durable relay state and publisher confirms.
- The remaining Wallet cost is now clearer:
  - settlement CTE and transaction are still real work;
  - settlement relay confirm wall-clock is still about `10s` cumulative across `10000` messages;
  - but the generic Wallet outbox no longer participates in the trade-completion path.
- This supports continuing the same line of work:
  - classify every durable write by whether it is the business fact, an idempotency claim, or relay state;
  - remove only redundant durable rows when retry/recovery semantics remain explicit.

### TPS-89 - MatchEngine TradeExecution-Table Relay Experiment

Status: **rejected; correctness passed but capacity regressed**

Hypothesis:

- MatchEngine currently writes both:
  - `match_engine.trade_executions` as the durable `TradeExecuted` business fact;
  - `match_engine.trade_outbox` as retryable relay state for publishing `TradeExecutedEvent`.
- Because `trade_executions` already contains all fields required to rebuild `TradeExecutedEvent`, we tested whether relay state could be moved onto `trade_executions` to remove the separate `trade_outbox` insert.
- This mirrored TPS-88's Wallet settlement-table relay, but with a stricter question:
  - is the MatchEngine trade fact table a good relay queue;
  - or does mixing fact inserts, relay updates, pending scans, and completion evidence increase contention?

Implementation tested:

- Added relay columns to `trade_executions`:
  - `event_status`;
  - `attempt_count`;
  - `next_retry_at`;
  - `last_error`;
  - `updated_at`.
- Changed `JpaTradeExecutionRecorder` to insert only `trade_executions` with `event_status='PENDING'`.
- Added `TradeExecutionRelay`:
  - selects pending `trade_executions`;
  - rebuilds `TradeExecutedEvent`;
  - publishes to RabbitMQ with publisher confirms;
  - marks rows `SENT` after confirm.
- Disabled the old `trade_outbox` relay in loadtest profile for a clean comparison.

Correctness verification:

- Focused tests passed for the new recorder and relay path.
- 500 smoke passed:
  - `GLT_TPS89_TRADE_EXECUTION_RELAY_SMOKE_500`;
  - `completedTrades=500`;
  - `tradeExecutions=500`;
  - `walletTradeSettlements=500`;
  - completion markers: `ORDER_APPLIED=500`, `WALLET_SETTLED=500`;
  - `trade_executions`: `SENT=500`;
  - new `trade_outbox` rows for the smoke run: `0`;
  - final ready/unacked backlog `0`.

Capacity results:

- 10k R1B with single-channel `TradeExecutionRelay`:
  - `GLT_TPS89_TRADE_EXECUTION_RELAY_10K_R1B`;
  - `businessMatchedE2eTps=645.95`;
  - `businessCompletionSeconds=15.48`;
  - `tradeExecutionReachTps=799.99`;
  - `completionMarkerReachTps=645.95`;
  - final ready/unacked backlog `0`;
  - `trade_executions`: `SENT=10000`;
  - new `trade_outbox` rows: `0`.
- 10k R2 after adding chunked publish support equivalent to the old outbox relay:
  - `GLT_TPS89_TRADE_EXECUTION_RELAY_10K_R2`;
  - `businessMatchedE2eTps=514.37`;
  - `businessCompletionSeconds=19.44`;
  - `tradeExecutionReachTps=617.86`;
  - `completionMarkerReachTps=514.37`;
  - final ready/unacked backlog `0`;
  - `trade_executions`: `SENT=10000`;
  - new `trade_outbox` rows: `0`.

Comparison:

| Metric | TPS-88 accepted baseline | TPS-89 R1B | TPS-89 R2 |
| --- | ---: | ---: | ---: |
| Business TPS | `761.27` | `645.95` | `514.37` |
| Business completion seconds | `13.14s` | `15.48s` | `19.44s` |
| TradeExecution reach TPS | `926.22` | `799.99` | `617.86` |
| Completion marker reach TPS | `771.89` | `645.95` | `514.37` |
| Match `trade_executions` inserts | `10000` | `10000` | `10000` |
| Match `trade_outbox` inserts | `10000` | `0` | `0` |
| Match relay-state updates | `trade_outbox: 10000` | `trade_executions: 10000` | `trade_executions: 10000` |
| Final ready/unacked backlog | `0` | `0` | `0` |

Decision:

- Reject the MatchEngine `trade_executions` relay merge.
- Reverted code back to the TPS-88 `trade_outbox` relay path.
- Dropped the local loadtest DB's experimental `trade_executions` relay columns and pending index to avoid polluting later runs.
- Kept only the loadtest service-startup fix from this work:
  - `start-loadtest-services.sh` now starts Wallet, Order, and MatchEngine sequentially and waits for each actuator health endpoint;
  - this prevents concurrent Gradle `eap-common/build` writes from making a service fail to start before the run phase.

Interpretation:

- TPS-89 is an important negative result.
- TPS-88 worked because `trade_settlements` is both the Wallet settlement fact and the idempotency key for the marker relay.
- MatchEngine is different:
  - `trade_executions` is the immutable business fact;
  - using it as a relay queue adds status updates and pending scans to the same table that the matching hot path is inserting into;
  - the relay update is not a HOT update in the measured run;
  - event reconstruction also reads many columns instead of publishing a prebuilt outbox payload.
- The separate `trade_outbox` row is still write amplification, but it isolates volatile relay state from the immutable trade fact table.
- Next TPS work should not merge `trade_outbox` into `trade_executions`.
- Better candidates are:
  - reduce Order trade-application/outbox cost;
  - revisit MatchEngine completion-marker writes;
  - inspect whether the remaining Match outbox payload/write path can be made cheaper without moving relay state onto the fact table.

Baseline sanity after revert:

- 10k light passed after reverting TPS-89 and cleaning local DB:
  - `GLT_TPS89_REVERT_OUTBOX_BASELINE_10K_R1`;
  - `businessMatchedE2eTps=777.33`;
  - `businessCompletionSeconds=12.86`;
  - `tradeExecutionReachTps=868.19`;
  - `orderCommandMatchReachTps=796.97`;
  - `walletSettlementReachTps=796.97`;
  - `completionMarkerReachTps=796.97`;
  - `completedTrades=10000`;
  - `tradeExecutions=10000`;
  - `walletTradeSettlements=10000`;
  - final ready/unacked backlog `0`;
  - `trade_outbox`: `SENT=10000`;
  - completion markers: `ORDER_APPLIED=10000`, `WALLET_SETTLED=10000`;
  - `trade_executions` no longer has the rejected relay-state columns in the local loadtest DB.

### TPS-90 - MatchEngine RecordTrade Phase Attribution

Status: **implemented; diagnostic only**

Problem:

- TPS-89 showed that merging MatchEngine relay state into `trade_executions` regressed capacity.
- The next question was whether the remaining MatchEngine cost was inside the SQL statement itself or in the transaction/JDBC boundary around it.

Implementation:

- Added `match_engine_trade_record_phase_duration` timers for:
  - `serialize`;
  - `insert_trade_outbox`;
  - `mark_trade_executed`.
- Added `match_engine_complete_reservation_phase_duration` timers for:
  - `prepare`;
  - `redis_eval`;
  - `result`.

Diagnostic result:

- `GLT_TPS90_MATCH_PHASE_METRICS_10K_R1` completed correctly:
  - `actualBuyPublishTps=1999.10`;
  - `businessMatchedE2eTps=640.00`;
  - `completedTrades=10000`;
  - final queues and DLQ `0`.
- MatchEngine phase metrics showed:
  - `recordTrade` total: `18.737603s`;
  - `insert_trade_outbox`: `11.255706s`;
  - `mark_trade_executed`: `0.088335s`;
  - `serialize`: `0.095743s`;
  - `complete_reservation.redis_eval`: `10.925129s`.
- PostgreSQL `pg_stat_statements` for the `trade_executions + trade_outbox` CTE was much lower:
  - `10000 calls`;
  - `3618.73ms total_exec_ms`;
  - `0.3619ms mean_exec_ms`.

Interpretation:

- Server-side SQL executor time is not enough to explain the full MatchEngine wall-clock cost.
- The missing time likely sits in JDBC round trips, Spring transaction boundary, WAL commit, and relay/consumer scheduling.
- This led directly to TPS-91's explicit transaction-boundary metrics.

### TPS-91 - MatchEngine Transaction Boundary Metrics and Redis User-Order Index A/B

Status: **implemented; diagnostic accepted**

Problem:

- TPS-90 left a gap between:
  - `recordTrade` wall-clock time;
  - measured SQL phases;
  - PostgreSQL server-side execution time.
- Redis `user:{userId}:orders` index maintenance also remained a plausible local hot-path cost:
  - unmatched order add path writes `SADD`;
  - reserved order completion writes `SREM`;
  - this index exists for user open-order query support, not for core matching.

Implementation:

- Added explicit MatchEngine transaction-boundary metrics under `match_engine_trade_record_phase_duration`:
  - `transaction_body`;
  - `transaction_total`;
  - `commit_gap`.
- Added loadtest flag:
  - `EAP_MATCH_USER_OPEN_ORDER_INDEX_ENABLED`;
  - defaults to `true`;
  - loadtest can set it to `false`.
- Updated Redis Lua scripts so user-open-order index mutation is conditional:
  - `add_order.lua`;
  - `remove_order.lua`;
  - `reserve_or_add_order_buy.lua`;
  - `reserve_or_add_order_sell.lua`;
  - `release_reserved_order.lua`;
  - `complete_reserved_order.lua`.

Verification:

- Focused MatchEngine tests passed:
  - `JpaTradeExecutionRecorderTest`;
  - `MatchingEngineServiceTest`;
  - `RedisOrderBookServiceTest`.

10k A/B result:

| Run | User index | Business TPS | Completion seconds | Reserve sum | Complete Redis eval | Record body | Transaction total | Commit gap |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `GLT_TPS91_USER_INDEX_ON_10K_R1` | on | `487.92` | `20.50s` | `32.145760s` | `9.670360s` | `10.621657s` | `16.618792s` | `5.997135s` |
| `GLT_TPS91_USER_INDEX_OFF_10K_R1` | off | `481.62` | `20.76s` | `19.647064s` | `8.574972s` | `9.038567s` | `15.044679s` | `6.006112s` |

Interpretation:

- Disabling `user:{userId}:orders` reduced local Redis work:
  - reserve sum improved materially;
  - complete-reservation Redis eval improved modestly.
- Full business TPS did not improve, so user-open-order index maintenance is not the current global bottleneck.
- The transaction-boundary metrics confirmed a stable `commit_gap` around `6s` cumulative per `10000` trades, roughly `0.6ms/trade`.
- PostgreSQL server-side SQL time remains much smaller than app-observed durable-chain time.

Decision:

- Keep the A/B flag as a loadtest diagnostic switch.
- Do not remove the user-open-order index as a TPS fix.
- Next work should estimate the DB durable-write ceiling before further code changes.

Latest repeat under the TPS-93/TPS-97 benchmark shape:

| Run | User index | Business TPS | Completion seconds | Orderbook admission TPS | Reserve Redis eval | Complete Redis eval | Final queues/DLQ |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS97_MATCH_USER_INDEX_OFF_LIGHT_10K_R1` | off | `749.07` | `13.35s` | `4832.54` | `19.784s` | `6.807s` | `0` |

Repeat interpretation:

- The run is valid for capacity comparison and all correctness gates converged:
  - `completedTrades=10000`;
  - `tradeExecutions=10000`;
  - `orderCommandMatchedRows=20000`;
  - `walletTradeSettlements=10000`;
  - `activeReservations=0`;
  - final queues/DLQ `0`.
- Compared with the accepted TPS-93 repeat median (`833.58`, range `729.71-940.93`), the result is inside the noise band and below median.
- Compared with TPS-93 R2, local Redis reserve cost did not improve:
  - TPS-93 R2 `reserve_order.redis_eval=15.888s`;
  - TPS-97 OFF `reserve_order.redis_eval=19.784s`.
- This reinforces the TPS-91 decision: keep the flag for diagnostics, but do not remove the user-open-order index as the main TPS fix.

### TPS-92 - DB Durable Write Ceiling Probe

Status: **in progress; MatchEngine, Wallet, and Order DB ceiling probes implemented**

Problem:

- Current 10k business-completed throughput is in the `480-780 completed trades/s` class depending on diagnostics level and recent run conditions.
- The dominant cost now appears to be the durable write chain, not Redis matching, not RabbitMQ publish input, and not a single slow SQL query.
- PostgreSQL server-side execution time is much smaller than service-observed wall-clock time:
  - Match `trade_executions + trade_outbox` CTE in TPS-91 ON: `3187.94ms / 10000 calls`, mean `0.3188ms`;
  - Match `recordTrade.transaction_total`: `16.618792s / 10000`;
  - Match `recordTrade.commit_gap`: `5.997135s / 10000`;
  - Wallet settlement CTE in TPS-91 ON: `1958.28ms / 10000 calls`, mean `0.1958ms`.
- Hikari pending connections and PostgreSQL activity waits were not the obvious limiter in the captured samples.

Hypothesis:

- The practical ceiling is created by repeated transaction boundaries, WAL commits, JDBC round trips, outbox relay state updates, publisher confirms, and cross-service completion markers.
- Before changing more business code, we need a controlled DB ceiling benchmark that separates:
  - raw SQL executor throughput;
  - transaction + commit throughput;
  - Spring/JDBC durable-chain overhead;
  - full E2E RabbitMQ/outbox/completion overhead.

Scope:

- Build benchmark/probe scripts or test runners that execute the existing hot-path SQL shapes without changing business semantics.
- Measure each service separately first, then compare to the full E2E result.
- Do not use this ticket to remove reliability writes. It is a measurement ticket.

Required probes:

1. MatchEngine DB ceiling:
   - run the current `trade_executions + trade_outbox` insert CTE for `10000` and `30000` trades;
   - measure single-row transaction mode;
   - measure grouped transaction mode where safe for the synthetic benchmark;
   - optionally measure completion-marker batch insert separately.

2. Order DB ceiling:
   - run the current trade-application batch SQL path against seeded `order_matching_state`;
   - capture lock-head phase, append phase, outbox insert phase, and transaction total;
   - compare rows/trade against runtime table stats.

3. Wallet DB ceiling:
   - run the current settlement CTE against seeded wallet rows;
   - measure wallet row update + settlement insert transaction total;
   - measure settlement relay mark-SENT update separately.

4. Outbox relay ceiling:
   - measure select pending, publish enqueue, publisher confirm, and mark-SENT update separately for MatchEngine, Order, and Wallet;
   - separate RabbitMQ confirm wall-clock from PostgreSQL update execution time.

Metrics to collect:

- `pg_stat_statements` total and mean execution time.
- `pg_stat_user_tables` inserts, updates, dead tuples.
- `pg_stat_activity` wait events.
- Hikari acquire/usage/pending metrics.
- Application phase timers:
  - SQL body;
  - transaction body;
  - transaction total;
  - commit gap.
- Per-probe throughput:
  - rows/s;
  - trades/s equivalent;
  - durable writes/s equivalent.

Acceptance criteria:

- Produce a table comparing:

| Layer | Measured throughput | Meaning |
| --- | ---: | --- |
| Raw PostgreSQL SQL | TBD | Executor-only ceiling for each hot SQL shape. |
| Transaction + commit | TBD | DB durable boundary ceiling without RabbitMQ. |
| Spring/JDBC local service | TBD | App-local durable chain ceiling. |
| Full E2E business gate | current baseline | Order + Wallet + MatchEngine + outbox + RabbitMQ + completion drain. |

- Answer which statement is true:
  - DB/schema write model itself cannot reach `2000 completed trades/s` on this local environment;
  - or DB can theoretically reach it, but Spring/JDBC/outbox/consumer pipeline is the limiting layer.
- Recommend exactly one next implementation target based on the largest measured gap.

Out of scope:

- Removing outbox reliability.
- Changing the completed-trade definition.
- Replacing RabbitMQ or PostgreSQL.
- Further concurrency tuning unless the probe shows an explicit worker saturation point.

Initial implementation:

- Added `matchDbCeilingProbe` Gradle task in `eap-matchEngine`.
- Added `MatchDbCeilingProbe` as a raw JDBC runner:
  - does not start Spring Boot;
  - does not use Redis;
  - does not publish to RabbitMQ;
  - executes the same `trade_executions + trade_outbox` CTE shape used by `JpaTradeExecutionRecorder`;
  - supports `transaction_per_row` and `grouped_transaction` modes.
- Added `walletDbCeilingProbe` Gradle task in `eap-wallet`.
- Added `WalletDbCeilingProbe` as a raw JDBC runner:
  - seeds synthetic buyer/seller wallet rows;
  - executes the same trade settlement CTE shape used by `WalletTradeSettlementAppender`;
  - excludes RabbitMQ listener, settlement relay, publisher confirm, and completion marker cost;
  - supports `transaction_per_row` and `grouped_transaction` modes.
- Added `orderDbCeilingProbe` Gradle task in `eap-order`.
- Added `OrderDbCeilingProbe` as a raw JDBC runner:
  - seeds synthetic `order_matching_state` rows;
  - executes the current trade-apply batch CTE shape against `order_trade_applications`, `order_matching_state`, and `order_event_outbox`;
  - excludes RabbitMQ listener, outbox relay, publisher confirm, and completion marker cost;
  - reports `transaction_per_batch` because the current Order hot path applies a batch CTE as the durable unit.
- Added `scripts/load-test/summarize-write-costs.sh`.
- `run-global-matched-e2e-two-phase.sh` now writes a post-run `write-cost-summary.md` after result JSON extraction.

Initial MatchEngine 10k probe:

| Run | Mode | Events | Workers | Batch size | Completed | Failures | Elapsed | TPS | p50 | p95 | p99 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TPS92_MATCH_DB_TX_PER_ROW_10K_R1` | `transaction_per_row` | `10000` | `16` | `100` | `10000` | `0` | `1.203s` | `8311.04` | `1.142ms` | `2.109ms` | `3.116ms` |
| `TPS92_MATCH_DB_GROUP100_10K_R1` | `grouped_transaction` | `10000` | `16` | `100` | `10000` | `0` | `1.052s` | `9507.01` | `0.609ms` | `1.660ms` | `4.111ms` |

Initial Wallet 10k probe:

| Run | Mode | Events | Workers | Batch size | Completed | Failures | Elapsed | TPS | p50 | p95 | p99 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TPS92_WALLET_DB_TX_PER_ROW_10K_R1` | `transaction_per_row` | `10000` | `16` | `100` | `10000` | `0` | `0.983s` | `10172.76` | `1.264ms` | `2.730ms` | `4.260ms` |
| `TPS92_WALLET_DB_GROUPED_10K_R1` | `grouped_transaction` | `10000` | `16` | `100` | `10000` | `0` | `0.588s` | `17016.19` | `0.671ms` | `1.506ms` | `2.587ms` |

Initial Order 10k probe:

| Run | Mode | Events | Workers | Batch size | Completed | Failures | Batches | Elapsed | TPS | Batch p50 | Batch p95 | Batch p99 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TPS92_ORDER_DB_BATCH100_10K_R1` | `transaction_per_batch` | `10000` | `16` | `100` | `10000` | `0` | `100` | `7.737s` | `1292.47` | `1237.679ms` | `2306.241ms` | `2372.752ms` |
| `TPS92_ORDER_DB_BATCH6_10K_R1` | `transaction_per_batch` | `10000` | `16` | `6` | `10000` | `0` | `1667` | `0.389s` | `25698.62` | `2.311ms` | `8.957ms` | `38.815ms` |
| `TPS92_ORDER_DB_BATCH10_10K_R1` | `transaction_per_batch` | `10000` | `16` | `10` | `10000` | `0` | `1000` | `0.442s` | `22618.35` | `4.679ms` | `14.487ms` | `43.724ms` |

Initial interpretation:

- MatchEngine PostgreSQL can execute the isolated `TradeExecuted + trade_outbox` write shape far above the current full E2E business TPS.
- Wallet PostgreSQL can execute the isolated settlement CTE far above the current full E2E business TPS.
- Order PostgreSQL is sensitive to synthetic batch shape:
  - `batch_size=100` is much slower and does not match the current full E2E observed average batch size;
  - `batch_size=6` and `batch_size=10` are closer to the current runtime batch count and execute far above the current full E2E business TPS.
- This does not mean the full system should reach `8000+ completed trades/s`:
  - the probe excludes Redis reservation work;
  - excludes `TradeOutboxRelay` select/publish/confirm/mark-SENT;
  - excludes Order and Wallet consumers;
  - excludes downstream completion-marker convergence;
  - excludes final RabbitMQ ready/unacked drain.
- It does mean the current `480-780 completed trades/s` E2E ceiling is not explained by these isolated SQL statements or by PostgreSQL executor capacity alone.
- Current best bottleneck statement:
  - DB SQL executor capacity is not the first limiter;
  - the limiter is the full durable pipeline around those SQL statements: listener scheduling, transaction boundaries, JDBC/service overhead, outbox relay select/publish/confirm/mark-SENT, and completion-marker convergence.
- Added `outboxRelayCeilingProbe` Gradle task in `eap-matchEngine`.
- Added `OutboxRelayCeilingProbe` as a raw JDBC + RabbitMQ runner:
  - supports `match`, `order`, and `wallet-settlement` modes;
  - seeds synthetic pending relay rows in the target service DB;
  - drains those rows through select, publish enqueue, RabbitMQ publisher confirm, and mark-SENT update;
  - publishes to a dedicated probe exchange/queue instead of business queues, so it does not contaminate the main Order/Wallet/MatchEngine queues;
  - measures select, enqueue, confirm, mark-SENT, and total batch duration separately.

Initial relay 10k probe:

| Run | Service | Events | Batch size | Completed | Failures | Batches | Elapsed | Relay TPS | Select | Enqueue | Confirm | Mark SENT |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TPS92_RELAY_MATCH_10K_R1` | `match` | `10000` | `500` | `10000` | `0` | `20` | `0.643s` | `15560.04` | `0.089443s` | `0.060674s` | `0.313383s` | `0.120599s` |
| `TPS92_RELAY_ORDER_10K_R1` | `order` | `10000` | `500` | `10000` | `0` | `20` | `0.776s` | `12889.62` | `0.213091s` | `0.091890s` | `0.321848s` | `0.117695s` |
| `TPS92_RELAY_WALLET_10K_R1` | `wallet-settlement` | `10000` | `500` | `10000` | `0` | `20` | `0.678s` | `14752.26` | `0.108912s` | `0.062822s` | `0.262683s` | `0.193270s` |

Relay interpretation:

- Isolated relay select + publish + confirm + mark-SENT can run far above the current `480-780 completed trades/s` full E2E ceiling.
- The full-run `16-18s` cumulative confirm/batch timers are therefore not explained by RabbitMQ publisher confirm throughput in isolation.
- Caveat:
  - the probe uses a dedicated probe exchange/queue, not the real fanout to Order/Wallet/MatchEngine business queues;
  - it measures relay mechanics and broker confirms without downstream consumers, completion-marker writes, or competing service work.
- Updated bottleneck statement:
  - isolated DB SQL is fast enough;
  - isolated relay mechanics are fast enough;
  - the current bottleneck is the combined consumer pipeline under concurrent service work: Match intake/record/relay, Order apply/relay, Wallet settlement/relay, and final completion-marker consumer drain.
- Next TPS-92 step should measure full-chain per-stage wall-clock lag from event creation to consumer receive to durable apply to downstream publish to completion marker, because the remaining gap appears between isolated component ceiling and the integrated pipeline, not inside a single SQL or relay primitive.

Java-side Wallet settlement probe:

- Inspection found an important asymmetry in the consumer pipeline:
  - Order `TradeExecuted` consumption already used a batch listener and batch append path;
  - MatchEngine completion-marker consumption already used batch listeners;
  - Wallet `TradeExecuted` settlement still consumed one event at a time, opening one Spring transaction per completed trade.
- This explained why the isolated Wallet DB ceiling was far above full E2E throughput:
  - isolated Wallet settlement CTE: `10172.76 TPS` in `transaction_per_row`, `17016.19 TPS` in grouped mode;
  - previous full E2E Wallet settlement timer in TPS-91 ON: `10000` CTE/transaction observations for `10000` trades.
- Implemented a guarded Wallet `TradeExecuted` batch listener:
  - `walletTradeExecutedBatchListenerContainerFactory` enables AMQP consumer batch mode;
  - loadtest profile uses `batch-size=50`, `receive-timeout-ms=25`, and existing `trade-executed.concurrency=12`;
  - production/default profile keeps `batch-size=1` to avoid changing normal runtime behavior by default;
  - batch settlement is only used when all buyer/seller users in the listener batch are non-null and non-overlapping;
  - duplicate/existing settlement, incomplete batch result, data-integrity failure, optimistic-lock failure, singleton batch, or overlapping wallet rows fall back to the previous single-event settlement path.
- Added Wallet batch metrics:
  - `eap_wallet_trade_settlement_batch_applied_total`;
  - `eap_wallet_trade_settlement_batch_fallback_total`;
  - `eap_wallet_trade_settlement_batch_fallback_reason_total{reason=...}`;
  - `eap_wallet_trade_settlement_batch_size`;
  - `eap_wallet_trade_settlement_batch_duration`.

Wallet batch smoke:

| Run | Events | Target TPS | Diagnostics | Result | completedTrades | walletTradeSettlements | business TPS | Final queues/DLQ |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | --- |
| `GLT_TPS92_WALLET_BATCH_SMOKE_500` | `500` | `500` | light | PASS | `500` | `500` | `288.58` | `0` |

Smoke batch signal:

| Metric | Value |
| --- | ---: |
| Wallet batch observations | `112` |
| Wallet batch-applied count | `80` |
| Wallet batch-fallback count | `32` |
| Wallet batch size sum | `500` |
| Wallet batch size max | `13` |
| Wallet CTE observations | `112` |
| Wallet CTE cumulative time | `1.600s` |

Wallet batch 10k light runs:

| Run | Events | Target TPS | Actual input TPS | Result | completedTrades | walletTradeSettlements | businessCompletionSeconds | business TPS | Final queues/DLQ |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS92_WALLET_BATCH_LIGHT_10K_R1` | `10000` | `2000` | `1997.95` | PASS | `10000` | `10000` | `13.16s` | `759.84` | `0` |
| `GLT_TPS92_WALLET_BATCH_LIGHT_10K_R2` | `10000` | `2000` | `1996.99` | PASS | `10000` | `10000` | `18.21s` | `549.04` | `0` |

10k business TPS average across R1/R2: `654.44 completed trades/s`.

10k batch signal:

| Metric | R1 | R2 |
| --- | ---: | ---: |
| Wallet batch observations | `1447` | `1860` |
| Wallet batch-applied count | `1239` | `1493` |
| Wallet batch-fallback count | `208` | `367` |
| Wallet fallback reason | `singleton_batch=208` | `singleton_batch=367` |
| Wallet batch size sum | `10000` | `10000` |
| Wallet average listener batch size | `6.91` | `5.38` |
| Wallet batch size max | `29` | `30` |
| Wallet CTE observations | `1447` | `1860` |
| Wallet CTE cumulative time | `9.549s` | `12.038s` |
| Wallet batch cumulative time | `11.516s` | `15.790s` |

Interpretation:

- This is the clearest TPS-92 evidence so far that Java/service pipeline shape matters.
- The Wallet SQL executor was already fast in isolation, but full E2E previously paid one listener transaction and one CTE observation per trade.
- After changing Wallet to a guarded Java batch listener, Wallet settlement CTE observations dropped from `10000` to `1447-1860` for the same `10000` completed trades.
- Business-gated throughput improved from the prior TPS-91 ON run (`487.92 completed trades/s`) to an R1/R2 average of `654.44 completed trades/s` in the same 10k target-2000 light scenario class.
- The improvement is not caused by relaxing correctness:
  - `completedTrades=10000`;
  - `walletTradeSettlements=10000`;
  - all measured ready/unacked queues ended at `0`;
  - DLQ ended at `0`;
  - fallback was only `singleton_batch`, not duplicate settlement, incomplete batch, data-integrity, or optimistic-lock fallback.
- The remaining top cumulative app timers after this change are now MatchEngine order intake/matching, MatchEngine trade record, Order trade apply, and outbox relay confirm/batch timers.
- Next implementation target should move from raw DB SQL tuning to integrated Java pipeline reduction:
  - inspect MatchEngine `orderConfirmed` single-event listener and `tryMatch` loop;
  - separate event deserialize/listener dispatch time from Redis reservation, trade record transaction, and outbox relay;
  - avoid more blind concurrency tuning unless metrics show worker starvation.

MatchEngine reserve phase metrics:

- Added `match_engine_reserve_order_phase_duration_seconds{phase=...}` to split the `reserveBestMatchOrAddOrderWithSequenceLua` cost:
  - `prepare`;
  - `serialize_incoming`;
  - `callback_prepare`;
  - `redis_eval`;
  - `result`;
  - `deserialize_resting`.
- This is observability only. It does not change matching semantics, Redis Lua behavior, or trade completion gates.

Reserve phase smoke:

| Run | Events | Target TPS | Result | completedTrades | business TPS | Final queues/DLQ |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| `GLT_TPS92_MATCH_RESERVE_PHASE_SMOKE_500` | `500` | `500` | PASS | `500` | `263.10` | `0` |

Smoke reserve phase signal:

| Phase | Count | Cumulative seconds |
| --- | ---: | ---: |
| total reserve | `1000` | `2.588` |
| `redis_eval` | `1000` | `2.447` |
| `serialize_incoming` | `1000` | `0.064` |
| `deserialize_resting` | `500` | `0.018` |
| `callback_prepare` | `1000` | `0.011` |
| `prepare` | `1000` | `0.006` |
| `result` | `500` | `0.0003` |

Reserve phase 10k run:

| Run | Events | Target TPS | Actual input TPS | Result | completedTrades | businessCompletionSeconds | business TPS | Final queues/DLQ |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |
| `GLT_TPS92_MATCH_RESERVE_PHASE_LIGHT_10K_R1` | `10000` | `2000` | `1998.89` | PASS | `10000` | `11.40s` | `876.89` | `0` |

10k reserve phase signal:

| Phase | Count | Cumulative seconds | Mean ms |
| --- | ---: | ---: | ---: |
| total reserve | `20000` | `24.525` | `1.226` |
| `redis_eval` | `20000` | `23.861` | `1.193` |
| `serialize_incoming` | `20000` | `0.215` | `0.011` |
| `deserialize_resting` | `10000` | `0.142` | `0.014` |
| `callback_prepare` | `20000` | `0.057` | `0.003` |
| `prepare` | `20000` | `0.022` | `0.001` |
| `result` | `10000` | `0.003` | `<0.001` |

Interpretation:

- The MatchEngine reserve hot-path cost is not primarily Java JSON serialization/deserialization or byte-array callback preparation.
- In the 10k run, Redis Lua eval accounts for about `97.3%` of total reserve time (`23.861s / 24.525s`).
- Combined MatchEngine matching work is now dominated by:
  - `reserve_or_add` Redis Lua for every order confirmation;
  - `TradeExecuted + trade_outbox` durable DB transaction for every completed trade;
  - `complete_reserved_order` Redis Lua for every completed resting order;
  - relay publisher confirms and downstream completion-marker drain.
- The good 10k result (`876.89 completed trades/s`) should be treated as a valid PASS run but not as proof that metrics improved performance; this is likely normal local-run variance plus the earlier Wallet batch improvement.
- Next useful design question:
  - whether the orderbook hot path can reduce Redis round trips or cleanup work without losing crash recovery for reserved orders;
  - whether benchmark semantics should report order-confirmation throughput separately from completed-trade throughput, because each completed trade currently requires processing both a resting SELL confirmation and an incoming BUY confirmation in the same run.

### TPS-93 - split matched-load throughput semantics

Problem:

- The previous headline field `businessMatchedE2eTps` was correct for completed-trade throughput, but it encouraged mixing three different questions:
  - how fast the system can admit resting limit orders into the orderbook;
  - how fast a marketable incoming order can become a fully completed trade;
  - how fast the whole two-phase synthetic market flow moves when both resting orders and incoming orders are counted.
- This matters because the current matched load test intentionally stages SELL orders first, waits for the Redis sell book to converge, and only then publishes BUY confirmations. Treating only the BUY-to-completion window as the whole workload hides the orderbook-admission cost.

Change:

- Added explicit result JSON fields:
  - `orderbookAdmissionTps`: resting SELL confirmations admitted into the Redis orderbook per second, measured from the start of SELL publish until the sell book reaches the expected size.
  - `businessCompletedTradeTps`: completed trades per second, measured from incoming BUY publish start until the business gate and measured queues are fully drained.
  - `blendedMarketFlowTps`: total order confirmations processed per second across the full synthetic two-phase scenario, calculated as `(sellPublished + buyPublished) / (orderbookAdmissionSeconds + businessCompletionSeconds)`.
- Kept `businessMatchedE2eTps` and `matchedE2eTps` as legacy aliases for `businessCompletedTradeTps`.
- Added timing/count helpers:
  - `sellBookReachedOrders`;
  - `sellBookPostPublishWaitSeconds`;
  - `orderbookAdmissionSeconds`;
  - `blendedMarketFlowOrders`;
  - `blendedMarketFlowSeconds`.
- Updated write-cost and repeat-run summaries so multi-run reports aggregate the new TPS fields.

Interpretation rule:

- Use `orderbookAdmissionTps` when discussing "orders can be put on the book".
- Use `businessCompletedTradeTps` when discussing "fully completed trades with Order/Wallet/MatchEngine convergence".
- Use `blendedMarketFlowTps` when discussing the overall throughput of this specific two-phase local benchmark, where every completed trade also required one pre-admitted resting order in the same measured run.
- Do not compare `orderbookAdmissionTps` directly with `businessCompletedTradeTps` as if they represented the same unit. The former is order confirmations into the book; the latter is completed trades.

First 10k run with split TPS semantics:

| Run | Events | Target TPS | Actual input TPS | Result | `orderbookAdmissionTps` | `businessCompletedTradeTps` | `blendedMarketFlowTps` | `businessCompletionSeconds` | Final queues/DLQ |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_R1` | `10000` | `2000` | `1998.80` | PASS | `4878.06` | `811.36` | `1391.31` | `12.32s` | `0` |

Correctness facts:

- `completedTrades=10000`;
- `tradeExecutions=10000`;
- `orderCommandMatchedRows=20000`;
- `walletTradeSettlements=10000`;
- `remainingSellOrders=0`;
- `remainingBuyOrders=0`;
- `activeReservations=0`;
- final measured queues and DLQ are `0`.

Why this result is materially better than earlier 400-600 TPS runs:

- The input driver was valid (`actualBuyPublishTps=1998.80`, `offeredLoadRatio=0.9994`), so the higher completed throughput is not caused by under-driving the system.
- The Order/Wallet batching work from prior tickets is now visible in the full chain:
  - Order applied `20000` command-side matched rows through `1217` batch operations.
  - Wallet settled `10000` trades through `1341` settlement batches.
  - Wallet singleton fallback was `134`, about `1.34%`, and did not indicate duplicate or failed settlement.
- The business completion tail is now much shorter than the earlier worst 20-30s cases:
  - `tradeExecutionsReachedSeconds=11.52`;
  - `orderMatchedReachedSeconds=12.32`;
  - `walletSettlementsReachedSeconds=12.32`;
  - `completedTradesReachedSeconds=12.32`;
  - `queueFullyDrainedSeconds=12.32`.
- The split TPS view explains the workload better:
  - orderbook admission is fast (`4878.06 orders/s`);
  - fully completed business trades are slower but correctness-gated (`811.36 trades/s`);
  - the full two-phase synthetic market flow is `1391.31 order confirmations/s` when both resting SELL and incoming BUY confirmations are counted.

Remaining cost signals:

| Area | Count | Cumulative seconds | Mean |
| --- | ---: | ---: | ---: |
| MatchEngine `reserve_order.redis_eval` | `20000` | `16.658s` | `0.833ms` |
| MatchEngine `complete_reservation.redis_eval` | `10000` | `6.371s` | `0.637ms` |
| MatchEngine `recordTrade.transaction_total` | `10000` | `12.072s` | `1.207ms` |
| MatchEngine `recordTrade.insert_trade_outbox` | `10000` | `7.154s` | `0.715ms` |
| MatchEngine `recordTrade.commit_gap` | `10000` | `4.691s` | `0.469ms` |
| MatchEngine outbox confirm | `10000` | `10.707s` | `1.071ms` |
| Order outbox confirm | `10000` | `10.555s` | `1.056ms` |
| Wallet settlement relay confirm | `10000` | `10.498s` | `1.050ms` |

Next investigation:

- "Split" here means split the performance evidence, not split services:
  - durable write chain: confirm whether MatchEngine `recordTrade` is dominated by trade-outbox insert, transaction commit/fsync, or transaction scheduling;
  - Outbox confirm: confirm whether each relay is paying one broker confirm wait per event and whether batch publish can wait on confirms as a group;
  - Redis reservation: confirm whether the `reserve_order` + `complete_reservation` pair can be reduced for immediately matched orders without losing crash recovery or idempotency.

Repeat validation:

Command:

```bash
REPEATS=3 TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 PUBLISHERS=128 \
  TIMEOUT_SECONDS=360 DIAGNOSTICS_LEVEL=light RESET_PG_STATS_BEFORE_RUN=true \
  bash scripts/load-test/run-2000-ticket-marker-repeat.sh GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3
```

Result:

- Summary JSON: `build/load-test-reports/matched-e2e-repeat-GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3-summary.json`.
- Valid runs: `3/3`.
- Invalid runs: `0`.
- All runs had:
  - valid input pressure;
  - `completedTrades=10000`;
  - `tradeExecutions=10000`;
  - `walletTradeSettlements=10000`;
  - `orderCommandMatchedRows=20000`;
  - final measured queue backlog `0`.

| Run | Actual input TPS | `orderbookAdmissionTps` | `businessCompletedTradeTps` | `blendedMarketFlowTps` | `businessCompletionSeconds` | Final backlog |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | `1998.46` | `4211.32` | `833.58` | `1391.69` | `12.00s` | `0` |
| R2 | `1999.26` | `4972.65` | `940.93` | `1582.44` | `10.63s` | `0` |
| R3 | `1999.22` | `3696.83` | `729.71` | `1218.84` | `13.70s` | `0` |

Aggregate:

| Metric | Avg | Median | Min | Max | Relative spread |
| --- | ---: | ---: | ---: | ---: | ---: |
| `actualBuyPublishTps` | `1998.98` | `1999.22` | `1998.46` | `1999.26` | `0.04%` |
| `orderbookAdmissionTps` | `4293.60` | `4211.32` | `3696.83` | `4972.65` | `29.71%` |
| `businessCompletedTradeTps` | `834.74` | `833.58` | `729.71` | `940.93` | `25.30%` |
| `blendedMarketFlowTps` | `1397.66` | `1391.69` | `1218.84` | `1582.44` | `26.01%` |
| `businessCompletionSeconds` | `12.11s` | `12.00s` | `10.63s` | `13.70s` | `25.35%` |

Interpretation:

- The prior Order and Wallet batch-path changes are validated as a real improvement direction: all three runs completed above `700` correctness-gated trades/s, and the median is `833.58`.
- The earlier single run `811.36` was not an isolated lucky result; it sits near the repeat median.
- The local environment still has material run-to-run noise (`businessCompletedTradeTps` relative spread about `25%`), so public reporting should use median/range instead of the best run.
- The driver is not the source of this variance in this repeat set: `actualBuyPublishTps` spread is only `0.04%`.
- Remaining variance is more likely in service-side queue drain, DB/Redis scheduling, JVM/container co-location, or RabbitMQ confirm timing.

### TPS-94 - outbox batch-confirm A/B probe

Hypothesis:

- TPS-93 showed about `10s` cumulative publisher-confirm timer cost in each completion relay:
  - MatchEngine `trade_outbox_confirm`;
  - Order `order_event_outbox_confirm`;
  - Wallet `trade_settlement_relay_confirm`.
- The first hypothesis was that each relay might be paying a real per-message blocking cost by waiting on every `CorrelationData` future individually.
- A guarded experiment added `batch-confirm-enabled` flags so a relay can publish a batch on an `invoke` channel and call `RabbitOperations.waitForConfirmsOrDie(...)` once for that batch.

Implementation:

- Added disabled-by-default flags:
  - `eap.match-engine.trade-outbox-relay.batch-confirm-enabled`;
  - `eap.order-event-outbox.batch-confirm-enabled`;
  - `eap.wallet.trade-settlement-relay.batch-confirm-enabled`.
- Loadtest profile exposes environment-variable switches, all defaulting to `false`:
  - `EAP_MATCH_TRADE_OUTBOX_BATCH_CONFIRM_ENABLED`;
  - `EAP_ORDER_OUTBOX_BATCH_CONFIRM_ENABLED`;
  - `EAP_WALLET_TRADE_SETTLEMENT_BATCH_CONFIRM_ENABLED`.
- Confirm failure is conservative: the affected batch/chunk is treated as failed and retried through the existing outbox retry path. Duplicate downstream delivery remains covered by existing idempotency gates.

Verification:

- Compile checks:
  - `eap-matchEngine ./gradlew --no-daemon testClasses`: PASS.
  - `eap-order ./gradlew --no-daemon testClasses`: PASS.
  - `eap-wallet ./gradlew --no-daemon testClasses`: PASS.
- Relay unit tests:
  - `TradeOutboxRelayTest`: PASS, including batch-confirm behavior.
  - `WalletTradeSettlementRelayTest`: PASS, including batch-confirm behavior.
- Smoke:
  - `GLT_TPS94_BATCH_CONFIRM_SMOKE_500`: PASS, `completedTrades=500`, `tradeExecutions=500`, `orderCommandMatchedRows=1000`, `walletTradeSettlements=500`, final queues/DLQ `0`.

10k comparison:

| Run | Batch-confirm config | Actual input TPS | Business completed TPS | Business completion seconds | Final queues/DLQ | Key confirm signal |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `GLT_TPS94_BATCH_CONFIRM_LIGHT_10K_R1` | Match + Order + Wallet ON | `1999.05` | `869.38` | `11.50s` | `0` | Match `trade_outbox_confirm` worsened to `39.534s` cumulative |
| `GLT_TPS94_ORDER_WALLET_BATCH_CONFIRM_LIGHT_10K_R2` | Match OFF, Order + Wallet ON | `1998.74` | `822.99` | `12.15s` | `0` | Confirm timers roughly unchanged: Match `10.712s`, Order `10.560s`, Wallet `10.435s` |

Decision:

- Do not enable batch-confirm mode by default.
- The experiment does not prove a durable throughput improvement over TPS-93 (`833.58` median, `729.71-940.93` range).
- MatchEngine batch confirm is actively suspicious in this local setup because channel-level confirm waiting with `publish-concurrency=4` made the Match confirm timer much worse.
- Order/Wallet batch confirm is not a meaningful win; the current per-correlation future loop likely already collapses most waiting into the first future(s) that observe broker confirms.

Conclusion:

- Outbox publisher-confirm cost is real, but the bottleneck is not simply "Java waits once per event".
- The next optimization should not keep drilling into `CorrelationData.getFuture()` versus `waitForConfirmsOrDie`.
- More useful next targets:
  - reduce durable outbox / marker writes;
  - reduce MatchEngine `TradeExecuted + trade_outbox` transaction cost;
  - reduce Redis reservation / completion round trips only if crash-recovery semantics stay intact;
  - inspect Order trade-apply batch SQL and Match completion marker insert cost as the current visible tail.

### TPS-95 - OrderTradeApplied application-table relay experiment

Status: **rejected; correctness passed but throughput regressed**

Hypothesis:

- Order trade apply currently writes:
  - one `order_service.order_trade_applications` row as the idempotent trade-application fact;
  - two `order_service.order_matching_state` updates;
  - one generic `order_service.order_event_outbox` row for `OrderTradeAppliedEvent`.
- Because `OrderTradeAppliedEvent` is derived from the trade-application fact, we tested whether the completion-marker relay could use `order_trade_applications` itself as the retryable relay source.
- This mirrored the successful Wallet TPS-88 settlement-table relay, but with a stricter risk:
  - `order_trade_applications` is also on the Order trade-apply hot path;
  - pending scans and `SENT` updates may contend with inserts into the same fact table.

Implementation tested:

- Added experimental relay columns to `order_trade_applications`:
  - `event_status`;
  - `attempt_count`;
  - `next_retry_at`;
  - `last_error`;
  - `updated_at`.
- Changed Order trade application inserts to set new rows `PENDING` and skip the generic `order_event_outbox` row for `OrderTradeAppliedEvent`.
- Added an `OrderTradeAppliedRelay` that:
  - selected pending `order_trade_applications`;
  - rebuilt `OrderTradeAppliedEvent`;
  - published to RabbitMQ with publisher confirms;
  - marked the fact rows `SENT` after confirm.
- Added temporary `eap_order_trade_applied_relay_*` metrics and actuator collection.

Correctness verification:

- `eap-order ./gradlew --no-daemon testClasses`: PASS.
- `OrderEventAppenderPostgresIT`: PASS.
- 500 smoke passed:
  - `GLT_TPS95_ORDER_TRADE_APPLIED_RELAY_SMOKE_500`;
  - `completedTrades=500`;
  - `tradeExecutions=500`;
  - `orderCommandMatchedRows=1000`;
  - `walletTradeSettlements=500`;
  - final queues/DLQ `0`.
- DB checks after smoke:
  - `order_trade_applications`: `SENT=500`;
  - generic `OrderTradeAppliedEvent` rows in `order_event_outbox`: `0`.

10k capacity result:

| Run | Actual input TPS | Business completed TPS | Business completion seconds | Final queues/DLQ | Key signal |
| --- | ---: | ---: | ---: | --- | --- |
| `GLT_TPS95_ORDER_TRADE_APPLIED_RELAY_LIGHT_10K_R1` | `1999.10` | `619.67` | `16.14s` | `0` | New OrderTradeApplied relay confirm `13.301s`; batch `13.855s` |

Comparison to accepted baseline:

| Metric | TPS-93 median | TPS-95 experiment |
| --- | ---: | ---: |
| `businessCompletedTradeTps` | `833.58` | `619.67` |
| `businessCompletionSeconds` | `12.00s` | `16.14s` |
| Order generic outbox rows for `OrderTradeAppliedEvent` | `10000` | `0` |
| Order trade-applied relay confirm sum | n/a | `13.301s` |
| Order trade-applied relay batch sum | n/a | `13.855s` |

Decision:

- Reject this design and do not keep it in the default code path.
- The code and local loadtest DB were cleaned back to the generic Order outbox path:
  - removed the experimental `OrderTradeAppliedRelay`;
  - removed temporary relay metrics and loadtest config;
  - removed `order-es-019` from the changelog;
  - dropped the experimental columns/index from the local loadtest DB and removed the `databasechangelog` row.
- No TPS-95 implementation code is kept in the default path.

Interpretation:

- Reducing a durable row is not automatically a throughput win.
- TPS-88 worked for Wallet because `trade_settlements` already is the settlement fact, idempotency key, and marker relay source, and it removed a generic outbox row without adding contention to the hottest insert path in the same way.
- Order is closer to the rejected MatchEngine TPS-89 experiment:
  - the hot fact table becomes both the high-rate insert target and the relay queue;
  - the relay must scan pending rows and update `event_status` on that same table;
  - publisher-confirm cost still exists, just under a different relay.
- Next Order work should improve the existing trade-apply CTE / generic outbox path rather than merging relay state into `order_trade_applications`.

### TPS-96 - Order trade-apply stable `unnest` batch SQL probe

Status: **rejected; correctness passed but Order batch cost regressed**

Hypothesis:

- Order trade apply uses one CTE to insert `order_trade_applications`, update two `order_matching_state` rows, and insert one generic `OrderTradeAppliedEvent` outbox row.
- The existing implementation builds a dynamic `VALUES (:tradeId0, ... :tradeIdN)` SQL string per batch size.
- We tested whether switching the batch input to a stable PostgreSQL array/`unnest` shape would reduce parse/plan overhead and improve the `batch_append` phase.

Implementation tested:

- Changed `OrderEventAppender.insertTradeApplicationsMatchingStatesAndOutboxes(...)` to bind 24 JDBC arrays and feed the CTE with `unnest(...)`.
- Preserved the same durable-write semantics:
  - `order_trade_applications` insert;
  - two `order_matching_state` updates per trade;
  - generic `order_event_outbox` insert for `OrderTradeAppliedEvent`;
  - same idempotency and completion marker behavior.

Verification:

- `eap-order ./gradlew --no-daemon testClasses`: PASS.
- `OrderEventAppenderPostgresIT`: PASS.
- 500 smoke passed:
  - `GLT_TPS96_ORDER_BATCH_UNNEST_SMOKE_500`;
  - `completedTrades=500`;
  - `tradeExecutions=500`;
  - `orderCommandMatchedRows=1000`;
  - `walletTradeSettlements=500`;
  - final queues/DLQ `0`.

10k capacity result:

| Run | Actual input TPS | Business completed TPS | Business completion seconds | Final queues/DLQ | Key signal |
| --- | ---: | ---: | ---: | --- | --- |
| `GLT_TPS96_ORDER_BATCH_UNNEST_LIGHT_10K_R1` | `1990.13` | `687.76` | `14.54s` | `0` | Order `batch_total=15.553s`, `batch_append=7.592s` |

Comparison to accepted TPS-93 R2:

| Metric | TPS-93 R2 dynamic `VALUES` | TPS-96 stable `unnest` |
| --- | ---: | ---: |
| `businessCompletedTradeTps` | `940.93` | `687.76` |
| `businessCompletionSeconds` | `10.63s` | `14.54s` |
| Order `batch_total` cumulative | `9.256s / 1108` | `15.553s / 1321` |
| Order `batch_append` cumulative | `5.164s / 1108` | `7.592s / 1321` |
| Match `try_match` cumulative | `34.368s` | `58.343s` |
| Match `reserve_order.redis_eval` cumulative | `15.888s` | `29.779s` |

Decision:

- Reject this change and keep the dynamic `VALUES` CTE path.
- The code was reverted after the 10k run.
- Stable `unnest` helped the Match completion-marker insert path earlier because it replaced many individual insert executions with fewer batch-shaped SQL calls. In Order trade apply, the existing path was already one CTE per listener batch, and the array construction/binding plus changed planner behavior did not reduce the hot-path cost.

Interpretation:

- This confirms that the current Order issue is not primarily SQL text-shape churn.
- The cost is more likely from the required durable-write chain itself:
  - fact insert;
  - conditional state updates;
  - generic outbox insert;
  - transaction/commit cost;
  - downstream marker convergence.
- Next work should inspect whether any durable writes are still semantically redundant, and separately measure MatchEngine durable write + Redis reservation costs instead of tuning Order batch input syntax.

### TPS-97 - Integrated stage-lag diagnostics and Redis user-index repeat

Status: **diagnostic implemented; user-index removal still rejected as TPS fix**

Problem:

- Isolated DB ceiling probes and isolated outbox relay probes are much faster than the full E2E business gate.
- The remaining question is where the integrated pipeline spends wall-clock time after `TradeExecuted` is durable:
  - Order apply and `OrderTradeAppliedEvent` relay;
  - Wallet settlement and `WalletTradeSettledEvent` relay;
  - MatchEngine completion-marker consumption and convergence.
- We also repeated the Redis user-open-order index OFF test under the newer TPS-93 benchmark shape to avoid relying on an older baseline.

Implementation:

- Added integrated stage-lag diagnostics to `scripts/load-test/collect-loadtest-diagnostics.sh`.
- The diagnostics produce:
  - `integrated-stage-lag.tsv`: per-trade timestamps and derived lag columns;
  - `integrated-stage-lag.md`: p50/p95/p99/max attribution table.
- Added a `stage-lag` diagnostics phase so stage lag can be regenerated after a run without overwriting actuator snapshots.
- Updated `scripts/load-test/summarize-write-costs.sh` to embed the integrated stage-lag report in `write-cost-summary.md`.

Timestamp semantics:

- Match time uses `match_engine.trade_executions.created_at`.
- Order time uses `OrderTradeAppliedEvent` rows in `order_service.order_event_outbox`:
  - `created_at` approximates Order apply + outbox write completion;
  - `published_at` is relay mark-SENT after RabbitMQ confirm, not downstream delivery time.
- Wallet currently has no immutable settlement-insert timestamp after the settlement-table relay change:
  - Wallet relay timing uses `wallet_service.trade_settlements.updated_at` after mark-SENT;
  - Wallet marker timing uses `match_engine.trade_completion_markers.created_at`.
- Completion-marker timing uses marker-row `created_at`, not the business `marker_at` payload timestamp.

Execution note:

- In the Codex sandbox, direct `docker` commands may work because the prefix is approved, but bash loadtest scripts can still fail to access Docker socket when run sandboxed.
- For full loadtest scripts, run the whole bash command with escalated permissions so nested Docker calls can inspect containers.

10k result:

| Run | User index | Actual input TPS | Business completed TPS | Business completion seconds | Final queues/DLQ |
| --- | --- | ---: | ---: | ---: | --- |
| `GLT_TPS97_MATCH_USER_INDEX_OFF_LIGHT_10K_R1` | off | `1999.03` | `749.07` | `13.35s` | `0` |

Correctness:

- `completedTrades=10000`;
- `tradeExecutions=10000`;
- `orderCommandMatchedRows=20000`;
- `walletTradeSettlements=10000`;
- `activeReservations=0`;
- final queues/DLQ `0`.

Integrated stage-lag result:

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Match persisted -> Order outbox created | `10000` | `1157.940` | `1870.780` | `2050.420` | `2227.300` |
| Order outbox created -> relay mark-SENT | `10000` | `947.645` | `1572.260` | `1755.770` | `1759.910` |
| Order outbox created -> ORDER_APPLIED marker | `10000` | `784.159` | `1103.730` | `1384.960` | `1521.470` |
| Match persisted -> Wallet settlement relay mark-SENT | `10000` | `2031.670` | `2748.560` | `3279.780` | `3521.920` |
| Match persisted -> WALLET_SETTLED marker | `10000` | `1837.900` | `2540.090` | `2832.850` | `2959.090` |
| Match persisted -> both completion markers | `10000` | `1936.800` | `2696.000` | `2944.340` | `3064.600` |
| Order/Wallet marker skew | `10000` | `121.223` | `408.391` | `688.296` | `1007.060` |

Interpretation:

- Redis user-open-order index OFF still does not improve completed-business TPS:
  - latest result `749.07` is inside the TPS-93 accepted range (`729.71-940.93`) and below the `833.58` median;
  - `reserve_order.redis_eval=19.784s`, worse than TPS-93 R2 `15.888s`.
- The integrated lag points to pipeline convergence, not one isolated primitive:
  - Order marker path p95 is about `1.10s` after Order outbox creation;
  - Wallet marker path p95 is about `2.54s` after Match trade persistence;
  - full marker convergence p95 is about `2.70s`.
- The next useful target is therefore Wallet/Order integrated relay and marker timing, especially the absence of an immutable Wallet settlement inserted-at timestamp and the Wallet relay/marker path attribution gap.

### TPS-98 - Wallet settlement inserted timestamp for durable-chain attribution

Status: **implemented; smoke and 10k attribution verified**

Problem:

- TPS-97 showed the Wallet marker path was a major part of integrated completion lag, but Wallet timing was still too coarse.
- `wallet_service.trade_settlements.settled_at` is the business/event timestamp from `TradeExecutedEvent.occurredAt`, not the actual Wallet DB insert time.
- `wallet_service.trade_settlements.updated_at` is overwritten by the Wallet settlement-table relay when the row is marked `SENT`, so it measures relay state update time, not immutable settlement apply time.
- Because of that, the stage-lag report could not separate:
  - Match persisted -> Wallet settlement inserted;
  - Wallet settlement inserted -> relay mark-SENT;
  - Wallet settlement inserted -> WALLET_SETTLED marker.

Implementation:

- Added `wallet_service.trade_settlements.inserted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP`.
- Mapped it on `TradeSettlementEntity` as a DB-generated, read-only field.
- Updated `scripts/load-test/collect-loadtest-diagnostics.sh` integrated stage-lag output:
  - Wallet settlement apply time now uses `trade_settlements.inserted_at`;
  - Wallet relay mark-SENT time still uses `trade_settlements.updated_at`;
  - the report now emits Wallet inserted-to-mark-SENT and inserted-to-marker lag.

Verification:

- `scripts/load-test/collect-loadtest-diagnostics.sh`: `bash -n` PASS.
- `scripts/load-test/summarize-write-costs.sh`: `bash -n` PASS.
- `eap-wallet ./gradlew --no-daemon testClasses`: PASS.
- `TradeExecutedListenerTest` + `WalletTradeSettlementRelayTest`: PASS.
- DB schema check confirmed `inserted_at`, `settled_at`, and `updated_at` are all `NOT NULL` timestamp columns.

Smoke run:

| Run | Events | Target input TPS | Actual input TPS | Completed trades | Wallet settlements | Business completed TPS | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS98_WALLET_INSERTED_AT_SMOKE_500` | `500` | `500` | `500.45` | `500` | `500` | `347.72` | `0` |

Smoke integrated stage-lag:

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Match persisted -> Order outbox created | `500` | `111.434` | `205.782` | `223.210` | `233.449` |
| Order outbox created -> relay mark-SENT | `500` | `53.053` | `177.674` | `184.912` | `217.787` |
| Order outbox created -> ORDER_APPLIED marker | `500` | `73.925` | `200.014` | `207.877` | `242.812` |
| Match persisted -> Wallet settlement inserted | `500` | `107.799` | `196.459` | `218.370` | `229.248` |
| Wallet settlement inserted -> relay mark-SENT | `500` | `55.945` | `181.096` | `181.572` | `181.572` |
| Wallet settlement inserted -> WALLET_SETTLED marker | `500` | `79.475` | `201.589` | `203.126` | `203.396` |
| Match persisted -> Wallet settlement relay mark-SENT | `500` | `190.344` | `370.026` | `398.976` | `409.233` |
| Match persisted -> WALLET_SETTLED marker | `500` | `214.962` | `389.081` | `417.811` | `431.057` |
| Match persisted -> both completion markers | `500` | `214.962` | `400.213` | `422.594` | `460.599` |
| Order/Wallet marker skew | `500` | `6.201` | `133.196` | `136.185` | `177.819` |

Interpretation:

- This change is observability for attribution, not a throughput optimization.
- The 500-event smoke only proves the schema, listener/relay tests, completion gate, and new stage-lag output are healthy.
- The 10k attribution run below compares:
  - Match persisted -> Wallet settlement inserted;
  - Wallet settlement inserted -> relay mark-SENT;
  - Wallet settlement inserted -> WALLET_SETTLED marker;
  - Order marker path under the same load.

10k attribution run:

| Run | Events | Target input TPS | Actual input TPS | Completed trades | Wallet settlements | Business completed TPS | Business completion seconds | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS98_WALLET_STAGE_LAG_LIGHT_10K_R1` | `10000` | `2000` | `1998.69` | `10000` | `10000` | `622.05` | `16.08s` | `0` |

10k integrated stage-lag:

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Match persisted -> Order outbox created | `10000` | `1376.800` | `2063.280` | `2264.800` | `2360.510` |
| Order outbox created -> relay mark-SENT | `10000` | `761.885` | `1541.130` | `1666.210` | `2196.440` |
| Order outbox created -> ORDER_APPLIED marker | `10000` | `607.320` | `1106.000` | `1216.490` | `1361.970` |
| Match persisted -> Wallet settlement inserted | `10000` | `1377.050` | `2073.250` | `2259.820` | `2402.370` |
| Wallet settlement inserted -> relay mark-SENT | `10000` | `753.197` | `1483.760` | `1666.040` | `1864.450` |
| Wallet settlement inserted -> WALLET_SETTLED marker | `10000` | `588.312` | `1172.450` | `1297.540` | `1475.380` |
| Match persisted -> Wallet settlement relay mark-SENT | `10000` | `2195.310` | `2986.370` | `3161.670` | `3504.050` |
| Match persisted -> WALLET_SETTLED marker | `10000` | `2028.470` | `2642.170` | `2734.440` | `3052.270` |
| Match persisted -> both completion markers | `10000` | `2079.520` | `2823.170` | `3132.790` | `3356.190` |
| Order/Wallet marker skew | `10000` | `101.227` | `438.262` | `626.393` | `908.847` |

10k Wallet metrics:

| Metric | Value |
| --- | ---: |
| Wallet settlement batches | `1621` |
| Wallet settlement batch-applied count | `1374` |
| Wallet settlement singleton fallback count | `247` |
| Wallet average settlement batch size | `6.17` |
| Wallet max settlement batch size | `25` |
| Wallet settlement CTE cumulative time | `10.768s` |
| Wallet settlement batch cumulative time | `13.542s` |
| Wallet settlement relay batches | `30` |
| Wallet settlement relay batch cumulative time | `13.204s` |
| Wallet settlement relay confirm cumulative time | `12.538s` |
| Wallet settlement relay mark-SENT cumulative time | `0.255s` |

Interpretation from 10k:

- Wallet settlement insertion is not independently lagging behind Order apply:
  - `Match persisted -> Order outbox created` p95 is `2063.280ms`;
  - `Match persisted -> Wallet settlement inserted` p95 is `2073.250ms`.
- Wallet after-insert completion cost is visible but not the first limiter:
  - `Wallet settlement inserted -> WALLET_SETTLED marker` p95 is `1172.450ms`;
  - `Wallet settlement inserted -> relay mark-SENT` p95 is `1483.760ms`.
- Relay `mark-SENT` SQL is not the problem by itself (`0.255s` cumulative for 30 update batches).
- Wallet relay confirm/batch wall-clock is non-trivial, but previous TPS-94 batch-confirm A/B did not prove a stable completed-TPS gain. Treat it as a possible targeted A/B, not the main durable-write fix.
- This run reinforces that the primary full-chain limiter is still the integrated durable pipeline from Match intake/trade persistence into Order and Wallet consumers:
  - input publish reached `1998.69 TPS`;
  - `tradeExecutionReachTps` was only `654.84`;
  - `businessCompletedTradeTps` was `622.05`;
  - `maxMatchEngineQueueReady=5610`, much larger than downstream ready backlogs.

### TPS-99 - MatchEngine tryMatch outcome attribution

Status: **implemented; smoke verified; needs 10k attribution run**

Problem:

- TPS-98 pointed back at MatchEngine, but the existing `match_engine_try_match_duration` metric mixed two different workloads:
  - resting orders that find no opposite order and are added to the Redis orderbook;
  - incoming orders that match, persist `TradeExecuted`, complete Redis reservation, and enter the durable outbox pipeline.
- This made the result look contradictory because previous checks showed Redis orderbook admission can be fast, while the latest full-chain run still showed MatchEngine as the first backlog point.
- The contradiction is mostly measurement granularity:
  - `try_match` count is order confirmations (`SELL + BUY`);
  - `businessCompletedTradeTps` is completed trades after the incoming BUY phase and downstream gates.

Implementation:

- Added `match_engine_try_match_outcome_duration_seconds{outcome=...}` with outcomes:
  - `added_to_book`;
  - `fully_matched`;
  - `matched_with_remainder`;
  - `no_op`.
- Kept the original `match_engine_try_match_duration_seconds` total timer for backward comparison.
- No matching behavior, Redis Lua script, DB write, outbox, or completion gate was changed.

Verification:

- `eap-matchEngine ./gradlew --no-daemon testClasses`: PASS.
- `MatchingEngineServiceTest` + `JpaTradeExecutionRecorderTest` + `RedisOrderBookServiceTest`: PASS.

Smoke run:

| Run | Events | Target input TPS | Actual input TPS | Orderbook admission TPS | Business completed TPS | Completed trades | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS99_MATCH_OUTCOME_SMOKE_500` | `500` | `500` | `492.58` | `1973.05` | `375.36` | `500` | `0` |

Smoke outcome metrics:

| Outcome | Count | Cumulative seconds | Mean ms |
| --- | ---: | ---: | ---: |
| `added_to_book` | `500` | `0.822s` | `1.644ms` |
| `fully_matched` | `500` | `2.515s` | `5.030ms` |
| `matched_with_remainder` | `0` | `0.000s` | n/a |
| `no_op` | `0` | `0.000s` | n/a |

Interpretation:

- The smoke confirms the metric splits the two-phase workload correctly:
  - the 500 resting SELL confirmations are classified as `added_to_book`;
  - the 500 incoming BUY confirmations are classified as `fully_matched`.
- In this smoke, fully matched orders cost about `3.06x` more than orderbook admission by mean timer (`5.030ms / 1.644ms`).
- The next useful run is a 10k light/deep run to compare outcome timers under full pressure:
  - if `added_to_book` stays cheap but `fully_matched` dominates, focus on Redis reserve + DB recordTrade + complete reservation;
  - if both outcomes grow together, inspect orderConfirmed listener dispatch, Redis connection pressure, and queue intake;
  - if `recordTrade` remains stable but `tradeExecutionReachTps` is low, inspect RabbitMQ consumer delivery or thread scheduling around MatchEngine intake.

10k attribution run:

| Run | Events | Target input TPS | Actual input TPS | Orderbook admission TPS | Business completed TPS | Business completion seconds | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS99_MATCH_OUTCOME_LIGHT_10K_R1` | `10000` | `2000` | `1996.50` | `3112.23` | `580.10` | `17.24s` | `0` |

10k outcome and MatchEngine metrics:

| Metric | Count | Cumulative seconds | Mean ms |
| --- | ---: | ---: | ---: |
| `try_match` total | `20000` | `49.928s` | `2.496ms` |
| `try_match outcome=added_to_book` | `10000` | `20.594s` | `2.059ms` |
| `try_match outcome=fully_matched` | `10000` | `29.333s` | `2.933ms` |
| `reserve_order` total | `20000` | `28.639s` | `1.432ms` |
| `reserve_order.redis_eval` | `20000` | `27.705s` | `1.385ms` |
| `recordTrade.transaction_total` | `10000` | `14.283s` | `1.428ms` |
| `recordTrade.insert_trade_outbox` | `10000` | `8.892s` | `0.889ms` |
| `recordTrade.commit_gap` | `10000` | `5.158s` | `0.516ms` |
| `complete_reservation` | `10000` | `6.378s` | `0.638ms` |
| Match trade outbox confirm | `10000` | `15.015s` | `1.502ms` |

10k integrated lag:

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Match persisted -> Order outbox created | `10000` | `1337.800` | `3860.880` | `4250.650` | `4721.350` |
| Match persisted -> Wallet settlement inserted | `10000` | `1342.110` | `3864.600` | `4254.960` | `4641.680` |
| Match persisted -> both completion markers | `10000` | `2137.330` | `4851.510` | `5438.360` | `5842.560` |

Interpretation from 10k:

- TPS99 confirms the earlier contradiction was a metric-boundary issue, not a reversal of previous findings.
- `added_to_book` is no longer negligible under full pressure:
  - 10k resting-order admission costs `20.594s` cumulative;
  - 10k fully matched orders cost `29.333s` cumulative.
- The common cost is `reserve_or_add` Redis Lua:
  - `reserve_order.redis_eval` accounts for `27.705s / 28.639s` of reserve time.
- Fully matched orders add the durable trade path on top:
  - `recordTrade.transaction_total=14.283s`;
  - `complete_reservation=6.378s`;
  - trade outbox confirm `15.015s`.
- Full E2E completed TPS dropped to `580.10`, below TPS-98 `622.05` and below the TPS-93 median `833.58`. Treat this as an attribution run, not a new performance baseline.
- Next useful optimization target should be MatchEngine `reserve_or_add` / orderConfirmed intake semantics before another broad concurrency change:
  - inspect Redis Lua and key access pattern under 20k order confirmations;
  - consider whether the two-phase load model should isolate resting-order admission and incoming-order completion in separate capacity tests;
  - only revisit DB/outbox confirm after the Redis/intake cost is separated from business completion cost.

### Future Epic - GCP/GKE production-like benchmark

Status: **recorded; deferred until local benchmark evidence is clean**

Decision:

- Local Docker/Desktop benchmark results are valid for code-path attribution and interview engineering evidence, but they are not a production-like capacity claim.
- A GCP/GKE benchmark should be opened as a separate epic after the current local work is stable enough to avoid paying cloud cost to debug local measurement or correctness issues.
- Do not use GCP/GKE numbers to replace the current local benchmark story until the deployment topology, resource limits, data stores, and correctness gates are documented.

Why this matters:

- Local tests share CPU, memory, Docker networking, load generator, PostgreSQL containers, Redis, and RabbitMQ on one machine.
- A cloud run adds real network hops, Kubernetes scheduling, persistent-disk and managed-service behavior, node sizing, broker/storage topology, and cloud observability overhead.
- Those factors are exactly what make the result more externally credible, but they also introduce more variables. Running cloud tests too early would make current bottleneck attribution harder, not easier.

Proposed cloud benchmark scope:

| Item | Initial direction |
| --- | --- |
| Platform | GKE Standard first, so node shape and resource requests/limits are explicit for benchmark reproducibility. |
| Services | Order, Wallet, MatchEngine, RabbitMQ, Redis, and load generator deployed with documented replicas and resource limits. |
| PostgreSQL | Cloud SQL PostgreSQL or one clearly documented PostgreSQL topology per service; record CPU, memory, disk type, IOPS, connection limits, and flags. |
| Redis | Memorystore or GKE Redis with `noeviction` benchmark gate and memory headroom recorded. |
| RabbitMQ | GKE StatefulSet or managed-equivalent topology with publisher confirm, queue ready/unacked, DLQ, and disk alarms monitored. |
| Load generator | Prefer a separate node pool or external runner so generator CPU/network does not silently cap service throughput. |
| Observability | Managed Prometheus / Cloud Monitoring plus the existing business correctness gate. |

Minimum cloud acceptance gates:

- Exact Git commits and container image digests are recorded.
- GKE cluster, node pool, CPU/memory requests, limits, HPA setting, DB/RabbitMQ/Redis topology, and region/zone are documented.
- The same TPS semantics are preserved:
  - orderbook admission TPS;
  - TradeExecuted reach TPS;
  - business-completed trade TPS;
  - blended market-flow TPS when using the two-phase workload.
- Final correctness still requires completed counts, Order rows, Wallet settlements, completion markers, final measured queue ready/unacked `0`, DLQ `0`, and no remaining Redis reservations/orderbook leftovers.
- Result tables include median/min/max across repeated runs, not a best single run.
- Cost guard is defined before execution, including maximum runtime, machine types, and teardown commands.

Local-first exit criteria before opening the cloud epic:

1. Commit the current local benchmark/code changes with clean service snapshots.
2. Re-run the latest 10k light benchmark at least three times and classify the result as accepted/rejected with reasons.
3. Keep one medium or formal steady-state correctness run green after the latest durable-write/reservation changes.
4. Update `docs/performance-report.md` and `docs/benchmarks/2026-07-public-benchmark.md` so local claims are internally consistent before adding GCP/GKE claims.

Candidate first ticket:

| ID | Priority | Task | Owner | Acceptance Criteria |
| --- | --- | --- | --- | --- |
| GCP-TPS-01 | P0 | Design GCP/GKE benchmark architecture and cost guard | Architect + Performance | Document topology, resource sizing, managed-vs-self-hosted datastore choice, expected cost envelope, teardown plan, benchmark commands, metrics, and correctness gates. No deployment is required in this ticket. |

### TPS-105 to TPS-108 - outbox relay index and confirm-cost attribution

Status: **Match relay select fix accepted; batch-confirm flags rejected as default tuning**

Context:

- A noisy 10k stress repeat showed final business completion degrading to `332.32 completed trades/s`.
- Integrated lag attributed the long tail to the gap after Match persisted `TradeExecuted` and before Order/Wallet durable work became visible.
- Application timers showed the immediate culprit was MatchEngine outbox relay selection:
  - slow run `trade_outbox_select_duration_seconds_sum=23.784829s`;
  - slow run `trade_outbox_select_duration_seconds_max=3.575777s`.
- The existing partial retry index was:
  - `idx_trade_outbox_pending_retry(next_retry_at, created_at) WHERE status='PENDING'`.
- The hot relay query drains pending rows by durable creation order:
  - `WHERE status='PENDING' AND next_retry_at <= CURRENT_TIMESTAMP ORDER BY created_at, id LIMIT ?`.

Change:

- Added a MatchEngine partial index aligned with the hot relay drain order:

```sql
CREATE INDEX IF NOT EXISTS idx_trade_outbox_pending_created_id
ON match_engine.trade_outbox(created_at, id)
WHERE status = 'PENDING';
```

Verification:

- `TradeOutboxRelayTest` + `JpaTradeExecutionRecorderTest`: PASS.
- 10k light run `GLT_TPS105_MATCH_OUTBOX_INDEX_LIGHT_10K_R1`: PASS, final measured queues/DLQ `0`.

Observed impact:

| Run | Change | Actual input TPS | Business completed TPS | Business completion seconds | Match outbox select sum | Match outbox select max | Final queues/DLQ |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Slow reference | before hot relay index | n/a | `332.32` | `30.09s` | `23.784829s` | `3.575777s` | `0` |
| `GLT_TPS105_MATCH_OUTBOX_INDEX_LIGHT_10K_R1` | add pending-created index | `9745.05` | `824.64` | `12.13s` | `0.414843s` | `0.019853s` | `0` |

Interpretation:

- The relay select long tail was real and index-related.
- The new `created_at, id` partial index fixes the hot scan/order path for normal pending drain.
- Keep the old retry index for now:
  - it protects delayed retry scans when many failed rows have future `next_retry_at`;
  - removing it could save some write amplification on `PENDING` insert and `SENT` update, but risks expensive retry scans under failure backlog.
- Record as future squeeze point only:
  - A/B removing `idx_trade_outbox_pending_retry` may be useful later, but only with both normal 10k load and a retry-backlog scenario.

Publisher-confirm A/B:

| Run | Batch-confirm config | Business completed TPS | Business completion seconds | TradeExecuted reach TPS | Max Match ready | Key signal |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS105_MATCH_OUTBOX_INDEX_LIGHT_10K_R1` | all OFF | `824.64` | `12.13s` | `824.64` | `1225` | current best comparable run |
| `GLT_TPS106_BATCH_CONFIRM_ALL_LIGHT_10K_R1` | Match + Order + Wallet ON | `613.79` | `16.29s` | `638.75` | `5036` | worse queue backlog and completion |
| `GLT_TPS107_MATCH_BATCH_CONFIRM_ONLY_LIGHT_10K_R1` | Match ON only | `725.18` | `13.79s` | `746.16` | `3189` | Match batch confirm alone regressed |
| `GLT_TPS108_DOWNSTREAM_BATCH_CONFIRM_ONLY_LIGHT_10K_R1` | Order + Wallet ON only | `772.34` | `12.95s` | `834.52` | `2647` | downstream batch confirm was not a win |

Confirm-cost readings:

| Run | Match confirm sum | Order confirm sum | Wallet settlement relay confirm sum |
| --- | ---: | ---: | ---: |
| `TPS105` all OFF | `10.247074s` | `9.899103s` | `9.709595s` |
| `TPS106` all ON | `54.411997756s` | `12.825280740s` | `12.488236662s` |
| `TPS107` Match ON only | `46.861912753s` | `11.020499s` | `11.001504s` |
| `TPS108` Order + Wallet ON only | `10.715506s` | `10.629510904s` | `10.512364097s` |

Decision:

- Do not enable `batch-confirm-enabled` by default for MatchEngine, Order, or Wallet in the 10k loadtest profile.
- The current batch-confirm metrics can overstate per-message confirm cost because batch wall-clock is re-recorded across messages. Use batch duration and business gate timing when interpreting these runs.
- Publisher confirm cost is still real, but the naive fix is not "wait once per batch".
- Next improvement should be narrower:
  - split relay batch wall-clock into publish enqueue, confirm wait, mark-SENT, and scheduler gap;
  - compare RabbitMQ confirm wall-clock against downstream marker creation, not only cumulative timer sums;
  - avoid broad consumer-count tuning unless a specific relay or queue shows under-drain after the phase metrics are separated.

### TPS-109 - relay phase metrics

Status: **implemented; smoke verified**

Purpose:

- TPS-105 to TPS-108 confirmed that cumulative confirm timers alone are not enough to decide whether the cost is RabbitMQ publisher confirm, Java relay scheduling, publish enqueue, or database mark-SENT.
- Add finer phase metrics to the three completion relays without changing reliable-publication semantics:
  - MatchEngine `TradeOutboxRelay`;
  - Order `OrderEventOutboxRelay`;
  - Wallet `WalletTradeSettlementRelay`.

New metrics:

| Relay | Publish stage | Confirm wall-clock | Post-confirm mark gap |
| --- | --- | --- | --- |
| MatchEngine TradeExecuted outbox | `trade_outbox_publish_stage_duration_seconds` | `trade_outbox_confirm_wall_duration_seconds` | `trade_outbox_post_confirm_mark_gap_duration_seconds` |
| Order outbox | `eap_order_outbox_publish_stage_duration_seconds` | `eap_order_outbox_confirm_wall_duration_seconds` | `eap_order_outbox_post_confirm_mark_gap_duration_seconds` |
| Wallet settlement relay | `eap_wallet_trade_settlement_relay_publish_stage_duration_seconds` | `eap_wallet_trade_settlement_relay_confirm_wall_duration_seconds` | `eap_wallet_trade_settlement_relay_post_confirm_mark_gap_duration_seconds` |

Interpretation:

- Keep using existing metrics for the other phases:
  - `*_select_duration_seconds`;
  - `*_publish_enqueue_duration_seconds`;
  - `*_confirm_duration_seconds`;
  - `*_mark_sent_duration_seconds`;
  - `*_batch_duration_seconds`.
- Prefer `*_confirm_wall_duration_seconds` when deciding whether publisher confirm is actually delaying a relay batch.
- Treat `*_confirm_duration_seconds` as a backward-compatible per-message/cumulative view; it can be misleading when batch confirm mode records an averaged duration per message.
- `*_post_confirm_mark_gap_duration_seconds` should normally be near zero. If it grows, investigate Java scheduling, executor starvation, or code between confirm completion and mark-SENT.

Smoke verification:

| Run | Events | Target input TPS | Actual input TPS | Business completed TPS | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS109_RELAY_PHASE_METRICS_SMOKE_500` | `500` | `1000` | `998.08` | `413.65` | `0` |

Smoke metric presence:

| Metric | Count | Sum |
| --- | ---: | ---: |
| `trade_outbox_publish_stage_duration_seconds` | `4` | `0.025532s` |
| `trade_outbox_confirm_wall_duration_seconds` | `4` | `0.227566s` |
| `trade_outbox_post_confirm_mark_gap_duration_seconds` | `4` | `0.000006s` |
| `eap_order_outbox_publish_stage_duration_seconds` | `4` | `0.021124s` |
| `eap_order_outbox_confirm_wall_duration_seconds` | `4` | `0.174362s` |
| `eap_order_outbox_post_confirm_mark_gap_duration_seconds` | `4` | `0.000032s` |
| `eap_wallet_trade_settlement_relay_publish_stage_duration_seconds` | `4` | `0.058616s` |
| `eap_wallet_trade_settlement_relay_confirm_wall_duration_seconds` | `4` | `0.178224s` |
| `eap_wallet_trade_settlement_relay_post_confirm_mark_gap_duration_seconds` | `4` | `0.000008s` |

Next run:

- Run the latest 10k light benchmark with these metrics enabled.
- Compare `confirm_wall`, `publish_stage`, `mark_sent`, and integrated stage lag before changing relay code.
- Prefer code-path fixes over broad tuning if a single phase dominates.

### TPS-110 - 10k light relay phase attribution

Status: **completed; publisher-confirm wall-clock is the dominant relay phase**

Run:

| Run | Events | Target input TPS | Actual input TPS | Business completed TPS | Business completion seconds | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS110_RELAY_PHASE_METRICS_LIGHT_10K_R1` | `10000` | `10000` | `9974.85` | `787.41` | `12.70s` | `0` |

Throughput split:

| Metric | Value |
| --- | ---: |
| Orderbook admission TPS | `4888.46` |
| TradeExecuted reach TPS | `908.50` |
| Order command match reach TPS | `813.62` |
| Wallet settlement reach TPS | `813.62` |
| Completion marker reach TPS | `787.41` |
| Blended market flow TPS | `1356.34` |

Relay phase timers:

| Relay | Batch sum | Confirm wall sum | Publish stage sum | Publish enqueue sum | Mark-SENT sum | Post-confirm mark gap |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MatchEngine `trade_outbox` | `12.008487s` | `11.193571s` | `0.531806s` | `0.928575s` | `0.153428s` | `0.000071s` |
| Order outbox | `11.404403s` | `10.968683s` | `0.148122s` | `0.141779s` | `0.191908s` | `0.000073s` |
| Wallet settlement relay | `11.441370s` | `10.917118s` | `0.224538s` | `0.216649s` | `0.236588s` | `0.000081s` |

Interpretation:

- At 10k offered BUY TPS, all three completion relays spend most of their batch wall-clock in RabbitMQ publisher-confirm waiting.
- Java post-confirm scheduling is not the issue in this run:
  - all `*_post_confirm_mark_gap_duration_seconds_sum` values are near zero.
- DB `mark-SENT` is visible but not dominant:
  - each relay spent about `0.15-0.24s` cumulative marking `10000` records `SENT`.
- Publish enqueue / message build is small for Order and Wallet, but MatchEngine enqueue is larger:
  - MatchEngine `publish_enqueue=0.928575s`;
  - still much smaller than MatchEngine `confirm_wall=11.193571s`.
- The completion tail still ends at `matchEngine.walletTradeSettled.queue`, but the new metrics suggest the relay bottleneck is not the code between confirm completion and mark-SENT.

Next investigation:

- Treat RabbitMQ publisher confirms as a real fixed cost under full business completion.
- Do not re-enable batch-confirm flags by default; TPS-106 to TPS-108 already rejected that broad approach.
- Look for code-path improvements around how many durable relay publications are required per trade, and only then revisit broker-confirm strategy with a narrower correctness-preserving design.

### TPS-111 - Remove Order/Wallet completion-marker relay from the hot path

Status: **completed for marker removal; 10k durable gate exposed an Order inbound reliability gap**

Decision:

- Stop treating per-trade `OrderTradeAppliedEvent` and `WalletTradeSettledEvent` callbacks to MatchEngine as part of the business hot path.
- Keep the durable facts that matter for correctness:
  - MatchEngine: `match_engine.trade_executions`;
  - Order: `order_service.order_trade_applications` plus `order_service.order_matching_state`;
  - Wallet: `wallet_service.trade_settlements` plus wallet balance invariants.
- Define `completedTrades` in the load test as the lower bound of those three durable fact counts, not as `trade_completion_markers` convergence.
- Keep final RabbitMQ ready/unacked drain and DLQ checks in the benchmark gate.

Rationale:

- TPS-110 showed that the Order and Wallet marker relays were dominated by RabbitMQ publisher-confirm wall-clock:
  - Order outbox confirm wall sum: `10.968683s`;
  - Wallet settlement relay confirm wall sum: `10.917118s`.
- Those callbacks were used to let MatchEngine maintain a convenience completion view. They were not required for Order to apply a trade or Wallet to settle it.
- Requiring every downstream service to publish an acknowledgement back to MatchEngine creates an open-ended consistency loop: once those acknowledgements exist, they themselves need retry, idempotency, queue drain, and monitoring.
- The cheaper consistency check is post-run or diagnostic reconciliation over durable state, not two more per-trade relay publications.

Implementation:

- Order trade application no longer creates a generic `OrderTradeAppliedEvent` row in `order_event_outbox`.
- Wallet settlement no longer publishes `WalletTradeSettledEvent` back to MatchEngine.
- After TPS-120, `trade_settlements` is only the Wallet settlement fact/idempotency table:
  - `trade_id`;
  - `legacy_match_id`;
  - `settled_at`;
  - `inserted_at`.
- `MatchedE2eLoadGenerator` now reports:
  - `completedTrades` = `min(trade_executions, order_trade_applications, trade_settlements)`;
  - `businessConvergenceReachTps` as the new durable-state convergence rate;
  - `completionMarkerReachTps` remains as a backward-compatible alias during the transition.
- Integrated stage-lag diagnostics now use durable facts:
  - `trade_executions.created_at`;
  - `order_trade_applications.applied_at`;
  - `trade_settlements.inserted_at`.

Expected effect:

- Remove two per-trade downstream-to-MatchEngine relay publications from the measured business completion chain.
- Remove two publisher-confirm tails that were not contributing to business correctness.
- Preserve the ability to verify consistency through durable-state counts, wallet balance invariants, final queue drain, DLQ checks, and targeted reconciliation queries.

Follow-up:

- Open the next ticket for Order `TradeExecuted` inbound inbox/replay before treating 10k completed-business TPS as stable.
- After Order inbound replay is fixed, rerun 10k light and then retire unused MatchEngine completion-marker listeners/tables and old relay metrics from the active load-test documentation.

Smoke verification:

| Run | Events | Target input TPS | Actual input TPS | Durable completed trades | Business TPS | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS111_MARKER_REMOVED_SMOKE_500` | `500` | `1000` | `999.17` | `500` | `536.29` | `0` |

Smoke correctness and removal checks:

- `tradeExecutions=500`;
- `orderCommandMatchedRows=1000`;
- `walletTradeSettlements=500`;
- `completedTrades=500`;
- `businessConvergenceReachTps=536.29`;
- `finalQueueBacklog=0`;
- `activeReservations=0`;
- marker queues stayed unused:
  - `maxOrderTradeAppliedQueueUnacked=0`;
  - `maxWalletTradeSettledQueueUnacked=0`;
  - final `orderTradeAppliedQueueReady=0`;
  - final `walletTradeSettledQueueReady=0`.

Post-run DB checks:

- Order generic `OrderTradeAppliedEvent` outbox rows for this market: `0`.
- Wallet `trade_settlements` for this market: `SENT=500`, `PENDING=0`.
- MatchEngine `trade_completion_markers` rows for this market: `0`.

Updated integrated-stage lag:

| Stage | p50 | p95 | p99 | max |
| --- | ---: | ---: | ---: | ---: |
| Match persisted -> Order trade application | `0.722ms` | `0.959ms` | `0.968ms` | `0.975ms` |
| Match persisted -> Wallet settlement inserted | `146.185ms` | `216.815ms` | `224.773ms` | `228.983ms` |
| Match persisted -> durable convergence | `146.185ms` | `216.815ms` | `224.773ms` | `228.983ms` |

10k light comparison:

| Run | Events | Target input TPS | Actual input TPS | Result | Match trades | Order applied trades | Wallet settlements | Final queues/DLQ |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- |
| `GLT_TPS111_MARKER_REMOVED_LIGHT_10K_R1` | `10000` | `10000` | `9967.13` | `REJECTED_ORDER_DURABLE_GAP` | `10000` | `9979` | `10000` | `0` |

10k finding:

- Removing Order/Wallet marker relay worked as intended:
  - `matchEngine.orderTradeApplied.queue` stayed unused;
  - `matchEngine.walletTradeSettled.queue` stayed unused;
  - MatchEngine marker listener metrics stayed at `0`;
  - final queues and DLQ were `0`.
- The new durable-state gate exposed a real Order-side gap:
  - `tradeExecutions=10000`;
  - `walletTradeSettlements=10000`;
  - `order_trade_applications=9979`;
  - `order_matching_state MATCHED=19958`, `OPEN=42`;
  - the 42 open rows map to 21 unique missing trades.
- MatchEngine trade facts were clean:
  - `10000` trade rows;
  - `10000` distinct `trade_id`;
  - `10000` distinct buyer orders;
  - `10000` distinct seller orders.
- Wallet settlement facts were also clean:
  - `10000` settlement rows;
  - all new rows used `event_status='SENT'`;
  - no Wallet marker relay work remained.

Interpretation:

- The previous completion-marker path was not a good enough proof of Order durable application.
- After marker removal, the correct business gate is now stricter and caught that Order can finish with `order.tradeExecuted.queue=0` while some `TradeExecuted` facts are not represented in `order_trade_applications`.
- A temporary Order batch durability guard was tested and removed because it did not catch this failure mode; the missing work is not proven to be "batch SQL returned success but wrote fewer rows."
- Setting Order `trade-executed.batch-size=1` was started as a probe but was too slow to be a practical fix. The solution should not be permanent single-message handling.

Next ticket direction:

- Add an Order-side durable inbound inbox for `TradeExecuted` before acking the RabbitMQ delivery, or add an equivalent replayable downstream delivery mechanism.
- The inbox/replay should make these states distinguishable:
  - received but not applied;
  - applied;
  - duplicate/redelivered;
  - failed and retryable.
- Completion consistency can then be verified cheaply by durable-state reconciliation without reintroducing per-trade callbacks from Order/Wallet to MatchEngine.

### 2026-07-23 - TPS-112 Order `TradeExecuted` inbound inbox and manual ACK

Status: completed and verified with 500 smoke + 10k light.

Problem found by TPS-111:

- After removing Order/Wallet per-trade completion-marker callbacks, the 10k durable gate exposed a real Order gap:
  - MatchEngine had `trade_executions=10000`;
  - Wallet had `trade_settlements=10000`;
  - Order only had `order_trade_applications=9979`;
  - final RabbitMQ queues and DLQ were still `0`.
- That meant broker drain alone was not a sufficient proof that Order had durably applied every `TradeExecuted`.

Implementation:

- Added `order_service.order_trade_execution_inbox`:
  - `trade_id` primary key;
  - buyer/seller order IDs;
  - deal price and quantity;
  - raw payload text;
  - `status IN ('RECEIVED', 'APPLIED', 'FAILED_RETRYABLE')`;
  - `attempt_count`, `received_at`, `applied_at`, `last_error`, `updated_at`.
- Changed `TradeExecutedListener` to manual RabbitMQ ACK:
  - deserialize message batch;
  - insert/upsert inbox rows as `RECEIVED`;
  - apply Order trade state;
  - mark inbox rows `APPLIED`;
  - ACK only after durable apply succeeds.
- On apply failure:
  - mark inbox rows `FAILED_RETRYABLE`;
  - `basicNack(..., requeue=true)`.
- On payload deserialization failure:
  - `basicNack(..., requeue=false)` so malformed messages can go to DLQ instead of looping.
- Updated load-test cleanup to truncate the new inbox table.
- Updated light diagnostics to emit `order-trade-executed-inbox-status.txt`.

Additional bug fixed during smoke:

- First smoke revealed retry was working but also exposed a fallback SQL bug:
  - some singleton/fallback Order trade applies failed once with PostgreSQL `could not determine data type of parameter $27`;
  - cause: after removing `OrderTradeAppliedEvent`, the individual trade-apply SQL still passed null outbox parameters without casts;
  - fix: cast nullable outbox parameters in the SQL (`uuid`, `varchar`, `text`) before checking/inserting them.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-order ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` | PASS |
| `eap-order ./gradlew --no-daemon testClasses` | PASS |
| `bash -n scripts/load-test/collect-loadtest-diagnostics.sh scripts/load-test/run-2000-ticket-marker-repeat.sh scripts/load-test/summarize-write-costs.sh` | PASS |
| `GLT_TPS111_ORDER_INBOX_SQLCAST_SMOKE_500` | PASS |
| `GLT_TPS111_ORDER_INBOX_LIGHT_10K_R2` | PASS |

500 smoke after SQL cast:

| Run | Events | Actual input TPS | Completed trades | Business convergence TPS | Inbox status | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| `GLT_TPS111_ORDER_INBOX_SQLCAST_SMOKE_500` | `500` | `1953.46` | `500` | `520.42` | `APPLIED=500`, `attempt_count=1..1`, `unapplied=0` | `0` |

10k light after inbox/manual ACK:

| Run | Events | Target input TPS | Actual input TPS | Completed trades | Business convergence TPS | Queue drain seconds | Final queues/DLQ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS111_ORDER_INBOX_LIGHT_10K_R2` | `10000` | `10000` | `9982.07` | `10000` | `974.85` | `10.26` | `0` |

10k durable facts:

- `tradeExecutions=10000`;
- `orderCommandMatchedRows=20000`;
- `completedTrades=10000`;
- `walletTradeSettlements=10000`;
- `activeReservations=0`;
- Order inbox:
  - `APPLIED=10000`;
  - `min_attempt=1`;
  - `max_attempt=1`;
  - `unapplied=0`.
- Marker callback queues stayed removed from the measured path:
  - `maxOrderTradeAppliedQueueUnacked=0`;
  - `maxWalletTradeSettledQueueUnacked=0`.

10k integrated-stage lag:

| Stage | Count | p50 | p95 | p99 | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Match persisted -> Order trade application | `10000` | `0.242ms` | `1.997ms` | `2.062ms` | `2.125ms` |
| Match persisted -> Wallet settlement inserted | `10000` | `1468.590ms` | `1949.550ms` | `2097.470ms` | `2217.900ms` |
| Match persisted -> durable convergence | `10000` | `1468.590ms` | `1949.550ms` | `2097.470ms` | `2217.900ms` |

Interpretation:

- The previous 10k `9979/10000` Order gap is fixed.
- The new Order inbox is not a completion-marker replacement; it is an Order-owned inbound reliability boundary.
- The current durable convergence bottleneck is no longer Order apply. Order reaches trade application within ~2ms p99 after Match persistence in this run.
- The remaining durable convergence tail is dominated by Wallet settlement, which matches the previous attribution that final business TPS is limited by downstream durable settlement rather than Redis matching or Order state application.
- A failed first 10k rerun was caused by local MatchEngine readiness timeout after seed, not by transaction correctness. The effective rerun used `LOADTEST_SERVICE_START_TIMEOUT_SECONDS=240`.

### 2026-07-23/24 - TPS-113 to TPS-115 Wallet settlement SQL and Match outbox relay batch probe

Status: partially completed.

Problem:

- After removing Order/Wallet completion-marker callbacks and adding the Order inbound inbox, the remaining durable tail was concentrated in the downstream durable write chain.
- `wallet.tradeExecuted.queue` was repeatedly the last non-zero queue, but MatchEngine `trade_outbox_confirm_wall_duration_seconds` was also a large fixed cost in 10k runs.
- The target was to reduce real durable write/relay cost, not to retune consumer concurrency.

Implementation:

- Wallet settlement appender:
  - removed the batch-level `existing_settlements` preselect that made one duplicate force whole-batch fallback;
  - changed batch insert to `ON CONFLICT (trade_id) DO NOTHING`;
  - allowed mixed idempotent batches where existing settlements are skipped and new settlements update wallets;
  - recorded duplicate skipped count when a batch contains already-settled trades.
- Wallet settlement hot insert:
  - stopped explicitly writing relay lifecycle columns that are not needed when `WalletTradeSettled` marker relay is disabled;
  - `event_status`, `attempt_count`, and `updated_at` now use DB defaults;
  - `next_retry_at` remains `NULL`;
  - updated `WalletDbCeilingProbe` to match the production settlement SQL shape.
- MatchEngine loadtest profile:
  - added `EAP_MATCH_TRADE_OUTBOX_BATCH_SIZE` so the Match `TradeExecuted` outbox relay batch size can be A/B tested without changing source defaults.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest` | PASS |
| `eap-wallet ./gradlew --no-daemon testClasses` | PASS |
| `GLT_TPS113_WALLET_BATCH_IDEMPOTENT_SMOKE_500` | PASS |
| `GLT_TPS114_WALLET_SETTLEMENT_DEFAULTS_SMOKE_500` | PASS |

DB default check after TPS-114 smoke:

| Run | Total settlements | `SENT` | `attempt_count=0` | `next_retry_at IS NULL` | `updated_at IS NOT NULL` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `GLT_TPS114_WALLET_SETTLEMENT_DEFAULTS_SMOKE_500` | `500` | `500` | `500` | `500` | `500` |

10k light comparison:

| Run | Notes | Actual input TPS | Completed trades | Business convergence TPS | Completion seconds | Last non-zero queue | Final queues/DLQ |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: |
| `GLT_TPS111_ORDER_INBOX_LIGHT_10K_R2` | Order inbox baseline | `9982.07` | `10000` | `974.85` | `10.26` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS113_WALLET_BATCH_IDEMPOTENT_LIGHT_10K_R1` | Wallet duplicate-safe batch | `9980.15` | `10000` | `865.58` | `11.55` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS113_WALLET_BATCH_IDEMPOTENT_LIGHT_10K_R2` | Wallet duplicate-safe batch | `9918.41` | `10000` | `910.82` | `11.29` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS114_WALLET_SETTLEMENT_DEFAULTS_LIGHT_10K_R1` | Wallet relay-field defaults | `9776.46` | `10000` | `734.75` | `13.79` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS115_MATCH_OUTBOX_BATCH1000_LIGHT_10K_R1` | Match outbox batch-size 1000 | `9980.36` | `10000` | `1154.89` | `8.66` | `order.tradeExecuted.queue` | `0` |
| `GLT_TPS115_MATCH_OUTBOX_BATCH1000_LIGHT_10K_R2` | Match outbox batch-size 1000 | `9980.30` | `10000` | `814.45` | `12.28` | `wallet.tradeExecuted.queue` | `0` |

Targeted timer comparison:

| Run | Match outbox batches | Match confirm wall sum | Match mark-SENT sum | Wallet settlement batch sum | Wallet settlement CTE sum |
| --- | ---: | ---: | ---: | ---: | ---: |
| `TPS113_R2` | `22` | `9.329s` | `0.258s` | `7.495s` | `5.700s` |
| `TPS114_R1` | `21` | `11.450s` | `0.250s` | `8.751s` | `6.667s` |
| `TPS115_R1` | `14` | `6.803s` | `0.089s` | `6.341s` | `5.221s` |
| `TPS115_R2` | `13` | `10.060s` | `0.114s` | `6.795s` | `5.643s` |

Interpretation:

- Wallet duplicate-safe batch is a correctness and retry-path improvement. It removes unnecessary batch fallback when duplicates are present.
- Wallet relay-field defaults are safe and keep settlement facts correct, but the 10k business TPS effect is small relative to local run noise.
- Match outbox relay batch-size 1000 has a clear mechanism and one strong run:
  - fewer relay batches;
  - lower mark-SENT cost;
  - potentially lower publisher confirm wall time.
- The second batch-size 1000 run was much weaker, so `1000` should not become the default yet.
- The reliable conclusion is that Match outbox publisher confirm is a major durable relay cost. The next performance ticket should run a controlled matrix for Match outbox batch size, for example `500/750/1000/1500`, with at least three 10k light runs per setting, and should compare confirm wall, tradeExecutionReachTps, business convergence, and duplicate replay blast radius.

Current recommendation:

- Keep `EAP_MATCH_TRADE_OUTBOX_BATCH_SIZE` as an A/B knob.
- Do not claim stable 1150 TPS yet.
- Treat the current stable local range as roughly 800-1000 completed trades/s under 10k offered-load, with a best observed 1154.89 TPS after reducing Match outbox relay batch boundaries.

### 2026-07-24 - TPS-116 Match outbox relay confirm strategy check

Status: completed.

Question:

- Earlier relay batching and publisher-confirm changes were introduced as plausible optimizations, but the current code path needed a direct A/B check.
- The target was to validate MatchEngine `TradeExecuted` outbox relay cost, specifically:
  - `batch-size=500` with the current per-message `CorrelationData` confirm wait;
  - `batch-size=500` with `RabbitOperations.waitForConfirmsOrDie(...)` batch confirm;
  - existing `batch-size=1000` per-message runs from TPS-115.

Runs:

| Run | Strategy | Actual input TPS | Valid capacity comparison | Completed trades | Business convergence TPS | Completion seconds | Last non-zero queue | Final backlog |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- | ---: |
| `GLT_TPS116_MATCH_CONFIRM_B500_PERMSG_LIGHT_10K_R1` | batch 500, per-message confirm | `9967.27` | yes | `10000` | `974.50` | `10.26` | `order.tradeExecuted.queue` | `0` |
| `GLT_TPS116_MATCH_CONFIRM_B500_BATCHCONFIRM_LIGHT_10K_R1` | batch 500, batch confirm | `9431.36` | no, driver under-offered | `10000` | `1111.31` | `9.00` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS116_MATCH_CONFIRM_B500_BATCHCONFIRM_LIGHT_10K_R2` | batch 500, batch confirm | `9707.55` | yes | `10000` | `965.26` | `10.36` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS115_MATCH_OUTBOX_BATCH1000_LIGHT_10K_R1` | batch 1000, per-message confirm | `9980.36` | yes | `10000` | `1154.89` | `8.66` | `order.tradeExecuted.queue` | `0` |
| `GLT_TPS115_MATCH_OUTBOX_BATCH1000_LIGHT_10K_R2` | batch 1000, per-message confirm | `9980.30` | yes | `10000` | `814.45` | `12.28` | `wallet.tradeExecuted.queue` | `0` |

Match relay timer comparison:

| Run | Outbox batches | Batch duration sum | Confirm wall count | Confirm wall sum | Publish stage sum | Mark-SENT sum | Select sum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TPS116_B500_PERMSG_R1` | `21` | `9.685s` | `21` | `8.812s` | `0.501s` | `0.220s` | `0.455s` |
| `TPS116_B500_BATCHCONFIRM_R1` | `21` | `8.478s` | `84` | `30.404s` | `8.117s` | `0.202s` | `0.440s` |
| `TPS116_B500_BATCHCONFIRM_R2` | `21` | `9.875s` | `84` | `36.339s` | `9.578s` | `0.157s` | `0.436s` |
| `TPS115_B1000_PERMSG_R1` | `14` | `7.752s` | `14` | `6.803s` | `0.661s` | `0.089s` | `0.558s` |
| `TPS115_B1000_PERMSG_R2` | `13` | `11.486s` | `13` | `10.060s` | `0.966s` | `0.114s` | `0.815s` |

Interpretation:

- `batch-confirm=true` is not proven better on the current chain.
  - R1 showed a higher completed TPS, but the load driver did not meet the offered-load threshold, so it is not a clean capacity comparison.
  - R2 was valid and landed at `965.26` completed trades/s, effectively equal to the `500 + per-message` baseline (`974.50`).
- Batch-confirm also changes timer semantics:
  - `publish_stage` includes the batch-level confirm wait;
  - `trade_outbox_confirm_wall_duration_seconds` count becomes chunk-oriented and should not be compared directly to per-message confirm wall count.
- `batch-size=1000` still has a plausible mechanism:
  - fewer relay batches;
  - lower `mark-SENT` work;
  - one strong run at `1154.89` completed trades/s.
- However, `batch-size=1000` also produced a weak valid run at `814.45` completed trades/s with larger Match queue ready peaks, so it is not stable enough to promote as default.

Decision:

- Keep loadtest default at `batch-size=500` and `batch-confirm-enabled=false`.
- Keep `EAP_MATCH_TRADE_OUTBOX_BATCH_SIZE` and `EAP_MATCH_TRADE_OUTBOX_BATCH_CONFIRM_ENABLED` as explicit A/B knobs.
- Do not claim batch-confirm as an accepted optimization.
- The durable relay cost remains real, but the next fix should not be "change confirm mode" by itself. The higher-value target is reducing how many durable relay publications the business flow requires, then retesting relay strategy after the chain is smaller.

### 2026-07-24 - TPS-117/TPS-118 Reduce durable relay bookkeeping

Status: first implementation completed; checkpoint relay smoke verified.

Decision:

- Do not remove the `TradeExecuted` business event.
  - Order and Wallet still need it to update their own durable state.
  - The event remains the integration contract from MatchEngine to downstream services.
- Reduce durable bookkeeping around successful processing:
  - Order success-path idempotency is represented by `order_trade_applications.trade_id`, not by a separate inbox `APPLIED` row.
  - Match reliable publication can be tested with `trade_executions` as the append-only event log plus a relay checkpoint, instead of per-trade `trade_outbox` insert/update rows.

TPS-117 implementation - Order inbox success-path slimming:

- `TradeExecutedListener` now:
  - deserializes the RabbitMQ batch;
  - applies trades through `OrderEventSourcingService.applyTrades(...)`;
  - ACKs only after the durable apply succeeds.
- It no longer writes `order_trade_execution_inbox` on the successful path:
  - no `RECEIVED` row per successful trade;
  - no `APPLIED` update per successful trade.
- `OrderTradeExecutedInbox` now acts as failure/retry diagnostics:
  - `markFailed(...)` performs an upsert to `FAILED_RETRYABLE`;
  - repeated failures increment `attempt_count`;
  - successful processing remains proven by `order_trade_applications`.

TPS-118 implementation - Match checkpoint relay candidate:

- Added `match_engine.trade_publish_checkpoints`:
  - one row per relay name;
  - tracks `last_created_at` + `last_trade_id`;
  - records batch failure attempts and last error without per-trade status rows.
- Added `idx_trade_executions_created_trade_id` for checkpoint scans over durable trade facts.
- Added `TradeExecutionCheckpointRelay` behind `eap.match-engine.trade-checkpoint-relay.enabled`.
- Added `eap.match-engine.trade-outbox.write-enabled`.
  - default remains `true`;
  - checkpoint A/B can set it to `false`, so Match writes only `trade_executions`.
- Loadtest profile can now switch modes:

```bash
EAP_MATCH_TRADE_OUTBOX_WRITE_ENABLED=false
EAP_MATCH_TRADE_OUTBOX_RELAY_ENABLED=false
EAP_MATCH_TRADE_CHECKPOINT_RELAY_ENABLED=true
```

Checkpoint relay semantics:

- Relay reads unpublished rows from `match_engine.trade_executions` after the checkpoint cursor.
- It publishes `TradeExecutedEvent` to the same trade exchange/routing key.
- It advances the checkpoint only after the whole selected batch is broker-confirmed.
- If publish/confirm fails, checkpoint does not advance; the next poll republishes the same batch.
- Duplicate replay is expected and must be absorbed by downstream `trade_id` idempotency:
  - Order: `order_trade_applications.trade_id`;
  - Wallet: `trade_settlements.trade_id`.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-order ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` | PASS |
| `eap-order ./gradlew --no-daemon testClasses` | PASS |
| `eap-matchEngine ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.JpaTradeExecutionRecorderTest --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest` | PASS |
| `eap-matchEngine ./gradlew --no-daemon testClasses` | PASS |
| `GLT_TPS117_118_CHECKPOINT_RELAY_SMOKE_500_R2` | PASS |

Smoke result:

| Run | Mode | Actual input TPS | Completed trades | Business convergence TPS | Completion seconds | Final backlog | Active reservations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `GLT_TPS117_118_CHECKPOINT_RELAY_SMOKE_500_R2` | Match checkpoint relay, no Match outbox write | `1000.53` | `500` | `616.46` | `0.81` | `0` | `0` |

Post-smoke DB checks:

| Check | Value |
| --- | ---: |
| Match `trade_executions` | `500` |
| Match `trade_outbox` | `0` |
| Match `trade_publish_checkpoints` | `1` |
| Match checkpoint `attempt_count` | `0` |
| Order `order_trade_applications` | `500` |
| Order `order_trade_execution_inbox` | `0` |

Known constraints:

- This is not yet the default production path.
- The checkpoint relay is an A/B candidate for loadtest and needs a 10k comparison before acceptance.
- Its current failure behavior is batch-level:
  - a failed publish/confirm keeps the checkpoint fixed;
  - successful messages in the failed batch may be replayed;
  - this intentionally trades per-trade relay bookkeeping for downstream idempotent replay.
- If this becomes the accepted path, add explicit diagnostics for checkpoint lag:
  - latest `trade_executions.created_at` minus checkpoint `last_created_at`;
  - count of rows after checkpoint;
  - checkpoint attempt count and last error.

Next validation:

- Run 10k light A/B:
  - current default: Match outbox write + outbox relay;
  - candidate: no Match outbox write + checkpoint relay.
- Compare:
  - business convergence TPS;
  - Match trade record transaction time;
  - Match relay select/publish/confirm/checkpoint mark time;
  - `trade_outbox` row count;
  - downstream duplicate/failure counts;
  - final queues/DLQ and durable state counts.

10k light A/B result:

| Run | Mode | Actual input TPS | Valid capacity comparison | Completed trades | Business convergence TPS | Completion seconds | Max Match ready | Last non-zero queue | Final backlog |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | ---: |
| `GLT_TPS117_118_BASELINE_OUTBOX_LIGHT_10K_R1` | Default Match outbox relay, Order success inbox removed | `9981.10` | yes | `10000` | `1231.16` | `8.12` | `404` | `wallet.tradeExecuted.queue` | `0` |
| `GLT_TPS117_118_CHECKPOINT_RELAY_LIGHT_10K_R1` | Match checkpoint relay, no Match outbox write | `7777.88` | no - driver under-offered | `10000` | `822.39` | `12.16` | `3107` | `wallet.tradeExecuted.queue` | `0` |

Post-10k checkpoint DB checks:

| Check | Value |
| --- | ---: |
| Match `trade_executions` | `10000` |
| Match `trade_outbox` | `0` |
| Match `trade_publish_checkpoints` | `1` |
| Match checkpoint `attempt_count` | `0` |
| Order `order_trade_applications` | `10000` |
| Order `order_trade_execution_inbox` | `0` |

Timer comparison:

| Metric | Default outbox relay | Checkpoint relay candidate | Interpretation |
| --- | ---: | ---: | --- |
| Match `try_match` sum | `46.694s` | `68.794s` | Candidate put more pressure on MatchEngine. |
| Match `trade_record.transaction_total` | `12.734s` | `28.244s` | Removing the outbox row did not reduce transaction wall time in the full chain. |
| Match `trade_record.transaction_body` | `7.605s` | `18.891s` | Candidate was slower inside the transaction window. |
| Match `trade_record.commit_gap` | `5.129s` | `9.353s` | Candidate also paid a larger commit/transaction gap. |
| Match relay batch duration | `7.369s` | `11.357s` | Current checkpoint relay is not a faster publication path. |
| Match relay confirm wall | `6.537s` | `9.479s` | Candidate confirm path is slower in this implementation. |
| Wallet settlement batch | `6.479s` | `10.441s` | Downstream drain also worsened under candidate pressure. |
| Order apply batch total | `7.086s` | `8.151s` | Order remained correct; cost was not the main regression. |

Decision:

- Accept TPS-117 as a promising hot-path simplification:
  - Order no longer writes a success-path inbox row per `TradeExecuted`;
  - the valid default-relay 10k run reached `1231.16` completed trades/s with `10000/10000` durable completion and zero final backlog.
- Do not accept TPS-118 checkpoint relay as the default path:
  - it is functionally correct in smoke and 10k;
  - it eliminated `trade_outbox` rows as intended;
  - however, the first 10k candidate under-delivered the input driver and completed materially slower than the default relay path.
- Keep these default settings:
  - `eap.match-engine.trade-outbox.write-enabled=true`;
  - `eap.match-engine.trade-outbox-relay.enabled=true`;
  - `eap.match-engine.trade-checkpoint-relay.enabled=false`.

Current interpretation:

- The separate Match `trade_outbox` row is still write amplification, but the current checkpoint relay implementation is not the right replacement.
- The checkpoint candidate likely serializes too much relay work and increases Match-side pressure instead of reducing it.
- If checkpoint relay is revisited, it needs partitioned or parallel checkpoint publishing plus clearer checkpoint-lag diagnostics before another 10k comparison.
- The next useful measurement should either:
  - repeat the default outbox path two more times to confirm the `~1231 TPS` result is stable after TPS-117; or
  - continue with Wallet settlement / Redis reservation costs, because `wallet.tradeExecuted.queue` remained the last queue to drain in the accepted run.

### 2026-07-24 - TPS-119 Remove retired Order trade-applied outbox shape

Status: implemented; 500 smoke verified.

Context:

- TPS-111 removed the downstream-to-MatchEngine completion-marker callbacks from the business hot path.
- TPS-117 changed Order success-path idempotency to rely on `order_trade_applications.trade_id` and made `order_trade_execution_inbox` failure diagnostics only.
- After those changes, Order `TradeExecuted` application still carried old trade-applied outbox support in the SQL shape:
  - `TradeApplicationBatchAppendCommand` still accepted an `OrderIntegrationEvent`;
  - the batch CTE still created outbox arrays;
  - the batch CTE still had an `inserted_outbox` branch;
  - `OrderDbCeilingProbe` still measured the older `trade application + matching state + order_event_outbox` shape.

Decision:

- Do not revive `OrderTradeAppliedEvent` as a hot-path callback.
- Keep Order completion represented by durable Order-owned facts:
  - `order_service.order_trade_applications`;
  - `order_service.order_matching_state`.
- Keep the normal Order event outbox for command-side events such as order submission and asset-reservation flows.
- Remove only the retired trade-applied marker outbox shape from the `TradeExecuted` application path.

Implementation:

- `OrderEventSourcingService` no longer carries a trade-applied integration event through `PreparedTrade`.
- `OrderEventAppender.appendTradeMatchedFromCaughtUpProjectionIfTradeApplicationAbsent(...)` now takes only:
  - buyer command;
  - seller command;
  - matched quantities;
  - `OrderTradeApplication`.
- The single-trade CTE now only:
  - inserts `order_trade_applications`;
  - updates two `order_matching_state` rows.
- The batch CTE now only:
  - checks existing trade applications;
  - inserts `order_trade_applications`;
  - updates buyer/seller `order_matching_state`.
- Removed batch outbox arrays and dead helper code from the trade-application hot path.
- Updated `OrderDbCeilingProbe` to measure the current production shape instead of the retired outbox-marker shape.
- Updated Order event-store integration tests to expect no `order_event_outbox` rows from trade application.

Smoke verification:

| Command / run | Result |
| --- | --- |
| `eap-order ./gradlew --no-daemon testClasses` | PASS |
| `eap-order ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` | PASS |
| `GLT_TPS119_ORDER_TRADE_NO_OUTBOX_SMOKE_500_R1` | PASS |

Smoke result:

| Run | Actual input TPS | Completed trades | Business convergence TPS | Completion seconds | Final backlog | Last non-zero queue |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS119_ORDER_TRADE_NO_OUTBOX_SMOKE_500_R1` | `999.99` | `500` | `545.43` | `0.92` | `0` | `wallet.tradeExecuted.queue` |

Post-smoke DB checks:

| Check | Value |
| --- | ---: |
| Match `trade_executions` | `500` |
| Match `trade_outbox` | `500` |
| Order `order_trade_applications` | `500` |
| Order `order_matching_state MATCHED` | `1000` |
| Order `order_event_outbox` | `0` |
| Order `order_trade_execution_inbox` | `0` |
| Wallet `trade_settlements` | `500` |

Smoke timer notes:

- Order remained correct:
  - `completedTrades=500`;
  - `orderCommandMatchedRows=1000`;
  - final marker callback queues stayed unused.
- Order apply timing in this 500 smoke:
  - `eap_order_trade_apply_duration_seconds{phase="batch_total"}`: `37` batches, `0.595s` cumulative, `16.087ms` mean;
  - `Match persisted -> Order trade application`: p99 `0.692ms`.
- The smoke is not a capacity comparison. It only proves the slimmer Order trade-application SQL shape is functionally valid.

Next validation:

- Run the default 10k light path again with TPS-119 included.
- Compare against `GLT_TPS117_118_BASELINE_OUTBOX_LIGHT_10K_R1`:
  - business convergence TPS;
  - Order `batch_total`, `batch_lock_heads`, and `batch_append`;
  - `order_event_outbox` row count;
  - final queues/DLQ and durable state counts.
- If 10k remains stable, keep TPS-119 as accepted cleanup and continue with Wallet settlement / Redis reservation cost attribution.

10k light validation:

| Run | Actual input TPS | Valid capacity comparison | Completed trades | Business convergence TPS | Completion seconds | Final backlog | Last non-zero queue |
| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS117_118_BASELINE_OUTBOX_LIGHT_10K_R1` | `9981.10` | yes | `10000` | `1231.16` | `8.12` | `0` | `wallet.tradeExecuted.queue` |
| `GLT_TPS119_ORDER_TRADE_NO_OUTBOX_LIGHT_10K_R1` | `9983.56` | yes | `10000` | `1125.85` | `8.88` | `0` | `wallet.tradeExecuted.queue` |

Post-10k DB checks:

| Check | Value |
| --- | ---: |
| Match `trade_executions` | `10000` |
| Match `trade_outbox` | `10000` |
| Order `order_trade_applications` | `10000` |
| Order `order_matching_state MATCHED` | `20000` |
| Order `order_event_outbox` | `0` |
| Order `order_trade_execution_inbox` | `0` |
| Wallet `trade_settlements` | `10000` |

10k timer comparison:

| Metric | TPS-117/118 baseline | TPS-119 | Interpretation |
| --- | ---: | ---: | --- |
| Order `batch_total` | `7.086s` | `7.920s` | No proven Order TPS win in this single run. |
| Order `batch_append` | `3.371s` | `3.952s` | SQL shape is slimmer, but run-to-run noise still dominates. |
| Order `batch_lock_heads` | `2.219s` | `2.524s` | Lock/read phase remains visible. |
| Match persisted -> Order apply p99 | `0.768ms` | `0.923ms` | Still sub-millisecond class; Order is not the long-tail bottleneck. |
| Wallet settlement batch | `6.479s` | `8.618s` | Wallet remains the downstream tail in this run. |
| Match persisted -> Wallet settlement p99 | `2137.560ms` | `2057.550ms` | Durable convergence tail remains Wallet-dominated. |

TPS-119 decision:

- Accept as cleanup and write-model simplification, not as a proven throughput improvement.
- The change removes a retired SQL/Java branch and makes the Order trade-application hot path match the current business definition:
  - no per-trade Order marker callback;
  - no `order_event_outbox` row from trade application;
  - durable Order completion is `order_trade_applications + order_matching_state`.
- The first 10k run landed lower than the previous best valid baseline (`1125.85` vs `1231.16`), so do not claim it increased TPS.
- It is still valuable because it reduces model complexity and keeps future DB ceiling probes aligned with the actual production path.
- Next TPS work should not stay on Order marker cleanup. Continue with:
  - Wallet settlement SQL / batch shape;
  - Match durable write + outbox confirm cost;
  - Redis reservation cost attribution under the same 10k offered-load model.

### 2026-07-24 - TPS-120 Retire Wallet settlement relay state from hot path

Status: implemented; 500 smoke verified.

Context:

- TPS-111 removed per-trade `OrderTradeAppliedEvent` and `WalletTradeSettledEvent` callbacks to MatchEngine from the business completion definition.
- After that change, Wallet completion is represented by Wallet-owned durable state:
  - `wallet_service.trade_settlements`;
  - buyer/seller wallet balance updates;
  - final queue/DLQ drain and balance invariants in the load test.
- `wallet_service.trade_settlements` still carried the older integrated `WalletTradeSettledEvent` relay shape:
  - event payload reconstruction columns: buyer/seller/order IDs, price, quantity, settlement amounts;
  - relay lifecycle columns: `event_status`, `attempt_count`, `next_retry_at`, `last_error`, `updated_at`;
  - partial pending-event index.
- The relay was disabled in default/loadtest config and no longer part of the current business hot path, but every settlement insert still paid the wider-row write cost.

Decision:

- Retire `WalletTradeSettlementRelay` instead of leaving a half-populated relay source.
- Keep `trade_settlements.trade_id` as the Wallet settlement idempotency key and durable settlement fact.
- Keep wallet balance updates in the same transaction as the settlement insert.
- Do not publish `WalletTradeSettledEvent` as a MatchEngine completion callback.

Implementation:

- `WalletTradeSettlementAppender` now inserts only:
  - `trade_id`;
  - `legacy_match_id`;
  - `settled_at`.
- Batch settlement SQL still uses input buyer/seller IDs and settlement amounts for the wallet updates, but it no longer persists those relay payload fields into `trade_settlements`.
- `TradeSettlementEntity` now maps only:
  - `tradeId`;
  - `legacyMatchId`;
  - `settledAt`;
  - `insertedAt`.
- Added Liquibase changeset `wallet-018`:
  - drops the pending-event partial index;
  - drops the old relay payload/lifecycle columns.
- Removed `WalletTradeSettlementRelay` and its focused test.
- Removed dead Wallet relay metrics and loadtest config.
- Updated `WalletDbCeilingProbe` to measure the current settlement fact + two wallet updates shape.
- Updated integrated stage-lag diagnostics to use only immutable `trade_settlements.inserted_at` for Wallet settlement timing.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-wallet ./gradlew --no-daemon testClasses` | PASS |
| `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest` | PASS |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_SMOKE_500_R1` | PASS |

Smoke result:

| Run | Actual input TPS | Valid capacity comparison | Completed trades | Wallet settlements | Business convergence TPS | Completion seconds | Final backlog | Last non-zero queue |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_SMOKE_500_R1` | `999.72` | yes | `500` | `500` | `545.11` | `0.92` | `0` | `wallet.tradeExecuted.queue` |

Post-smoke correctness checks:

| Check | Value |
| --- | ---: |
| `wallet_service.trade_settlements` rows | `500` |
| `lockedCurrency` | `0` |
| `lockedAmount` | `0` |
| Final queue backlog | `0` |
| Queue drain tail after completed trades | `0.00s` |

Post-smoke schema check:

`wallet_service.trade_settlements` now has only:

| Column | Purpose |
| --- | --- |
| `trade_id` | Primary key and settlement idempotency key. |
| `legacy_match_id` | Compatibility / attribution field. |
| `settled_at` | Business/event settlement time. |
| `inserted_at` | Immutable Wallet durable apply timestamp for lag attribution. |

The only remaining index is `trade_settlements_pkey` on `trade_id`.

Smoke timer notes:

- The smoke is not a capacity comparison against the 10k baseline.
- It proves the slimmer Wallet settlement schema is compatible with service startup, Liquibase migration, settlement idempotency, wallet balance updates, and the current completion gate.
- In this 500 smoke, Wallet remained the final durable tail:
  - `Match persisted -> Wallet settlement inserted` p99 `236.542ms`;
  - `Match persisted -> durable convergence` p99 `236.542ms`.

10k light validation:

| Run | Actual input TPS | Valid capacity comparison | Completed trades | Business convergence TPS | Completion seconds | Final backlog | Last non-zero queue |
| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS117_118_BASELINE_OUTBOX_LIGHT_10K_R1` | `9981.10` | yes | `10000` | `1231.16` | `8.12` | `0` | `wallet.tradeExecuted.queue` |
| `GLT_TPS119_ORDER_TRADE_NO_OUTBOX_LIGHT_10K_R1` | `9983.56` | yes | `10000` | `1125.85` | `8.88` | `0` | `wallet.tradeExecuted.queue` |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_LIGHT_10K_R1` | `9964.05` | yes | `10000` | `1309.83` | `7.63` | `0` | `order.tradeExecuted.queue` |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_LIGHT_10K_R2` | `9871.39` | yes | `10000` | `815.44` | `12.62` | `0` | `order.tradeExecuted.queue` |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_LIGHT_10K_R3` | `9963.34` | yes | `10000` | `1172.64` | `8.53` | `0` | `order.tradeExecuted.queue` |

TPS-120 repeat summary:

| Metric | Value |
| --- | ---: |
| Runs | `3` |
| Completed trades per run | `10000/10000` |
| Valid capacity comparisons | `3/3` |
| Actual input TPS avg | `9932.93` |
| Business convergence TPS avg | `1099.30` |
| Business convergence TPS median | `1172.64` |
| Business convergence TPS min / max | `815.44` / `1309.83` |
| Completion seconds avg | `9.59s` |
| Completion seconds min / max | `7.63s` / `12.62s` |

Post-10k correctness checks:

| Check | Value |
| --- | ---: |
| Match `trade_executions` | `10000` |
| Order `order_trade_applications` / command matched rows | `10000` / `20000` |
| Wallet `trade_settlements` | `10000` |
| Wallet `lockedCurrency` / `lockedAmount` | `0` / `0` |
| Final queues / DLQ | `0` |
| Queue drain tail after completed trades | `0.00s` |

10k timer comparison:

| Metric | TPS-119 | TPS-120 | Interpretation |
| --- | ---: | ---: | --- |
| Business completion seconds | `8.88s` | `7.63s` | Full durable convergence improved in this run. |
| Business convergence TPS | `1125.85` | `1309.83` | `+16.3%` versus TPS-119; `+6.4%` versus TPS-117/118 baseline. |
| Match `try_match` sum | `41.273s` | `33.419s` | Match-side work also improved in this run; do not attribute the full gain only to Wallet schema slimming. |
| Match `trade_record.transaction_total` | `14.417s` | `10.112s` | Lower transaction wall time helped the whole chain. |
| Wallet settlement batch sum | `8.618s` | `14.378s` | Batch wall-clock cumulative increased, so this timer alone does not explain the TPS win. |
| Wallet settlement CTE sum | `6.993s` | `8.412s` | Cumulative SQL timer did not fall; mean changed with the observed count. Treat with caution. |
| Match persisted -> Wallet settlement p99 | `2057.550ms` | `1881.940ms` | Wallet durable tail improved but still dominates durable convergence. |
| Match persisted -> Order trade application p99 | `0.923ms` | `1.548ms` | Order remains sub-2ms from Match persistence in this run. |

TPS-120 decision:

- Accept as an architecture and write-model cleanup.
- Correctness held across all three 10k light repeats:
  - `10000/10000` completed every run;
  - input driver valid every run;
  - final queues/DLQ drained every run;
  - Wallet balance invariants held every run.
- Do not claim a stable `1300 TPS` result:
  - R1 reached `1309.83 TPS`;
  - R2 fell to `815.44 TPS`;
  - R3 recovered to `1172.64 TPS`;
  - the three-run average is `1099.30 TPS`, with median `1172.64 TPS`.
- The repeat result shows the current 10k burst workload still has significant run-to-run noise.
- R2's outlier had `maxMatchEngineQueueReady=3501`, pointing to MatchEngine input/matching backlog rather than Wallet settlement loss or broken correctness.
- The important durable-state model improvement should stay regardless of repeat-run noise:
  - Wallet settlement is now one idempotency/fact row plus two wallet balance updates;
  - the retired `WalletTradeSettledEvent` relay source is gone from the hot path;
  - completion is verified by durable state and final queue/DLQ drain, not another callback loop.

Next validation:

- Do not publish the single-run `1309.83 TPS` as a stable benchmark.
- For public/performance-report numbers, prefer median/range or a longer steady-state workload.
- Continue attribution on the remaining variable tail:
  - Wallet listener batch fragmentation and transaction wall time;
  - Match `trade_outbox` confirm wall;
  - Redis reservation/completion eval cost under 10k offered load.

100k / 10s long-pressure probe:

| Run | Target input TPS | Actual input TPS | Valid capacity comparison | Completed trades | Business convergence TPS | Completion seconds | Final backlog |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| `GLT_TPS120_WALLET_SETTLEMENT_SLIM_LIGHT_100K_R1` | `10000` | `7267.42` | no: `driver_offered_tps_below_threshold` | `100000` | `1122.11` | `89.51` | `0` |

Correctness result:

- `100000/100000` trades completed.
- Match `trade_executions=100000`.
- Order command matched rows `200000`.
- Wallet `trade_settlements=100000`.
- Wallet `lockedCurrency=0`, `lockedAmount=0`.
- Final queues and DLQ drained to `0`.

Capacity interpretation:

- This is not a valid `10k input TPS` capacity result because the publisher only achieved `7267.42/s`.
- The run is still useful as a long-pressure diagnostic because the offered load was far above the completed-business rate.
- `matchEngine.orderConfirmed.queue` peaked at `87847` ready messages and was the first large backlog.
- `tradeExecutionReachTps=1313.97`, while durable business convergence was `1122.11`.
- The long-pressure result supports this current capacity model:
  - MatchEngine can persist `TradeExecuted` faster than the full business chain can converge.
  - Order application is not the long tail: `Match persisted -> Order trade application` p99 was `0.949ms`.
  - Wallet settlement remains the durable convergence tail after Match persistence: `Match persisted -> Wallet settlement inserted` p99 was `17821.000ms`.
  - The first large queue backlog is before MatchEngine processing, so the next throughput work should start with MatchEngine intake/matching cost, not downstream marker callbacks.

100k app timer highlights:

| Rank | Timer | Count | Cumulative seconds | Mean ms | Interpretation |
| ---: | --- | ---: | ---: | ---: | --- |
| 1 | `match_engine_try_match_duration` | `200000` | `566.575s` | `2.833` | Main MatchEngine intake/matching work. |
| 2 | `match_engine_try_match_outcome{fully_matched}` | `100000` | `464.774s` | `4.648` | Incoming BUY matched path is expensive under long pressure. |
| 3 | `match_engine_reserve_order` | `200000` | `245.346s` | `1.227` | Reservation / add path cost. |
| 4 | `match_engine_reserve_order_phase{redis_eval}` | `200000` | `239.505s` | `1.198` | Redis Lua eval dominates reserve/add. |
| 5 | `match_engine_complete_reservation` | `100000` | `181.620s` | `1.816` | Second Redis Lua call after durable trade insert. |
| 7 | `match_engine_complete_reservation_phase{redis_eval}` | `100000` | `180.551s` | `1.806` | Completion Lua eval is also a major fixed cost. |
| 13 | `match_engine_trade_record.transaction_total` | `100000` | `136.009s` | `1.360` | Durable trade execution + outbox transaction. |
| 20 | `trade_outbox_confirm_wall` | `219` | `69.844s` | `318.922` | Broker confirm wall-clock remains visible. |

Next fix candidates from the long-pressure probe:

1. Review MatchEngine Redis orderbook mutation shape:
   - `reserveBestMatchOrAddOrderWithSequenceLua(...)` currently serializes the incoming order and executes one reserve/add Lua call for every OrderConfirmed event.
   - Fully matched trades then execute `completeReservedOrder(...)`, adding a second Redis Lua eval per trade.
   - Investigate whether fully matched resting orders can be finalized inside the same atomic reservation/match script after durable persistence constraints are reconsidered, or whether a cheaper post-trade Redis cleanup model is acceptable.
2. Review Match `trade_executions + trade_outbox` transaction:
   - `JpaTradeExecutionRecorder` writes the durable trade fact and one `trade_outbox` row per trade.
   - The row is still needed to publish to Order/Wallet, but the transaction and relay confirm wall are now a visible fixed cost.
   - Check whether publication can be made cheaper without losing retry/reconciliation guarantees.
3. Improve the long-load test driver before claiming 10k sustained input:
   - The 100k run only offered `7267.42/s`;
   - publisher acquire/send times were high;
   - future `100k` benchmark claims need either a stronger driver mode or a lower target that the driver can actually sustain.

### 2026-07-24 - TPS-122 Friday wrap-up: Wallet batch SQL fix and 1200 TPS boundary

Status: implemented; focused tests and three 10k light runs completed.

Context:

- After TPS-120/TPS-121, the current goal was to push correctness-gated completed-business TPS toward `1200`.
- The next suspected tail was still durable write / relay cost, but Wallet batch metrics showed a concrete defect:
  - `eap_wallet_trade_settlement_batch_applied_total=0`;
  - `eap_wallet_trade_settlement_batch_fallback_total=940`;
  - `data_integrity` fallback dominated the batch path.
- This meant the Wallet listener was receiving batches but most batches first failed the batch SQL path and then fell back to single-event settlement.

Root cause:

- `WalletTradeSettlementAppender.APPEND_BATCH_SQL` declared 9 input columns but the `unnest(...)` expression only contained 8 placeholders.
- Java bound 9 JDBC arrays, so the SQL shape was invalid for the current batch settlement path.
- The failure was hidden by the designed fallback behavior:
  - correctness remained intact;
  - throughput paid for one failed batch attempt plus many single-event settlement transactions.

Implementation:

- Fixed the Wallet batch SQL placeholder list so it matches the 9 bound arrays.
- Added `WalletTradeSettlementAppenderTest` to assert the batch SQL keeps 9 JDBC placeholders.
- Kept the fallback path intact for singleton batches and exceptional cases.
- Added a small Order listener optimization:
  - successful TradeExecuted batches now use `basicAck(lastDeliveryTag, multiple=true)`;
  - failed batches use `basicNack(lastDeliveryTag, multiple=true, requeue=true)`;
  - single-message behavior remains single-message ACK/NACK.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-wallet ./gradlew --no-daemon test --tests com.eap.eap_wallet.application.TradeExecutedListenerTest --tests com.eap.eap_wallet.application.WalletTradeSettlementAppenderTest` | PASS |
| `eap-order ./gradlew --no-daemon test --tests com.eap.eap_order.application.TradeExecutedListenerTest` | PASS |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_10K_R1` | PASS |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_ORDER_BATCH_ACK_10K_R2` | PASS |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_ORDER_BATCH_ACK_10K_R3` | PASS |

10k light results:

| Run | Actual input TPS | Valid capacity comparison | Completed trades | TradeExecuted reach TPS | Business convergence TPS | Completion seconds | Final backlog | Last non-zero queue |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_10K_R1` | `9975.65` | yes | `10000` | `1224.71` | `1173.58` | `8.52` | `0` | `order.tradeExecuted.queue` |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_ORDER_BATCH_ACK_10K_R2` | `9966.80` | yes | `10000` | `840.17` | `796.77` | `12.55` | `0` | `wallet.tradeExecuted.queue` |
| `GLT_TPS122_WALLET_BATCH_SQL_FIX_ORDER_BATCH_ACK_10K_R3` | `9933.61` | yes | `10000` | `1098.90` | `1017.09` | `9.83` | `0` | `wallet.tradeExecuted.queue` |

Correctness checks across all three runs:

- `completedTrades=10000`.
- `tradeExecutions=10000`.
- `walletTradeSettlements=10000`.
- `lockedCurrency=0`.
- `lockedAmount=0`.
- Final measured queues and DLQ drained to `0`.

Wallet batch validation:

| Metric | Before fix | After fix examples |
| --- | ---: | ---: |
| Batch applied count | `0` | `746` to `912` |
| Batch fallback reason `data_integrity` | high | `0` |
| Remaining fallback reason | `data_integrity`, `singleton_batch` | `singleton_batch` only |

Interpretation:

- Accept the Wallet batch SQL fix as a real hot-path improvement:
  - it removes failed batch attempts;
  - it restores the intended set-based settlement path;
  - it keeps settlement idempotency and wallet invariants intact.
- Do not claim stable `1200` completed-business TPS yet:
  - the best run reached `1173.58`, close to the target;
  - repeat runs still ranged from `796.77` to `1173.58`;
  - MatchEngine input / durable publication showed large run-to-run variance.
- The Order batch ACK change is acceptable as a small RabbitMQ fixed-cost cleanup, but it is not proven to be the TPS driver.

Monday resume target:

1. Continue from MatchEngine durable publication, not consumer concurrency:
   - `match_engine_trade_record.transaction_total`;
   - `insert_trade_outbox`;
   - `trade_outbox_confirm_wall`;
   - RabbitMQ publisher confirm behavior under burst load.
2. Do not accept the current checkpoint relay as a replacement yet:
   - the earlier checkpoint relay 10k probe skipped a trade under active writes;
   - cursor advancement over `(created_at, trade_id)` is unsafe without a stable watermark or gap-handling strategy.
3. Keep the 1200 TPS target, but judge it by repeated valid runs:
   - at least 3 valid 10k light runs;
   - all durable correctness checks must pass;
   - final measured queues and DLQ must drain to zero.

### 2026-07-27 - TPS-123 Match outbox relay attribution

Status: implemented; focused test and one 10k light attribution run completed.

Context:

- The TPS-122 best run reached `1173.58` completed-business TPS but repeatability was still noisy.
- Recent 10k/100k runs repeatedly showed Match `trade_outbox_confirm_wall` as a visible fixed cost.
- The next question was whether Match `TradeExecuted` relay cost came from:
  - selecting and mapping pending outbox rows;
  - rebuilding JSON payload from `trade_executions`;
  - building RabbitMQ messages;
  - waiting for publisher confirms;
  - marking outbox rows `SENT`.

Implementation:

- Added fixed-name Match outbox relay metrics:
  - `trade_outbox_batch_size`;
  - `trade_outbox_confirmed_batch_size`;
  - `trade_outbox_row_mapping_duration`;
  - `trade_outbox_payload_rebuild_duration`;
  - `trade_outbox_message_build_duration`;
  - `trade_outbox_first_confirm_duration`;
  - `trade_outbox_remaining_confirm_duration`.
- Kept existing behavior unchanged:
  - `trade_executions` and `trade_outbox` are still committed together;
  - relay still publishes persistent `TradeExecutedEvent`;
  - relay still waits for broker confirmation before marking rows `SENT`.
- Updated `summarize-write-costs.sh` to emit `Match Trade Outbox Relay Breakdown`.

Verification:

| Command / run | Result |
| --- | --- |
| `eap-matchEngine ./gradlew --no-daemon test --tests com.eap.eap_matchengine.application.TradeOutboxRelayTest` | PASS |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R1` | PASS |

10k light result:

| Metric | Value |
| --- | ---: |
| actualBuyPublishTps | `9972.96` |
| validForCapacityComparison | `true` |
| orderbookAdmissionTps | `4290.91` |
| tradeExecutionReachTps | `1452.25` |
| businessCompletedTradeTps | `1352.14` |
| businessCompletionSeconds | `7.40` |
| completedTrades | `10000` |
| tradeExecutions | `10000` |
| walletTradeSettlements | `10000` |
| finalQueueBacklog | `0` |
| lastNonZeroQueue | `wallet.tradeExecuted.queue` |

Correctness:

- `completedTrades=10000`.
- `tradeExecutions=10000`.
- `walletTradeSettlements=10000`.
- `lockedCurrency=0`.
- `lockedAmount=0`.
- Final measured queues and DLQ drained to `0`.

Match outbox relay attribution:

| Metric | Count | Sum | Max | Mean |
| --- | ---: | ---: | ---: | ---: |
| `batch_size` | `21` | `10000.000000` | `500.000000` | `476.190476` |
| `confirmed_batch_size` | `21` | `10000.000000` | `500.000000` | `476.190476` |
| `batch_duration_seconds` | `21` | `6.508267` | `0.544472` | `0.309917` |
| `select_duration_seconds` | `327` | `0.395980` | `0.044280` | `0.001211` |
| `publish_stage_duration_seconds` | `21` | `0.470856` | `0.283791` | `0.022422` |
| `publish_enqueue_duration_seconds` | `10000` | `0.736596` | `0.003981` | `0.000074` |
| `message_build_duration_seconds` | `10000` | `0.054151` | `0.001241` | `0.000005` |
| `payload_rebuild_duration_seconds` | `10000` | `0.045952` | `0.001208` | `0.000005` |
| `confirm_wall_duration_seconds` | `21` | `5.721056` | `0.511395` | `0.272431` |
| `confirm_duration_seconds` | `10000` | `5.717140` | `0.362514` | `0.000572` |
| `first_confirm_duration_seconds` | `21` | `4.426251` | `0.362514` | `0.210774` |
| `remaining_confirm_duration_seconds` | `9979` | `1.290889` | `0.125266` | `0.000129` |
| `mark_sent_duration_seconds` | `21` | `0.194316` | `0.025190` | `0.009253` |

Interpretation:

- This run crossed the previous 1200 TPS target with `1352.14` completed-business TPS, but it is one attribution run, not a new stable capacity claim.
- JSON payload rebuild is not the bottleneck:
  - `10000` rebuilds took only `0.045952s` total;
  - `10000` message builds took only `0.054151s` total.
- Marking outbox rows `SENT` is also not the dominant relay cost:
  - `21` grouped updates took `0.194316s` total.
- The dominant Match relay cost is RabbitMQ publisher-confirm waiting:
  - confirm wall took `5.721056s` of the `6.508267s` relay batch time;
  - the first confirm in each relay batch/chunk accounted for `4.426251s`.
- This means the current relay spends most of its visible relay time waiting for the broker to durably accept published `TradeExecutedEvent`s, not rebuilding payloads or updating relay state.

Next fix candidates:

1. Repeat the 10k light run at least two more times before accepting `1350+` as a stable class.
2. Investigate Match reliable publication strategy:
   - current per-trade outbox reliability is correct but confirm waiting is still a fixed cost;
   - earlier batch-confirm A/B was worse, so do not blindly switch it on;
   - any replacement must preserve retry/reconciliation and avoid the unsafe checkpoint cursor bug.
3. Keep Wallet as a convergence tail candidate:
   - `Match persisted -> Wallet settlement inserted` p95 was `1663.550ms`;
   - `wallet.tradeExecuted.queue` was the last non-zero queue in this run.

### 2026-07-27 - TPS-123 repeated 10k light confirmation

Status: completed; two additional 10k light runs completed.

Context:

- TPS-123 R1 produced a strong single-run result: `1352.14` completed-business TPS.
- Before accepting that as a stable capacity class, the same workload was repeated twice with unchanged settings:
  - `TARGET_TPS=10000`;
  - `DURATION_SECONDS=1`;
  - `EVENTS=10000`;
  - `PUBLISHERS=128`;
  - `DIAGNOSTICS_LEVEL=light`.

Result summary:

| Run | Actual input TPS | Orderbook admission TPS | TradeExecuted reach TPS | Business completed TPS | Completion seconds | Last non-zero queue | Last non-zero seconds |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R1` | `9972.96` | `4290.91` | `1452.25` | `1352.14` | `7.40` | `wallet.tradeExecuted.queue` | `7.08` |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R2` | `9960.92` | `4331.69` | `1159.43` | `1100.55` | `9.09` | `wallet.tradeExecuted.queue` | `8.62` |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R3` | `9926.81` | `3998.54` | `1234.77` | `1112.06` | `8.99` | `wallet.tradeExecuted.queue` | `8.56` |

Aggregate:

- Mean completed-business TPS: `1188.25`.
- Median completed-business TPS: `1112.06`.
- Range: `1100.55` to `1352.14`.
- Mean TradeExecuted reach TPS: `1282.15`.
- All three runs were valid capacity comparisons.
- All three runs completed `10000/10000` trades.
- All three runs ended with final measured queues and DLQ drained to `0`.

Correctness checks across all three runs:

- `completedTrades=10000`.
- `tradeExecutions=10000`.
- `walletTradeSettlements=10000`.
- `lockedCurrency=0`.
- `lockedAmount=0`.
- `finalQueueBacklog=0`.

Match outbox relay comparison:

| Run | Batch duration sum | Confirm wall sum | First confirm sum | Remaining confirm sum | Mark SENT sum | Payload rebuild sum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | `6.508267s` | `5.721056s` | `4.426251s` | `1.290889s` | `0.194316s` | `0.045952s` |
| R2 | `7.632587s` | `6.591884s` | `4.179253s` | `2.407892s` | `0.204439s` | `0.068983s` |
| R3 | `7.602891s` | `6.914233s` | `5.059197s` | `1.850911s` | `0.227284s` | `0.049241s` |

Integrated stage lag:

| Run | Match -> Order p95 | Match -> Wallet p95 | Match -> Wallet p99 | Durable convergence p99 |
| --- | ---: | ---: | ---: | ---: |
| R1 | `1.356ms` | `1663.550ms` | `1755.730ms` | `1755.730ms` |
| R2 | `0.413ms` | `2135.080ms` | `2429.570ms` | `2429.570ms` |
| R3 | `0.847ms` | `1966.590ms` | `2082.340ms` | `2082.340ms` |

Interpretation:

- Do not claim stable `1350+` completed-business TPS from TPS-123 yet.
- The current measured class is closer to `1100-1200` completed-business TPS on this local 10k light workload:
  - the average is `1188.25`;
  - the two confirmation runs clustered around `1100-1112`.
- The bottleneck evidence is now clearer than before:
  - MatchEngine determines how fast `TradeExecuted` reaches downstream services;
  - Wallet remains the final durable convergence tail after Match persistence;
  - Order application is not the tail in these runs, with Match -> Order p95 below `1.4ms`.
- Match outbox relay confirm is a real fixed cost, but it does not fully explain the R1/R2/R3 spread:
  - R2/R3 confirm wall was about `0.87-1.19s` higher than R1;
  - completed-business time was about `1.59-1.69s` slower than R1;
  - Wallet settlement lag also grew materially in R2/R3.
- Payload rebuild remains ruled out as a meaningful bottleneck:
  - all runs rebuilt `10000` payloads in less than `0.07s` total.

Next action:

1. Inspect Wallet settlement batch path again with the new evidence:
   - Wallet is consistently the last non-zero queue;
   - Match -> Wallet p95/p99 moved with the slower completed-business runs.
2. Inspect Match `trade_record` transaction variability:
   - R1 transaction total: `17.032s`;
   - R2 transaction total: `20.746s`;
   - R3 transaction total: `20.223s`.
3. Treat RabbitMQ publisher confirm as a secondary fixed-cost target:
   - still important;
   - but not sufficient alone to explain the full business completion tail.

### 2026-07-27 - TPS-124 Wallet batch collection window

Status: implemented in loadtest profile; one env A/B probe and one default-profile verification run completed.

Context:

- TPS-123 repeated runs showed Wallet as the durable convergence tail:
  - `wallet.tradeExecuted.queue` was the last non-zero queue in all three runs;
  - Match -> Wallet p95/p99 grew in the slower completed-business runs.
- Wallet batch metrics showed unstable batch shape despite `batch-size=50`:
  - batch count: `797`, `919`, `998`;
  - singleton fallback count: `70`, `83`, `142`;
  - average batch size: about `12.5`, `10.9`, `10.0`.
- This meant Wallet was paying the batch SQL fixed cost hundreds more times than necessary under the 10k burst workload.

Change:

- Loadtest profile only:
  - changed `eap.wallet.listeners.trade-executed.receive-timeout-ms` from `25` to `75`.
- Production default remains unchanged.
- Business behavior and settlement SQL are unchanged.

Verification runs:

| Run | Setting | Actual input TPS | TradeExecuted reach TPS | Completed TPS | Completion seconds | Final backlog |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R2` | baseline `25ms` | `9960.92` | `1159.43` | `1100.55` | `9.09` | `0` |
| `GLT_TPS123_MATCH_OUTBOX_ATTR_LIGHT_10K_R3` | baseline `25ms` | `9926.81` | `1234.77` | `1112.06` | `8.99` | `0` |
| `GLT_TPS124_WALLET_BATCH_TIMEOUT75_LIGHT_10K_R1` | env override `75ms` | `9976.90` | `1472.55` | `1292.98` | `7.73` | `0` |
| `GLT_TPS124_WALLET_BATCH_TIMEOUT75_DEFAULT_LIGHT_10K_R1` | profile default `75ms` | `9881.90` | `1472.57` | `1206.37` | `8.29` | `0` |

Wallet batch metrics:

| Run | Batch count | Batch size sum | Max batch size | Singleton / fallback count | Batch duration sum | CTE duration sum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TPS-123 R1 baseline | `797` | `10000` | `50` | `70` | `5.217753s` | `4.370838s` |
| TPS-123 R2 baseline | `919` | `10000` | `42` | `83` | `6.928202s` | `5.311461s` |
| TPS-123 R3 baseline | `998` | `10000` | `50` | `142` | `8.881874s` | `7.190025s` |
| TPS-124 env `75ms` | `265` | `10000` | `50` | `0` | `3.118675s` | `2.738265s` |
| TPS-124 default `75ms` | `325` | `10000` | `50` | `0` | `3.885851s` | `3.493085s` |

Integrated lag:

| Run | Match -> Wallet p50 | Match -> Wallet p95 | Match -> Wallet p99 |
| --- | ---: | ---: | ---: |
| TPS-123 R2 baseline | `1558.710ms` | `2135.080ms` | `2429.570ms` |
| TPS-123 R3 baseline | `1450.340ms` | `1966.590ms` | `2082.340ms` |
| TPS-124 env `75ms` | `1369.800ms` | `1983.760ms` | `2100.930ms` |
| TPS-124 default `75ms` | `1580.330ms` | `2036.600ms` | `2093.660ms` |

Interpretation:

- The `75ms` loadtest window is accepted as a real Wallet fixed-cost reduction:
  - batch count dropped from the `797-998` range to `265-325`;
  - singleton fallback dropped to `0`;
  - Wallet CTE total dropped from the `5.31-7.19s` slow-run range to `2.74-3.49s`.
- This is not a complete TPS fix:
  - completed TPS improved versus the slow TPS-123 confirmation runs, but still ranged from `1206.37` to `1292.98`;
  - Wallet remains the last non-zero queue;
  - Match `TradeExecuted` reach was strong in both TPS-124 runs, so the remaining tail is still Wallet durable convergence and Match fixed durable publication cost.
- This profile change is workload-sensitive:
  - it benefits burst settlement throughput;
  - it intentionally trades a small waiting window for fewer database batch executions;
  - production settings should be decided against API/user-visible latency requirements, not copied blindly from loadtest.

Next action:

1. Keep the loadtest profile at `75ms`.
2. Continue with Wallet settlement SQL shape:
   - the current batch CTE still updates `wallets` twice per trade through `input JOIN settlement`;
   - inspect whether there is a cheaper grouped update model for this load shape without losing wallet invariants.
3. Continue Match `trade_record` transaction variability analysis:
   - TPS-124 showed strong `tradeExecutionReachTps`, but Match durable transaction remains one of the largest cumulative costs.

### 2026-07-27 - TPS-125 Metric naming cleanup before further tuning

Status: implemented; compile and targeted tests passed.

Context:

- The next tuning work depends heavily on comparing load-test JSON, actuator metrics, and write-cost summaries.
- Several older MatchEngine metrics still used unscoped names such as `trade_outbox_*`, `trade_completion_marker_*`, and `trade_completion_*`.
- Load-test JSON also still emitted legacy throughput aliases such as `businessMatchedE2eTps`, `matchedE2eTps`, and `completionMarkerReachTps`.
- These names were not a runtime bottleneck, but they created a real diagnosis risk because a reader could not immediately tell whether a number represented a whole-business gate or one service stage.

Naming rule:

- Whole-chain / load-test business numbers use `business*`.
- Service-specific stage numbers use a service prefix:
  - `order*`;
  - `wallet*`;
  - `matchEngine*` in JSON output;
  - `match_engine_*` in Prometheus/Micrometer metrics, because Prometheus metric names use underscores.
- Runtime Micrometer metrics should not publish duplicate legacy aliases.
- Summary tooling may keep read-side fallback for older reports, but new report labels should use the canonical names.

Changes:

- Renamed MatchEngine runtime metrics:
  - `trade_outbox_*` -> `match_engine_trade_outbox_*`;
  - `trade_completion_marker_*` -> `match_engine_trade_completion_marker_*`;
  - `trade_completion_*` -> `match_engine_trade_completion_*`;
  - `match_reservation_reconciler_*` -> `match_engine_reservation_reconciler_*`;
  - `match_reservations_active` -> `match_engine_reservations_active`.
- Renamed the Match trade record phase tag:
  - `insert_trade_outbox` -> `insert_trade_execution_and_outbox`.
- Renamed load-test JSON throughput output:
  - `actualBuyPublishTps` -> `businessInputOrderTps`;
  - `orderbookAdmissionTps` -> `businessOrderbookAdmissionTps`;
  - `blendedMarketFlow*` -> `businessMarketFlow*`;
  - `tradeExecutionReachTps` -> `matchEngineTradeExecutionReachTps`;
  - `orderCommandMatchReachTps` -> `orderTradeApplicationReachTps`;
  - `walletSettlementReachTps` -> `walletTradeSettlementReachTps`.
- Removed new output of legacy JSON aliases:
  - `businessMatchedE2eTps`;
  - `matchedE2eTps`;
  - `completionMarkerReachTps`;
  - `strictCompletionMarkerReachTps`.
- Updated write-cost summary parsing to prefer canonical names while still reading older reports when needed.

Verification:

| Check | Result |
| --- | --- |
| `eap-matchEngine` targeted tests: `TradeCompletionServiceTest`, `TradeOutboxRelayTest` | PASS |
| `eap-order` `testClasses` | PASS |
| `summarize-write-costs.sh` syntax | PASS |
| `collect-loadtest-diagnostics.sh` syntax | PASS |
| Runtime MatchEngine metric-name scan | No unscoped `trade_*` / short `match_*` Micrometer builders remain. |
| Load-test JSON output scan | No new `businessMatchedE2eTps`, `matchedE2eTps`, `completionMarkerReachTps`, or old stage output remains. |
| 500-trade light smoke `GLT_TPS125_METRIC_NAMING_SMOKE_500` | PASS, final queues/DLQ `0`; result JSON and write-cost summary use canonical throughput names. |
| Smoke actuator scrape | PASS, no runtime `trade_outbox_*`, `trade_completion_*`, or `match_reservation_*` MatchEngine metric prefixes remain. |

Match DB probe note:

- The Match trade DB record cost is not fully solved yet.
- TPS-125 isolated DB ceiling probe showed:
  - current-like `cte_metadata`: `8314.25` trade fact + outbox inserts/s, p95 `2.350ms`;
  - split statements `split_metadata`: `6339.87`/s, p95 `3.028ms`;
  - trade fact only `trade_only`: `9009.41`/s, p95 `1.817ms`.
- This means the current CTE shape is better than splitting into two statements in isolation.
- Removing the outbox row has a measurable isolated benefit, but the full-chain bottleneck cannot be explained by this DB insert shape alone.

Next action:

1. Keep Match trade DB record under investigation, but do not replace the CTE with split SQL.
2. Use the cleaned metric names for the next 10k light run so the report separates:
   - business completion;
   - MatchEngine trade execution reach;
   - Order trade application reach;
   - Wallet trade settlement reach;
   - MatchEngine trade outbox relay stages.

### 2026-07-27 - TPS-125 10k light run with canonical metric names

Status: completed; correctness passed, throughput regressed versus TPS-124.

Run:

- `GLT_TPS125_METRIC_NAMING_LIGHT_10K_R1`
- `TARGET_TPS=10000`
- `DURATION_SECONDS=1`
- `EVENTS=10000`
- `PUBLISHERS=128`
- `DIAGNOSTICS_LEVEL=light`

Result:

| Metric | Value |
| --- | ---: |
| `businessInputOrderTps` | `9978.95` |
| `businessOrderbookAdmissionTps` | `3243.75` |
| `businessCompletedTradeTps` | `838.75` |
| `businessMarketFlowTps` | `1332.86` |
| `businessCompletionSeconds` | `11.92` |
| `matchEngineTradeExecutionReachTps` | `962.13` |
| `orderTradeApplicationReachTps` | `838.75` |
| `walletTradeSettlementReachTps` | `838.75` |
| `businessConvergenceReachTps` | `838.75` |
| `queueFullyDrainedSeconds` | `11.92` |
| `lastNonZeroQueue` | `wallet.tradeExecuted.queue` |
| `reservationCleanupReachedSeconds` | `15.34` |
| `reservationCleanupTailAfterBusinessSeconds` | `3.42` |

Correctness:

- `completedTrades=10000`.
- `tradeExecutions=10000`.
- `orderCommandMatchedRows=20000`.
- `walletTradeSettlements=10000`.
- `lockedCurrency=0`.
- `lockedAmount=0`.
- final measured queues and DLQ drained to `0`.
- Redis orderbook ended with `remainingSellOrders=0`, `remainingBuyOrders=0`, and `activeReservations=0`.

Comparison with TPS-124:

| Metric | TPS-124 env 75ms | TPS-124 default 75ms | TPS-125 canonical names |
| --- | ---: | ---: | ---: |
| completed-business TPS | `1292.98` | `1206.37` | `838.75` |
| TradeExecuted reach TPS | `1472.55` | `1472.57` | `962.13` |
| business completion seconds | `7.73` | `8.29` | `11.92` |
| Match reserve Redis eval sum | `14.923s` | `16.471s` | `30.610s` |
| Match trade record transaction total | `17.172s` | `18.524s` | `21.650s` |
| Match trade insert phase | `7.021s` | `7.481s` | `8.730s` |
| Match outbox confirm wall | `5.970s` | `6.825s` | `8.919s` |
| Wallet settlement batch count | `265` | `325` | `565` |
| Wallet settlement CTE sum | `2.738s` | `3.493s` | `4.809s` |
| Wallet singleton/fallback count | `0` | `0` | `67` |

Interpretation:

- This is a valid correctness run, but it is not a new performance improvement.
- The main regression starts before downstream completion:
  - `matchEngineTradeExecutionReachTps` fell from the TPS-124 `1472/s` class to `962/s`;
  - `businessCompletedTradeTps` then followed the slower Match reach rate.
- The largest new Match-side delta is `reserve_order.redis_eval`:
  - TPS-124 env `75ms`: `14.923s / 20000`;
  - TPS-124 default `75ms`: `16.471s / 20000`;
  - TPS-125: `30.610s / 20000`.
- Match durable trade record also worsened, but less dramatically:
  - transaction total rose to `21.650s`;
  - insert fact + outbox rose to `8.730s`;
  - commit gap rose to `5.807s`.
- Match outbox confirm wall also worsened to `8.919s`, but the first-order regression is visible in Match processing before downstream settlement.
- Wallet still forms the final convergence tail:
  - last non-zero queue was `wallet.tradeExecuted.queue`;
  - Match -> Wallet p95 was `2277.920ms`;
  - Wallet batch shape regressed from `265-325` batches to `565` batches, with `67` singleton/fallback events.
- Reservation cleanup is not in the strict business completion gate, but TPS-125 exposed a cleanup tail:
  - active reservations at business completion: `7171`;
  - cleanup reached zero `3.42s` after business completion.

Next action:

1. Inspect Match Redis reserve-or-add path variability first:
   - same workload class, but Redis eval cost doubled;
   - check Lua script path, Redis command contention, key cleanup timing, and whether reservation cleanup overlaps with active matching.
2. Inspect why Wallet batch shape regressed despite the `75ms` loadtest receive window:
   - batch count rose to `565`;
   - singleton/fallback returned to `67`.
3. Keep Match outbox confirm as a secondary target:
   - confirm wall is expensive, but it did not alone explain the TPS-125 drop.

### 2026-07-27 - TPS-126 Benchmark contract v2 and broker-confirmed input

Status: implemented; pushed.

Context:

- GPT Pro review pointed out that the latest script and report names still implied the old completion-marker contract, while the code had moved to a durable-fact gate.
- The load generator previously counted a publish as input after `RabbitTemplate.convertAndSend()` returned.
- That was only a client-side send attempt, not proof that RabbitMQ accepted the message.
- Public benchmark claims need a stricter input boundary before discussing 2000 TPS.

Changes:

- Added RabbitMQ publisher-confirm accounting to the matched-trade load generator.
- Replaced the load generator hot publish path with RabbitMQ Java client direct publishing:
  - one fixed publisher channel;
  - asynchronous confirm listener;
  - bounded in-flight publishes;
  - mandatory publish returns counted as invalid input.
- Split input metrics:
  - `businessInputAttemptedOrderTps`: client-side BUY send-window attempts/s;
  - `businessInputBrokerAckedOrderTps`: RabbitMQ-confirmed BUY input/s;
  - `businessInputOrderTps`: retained as a compatibility alias for broker-confirmed input.
- Added `publisherMode`, `publisherMaxInFlight`, send-window, and confirm-wait metrics.
- Repeat summary now reports the contract-v2 input metrics and confirm timings.
- Added new neutral script names:
  - `scripts/load-test/run-matched-trade-completion-10k.sh`;
  - `scripts/load-test/run-matched-trade-completion-repeat.sh`.
- Kept the old `run-2000-ticket-marker-*` names only as legacy aliases.
- Updated README, performance report, and public benchmark runbook so current completion semantics are:
  - MatchEngine `trade_executions`;
  - Order `order_trade_applications`;
  - Wallet `trade_settlements`;
  - identical `trade_id` sets across the three services;
  - final measured RabbitMQ queue drain.

Verification:

| Check | Result |
| --- | --- |
| `eap-order` `testClasses` | PASS |
| load-test script syntax | PASS |
| 500 direct-confirm smoke, `GLT_TPS126_DIRECT_CONFIRM_FIELDS_SMOKE_500_R1` | Completed with broker acks `500/500` BUY and SELL, no nack/return/timeout, equal trade-ID sets, final queues/DLQ `0`; rejected for capacity comparison because the short-window broker-confirmed input was only `797.33/s` against a `1000/s` target. |
| 10k direct-confirm light, `GLT_TPS126_DIRECT_CONFIRM_LIGHT_10K_R1` | Completed with broker acks `10000/10000` BUY and SELL, no nack/return/timeout, equal trade-ID sets, final queues/DLQ `0`; `businessCompletedTradeTps=1234.47`; rejected for 2000-input capacity comparison because `businessInputBrokerAckedOrderTps=1377.80`. |

Interpretation:

- The current `1200/s` class result is not a local-only "send and hope" number; it is backed by broker acks, durable facts in all three services, trade-ID equality, wallet balance checks, and final queue drain.
- It is still not a valid `2000/s` broker-confirmed capacity result.
- The older TPS93 repeat remains useful performance-history evidence, but public claims should move to contract v2.
- Next publishable benchmark step:
  1. run a clean five-repeat contract-v2 10k benchmark;
  2. report median/range for attempted input, broker-confirmed input, and completed business TPS;
  3. only then decide whether to continue TPS tuning or move to steady-state / cloud portability.

### 2026-07-28 - Order admission chain: Redis query-index split and clean-reset fix

Status: implemented; local verification complete.

Context:

- The `order-admission-chain` benchmark was split from the matched-trade completion benchmark to measure the front half of the lifecycle:
  - Order HTTP request accepted;
  - Order submission request persisted;
  - Order outbox publishes `OrderSubmitted`;
  - Wallet reserves assets and emits reservation confirmation;
  - Order persists `OrderAssetReservationConfirmed`;
  - MatchEngine admits the order into the Redis orderbook;
  - measured queues drain.
- MatchEngine Redis `user:{userId}:orders` was originally maintained in the same Lua hot path as orderbook admission so user open orders could be queried by user.
- The current Order API still had a legacy read path that tried to query MatchEngine Redis for pending user orders, even though Order already owns the `orders_current` projection.

Changes:

- Added MatchEngine listener-level timer output:
  - `matchEngineOrderConfirmedListener*`;
  - `matchEngineTryMatch*`;
  - `matchEngineReserveRedisEval*`.
- Changed Order user-order query to read `order_service.orders_current` instead of synchronously calling MatchEngine Redis.
- Added a benchmark startup env bridge so `run-order-admission-chain-10k.sh` can start MatchEngine with:
  - `ORDER_ADMISSION_MATCH_USER_OPEN_ORDER_INDEX_ENABLED=false` by default;
  - production/manual MatchEngine startup still defaults the index to enabled unless explicitly disabled.
- Added `--flush-redis-on-reset` to `OrderHttpLoadGenerator`; the order-admission script defaults it to `true`.

Why this matters:

- The query-index split keeps service ownership cleaner:
  - Order owns user-facing order status/read models.
  - MatchEngine Redis owns matching/orderbook state.
- The benchmark no longer forces every orderbook admission to pay for a query index that is not part of admission correctness.
- The Redis reset fix is required for reproducibility. Before this fix, reset only deleted `orderbook:{market}:buy/sell` and left old `order:*`, `order:reservation:*`, and `user:*:orders` keys behind.

Evidence:

| Run | Redis reset | User index | Business admission TPS | Orderbook admission TPS | Redis eval mean |
| --- | --- | --- | ---: | ---: | ---: |
| `GLT_20260728_ORDER_ADMISSION_MATCH_TIMER_JSON_10K_R1` | partial key delete | on | `492.46` | `565.36` | `2.552ms` |
| `GLT_20260728_ORDER_ADMISSION_USER_INDEX_OFF_10K_R1` | partial key delete | off | `431.21` | `669.55` | `1.311ms` |
| `GLT_20260728_ORDER_ADMISSION_USER_INDEX_DEFAULT_OFF_10K_R1` | partial key delete with dirty keyspace | off | `459.26` | `546.16` | `13.315ms` |
| `GLT_20260728_ORDER_ADMISSION_CLEAN_REDIS_USER_INDEX_OFF_10K_R1` | `FLUSHDB` | off | `486.52` | `600.82` | `1.300ms` |
| `GLT_20260728_ORDER_ADMISSION_CLEAN_REDIS_USER_INDEX_ON_10K_R1` | `FLUSHDB` | on | `502.38` | `649.09` | `1.565ms` |

Interpretation:

- Dirty Redis state can invalidate order-admission conclusions:
  - the active Redis had `253,775` keys before the clean-reset fix;
  - Redis eval jumped to `13.315ms` in the dirty-keyspace run.
- Disabling `user:{userId}:orders` reduces local Redis Lua cost under clean Redis:
  - `1.565ms -> 1.300ms`, about `17%` lower eval mean in this pair.
- The improvement is not yet visible as a stable end-to-end admission TPS win:
  - business admission remained in the `486-502/s` band;
  - queue drain and Order/Wallet relay phases dominate the wall-clock result.
- Therefore, user-open-order index removal is a valid cleanup and localized Redis optimization, but it is not the primary admission-chain bottleneck.

Next action:

1. Keep `order-admission-chain` clean Redis reset as mandatory benchmark behavior.
2. Keep user-open-order index disabled for the admission benchmark contract because user-order reads now come from Order projection.
3. Do not claim a TPS improvement from this change alone.
4. Continue admission-chain tuning at the dominant phases:
   - Order submission outbox relay;
   - Wallet reservation durable apply/outbox relay;
   - Order reservation-confirmed consumer and queue drain.
