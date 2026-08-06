# Runtime Hot Window Summary

- diagnostics: `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R1-diagnostics`
- samples: `build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R1-diagnostics/runtime-samples.log`
- generatedAt: 2026-08-05T05:35:39Z

## Sampler Metadata

| Field | Value |
|---|---:|
| diagnosticsLevel | `deep` |
| intervalSeconds | 5 |
| samples | 25 |
| startedAt | `2026-08-05T05:31:32Z` |
| stoppedAt | `2026-08-05T05:35:20Z` |

## RabbitMQ Backlog Peaks

| Queue | Max messages | Max ready | Max unacked | Max backlog |
|---|---:|---:|---:|---:|
| `matchEngine.orderConfirmed.queue` | 3359 | 2659 | 888 | 3359 |
| `order.tradeExecuted.queue` | 774 | 174 | 600 | 774 |
| `order.orderConfirmed.queue` | 569 | 0 | 569 | 569 |
| `wallet.tradeExecuted.queue` | 378 | 158 | 267 | 378 |
| `wallet.orderSubmitted.queue` | 378 | 0 | 378 | 378 |
| `wallet.auctionCleared.queue` | 0 | 0 | 0 | 0 |
| `wallet.auctionBidSubmitted.queue` | 0 | 0 | 0 | 0 |
| `order.orderFailed.queue` | 0 | 0 | 0 | 0 |
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
| match | 35 | 107581 | 0 | 298722 | 389671 | 7 |
| order | 60 | 235221 | 0 | 1105748 | 606005 | 100 |
| wallet | 45 | 304311 | 0 | 499318 | 599032 | 20 |

## PostgreSQL WAL Delta

Each service uses a separate PostgreSQL container, so cluster-wide pg_stat_wal deltas are service-specific here.

| Service | WAL records | WAL FPI | WAL bytes | Buffers full | Writes | Syncs | Write time ms | Sync time ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| match | 2961282 | 38 | 271495408 | 0 | 21210 | 1009 | 0.000 | 0.000 |
| order | 6008728 | 73 | 831315094 | 0 | 47546 | 1122 | 0.000 | 0.000 |
| wallet | 2971679 | 30 | 307321245 | 0 | 26498 | 1011 | 0.000 | 0.000 |

## PostgreSQL Actionable Wait Peaks

Idle ClientRead sessions are filtered out here so active, lock, IO, WAL, and timeout waits are easier to spot.

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle in transaction` | 28 | 0.010 |
| order | `Lock` | `extend` | `active` | 20 | 0.249 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 15 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.001 |
| order | `none` | `none` | `active` | 7 | 0.249 |
| match | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| wallet | `none` | `none` | `active` | 3 | 0.084 |
| match | `none` | `none` | `active` | 3 | 0.012 |
| wallet | `Client` | `ClientRead` | `active` | 3 | 0.000 |
| wallet | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| match | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| wallet | `Timeout` | `VacuumDelay` | `active` | 1 | 0.467 |
| match | `IO` | `BufFileWrite` | `active` | 1 | 0.072 |
| wallet | `Lock` | `transactionid` | `active` | 1 | 0.000 |
| order | `none` | `none` | `idle in transaction` | 1 | 0.000 |
| order | `LWLock` | `WALInsert` | `active` | 1 | 0.000 |

## PostgreSQL All Wait Peaks

| Service | Wait type | Wait event | State | Max sessions | Max age seconds |
|---|---|---|---|---:|---:|
| order | `Client` | `ClientRead` | `idle` | 59 | 203.355 |
| wallet | `Client` | `ClientRead` | `idle` | 42 | 203.871 |
| match | `Client` | `ClientRead` | `idle` | 33 | 204.596 |
| order | `Client` | `ClientRead` | `idle in transaction` | 28 | 0.010 |
| order | `Lock` | `extend` | `active` | 20 | 0.249 |
| wallet | `Client` | `ClientRead` | `idle in transaction` | 15 | 0.000 |
| match | `Client` | `ClientRead` | `idle in transaction` | 14 | 0.001 |
| order | `none` | `none` | `active` | 7 | 0.249 |
| wallet | `none` | `none` | `idle` | 4 | 0.127 |
| match | `Client` | `ClientRead` | `active` | 4 | 0.000 |
| wallet | `none` | `none` | `active` | 3 | 0.084 |
| match | `none` | `none` | `active` | 3 | 0.012 |
| wallet | `Client` | `ClientRead` | `active` | 3 | 0.000 |
| match | `none` | `none` | `idle` | 2 | 0.107 |
| order | `none` | `none` | `idle` | 2 | 0.053 |
| wallet | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| order | `Client` | `ClientRead` | `active` | 2 | 0.000 |
| match | `none` | `none` | `idle in transaction` | 2 | 0.000 |
| match | `LWLock` | `BufferContent` | `active` | 2 | 0.000 |
| wallet | `Timeout` | `VacuumDelay` | `active` | 1 | 0.467 |

## Hikari Gauge Peaks

| Service | Gauge | Labels | Max observed |
|---|---|---|---:|
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 85.000 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| wallet | `hikaricp_connections_idle` | `application="eap-wallet",pool="HikariPool-1"` | 40.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 35.000 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.000 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 33.000 |
| match | `hikaricp_connections_idle` | `application="eap-matchEngine",pool="HikariPool-1"` | 32.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderConsumerPool"` | 20.000 |
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 20.000 |
| wallet | `hikaricp_connections_min` | `application="eap-wallet",pool="HikariPool-1"` | 12.000 |
| match | `hikaricp_connections_min` | `application="eap-matchEngine",pool="HikariPool-1"` | 10.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 8.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderConsumerPool"` | 5.000 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.000 |
| order | `hikaricp_connections_idle` | `application="eap-order",pool="OrderProjectionPool"` | 2.000 |
| order | `hikaricp_connections_min` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 1.000 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.000 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.000 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.000 |

## JVM CPU Gauges

| Service | Gauge | Max observed | Average observed |
|---|---|---:|---:|
| wallet | `system_cpu_usage` | 1.000000 | 0.897368 |
| order | `system_cpu_usage` | 1.000000 | 0.902746 |
| match | `system_cpu_usage` | 0.996771 | 0.860521 |
| order | `process_cpu_usage` | 0.089968 | 0.070308 |
| wallet | `process_cpu_usage` | 0.049869 | 0.031111 |
| match | `process_cpu_usage` | 0.049673 | 0.037854 |

## Redis Peaks

| Metric | Max observed |
|---|---:|
| used_memory_bytes | 10279872 |
| used_memory_peak_bytes | 97877224 |
| instantaneous_ops_per_sec | 13588 |
| evicted_keys | 0 |
