# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260806_MATCH_BITMAP_MIXED_900_USERS500_DEEP_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-06T07:54:28Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Completion marker timing is intentionally absent because Order/Wallet no longer publish per-trade marker events to MatchEngine.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 15750 | 108.124 | 429.209 | 873.324 | 1137.420 |
| Match persisted -> Wallet settlement inserted | 15750 | 81.445 | 410.381 | 818.230 | 1030.680 |
| Match persisted -> durable convergence | 15750 | 109.106 | 441.977 | 873.324 | 1137.420 |
| Order/Wallet durable skew | 15750 | 26.623 | 68.074 | 107.693 | 196.412 |
