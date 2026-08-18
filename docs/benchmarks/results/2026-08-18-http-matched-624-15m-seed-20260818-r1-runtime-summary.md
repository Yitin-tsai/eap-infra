# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260818_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260818_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-18T01:40:55Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `light` |
| intervalSeconds | 5 |
| samples | 107 |
| startedAt | `2026-08-18T01:23:46Z` |
| stoppedAt | `2026-08-18T01:40:35Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 2518 | 1168 | 1600 | 2518 |
| `wallet.orderSubmitted.queue` | 571 | 0 | 571 | 571 |
| `order.orderConfirmed.queue` | 265 | 0 | 265 | 265 |
| `order.tradeExecuted.queue` | 178 | 0 | 178 | 178 |
| `wallet.tradeExecuted.queue` | 162 | 0 | 162 | 162 |
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
| `rabbit@c2d709da6307` | 107 | 0 | 0 | 402141184 | 3328684851 | 447472308224 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 38 | 346796 | 0 | 898044 | 1189513 | 20 |
| order | 62 | 800619 | 0 | 3335158 | 1841071 | 488 |
| wallet | 46 | 915936 | 0 | 1498446 | 1798194 | 106 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 8940046 | 5081 | 843149358 | 0 | 69285 | 4643 | 0.000 | 0.000 |
| order | 18190159 | 37703 | 2721726427 | 0 | 165773 | 5264 | 0.000 | 0.000 |
| wallet | 9532268 | 13056 | 1028362754 | 0 | 79517 | 4517 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 31 | 1.572 |
| wallet | `LWLock` | `WALInsert` | `active` | 31 | 0.062 |
| order | `Lock` | `extend` | `active` | 30 | 0.091 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 24 | 0.110 |
| wallet | `Lock` | `extend` | `active` | 18 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `active` | 16 | 0.000 |
| wallet | `none` | `none` | `active` | 14 | 5.082 |
| order | `LWLock` | `BufferContent` | `active` | 13 | 1.581 |
| match | `Client` | `ClientRead` | `idle in transaction` | 13 | 0.019 |
| order | `none` | `none` | `active` | 12 | 20.518 |
| order | `IPC` | `XactGroupUpdate` | `active` | 11 | 0.000 |
| wallet | `LWLock` | `WALWrite` | `active` | 8 | 4.715 |
| order | `Client` | `ClientRead` | `active` | 8 | 0.000 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.034 |
| wallet | `Client` | `ClientRead` | `active` | 6 | 0.030 |
| match | `LWLock` | `BufferContent` | `active` | 6 | 0.000 |
| match | `none` | `none` | `active` | 4 | 0.394 |
| order | `LWLock` | `XidGen` | `active` | 4 | 0.002 |
| order | `IO` | `DataFileRead` | `active` | 3 | 13.777 |
| order | `none` | `none` | `idle in transaction` | 3 | 0.005 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 945.336 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 963.255 |
| match | `Client` | `ClientRead` | `idle` | 36 | 964.819 |
| order | `Client` | `ClientRead` | `idle in transaction` | 31 | 1.572 |
| wallet | `LWLock` | `WALInsert` | `active` | 31 | 0.062 |
| order | `Lock` | `extend` | `active` | 30 | 0.091 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 24 | 0.110 |
| wallet | `Lock` | `extend` | `active` | 18 | 0.000 |
| wallet | `LWLock` | `BufferContent` | `active` | 16 | 0.000 |
| wallet | `none` | `none` | `active` | 14 | 5.082 |
| order | `LWLock` | `BufferContent` | `active` | 13 | 1.581 |
| match | `Client` | `ClientRead` | `idle in transaction` | 13 | 0.019 |
| order | `none` | `none` | `active` | 12 | 20.518 |
| order | `IPC` | `XactGroupUpdate` | `active` | 11 | 0.000 |
| wallet | `LWLock` | `WALWrite` | `active` | 8 | 4.715 |
| order | `Client` | `ClientRead` | `active` | 8 | 0.000 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.034 |
| wallet | `Client` | `ClientRead` | `active` | 6 | 0.030 |
| match | `LWLock` | `BufferContent` | `active` | 6 | 0.000 |
| wallet | `none` | `none` | `idle` | 4 | 0.644 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 85.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 34.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 21.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 19.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 4.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| order | `process_cpu_usage` | 1.100000 | 0.054908 |
| wallet | `system_cpu_usage` | 1.000000 | 0.852748 |
| order | `system_cpu_usage` | 1.000000 | 0.875640 |
| match | `system_cpu_usage` | 0.999336 | 0.836051 |
| wallet | `process_cpu_usage` | 0.201491 | 0.027847 |
| match | `process_cpu_usage` | 0.083341 | 0.024125 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 19378496 |
| used_memory_peak_bytes | 21373192 |
| instantaneous_ops_per_sec | 18521 |
| evicted_keys | 0 |
