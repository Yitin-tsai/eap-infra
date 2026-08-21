# Runtime Hot Window Summary

- diagnostics: `build/load-test-reports/http-matched-external-ORDER_POOL_ATTRIBUTION_700_20260820_R1-diagnostics`
- samples: `build/load-test-reports/http-matched-external-ORDER_POOL_ATTRIBUTION_700_20260820_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-20T08:08:58Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 41 |
| startedAt | `2026-08-20T07:56:38Z` |
| stoppedAt | `2026-08-20T08:08:08Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 4376 | 3626 | 1500 | 4376 |
| `wallet.orderSubmitted.queue` | 1003 | 363 | 640 | 1003 |
| `order.orderConfirmed.queue` | 432 | 0 | 432 | 432 |
| `order.tradeExecuted.queue` | 203 | 0 | 203 | 203 |
| `wallet.tradeExecuted.queue` | 185 | 0 | 185 | 185 |
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
| `rabbit@c2d709da6307` | 41 | 0 | 0 | 397918208 | 3328684851 | 448964517888 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 39 | 208680 | 0 | 581464 | 510354 | 17 |
| order | 61 | 558533 | 0 | 2356050 | 1181060 | 325 |
| wallet | 44 | 587843 | 0 | 967510 | 1161546 | 63 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 4685292 | 30 | 437670690 | 0 | 36581 | 3086 | 0.000 | 0.000 |
| order | 12863704 | 129 | 1812096969 | 0 | 84979 | 3318 | 0.000 | 0.000 |
| wallet | 6211597 | 53 | 641054530 | 0 | 51199 | 3097 | 0.000 | 0.000 |

## PostgreSQL Background Writer Delta

These cluster-level deltas distinguish checkpoint or backend write pressure from in-memory WAL and buffer contention.

| Service | Timed checkpoints | Requested checkpoints | Checkpoint write ms | Checkpoint sync ms | Checkpoint buffers | Clean buffers | Maxwritten stops | Backend buffers | Backend fsyncs | Allocated buffers |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 0 | 0 | 0.000 | 0.000 | 0 | 0 | 0 | 0 | 0 | 19152 |
| order | 0 | 0 | 0.000 | 0.000 | 0 | 78775 | 659 | 126964 | 0 | 131847 |
| wallet | 0 | 0 | 0.000 | 0.000 | 0 | 0 | 0 | 0 | 0 | 31803 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Application / pool | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---|---:|---:|
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 24 | 0.173 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.280 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.070 |
| match | `PostgreSQL JDBC Driver` | `LWLock` | `BufferContent` | `active` | 13 | 0.036 |
| order | `OrderConsumerPool` | `none` | `none` | `active` | 11 | 0.575 |
| wallet | `PostgreSQL JDBC Driver` | `LWLock` | `BufferContent` | `active` | 11 | 0.136 |
| order | `OrderConsumerPool` | `Lock` | `extend` | `active` | 11 | 0.066 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle in transaction` | 10 | 0.263 |
| wallet | `PostgreSQL JDBC Driver` | `Lock` | `extend` | `active` | 10 | 0.016 |
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `active` | 9 | 0.084 |
| order | `OrderCommandPool` | `LWLock` | `BufferContent` | `active` | 9 | 0.076 |
| order | `OrderCommandPool` | `Lock` | `extend` | `active` | 7 | 0.047 |
| order | `OrderCommandPool` | `LWLock` | `WALInsert` | `idle in transaction` | 5 | 0.076 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `active` | 4 | 0.163 |
| order | `OrderCommandPool` | `LWLock` | `BufferContent` | `idle` | 4 | 0.058 |
| wallet | `PostgreSQL JDBC Driver` | `none` | `none` | `active` | 3 | 0.588 |
| order | `OrderConsumerPool` | `LWLock` | `BufferContent` | `active` | 3 | 0.378 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `active` | 3 | 0.318 |
| order | `OrderCommandPool` | `none` | `none` | `active` | 3 | 0.303 |
| order | `OrderCommandPool` | `none` | `none` | `idle in transaction` | 3 | 0.273 |

## PostgreSQL All Wait Peaks

| Service | Application / pool | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---|---:|---:|
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle` | 41 | 1.998 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle` | 35 | 107.546 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle` | 35 | 0.326 |
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 24 | 0.173 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.280 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle` | 20 | 25.046 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.070 |
| match | `PostgreSQL JDBC Driver` | `LWLock` | `BufferContent` | `active` | 13 | 0.036 |
| order | `OrderConsumerPool` | `none` | `none` | `active` | 11 | 0.575 |
| wallet | `PostgreSQL JDBC Driver` | `LWLock` | `BufferContent` | `active` | 11 | 0.136 |
| order | `OrderConsumerPool` | `Lock` | `extend` | `active` | 11 | 0.066 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle in transaction` | 10 | 0.263 |
| wallet | `PostgreSQL JDBC Driver` | `Lock` | `extend` | `active` | 10 | 0.016 |
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `active` | 9 | 0.084 |
| order | `OrderCommandPool` | `LWLock` | `BufferContent` | `active` | 9 | 0.076 |
| order | `OrderCommandPool` | `Lock` | `extend` | `active` | 7 | 0.047 |
| wallet | `PostgreSQL JDBC Driver` | `none` | `none` | `idle` | 6 | 0.191 |
| order | `OrderCommandPool` | `LWLock` | `WALInsert` | `idle in transaction` | 5 | 0.076 |
| order | `OrderCommandPool` | `none` | `none` | `idle` | 4 | 0.225 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `active` | 4 | 0.163 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 161.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 24.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 23.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.897886 |
| order | `system_cpu_usage` | 1.000000 | 0.926156 |
| match | `system_cpu_usage` | 0.999173 | 0.930542 |
| order | `process_cpu_usage` | 0.561538 | 0.074047 |
| wallet | `process_cpu_usage` | 0.185901 | 0.033058 |
| match | `process_cpu_usage` | 0.071347 | 0.026185 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 53956000 |
| used_memory_peak_bytes | 54609960 |
| instantaneous_ops_per_sec | 18105 |
| evicted_keys | 0 |
