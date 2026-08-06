# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260805_ORDER_ASYNC4_WALLET_BATCHCONFIRM_900_15M_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-05T08:51:48Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.applied_at`, the durable command-side trade-application fact.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Completion marker timing is intentionally absent because Order/Wallet no longer publish per-trade marker events to MatchEngine.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 431783 | 5.166 | 51.794 | 88.903 | 116.256 |
| Match persisted -> Wallet settlement inserted | 431783 | 4239.630 | 19736.800 | 21974.900 | 25811.600 |
| Match persisted -> durable convergence | 431783 | 4239.630 | 19736.800 | 21974.900 | 25811.600 |
| Order/Wallet durable skew | 431783 | 4236.500 | 19712.100 | 21955.100 | 25806.200 |
