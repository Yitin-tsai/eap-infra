# Runtime Hot Window Summary

- diagnostics: `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_BITMAP_MIXED_900_USERS500_DEEP_R2-diagnostics`
- samples: `build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_BITMAP_MIXED_900_USERS500_DEEP_R2-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-06T07:54:41Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 7 |
| startedAt | `2026-08-06T07:53:35Z` |
| stoppedAt | `2026-08-06T07:54:25Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `order.tradeExecuted.queue` | 88 | 0 | 88 | 88 |
| `wallet.tradeExecuted.queue` | 83 | 0 | 83 | 83 |
| `matchEngine.orderConfirmed.queue` | 59 | 0 | 59 | 59 |
| `wallet.orderSubmitted.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionBidSubmitted.queue` | 0 | 0 | 0 | 0 |
| `order.orderFailed.queue` | 0 | 0 | 0 | 0 |
| `order.orderConfirmed.queue` | 0 | 0 | 0 | 0 |
| `order.dlq` | 0 | 0 | 0 | 0 |
| `order.auctionCreated.queue` | 0 | 0 | 0 | 0 |
| `order.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.walletTradeSettled.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.orderTradeApplied.queue` | 0 | 0 | 0 | 0 |
| `matchEngine.auctionBidConfirmed.queue` | 0 | 0 | 0 | 0 |

## PostgreSQL Activity Delta

Deltas are derived from the first and last observed sampler values in this diagnostics window.

| Service | Max backends | Commit delta | Rollback delta | Insert delta | Update delta | Delete delta |
|---|---:|---:|---:|---:|---:|---:|
| match | 20 | 18191 | 0 | 46671 | 62752 | 3 |
| order | 59 | 39186 | 0 | 173801 | 95334 | 0 |
| wallet | 43 | 49491 | 0 | 78839 | 94536 | 6 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 455318 | 63 | 40655347 | 0 | 3965 | 175 | 0.000 | 0.000 |
| order | 885745 | 54 | 122469232 | 0 | 9031 | 190 | 0.000 | 0.000 |
| wallet | 501014 | 28 | 48225405 | 0 | 4562 | 182 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| wallet | `Client` | `ClientRead` | `idle in transaction` | 16 | 0.003 |
| order | `Client` | `ClientRead` | `idle in transaction` | 6 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| order | `none` | `none` | `active` | 2 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 58 | 29.497 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 31.315 |
| match | `Client` | `ClientRead` | `idle` | 19 | 33.594 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 16 | 0.003 |
| order | `Client` | `ClientRead` | `idle in transaction` | 6 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 4 | 0.000 |
| wallet | `none` | `none` | `idle` | 3 | 0.000 |
| wallet | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| order | `none` | `none` | `active` | 2 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `none` | `none` | `idle` | 1 | 0.088 |
| match | `none` | `none` | `idle` | 1 | 0.009 |
| wallet | `none` | `none` | `active` | 1 | 0.000 |
| match | `none` | `none` | `active` | 1 | 0.000 |
| match | `Client` | `ClientRead` | `active` | 1 | 0.000 |

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
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 18.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 9.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 7.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 3.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.715135 |
| order | `system_cpu_usage` | 0.979310 | 0.782408 |
| match | `system_cpu_usage` | 0.954322 | 0.669385 |
| order | `process_cpu_usage` | 0.083110 | 0.051531 |
| wallet | `process_cpu_usage` | 0.069226 | 0.032545 |
| match | `process_cpu_usage` | 0.061537 | 0.031502 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 2870024 |
| used_memory_peak_bytes | 254759296 |
| instantaneous_ops_per_sec | 12964 |
| evicted_keys | 0 |
