# Match Relay To Downstream Isolated Diagnostic

## Purpose

The direct trade-consumer fanout probe showed that Order and Wallet can consume
paced `TradeExecuted` traffic above the current full-chain rate, but it omitted
the Match trade-outbox relay. This diagnostic fills that boundary:

`durable Match trade/outbox activation -> real Match relay -> RabbitMQ fanout -> Order batch application + Wallet settlement -> durable state -> queue drain`

It starts RabbitMQ, Redis, all three PostgreSQL databases, and the real Order,
Wallet, and MatchEngine applications. HTTP admission, Wallet reservation, Order
confirmation, Redis matching, and Match trade persistence are deliberately
outside the measured window. This is a pre-seeded backlog-drain diagnostic, not
a mixed-flow or full-lifecycle capacity test.

## Workload And Gates

- seed `10000` legal Order pairs and corresponding locked Wallet assets;
- seed `10000` durable Match trade facts and outbox rows with a future retry
  time, so the relay cannot publish before measurement starts;
- start the real Match relay, then activate all seeded outbox rows in one
  control statement;
- use the real Match publisher-confirm path, RabbitMQ exchange fanout, Order
  batch listener, and Wallet transaction listener;
- require `10000` identical trade IDs in Match, Order, and Wallet;
- require exact asset settlement, zero locks, zero retry/outbox debt, empty
  consumer queues, and an empty DLQ.

The activation statement is test control and is included in elapsed time. The
durable convergence timestamp excludes the additional three-sample queue-drain
verification delay. Queue peaks are sampled every `500ms` and may undercount
short bursts; final queue state and durable records are correctness gates.

## Valid Results

| Signal | R1 | R2 |
| --- | ---: | ---: |
| Match outbox rows activated / sent / failed | `10000 / 10000 / 0` | `10000 / 10000 / 0` |
| Match relay confirmed-SENT rate | `2356.43 trades/s` | `2681.94 trades/s` |
| Order durable application rate | `2356.43 trades/s` | `2521.07 trades/s` |
| Wallet durable settlement rate | `2125.20 trades/s` | `2521.07 trades/s` |
| three-service durable convergence | `4.705s` / `2125.20 trades/s` | `3.967s` / `2521.07 trades/s` |
| full gate including queue verification | `5.782s` / `1729.53 trades/s` | `5.271s` / `1897.15 trades/s` |
| sampled Order / Wallet queue maximum | `500 / 2284` | `500 / 361` |
| final Order queue / Wallet queue / DLQ | `0 / 0 / 0` | `0 / 0 / 0` |
| exact Match / Order / Wallet trade IDs | `10000 / 10000 / 10000` | `10000 / 10000 / 10000` |
| assets and durable debt | exact / zero | exact / zero |
| correctness | `PASS` | `PASS` |

Artifacts:

- [R1 result](results/2026-08-14-match-relay-downstream-10k-r1.json)
- [R2 result](results/2026-08-14-match-relay-downstream-10k-r2.json)

Both artifacts declare `evidenceClass=isolated-component-boundary` and
`capacityClaimAllowed=false`.

## Interpretation

The slower repeat still relayed all Match outbox rows at `2356.43 trades/s` and
reached durable three-service convergence at `2125.20 trades/s`. The Match relay
therefore does not impose a standalone ceiling near the current shuffled mixed
HTTP lower-bound class. Together with the Rabbit-to-Match and direct downstream
probes, this closes the last previously omitted service boundary as an isolated
hypothesis.

R1's higher sampled Wallet queue peak shows that burst distribution and local
scheduling vary even when final durable throughput remains high. This is why a
single queue peak or a single fast repeat cannot establish capacity.

The result does not prove that the same rates hold when HTTP admission, Wallet
reservation, Order confirmation, Redis matching, Match persistence, relay, and
downstream settlement compete on one host. Current evidence points to combined
pipeline and shared-host scheduling/CPU pressure rather than one service with a
sub-700 standalone ceiling. The next full-chain work should use a short canonical
mixed run with stage timing and host diagnostics, not another concurrency-only
change.
