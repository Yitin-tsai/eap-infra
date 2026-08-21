# Write Cost Summary

- diagnostics: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R1-diagnostics`
- result: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R1-result.json`
- generatedAt: 2026-08-20T01:14:40Z

## Business Result

| Metric | Value |
|---|---:|
| marketId | `ENERGY-SPOT` |
| completedTrades | n/a |
| businessOrderbookAdmissionTps | n/a |
| businessCompletedTradeTps | n/a |
| businessMarketFlowTps | n/a |
| businessMarketFlowOrders | n/a |
| businessMarketFlowSeconds | n/a |
| businessCompletionSeconds | n/a |
| matchEngineTradeExecutionReachTps | n/a |
| orderTradeApplicationReachTps | n/a |
| walletTradeSettlementReachTps | n/a |
| businessConvergenceReachTps | n/a |
| queueFullyDrainedSeconds | n/a |
| lastNonZeroQueue | `n/a` |
| lastNonZeroQueueSeconds | n/a |

## Application Timer Ranking

Cumulative seconds are sums across all observed events, so they show work/cost contribution rather than wall-clock elapsed time.

| Rank | Service | Timer | Labels | Count | Cumulative seconds | Mean ms |
|---:|---|---|---|---:|---:|---:|
| 1 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_total"` | 220241 | 62950.879 | 285.827 |
| 2 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_before_callback"` | 220241 | 50775.063 | 230.543 |
| 3 | order | `hikaricp_connections_acquire_seconds` | `pool="OrderCommandPool"` | 220243 | 50764.967 | 230.495 |
| 4 | wallet | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 333661 | 12716.876 | 38.113 |
| 5 | order | `hikaricp_connections_usage_seconds` | `pool="OrderCommandPool"` | 220243 | 12174.853 | 55.279 |
| 6 | match | `match_engine_order_confirmed_listener_duration_seconds` | - | 220405 | 10257.879 | 46.541 |
| 7 | wallet | `eap_wallet_order_submitted_processing_duration_seconds` | - | 220241 | 9642.766 | 43.783 |
| 8 | wallet | `eap_wallet_order_submitted_transaction_duration_seconds` | - | 220241 | 9641.843 | 43.779 |
| 9 | match | `match_engine_try_match_duration_seconds` | - | 220408 | 8513.249 | 38.625 |
| 10 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_body"` | 220241 | 7647.507 | 34.723 |
| 11 | order | `eap_order_submission_append_duration_seconds` | `phase="initial_append_cte"` | 220241 | 7610.511 | 34.555 |
| 12 | match | `match_engine_try_match_outcome_duration_seconds` | `outcome="fully_matched"` | 110088 | 6647.936 | 60.387 |
| 13 | wallet | `eap_wallet_order_submitted_transaction_body_duration_seconds` | - | 220241 | 5025.865 | 22.820 |
| 14 | wallet | `eap_wallet_order_submitted_reservation_cte_duration_seconds` | - | 220241 | 5010.339 | 22.749 |
| 15 | order | `hikaricp_connections_usage_seconds` | `pool="OrderConsumerPool"` | 60939 | 4946.069 | 81.164 |
| 16 | wallet | `eap_wallet_trade_settlement_processing_duration_seconds` | - | 110088 | 4883.861 | 44.363 |
| 17 | wallet | `eap_wallet_trade_settlement_transaction_duration_seconds` | - | 110088 | 4883.610 | 44.361 |
| 18 | match | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 118221 | 4864.803 | 41.150 |
| 19 | match | `match_engine_trade_record_duration_seconds` | - | 110088 | 4782.121 | 43.439 |
| 20 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_total"` | 110088 | 4731.563 | 42.980 |
| 21 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_after_body"` | 220241 | 4527.755 | 20.558 |
| 22 | match | `match_engine_reserve_order_duration_seconds` | - | 220408 | 3729.702 | 16.922 |
| 23 | match | `match_engine_reserve_order_phase_duration_seconds` | `phase="redis_eval"` | 220408 | 3707.769 | 16.822 |
| 24 | wallet | `eap_wallet_order_submitted_transaction_after_body_duration_seconds` | - | 220241 | 3585.533 | 16.280 |
| 25 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_body"` | 110088 | 3430.661 | 31.163 |

