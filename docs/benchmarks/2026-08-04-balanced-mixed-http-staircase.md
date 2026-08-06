# Balanced Mixed HTTP Staircase - 2026-08-04

Status: provisional single-seed capacity boundary. The result is valid for short-stage capacity search, not a sustained production SLA.

## Why This Run Exists

The former HTTP staircase sent strict `SELL, BUY` pairs. That was deterministic but more orderly than a real market. The current canonical workload creates an equal number of BUY and SELL orders, shuffles their arrival order with a recorded seed, and sends both sides through the public HTTP path.

The sequential SELL-then-BUY benchmark remains useful for regression and upper-bound diagnosis. Its `922.38 trades/s` best result is not the mixed-flow system capacity.

## Workload

- arrival pattern: `shuffled`
- workload seed: `20260804`
- range: `700` to `1100` total HTTP orders/s in `100 orders/s` steps
- stage window: `5s` warm-up plus `15s` measurement
- users: `500` per side, assigned round-robin within each side's shuffled arrival stream
- load generator, three services, PostgreSQL, RabbitMQ, and Redis: one machine
- one trade requires one accepted BUY and one accepted SELL

## Results

| Runtime profile | 700 orders/s | 800 orders/s | 900 orders/s | 1000 orders/s | Boundary |
| --- | ---: | ---: | ---: | ---: | --- |
| `core-capacity` | `381.48 trades/s`, pass | `402.92`, pass | `450.58`, pass | `447.87`, fail | `900 pass / 1000 fail` |
| `production-equivalent` | `346.43 trades/s`, pass | `227.95`, fail | not attempted | not attempted | `700 pass / 800 fail` |

The failed `1000 orders/s` core stage completed `89.57%` of its `500 trades/s` target during the measurement window. With normal Order projection frequency and runtime defaults restored, the failed `800 orders/s` production-equivalent stage completed `56.99%` of its `400 trades/s` target and its queue backlog grew at `483.84 messages/s`. Every accepted order still converged after traffic stopped.

## Final Correctness

| Signal | Core Capacity | Production Equivalent |
| --- | ---: | ---: |
| HTTP orders accepted | `68000/68000` | `30000/30000` |
| Expected trades | `34000` | `15000` |
| Match / Order / Wallet durable trade rows | `34000 / 34000 / 34000` | `15000 / 15000 / 15000` |
| Three-service trade-ID equality | `true` | `true` |
| HTTP 429 / 503 / other failures | `0 / 0 / 0` | `0 / 0 / 0` |
| Remaining BUY / SELL orders | `0 / 0` | `0 / 0` |
| Active reservations | `0` | `0` |
| Final queue backlog / DLQ | `0 / 0` | `0 / 0` |
| Asset settlement | exact | exact |

The core run converged at `401.20 trades/s` over its complete run. The production-equivalent run converged at `339.35 trades/s` after stopping at its first failed stage. These run-wide rates cover different stage sets and must not be compared as an A/B throughput percentage.

## Diagnostic Signal

Post-run durable timestamp analysis showed:

| Runtime profile | Match to Order p95 | Match to Wallet p95 |
| --- | ---: | ---: |
| `core-capacity` | `2.989 ms` | `1533.000 ms` |
| `production-equivalent` | `1.443 ms` | `2584.380 ms` |

Wallet settlement remains the longer downstream tail. The production-equivalent sample includes normal Order projection frequency and shows a materially longer Wallet tail, but these single-run values support attribution only.

## Harness Defects Found

Two rejected setup attempts improved the benchmark itself:

- The first shuffled smoke assigned users from shuffled trade indexes and created artificial same-user bursts, causing `31` expected rate-limit rejections. User assignment now remains round-robin independently within each side while side arrival order stays shuffled.
- The first production-equivalent staircase found stale outbox messages becoming unacked between service startup and database reset. Reset now waits for queue quiescence, truncates service data a second time, and requires three consecutive empty queue samples.

Neither rejected attempt is capacity evidence.

## Interpretation

- The optimized core-capacity boundary is provisionally `900 pass / 1000 fail`, equivalent to a `450 completed trades/s` passing target.
- The production-equivalent boundary is provisionally `700 pass / 800 fail`, equivalent to a `350 completed trades/s` passing target.
- Both failed stages accepted all input and eventually converged; they failed because business completion could not keep pace during the measurement window.
- The earlier strict-alternating boundary of `1000 pass / 1100 fail` was workload-sensitive and should be treated as historical regression evidence.
- Runtime profile work matters: restoring normal projection frequency, smaller pools and batches, completion-view writes, and reconcilers moved the provisional knee down by two `100 orders/s` stages.
- Follow-up testing passed three seeds at 900 orders/s for three-minute windows, but a 30-minute 900 orders/s soak failed as the Order event outbox accumulated durable debt. See the [2026-08-05 robustness report](2026-08-05-wallet-settlement-robustness.md). A lower long-duration knee and an external load generator are still required before publishing a sustained capacity claim.

## Artifacts

- [`core-capacity` result](results/2026-08-04-http-matched-shuffled-staircase-core-result.json)
- [`production-equivalent` result](results/2026-08-04-http-matched-shuffled-staircase-production-equivalent-result.json)
