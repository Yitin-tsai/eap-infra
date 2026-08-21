# Runtime Hot Window Summary

- diagnostics: `ORDER_POOL_ATTRIBUTION_648_20260820_R1`
- raw samples: removed after summary generation
- generatedAt: 2026-08-20T02:56:00Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 10 |
| startedAt | `2026-08-20T02:53:02Z` |
| stoppedAt | `2026-08-20T02:54:28Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `order.orderConfirmed.queue` | 168 | 0 | 168 | 168 |
| `wallet.orderSubmitted.queue` | 157 | 0 | 157 | 157 |
| `order.tradeExecuted.queue` | 128 | 0 | 128 | 128 |
| `matchEngine.orderConfirmed.queue` | 95 | 0 | 95 | 95 |
| `wallet.tradeExecuted.queue` | 79 | 0 | 79 | 79 |
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
| `rabbit@c2d709da6307` | 10 | 0 | 0 | 301920256 | 3328684851 | 449919156224 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 22 | 29226 | 0 | 73998 | 98913 | 4 |
| order | 59 | 68420 | 0 | 281789 | 156048 | 74 |
| wallet | 43 | 75796 | 0 | 124118 | 148906 | 7 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 724719 | 30 | 64877604 | 0 | 6417 | 359 | 723.056 | 2083.518 |
| order | 1472673 | 67 | 202027432 | 0 | 15750 | 390 | 5072.794 | 2381.552 |
| wallet | 772815 | 30 | 74675981 | 0 | 6938 | 351 | 1552.408 | 1779.971 |

## PostgreSQL Background Writer Delta

These cluster-level deltas distinguish checkpoint or backend write pressure from in-memory WAL and buffer contention.

| Service | Timed checkpoints | Requested checkpoints | Checkpoint write ms | Checkpoint sync ms | Checkpoint buffers | Clean buffers | Maxwritten stops | Backend buffers | Backend fsyncs | Allocated buffers |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 0 | 0 | 0.000 | 0.000 | 0 | 0 | 0 | 0 | 0 | 2395 |
| order | 0 | 0 | 0.000 | 0.000 | 0 | 0 | 0 | 0 | 0 | 15566 |
| wallet | 0 | 0 | 0.000 | 0.000 | 0 | 0 | 0 | 0 | 0 | 4331 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Application / pool | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---|---:|---:|
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle in transaction` | 9 | 0.008 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle in transaction` | 5 | 0.016 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 5 | 0.008 |
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.008 |
| order | `OrderConsumerPool` | `none` | `none` | `idle in transaction` | 3 | 0.005 |
| order | `OrderConsumerPool` | `none` | `none` | `active` | 2 | 0.003 |
| order | `OrderCommandPool` | `Lock` | `extend` | `idle` | 1 | 0.089 |
| wallet | `PostgreSQL JDBC Driver` | `none` | `none` | `active` | 1 | 0.016 |
| order | `OrderCommandPool` | `none` | `none` | `active` | 1 | 0.002 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `active` | 1 | 0.001 |

## PostgreSQL All Wait Peaks

| Service | Application / pool | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---|---:|---:|
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle` | 41 | 1.854 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle` | 35 | 0.305 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle` | 20 | 12.971 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle` | 20 | 0.166 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `idle in transaction` | 9 | 0.008 |
| order | `OrderCommandPool` | `Client` | `ClientRead` | `idle in transaction` | 5 | 0.016 |
| match | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 5 | 0.008 |
| wallet | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.008 |
| order | `OrderConsumerPool` | `none` | `none` | `idle in transaction` | 3 | 0.005 |
| order | `OrderProjectionPool` | `Client` | `ClientRead` | `idle` | 2 | 73.668 |
| order | `OrderCommandPool` | `none` | `none` | `idle` | 2 | 0.091 |
| wallet | `PostgreSQL JDBC Driver` | `none` | `none` | `idle` | 2 | 0.006 |
| order | `OrderConsumerPool` | `none` | `none` | `active` | 2 | 0.003 |
| order | `PostgreSQL JDBC Driver` | `Client` | `ClientRead` | `idle` | 1 | 1.946 |
| order | `OrderCommandPool` | `Lock` | `extend` | `idle` | 1 | 0.089 |
| wallet | `PostgreSQL JDBC Driver` | `none` | `none` | `active` | 1 | 0.016 |
| order | `OrderCommandPool` | `none` | `none` | `active` | 1 | 0.002 |
| order | `OrderConsumerPool` | `Client` | `ClientRead` | `active` | 1 | 0.001 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 33.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 13.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 11.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 10.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.867640 |
| match | `system_cpu_usage` | 0.943970 | 0.738162 |
| order | `system_cpu_usage` | 0.922121 | 0.870194 |
| order | `process_cpu_usage` | 0.077558 | 0.065850 |
| match | `process_cpu_usage` | 0.037107 | 0.028023 |
| wallet | `process_cpu_usage` | 0.036421 | 0.027498 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 2343936 |
| used_memory_peak_bytes | 3139256 |
| instantaneous_ops_per_sec | 9980 |
| evicted_keys | 0 |
