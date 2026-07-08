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
