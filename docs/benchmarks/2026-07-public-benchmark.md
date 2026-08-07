# EAP Public Benchmark Plan - 2026-07

Status: 10k repeat completed on 2026-07-13. First steady-state validation attempt was rejected on 2026-07-13 because the active Redis used an evicting development configuration; the clean Redis rerun completed successfully.

## Goal

Turn the current 10k local benchmark from a useful engineering result into a public case-study result that can survive first-round interview scrutiny.

The goal is not to claim 2000 completed TPS. The goal is to publish repeatable evidence for completed business throughput on a pinned code/config/environment snapshot.

## Benchmark Definitions

EAP benchmark results are separated by workflow contract:

| Contract | Status | Meaning |
| --- | --- | --- |
| `order-admission-chain` | implemented | Order API through Wallet reservation and MatchEngine orderbook admission |
| `matched-trade-completion-chain` | implemented | Seeded confirmed orders through MatchEngine matching, Order trade application, Wallet settlement, trade-ID equality, and queue drain |
| `public-order-lifecycle` | planned | User-facing HTTP order submission through full durable trade completion |
| `rabbitmq-publish-only` | implemented diagnostic | RabbitMQ broker-confirmed input ceiling without service consumers |

The current public benchmark plan is for `matched-trade-completion-chain`. It must not be described as a public API lifecycle benchmark.

| Metric | Definition |
| --- | --- |
| Input attempted load | client-side BUY order confirmations sent toward the match path during the scheduled send window |
| Broker-confirmed input load | BUY order confirmations acknowledged by RabbitMQ publisher confirms |
| Completed trade | `TradeExecuted` persisted, Order applied, Wallet settled, the three durable trade-ID sets are identical, and measured queues drained |
| Business E2E TPS | `completedTrades / (max(durableTradeFactConvergedAt, finalMeasuredQueueDrainedAt) - runPhaseStartedAt)` |
| Valid run | completed counts match target, Match/Order/Wallet trade-ID sets are identical, final queue backlog is zero, publish failures/returns/nacks/timeouts are zero, and broker-confirmed input TPS reaches the configured threshold |

`DURATION_SECONDS=5` is the scheduled BUY publishing window. It is not the completed-business timing window.

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
TIMEOUT_SECONDS=300 \
DIAGNOSTICS_LEVEL=none \
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

## Current Contract-v2 Status

The benchmark contract was hardened after the 2026-07-13 public repeat to add:

- RabbitMQ publisher confirms for load-generator input.
- Separate `businessInputAttemptedOrderTps` and `businessInputBrokerAckedOrderTps`.
- `completedTradeIdSetsEqual` and missing-ID diagnostics across MatchEngine, Order, and Wallet.
- Fail-closed queue metric handling through `queueMetricsReadFailures`.
- New entrypoint names: `run-matched-trade-completion-10k.sh` and `run-matched-trade-completion-repeat.sh`.
- Separate RabbitMQ input-ceiling diagnostic entrypoint: `run-rabbitmq-publish-only-10k.sh`.

Latest diagnostic run:

| Metric | Value |
| --- | ---: |
| Run ID | `GLT_TPS126_DIRECT_CONFIRM_LIGHT_10K_R1` |
| Broker-confirmed BUY input | `1377.80/s` |
| BUY broker acks | `10000/10000` |
| Business completed trade TPS | `1234.47/s` |
| Completed trade-ID set equality | `true` |
| Final measured queues / DLQ | `0 / 0` |
| Public capacity validity | rejected: `driver_offered_tps_below_threshold` |

Interpretation: this run proves the hardened correctness gate on a 10k sample, but it does not replace the public benchmark median because broker-confirmed input did not reach the configured `95%` threshold for a `2000/s` target. The next publishable benchmark should be a clean five-run repeat under contract v2.

TPS126 also split input measurement from integrated service work:

| Probe | Broker-Confirmed Input | Completed Trades | Interpretation |
| --- | ---: | ---: | --- |
| `rabbitmq-publish-only` 10k | `1994.98/s` | N/A | RabbitMQ and the load generator can confirm near-2000/s without service consumers |
| `matched-trade-completion-chain`, `PUBLISHERS=128`, 16 connections | `1171.38/s` | `1046.34/s` | aggressive publisher fan-out increases RabbitMQ confirm contention during integrated service work |
| `matched-trade-completion-chain`, `PUBLISHERS=1` | `1531.96/s` | `1385.10/s` | lower-interference default for completed-trade-chain capacity probes |

## 2026-07-13 Official 10k Repeat Result

This is the pinned public result under the older input-attempt contract. It remains useful history, but it should not be used as proof of 2000/s broker-confirmed input.

