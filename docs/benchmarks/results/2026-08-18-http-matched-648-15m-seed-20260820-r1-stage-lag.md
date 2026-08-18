# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_648_15M_SEED20260820_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-18T03:52:24Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 311040 | 137.458 | 905.434 | 1791.520 | 21684.600 |
| Match persisted -> Wallet settlement inserted | 311040 | 104.469 | 881.559 | 1672.450 | 3763.790 |
| Match persisted -> durable convergence | 311040 | 138.142 | 951.327 | 1847.720 | 21684.600 |
| Order/Wallet durable skew | 311040 | 30.885 | 125.624 | 311.730 | 21347.900 |
