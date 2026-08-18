# Reservation Cleanup Batch A/B

## Purpose

The rejected `650 orders/s` sustained probe showed long MatchEngine reservation
cleanup batches while the single host was saturated. This experiment tested
whether reducing the load-test cleanup claim limit from `1000` to `250` improves
cleanup efficiency or full-chain progress.

This is a current-worktree diagnostic, not release-pinned capacity evidence.
Only benchmark tooling and documentation were uncommitted; the service runtime
code came from `eap-common` `628893a`, `eap-order` `d8564b7`, `eap-wallet`
`e538362`, and `eap-matchEngine` `ed55214`.

## Stage 1: Isolated Screening

The new `reservation-cleanup-isolated` probe starts only Match PostgreSQL and
Redis. Each variant received `10000` identical-shape pending tasks and Redis
reservations. Both execution orders were tested to expose warm-cache bias.

| Order | Batch size | Tasks/s | Batch mean | Batch max | Correctness |
| --- | ---: | ---: | ---: | ---: | --- |
| A/B first | `1000` | `4825.65` | `207.22ms` | `288.89ms` | pass |
| A/B second | `250` | `5134.53` | `48.69ms` | `116.48ms` | pass |
| B/A first | `250` | `5711.77` | `43.77ms` | `80.49ms` | pass |
| B/A second | `1000` | `5702.42` | `175.36ms` | `237.02ms` | pass |

The apparent throughput advantage for `250` fell from `6.4%` to `0.2%` when
the order was reversed. It is therefore not a repeatable throughput win. The
smaller limit predictably bounded one probe call to roughly one quarter of the
work while preserving total cleanup throughput, which was sufficient to justify
a short full-chain interaction test.

Artifacts:

- [A/B batch 1000](results/2026-08-14-reservation-cleanup-isolated-ab-r1-batch1000.json)
- [A/B batch 250](results/2026-08-14-reservation-cleanup-isolated-ab-r1-batch250.json)
- [B/A batch 250](results/2026-08-14-reservation-cleanup-isolated-ba-r1-batch250.json)
- [B/A batch 1000](results/2026-08-14-reservation-cleanup-isolated-ba-r1-batch1000.json)

These artifacts set `evidenceClass=isolated-diagnostic` and
`capacityClaimAllowed=false`.

## Stage 2: Short Full-Chain Confirmation

The reverse-order full-chain comparison ran `250` first and `1000` second. Both
used the same seed, `60s` warmup, `120s` measurement, `650 total orders/s`, jar
launch mode, and light diagnostics.

| Signal | Batch 250 | Batch 1000 |
| --- | ---: | ---: |
| accepted orders/s | `649.99` | `649.62` |
| completed trades/s | `324.86` | `324.46` |
| completion target | `99.96%` | `99.83%` |
| maximum steady backlog | `708` | `620` |
| backlog slope | `+0.4393/s` | `+0.0378/s` |
| HTTP p95 / p99 upper bound | `200 / 500ms` | `100 / 200ms` |
| full-lifecycle trades/s | `319.98` | `321.38` |
| Match / Order / Wallet trades | `58500 / 58500 / 58500` | `58500 / 58500 / 58500` |
| final queue / DLQ / reservation debt | `0` | `0` |

Both variants passed every correctness and short sustained gate. The `0.12%`
same-window throughput difference is immaterial, while backlog, HTTP latency,
and full-convergence throughput slightly favored `1000` in this order.

The runtime metrics also show that the configured maximum was not the normal
batch size. Batch `250` completed `58500` reservations across `1549` non-empty
worker calls, about `37.8` rows per call. Batch `1000` used `1822` calls, about
`32.1` rows per call. Its configured `1000` limit therefore did not force
thousand-row chunks during this run. Full-chain batch mean/max were
`39.12ms / 2.133s` for `250` and `35.46ms / 1.235s` for `1000`.

Artifacts:

- [batch 250 short full-chain result](results/2026-08-14-http-matched-cleanup-batch250-650-2m-r2.json)
- [batch 1000 short full-chain result](results/2026-08-14-http-matched-cleanup-batch1000-650-2m-r2.json)

## Decision

- Reject `250` as a performance improvement; the end-to-end advantage did not
  reproduce and no correctness defect requires the smaller limit.
- Keep the load-test default at `1000`. No service configuration is changed.
- Do not run a 15-minute candidate soak because the promotion gate was not met.
- Keep the isolated probe as the first stage for future cleanup implementation
  changes, but do not use its TPS as a complete-trade capacity claim.
- Continue 650 attribution outside cleanup batch sizing. The rejected 15-minute
  run still points to combined MatchEngine intake, Order/Wallet database pressure,
  load-generator scheduling, and single-host CPU contention.
