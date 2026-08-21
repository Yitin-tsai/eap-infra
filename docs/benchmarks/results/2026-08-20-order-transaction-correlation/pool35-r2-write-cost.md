# Write Cost Summary

- diagnostics: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R2-diagnostics`
- result: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R2-result.json`
- generatedAt: 2026-08-20T01:26:12Z

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
| 1 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_total"` | 252000 | 20993.042 | 83.306 |
| 2 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_before_callback"` | 252000 | 15316.978 | 60.782 |
| 3 | order | `hikaricp_connections_acquire_seconds` | `pool="OrderCommandPool"` | 252002 | 15313.284 | 60.767 |
| 4 | wallet | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 383131 | 6569.933 | 17.148 |
| 5 | order | `hikaricp_connections_usage_seconds` | `pool="OrderCommandPool"` | 252002 | 5681.558 | 22.546 |
| 6 | match | `match_engine_order_confirmed_listener_duration_seconds` | - | 252038 | 5426.236 | 21.529 |
| 7 | wallet | `eap_wallet_order_submitted_processing_duration_seconds` | - | 252148 | 5036.855 | 19.976 |
| 8 | wallet | `eap_wallet_order_submitted_transaction_duration_seconds` | - | 252148 | 5036.361 | 19.974 |
| 9 | match | `match_engine_try_match_duration_seconds` | - | 252038 | 4510.940 | 17.898 |
| 10 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_body"` | 252000 | 3557.669 | 14.118 |
| 11 | order | `eap_order_submission_append_duration_seconds` | `phase="initial_append_cte"` | 252000 | 3541.896 | 14.055 |
| 12 | match | `match_engine_try_match_outcome_duration_seconds` | `outcome="fully_matched"` | 126000 | 3509.214 | 27.851 |
| 13 | wallet | `eap_wallet_order_submitted_transaction_body_duration_seconds` | - | 252148 | 2637.925 | 10.462 |
| 14 | wallet | `eap_wallet_order_submitted_reservation_cte_duration_seconds` | - | 252148 | 2631.065 | 10.435 |
| 15 | match | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 141170 | 2562.302 | 18.150 |
| 16 | wallet | `eap_wallet_trade_settlement_processing_duration_seconds` | - | 126000 | 2501.187 | 19.851 |
| 17 | wallet | `eap_wallet_trade_settlement_transaction_duration_seconds` | - | 126000 | 2501.041 | 19.850 |
| 18 | match | `match_engine_trade_record_duration_seconds` | - | 126000 | 2498.555 | 19.830 |
| 19 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_total"` | 126000 | 2467.810 | 19.586 |
| 20 | order | `hikaricp_connections_usage_seconds` | `pool="OrderConsumerPool"` | 70912 | 2208.317 | 31.142 |
| 21 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_after_body"` | 252000 | 2118.196 | 8.406 |
| 22 | match | `match_engine_reserve_order_duration_seconds` | - | 252038 | 2011.486 | 7.981 |
| 23 | match | `match_engine_reserve_order_phase_duration_seconds` | `phase="redis_eval"` | 252038 | 1999.329 | 7.933 |
| 24 | wallet | `eap_wallet_order_submitted_transaction_after_body_duration_seconds` | - | 252148 | 1870.067 | 7.417 |
| 25 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_body"` | 126000 | 1763.995 | 14.000 |

## PostgreSQL Executor Ranking

This is PostgreSQL executor time from pg_stat_statements. Gaps versus application timers usually point to JDBC, transaction, commit, broker confirm, scheduling, or client-side waits.

