# Canonical Mixed HTTP Diagnostic - 2026-08-07

This report records a current-worktree diagnostic after the mixed HTTP load generator was changed to rotate users in actual per-side send order. It is not a release-pinned capacity claim: the participating repositories contained uncommitted changes when the runs were executed.

## Contract

- Contract: `http-matched-staircase-chain`
- Arrival pattern: seeded, shuffled, balanced BUY/SELL HTTP traffic
- Runtime: canonical service-owned `application-loadtest.yml` settings
- Rate limiting: enabled
- Host: load generator, services, PostgreSQL, RabbitMQ, and Redis on one machine
- Correctness gate: exact MatchEngine/Order/Wallet `trade_id` equality, asset reconciliation, empty order books and reservations, and final RabbitMQ/DLQ drain

The user schedule is rate-compliant by construction: BUY and SELL users rotate according to each side's actual shuffled send order. This prevents a seed from accidentally clustering several requests for one user into the same one-second API limit window.

## 700 Orders/s Lower-Bound Regression

Run: `GLT_20260807_CANONICAL_RATE_COMPLIANT_MIXED_700_R2`

| Metric | Result |
| --- | ---: |
| Offered / accepted HTTP rate | `700.00 / 699.98 orders/s` |
| Measurement-window completion | `346.12 trades/s` |
| Full-lifecycle completion | `320.47 trades/s` |
| HTTP accepted | `17500 / 17500` |
| HTTP 429 / 503 / other failures | `0 / 0 / 0` |
| MatchEngine / Order / Wallet trades | `8750 / 8750 / 8750` |
| Three-service trade IDs equal | `true` |
| Maximum measured backlog | `334` |
| Final queue and DLQ backlog | `0` |

All asset, order-book, reservation, and durable-debt gates passed. This is one short-window, one-seed, same-host result. It preserves the existing public statement that the current shuffled mixed HTTP lower bound is in the `700 accepted orders/s`, `350 same-window trades/s`, and `320 full-lifecycle trades/s` class; it does not establish a long-duration capacity.

## Deep Staircase Diagnostic

Run: `GLT_20260807_CANONICAL_RATE_COMPLIANT_MIXED_DEEP_700_1300_R1`

The runner was configured for `700..1300 orders/s` in `100 orders/s` steps, with `10s` warm-up, `15s` measurement, and deep diagnostics. It stopped at the first failed stage.

| Stage | Offered / accepted | Completed in stage window | Max backlog | Result |
| ---: | ---: | ---: | ---: | --- |
| `700 orders/s` | `699.99 / 699.99` | `389.19 trades/s` | `411` | pass |
| `800 orders/s` | `799.99 / 799.94` | `167.93 trades/s` | `4090` | fail: completion rate below minimum |

The `389.19 trades/s` stage value includes carry-over timing from the preceding warm-up and is not a replacement for the isolated 700-stage result above. Deep diagnostics also add observer cost, so these stage values must not be compared directly with low-observation capacity runs.

Despite the 800-stage failure, all accepted work eventually converged:

- `37500 / 37500` HTTP orders accepted, with no 429, 503, or other failures.
- `18750 / 18750 / 18750` MatchEngine, Order, and Wallet durable trades.
- Exact assets, no remaining BUY/SELL orders, no active MatchEngine reservations.
- Final measured queues and DLQ at zero.
- Run-wide convergence: `18750` trades in `55.2844s`, or `339.16 trades/s` across the combined warm-up and stage sequence. This run-wide value spans different rates and is not a steady-state capacity number.

## Bottleneck Evidence

The failed stage showed a common upstream delivery pause rather than independent Order or Wallet correctness failures:

| Evidence | Result |
| --- | ---: |
| MatchEngine scheduler pool size | `1` thread |
| Scheduler tasks queued at final scrape | `5` |
| Reservation-cleanup batch maximum | `9.380s` |
| Match persisted to Order p95 | `7.382s` |
| Match persisted to Wallet p95 | `7.354s` |
| Match persisted to durable convergence p99 | `11.990s` |
| Order/Wallet durable skew p50 | `36.446ms` |

`ReservationCleanupWorker`, `TradeOutboxRelay`, `ReservationReconciler`, auction jobs, and the disabled-by-default checkpoint relay all use Spring scheduling. The observed MatchEngine scheduler had one worker. A long reservation-cleanup invocation can therefore delay the outbox relay before its dedicated publisher executor receives any work. The nearly identical Order and Wallet lag supports this common-upstream hypothesis.

The same-host system CPU averaged about `85.0%` from the Order and Wallet process views and `73.6%` from MatchEngine, with peaks near `100%`. This means host contention and deep diagnostic overhead remain confounding factors, but they do not explain away the single scheduler serialization visible in the application metrics.

## Controlled Follow-up: Scheduler Isolation

