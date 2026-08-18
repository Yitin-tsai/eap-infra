# Release-Pinned 624 Sustained Candidate

## Purpose

The 2026-08-14 short-window recheck classified `624 orders/s` as variable across
seeds. This run extends that rate to a `60s` warm-up plus `900s` measurement
window on a clean, committed snapshot. It asks whether one new shuffled mixed
HTTP seed can remain bounded for 15 minutes; it does not by itself promote 624
to the public sustained lower bound.

## Pinned Snapshot

| Repository | Commit |
| --- | --- |
| `eap-infra` | `3a064ec` |
| `eap-common` | `628893a` |
| `eap-order` | `fc74688` |
| `eap-wallet` | `e538362` |
| `eap-matchEngine` | `6924a65` |

The Order and MatchEngine commits after the 2026-08-13 business revisions add
load-test probes or documentation. Wallet `e538362` corrects metric timing; it
does not change settlement semantics.

## Contract

- `http-matched-steady-state-chain`;
- balanced BUY/SELL HTTP traffic, shuffled with seed `20260818`;
- `624 total orders/s`, `500` users per side;
- release jars, canonical load-test profiles, and light diagnostics every `5s`;
- same-host services, three PostgreSQL containers, RabbitMQ, Redis, monitoring,
  and load generator;
- exact three-service trade IDs, asset reconciliation, empty order books and
  reservations, final queue/DLQ drain, bounded backlog, and no HTTP failures.

Command:

```bash
caffeinate -dimsu env \
  TARGET_ORDER_TPS=624 \
  WARMUP_SECONDS=60 \
  DURATION_SECONDS=900 \
  USERS_PER_SIDE=500 \
  WORKLOAD_SEED=20260818 \
  WAIT_TIMEOUT_SECONDS=900 \
  DIAGNOSTICS_LEVEL=light \
  DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS=5 \
  LOADTEST_SERVICE_LAUNCH_MODE=jar \
  RUN_ID=GLT_20260818_CURRENT_624_15M_SEED20260818_R1 \
  bash scripts/load-test/run-http-matched-steady-state.sh
```

## Result

| Signal | Result |
| --- | ---: |
| HTTP accepted | `599040 / 599040` |
| HTTP failures / unscheduled | `0 / 0` |
| steady accepted orders/s | `623.84` |
| steady completed trades/s | `307.19` |
| completion target ratio | `98.46%` |
| HTTP p50 / p95 / p99 upper bound | `10 / 500 / 500ms` |
| backlog start / end / maximum | `55 / 1109 / 4257` |
| backlog slope | `+0.9367 messages/s` |
| Match / Order / Wallet trades | `299520 / 299520 / 299520` |
| full convergence | `997.4536s`, `300.28 trades/s` |
| final queue / DLQ / order-book / reservation debt | `0` |
| RabbitMQ alarm samples | `0 / 107` |
| sustained-capacity gate | `PASS` |

The exact trade-ID fingerprint was identical across all three services, and all
asset locks were released with the expected buyer and seller deltas.

## Pressure Signals

This is a correctness-valid candidate, not a comfortable headroom result:

- Order command-pool pending requests peaked at `85`; Wallet pending requests
  peaked at `21`;
- system CPU averaged `83.61-87.56%` across service views and reached about
  `100%`;
- sampled MatchEngine order-confirmed backlog peaked at `2518`, while the
  generator's one-second aggregate backlog peaked at `4257`;
- Match-to-durable-convergence p95/p99 were `820.000/1423.890ms`, with one
  Match-to-Order maximum of `32420.500ms`;
- PostgreSQL WAL growth was approximately `2.72GB` for Order, `1.03GB` for
  Wallet, and `0.84GB` for MatchEngine.

No RabbitMQ resource alarm, HTTP count mismatch, queue read failure, deadlock,
or cross-service correctness failure was observed. The light diagnostic sampler
completed `107` samples; its monitoring cadence and the same-host load generator
remain part of the test boundary.

## Decision

Accept this run as one valid 15-minute `624 orders/s` candidate. Do not replace
the two-seed release-pinned `600 orders/s` public lower bound yet: earlier
short-window 624 results varied by seed, and this run still shows meaningful
pool, CPU, tail-latency, and backlog pressure.

The next capacity experiment is a second 15-minute 624 run with a different
seed and unchanged controls. Test 648 as a sustained candidate only if 624
repeats with bounded backlog and comparable tail latency.

Artifacts:

- [result JSON](results/2026-08-18-http-matched-624-15m-seed-20260818-r1.json)
- [one-second samples](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-samples.csv)
- [runtime summary](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-runtime-summary.md)
- [integrated stage lag](results/2026-08-18-http-matched-624-15m-seed-20260818-r1-stage-lag.md)
