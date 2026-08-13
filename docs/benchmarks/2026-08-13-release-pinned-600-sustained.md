# Release-Pinned 600 Sustained Full-Lifecycle Run

## Purpose

The 2026-08-11 release-pinned `700 orders/s` repeat passed final correctness but failed the 15-minute sustained completion and backlog gates. This follow-up searched downward for a current, repeatable starting point using the same shuffled mixed-HTTP business contract.

Repository versions for the accepted run:

| Repository | Commit |
| --- | --- |
| `eap-infra` | `976114c` |
| `eap-common` | `628893a` |
| `eap-order` | `c95381c` |
| `eap-wallet` | `3811169` |
| `eap-matchEngine` | `ed55214` |

## Contract

- public HTTP path for shuffled BUY and SELL orders;
- `60s` warmup and `900s` measurement window;
- target `600 total orders/s`;
- workload seed `20260811`, `500` users per side;
- same-host services, PostgreSQL, RabbitMQ, Redis, monitoring, and load generator;
- light diagnostics;
- completion target ratio at least `95%`;
- backlog slope at most `+7 messages/s` and maximum backlog at most `21000`;
- exact MatchEngine, Order, and Wallet trade IDs and asset reconciliation;
- final queues, DLQ, order books, and reservations drained to zero.

## Rejected R1: Host Interruption

R1 experienced a local scheduling pause. Order's Hikari pools reported `Thread starvation or clock leap detected` with a `7m29s` delta. During the same interval, `128` HTTP requests and `7` RabbitMQ management reads timed out.

Durable reconciliation showed that `127` timed-out requests had committed and only `1` SELL order was absent. The actual durable workload still converged correctly to `287999` identical three-service trades; one remaining SELL order and one locked seller unit matched the accepted BUY/SELL imbalance, and final queues, DLQ, and active reservations were zero.

R1 is rejected as capacity evidence because the load generator and monitoring were interrupted by the host. It is retained because it also exposed a benchmark bug: a failed queue read used `Long.MAX_VALUE` as backlog, corrupting maximum-backlog and slope output. `eap-order` commit `c95381c` now reports unavailable backlog as `-1`, calculates backlog statistics only from successful samples, and still invalidates any run containing metrics-read failures.

[Rejected R1 result JSON](results/2026-08-13-http-matched-releasepin-600-seed-20260811-r1-host-interrupted.json)

## Accepted R2

R2 used the same workload and service configuration, with macOS sleep prevention enabled for the benchmark process.

| Signal | Result |
| --- | ---: |
| scheduled / HTTP accepted orders | `576000 / 576000` |
| HTTP `429 / 503 / other` | `0 / 0 / 0` |
| steady accepted orders/s | `597.12` |
| steady completed trades/s | `292.74` |
| completion target ratio | `97.58%` |
| completion-to-accepted ratio | `98.05%` |
| backlog start / end | `0 / 7239` |
| backlog slope | `+3.6169/s` |
| maximum backlog | `8918` |
| full convergence | `999.3486s` |
| full-convergence trades/s | `288.19` |
| Match / Order / Wallet trades | `288000 / 288000 / 288000` |
| queue-metrics failures | `0` |
| final queue / DLQ / reservation debt | `0` |
| sustained-capacity gate | pass |

The three services produced the same trade-ID fingerprint. Final buyer and seller balances exactly matched `288000` trades, with no locked assets or remaining orders.

[Accepted R2 result JSON](results/2026-08-13-http-matched-releasepin-600-seed-20260811-r2.json)

## Inconclusive Second-Seed Repeat

A repeat with seed `20260813` did not produce capacity or final-correctness evidence. RabbitMQ set its `system_memory_high_watermark` alarm at `07:04:40Z`; the alarm remained active during the run and publisher channels later closed with pending confirms. The load generator could no longer maintain its scheduled offered rate.

At `07:31:16Z`, one Order PostgreSQL server process exited with code `2`. PostgreSQL terminated its remaining server processes and entered crash recovery, invalidating the benchmark's long-lived monitoring connection with an EOF. The container itself did not restart and was not marked OOM-killed; PostgreSQL completed recovery and accepted connections again at `07:33:11Z`. The available evidence does not establish the root cause of that backend exit, so this report does not attribute it to application code or memory pressure.

The repeat is inconclusive rather than a 600-capacity failure: offered load was not maintained, RabbitMQ was under a resource alarm, and the harness could not execute its final three-service correctness gate. It does not count as the required second seed.

This failure drove two fail-closed harness changes:

- runtime diagnostics now sample RabbitMQ memory and disk alarms, and an observed alarm invalidates capacity evidence;
- a harness exception before the normal result now produces a rejected `harness-failure` JSON instead of losing the artifact.

[Second-seed infrastructure-failure metadata](results/2026-08-13-http-matched-releasepin-600-seed-20260813-r1-infrastructure-failure.json)

## Diagnostics and Decision

The largest sampled RabbitMQ queue remained `matchEngine.orderConfirmed.queue` at `6934`; `wallet.orderSubmitted.queue` peaked at `2216`. Downstream Order and Wallet trade queues peaked at `272` and `230`. MatchEngine admission remains the first pressure point, but it did not violate this run's backlog gates.

System CPU still averaged roughly `85-90%` and reached `100%` because all components shared one host. The result establishes a same-host engineering lower bound, not a production SLA.

The reservation ownership change also behaved as intended: the reconciler deferred `7125` worker-owned cleanup tasks, completed `0` of them itself, and emitted no redundant cleanup warnings. No publisher-confirm timeout or Hikari starvation warning occurred in R2.

Decision:

- promote `600 accepted orders/s` class as the current release-pinned, 15-minute single-run sustained lower bound for this exact single-host shuffled mixed-HTTP contract;
- retain about `700 accepted orders/s` only as a short-window lower-bound class;
- do not call 600 cross-seed repeatable, or promote sustained `650` or `700`, until a second 600 seed passes without host, database, or broker resource interruption.
