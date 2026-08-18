# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_600_648_LIGHT_SEED20260817_R4-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_600_648_LIGHT_SEED20260817_R4-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-14T09:00:25Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `light` |
| intervalSeconds | 2 |
| samples | 29 |
| startedAt | `2026-08-14T08:58:06Z` |
| stoppedAt | `2026-08-14T09:00:22Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 1437 | 237 | 1200 | 1437 |
| `order.orderConfirmed.queue` | 217 | 0 | 217 | 217 |
| `wallet.orderSubmitted.queue` | 154 | 0 | 154 | 154 |
| `order.tradeExecuted.queue` | 38 | 0 | 38 | 38 |
| `wallet.tradeExecuted.queue` | 35 | 0 | 35 | 35 |
| `wallet.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionBidSubmitted.queue` | 0 | 0 | 0 | 0 |
| `order.orderFailed.queue` | 0 | 0 | 0 | 0 |
| `order.dlq` | 0 | 0 | 0 | 0 |
| `order.auctionCreated.queue` | 0 | 0 | 0 | 0 |
| `order.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.auctionBidConfirmed.queue` | 0 | 0 | 0 | 0 |

## RabbitMQ Resource Alarms

| Node | Samples | Memory alarm samples | Disk alarm samples | Max memory bytes | Memory limit bytes | Min disk free bytes | Disk limit bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| `rabbit@c2d709da6307` | 29 | 0 | 0 | 349331456 | 3328684851 | 452591316992 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 25 | 44358 | 0 | 112119 | 149884 | 6 |
| order | 60 | 101184 | 0 | 416502 | 229764 | 67 |
| wallet | 43 | 116500 | 0 | 187843 | 224400 | 13 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 1108828 | 55 | 99620018 | 0 | 9383 | 565 | 0.000 | 0.000 |
| order | 2203283 | 141 | 302664038 | 0 | 22485 | 617 | 0.000 | 0.000 |
| wallet | 1179432 | 46 | 115107656 | 0 | 10405 | 568 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 30 | 0.127 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 29 | 0.033 |
| match | `Client` | `ClientRead` | `idle in transaction` | 10 | 0.000 |
| order | `none` | `none` | `active` | 4 | 0.183 |
| wallet | `none` | `none` | `active` | 3 | 0.000 |
| match | `none` | `none` | `active` | 2 | 0.003 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 1 | 0.101 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| order | `LWLock` | `WALInsert` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 123.636 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 123.973 |
| order | `Client` | `ClientRead` | `idle in transaction` | 30 | 0.127 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 29 | 0.033 |
| match | `Client` | `ClientRead` | `idle` | 23 | 120.426 |
| match | `Client` | `ClientRead` | `idle in transaction` | 10 | 0.000 |
| order | `none` | `none` | `active` | 4 | 0.183 |
| wallet | `none` | `none` | `idle` | 3 | 0.000 |
| wallet | `none` | `none` | `active` | 3 | 0.000 |
| match | `none` | `none` | `active` | 2 | 0.003 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `none` | `none` | `idle` | 1 | 0.102 |
| order | `IO` | `DataFileRead` | `active` | 1 | 0.101 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| order | `LWLock` | `WALInsert` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 37.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 33.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 22.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 13.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.720123 |
| order | `system_cpu_usage` | 1.000000 | 0.782076 |
| match | `system_cpu_usage` | 1.000000 | 0.730293 |
| wallet | `process_cpu_usage` | 0.320000 | 0.041737 |
| order | `process_cpu_usage` | 0.143057 | 0.056481 |
| match | `process_cpu_usage` | 0.092939 | 0.031233 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 4410128 |
| used_memory_peak_bytes | 7894072 |
| instantaneous_ops_per_sec | 17269 |
| evicted_keys | 0 |
