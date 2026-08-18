# Release-Pinned 648 Sustained Boundary

## Purpose

After two `624 orders/s` long-window seeds passed, these runs changed only the
target input rate to `648 orders/s`. Two new shuffled mixed HTTP seeds used the
same release jars, canonical profiles, light diagnostics, correctness gates,
and `60s` warm-up plus `900s` measurement window.

## Pinned Snapshot

| Repository | Commit |
| --- | --- |
| `eap-infra` | `37f4158` |
| `eap-common` | `628893a` |
| `eap-order` | `fc74688` |
| `eap-wallet` | `e538362` |
| `eap-matchEngine` | `6924a65` |

No service code, pool size, listener concurrency, recovery behavior, or
diagnostic level changed between the 624 and 648 campaigns.

## Contract

- `http-matched-steady-state-chain`;
- balanced BUY/SELL HTTP traffic, shuffled with seeds `20260820` and `20260821`;
- `648 total orders/s`, `500` users per side;
- release jars, canonical load-test profiles, and light diagnostics every `5s`;
- services, load generator, three PostgreSQL containers, RabbitMQ, Redis, and
  monitoring on the same host;
- exact three-service trade IDs, asset reconciliation, empty order books and
  reservations, final queue/DLQ drain, bounded backlog, and no HTTP failures.

Example command:

```bash
caffeinate -dimsu env \
  TARGET_ORDER_TPS=648 \
  WARMUP_SECONDS=60 \
  DURATION_SECONDS=900 \
  USERS_PER_SIDE=500 \
  WORKLOAD_SEED=20260821 \
  WAIT_TIMEOUT_SECONDS=900 \
  DIAGNOSTICS_LEVEL=light \
  DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS=5 \
  LOADTEST_SERVICE_LAUNCH_MODE=jar \
  RUN_ID=GLT_20260818_CURRENT_648_15M_SEED20260821_R2 \
  bash scripts/load-test/run-http-matched-steady-state.sh
```

## Results

| Signal | Seed `20260820` | Seed `20260821` |
| --- | ---: | ---: |
| HTTP accepted | `622080 / 622080` | `622080 / 622080` |
| HTTP failures / unscheduled | `0 / 0` | `0 / 0` |
| traffic send time | `963.4901s` | `960.3237s` |
| steady accepted orders/s | `645.27` | `648.00` |
| steady completed trades/s | `315.96` | `314.84` |
| completion target ratio | `97.52%` | `97.17%` |
| HTTP p50 / p95 / p99 upper bound | `10 / 200 / 500ms` | `50 / 500 / 1000ms` |
| backlog start / end / maximum | `63 / 857 / 4001` | `9 / 1136 / 4907` |
| backlog slope | `+0.5116 messages/s` | `+1.1820 messages/s` |
| Match / Order / Wallet trades | `311040 / 311040 / 311040` | `311040 / 311040 / 311040` |
| full convergence | `1004.2155s`, `309.73 trades/s` | `1032.8741s`, `301.14 trades/s` |
| final queue / DLQ / order-book / reservation debt | `0` | `0` |
| sustained-capacity gate | `PASS` | `PASS` |

Both runs produced the same trade-ID fingerprint in all three services,
reconciled buyer and seller assets exactly, released every asset lock and Match
reservation, and drained every measured final queue.

## Pressure Signals

The result is repeatable according to the configured gates, but it is a
shared-host pressure boundary:

- Order command-pool pending requests peaked at `90` and `91`; Wallet pending
  requests peaked at `25` in both runs;
- system CPU averaged roughly `85-88%` and reached `100%` in both runs;
- the second run's sampled Match order-confirmed queue reached `3758`, while
  the generator's one-second aggregate backlog reached `4907`;
- Match-to-durable-convergence p95/p99 were `951.327/1847.720ms` and
  `1154.780/2016.220ms`;
- Order WAL grew by approximately `2.79GB` and `2.82GB`; Wallet by `1.06GB`
  in each run; MatchEngine by approximately `0.89GB` in each run;
- the first run needed `3.4901s` beyond the nominal 960-second traffic period
  to finish scheduling all requests, while still satisfying the offered-load
  and unscheduled-order gates.

No RabbitMQ resource alarm, Redis eviction, HTTP failure, deadlock, queue-read
failure, or cross-service correctness failure was observed. The startup log's
optional Bean Validation provider message is informational and unrelated to the
transaction result.

## Decision

Promote `648 accepted orders/s` to the highest current repeatable,
release-pinned, same-host shuffled mixed HTTP 15-minute lower-bound class. This
is an exact workload claim, not a production SLA or proof of comfortable
headroom.

The two 648 runs increased accepted input over 624, but their full-lifecycle
rates (`309.73` and `301.14 trades/s`) remained in the same range as the two 624
runs (`300.28` and `310.05 trades/s`). Tail latency, pool pending work, and CPU
also increased. Therefore, do not move directly to a 672 sustained claim. The
next experiment should attribute the shared-host knee by separating load-driver
CPU pressure or reducing observability overhead without changing business logic.

Artifacts:

- [seed 20260820 result JSON](results/2026-08-18-http-matched-648-15m-seed-20260820-r1.json)
- [seed 20260820 one-second samples](results/2026-08-18-http-matched-648-15m-seed-20260820-r1-samples.csv)
- [seed 20260820 runtime summary](results/2026-08-18-http-matched-648-15m-seed-20260820-r1-runtime-summary.md)
- [seed 20260820 integrated stage lag](results/2026-08-18-http-matched-648-15m-seed-20260820-r1-stage-lag.md)
- [seed 20260821 result JSON](results/2026-08-18-http-matched-648-15m-seed-20260821-r2.json)
- [seed 20260821 one-second samples](results/2026-08-18-http-matched-648-15m-seed-20260821-r2-samples.csv)
- [seed 20260821 runtime summary](results/2026-08-18-http-matched-648-15m-seed-20260821-r2-runtime-summary.md)
- [seed 20260821 integrated stage lag](results/2026-08-18-http-matched-648-15m-seed-20260821-r2-stage-lag.md)
