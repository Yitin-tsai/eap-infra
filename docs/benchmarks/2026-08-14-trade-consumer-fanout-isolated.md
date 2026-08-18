# Trade Consumer Fanout Isolated Diagnostic

## Purpose

The RabbitMQ-to-Match probe measures the path up to durable Match trade facts but
deliberately disables the trade outbox relay. This diagnostic isolates the next
service boundary:

`direct TradeExecuted publish -> RabbitMQ fanout -> Order batch application + Wallet single-event settlement -> durable state -> queue drain`

It starts only RabbitMQ, Order PostgreSQL, Wallet PostgreSQL, and the real Order
and Wallet services. MatchEngine, Redis, HTTP admission, Wallet reservation,
Order confirmation, Match trade persistence, and the Match trade-outbox relay
are absent. The result is therefore component-boundary evidence, not full-chain
capacity.

## Workload And Gates

- legal Order command state and Wallet asset locks are seeded with the existing
  matched-E2E data model;
- `10000` unique `TradeExecuted` messages are published to the real trade
  exchange with persistent delivery and correlated publisher confirms;
- Order uses its real batch listener and durable `order_trade_applications` plus
  `order_matching_state` hot path;
- Wallet uses its real listener, explicit transaction, stable wallet lock order,
  settlement fact, and asset updates;
- expected, Order, and Wallet trade-ID sets must be identical;
- all asset locks must be released and buyer/seller asset deltas must reconcile;
- Order retry inbox, Order outbox, Wallet outbox, final consumer queues, and DLQ
  must be empty.

Order projection and the retired completion-feedback path are not part of the
business gate. Three consecutive `500ms` queue samples verify final drain. This
verification delay is reported separately from durable Order/Wallet arrival and
must not be used to infer listener capacity.

## Valid Results

| Signal | `1000 events/s` | `2000 events/s` |
| --- | ---: | ---: |
| broker-confirmed publish rate | `999.50/s` | `1997.28/s` |
| Order durable applications | `10000` | `10000` |
| Order durable arrival rate | `991.54 trades/s` | `1972.77 trades/s` |
| Wallet durable settlements | `10000` | `10000` |
| Wallet durable arrival rate | `991.54 trades/s` | `1972.77 trades/s` |
| durable fanout arrival window | `10.085s` | `5.069s` |
| queue-drain verification time | `11.225s` | `6.151s` |
| exact expected/Order/Wallet trade IDs | `10000/10000/10000` | `10000/10000/10000` |
| final Order queue / Wallet queue / DLQ | `0/0/0` | `0/0/0` |
| correctness | `PASS` | `PASS` |

The Order and Wallet arrival timestamps share a `200ms` database sampling
resolution. The results show that both consumers kept up with these paced short
windows; they do not prove identical service ceilings.

Artifacts:

- [1000 events/s result](results/2026-08-14-trade-consumer-fanout-10k-1000-r1.json)
- [2000 events/s result](results/2026-08-14-trade-consumer-fanout-10k-2000-r1.json)

Both artifacts declare `evidenceClass=isolated-diagnostic` and
`capacityClaimAllowed=false`.

## Rejected Probe Revisions

The first smoke started consumers before purging RabbitMQ. Retained messages
from an earlier workload were consumed and the run was rejected as an isolation
failure. The runner now purges all EAP queues before either consumer starts.

The next smoke correctly produced `500` Order applications, `1000` matched Order
command rows, `500` Wallet settlements, exact assets, and empty queues. Its
probe gate nevertheless timed out because it incorrectly required
`OrderMatchedV1` event-store rows. The current Order batch hot path intentionally
uses `order_trade_applications` plus `order_matching_state` as its durable
application and command-state evidence. The invalid requirement was removed;
the run was not retained as performance evidence.

The probe originally also kept its Java process alive for about `60s` after the
result because a Rabbit client executor used non-daemon threads. A probe-owned
daemon executor removed that tooling tail. It does not change service runtime
behavior or the measured window.

## Interpretation

At a paced `2000 TradeExecuted/s`, both downstream services durably reached all
`10000` trades in `5.069s`, with exact trade IDs and assets. This is more than
five times the current roughly `350 trades/s` shuffled mixed full-chain class.
It rejects Order trade application plus Wallet settlement fanout as the sole
current full-chain ceiling.

The result does not clear the omitted Match trade-outbox relay or same-host
contention when HTTP admission, Wallet reservation, matching, relay, Order
application, and Wallet settlement execute concurrently. The next narrow
diagnostic should add the real Match trade-outbox relay to this boundary before
another long full-chain run.
