# Integrated Stage Lag

- marketId: `ENERGY-SPOT`
- rows: `/Users/cfh00909120/Desktop/eap-workspace/build/load-test-reports/http-matched-steady-GLT_20260805_HTTP_MATCHED_DEEP_DIAG_950_R1-diagnostics/integrated-stage-lag.tsv`
- generatedAt: 2026-08-05T05:35:24Z

Lag values are measured from persisted database timestamps after the run. They are for attribution, not hot-path instrumentation.

Notes:

- Match time uses `trade_executions.created_at`.
- Order time uses `order_trade_applications.applied_at`, the durable command-side trade-application fact.
- Wallet settlement apply time uses `trade_settlements.inserted_at`, the durable settlement fact insert time.
- Completion marker timing is intentionally absent because Order/Wallet no longer publish per-trade marker events to MatchEngine.

| Stage | Count | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|---:|
| Match persisted -> Order trade application | 99750 | 0.931 | 21.484 | 22.337 | 22.803 |
| Match persisted -> Wallet settlement inserted | 99750 | 683.180 | 4718.350 | 6299.100 | 8088.190 |
| Match persisted -> durable convergence | 99750 | 683.180 | 4718.350 | 6299.100 | 8088.190 |
| Order/Wallet durable skew | 99750 | 677.292 | 4709.430 | 6299.120 | 8066.850 |
