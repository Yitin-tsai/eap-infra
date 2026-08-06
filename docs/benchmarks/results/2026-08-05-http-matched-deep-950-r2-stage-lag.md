# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-05T05:41:33Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.applied_at`, the durable command-side trade-application fact.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Completion marker timing is intentionally absent because Order/Wallet no longer publish per-trade marker events to MatchEngine.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 99750 | 5.231 | 101.863 | 106.429 | 108.187 |
| Match persisted -> Wallet settlement inserted | 99750 | 3664.200 | 13562.600 | 15100.400 | 16983.400 |
| Match persisted -> durable convergence | 99750 | 3664.200 | 13562.600 | 15100.400 | 16983.400 |
| Order/Wallet durable skew | 99750 | 3664.880 | 13516.000 | 15001.400 | 16894.500 |
