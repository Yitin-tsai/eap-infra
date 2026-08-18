# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_624_DEEP_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_624_DEEP_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-14T08:49:04Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 2 |
| samples | 10 |
| startedAt | `2026-08-14T08:48:04Z` |
| stoppedAt | `2026-08-14T08:49:01Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 2413 | 1763 | 700 | 2413 |
| `wallet.tradeExecuted.queue` | 264 | 64 | 200 | 264 |
| `wallet.orderSubmitted.queue` | 213 | 0 | 213 | 213 |
| `order.tradeExecuted.queue` | 148 | 0 | 148 | 148 |
| `order.orderConfirmed.queue` | 117 | 0 | 117 | 117 |
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
| `rabbit@c2d709da6307` | 10 | 0 | 0 | 330526720 | 3328684851 | 453333123072 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 21 | 14210 | 0 | 37356 | 49368 | 3 |
| order | 59 | 32460 | 0 | 138395 | 76195 | 29 |
| wallet | 44 | 40100 | 0 | 63204 | 75714 | 6 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 371935 | 31 | 33862660 | 0 | 2875 | 193 | 0.000 | 0.000 |
| order | 742055 | 60 | 102103034 | 0 | 6280 | 213 | 0.000 | 0.000 |
| wallet | 401612 | 28 | 39427794 | 0 | 3545 | 210 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| wallet | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.001 |
| order | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.069 |
| match | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.007 |
| order | `none` | `none` | `active` | 3 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.027 |
| wallet | `none` | `none` | `active` | 2 | 0.000 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 37.595 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 38.469 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 23 | 0.001 |
| match | `Client` | `ClientRead` | `idle` | 20 | 40.122 |
| order | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.069 |
| match | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.007 |
| order | `none` | `none` | `active` | 3 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.027 |
| wallet | `none` | `none` | `active` | 2 | 0.000 |
| match | `none` | `none` | `idle` | 1 | 0.014 |
| wallet | `none` | `none` | `idle` | 1 | 0.006 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 18.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 14.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 9.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 4.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.804041 |
| order | `system_cpu_usage` | 1.000000 | 0.805349 |
| match | `system_cpu_usage` | 0.999558 | 0.742323 |
| order | `process_cpu_usage` | 0.146248 | 0.069748 |
| match | `process_cpu_usage` | 0.097674 | 0.039333 |
| wallet | `process_cpu_usage` | 0.073209 | 0.033361 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 5334984 |
| used_memory_peak_bytes | 6209272 |
| instantaneous_ops_per_sec | 15584 |
| evicted_keys | 0 |
