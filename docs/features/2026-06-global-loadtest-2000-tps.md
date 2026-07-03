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
- Order projection/status updated.
- Completion view/reconciliation marks the trade complete.
- RabbitMQ queues drain to zero or expected steady-state floor.
- Outbox pending/failed return to zero after drain window.

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

### Epic 8: Projection Correctness Boundary

| ID | Task | Owner Role | Acceptance Criteria | Dependencies |
| --- | --- | --- | --- | --- |
| TPS-08-01 | Add Order projection to matched E2E acceptance boundary | QA + Implementation Lead | Load generator waits for and asserts `orders_current` has buyer/seller rows marked `MATCHED`; projection failure must fail the benchmark | TPS-03-01 |
| TPS-08-02 | Fix projection schema mismatch exposed by long loadtest market IDs | Implementation Lead | `orders_current.market_id` accepts current loadtest identifiers; no projection `value too long` error remains | TPS-08-01 |
| TPS-08-03 | Re-run guarded 1500 with projection invariant | QA + Performance | `orderCurrentMatchedRows = events * 2`, final queues/DLQ `0`, and completion view has no incomplete trades | TPS-08-02 |

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

Load-test driver fix applied:

- `MatchedE2eLoadGenerator.purgeQueues` now uses synchronous purge (`noWait=false`) and skips missing queues using `getQueueProperties`.
- `order.dlq` is purged as part of each run setup.
- Rationale: queue cleanup must complete before publishing, otherwise stale messages dominate queue peaks and invalidate TPS numbers.

Current accepted baseline:

- The highest reliable global E2E baseline remains `~354 completed matched trades/s` for 1500 matched trades after fixing the Order `trade-executed` listener concurrency.
- The latest normalized-concurrency run solved the completion-marker queue signal (`maxOrderTradeAppliedQueueReady=0`) but produced lower throughput (`~297 completed trades/s`), so it should be treated as a correctness/concurrency-coverage run rather than a new throughput high-water mark.
- The latest projection-invariant run (`~292 completed trades/s`) is the current strongest correctness run because it verifies `orders_current` as well as trade completion and wallet settlement.
- Do not claim 2000 TPS yet; the next task is to inspect DB write amplification and tune concurrency against measured throughput, not just zero queue depth.

Projection correctness finding:

- A previous guarded run could have been incorrectly accepted because the load generator checked `OrderMatchedV1` events, Wallet settlement, completion view, and queues, but did not check the rebuildable Order read model `orders_current`.
- The Order projector was failing on long loadtest market IDs with `ERROR: value too long for type character varying(50)`.
- This means the event-store fact existed, but the user-facing projection could lag or fail while the benchmark still reported success.
- Fix applied:
  - `orders_current.market_id` changed to `VARCHAR(100)` through Liquibase changeset `order-es-006`.
  - `MatchedE2eLoadGenerator` now waits for and asserts `orderCurrentMatchedRows == events * 2`.
- Benchmark rule: a global matched E2E run is not accepted unless both source-of-truth event facts and user-facing projections satisfy the final invariant.

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
