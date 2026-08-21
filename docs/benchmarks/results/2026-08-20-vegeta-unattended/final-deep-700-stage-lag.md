# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-external-VEGETA_UNATTENDED_20260819_R1_FINAL_DEEP_700_SEED_20260899-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-19T20:05:05Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 336000 | 94.284 | 190.301 | 289.645 | 609.438 |
| Match persisted -> Wallet settlement inserted | 336000 | 65.026 | 156.300 | 254.265 | 579.725 |
| Match persisted -> durable convergence | 336000 | 94.304 | 191.101 | 290.961 | 609.438 |
| Order/Wallet durable skew | 336000 | 28.670 | 44.069 | 65.449 | 430.067 |
