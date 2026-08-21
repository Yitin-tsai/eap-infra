# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-DRIVER_DEEP_VEGETA_648_SEED_20260804_R2_FIXED-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-DRIVER_DEEP_VEGETA_648_SEED_20260804_R2_FIXED-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-19T08:52:00Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 6 |
| startedAt | `2026-08-19T08:51:08Z` |
| stoppedAt | `2026-08-19T08:51:56Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `order.orderConfirmed.queue` | 83 | 0 | 83 | 83 |
| `matchEngine.orderConfirmed.queue` | 65 | 0 | 65 | 65 |
| `order.tradeExecuted.queue` | 11 | 0 | 11 | 11 |
| `wallet.tradeExecuted.queue` | 0 | 0 | 0 | 0 |
| `wallet.orderSubmitted.queue` | 0 | 0 | 0 | 0 |
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
| `rabbit@c2d709da6307` | 6 | 0 | 0 | 310484992 | 3328684851 | 452398288896 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 18 | 14430 | 0 | 36438 | 51015 | 0 |
| order | 58 | 34033 | 0 | 140252 | 77751 | 0 |
| wallet | 42 | 37401 | 0 | 60751 | 74077 | 0 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 364506 | 0 | 32357604 | 0 | 3172 | 173 | 0.000 | 0.000 |
| order | 722604 | 0 | 99076585 | 0 | 7590 | 198 | 0.000 | 0.000 |
| wallet | 379324 | 0 | 36468059 | 0 | 3408 | 176 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| wallet | `Client` | `ClientRead` | `active` | 7 | 0.001 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 6 | 0.001 |
| wallet | `none` | `none` | `active` | 4 | 0.021 |
| wallet | `LWLock` | `WALInsert` | `active` | 3 | 0.012 |
| wallet | `LWLock` | `BufferContent` | `idle` | 3 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 3 | 0.000 |
| match | `none` | `none` | `active` | 2 | 0.001 |
| wallet | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `none` | `none` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 57 | 4.445 |
| wallet | `Client` | `ClientRead` | `idle` | 41 | 2.448 |
| match | `Client` | `ClientRead` | `idle` | 17 | 18.075 |
| wallet | `Client` | `ClientRead` | `active` | 7 | 0.001 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 6 | 0.001 |
| wallet | `none` | `none` | `active` | 4 | 0.021 |
| wallet | `LWLock` | `WALInsert` | `active` | 3 | 0.012 |
| wallet | `LWLock` | `BufferContent` | `idle` | 3 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 3 | 0.000 |
| match | `none` | `none` | `active` | 2 | 0.001 |
| wallet | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `none` | `none` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 38.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 16.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 12.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 10.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 9.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 3.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.787468 |
| order | `system_cpu_usage` | 1.000000 | 0.781511 |
| match | `system_cpu_usage` | 0.964080 | 0.615176 |
| order | `process_cpu_usage` | 0.174609 | 0.088161 |
| wallet | `process_cpu_usage` | 0.100844 | 0.043511 |
| match | `process_cpu_usage` | 0.086479 | 0.034430 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 2254608 |
| used_memory_peak_bytes | 4017296 |
| instantaneous_ops_per_sec | 10914 |
| evicted_keys | 0 |
