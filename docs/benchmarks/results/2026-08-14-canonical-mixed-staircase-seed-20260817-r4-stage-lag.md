# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-staircase-GLT_20260814_CANONICAL_MIXED_600_648_LIGHT_SEED20260817_R4-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-14T09:00:23Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.inserted_at`, the database-generated durable insertion time.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Business completion is measured directly from the three service-owned durable tables.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 37440 | 109.522 | 431.178 | 794.829 | 2950.710 |
| Match persisted -> Wallet settlement inserted | 37440 | 81.873 | 442.669 | 858.529 | 3568.180 |
| Match persisted -> durable convergence | 37440 | 110.642 | 478.348 | 866.588 | 3568.180 |
| Order/Wallet durable skew | 37440 | 28.316 | 93.180 | 195.372 | 3177.720 |
