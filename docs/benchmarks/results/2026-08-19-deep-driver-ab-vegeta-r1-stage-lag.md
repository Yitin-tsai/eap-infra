# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-DRIVER_DEEP_VEGETA_648_SEED_20260804_R2_FIXED-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-19T08:51:59Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 12960 | 109.066 | 314.064 | 453.030 | 580.712 |
| Match persisted -> Wallet settlement inserted | 12960 | 84.656 | 291.637 | 441.078 | 682.677 |
| Match persisted -> durable convergence | 12960 | 110.957 | 324.149 | 472.578 | 682.677 |
| Order/Wallet durable skew | 12960 | 26.905 | 77.808 | 132.701 | 295.433 |
