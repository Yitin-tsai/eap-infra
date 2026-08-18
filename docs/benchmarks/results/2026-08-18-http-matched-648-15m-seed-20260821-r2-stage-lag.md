# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260821_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-18T04:12:03Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 311040 | 237.247 | 1094.810 | 1934.740 | 12062.100 |
| Match persisted -> Wallet settlement inserted | 311040 | 205.381 | 1070.510 | 1857.480 | 3027.020 |
| Match persisted -> durable convergence | 311040 | 246.352 | 1154.780 | 2016.220 | 12062.100 |
| Order/Wallet durable skew | 311040 | 33.908 | 187.720 | 503.463 | 11728.000 |
