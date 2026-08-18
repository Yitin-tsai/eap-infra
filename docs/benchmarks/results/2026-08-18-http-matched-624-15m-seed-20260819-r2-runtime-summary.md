# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260819_R2-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260819_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-18T02:18:09Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `light` |
| intervalSeconds | 5 |
| samples | 120 |
| startedAt | `2026-08-18T02:01:30Z` |
| stoppedAt | `2026-08-18T02:17:50Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 421 | 0 | 421 | 421 |
| `wallet.orderSubmitted.queue` | 287 | 0 | 287 | 287 |
| `order.orderConfirmed.queue` | 205 | 0 | 205 | 205 |
| `order.tradeExecuted.queue` | 92 | 0 | 92 | 92 |
| `wallet.tradeExecuted.queue` | 80 | 0 | 80 | 80 |
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
| `rabbit@c2d709da6307` | 120 | 0 | 0 | 342728704 | 3328684851 | 447808159744 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 38 | 359026 | 0 | 898319 | 1198721 | 20 |
| order | 61 | 822189 | 0 | 3340286 | 1845711 | 534 |
| wallet | 45 | 918242 | 0 | 1498426 | 1798244 | 101 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 8913949 | 4010 | 824853756 | 0 | 74201 | 4539 | 0.000 | 0.000 |
| order | 17928933 | 34628 | 2655203035 | 0 | 197724 | 6154 | 0.000 | 0.000 |
| wallet | 9482070 | 10477 | 991432151 | 0 | 82252 | 4453 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.093 |
| wallet | `Lock` | `extend` | `active` | 22 | 0.112 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 20 | 0.018 |
| match | `Client` | `ClientRead` | `idle in transaction` | 18 | 0.011 |
| wallet | `LWLock` | `BufferContent` | `active` | 13 | 0.003 |
| wallet | `none` | `none` | `active` | 9 | 0.890 |
| order | `none` | `none` | `active` | 7 | 8.421 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.000 |
| match | `none` | `none` | `active` | 4 | 0.333 |
| order | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 3 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 2 | 4.497 |
| wallet | `LWLock` | `BufferContent` | `idle` | 2 | 0.099 |
| order | `none` | `none` | `idle in transaction` | 2 | 0.014 |
| wallet | `LWLock` | `WALInsert` | `active` | 2 | 0.002 |
| order | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| order | `Timeout` | `VacuumDelay` | `active` | 1 | 6.886 |
| order | `IO` | `WALSync` | `active` | 1 | 0.404 |
| wallet | `IO` | `DataFileExtend` | `active` | 1 | 0.106 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 956.065 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 956.843 |
| match | `Client` | `ClientRead` | `idle` | 35 | 957.686 |
| order | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.093 |
| wallet | `Lock` | `extend` | `active` | 22 | 0.112 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 20 | 0.018 |
| match | `Client` | `ClientRead` | `idle in transaction` | 18 | 0.011 |
| wallet | `LWLock` | `BufferContent` | `active` | 13 | 0.003 |
| wallet | `none` | `none` | `active` | 9 | 0.890 |
| order | `none` | `none` | `active` | 7 | 8.421 |
| order | `none` | `none` | `idle` | 5 | 0.200 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.000 |
| match | `none` | `none` | `active` | 4 | 0.333 |
| wallet | `none` | `none` | `idle` | 4 | 0.127 |
| order | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| match | `none` | `none` | `idle` | 3 | 0.416 |
| match | `none` | `none` | `idle in transaction` | 3 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 2 | 4.497 |
| wallet | `LWLock` | `BufferContent` | `idle` | 2 | 0.099 |
| order | `none` | `none` | `idle in transaction` | 2 | 0.014 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 80.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 33.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 22.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 7.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 5.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.808862 |
| order | `system_cpu_usage` | 1.000000 | 0.801765 |
| match | `system_cpu_usage` | 0.988201 | 0.795387 |
| wallet | `process_cpu_usage` | 0.235644 | 0.025973 |
| order | `process_cpu_usage` | 0.210116 | 0.046914 |
| match | `process_cpu_usage` | 0.091592 | 0.023506 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 3709664 |
| used_memory_peak_bytes | 4735016 |
| instantaneous_ops_per_sec | 12330 |
| evicted_keys | 0 |