MatchEngine now assigns trade-outbox polling and reservation maintenance to independent single-thread schedulers. A separate default scheduler preserves the existing auction schedule semantics. The same-seed deep `700..800` A/B (`GLT_20260807_CDA_SCHEDULER_ISOLATION_DEEP_700_800_R1`) passed both stages:

| Stage | Completed in stage window | Max backlog | Result |
| ---: | ---: | ---: | --- |
| `700 orders/s` | `344.10 trades/s` | `246` | pass |
| `800 orders/s` | `383.45 trades/s` | `246` | pass |

Compared with the pre-isolation 800 stage, completion rose from `167.93` to `383.45 trades/s` and maximum backlog fell from `4090` to `246`. Match-to-Order p95 fell from `7.382s` to `220.869ms`; Match-to-Wallet p95 fell from `7.354s` to `188.196ms`. All `18750` trades converged identically across MatchEngine, Order, and Wallet with exact assets and empty final queues. This supports adopting scheduler isolation, but one short A/B does not establish 800 orders/s as current capacity.

## Rejected 1000-stage Result and Correctness Fix

A wider same-seed deep repeat (`GLT_20260807_CDA_SCHEDULER_ISOLATION_DEEP_700_1300_R2`) passed 700, 800, and 900 before failing the 1000 stage. Its final gate found `42500` Match trades but only `42499` Order and Wallet trades plus one DLQ message. Investigation found one BUY order used in two Match trades.

The Wallet transaction correctly rejected the later settlement; it was not the source of the duplicate. MatchEngine's reservation reconciler correlated Redis reservations to durable trades using an order ID plus a cross-process timestamp lower bound. Under load, that comparison missed an already durable trade and released the resting order back to the visible book. The 900-stage pass is therefore retained only as a diagnostic and cannot become a capacity claim because the run failed its final correctness gate.

The fix stores the exact `tradeId` in each Redis reservation. Cleanup, compensation, and reconciliation must present that same ID before Lua can complete or release the reservation. A stale cleanup cannot delete a newer reservation for the same order. Fresh reservations younger than the orphan threshold are skipped before any reconciliation DB query.

The post-fix light staircase (`GLT_20260807_CDA_RESERVATION_TRADEID_LIGHT_600_800_R3`) produced:

| Stage | Offered / accepted | Completed in stage window | Max backlog | Result |
| ---: | ---: | ---: | ---: | --- |
| `600 orders/s` | `599.73 / 594.03` | `325.09 trades/s` | `1219` | pass |
| `700 orders/s` | `699.99 / 699.97` | `355.90 trades/s` | `600` | pass |
| `800 orders/s` | `799.99 / 798.84` | `245.96 trades/s` | `9961` | fail: completion and backlog |

All `52500` accepted orders converged to `26250 / 26250 / 26250` exact three-service trades. Assets, order books, reservations, queues, and DLQ all ended at zero. The artifact is valid for capacity search and places the first failed stage at 800 for this run.

Isolated diagnostics on the same code reached `32007.38 ops/s` for the 50K Redis/Lua matching core and `9964.57 trade+outbox rows/s` for a 30K Match PostgreSQL probe. These values only reject the isolated components as the observed 700-stage ceiling; they are not full-chain capacity numbers.

## Decision

- Adopt scheduler isolation and exact reservation-to-trade correlation because their focused tests, crash-recovery tests, A/B evidence, and final correctness gates agree.
- Keep the public mixed-flow lower bound at the existing 700 orders/s class. Do not promote the invalid 900 stage or the non-repeatable 800 pass.
- Treat 800 as the current short-window search boundary, not a correctness failure: the post-fix workload fully converged after input stopped.
- Keep deep and light runs separate. Same-host CPU and monitoring remain material confounders.

## Commands

```bash
START_ORDER_TPS=700 END_ORDER_TPS=700 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
WORKLOAD_SEED=20260807 DIAGNOSTICS_LEVEL=light \
RUN_ID=GLT_20260807_CANONICAL_RATE_COMPLIANT_MIXED_700_R2 \
bash scripts/load-test/run-http-matched-staircase.sh

START_ORDER_TPS=700 END_ORDER_TPS=1300 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
WORKLOAD_SEED=20260807 DIAGNOSTICS_LEVEL=deep \
RUN_ID=GLT_20260807_CANONICAL_RATE_COMPLIANT_MIXED_DEEP_700_1300_R1 \
bash scripts/load-test/run-http-matched-staircase.sh

START_ORDER_TPS=600 END_ORDER_TPS=800 STEP_ORDER_TPS=100 \
STAGE_WARMUP_SECONDS=10 STAGE_DURATION_SECONDS=15 \
WORKLOAD_SEED=20260807 DIAGNOSTICS_LEVEL=light \
RUN_ID=GLT_20260807_CDA_RESERVATION_TRADEID_LIGHT_600_800_R3 \
bash scripts/load-test/run-http-matched-staircase.sh
```
