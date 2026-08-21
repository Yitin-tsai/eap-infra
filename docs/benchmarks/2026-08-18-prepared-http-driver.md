# Prepared HTTP Driver Diagnostic

## Problem

The `1200` and `2000 orders/s` overload probes could not deliver their target
rates while the load generator, EAP services, PostgreSQL, RabbitMQ, and Redis all
shared one laptop. The old steady driver constructed the shuffled schedule,
UUID-based order data, JSON, URI, and HTTP request while traffic was running.
This made generator work part of the same-host contention being measured.

The objective was to remove deterministic workload construction from the timed
path without changing EAP business logic or pretending that one host had become
multiple CPU domains.

## Candidate Design

`prepared-sync` is available as an explicit steady-state candidate:

1. Register and fund load-test users outside the traffic window.
2. Build the complete seeded BUY/SELL schedule, deterministic order IDs, user
   assignments, and serialized request bodies before starting the clock.
3. Replay those bodies at fixed monotonic deadlines through the existing
   bounded worker pool and synchronous Java HTTP client.
4. Preserve the existing HTTP, durable-state, asset, reservation, queue, DLQ,
   and three-service trade-ID gates.

The runner records `httpDriverMode`, `loadGeneratorMaxInFlight`, and
`workloadPreparationSeconds`. Prepared request bodies consume heap, and the
driver still runs on the same host as EAP. This is a measurement-tooling
improvement, not physical resource isolation.

## Driver-Only Calibration

The calibration runs against an in-process no-op HTTP endpoint. It starts no EAP
service or Docker container and embeds `capacityClaimAllowed=false` in its JSON.

| Signal | Result |
| --- | ---: |
| mode | `prepared-sync` |
| requests | `20000` |
| target / offered | `2000 / 1999.98 requests/s` |
| workers / maximum in flight | `128 / 256` |
| accepted / received | `20000 / 20000` |
| failures / unscheduled | `0 / 0` |
| preparation time | `0.0051s` |

This rejects the prepared-sync driver itself as a `2000 requests/s` no-op input
ceiling. It says nothing about Order admission or completed-trade capacity.

## Short Full-Chain A/B

All full-chain runs used the same seed `20260818`, `648 total orders/s`, `10s`
warm-up, `30s` measurement, `500` users per side, `128` workers, `256` maximum
in-flight requests, five-second business sampling, and no external diagnostic
sampler. Only the HTTP driver mode changed.

| Signal | legacy-sync | prepared-async, rejected | prepared-sync |
| --- | ---: | ---: | ---: |
| HTTP accepted / expected | `25920 / 25920` | `25920 / 25920` | `25920 / 25920` |
| accepted orders/s | `647.87` | `647.90` | `647.49` |
| steady completed trades/s | `338.36` | `410.96` | `338.08` |
| maximum sampled backlog | `2424` | `4913` | `1239` |
| HTTP p95 upper bound | `200ms` | `500ms` | `500ms` |
| full convergence trades/s | `313.32` | `312.53` | `311.75` |
| exact final trades per service | `12960` | `12960` | `12960` |
| final queue / DLQ / reservation debt | `0` | `0` | `0` |
| correctness gate | `PASS` | `PASS` | `PASS` |

The steady completed-trade value is sensitive to how much backlog is present at
the sampled window boundaries. Full-convergence throughput is the more stable
comparison here and was effectively unchanged across all three runs.

## High-Rate Full-Chain Validation

The prepared-sync candidate was then tested at the same `1200` and `2000
orders/s` targets as the historical overload probes. Both used seed `20260822`,
`10s + 30s`, five-second business sampling, no external diagnostics, `128`
workers, and `256` maximum in flight.

