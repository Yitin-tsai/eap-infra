# Release-Pinned 624 Sustained Evidence

## Purpose

The 2026-08-14 short-window recheck classified `624 orders/s` as variable across
seeds. Two later runs extend that rate to a `60s` warm-up plus `900s`
measurement window on the same clean, committed snapshot. They ask whether new
shuffled mixed HTTP seeds can remain bounded for 15 minutes without changing
service concurrency, pool sizes, business logic, or diagnostics.

## Pinned Snapshot

| Repository | Commit |
| --- | --- |
| `eap-infra` | `3a064ec` (seed `20260818`), `3341c82` (seed `20260819`) |
| `eap-common` | `628893a` |
| `eap-order` | `fc74688` |
| `eap-wallet` | `e538362` |
| `eap-matchEngine` | `6924a65` |

Infra `3341c82` only publishes the first run's evidence on top of `3a064ec`; it
does not change the harness contract. The Order and MatchEngine commits after
the 2026-08-13 business revisions add load-test probes or documentation. Wallet
`e538362` corrects metric timing; it does not change settlement semantics.

## Contract

- `http-matched-steady-state-chain`;
- balanced BUY/SELL HTTP traffic, shuffled with seeds `20260818` and `20260819`;
- `624 total orders/s`, `500` users per side;
- release jars, canonical load-test profiles, and light diagnostics every `5s`;
- same-host services, three PostgreSQL containers, RabbitMQ, Redis, monitoring,
  and load generator;
- exact three-service trade IDs, asset reconciliation, empty order books and
  reservations, final queue/DLQ drain, bounded backlog, and no HTTP failures.

Example command for the second repeat:

```bash
caffeinate -dimsu env \
  TARGET_ORDER_TPS=624 \
  WARMUP_SECONDS=60 \
  DURATION_SECONDS=900 \
  USERS_PER_SIDE=500 \
  WORKLOAD_SEED=20260819 \
  WAIT_TIMEOUT_SECONDS=900 \
  DIAGNOSTICS_LEVEL=light \
  DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS=5 \
  LOADTEST_SERVICE_LAUNCH_MODE=jar \
  RUN_ID=GLT_20260818_CURRENT_624_15M_SEED20260819_R2 \
  bash scripts/load-test/run-http-matched-steady-state.sh
```

## Results

| Signal | Seed `20260818` | Seed `20260819` |
| --- | ---: | ---: |
| HTTP accepted | `599040 / 599040` | `599040 / 599040` |
| HTTP failures / unscheduled | `0 / 0` | `0 / 0` |
| steady accepted orders/s | `623.84` | `624.00` |
| steady completed trades/s | `307.19` | `312.03` |
| completion target ratio | `98.46%` | `100.01%` |
| HTTP p50 / p95 / p99 upper bound | `10 / 500 / 500ms` | `5 / 100 / 200ms` |
| backlog start / end / maximum | `55 / 1109 / 4257` | `168 / 112 / 1164` |
| backlog slope | `+0.9367 messages/s` | `+0.0111 messages/s` |
| Match / Order / Wallet trades | `299520 / 299520 / 299520` | `299520 / 299520 / 299520` |
| full convergence | `997.4536s`, `300.28 trades/s` | `966.0380s`, `310.05 trades/s` |
| final queue / DLQ / order-book / reservation debt | `0` | `0` |
| RabbitMQ alarm samples | `0 / 107` | `0 / 120` |
| sustained-capacity gate | `PASS` | `PASS` |

In both runs, the exact trade-ID fingerprint was identical across all three
services, all asset locks were released with the expected buyer and seller
deltas, and every measured queue drained.

## Pressure Signals

These are correctness-valid repeats, not comfortable headroom results:

- Order command-pool pending requests peaked at `85` and `80`; Wallet pending
  requests peaked at `21` and `5`;
- system CPU averaged roughly `80-88%` across service views and reached about
  `100%`;
- the generator's one-second aggregate backlog peaked at `4257` and `1164`;
- Match-to-durable-convergence p95/p99 improved from `820.000/1423.890ms` in
  the first run to `292.510/478.365ms` in the second, but this seed-dependent
  difference is not attributed to a code change;
- PostgreSQL WAL growth was approximately `2.72GB` for Order, `1.03GB` for
  Wallet, and `0.84GB` for MatchEngine.

No RabbitMQ resource alarm, HTTP count mismatch, queue read failure, deadlock,
or cross-service correctness failure was observed. The light diagnostic sampler
completed `107` and `120` samples; its monitoring cadence and the same-host load
generator remain part of the test boundary.

## Decision

Accept `624 orders/s` as the current release-pinned, same-host, shuffled mixed
HTTP 15-minute sustained lower-bound class because two new long-window seeds
passed the same contract with bounded backlog and exact final convergence. This
promotion supersedes the earlier `600 orders/s` public lower bound for this
exact test boundary.

It does not erase the earlier short-window `2 pass / 1 fail` result, establish
production capacity, or show comfortable hardware headroom. The next candidate
is `648 orders/s` under the same long-window controls; a separate load-generator
CPU domain or host remains necessary before attributing the shared-host boundary
solely to application code.

Artifacts:

- [result JSON](results/2026-08-18-http-matched-624-15m-seed-20260818-r1.json)
- [one-second samples](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-samples.csv)
- [runtime summary](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-runtime-summary.md)
- [integrated stage lag](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-stage-lag.md)
- [seed 20260819 result JSON](results/2026-08-18-http-matched-624-15m-seed-20260819-r2.json)
- [seed 20260819 one-second samples](results/2026-08-18-http-matched-624-15m-seed-20260819-r2-samples.csv)
- [seed 20260819 runtime summary](results/2026-08-18-http-matched-624-15m-seed-20260819-r2-runtime-summary.md)
- [seed 20260819 integrated stage lag](results/2026-08-18-http-matched-624-15m-seed-20260819-r2-stage-lag.md)