## PostgreSQL Executor Ranking

This is PostgreSQL executor time from pg_stat_statements. Gaps versus application timers usually point to JDBC, transaction, commit, broker confirm, scheduling, or client-side waits.

| Rank | Service | Calls | Total exec ms | Mean exec ms | Query prefix |
|---:|---|---:|---:|---:|---|
| 1 | order | 220241 | 3082644.15 | 13.9967 | `WITH inserted_head AS ( INSERT INTO order_service.order_stream_heads (aggregate_id, current_version, last_event_id, last_hash, user_id, rema` |
| 2 | wallet | 220241 | 1292061.15 | 5.8666 | `WITH claimed AS ( INSERT INTO wallet_service.order_submission_idempotency(order_id, user_id, recorded_at) VALUES ($1, $2, CURRENT_TIMESTAMP)` |
| 3 | order | 16665 | 913052.78 | 54.7886 | `WITH input(event_id, aggregate_id, event_type, payload_canonical, metadata_canonical, schema_version, occurred_at, hash_material_prefix, cur` |
| 4 | wallet | 110088 | 398428.11 | 3.6192 | `WITH locked_wallets AS MATERIALIZED ( SELECT user_id FROM wallet_service.wallets WHERE user_id IN ($1, $2) ORDER BY user_id FOR UPDATE ), ex` |
| 5 | match | 110088 | 308346.64 | 2.8009 | `WITH inserted_trade AS ( INSERT INTO match_engine.trade_executions (trade_id, sequence, legacy_match_id, market_id, buyer_id, seller_id, buy` |
| 6 | match | 110088 | 192787.01 | 1.7512 | `INSERT INTO match_engine.reservation_cleanup_tasks (trade_id, order_id, user_id) VALUES ($1, $2, $3) ON CONFLICT (trade_id) DO NOTHING` |
| 7 | order | 16431 | 158154.31 | 9.6254 | `WITH input(trade_id, trade_buyer_order_id, trade_seller_order_id, trade_price, trade_quantity, trade_applied_at, buyer_order_id, buyer_quant` |
| 8 | order | 934 | 85106.20 | 91.1201 | `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count FROM order_service.order_event_outbox WHERE status = '` |
| 9 | wallet | 290 | 56473.88 | 194.7375 | `select count(oe1_0.id) from wallet_service.outbox oe1_0 where oe1_0.status=$1` |
| 10 | order | 6625 | 41860.25 | 6.3185 | `INSERT INTO order_service.order_event_store (event_id, aggregate_id, aggregate_type, aggregate_version, event_type, payload_canonical, metad` |
| 11 | order | 11983 | 39133.55 | 3.2658 | `WITH trade_application AS ( INSERT INTO order_service.order_trade_applications (trade_id, buyer_order_id, seller_order_id, price, quantity, ` |
| 12 | order | 438 | 35827.21 | 81.7973 | `UPDATE order_service.order_event_outbox SET status = $502, published_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, last_error = $5` |
| 13 | wallet | 940 | 34041.48 | 36.2143 | `SELECT id, event_type, routing_key, payload, attempt_count FROM wallet_service.outbox WHERE status = 'PENDING' AND next_retry_at <= CURRENT_` |
| 14 | order | 110 | 33900.57 | 308.1870 | `SELECT count(*) FROM order_service.order_event_store WHERE event_type = $1` |
| 15 | order | 13030 | 26165.01 | 2.0081 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_id IN ($1, $2) ORDER ` |
| 16 | match | 420 | 25650.57 | 61.0728 | `SELECT count(*) FROM match_engine.trade_executions WHERE market_id = $1` |
| 17 | order | 422 | 24878.58 | 58.9540 | `SELECT count(*) FROM order_service.order_trade_applications WHERE left(trade_id, $1) = $2` |
| 18 | order | 10 | 24126.78 | 2412.6775 | `SELECT count(*) FILTER ( WHERE payload_canonical::jsonb ->> $3 = $4) AS buy_orders, count(*) FILTER ( WHERE payload_canonical::jsonb ->> $5 ` |
| 19 | wallet | 423 | 22695.70 | 53.6541 | `UPDATE wallet_service.outbox SET status = $503, next_retry_at = $504, last_error = $505, updated_at = $1 WHERE id IN ($2, $3, $4, $5, $6, $7` |
| 20 | order | 13275 | 18313.80 | 1.3796 | `INSERT INTO order_service.orders_current (order_id, user_id, market_id, market_sequence, side, price, original_amount, remaining_amount, mat` |

## Match Trade Outbox Relay Breakdown

This isolates MatchEngine TradeExecuted relay costs. Batch-size rows are counts; duration rows are seconds.

| Metric | Count | Sum | Max | Mean |
|---|---:|---:|---:|---:|
| `match_engine_trade_outbox_batch_size` | 746 | 110088.000000 | 500.000000 | 147.571046 |
| `match_engine_trade_outbox_confirmed_batch_size` | 746 | 110088.000000 | 500.000000 | 147.571046 |
| `match_engine_trade_outbox_batch_duration_seconds` | 746 | 369.734779 | 1.415925 | 0.495623 |
| `match_engine_trade_outbox_select_duration_seconds` | 1456 | 54.284233 | 0.498505 | 0.037283 |
| `match_engine_trade_outbox_publish_stage_duration_seconds` | 746 | 12.553090 | 0.115641 | 0.016827 |
| `match_engine_trade_outbox_publish_enqueue_duration_seconds` | 110088 | 26.922598 | 0.045357 | 0.000245 |
| `match_engine_trade_outbox_message_build_duration_seconds` | 110088 | 2.476709 | 0.036870 | 0.000022 |
| `match_engine_trade_outbox_payload_rebuild_duration_seconds` | 110088 | 1.965235 | 0.036869 | 0.000018 |
| `match_engine_trade_outbox_confirm_wall_duration_seconds` | 746 | 272.110077 | 1.246044 | 0.364759 |
| `match_engine_trade_outbox_confirm_duration_seconds` | 110088 | 272.027735 | 0.610811 | 0.002471 |
| `match_engine_trade_outbox_first_confirm_duration_seconds` | 746 | 111.054499 | 0.610811 | 0.148867 |
| `match_engine_trade_outbox_remaining_confirm_duration_seconds` | 109342 | 160.973236 | 0.498717 | 0.001472 |
| `match_engine_trade_outbox_mark_sent_duration_seconds` | 746 | 30.838431 | 0.167654 | 0.041338 |

## Integrated Stage Lag


- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-20T01:14:21Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 110088 | 609.798 | 2111.150 | 4571.390 | 36361.300 |
| Match persisted -> Wallet settlement inserted | 110088 | 592.587 | 2122.150 | 3621.080 | 5655.990 |
| Match persisted -> durable convergence | 110088 | 660.017 | 2514.160 | 5281.290 | 36361.300 |
| Order/Wallet durable skew | 110088 | 69.971 | 734.862 | 3717.830 | 34504.600 |

## Hikari Snapshot

| Service | Metric | Labels | Value |
|---|---|---|---:|
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.0 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.0 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.0 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 35.0 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderConsumerPool"` | 20.0 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderProjectionPool"` | 3.0 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderCommandPool"` | 0.0 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderConsumerPool"` | 0.0 |
| order | `hikaricp_connections_pending` | `application="eap-order",pool="OrderProjectionPool"` | 0.0 |
| wallet | `hikaricp_connections_active` | `application="eap-wallet",pool="HikariPool-1"` | 0.0 |
| wallet | `hikaricp_connections_max` | `application="eap-wallet",pool="HikariPool-1"` | 40.0 |
| wallet | `hikaricp_connections_pending` | `application="eap-wallet",pool="HikariPool-1"` | 0.0 |

## Reading Notes

- Treat app timer ranking as the matched-trade-completion-chain bottleneck view.
- Treat pg_stat ranking as DB executor cost only; it does not include broker confirm, queue drain, or most client-side transaction gaps.
- `*_publish_duration_seconds` is intentionally excluded because current relay instrumentation can overcount batch lifetime; use enqueue, confirm, select, mark-sent, and batch timers instead.
