# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R2-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-19T08:47:24Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 7 |
| startedAt | `2026-08-19T08:46:23Z` |
| stoppedAt | `2026-08-19T08:47:19Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 656 | 6 | 650 | 656 |
| `order.orderConfirmed.queue` | 293 | 0 | 293 | 293 |
| `order.tradeExecuted.queue` | 43 | 0 | 43 | 43 |
| `wallet.orderSubmitted.queue` | 23 | 0 | 23 | 23 |
| `wallet.tradeExecuted.queue` | 6 | 0 | 6 | 6 |
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
| `rabbit@c2d709da6307` | 7 | 0 | 0 | 312254464 | 3328684851 | 452383866880 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 20 | 14974 | 0 | 38622 | 51902 | 3 |
| order | 59 | 34278 | 0 | 143546 | 79223 | 30 |
| wallet | 43 | 41440 | 0 | 65352 | 78432 | 7 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 385071 | 31 | 34694592 | 0 | 3095 | 192 | 0.000 | 0.000 |
| order | 756830 | 63 | 104141653 | 0 | 7021 | 213 | 0.000 | 0.000 |
| wallet | 413259 | 28 | 40007185 | 0 | 3657 | 204 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 8 | 0.000 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `idle` | 4 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| order | `none` | `none` | `active` | 2 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| wallet | `LWLock` | `WALInsert` | `active` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 33.565 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 34.730 |
| match | `Client` | `ClientRead` | `idle` | 18 | 35.386 |
| order | `Client` | `ClientRead` | `idle in transaction` | 8 | 0.000 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `idle` | 4 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| order | `none` | `none` | `active` | 2 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| wallet | `LWLock` | `WALInsert` | `active` | 1 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `none` | `none` | `idle` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 1 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 17.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 9.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 6.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.780900 |
| order | `system_cpu_usage` | 1.000000 | 0.789457 |
| match | `system_cpu_usage` | 0.982071 | 0.695371 |
| wallet | `process_cpu_usage` | 0.129095 | 0.045347 |
| order | `process_cpu_usage` | 0.127020 | 0.063010 |
| match | `process_cpu_usage` | 0.088246 | 0.038810 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 3069984 |
| used_memory_peak_bytes | 4017296 |
| instantaneous_ops_per_sec | 12549 |
| evicted_keys | 0 |