| Signal | 1200 target | 2000 target |
| --- | ---: | ---: |
| payload preparation time | `0.1004s` | `0.1423s` |
| HTTP accepted / expected | `48000 / 48000` | `76949 / 80000` |
| unscheduled | `0` | `3051` |
| total accepted orders/s | `1119.12` | `1096.16` |
| steady accepted orders/s | `964.83` | `1023.60` |
| offered-load ratio | `80.40%` | `51.18%` |
| steady completed trades/s | `180.33` | `124.11` |
| backlog slope | `+561.4447/s` | `+694.2108/s` |
| exact final trades | `24000` | `38446` |
| final queue / DLQ debt | `0` | `0` |
| capacity gate | `FAIL` | `FAIL` |

Pre-generating request data did not make the synchronous full-chain driver
maintain either target. At 1200, all finite work was eventually scheduled and
converged, but not within the offered-load or completion gates. At 2000, the
driver reached the 30-second scheduling grace limit and left `3051` requests
unscheduled. Of the accepted orders, there were `57` more BUYs than SELLs; those
orders correctly remained open with their corresponding asset lock. All
`38446` pairable trades still converged across the three services.

Preparation itself took only `0.10-0.14s`. The remaining generator cost is HTTP
I/O, response latency, worker and in-flight permit occupancy, plus competition
with the services on the same host. The no-op calibration and full-chain probes
therefore answer different questions: the former proves the driver can pace
2000 low-latency responses, while the latter shows that service latency closes
the synchronous workload under shared-host saturation.

## Rejected Experiment

The first candidate combined pre-generated payloads with
`HttpClient.sendAsync`. It reached the requested offered rate, but doubled the
maximum backlog relative to legacy-sync, increased the HTTP latency histogram,
and did not improve full convergence. Because it changed both preparation and
transport, it was not a controlled answer to the original question. The async
mode was removed rather than retained as another public tuning switch.

## Decision

- Retain `prepared-sync` only as an explicit diagnostic. It correctly places
  deterministic workload construction outside the traffic clock, but the
  high-rate validation did not improve effective offered load enough to meet
  its performance objective.
- Do not claim a throughput increase from the single short A/B. The backlog
  reduction requires reverse-order repeats before it can be attributed to the
  driver change.
- Keep `legacy-sync` as the canonical default until the candidate also passes a
  long-window lifecycle run. This preserves comparability with the current
  release-pinned 648 evidence.
- Keep `648 accepted orders/s` as the current same-host sustained pressure
  boundary. This diagnostic does not replace either 15-minute seed.
- Keep the earlier `1200` and `2000 orders/s` runs classified as historical
  driver-limited overload probes. They were produced by a different driver.
- Do not treat pre-generation as load-generator isolation. A lower-overhead
  external load tool, dedicated CPU allocation, or a separate host is required
  before another high-rate full-chain capacity attempt.

Artifacts:

- [prepared-sync driver calibration](results/2026-08-18-prepared-driver-calibration-20k-2000-r1.json)
- [legacy-sync full-chain result](results/2026-08-18-driver-ab-legacy-648-40s-r1.json)
- [legacy-sync samples](results/2026-08-18-driver-ab-legacy-648-40s-r1-samples.csv)
- [rejected prepared-async full-chain result](results/2026-08-18-driver-ab-prepared-async-648-40s-r1.json)
- [rejected prepared-async samples](results/2026-08-18-driver-ab-prepared-async-648-40s-r1-samples.csv)
- [prepared-sync full-chain result](results/2026-08-18-driver-ab-prepared-sync-648-40s-r1.json)
- [prepared-sync samples](results/2026-08-18-driver-ab-prepared-sync-648-40s-r1-samples.csv)
- [prepared-sync 1200 overload result](results/2026-08-18-prepared-sync-1200-40s-r1.json)
- [prepared-sync 1200 samples](results/2026-08-18-prepared-sync-1200-40s-r1-samples.csv)
- [prepared-sync 2000 overload result](results/2026-08-18-prepared-sync-2000-40s-r1.json)
- [prepared-sync 2000 samples](results/2026-08-18-prepared-sync-2000-40s-r1-samples.csv)
