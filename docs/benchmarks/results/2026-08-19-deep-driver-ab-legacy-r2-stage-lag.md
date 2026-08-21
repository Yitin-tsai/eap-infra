# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-19T08:47:23Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 12960 | 122.238 | 294.231 | 438.680 | 638.748 |
| Match persisted -> Wallet settlement inserted | 12960 | 98.208 | 297.599 | 479.717 | 681.779 |
| Match persisted -> durable convergence | 12960 | 124.855 | 318.268 | 497.129 | 681.779 |
| Order/Wallet durable skew | 12960 | 27.157 | 76.989 | 149.845 | 333.781 |
