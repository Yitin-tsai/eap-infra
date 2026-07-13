# EAP Public Benchmark Plan - 2026-07

Status: planned. This document defines the benchmark release criteria before publishing a stronger README claim.

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

Before publishing final numbers, fill in the exact Git commit after committing benchmark code/config.

```text
gitCommit=<fill after commit>
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

## Publication Criteria

Do not update README with a stronger public claim until:

1. Benchmark code/config is committed.
2. Container images are pinned.
3. Five 10k repeat runs complete.
4. Public table uses median plus min/max range.
5. Invalid run rules are documented before interpreting results.
6. At least one steady-state run is completed or explicitly listed as a remaining gap.
