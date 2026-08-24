# Cancellation Ownership and Regression Evidence - 2026-08-24

## Decision Summary

The cancellation design keeps order state in Order and matching arbitration in
MatchEngine. Wallet does not maintain a per-order reservation projection. It trusts
the durable MatchEngine cancellation fact for the exact unmatched quantity, derives
the asset delta, and records only the idempotency fact needed to apply that
cancellation once.

This decision removes state that Wallet did not need to own from normal order and
trade paths. It was adopted because focused PostgreSQL tests and a cross-service
cancellation lifecycle passed, and both short- and 15-minute shuffled mixed-HTTP
regressions did not show a correctness or throughput regression. There is no
controlled before/after benchmark for the removed projection, so this report does
**not** claim a measured TPS improvement from the simplification.

## The Rejected Assumption

An earlier conservative design maintained a Wallet row for every accepted order and
updated it after each trade. The goal was to calculate the amount released by a later
cancellation from Wallet-local order state.

Review challenged the ownership premise. An EAP order cannot be amended after
acceptance. MatchEngine already owns the atomic decision between matching and
cancelling the remaining order-book quantity, and its durable result contains the
exact cancelled remainder. Wallet owns balances, not the order lifecycle. Rebuilding
the order projection in Wallet therefore added a second mutable model without adding
a new authoritative fact.

The useful invariant is additive:

```text
original reserved quantity = matched quantity + cancelled remainder
```

For a BUY order of 10 units at price 100 that trades 4 and cancels 6, settlement
consumes the reservation for 4 and cancellation releases 600 currency units. If the
two events arrive in the opposite order, the two disjoint deltas still converge to
the same balance. The system does not need to assign delivery priority between the
trade and cancellation events.

## Adopted Boundary

- Order durably accepts the cancellation request and owns the order event stream.
- MatchEngine records the request, arbitrates cancellation against admission and
  matching at the Redis Lua boundary, and publishes the exact result through its
  transactional outbox.
- Wallet applies only `CANCELLED` results. In one explicit database transaction it
  locks the wallet, inserts `order_cancellation_applications`, verifies replay
  identity, checks that locked assets cannot become negative, and applies the release.
- `cancellation_id` is the command identity and `order_id` is unique, so an identical
  redelivery is a no-op while a conflicting payload fails visibly.
- Normal order reservation and trade settlement do not write a Wallet cancellation
  or per-order state table.

`order_cancellation_applications` is an idempotency ledger for actual cancellations,
not an order projection. Its write cost exists only when a cancellation succeeds.

## Correctness Evidence

Wallet unit tests and PostgreSQL integration tests cover missing wallets,
insufficient locked assets, duplicate and conflicting identities, cancellation before
or after settlement, concurrent delivery, and multiple partial settlements. The
final clean test execution completed Common `5` discovered / `0` skipped, Order
`133` / `33` environment-gated skipped, Wallet `65` / `12` skipped, and MatchEngine
`126` / `12` skipped, with zero failures. The real PostgreSQL, Redis, RabbitMQ, and
three-service paths were then exercised by the lifecycle and sustained regression
below.

The cross-service HTTP lifecycle run
`CANCELLATION_LIFECYCLE_20260824_FINAL_R9` covered:

- cancellation of an open order;
- cancellation of the remainder after a partial fill;
- 10 concurrent match/cancel races.

All 10 race iterations produced one valid winner. Order applied 22 cancellation
results and Wallet recorded 22 matching applications. The three services retained
the same trade IDs, assets reconciled, and all outboxes, queues, unacknowledged
messages, DLQ entries, and Match reservations drained to zero. This is cancellation
correctness evidence, not a cancellation-throughput benchmark.

All 10 cross-service race iterations happened to end with cancellation winning. The
run proves mutual exclusion for those observed schedules, but it does not claim a
balanced sample of both winners. Focused tests separately cover already-matched and
non-open rejection paths.

## Sustained Normal Mixed-HTTP Regression

The post-change worktree first passed a `20s + 60s` smoke regression and then ran the
canonical shuffled BUY/SELL HTTP flow with the same seed `20260899`, 60 seconds of
warm-up, 900 seconds of measurement, and a target of `648 total orders/s`. The final
run was `CANCELLATION_EVENT_ONLY_648_15M_20260824_R2`:

| Signal | Result |
| --- | ---: |
| HTTP accepted | `622080 / 622080` |
| HTTP 429 / 503 / other failures / unscheduled | `0 / 0 / 0 / 0` |
| Accepted rate | `648.00 orders/s` steady; `647.99 orders/s` full window |
| Steady completed rate | `323.87 trades/s` |
| Full-lifecycle rate | `322.44 trades/s` |
| Match / Order / Wallet trades | `311040 / 311040 / 311040` |
| HTTP p50 / p95 / p99 upper bound | `1 / 20 / 50 ms` |
| Maximum steady backlog | `338` |
| Backlog start / end / slope | `42 / 73 / +0.0067/s` |
| Final queue / DLQ / Match reservation debt | `0` |
| Final Hikari pending connections | `0` |
| RabbitMQ memory / disk alarm samples | `0 / 0` across `133` samples |
| Redis evicted keys | `0` |

The run passed the sustained business contract and exact final gates. The source and
runner fingerprints stayed stable throughout the run. The workload's completion
target ratio was `0.9996`, all locked assets and order-book entries returned to zero,
and the identical three-service trade-ID set had fingerprint
`35bab0ef2614fc4bbfc135b031cd2d30d0a6e4f801928e933421e591ca6c449e`.

Light diagnostics found no RabbitMQ resource alarms and only bounded unacknowledged
queue peaks (`118` Order confirmations, `87` Wallet submissions, `78` MatchEngine
confirmations, `57` Order trade events, and `45` Wallet trade events). Wallet's
Hikari pool briefly reached `9` pending requests while the Order and MatchEngine
pools remained at `0`; every pool was back to `0` pending at the final snapshot.
This is a useful transient saturation signal, but it did not produce growing backlog,
failed requests, or convergence debt at this workload.

The observed latency, completion rate, and backlog are better than the two historical
release-pinned 648 seeds, but this single dirty-worktree seed is not a controlled A/B.
The difference must not be attributed to the cancellation redesign without a clean,
repeatable, commit-pinned campaign.

All transaction-path repositories still contained uncommitted work and the benchmark
was intentionally run in diagnostic evidence mode. It is therefore a full-duration
current-worktree regression result, not release-pinned capacity evidence. It does not
replace the two-seed, 15-minute, release-pinned `648 accepted orders/s` boundary and
does not establish cancellation-heavy capacity.

## Engineering Workflow Lesson

This change is useful as an AI-assisted review case because the human owner did not
accept the first conservative model merely because it appeared safer. The review was
reopened around service ownership and the actual invariant. Implementation then
removed the unneeded projection, QA expanded out-of-order and race coverage, and the
benchmark gate checked that the simpler model did not damage the normal trading path.

The reusable lesson is not “remove tables for speed.” It is:

1. identify which service owns the authoritative decision;
2. separate domain state from idempotency evidence;
3. make concurrent event effects commute where the business invariant allows it;
4. require focused failure tests and a full-chain regression before adopting the
   simpler design;
5. refuse a performance-improvement claim when no comparable A/B exists.

Artifact: [curated result, diagnostics, and provenance summary](results/2026-08-24-cancellation-ownership/summary.json).
