# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260805_ORDER_OUTBOX_ASYNC4_900_15M_R3-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-05T08:14:05Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.applied_at`, the durable command-side trade-application fact.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Completion marker timing is intentionally absent because Order/Wallet no longer publish per-trade marker events to MatchEngine.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 311380 | 8.295 | 79.969 | 105.882 | 114.029 |
| Match persisted -> Wallet settlement inserted | 311380 | 8987.660 | 21133.600 | 23407.100 | 28306.500 |
| Match persisted -> durable convergence | 311380 | 8987.660 | 21133.600 | 23407.100 | 28306.500 |
| Order/Wallet durable skew | 311380 | 8964.670 | 21114.800 | 23384.000 | 28265.400 |
