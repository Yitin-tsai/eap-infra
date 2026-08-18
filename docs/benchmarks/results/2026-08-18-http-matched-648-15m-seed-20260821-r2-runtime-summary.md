# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260821_R2-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260821_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-18T04:12:16Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `light` |
| intervalSeconds | 5 |
| samples | 95 |
| startedAt | `2026-08-18T03:54:30Z` |
| stoppedAt | `2026-08-18T04:11:57Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 3758 | 2158 | 1600 | 3758 |
| `order.orderConfirmed.queue` | 611 | 0 | 611 | 611 |
| `wallet.orderSubmitted.queue` | 469 | 0 | 469 | 469 |
| `order.tradeExecuted.queue` | 393 | 0 | 393 | 393 |
| `wallet.tradeExecuted.queue` | 286 | 0 | 286 | 286 |
| `order.auctionCreated.queue` | 1 | 0 | 1 | 1 |
| `wallet.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionBidSubmitted.queue` | 0 | 0 | 0 | 0 |
| `order.orderFailed.queue` | 0 | 0 | 0 | 0 |
| `order.dlq` | 0 | 0 | 0 | 0 |
| `order.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.auctionBidConfirmed.queue` | 0 | 0 | 0 | 0 |

## RabbitMQ Resource Alarms

| Node | Samples | Memory alarm samples | Disk alarm samples | Max memory bytes | Memory limit bytes | Min disk free bytes | Disk limit bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| `rabbit@c2d709da6307` | 95 | 0 | 0 | 423673856 | 3328684851 | 445116633088 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 40 | 348341 | 0 | 932814 | 1244801 | 18 |
| order | 63 | 800975 | 0 | 3459651 | 1907419 | 492 |
| wallet | 47 | 948546 | 0 | 1556023 | 1867233 | 98 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 9424100 | 4248 | 888638667 | 0 | 68660 | 4798 | 0.000 | 0.000 |
| order | 19259824 | 28326 | 2818131304 | 0 | 153572 | 6185 | 0.000 | 0.000 |
| wallet | 9969893 | 7672 | 1057253219 | 0 | 84852 | 4594 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 33 | 0.540 |
| order | `Lock` | `extend` | `active` | 29 | 0.100 |
| order | `LWLock` | `BufferContent` | `active` | 27 | 0.188 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 25 | 0.025 |
| wallet | `LWLock` | `BufferContent` | `active` | 21 | 0.000 |
| order | `none` | `none` | `active` | 15 | 31.530 |
| match | `Client` | `ClientRead` | `idle in transaction` | 15 | 0.025 |
| wallet | `none` | `none` | `active` | 8 | 4.614 |
| order | `Client` | `ClientRead` | `active` | 7 | 0.495 |
| wallet | `none` | `none` | `idle in transaction` | 6 | 0.006 |
| order | `LWLock` | `WALInsert` | `active` | 6 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 5 | 22.168 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.000 |
| match | `none` | `none` | `active` | 4 | 1.994 |
| wallet | `LWLock` | `WALInsert` | `active` | 4 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 3 | 0.768 |
| match | `none` | `none` | `idle in transaction` | 3 | 0.021 |
| order | `Timeout` | `VacuumDelay` | `active` | 2 | 32.535 |
| order | `LWLock` | `LockManager` | `active` | 2 | 0.100 |
| match | `LWLock` | `WALInsert` | `active` | 2 | 0.021 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 942.254 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 978.118 |
| match | `Client` | `ClientRead` | `idle` | 36 | 979.174 |
| order | `Client` | `ClientRead` | `idle in transaction` | 33 | 0.540 |
| order | `Lock` | `extend` | `active` | 29 | 0.100 |
| order | `LWLock` | `BufferContent` | `active` | 27 | 0.188 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 25 | 0.025 |
| wallet | `LWLock` | `BufferContent` | `active` | 21 | 0.000 |
| order | `none` | `none` | `active` | 15 | 31.530 |
| match | `Client` | `ClientRead` | `idle in transaction` | 15 | 0.025 |
| order | `none` | `none` | `idle` | 14 | 0.985 |
| wallet | `none` | `none` | `active` | 8 | 4.614 |
| order | `Client` | `ClientRead` | `active` | 7 | 0.495 |
| match | `none` | `none` | `idle` | 6 | 0.372 |
| wallet | `none` | `none` | `idle in transaction` | 6 | 0.006 |
| order | `LWLock` | `WALInsert` | `active` | 6 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 5 | 22.168 |
| wallet | `none` | `none` | `idle` | 5 | 0.126 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.000 |
| match | `none` | `none` | `active` | 4 | 1.994 |

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
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 28.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 25.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 9.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.873807 |
| order | `system_cpu_usage` | 1.000000 | 0.878477 |
| match | `system_cpu_usage` | 0.999527 | 0.873066 |
| wallet | `process_cpu_usage` | 0.700000 | 0.033756 |
| order | `process_cpu_usage` | 0.139141 | 0.043839 |
| match | `process_cpu_usage` | 0.079057 | 0.025067 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 48941336 |
| used_memory_peak_bytes | 49307896 |
| instantaneous_ops_per_sec | 20229 |
| evicted_keys | 0 |
