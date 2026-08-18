# Match Processor Combined Isolated Diagnostic

## Purpose

The rejected `650 orders/s` sustained run accumulated its largest queue at
`matchEngine.orderConfirmed.queue`. Existing probes measured Redis/Lua matching
and Match PostgreSQL writes separately, so neither included the actual combined
processor path. This diagnostic adds the missing boundary:

`OrderConfirmedProcessor -> incoming-order idempotency guard -> Redis reserve or add -> TradeExecuted + outbox + cleanup task transaction`

It starts only Match PostgreSQL and Redis. RabbitMQ, HTTP, Order, Wallet, outbox
relay, and concurrent cleanup are excluded. Cleanup is drained and measured only
after all OrderConfirmed events finish.

This is a short current-worktree isolated diagnostic. It is not a full-chain or
production capacity claim.

## Workload

- `10000` BUY/SELL pairs, or `20000` total OrderConfirmed events;
- equal price and quantity `1`, with shuffled mixed arrival order;
- `12` processor workers and a `35` connection Match database pool;
- real Redis Lua scripts, Redisson guards, incoming completion bitmap, JDBC trade
  and outbox insert, cleanup task insert, and explicit database transaction;
- cleanup limit `1000`, drained after processor timing;
- two workload seeds.

## Results

| Signal | Seed `20260814` | Seed `20260815` |
| --- | ---: | ---: |
| processed orders/s | `6953.08` | `7229.07` |
| persisted trades/s | `3476.54` | `3614.54` |
| order latency p95 / p99 | `3.08 / 5.00ms` | `2.97 / 4.73ms` |
| trade transaction mean / max | `1.32 / 25.33ms` | `1.26 / 54.90ms` |
| cleanup tasks/s | `4804.46` | `4565.30` |
| processing failures | `0` | `0` |

Both runs produced exactly:

- `10000` trade rows and `10000` distinct trade IDs;
- matched quantity `10000`;
- `10000` trade outbox rows and `10000` cleanup tasks;
- `20000` completed incoming-order markers;
- empty BUY and SELL order books;
- `10000` active reservations before the deliberate cleanup drain and `0` after;
- `10000` completed cleanup tasks and no failed or pending cleanup work.

Artifacts:

- [seed 20260814 result](results/2026-08-14-match-processor-combined-seed-20260814-r1.json)
- [seed 20260815 result](results/2026-08-14-match-processor-combined-seed-20260815-r2.json)

Both artifacts declare `evidenceClass=isolated-diagnostic` and
`capacityClaimAllowed=false`.

## Interpretation

The isolated combined path sustained roughly `3.5K persisted trades/s`, more
than ten times the approximately `325 trades/s` target implied by a full-chain
`650 orders/s` workload. This rejects the combined Redis matching plus Match
trade transaction as the sole explanation for the observed full-chain boundary.

It does not prove that MatchEngine is irrelevant under full-system contention.
The probe omits RabbitMQ delivery and acknowledgements, concurrent cleanup and
relay scheduling, downstream services, HTTP generation, and competition for the
same host. The follow-up
[RabbitMQ-to-Match diagnostic](2026-08-14-rabbit-match-intake-isolated.md)
added the real listener and concurrent cleanup and still exceeded the current
full-chain result. The remaining useful boundary is Match trade relay plus
downstream Order and Wallet consumption, rather than more cleanup batch tuning.
