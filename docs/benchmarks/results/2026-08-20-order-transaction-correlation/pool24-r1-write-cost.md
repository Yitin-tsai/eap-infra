# Write Cost Summary

- diagnostics: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_POOL24_20260820_R1-diagnostics`
- result: `build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_POOL24_20260820_R1-result.json`
- generatedAt: 2026-08-20T02:15:22Z

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
| 1 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_total"` | 250817 | 39108.927 | 155.926 |
| 2 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_before_callback"` | 250817 | 33294.003 | 132.742 |
| 3 | order | `hikaricp_connections_acquire_seconds` | `pool="OrderCommandPool"` | 250819 | 33290.415 | 132.727 |
| 4 | wallet | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 380451 | 7718.639 | 20.288 |
| 5 | match | `match_engine_order_confirmed_listener_duration_seconds` | - | 250817 | 5985.259 | 23.863 |
| 6 | wallet | `eap_wallet_order_submitted_processing_duration_seconds` | - | 250817 | 5846.730 | 23.311 |
| 7 | wallet | `eap_wallet_order_submitted_transaction_duration_seconds` | - | 250817 | 5846.199 | 23.309 |
| 8 | order | `hikaricp_connections_usage_seconds` | `pool="OrderCommandPool"` | 250819 | 5813.385 | 23.178 |
| 9 | match | `match_engine_try_match_duration_seconds` | - | 250817 | 5001.897 | 19.942 |
| 10 | match | `match_engine_try_match_outcome_duration_seconds` | `outcome="fully_matched"` | 125398 | 3925.973 | 31.308 |
| 11 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_body"` | 250817 | 3746.446 | 14.937 |
| 12 | order | `eap_order_submission_append_duration_seconds` | `phase="initial_append_cte"` | 250817 | 3727.641 | 14.862 |
| 13 | wallet | `eap_wallet_order_submitted_transaction_body_duration_seconds` | - | 250817 | 3164.652 | 12.617 |
| 14 | wallet | `eap_wallet_order_submitted_reservation_cte_duration_seconds` | - | 250817 | 3155.456 | 12.581 |
| 15 | order | `hikaricp_connections_usage_seconds` | `pool="OrderConsumerPool"` | 76189 | 3018.915 | 39.624 |
| 16 | match | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 136635 | 2918.364 | 21.359 |
| 17 | match | `match_engine_trade_record_duration_seconds` | - | 125398 | 2845.786 | 22.694 |
| 18 | wallet | `eap_wallet_trade_settlement_processing_duration_seconds` | - | 125398 | 2816.000 | 22.456 |
| 19 | wallet | `eap_wallet_trade_settlement_transaction_duration_seconds` | - | 125398 | 2815.846 | 22.455 |
| 20 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_total"` | 125398 | 2812.070 | 22.425 |
| 21 | wallet | `eap_wallet_order_submitted_transaction_after_body_duration_seconds` | - | 250817 | 2161.845 | 8.619 |
| 22 | match | `match_engine_reserve_order_duration_seconds` | - | 250817 | 2155.187 | 8.593 |
| 23 | match | `match_engine_reserve_order_phase_duration_seconds` | `phase="redis_eval"` | 250817 | 2139.600 | 8.531 |
| 24 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_after_body"` | 250817 | 2068.213 | 8.246 |
| 25 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_body"` | 125398 | 2037.242 | 16.246 |

## PostgreSQL Executor Ranking

This is PostgreSQL executor time from pg_stat_statements. Gaps versus application timers usually point to JDBC, transaction, commit, broker confirm, scheduling, or client-side waits.

