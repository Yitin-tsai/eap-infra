# Published Benchmark Artifacts

This directory contains reviewed evidence selected from local raw runs. The source
location for generated artifacts is `build/load-test-reports/`, which is intentionally
ignored by Git and may be pruned.

For new campaigns, create one bundle named `YYYY-MM-DD-topic/`. Prefer:

- `summary.json`: normalized metrics, decision, evidence class, and source provenance;
- `*-result.json`: raw runner result when the exact schema materially supports the claim;
- `*-samples.csv`: only when time-series behavior or backlog slope is part of the claim;
- `*-runtime-summary.md` and `*-stage-lag.md`: only when resource or stage attribution is discussed.

Do not copy logs or an entire diagnostics directory automatically. Keep the smallest
portable evidence set that lets another reviewer verify the report. Existing flat
files predate the bundle convention and remain where they are to preserve links and
history.
