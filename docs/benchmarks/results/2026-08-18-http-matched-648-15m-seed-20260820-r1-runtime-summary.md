# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260820_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260820_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-18T03:52:39Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `light` |
| intervalSeconds | 5 |
| samples | 107 |
| startedAt | `2026-08-18T03:35:18Z` |
| stoppedAt | `2026-08-18T03:52:17Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `wallet.orderSubmitted.queue` | 1452 | 812 | 640 | 1452 |
| `matchEngine.orderConfirmed.queue` | 1271 | 0 | 1271 | 1271 |
| `order.orderConfirmed.queue` | 350 | 0 | 350 | 350 |
| `wallet.tradeExecuted.queue` | 226 | 0 | 226 | 226 |
| `order.tradeExecuted.queue` | 143 | 0 | 143 | 143 |
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
| `rabbit@c2d709da6307` | 107 | 0 | 0 | 389902336 | 3328684851 | 447321661440 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 40 | 358557 | 0 | 932856 | 1244476 | 15 |
| order | 63 | 825953 | 0 | 3463271 | 1911426 | 531 |
| wallet | 45 | 950884 | 0 | 1556144 | 1867504 | 92 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 9359991 | 5956 | 885334414 | 0 | 72250 | 4725 | 0.000 | 0.000 |
| order | 18842082 | 33545 | 2790101338 | 0 | 176937 | 6303 | 0.000 | 0.000 |
| wallet | 9875508 | 13803 | 1062875162 | 0 | 83896 | 4583 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 29 | 0.192 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 25 | 0.069 |
| order | `Lock` | `extend` | `active` | 24 | 0.503 |
| wallet | `LWLock` | `BufferContent` | `active` | 22 | 0.077 |
| match | `Client` | `ClientRead` | `idle in transaction` | 21 | 0.061 |
| order | `none` | `none` | `active` | 20 | 11.326 |
| order | `LWLock` | `BufferContent` | `active` | 18 | 0.185 |
| match | `LWLock` | `BufferContent` | `active` | 11 | 0.011 |
| wallet | `LWLock` | `WALInsert` | `active` | 8 | 0.034 |
| wallet | `none` | `none` | `active` | 7 | 0.980 |
| order | `Client` | `ClientRead` | `active` | 5 | 0.023 |
| match | `none` | `none` | `active` | 4 | 2.438 |
| wallet | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 3 | 29.423 |
| match | `LWLock` | `BufferContent` | `idle` | 3 | 0.024 |
| wallet | `none` | `none` | `idle in transaction` | 3 | 0.016 |
| order | `none` | `none` | `idle in transaction` | 3 | 0.001 |
| order | `Timeout` | `VacuumDelay` | `active` | 2 | 13.168 |
| order | `LWLock` | `LockManager` | `active` | 2 | 0.175 |
| order | `LWLock` | `WALInsert` | `active` | 2 | 0.135 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 951.235 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 971.249 |
| match | `Client` | `ClientRead` | `idle` | 37 | 973.807 |
| order | `Client` | `ClientRead` | `idle in transaction` | 29 | 0.192 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 25 | 0.069 |
| order | `Lock` | `extend` | `active` | 24 | 0.503 |
| wallet | `LWLock` | `BufferContent` | `active` | 22 | 0.077 |
| match | `Client` | `ClientRead` | `idle in transaction` | 21 | 0.061 |
| order | `none` | `none` | `active` | 20 | 11.326 |
| order | `LWLock` | `BufferContent` | `active` | 18 | 0.185 |
| match | `LWLock` | `BufferContent` | `active` | 11 | 0.011 |
| wallet | `LWLock` | `WALInsert` | `active` | 8 | 0.034 |
| wallet | `none` | `none` | `active` | 7 | 0.980 |
| order | `Client` | `ClientRead` | `active` | 5 | 0.023 |
| match | `none` | `none` | `active` | 4 | 2.438 |
| order | `none` | `none` | `idle` | 4 | 0.185 |
| wallet | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 3 | 29.423 |
| wallet | `none` | `none` | `idle` | 3 | 0.343 |
| match | `LWLock` | `BufferContent` | `idle` | 3 | 0.024 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 90.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 25.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 17.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.877663 |
| order | `system_cpu_usage` | 1.000000 | 0.872731 |
| match | `system_cpu_usage` | 0.999715 | 0.849551 |
| wallet | `process_cpu_usage` | 0.155932 | 0.026946 |
| order | `process_cpu_usage` | 0.146327 | 0.045515 |
| match | `process_cpu_usage` | 0.091775 | 0.025031 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 13860944 |
| used_memory_peak_bytes | 15022800 |
| instantaneous_ops_per_sec | 18759 |
| evicted_keys | 0 |