Historical command prefix (the former `baseline` diagnostics alias is now named `none`):

```bash
REPEATS=5 TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
PUBLISHERS=1 TIMEOUT_SECONDS=300 DIAGNOSTICS_LEVEL=baseline \
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
| business completed trade TPS | `582.73` | `503.11` | `662.17` |
| business completion seconds | `17.29` | `15.10` | `19.88` |
| trade execution reach TPS | `1082.09` | `1036.83` | `1176.72` |
| Order command match reach TPS | `843.92` | `825.46` | `974.14` |
| Wallet settlement reach TPS | `843.92` | `825.46` | `974.14` |
| legacy completion marker reach TPS | `745.60` | `701.99` | `803.90` |

Per-run business TPS:

| Run | Valid | Offered TPS | Business E2E TPS | Completion Seconds | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| `R1` | yes | `1999.03` | `503.11` | `19.88` | final queues/DLQ `0` |
| `R2` | yes | `1998.54` | `532.08` | `18.79` | final queues/DLQ `0` |
| `R3` | no | `733.79` | `438.14` | `22.82` | driver offered TPS below threshold |
| `R4` | yes | `1999.13` | `662.17` | `15.10` | final queues/DLQ `0` |
| `R5` | yes | `1998.85` | `633.38` | `15.79` | final queues/DLQ `0` |

## Post-Public Local Improvement: TPS93

The 2026-07-13 repeat remains the pinned public benchmark result. A later local run set, `GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3`, is useful interview material because it shows a concrete performance improvement after the Order / Wallet batch-path work and the TPS semantic split. It should not replace the public benchmark until it is rerun on a clean contract-v2 commit snapshot with a published artifact bundle.

Command prefix:

```bash
REPEATS=3 TARGET_TPS=2000 DURATION_SECONDS=5 EVENTS=10000 \
PUBLISHERS=1 TIMEOUT_SECONDS=360 DIAGNOSTICS_LEVEL=light \
RESET_PG_STATS_BEFORE_RUN=true \
bash scripts/load-test/run-matched-trade-completion-repeat.sh \
  GLT_TPS93_THROUGHPUT_SEMANTICS_LIGHT_10K_REPEAT3
```

Validity:

| Result | Count |
| --- | ---: |
| Valid local runs | `3` |
| Invalid runs | `0` |
| Final measured queues / DLQ | `0` in every run |

Valid-runs summary:

| Metric | Median | Min | Max |
| --- | ---: | ---: | ---: |
| actual buy publish TPS | `1999.22` | `1998.46` | `1999.26` |
| orderbook admission TPS | `4211.32` | `3696.83` | `4972.65` |
| business completed trade TPS | `833.58` | `729.71` | `940.93` |
| blended market flow TPS | `1391.69` | `1218.84` | `1582.44` |
| business completion seconds | `12.00` | `10.63` | `13.70` |

Why this matters:

- It gives a measured improvement path from the earlier public median `582.73` completed trades/s to a later local median `833.58` completed trades/s.
- The input driver was stable across all three runs: actual offered TPS relative spread was only `0.04%`.
- The correctness gate was not loosened: every run reached `10000` completed trades, `10000` trade executions, `10000` wallet settlements, `20000` Order command matched rows, and final measured queues / DLQ at zero.
- The result should be discussed as median/range, not best-run throughput, because local service-side variance remained material.
- The useful interview story is not "I tuned a thread count"; it is "I fixed the measurement boundary, separated admission TPS from completed-trade TPS, then reduced hot-path batch overhead and validated the improvement with repeated correctness-gated runs."

## Validity Rules

A run is valid for public summary only if:

- `businessInputBrokerAckedOrderTps >= TARGET_TPS * MIN_OFFERED_TPS_RATIO`;
- `buyPublishFailures == 0`;
- `sellPublishFailures == 0`;
- `buyPublishBrokerAcked == EVENTS`;
- `sellPublishBrokerAcked == EVENTS`;
- `buyPublishBrokerNacked == 0`;
- `sellPublishBrokerNacked == 0`;
- `buyPublishReturned == 0`;
- `sellPublishReturned == 0`;
- `buyPublishConfirmTimedOut == 0`;
- `sellPublishConfirmTimedOut == 0`;
- `completedTrades == EVENTS`;
- `tradeExecutions == EVENTS`;
- `walletTradeSettlements == EVENTS`;
- `orderCommandMatchedRows == EVENTS * 2`;
- `completedTradeIdSetsEqual == true`;
- `remainingSellOrders == 0`;
- `remainingBuyOrders == 0`;
- `activeReservations == 0`;
- `queueMetricsReadFailures == 0`;
- final measured ready/unacked queue backlog is zero.

Invalid runs are kept in the result bundle but excluded from the public median.

## Steady-State Follow-Up

After the 10k repeat benchmark is accepted, run one 10-15 minute steady-state benchmark at a conservative target. Do not use the 2000 offered-load burst as the first steady-state claim.

Suggested first pass:

```bash
TARGET_TPS=500 \
DURATION_SECONDS=900 \
EVENTS=450000 \
PUBLISHERS=1 \
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

