# Runtime Hot Window Summary

- diagnostics: `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R2-diagnostics`
- samples: `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-05T05:41:44Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 22 |
| startedAt | `2026-08-05T05:37:19Z` |
| stoppedAt | `2026-08-05T05:41:29Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 8526 | 7076 | 1600 | 8526 |
| `wallet.orderSubmitted.queue` | 1743 | 1103 | 640 | 1743 |
| `wallet.tradeExecuted.queue` | 367 | 0 | 367 | 367 |
| `order.orderConfirmed.queue` | 313 | 0 | 313 | 313 |
| `order.tradeExecuted.queue` | 85 | 0 | 85 | 85 |
| `wallet.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionBidSubmitted.queue` | 0 | 0 | 0 | 0 |
| `order.orderFailed.queue` | 0 | 0 | 0 | 0 |
| `order.dlq` | 0 | 0 | 0 | 0 |
| `order.auctionCreated.queue` | 0 | 0 | 0 | 0 |
| `order.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.walletTradeSettled.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.orderTradeApplied.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.auctionBidConfirmed.queue` | 0 | 0 | 0 | 0 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 35 | 105044 | 0 | 298818 | 389672 | 10 |
| order | 61 | 231276 | 0 | 1104301 | 606122 | 119 |
| wallet | 43 | 303122 | 0 | 498894 | 598019 | 20 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 3023880 | 3272 | 301836592 | 0 | 20287 | 1133 | 0.000 | 0.000 |
| order | 6214207 | 14539 | 938210655 | 0 | 39386 | 1214 | 0.000 | 0.000 |
| wallet | 3006364 | 5110 | 348118234 | 0 | 27078 | 1068 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 21 | 0.574 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 19 | 0.028 |
| match | `Client` | `ClientRead` | `idle in transaction` | 12 | 0.015 |
| order | `none` | `none` | `active` | 9 | 0.620 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.533 |
| order | `IPC` | `XactGroupUpdate` | `active` | 7 | 0.000 |
| wallet | `none` | `none` | `active` | 6 | 0.251 |
| order | `Lock` | `extend` | `active` | 5 | 0.523 |
| order | `LWLock` | `BufferContent` | `active` | 4 | 0.011 |
| match | `none` | `none` | `active` | 4 | 0.000 |
| match | `LWLock` | `BufferContent` | `active` | 4 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 3 | 0.216 |
| wallet | `Client` | `ClientRead` | `active` | 3 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.009 |
| wallet | `none` | `none` | `idle in transaction` | 2 | 0.008 |
| order | `LWLock` | `BufferContent` | `idle` | 2 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| order | `Timeout` | `VacuumDelay` | `active` | 1 | 1.221 |
| order | `LWLock` | `WALInsert` | `idle in transaction` | 1 | 0.530 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.025 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 208.400 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 209.185 |
| match | `Client` | `ClientRead` | `idle` | 33 | 210.619 |
| order | `Client` | `ClientRead` | `idle in transaction` | 21 | 0.574 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 19 | 0.028 |
| match | `Client` | `ClientRead` | `idle in transaction` | 12 | 0.015 |
| order | `none` | `none` | `active` | 9 | 0.620 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.533 |
| order | `IPC` | `XactGroupUpdate` | `active` | 7 | 0.000 |
| wallet | `none` | `none` | `active` | 6 | 0.251 |
| order | `Lock` | `extend` | `active` | 5 | 0.523 |
| wallet | `none` | `none` | `idle` | 4 | 0.020 |
| order | `LWLock` | `BufferContent` | `active` | 4 | 0.011 |
| match | `none` | `none` | `active` | 4 | 0.000 |
| match | `LWLock` | `BufferContent` | `active` | 4 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 3 | 0.216 |
| wallet | `Client` | `ClientRead` | `active` | 3 | 0.000 |
| order | `none` | `none` | `idle` | 2 | 0.104 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.009 |
| wallet | `none` | `none` | `idle in transaction` | 2 | 0.008 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 91.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 32.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 26.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 2.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 1.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.888339 |
| order | `system_cpu_usage` | 1.000000 | 0.904378 |
| match | `system_cpu_usage` | 0.999262 | 0.864777 |
| wallet | `process_cpu_usage` | 0.237133 | 0.042705 |
| order | `process_cpu_usage` | 0.135148 | 0.067951 |
| match | `process_cpu_usage` | 0.050301 | 0.035056 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 30149872 |
| used_memory_peak_bytes | 97877224 |
| instantaneous_ops_per_sec | 14779 |
| evicted_keys | 0 |
