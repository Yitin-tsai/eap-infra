# EAP k6 Workloads

k6 owns HTTP load generation only. Service lifecycle, deterministic data setup,
RabbitMQ/Redis/PostgreSQL diagnostics, and final cross-service correctness remain in
the shell and Java harnesses.

## Modules

```text
k6/
  http-matched-open-loop.js   executable workload
  lib/
    config.js                 environment parsing, scenario, and thresholds
    prepared-workload.js      finite checksummed request schedule adapter
    report.js                 driver-only JSON and Markdown summaries
```

The workload uses `constant-arrival-rate`. A run fails its driver gate when any
prepared request is missing, an iteration falls outside the finite schedule, an
iteration is dropped, an HTTP response is not 2xx,
or an optional `K6_MAX_P95_MS` limit is crossed. Those gates prove only that k6
offered the intended HTTP traffic successfully.

The final EAP verifier separately requires durable MatchEngine/Order/Wallet trade-ID
equality, asset reconciliation, empty order books and reservations, and queue/DLQ
drain. Never publish a capacity claim from the k6 summary alone.

## Adding a Workload

1. Keep environment parsing and thresholds in `lib/config.js` unless the new
   contract genuinely needs different options.
2. Put reusable request-data parsing in `lib/`; keep the entry script limited to
   scenario behavior.
3. Tag each request with a stable endpoint name and business dimension. Do not use
   high-cardinality order or user IDs as metric tags.
4. Emit both a machine-readable summary and a short driver Markdown report through
   `handleSummary()`.
5. Pass request-level results to an EAP verifier. Checks and thresholds are not a
   replacement for durable business-state validation.

## References

- [k6 basic introduction used for the initial test-type vocabulary](https://ithelp.ithome.com.tw/articles/10305586)
- [Official k6 executor reference](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/)
- [Official k6 results-output guide](https://grafana.com/docs/k6/latest/results-output/)
- [Official custom-summary reference](https://grafana.com/docs/k6/latest/results-output/end-of-test/custom-summary/)
# HTTP idempotency comparisons

The full-chain external runner accepts `HTTP_IDEMPOTENCY_MODE=none|unique` (k6 only;
default `none`). `unique` adds a stable key derived from each prepared order UUID
during initialization. It preserves request bodies and the unique-order schedule;
the mode is saved in the driver and full-chain results.

Use the isolated comparison runner with sleep prevention on macOS:

```bash
caffeinate -dimsu env python3 scripts/load-test/run-http-idempotency-comparison.py \
  --campaign-id HTTP_IDEMPOTENCY_NEW_RUN --duration 180 --warmup 60 --repeats 3
```

It resets dedicated loadtest data before each service start, retains raw artifacts
and volumes, and verifies schema-v4, exact counts, receipt identity and stable source.
Start the dedicated infrastructure with the same `synchronous_commit=on` setting
first. Use a fresh campaign ID. Stop owned services/containers after inspection.

`http-idempotency-replay.js` is a separate replay-only probe. Targets must refer to
already committed keys and include `expectedResponse` from the original receipt.
It compares returned fields and labels all traffic as replay, with zero new orders.
It requires separate before/after database, asset, sequence and outcome-counter
verification; HTTP success alone is insufficient. It does not prove mixed live-load
capacity. See the repository's 2026-11-05 benchmark report for evidence and limits.