2026-07-14 repeat attempt:

- Goal: verify the repaired load-test harness and turn the single clean steady-state result into repeat-based evidence.
- 10k guard: `GLT_20260714_TPS58_GUARD_10K` completed the correctness gate with `10000` completed trades, aligned Order/Wallet counts, final queues/DLQ `0`, remaining orderbook entries `0`, and Redis `evicted_keys=0`. The local driver only reached `521.47` offered BUY confirmations/s, so this run is a harness/correctness guard, not a public 2000 offered-load sample.
- Steady-state runs attempted: `EAP_STEADY_500TPS_15M_20260714_R1` through `R3`.
- Valid steady-state samples: `2/3`.
- Invalid sample: `R3`, rejected as `steady_state_correctness_miss_19_trades`.

Valid steady-state samples:

| Run | Offered BUY TPS | Business E2E TPS | Completion Window | Drain After BUY | Final State |
| --- | ---: | ---: | ---: | ---: | --- |
| `R1` | `494.71` | `477.42` | `942.57s` | `32.95s` | `450000/450000`, queues/DLQ `0`, orderbook `0/0`, Redis evictions `0` |
| `R2` | `500.00` | `497.89` | `903.81s` | `3.81s` | `450000/450000`, queues/DLQ `0`, orderbook `0/0`, Redis evictions `0` |

Valid-sample summary:

| Metric | Median | Min | Max |
| --- | ---: | ---: | ---: |
| actual BUY publish TPS | `497.36` | `494.71` | `500.00` |
| business completed trade TPS | `487.66` | `477.42` | `497.89` |
| business completion seconds | `923.19` | `903.81` | `942.57` |
| drain after BUY publish | `18.38s` | `3.81s` | `32.95s` |

Rejected `R3` details:

- Offered BUY rate stayed near target: `494.78/s`, with publish failures `0`.
- Correctness gate failed: `449981 / 450000` completed trades, `449981 / 450000` trade executions, `449981 / 450000` Wallet settlements, and `899962 / 900000` Order command matched rows.
- Final broker queues and DLQ drained to zero, but `remainingBuyOrders=19`, `lockedCurrency=1900`, and `lockedAmount=19`.
- Redis remained clean: `maxmemory-policy=noeviction`, `evicted_keys=0`.
- The run log contained one RabbitMQ client message: `Received a frame on an unknown channel, ignoring it`.
- Interpretation: the earlier Redis eviction issue is fixed, but the system cannot yet claim three-run steady-state correctness. The next performance/reliability task should investigate the 19-trade miss with the preserved R3 diagnostics.

## Publication Criteria

Do not update README with a stronger public claim until:

1. Benchmark code/config is committed.
2. Container images are pinned.
3. Five 10k repeat runs complete.
4. Public table uses median plus min/max range.
5. Invalid run rules are documented before interpreting results.
6. At least one steady-state run is completed, or the rejected result and remaining gap are explicitly listed.

## Cloud Benchmark Follow-Up

The current public benchmark track is intentionally local-first. It is useful for code-path attribution, repeatability, and interview discussion, but it is not a GCP/GKE production-like capacity claim.

Open a separate GCP/GKE benchmark epic only after the local evidence is internally consistent and committed. The cloud benchmark should add infrastructure realism without changing the business correctness gate.

Minimum cloud benchmark additions:

- exact service commits and image digests;
- GKE mode, region/zone, node pool shape, pod requests/limits, replica counts, and autoscaling settings;
- PostgreSQL topology, version, CPU/memory/disk/IOPS settings, connection limits, and relevant flags;
- RabbitMQ topology, persistence settings, publisher confirm behavior, queue ready/unacked, DLQ, and disk alarm metrics;
- Redis topology, memory limit, eviction policy, peak memory, and orderbook/reservation cleanup gates;
- load-generator placement, CPU/network limits, offered-load accuracy, and client-side failures;
- repeated-run median/min/max for orderbook admission TPS, TradeExecuted reach TPS, business-completed trade TPS, and blended market-flow TPS where applicable;
- cost guard and teardown commands.

Until that epic is complete, external claims should be worded as local benchmark evidence, not cloud or production TPS.
