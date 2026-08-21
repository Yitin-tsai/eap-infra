# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R2-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-20T01:26:03Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 38 |
| startedAt | `2026-08-20T01:19:04Z` |
| stoppedAt | `2026-08-20T01:25:53Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 1278 | 528 | 841 | 1278 |
| `wallet.orderSubmitted.queue` | 1084 | 444 | 640 | 1084 |
| `order.orderConfirmed.queue` | 252 | 0 | 252 | 252 |
| `wallet.tradeExecuted.queue` | 172 | 0 | 172 | 172 |
| `order.tradeExecuted.queue` | 153 | 0 | 153 | 153 |
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
| `rabbit@c2d709da6307` | 38 | 0 | 0 | 379441152 | 3328684851 | 447320539136 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 37 | 140520 | 0 | 374575 | 489577 | 10 |
| order | 61 | 323354 | 0 | 1397726 | 770945 | 226 |
| wallet | 44 | 380982 | 0 | 626242 | 751771 | 45 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 3699461 | 36 | 336294231 | 0 | 27802 | 1795 | 0.000 | 0.000 |
| order | 7705936 | 73 | 1063174738 | 0 | 64789 | 1939 | 0.000 | 0.000 |
| wallet | 3999606 | 27 | 406741319 | 0 | 34230 | 1719 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 31 | 0.661 |
| order | `LWLock` | `BufferContent` | `active` | 30 | 0.073 |
| match | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.084 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.063 |
| order | `LWLock` | `WALInsert` | `active` | 22 | 0.101 |
| wallet | `LWLock` | `BufferContent` | `active` | 18 | 0.031 |
| order | `none` | `none` | `active` | 7 | 2.138 |
| wallet | `none` | `none` | `active` | 7 | 0.283 |
| wallet | `Client` | `ClientRead` | `active` | 7 | 0.062 |
| order | `Lock` | `extend` | `active` | 6 | 0.752 |
| match | `Lock` | `extend` | `active` | 4 | 0.031 |
| order | `Client` | `ClientRead` | `active` | 3 | 0.657 |
| order | `none` | `none` | `idle in transaction` | 3 | 0.045 |
| match | `none` | `none` | `active` | 2 | 0.031 |
| order | `LWLock` | `WALInsert` | `idle in transaction` | 2 | 0.021 |
| match | `LWLock` | `WALInsert` | `active` | 2 | 0.011 |
| order | `LWLock` | `WALInsert` | `idle` | 1 | 0.248 |
| wallet | `LWLock` | `BufferContent` | `idle in transaction` | 1 | 0.059 |
| match | `none` | `none` | `idle in transaction` | 1 | 0.046 |
| wallet | `LWLock` | `WALInsert` | `active` | 1 | 0.045 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 100.645 |
| wallet | `Client` | `ClientRead` | `idle` | 41 | 28.935 |
| match | `Client` | `ClientRead` | `idle` | 35 | 102.926 |
| order | `Client` | `ClientRead` | `idle in transaction` | 31 | 0.661 |
| order | `LWLock` | `BufferContent` | `active` | 30 | 0.073 |
| match | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.084 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.063 |
| order | `LWLock` | `WALInsert` | `active` | 22 | 0.101 |
| wallet | `LWLock` | `BufferContent` | `active` | 18 | 0.031 |
| order | `none` | `none` | `active` | 7 | 2.138 |
| wallet | `none` | `none` | `active` | 7 | 0.283 |
| wallet | `Client` | `ClientRead` | `active` | 7 | 0.062 |
| order | `Lock` | `extend` | `active` | 6 | 0.752 |
| match | `Lock` | `extend` | `active` | 4 | 0.031 |
| order | `Client` | `ClientRead` | `active` | 3 | 0.657 |
| order | `none` | `none` | `idle` | 3 | 0.046 |
| order | `none` | `none` | `idle in transaction` | 3 | 0.045 |
| match | `none` | `none` | `idle` | 2 | 0.090 |
| match | `none` | `none` | `active` | 2 | 0.031 |
| order | `LWLock` | `WALInsert` | `idle in transaction` | 2 | 0.021 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 151.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 34.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 26.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 22.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 7.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.821642 |
| order | `system_cpu_usage` | 1.000000 | 0.766383 |
| match | `system_cpu_usage` | 0.999818 | 0.782923 |
| wallet | `process_cpu_usage` | 0.190476 | 0.032984 |
| order | `process_cpu_usage` | 0.180409 | 0.053047 |
| match | `process_cpu_usage` | 0.083411 | 0.026455 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 28241016 |
| used_memory_peak_bytes | 58633088 |
| instantaneous_ops_per_sec | 17513 |
| evicted_keys | 0 |