| Rank | Service | Calls | Total exec ms | Mean exec ms | Query prefix |
|---:|---|---:|---:|---:|---|
| 1 | order | 250817 | 1563104.76 | 6.2321 | `WITH inserted_head AS ( INSERT INTO order_service.order_stream_heads (aggregate_id, current_version, last_event_id, last_hash, user_id, rema` |
| 2 | wallet | 250817 | 857708.53 | 3.4197 | `WITH claimed AS ( INSERT INTO wallet_service.order_submission_idempotency(order_id, user_id, recorded_at) VALUES ($1, $2, CURRENT_TIMESTAMP)` |
| 3 | order | 24943 | 679288.37 | 27.2336 | `WITH input(event_id, aggregate_id, event_type, payload_canonical, metadata_canonical, schema_version, occurred_at, hash_material_prefix, cur` |
| 4 | wallet | 125398 | 258605.43 | 2.0623 | `WITH locked_wallets AS MATERIALIZED ( SELECT user_id FROM wallet_service.wallets WHERE user_id IN ($1, $2) ORDER BY user_id FOR UPDATE ), ex` |
| 5 | match | 125398 | 210550.53 | 1.6791 | `WITH inserted_trade AS ( INSERT INTO match_engine.trade_executions (trade_id, sequence, legacy_match_id, market_id, buyer_id, seller_id, buy` |
| 6 | match | 125398 | 121611.84 | 0.9698 | `INSERT INTO match_engine.reservation_cleanup_tasks (trade_id, order_id, user_id) VALUES ($1, $2, $3) ON CONFLICT (trade_id) DO NOTHING` |
| 7 | order | 20112 | 113858.13 | 5.6612 | `WITH input(trade_id, trade_buyer_order_id, trade_seller_order_id, trade_price, trade_quantity, trade_applied_at, buyer_order_id, buyer_quant` |
| 8 | wallet | 232 | 51133.31 | 220.4022 | `select count(oe1_0.id) from wallet_service.outbox oe1_0 where oe1_0.status=$1` |
| 9 | order | 11954 | 30014.37 | 2.5108 | `WITH trade_application AS ( INSERT INTO order_service.order_trade_applications (trade_id, buyer_order_id, seller_order_id, price, quantity, ` |
| 10 | order | 380 | 28053.79 | 73.8258 | `SELECT count(*) FROM order_service.order_trade_applications WHERE left(trade_id, $1) = $2` |
| 11 | order | 235 | 23517.45 | 100.0742 | `UPDATE order_service.order_event_outbox SET status = $502, published_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP, last_error = $5` |
| 12 | match | 378 | 23289.84 | 61.6133 | `SELECT count(*) FROM match_engine.trade_executions WHERE market_id = $1` |
| 13 | order | 14129 | 22755.99 | 1.6106 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_id IN ($1, $2) ORDER ` |
| 14 | match | 1660 | 21325.05 | 12.8464 | `WITH claimed AS ( SELECT id FROM match_engine.reservation_cleanup_tasks WHERE (status = 'PENDING' AND next_retry_at <= CURRENT_TIMESTAMP) OR` |
| 15 | order | 1482 | 21095.61 | 14.2346 | `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count FROM order_service.order_event_outbox WHERE status = '` |
| 16 | wallet | 379 | 18386.09 | 48.5121 | `SELECT count(*) FROM wallet_service.trade_settlements WHERE left(trade_id, $1) = $2` |
| 17 | order | 4688 | 18348.54 | 3.9139 | `INSERT INTO order_service.order_trade_execution_inbox AS inbox (trade_id, legacy_match_id, buyer_order_id, seller_order_id, deal_price, quan` |
| 18 | order | 10 | 18137.28 | 1813.7277 | `SELECT count(*) FILTER ( WHERE payload_canonical::jsonb ->> $3 = $4) AS buy_orders, count(*) FILTER ( WHERE payload_canonical::jsonb ->> $5 ` |
| 19 | order | 4385 | 16330.02 | 3.7241 | `INSERT INTO order_service.order_event_store (event_id, aggregate_id, aggregate_type, aggregate_version, event_type, payload_canonical, metad` |
| 20 | wallet | 229 | 11504.32 | 50.2372 | `UPDATE wallet_service.outbox SET status = $503, next_retry_at = $504, last_error = $505, updated_at = $1 WHERE id IN ($2, $3, $4, $5, $6, $7` |

## Match Trade Outbox Relay Breakdown

This isolates MatchEngine TradeExecuted relay costs. Batch-size rows are counts; duration rows are seconds.

| Metric | Count | Sum | Max | Mean |
|---|---:|---:|---:|---:|
| `match_engine_trade_outbox_batch_size` | 1371 | 125398.000000 | 500.000000 | 91.464624 |
| `match_engine_trade_outbox_confirmed_batch_size` | 1371 | 125398.000000 | 500.000000 | 91.464624 |
| `match_engine_trade_outbox_batch_duration_seconds` | 1371 | 240.788567 | 1.613573 | 0.175630 |
| `match_engine_trade_outbox_select_duration_seconds` | 1799 | 32.942578 | 0.213673 | 0.018312 |
| `match_engine_trade_outbox_publish_stage_duration_seconds` | 1371 | 6.989969 | 0.144459 | 0.005098 |
| `match_engine_trade_outbox_publish_enqueue_duration_seconds` | 125398 | 16.488212 | 0.109828 | 0.000131 |
| `match_engine_trade_outbox_message_build_duration_seconds` | 125398 | 1.695985 | 0.073570 | 0.000014 |
| `match_engine_trade_outbox_payload_rebuild_duration_seconds` | 125398 | 1.380731 | 0.073570 | 0.000011 |
| `match_engine_trade_outbox_confirm_wall_duration_seconds` | 1371 | 181.373570 | 1.455875 | 0.132293 |
| `match_engine_trade_outbox_confirm_duration_seconds` | 125398 | 181.310571 | 0.697001 | 0.001446 |
| `match_engine_trade_outbox_first_confirm_duration_seconds` | 1371 | 77.005627 | 0.697001 | 0.056167 |
| `match_engine_trade_outbox_remaining_confirm_duration_seconds` | 124027 | 104.304944 | 0.463595 | 0.000841 |
| `match_engine_trade_outbox_mark_sent_duration_seconds` | 1371 | 20.355102 | 0.181190 | 0.014847 |

## Integrated Stage Lag


- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-ORDER_TX_CORRELATION_700_POOL24_20260820_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-20T02:14:40Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 125398 | 309.206 | 1388.000 | 64478.200 | 85747.500 |
| Match persisted -> Wallet settlement inserted | 125398 | 283.701 | 1082.730 | 1818.900 | 2970.980 |
| Match persisted -> durable convergence | 125398 | 331.238 | 1555.220 | 64478.200 | 85747.500 |
| Order/Wallet durable skew | 125398 | 37.614 | 410.211 | 64005.300 | 85595.500 |

## Hikari Snapshot

| Service | Metric | Labels | Value |
|---|---|---|---:|
| match | `hikaricp_connections_active` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.0 |
| match | `hikaricp_connections_max` | `application="eap-matchEngine",pool="HikariPool-1"` | 35.0 |
| match | `hikaricp_connections_pending` | `application="eap-matchEngine",pool="HikariPool-1"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderCommandPool"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderConsumerPool"` | 0.0 |
| order | `hikaricp_connections_active` | `application="eap-order",pool="OrderProjectionPool"` | 0.0 |
| order | `hikaricp_connections_max` | `application="eap-order",pool="OrderCommandPool"` | 24.0 |
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