| Rank | Service | Calls | Total exec ms | Mean exec ms | Query prefix |
|---:|---|---:|---:|---:|---|
| 1 | order | 252000 | 1296063.58 | 5.1431 | `WITH inserted_head AS ( INSERT INTO order_service.order_stream_heads (aggregate_id, current_version, last_event_id, last_hash, user_id, rema` |
| 2 | wallet | 252148 | 597277.32 | 2.3688 | `WITH claimed AS ( INSERT INTO wallet_service.order_submission_idempotency(order_id, user_id, recorded_at) VALUES ($1, $2, CURRENT_TIMESTAMP)` |
| 3 | order | 29061 | 395953.55 | 13.6249 | `WITH input(event_id, aggregate_id, event_type, payload_canonical, metadata_canonical, schema_version, occurred_at, hash_material_prefix, cur` |
| 4 | wallet | 126000 | 164699.46 | 1.3071 | `WITH locked_wallets AS MATERIALIZED ( SELECT user_id FROM wallet_service.wallets WHERE user_id IN ($1, $2) ORDER BY user_id FOR UPDATE ), ex` |
| 5 | match | 126000 | 129168.28 | 1.0251 | `WITH inserted_trade AS ( INSERT INTO match_engine.trade_executions (trade_id, sequence, legacy_match_id, market_id, buyer_id, seller_id, buy` |
| 6 | match | 126000 | 80024.43 | 0.6351 | `INSERT INTO match_engine.reservation_cleanup_tasks (trade_id, order_id, user_id) VALUES ($1, $2, $3) ON CONFLICT (trade_id) DO NOTHING` |
| 7 | order | 23179 | 60870.56 | 2.6261 | `WITH input(trade_id, trade_buyer_order_id, trade_seller_order_id, trade_price, trade_quantity, trade_applied_at, buyer_order_id, buyer_quant` |
| 8 | order | 378 | 27759.88 | 73.4388 | `SELECT count(*) FROM order_service.order_trade_applications WHERE left(trade_id, $1) = $2` |
| 9 | wallet | 240 | 27586.07 | 114.9419 | `select count(oe1_0.id) from wallet_service.outbox oe1_0 where oe1_0.status=$1` |
| 10 | match | 376 | 22897.52 | 60.8977 | `SELECT count(*) FROM match_engine.trade_executions WHERE market_id = $1` |
| 11 | match | 3948 | 17803.71 | 4.5096 | `WITH claimed AS ( SELECT id FROM match_engine.reservation_cleanup_tasks WHERE (status = 'PENDING' AND next_retry_at <= CURRENT_TIMESTAMP) OR` |
| 12 | wallet | 377 | 16052.34 | 42.5792 | `SELECT count(*) FROM wallet_service.trade_settlements WHERE left(trade_id, $1) = $2` |
| 13 | order | 221 | 15964.01 | 72.2353 | `UPDATE order_service.order_event_outbox SET status = $502, published_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, last_error = $5` |
| 14 | wallet | 1818 | 15805.92 | 8.6941 | `SELECT id, event_type, routing_key, payload, attempt_count FROM wallet_service.outbox WHERE status = 'PENDING' AND next_retry_at <= CURRENT_` |
| 15 | order | 10 | 14637.43 | 1463.7434 | `SELECT count(*) FILTER ( WHERE payload_canonical::jsonb ->> $3 = $4) AS buy_orders, count(*) FILTER ( WHERE payload_canonical::jsonb ->> $5 ` |
| 16 | order | 5652 | 12971.92 | 2.2951 | `WITH trade_application AS ( INSERT INTO order_service.order_trade_applications (trade_id, buyer_order_id, seller_order_id, price, quantity, ` |
| 17 | order | 3991 | 11166.32 | 2.7979 | `INSERT INTO order_service.order_event_store (event_id, aggregate_id, aggregate_type, aggregate_version, event_type, payload_canonical, metad` |
| 18 | order | 1906 | 10275.00 | 5.3909 | `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count FROM order_service.order_event_outbox WHERE status = '` |
| 19 | wallet | 234 | 9952.19 | 42.5307 | `UPDATE wallet_service.outbox SET status = $503, next_retry_at = $504, last_error = $505, updated_at = $1 WHERE id IN ($2, $3, $4, $5, $6, $7` |
| 20 | order | 6120 | 9828.64 | 1.6060 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_id IN ($1, $2) ORDER ` |

## Match Trade Outbox Relay Breakdown

This isolates MatchEngine TradeExecuted relay costs. Batch-size rows are counts; duration rows are seconds.

| Metric | Count | Sum | Max | Mean |
|---|---:|---:|---:|---:|
| `match_engine_trade_outbox_batch_size` | 1678 | 126000.000000 | 500.000000 | 75.089392 |
| `match_engine_trade_outbox_confirmed_batch_size` | 1678 | 126000.000000 | 500.000000 | 75.089392 |
| `match_engine_trade_outbox_batch_duration_seconds` | 1678 | 196.336666 | 1.883351 | 0.117006 |
| `match_engine_trade_outbox_select_duration_seconds` | 2107 | 30.691076 | 0.321758 | 0.014566 |
| `match_engine_trade_outbox_publish_stage_duration_seconds` | 1678 | 6.330574 | 0.135860 | 0.003773 |
| `match_engine_trade_outbox_publish_enqueue_duration_seconds` | 126000 | 16.087006 | 0.084598 | 0.000128 |
| `match_engine_trade_outbox_message_build_duration_seconds` | 126000 | 1.369369 | 0.082953 | 0.000011 |
| `match_engine_trade_outbox_payload_rebuild_duration_seconds` | 126000 | 1.042664 | 0.025204 | 0.000008 |
| `match_engine_trade_outbox_confirm_wall_duration_seconds` | 1678 | 147.330343 | 1.523792 | 0.087801 |
| `match_engine_trade_outbox_confirm_duration_seconds` | 126000 | 147.276691 | 0.672674 | 0.001169 |
| `match_engine_trade_outbox_first_confirm_duration_seconds` | 1678 | 63.032352 | 0.672674 | 0.037564 |
| `match_engine_trade_outbox_remaining_confirm_duration_seconds` | 124322 | 84.244339 | 0.412813 | 0.000678 |
| `match_engine_trade_outbox_mark_sent_duration_seconds` | 1678 | 14.951269 | 0.316957 | 0.008910 |

## Integrated Stage Lag


- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_20260820_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-20T01:25:58Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 126000 | 235.460 | 1062.370 | 1632.850 | 9601.310 |
| Match persisted -> Wallet settlement inserted | 126000 | 213.267 | 1041.890 | 1555.690 | 9498.410 |
| Match persisted -> durable convergence | 126000 | 253.791 | 1128.730 | 1707.630 | 9601.310 |
| Order/Wallet durable skew | 126000 | 32.973 | 216.167 | 528.119 | 8536.110 |

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
