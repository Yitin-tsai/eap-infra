# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_POOL24_20260820_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_POOL24_20260820_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-20T02:14:45Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 32 |
| startedAt | `2026-08-20T02:07:46Z` |
| stoppedAt | `2026-08-20T02:14:35Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 11085 | 10235 | 900 | 11085 |
| `wallet.orderSubmitted.queue` | 641 | 1 | 640 | 641 |
| `wallet.tradeExecuted.queue` | 301 | 0 | 301 | 301 |
| `order.orderConfirmed.queue` | 276 | 0 | 276 | 276 |
| `order.tradeExecuted.queue` | 222 | 0 | 222 | 222 |
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
| `rabbit@c2d709da6307` | 32 | 0 | 0 | 388636672 | 3328684851 | 448940756992 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 37 | 137064 | 0 | 373669 | 487857 | 10 |
| order | 51 | 327345 | 0 | 1394498 | 773755 | 208 |
| wallet | 43 | 378723 | 0 | 623678 | 749046 | 44 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 3731626 | 4 | 342217082 | 0 | 26291 | 1861 | 0.000 | 0.000 |
| order | 7864404 | 35 | 1094765854 | 0 | 55908 | 2017 | 0.000 | 0.000 |
| wallet | 3990742 | 6 | 409751531 | 0 | 33196 | 1806 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.191 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 26 | 0.044 |
| wallet | `Lock` | `extend` | `active` | 25 | 0.085 |
| match | `Client` | `ClientRead` | `active` | 21 | 0.167 |
| order | `Lock` | `extend` | `active` | 17 | 0.161 |
| match | `Client` | `ClientRead` | `idle in transaction` | 11 | 0.139 |
| order | `none` | `none` | `active` | 9 | 0.578 |
| wallet | `LWLock` | `BufferContent` | `active` | 8 | 0.017 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.023 |
| match | `Lock` | `extend` | `active` | 5 | 0.050 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.022 |
| wallet | `none` | `none` | `active` | 4 | 1.432 |
| wallet | `LWLock` | `BufferContent` | `idle` | 4 | 0.196 |
| match | `none` | `none` | `active` | 4 | 0.063 |
| order | `Client` | `ClientRead` | `active` | 4 | 0.046 |
| wallet | `LWLock` | `WALInsert` | `idle` | 3 | 0.195 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.115 |
| order | `none` | `none` | `idle in transaction` | 2 | 0.110 |
| order | `LWLock` | `BufferContent` | `active` | 2 | 0.022 |
| match | `IO` | `BufFileWrite` | `active` | 1 | 0.973 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 47 | 107.509 |
| wallet | `Client` | `ClientRead` | `idle` | 41 | 19.775 |
| match | `Client` | `ClientRead` | `idle` | 35 | 58.695 |
| order | `Client` | `ClientRead` | `idle in transaction` | 27 | 0.191 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 26 | 0.044 |
| wallet | `Lock` | `extend` | `active` | 25 | 0.085 |
| match | `Client` | `ClientRead` | `active` | 21 | 0.167 |
| order | `Lock` | `extend` | `active` | 17 | 0.161 |
| match | `Client` | `ClientRead` | `idle in transaction` | 11 | 0.139 |
| wallet | `none` | `none` | `idle` | 10 | 0.244 |
| order | `none` | `none` | `active` | 9 | 0.578 |
| wallet | `LWLock` | `BufferContent` | `active` | 8 | 0.017 |
| order | `LWLock` | `WALInsert` | `active` | 7 | 0.023 |
| match | `Lock` | `extend` | `active` | 5 | 0.050 |
| wallet | `Client` | `ClientRead` | `active` | 5 | 0.022 |
| wallet | `none` | `none` | `active` | 4 | 1.432 |
| wallet | `LWLock` | `BufferContent` | `idle` | 4 | 0.196 |
| match | `none` | `none` | `active` | 4 | 0.063 |
| order | `Client` | `ClientRead` | `active` | 4 | 0.046 |
| order | `none` | `none` | `idle` | 3 | 0.434 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 170.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 34.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 24.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 24.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 24.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 24.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 24.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 22.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 6.000 |
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
| wallet | `system_cpu_usage` | 1.000000 | 0.932851 |
| order | `system_cpu_usage` | 0.999767 | 0.909288 |
| match | `system_cpu_usage` | 0.999668 | 0.872860 |
| order | `process_cpu_usage` | 0.206432 | 0.059173 |
| wallet | `process_cpu_usage` | 0.132529 | 0.032337 |
| match | `process_cpu_usage` | 0.059919 | 0.028179 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 27742032 |
| used_memory_peak_bytes | 58633088 |
| instantaneous_ops_per_sec | 20561 |
| evicted_keys | 0 |
