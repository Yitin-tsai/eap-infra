# EAP Public Benchmark Plan - 2026-07

Status: 10k repeat completed on 2026-07-13. First steady-state validation attempt was rejected on 2026-07-13 because the active Redis used an evicting development configuration; the clean Redis rerun completed successfully.

## Goal

Turn the current 10k local benchmark from a useful engineering result into a public case-study result that can survive first-round interview scrutiny.

The goal is not to claim 2000 completed TPS. The goal is to publish repeatable evidence for completed business throughput on a pinned code/config/environment snapshot.

## Benchmark Definitions

| Metric | Definition |
| --- | --- |
| Offered load | order confirmations published toward the match path |
| Completed trade | `TradeExecuted` persisted, Order applied, Wallet settled, completion markers converged, measured queues drained |
| Business E2E TPS | `completedTrades / (max(completionMarkerReachedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)` |
| Valid run | completed counts match target, final queue backlog is zero, publish failures are zero, and offered TPS reaches the configured threshold |

`DURATION_SECONDS=5` is the offered-load publishing window. It is not the completed-business timing window.

## Pinned Environment

| Component | Value |
| --- | --- |
| Machine | MacBook Pro, Apple M5, 10 cores, 16 GB RAM |
| OS | macOS 26.5.1 |
| Docker | Docker 29.5.3 |
| JDK | Temurin OpenJDK 21.0.10 |
| PostgreSQL image | `postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647` |
| RabbitMQ image | `rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281` |
| Redis image | `redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99` |
| Load generator | same local machine as services and containers |

The 2026-07-13 repeat benchmark used this pinned snapshot:

```text
benchmarkInfra=2252e54738d10683894b965c93d93bff32fd8c08
eap-order=5f7f6e18bb40c1e17e565de6377ea1eef77ed165
eap-wallet=f5ac2916a6443c7f7c577db379712b4df34df545
eap-matchEngine=012a5c488aeb0da503eb6897abb6afcbafc5cc69
eap-common=8cce7cd93d1e6cfde3fcf715894a01678b96ff76
```

Generate a machine-readable snapshot before running official repeats:

```bash
scripts/load-test/collect-benchmark-snapshot.sh \
  > build/load-test-reports/EAP_PUBLIC_10K_YYYYMMDD-snapshot.json
```

The snapshot records:

- infra/order/wallet/matchEngine/common Git commits;
- whether any repo is dirty;
- pinned PostgreSQL/RabbitMQ/Redis image refs;
- locally inspected image repo digests.

Do not publish a reproducibility claim while `clean=false`.

The 2026-07-13 snapshot reported `clean=true` for tracked files and `hasUntrackedFiles=true` for unrelated local files. Public claims should therefore cite the tracked commit snapshot and avoid implying the whole workspace contained no untracked local material.

## Official 10k Repeat Command

```bash
REPEATS=5 \
TARGET_TPS=2000 \
DURATION_SECONDS=5 \
EVENTS=10000 \
PUBLISHERS=128 \
TIMEOUT_SECONDS=300 \
DIAGNOSTICS_LEVEL=baseline \
MIN_OFFERED_TPS_RATIO=0.95 \
bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_YYYYMMDD
```

Output:

```text
build/load-test-reports/matched-e2e-repeat-EAP_PUBLIC_10K_YYYYMMDD-summary.json
build/load-test-reports/EAP_PUBLIC_10K_YYYYMMDD-snapshot.json
```

The summary JSON reports:

- valid and invalid run counts;
- invalid reasons;
- per-run artifact paths;
- all-run statistics;
- valid-runs-only statistics;
- avg / median / min / max / spread.

## 2026-07-13 Official 10k Repeat Result

Command prefix:

```bash
REPEATS=5 TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
PUBLISHERS=128 TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=baseline \
MIN_OFFERED_TPS_RATIO=0.95 \
bash scripts/load-test/run-public-benchmark-10k-repeat.sh EAP_PUBLIC_10K_20260713
```

Artifacts:

```text
build/load-test-reports/EAP_PUBLIC_10K_20260713-snapshot.json
build/load-test-reports/matched-e2e-repeat-EAP_PUBLIC_10K_20260713-summary.json
```

Validity:

| Result | Count |
| --- | ---: |
| Valid public runs | `4` |
| Invalid runs | `1` |
| Invalid reason | `EAP_PUBLIC_10K_20260713_R3`: `driver_offered_tps_below_threshold` |

Valid-runs-only summary:

