# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_624_DEEP_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-14T08:49:04Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 12480 | 173.839 | 383.764 | 503.696 | 811.707 |
| Match persisted -> Wallet settlement inserted | 12480 | 158.812 | 399.400 | 590.278 | 759.974 |
| Match persisted -> durable convergence | 12480 | 183.762 | 422.093 | 604.428 | 811.707 |
| Order/Wallet durable skew | 12480 | 29.692 | 99.241 | 195.418 | 320.102 |
