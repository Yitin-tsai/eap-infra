# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-20T01:14:26Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 22 |
| startedAt | `2026-08-20T01:06:01Z` |
| stoppedAt | `2026-08-20T01:14:15Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 9754 | 8854 | 1300 | 9754 |
| `wallet.orderSubmitted.queue` | 1648 | 1008 | 640 | 1648 |
| `order.orderConfirmed.queue` | 502 | 0 | 502 | 502 |
| `order.tradeExecuted.queue` | 482 | 0 | 482 | 482 |
| `wallet.tradeExecuted.queue` | 348 | 0 | 348 | 348 |
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
| `rabbit@c2d709da6307` | 22 | 0 | 0 | 389935104 | 3328684851 | 446386225152 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 36 | 117543 | 0 | 326108 | 438693 | 13 |
| order | 61 | 281952 | 0 | 1222728 | 673823 | 288 |
| wallet | 43 | 331422 | 0 | 545300 | 655478 | 50 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 3291161 | 11 | 302633224 | 0 | 21758 | 2174 | 0.000 | 0.000 |
| order | 7060910 | 62 | 984881786 | 0 | 36644 | 2099 | 0.000 | 0.000 |
| wallet | 3523385 | 36 | 373673769 | 0 | 28047 | 2047 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `LWLock` | `BufferContent` | `active` | 36 | 0.067 |
| order | `Client` | `ClientRead` | `idle in transaction` | 30 | 0.096 |
| order | `Lock` | `extend` | `active` | 27 | 0.327 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 22 | 0.069 |
| order | `LWLock` | `WALInsert` | `active` | 15 | 0.018 |
| match | `Client` | `ClientRead` | `idle in transaction` | 13 | 0.054 |
| order | `Client` | `ClientRead` | `active` | 11 | 0.000 |
| order | `none` | `none` | `active` | 10 | 20.410 |
| wallet | `none` | `none` | `active` | 7 | 1.154 |
| wallet | `Lock` | `extend` | `active` | 5 | 0.074 |
| match | `none` | `none` | `active` | 4 | 0.010 |
| wallet | `LWLock` | `BufferContent` | `active` | 3 | 0.000 |
| wallet | `Lock` | `transactionid` | `active` | 2 | 0.031 |
| wallet | `Client` | `ClientRead` | `active` | 2 | 0.002 |
| order | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `LWLock` | `XidGen` | `active` | 2 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| order | `Timeout` | `VacuumDelay` | `active` | 1 | 2.932 |
| order | `IO` | `DataFileExtend` | `active` | 1 | 0.121 |
| wallet | `IPC` | `BgWorkerShutdown` | `active` | 1 | 0.111 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 105.633 |
| wallet | `Client` | `ClientRead` | `idle` | 41 | 42.589 |
| order | `LWLock` | `BufferContent` | `active` | 36 | 0.067 |
| match | `Client` | `ClientRead` | `idle` | 35 | 48.161 |
| order | `Client` | `ClientRead` | `idle in transaction` | 30 | 0.096 |
| order | `Lock` | `extend` | `active` | 27 | 0.327 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 22 | 0.069 |
| order | `LWLock` | `WALInsert` | `active` | 15 | 0.018 |
| match | `Client` | `ClientRead` | `idle in transaction` | 13 | 0.054 |
| order | `Client` | `ClientRead` | `active` | 11 | 0.000 |
| order | `none` | `none` | `active` | 10 | 20.410 |
| wallet | `none` | `none` | `active` | 7 | 1.154 |
| order | `none` | `none` | `idle` | 6 | 0.335 |
| wallet | `Lock` | `extend` | `active` | 5 | 0.074 |
| match | `none` | `none` | `active` | 4 | 0.010 |
| wallet | `none` | `none` | `idle` | 3 | 0.160 |
| wallet | `LWLock` | `BufferContent` | `active` | 3 | 0.000 |
| wallet | `Lock` | `transactionid` | `active` | 2 | 0.031 |
| wallet | `Client` | `ClientRead` | `active` | 2 | 0.002 |
| order | `none` | `none` | `idle in transaction` | 2 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 163.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 34.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 25.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 19.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 17.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.908660 |
| order | `system_cpu_usage` | 1.000000 | 0.787519 |
| match | `system_cpu_usage` | 0.999756 | 0.860119 |
| order | `process_cpu_usage` | 0.132251 | 0.041583 |
| wallet | `process_cpu_usage` | 0.072830 | 0.023476 |
| match | `process_cpu_usage` | 0.035701 | 0.022860 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 58103120 |
| used_memory_peak_bytes | 58633088 |
| instantaneous_ops_per_sec | 18481 |
| evicted_keys | 0 |
