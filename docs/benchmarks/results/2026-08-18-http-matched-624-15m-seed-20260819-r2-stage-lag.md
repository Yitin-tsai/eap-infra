# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260819_R2-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-18T02:17:55Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 299520 | 106.925 | 287.970 | 470.305 | 3415.920 |
| Match persisted -> Wallet settlement inserted | 299520 | 76.193 | 247.408 | 423.672 | 1901.120 |
| Match persisted -> durable convergence | 299520 | 107.031 | 292.510 | 478.365 | 3415.920 |
| Order/Wallet durable skew | 299520 | 29.189 | 61.880 | 115.783 | 3369.310 |
