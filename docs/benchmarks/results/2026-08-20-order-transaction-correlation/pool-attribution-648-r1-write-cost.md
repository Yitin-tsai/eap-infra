# Write Cost Summary

- diagnostics: `ORDER_POOL_ATTRIBUTION_648_20260820_R1`
- result: [pool-attribution-648-r1-result.json](pool-attribution-648-r1-result.json)
- generatedAt: 2026-08-20T02:57:43Z

## Business Result

| Metric | Value |
|---|---:|
| marketId | `ENERGY-SPOT` |
| completedTrades | 25920 |
| businessOrderbookAdmissionTps | n/a |
| businessCompletedTradeTps | n/a |
| businessMarketFlowTps | n/a |
| businessMarketFlowOrders | n/a |
| businessMarketFlowSeconds | n/a |
| businessCompletionSeconds | 83.1460 |
| matchEngineTradeExecutionReachTps | n/a |
| orderTradeApplicationReachTps | n/a |
| walletTradeSettlementReachTps | n/a |
| businessConvergenceReachTps | n/a |
| externalSteadyAcceptedOrderTps | 647.89 |
| externalSteadyCompletedTradeTps | 325.48 |
| externalFullConvergenceTradeTps | 311.74 |
| queueFullyDrainedSeconds | n/a |
| lastNonZeroQueue | `n/a` |
| lastNonZeroQueueSeconds | n/a |

## Application Timer Ranking

Cumulative seconds are sums across all observed events, so they show work/cost contribution rather than wall-clock elapsed time.

| Rank | Service | Timer | Labels | Count | Cumulative seconds | Mean ms |
|---:|---|---|---|---:|---:|---:|
| 1 | wallet | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 80352 | 539.185 | 6.710 |
| 2 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_total"` | 51840 | 520.927 | 10.049 |
| 3 | wallet | `eap_wallet_order_submitted_processing_duration_seconds` | - | 51840 | 413.558 | 7.978 |
| 4 | wallet | `eap_wallet_order_submitted_transaction_duration_seconds` | - | 51840 | 413.441 | 7.975 |
| 5 | match | `match_engine_order_confirmed_listener_duration_seconds` | - | 51840 | 391.676 | 7.555 |
| 6 | order | `hikaricp_connections_usage_seconds` | `pool="OrderCommandPool"` | 51842 | 349.164 | 6.735 |
| 7 | match | `match_engine_try_match_duration_seconds` | - | 51840 | 326.878 | 6.306 |
| 8 | match | `match_engine_try_match_outcome_duration_seconds` | `outcome="fully_matched"` | 25920 | 248.442 | 9.585 |
| 9 | wallet | `eap_wallet_order_submitted_transaction_body_duration_seconds` | - | 51840 | 235.248 | 4.538 |
| 10 | wallet | `eap_wallet_order_submitted_reservation_cte_duration_seconds` | - | 51840 | 233.543 | 4.505 |
| 11 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_body"` | 51840 | 212.176 | 4.093 |
| 12 | order | `eap_order_submission_append_duration_seconds` | `phase="initial_append_cte"` | 51840 | 207.255 | 3.998 |
| 13 | order | `hikaricp_connections_usage_seconds` | `pool="OrderConsumerPool"` | 18719 | 193.499 | 10.337 |
| 14 | match | `hikaricp_connections_usage_seconds` | `pool="HikariPool-1"` | 31432 | 183.842 | 5.849 |
| 15 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_before_callback"` | 51840 | 170.776 | 3.294 |
| 16 | order | `hikaricp_connections_acquire_seconds` | `pool="OrderCommandPool"` | 51842 | 170.115 | 3.281 |
| 17 | match | `match_engine_trade_record_duration_seconds` | - | 25920 | 169.685 | 6.547 |
| 18 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_total"` | 25920 | 167.871 | 6.476 |
| 19 | wallet | `eap_wallet_order_submitted_transaction_after_body_duration_seconds` | - | 51840 | 167.838 | 3.238 |
| 20 | match | `match_engine_reserve_order_duration_seconds` | - | 51840 | 157.011 | 3.029 |
| 21 | match | `match_engine_reserve_order_phase_duration_seconds` | `phase="redis_eval"` | 51840 | 153.931 | 2.969 |
| 22 | order | `eap_order_submission_append_duration_seconds` | `phase="transaction_after_body"` | 51840 | 137.924 | 2.661 |
| 23 | wallet | `eap_wallet_trade_settlement_processing_duration_seconds` | - | 25920 | 133.029 | 5.132 |
| 24 | wallet | `eap_wallet_trade_settlement_transaction_duration_seconds` | - | 25920 | 132.998 | 5.131 |
| 25 | match | `match_engine_trade_record_phase_duration_seconds` | `phase="transaction_body"` | 25920 | 119.382 | 4.606 |

