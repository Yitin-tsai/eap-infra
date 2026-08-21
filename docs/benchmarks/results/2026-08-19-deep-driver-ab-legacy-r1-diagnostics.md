# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R1-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-19T08:43:15Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 7 |
| startedAt | `2026-08-19T08:42:19Z` |
| stoppedAt | `2026-08-19T08:43:11Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `order.orderConfirmed.queue` | 74 | 0 | 74 | 74 |
| `order.tradeExecuted.queue` | 44 | 0 | 44 | 44 |
| `matchEngine.orderConfirmed.queue` | 23 | 0 | 23 | 23 |
| `wallet.tradeExecuted.queue` | 8 | 0 | 8 | 8 |
| `wallet.orderSubmitted.queue` | 1 | 0 | 1 | 1 |
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
| `rabbit@c2d709da6307` | 7 | 0 | 0 | 288550912 | 3328684851 | 452402143232 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 19 | 14958 | 0 | 37026 | 49359 | 3 |
| order | 59 | 33229 | 0 | 134196 | 73698 | 33 |
| wallet | 43 | 39201 | 0 | 61648 | 72641 | 7 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 362857 | 59 | 32471962 | 0 | 3170 | 181 | 0.000 | 0.000 |
| order | 698139 | 105 | 95857207 | 0 | 7508 | 199 | 0.000 | 0.000 |
| wallet | 386487 | 47 | 37298749 | 0 | 3381 | 186 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| match | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 2 | 0.000 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `none` | `none` | `active` | 1 | 0.000 |
| order | `Lock` | `extend` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 37.365 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 37.786 |
| match | `Client` | `ClientRead` | `idle` | 18 | 38.250 |
| match | `Client` | `ClientRead` | `idle in transaction` | 7 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 2 | 0.000 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `none` | `none` | `active` | 1 | 0.000 |
| order | `Lock` | `extend` | `active` | 1 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 27.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 20.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 17.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 16.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| order | `system_cpu_usage` | 1.000000 | 0.757437 |
| wallet | `system_cpu_usage` | 0.976326 | 0.724515 |
| match | `system_cpu_usage` | 0.972352 | 0.652920 |
| order | `process_cpu_usage` | 0.143124 | 0.071778 |
| wallet | `process_cpu_usage` | 0.120485 | 0.046426 |
| match | `process_cpu_usage` | 0.108696 | 0.039139 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 2485736 |
| used_memory_peak_bytes | 2959240 |
| instantaneous_ops_per_sec | 9477 |
| evicted_keys | 0 |