| Metric | Median | Min | Max |
| --- | ---: | ---: | ---: |
| actual buy publish TPS | `1998.94` | `1998.54` | `1999.13` |
| business matched E2E TPS | `582.73` | `503.11` | `662.17` |
| business completion seconds | `17.29` | `15.10` | `19.88` |
| trade execution reach TPS | `1082.09` | `1036.83` | `1176.72` |
| Order command match reach TPS | `843.92` | `825.46` | `974.14` |
| Wallet settlement reach TPS | `843.92` | `825.46` | `974.14` |
| completion marker reach TPS | `745.60` | `701.99` | `803.90` |

Per-run business TPS:

| Run | Valid | Offered TPS | Business E2E TPS | Completion Seconds | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| `R1` | yes | `1999.03` | `503.11` | `19.88` | final queues/DLQ `0` |
| `R2` | yes | `1998.54` | `532.08` | `18.79` | final queues/DLQ `0` |
| `R3` | no | `733.79` | `438.14` | `22.82` | driver offered TPS below threshold |
| `R4` | yes | `1999.13` | `662.17` | `15.10` | final queues/DLQ `0` |
| `R5` | yes | `1998.85` | `633.38` | `15.79` | final queues/DLQ `0` |

## Validity Rules

A run is valid for public summary only if:

- `actualBuyPublishTps >= TARGET_TPS * MIN_OFFERED_TPS_RATIO`;
- `buyPublishFailures == 0`;
- `sellPublishFailures == 0`;
- `completedTrades == EVENTS`;
- `tradeExecutions == EVENTS`;
- `walletTradeSettlements == EVENTS`;
- `orderCommandMatchedRows == EVENTS * 2`;
- `remainingSellOrders == 0`;
- `remainingBuyOrders == 0`;
- final measured ready/unacked queue backlog is zero.

Invalid runs are kept in the result bundle but excluded from the public median.

## Steady-State Follow-Up

After the 10k repeat benchmark is accepted, run one 10-15 minute steady-state benchmark at a conservative target. Do not use the 2000 offered-load burst as the first steady-state claim.

Suggested first pass:

```bash
TARGET_TPS=500 \
DURATION_SECONDS=900 \
EVENTS=450000 \
PUBLISHERS=128 \
TIMEOUT_SECONDS=1800 \
DIAGNOSTICS_LEVEL=light \
bash scripts/load-test/run-global-matched-e2e-sustained.sh
```

The steady-state result should report:

- completed business TPS;
- queue backlog over time;
- final queue drain time;
- DLQ;
- p50/p95/p99 if available;
- whether backlog trends upward, downward, or stays bounded.

2026-07-13 first pass:

- Run ID: `EAP_STEADY_500TPS_15M_20260713_R1`.
- Target: `500` offered BUY confirmations/s for `900s`, `450000` intended matched trades.
- Offered load: `450000` BUY confirmations published in `900.00s`, failures `0`.
- Result: rejected. Only `25379` trades completed; Order command matched rows reached `50758`; Wallet settlements reached `25379`.
- Final broker state: measured ready/unacked queues drained to zero and DLQ was zero.
- Redis order-book state: `remainingSellOrders=0`, `remainingBuyOrders=424621`.
- Root cause: the active Redis container used `maxmemory=200mb` with `maxmemory-policy=allkeys-lru`; `INFO stats` showed `evicted_keys=1284406`. Eviction removed order detail keys while leaving orderbook ZSET members, creating false no-match behavior.
- Interpretation: not a valid steady-state throughput claim. Repeat only after the environment gate confirms clean `noeviction` Redis with `evicted_keys=0`.

2026-07-13 clean Redis rerun:

- Run ID: `EAP_STEADY_500TPS_15M_20260713_R2`.
- Target: `500` offered BUY confirmations/s for `900s`, `450000` intended matched trades.
- Offered load: `450000` BUY confirmations published in `913.34s`, actual offered TPS `492.70`, failures `0`.
- Result: accepted. `450000` completed trades; `450000` trade executions; `450000` Wallet settlements; `900000` Order command matched rows.
- Business completion window: `934.74s`; fully gated completed throughput `481.42` completed trades/s.
- Final broker and orderbook state: measured ready/unacked queues `0`, DLQ `0`, `remainingSellOrders=0`, `remainingBuyOrders=0`.
- Redis state: `maxmemory-policy=noeviction`, `evicted_keys=0`, peak memory about `270.77MB`.
- Interpretation: valid near-500 offered-load steady-state result on the local environment. Do not describe it as 500 completed TPS or 2000 completed TPS.

## Publication Criteria

Do not update README with a stronger public claim until:

1. Benchmark code/config is committed.
2. Container images are pinned.
3. Five 10k repeat runs complete.
4. Public table uses median plus min/max range.
5. Invalid run rules are documented before interpreting results.
6. At least one steady-state run is completed, or the rejected result and remaining gap are explicitly listed.