## PostgreSQL Executor Ranking

This is PostgreSQL executor time from pg_stat_statements. Gaps versus application timers usually point to JDBC, transaction, commit, broker confirm, scheduling, or client-side waits.

| Rank | Service | Calls | Total exec ms | Mean exec ms | Query prefix |
|---:|---|---:|---:|---:|---|
| 1 | wallet | 51840 | 38391.84 | 0.7406 | `WITH claimed AS ( INSERT INTO wallet_service.order_submission_idempotency(order_id, user_id, recorded_at) VALUES ($1, $2, CURRENT_TIMESTAMP)` |
| 2 | order | 51840 | 31688.82 | 0.6113 | `WITH inserted_head AS ( INSERT INTO order_service.order_stream_heads (aggregate_id, current_version, last_event_id, last_hash, user_id, rema` |
| 3 | order | 8641 | 19715.12 | 2.2816 | `WITH input(event_id, aggregate_id, event_type, payload_canonical, metadata_canonical, schema_version, occurred_at, hash_material_prefix, cur` |
| 4 | wallet | 25920 | 7098.41 | 0.2739 | `WITH locked_wallets AS MATERIALIZED ( SELECT user_id FROM wallet_service.wallets WHERE user_id IN ($1, $2) ORDER BY user_id FOR UPDATE ), ex` |
| 5 | match | 25920 | 6214.81 | 0.2398 | `WITH inserted_trade AS ( INSERT INTO match_engine.trade_executions (trade_id, sequence, legacy_match_id, market_id, buyer_id, seller_id, buy` |
| 6 | order | 6273 | 4824.06 | 0.7690 | `WITH input(trade_id, trade_buyer_order_id, trade_seller_order_id, trade_price, trade_quantity, trade_applied_at, buyer_order_id, buyer_quant` |
| 7 | match | 25920 | 4514.01 | 0.1742 | `INSERT INTO match_engine.reservation_cleanup_tasks (trade_id, order_id, user_id) VALUES ($1, $2, $3) ON CONFLICT (trade_id) DO NOTHING` |
| 8 | match | 1742 | 2482.62 | 1.4252 | `WITH claimed AS ( SELECT id FROM match_engine.reservation_cleanup_tasks WHERE (status = 'PENDING' AND next_retry_at <= CURRENT_TIMESTAMP) OR` |
| 9 | order | 638 | 690.02 | 1.0815 | `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count FROM order_service.order_event_outbox WHERE status = '` |
| 10 | wallet | 56 | 653.58 | 11.6710 | `select count(oe1_0.id) from wallet_service.outbox oe1_0 where oe1_0.status=$1` |
| 11 | order | 770 | 567.90 | 0.7375 | `WITH trade_application AS ( INSERT INTO order_service.order_trade_applications (trade_id, buyer_order_id, seller_order_id, price, quantity, ` |
| 12 | match | 649 | 552.52 | 0.8513 | `SELECT outbox.id, outbox.event_type, outbox.aggregate_id, outbox.routing_key, outbox.payload, outbox.attempt_count, trade.sequence, trade.le` |
| 13 | order | 413 | 390.77 | 0.9462 | `SELECT current_version, last_hash, user_id, remaining_amount, status FROM order_service.order_stream_heads WHERE aggregate_id = $1 FOR UPDAT` |
| 14 | order | 6 | 384.25 | 64.0409 | `SELECT count(*) FROM order_service.order_event_store WHERE event_type = $1` |
| 15 | wallet | 635 | 379.76 | 0.5981 | `SELECT id, event_type, routing_key, payload, attempt_count FROM wallet_service.outbox WHERE status = 'PENDING' AND next_retry_at <= CURRENT_` |
| 16 | match | 44 | 334.86 | 7.6104 | `SELECT count(*) FROM match_engine.trade_executions WHERE market_id = $1` |
| 17 | order | 2258 | 314.47 | 0.1393 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_id IN ($1, $2, $3, $4` |
| 18 | order | 1647 | 294.54 | 0.1788 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_id IN ($1, $2, $3, $4` |
| 19 | order | 45 | 276.24 | 6.1386 | `SELECT count(*) FROM order_service.order_trade_applications WHERE left(trade_id, $1) = $2` |
| 20 | wallet | 45 | 268.85 | 5.9745 | `SELECT count(*) FROM wallet_service.trade_settlements WHERE left(trade_id, $1) = $2` |

## PostgreSQL WAL Ranking

WAL bytes attribute generated write volume to statements. They do not measure WAL flush latency or storage durability.

| Rank | Service | Calls | WAL bytes | WAL bytes/call | WAL records | WAL FPI | Query prefix |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | order | 51840 | 94919549 | 1831.0 | 523011 | 0 | `WITH inserted_head AS ( INSERT INTO order_service.order_stream_heads (aggregate_id, current_version, last_event_id, last` |
| 2 | order | 8641 | 72044747 | 8337.5 | 537748 | 0 | `WITH input(event_id, aggregate_id, event_type, payload_canonical, metadata_canonical, schema_version, occurred_at, hash_` |
| 3 | wallet | 51840 | 48693575 | 939.3 | 422724 | 0 | `WITH claimed AS ( INSERT INTO wallet_service.order_submission_idempotency(order_id, user_id, recorded_at) VALUES ($1, $2` |
| 4 | match | 25920 | 22535230 | 869.4 | 208873 | 0 | `WITH inserted_trade AS ( INSERT INTO match_engine.trade_executions (trade_id, sequence, legacy_match_id, market_id, buye` |
| 5 | wallet | 25920 | 14799487 | 571.0 | 184376 | 0 | `WITH locked_wallets AS MATERIALIZED ( SELECT user_id FROM wallet_service.wallets WHERE user_id IN ($1, $2) ORDER BY user` |
| 6 | order | 6273 | 14242543 | 2270.5 | 137698 | 0 | `WITH input(trade_id, trade_buyer_order_id, trade_seller_order_id, trade_price, trade_quantity, trade_applied_at, buyer_o` |
| 7 | match | 25920 | 12339126 | 476.0 | 131145 | 0 | `INSERT INTO match_engine.reservation_cleanup_tasks (trade_id, order_id, user_id) VALUES ($1, $2, $3) ON CONFLICT (trade_` |
| 8 | match | 1742 | 10951552 | 6286.8 | 137119 | 0 | `WITH claimed AS ( SELECT id FROM match_engine.reservation_cleanup_tasks WHERE (status = 'PENDING' AND next_retry_at <= C` |
| 9 | match | 162 | 2731713 | 16862.4 | 34860 | 0 | `UPDATE match_engine.reservation_cleanup_tasks SET updated_at = CURRENT_TIMESTAMP WHERE id IN ($1, $2, $3, $4, $5, $6, $7` |
| 10 | match | 162 | 2205185 | 13612.3 | 25623 | 0 | `UPDATE match_engine.reservation_cleanup_tasks SET status = $51, last_error = $52, updated_at = CURRENT_TIMESTAMP WHERE i` |
| 11 | order | 4109 | 2146883 | 522.5 | 20739 | 0 | `INSERT INTO order_service.orders_current (order_id, user_id, market_id, market_sequence, side, price, original_amount, r` |
| 12 | order | 3891 | 1895800 | 487.2 | 19464 | 0 | `UPDATE order_service.orders_current SET status = $1, aggregate_version = $2, updated_at = CURRENT_TIMESTAMP WHERE order_` |
| 13 | order | 2258 | 835798 | 370.1 | 14782 | 0 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_i` |
| 14 | order | 1647 | 789918 | 479.6 | 14113 | 0 | `SELECT order_id, user_id, remaining_amount, matched_amount, status FROM order_service.order_matching_state WHERE order_i` |
| 15 | order | 638 | 518118 | 812.1 | 8138 | 0 | `SELECT id, event_id, exchange_name, routing_key, message_type, payload, attempt_count FROM order_service.order_event_out` |
| 16 | wallet | 35 | 514673 | 14704.9 | 5751 | 0 | `UPDATE wallet_service.outbox SET status = $82, next_retry_at = $83, last_error = $84, updated_at = $1 WHERE id IN ($2, $` |
| 17 | wallet | 635 | 489530 | 770.9 | 7739 | 0 | `SELECT id, event_type, routing_key, payload, attempt_count FROM wallet_service.outbox WHERE status = 'PENDING' AND next_` |
| 18 | order | 23 | 482883 | 20994.9 | 4205 | 0 | `UPDATE order_service.order_event_outbox SET status = $84, published_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTA` |
| 19 | wallet | 34 | 467672 | 13755.1 | 5266 | 0 | `UPDATE wallet_service.outbox SET status = $78, next_retry_at = $79, last_error = $80, updated_at = $1 WHERE id IN ($2, $` |
| 20 | order | 770 | 412281 | 535.4 | 4189 | 0 | `WITH trade_application AS ( INSERT INTO order_service.order_trade_applications (trade_id, buyer_order_id, seller_order_i` |

## Match Trade Outbox Relay Breakdown

This isolates MatchEngine TradeExecuted relay costs. Batch-size rows are counts; duration rows are seconds.

| Metric | Count | Sum | Max | Mean |
|---|---:|---:|---:|---:|
| `match_engine_trade_outbox_batch_size` | 555 | 25920.000000 | 180.000000 | 46.702703 |
| `match_engine_trade_outbox_confirmed_batch_size` | 555 | 25920.000000 | 180.000000 | 46.702703 |
| `match_engine_trade_outbox_batch_duration_seconds` | 555 | 22.431249 | 0.563626 | 0.040417 |
| `match_engine_trade_outbox_select_duration_seconds` | 781 | 3.880756 | 0.389168 | 0.004969 |
| `match_engine_trade_outbox_publish_stage_duration_seconds` | 555 | 1.287943 | 0.045342 | 0.002321 |
| `match_engine_trade_outbox_publish_enqueue_duration_seconds` | 25920 | 2.994564 | 0.015808 | 0.000116 |
| `match_engine_trade_outbox_message_build_duration_seconds` | 25920 | 0.364756 | 0.013957 | 0.000014 |
| `match_engine_trade_outbox_payload_rebuild_duration_seconds` | 25920 | 0.314686 | 0.012776 | 0.000012 |
| `match_engine_trade_outbox_confirm_wall_duration_seconds` | 555 | 15.938794 | 0.340040 | 0.028719 |
| `match_engine_trade_outbox_confirm_duration_seconds` | 25920 | 15.925697 | 0.190604 | 0.000614 |
| `match_engine_trade_outbox_first_confirm_duration_seconds` | 555 | 8.892030 | 0.190604 | 0.016022 |
| `match_engine_trade_outbox_remaining_confirm_duration_seconds` | 25365 | 7.033667 | 0.175363 | 0.000277 |
| `match_engine_trade_outbox_mark_sent_duration_seconds` | 555 | 1.602870 | 0.104401 | 0.002888 |

## Integrated Stage Lag


- marketId: `ENERGY-SPOT`
- raw per-trade rows: removed after summary generation
- generatedAt: 2026-08-20T02:54:31Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 25920 | 104.669 | 254.513 | 385.200 | 795.013 |
| Match persisted -> Wallet settlement inserted | 25920 | 77.297 | 232.658 | 357.505 | 769.865 |
| Match persisted -> durable convergence | 25920 | 105.803 | 264.471 | 390.289 | 795.013 |
| Order/Wallet durable skew | 25920 | 27.605 | 58.753 | 114.688 | 347.703 |

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
