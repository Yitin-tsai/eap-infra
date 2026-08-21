# Match Added-Order Completion Fusion - 2026-08-19

## Problem and Boundary

Every guarded `OrderConfirmed` previously executed the Redis reserve-or-add Lua
script and then issued a second Lua call to set the incoming-order completion
bitmap and delete its processing lease. When no opposite order exists, adding
the order to the visible order book is already the terminal business action for
that MatchEngine input. The second client round trip was therefore redundant.

This experiment does not change PostgreSQL transaction count or trade
persistence. The earlier attempt to combine trade, outbox, and reservation
cleanup writes into one PostgreSQL CTE remains rejected. The current trade and
cleanup transaction boundary is unchanged.

## Change

The guarded BUY and SELL reserve-or-add scripts now perform these operations in
one Redis execution when the incoming order is added to the book:

1. add the order-book, detail, and optional user-index entries;
2. set the completed bitmap bit;
3. delete the processing lease;
4. return `__ADDED_COMPLETED__`.

`OrderConfirmedProcessor` recognizes that result and does not issue another
completion-marker call. A fully matched incoming order still marks completion
only after its durable PostgreSQL trade transaction succeeds. A partially
matched order whose remainder is added to the book completes in the final Redis
Lua call after all preceding trades have committed.

This also narrows the failure window. If the client loses the Lua response, a
redelivery observes the completed bitmap and cannot add or match the order a
second time.

## Correctness Verification

The focused processor, matching-service, and Redis result tests passed. The
complete MatchEngine unit suite also passed. The PostgreSQL/Redis crash-recovery
suite passed with a new case that deliberately throws if Java attempts the old
second marker write; the order remained visible once, its bitmap was complete,
the processing hash was absent, and repeated delivery created no trade or
duplicate order.

Commands:

```bash
./gradlew --no-daemon test
./gradlew --no-daemon crashRecoveryIntegrationTest
```

## Isolated A/B

The `match-processor-combined-isolated` probe used only Match PostgreSQL and
Redis. Each pair produces one order added to the book and one matched order, so
the candidate should remove exactly one Redis client command per pair while
leaving trade, outbox, cleanup-task, reservation, and completed-marker counts
unchanged.

| Seed | Baseline orders/s | Candidate orders/s | Difference | Correctness |
| --- | ---: | ---: | ---: | --- |
| `20260819` | `5681.98` | `6147.18` | `+8.2%` | PASS / PASS |
| `20260820` | `3885.10` | `2531.72` | `-34.8%` | PASS / PASS |

The throughput result is **inconclusive**. During the second pair, unrelated
host processes and endpoint-security agents consumed substantial CPU. The
cleanup phase, which is outside the modified path, also fell from `3466.98` to
`1703.16 tasks/s`. Averaging these runs would hide host contamination rather
than establish a code effect.

A smaller same-seed command-count probe produced deterministic structural
evidence:

| Signal for 1,000 pairs | Baseline | Candidate |
| --- | ---: | ---: |
| Redis `EVALSHA` calls | `5000` | `4000` |
| `SETBIT` calls | `2000` | `2000` |
| `HDEL` calls | `2000` | `2000` |
| Completed incoming markers | `2000` | `2000` |
| Trade/outbox/cleanup rows | `1000/1000/1000` | `1000/1000/1000` |
| Correctness | PASS | PASS |

The `1000` removed `EVALSHA` calls equal the number of orders added to the book.
The unchanged `SETBIT` and `HDEL` counts show that correctness work was fused,
not skipped. Total `EVALSHA` calls fell by `20%` for this isolated workload.

## Decision

Adopt the code change because it preserves the full correctness contract,
removes a proven redundant Redis client round trip, and improves the crash
window without changing database transaction semantics. Do not claim a TPS
improvement from this experiment. A later full-chain A/B may determine whether
the reduction is visible under the co-located HTTP workload.

## Short Full-Chain Recheck

The first current-candidate attempt is rejected as host-contaminated. VS Code's
Java language server reached about `138%` CPU during the traffic window, and an
unrelated Maven Surefire suite started shortly afterward. The external driver
scheduled only `20427/25920` requests, so offered load, completion rate, and
backlog gates failed. All accepted work still converged into `10204` identical
MatchEngine, Order, and Wallet trades with correct assets and zero final debt.
This is correctness evidence under overload, not a candidate regression or
capacity result.

After the unrelated suite ended, the services were built and launched as
executable jars in the same runner session so service Gradle daemons did not
compete with traffic. The same `648 orders/s`, `10s + 30s`, seed `20260804`
contract then passed:

| Signal | Earlier external R1 | Earlier external R2 | Completion-fusion recheck |
| --- | ---: | ---: | ---: |
| accepted orders/s | `648.00` | `647.97` | `647.68` |
| same-window trades/s | `323.79` | `323.28` | `360.44` |
| backlog at window start / end | `41 / 0` | `49 / 164` | `1895 / 120` |
| maximum backlog | `400` | `185` | `1895` |
| HTTP p95 upper bound | `100ms` | `50ms` | `200ms` |
| full-convergence trades/s | `304.34` | `305.57` | `304.28` |
| full correctness and drain | PASS | PASS | PASS |

The candidate accepted all `25920` HTTP orders and converged exactly to `12960`
three-service trades with correct assets, empty order books and reservations,
and zero queue or DLQ debt. Its `360.44 same-window trades/s` is not a throughput
gain: the measurement window began with `1895` messages of warm-up debt and
therefore counted catch-up work. Full-convergence throughput remained unchanged
at `304.28 trades/s`, while latency and transient backlog were higher.

This recheck clears a material full-chain regression but does not prove a
full-chain performance improvement. It also used jar launch mode to control host
interference, unlike the earlier boot-run comparison, so it is not a strict
single-variable code A/B. The adoption decision remains based on deterministic
round-trip removal plus correctness and crash-recovery evidence.

The [summary artifact](results/2026-08-19-match-added-completion-fusion-ab.json)
sets `capacityClaimAllowed=false` and records the throughput decision as
`INCONCLUSIVE`.
