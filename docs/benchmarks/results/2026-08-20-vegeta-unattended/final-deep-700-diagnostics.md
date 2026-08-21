# Runtime Hot Window Summary

- diagnostics: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-VEGETA_UNATTENDED_20260819_R1_FINAL_DEEP_700_SEED_20260899-diagnostics`
- samples: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-VEGETA_UNATTENDED_20260819_R1_FINAL_DEEP_700_SEED_20260899-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-19T20:05:20Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 15 |
| samples | 56 |
| startedAt | `2026-08-19T19:48:32Z` |
| stoppedAt | `2026-08-19T20:04:58Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 101 | 0 | 101 | 101 |
| `order.orderConfirmed.queue` | 100 | 0 | 100 | 100 |
| `order.tradeExecuted.queue` | 88 | 0 | 88 | 88 |
| `wallet.orderSubmitted.queue` | 78 | 0 | 78 | 78 |
| `wallet.tradeExecuted.queue` | 45 | 0 | 45 | 45 |
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
| `rabbit@c2d709da6307` | 56 | 0 | 0 | 352649216 | 3328684851 | 443619663872 | 50000000 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 37 | 404612 | 0 | 1006069 | 1343529 | 18 |
| order | 61 | 914286 | 0 | 3741244 | 2064194 | 510 |
| wallet | 43 | 1026801 | 0 | 1678068 | 2014210 | 98 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 9960527 | 3813 | 914423326 | 0 | 81919 | 4511 | 0.000 | 0.000 |
| order | 19853577 | 13333 | 2776226783 | 0 | 237425 | 6196 | 0.000 | 0.000 |
| wallet | 10594848 | 8845 | 1077662055 | 0 | 92089 | 4383 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| match | `Client` | `ClientRead` | `idle in transaction` | 17 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 11 | 0.008 |
| order | `Client` | `ClientRead` | `active` | 11 | 0.000 |
| order | `none` | `none` | `active` | 10 | 7.662 |
| order | `LWLock` | `BufferContent` | `active` | 9 | 0.000 |
| match | `none` | `none` | `active` | 4 | 0.953 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 4 | 0.000 |
| order | `LWLock` | `BufferContent` | `idle` | 4 | 0.000 |
| wallet | `none` | `none` | `active` | 2 | 0.513 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 1 | 4.545 |
| order | `Timeout` | `VacuumDelay` | `active` | 1 | 2.064 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `IO` | `DataFileExtend` | `idle` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 108.546 |
| wallet | `Client` | `ClientRead` | `idle` | 41 | 11.346 |
| match | `Client` | `ClientRead` | `idle` | 34 | 96.544 |
| match | `Client` | `ClientRead` | `idle in transaction` | 17 | 0.000 |
| order | `Client` | `ClientRead` | `idle in transaction` | 11 | 0.008 |
| order | `Client` | `ClientRead` | `active` | 11 | 0.000 |
| order | `none` | `none` | `active` | 10 | 7.662 |
| order | `LWLock` | `BufferContent` | `active` | 9 | 0.000 |
| match | `none` | `none` | `active` | 4 | 0.953 |
| wallet | `none` | `none` | `idle` | 4 | 0.106 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 4 | 0.000 |
| order | `LWLock` | `BufferContent` | `idle` | 4 | 0.000 |
| order | `none` | `none` | `idle` | 3 | 0.225 |
| wallet | `none` | `none` | `active` | 2 | 0.513 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `IO` | `DataFileRead` | `active` | 1 | 4.545 |
| order | `Timeout` | `VacuumDelay` | `active` | 1 | 2.064 |
| match | `none` | `none` | `idle` | 1 | 0.973 |
| wallet | `none` | `none` | `idle in transaction` | 1 | 0.000 |

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
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 33.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 20.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 16.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 6.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.734845 |
| order | `system_cpu_usage` | 1.000000 | 0.771032 |
| match | `system_cpu_usage` | 0.873466 | 0.653334 |
| wallet | `process_cpu_usage` | 0.219270 | 0.027954 |
| order | `process_cpu_usage` | 0.145882 | 0.044612 |
| match | `process_cpu_usage` | 0.060663 | 0.020669 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 3534552 |
| used_memory_peak_bytes | 55802936 |
| instantaneous_ops_per_sec | 13225 |
| evicted_keys | 0 |
