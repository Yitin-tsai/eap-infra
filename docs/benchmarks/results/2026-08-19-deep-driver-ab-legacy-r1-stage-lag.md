# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-DRIVER_DEEP_LEGACY_648_SEED_20260804_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-19T08:43:14Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 12960 | 100.304 | 215.789 | 294.007 | 541.523 |
| Match persisted -> Wallet settlement inserted | 12960 | 74.255 | 194.439 | 294.195 | 475.765 |
| Match persisted -> durable convergence | 12960 | 100.854 | 221.593 | 311.270 | 541.523 |
| Order/Wallet durable skew | 12960 | 26.564 | 51.644 | 78.827 | 161.164 |
