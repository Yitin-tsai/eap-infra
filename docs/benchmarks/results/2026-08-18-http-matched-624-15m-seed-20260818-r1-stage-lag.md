# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260818_CURRENT_624_15M_SEED20260818_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-18T01:40:41Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 299520 | 139.430 | 765.281 | 1369.900 | 32420.500 |
| Match persisted -> Wallet settlement inserted | 299520 | 106.928 | 753.131 | 1264.340 | 2425.960 |
| Match persisted -> durable convergence | 299520 | 140.345 | 820.000 | 1423.890 | 32420.500 |
| Order/Wallet durable skew | 299520 | 30.716 | 131.226 | 351.906 | 31165.200 |
