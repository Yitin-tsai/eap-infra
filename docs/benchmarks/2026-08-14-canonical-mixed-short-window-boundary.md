# Canonical Mixed Short-Window Boundary Recheck

## Purpose

The isolated Match processor, Rabbit-to-Match intake, downstream fanout, and
Match-relay diagnostics each ran well above the current full-chain rate. This
recheck therefore returned to the canonical shuffled mixed HTTP lifecycle to
test the combined pipeline on one host without changing service concurrency,
pool sizes, business logic, or recovery behavior.

This report answers a narrow question: does the current revision repeatedly
pass short `600`, `624`, and `648 total orders/s` stages? It does not replace
the release-pinned 15-minute sustained evidence.

## Contract And Controls

- contract: `http-matched-staircase-chain`;
- arrival pattern: balanced BUY/SELL shuffled by a recorded workload seed;
- runtime profile: canonical service-owned `application-loadtest.yml` settings;
- service launch: release jars;
- each stage: `10s` warm-up plus `30s` measurement;
- diagnostics: light `2s` sampling, with one standalone deep `624` diagnostic;
- host control: valid repeats used `caffeinate` to prevent macOS sleep;
- correctness: exact MatchEngine, Order, and Wallet trade-ID equality, exact
  assets, empty order books and reservations, and final queue/DLQ drain.

`caffeinate` is a load-generator host control, not an application optimization.

## Comparable Staircase Results

| Seed / run | 600 stage | 624 stage | 648 stage | Final correctness | Classification |
| --- | --- | --- | --- | --- | --- |
| `20260814` R1 | PASS, `346.12 trades/s` | FAIL, `271.62 trades/s`, max backlog `2093`, slope `+51.18/s` | not run | `24480` exact trades, final debt `0` | valid capacity-search run |
| `20260816` R3 | PASS, `301.45 trades/s` | PASS, `312.28 trades/s`, max backlog `153`, slope `+0.12/s` | not requested | `24480` exact trades, final debt `0` | valid capacity-search run |
| `20260817` R4 | PASS, `313.62 trades/s` | PASS, `313.45 trades/s`, max backlog `193`, slope `-0.57/s` | PASS, `325.63 trades/s`, max backlog `2161`, slope `+52.15/s` | `37440` exact trades, final debt `0` | valid capacity-search run |

Artifacts:

- [seed 20260814 R1](results/2026-08-14-canonical-mixed-staircase-seed-20260814-r1.json)
- [seed 20260816 R3](results/2026-08-14-canonical-mixed-staircase-seed-20260816-r3.json)
- [seed 20260817 R4](results/2026-08-14-canonical-mixed-staircase-seed-20260817-r4.json)
- [seed 20260817 runtime summary](results/2026-08-14-canonical-mixed-staircase-seed-20260817-r4-runtime-summary.md)
- [seed 20260817 integrated stage lag](results/2026-08-14-canonical-mixed-staircase-seed-20260817-r4-stage-lag.md)

R4's `648` stage passed the configured queue-growth rule because backlog ended
at only `10` messages and later drained to zero, despite a positive regression
slope caused by an intra-window transient. Its HTTP p99 histogram upper bound
was `2000ms`, compared with `50ms` at `624`. One short pass with this latency and
backlog volatility is exploration evidence, not a stable lower-bound promotion.

## Standalone Deep Diagnostic

A same-seed standalone `624 orders/s` deep run passed at `358.41 same-window
trades/s`. It reached `12480` exact three-service trades and zero final debt.
Deep diagnostics found no RabbitMQ alarm, meaningful database lock or WAL wait,
or fixed standalone service ceiling. Match-to-durable-convergence p95 was
`422.093ms`.

[Standalone 624 deep result](results/2026-08-14-canonical-mixed-624-deep-seed-20260814-r1.json)

Supporting diagnostics:

- [runtime summary](results/2026-08-14-canonical-mixed-624-deep-seed-20260814-r1-runtime-summary.md)
- [integrated stage lag](results/2026-08-14-canonical-mixed-624-deep-seed-20260814-r1-stage-lag.md)

This run did not include the preceding `600` stage and used a different
diagnostic level. It helps reject a deterministic `624` code ceiling but cannot
replace the comparable staircase result that failed at the same seed.

## Rejected Host-Pause Run

Seed `20260815` R2 passed `600` and appeared to fail `624`, but the overall run
is invalid for capacity comparison. The client recorded one failed HTTP
response while the final database contained all `48960` submitted orders. The
runner correctly emitted `http_accepted_count_mismatch` and `http_failures`.
During the run, operator log review found Hikari housekeeper
starvation/clock-leap warnings in all three JVMs over the same approximately
`85s` interval. The raw service logs were not retained in the public result
artifact, so this observation is supporting diagnosis rather than a
machine-verifiable gate. The HTTP mismatch alone is sufficient to reject the
run; the concurrent warnings point to host scheduling loss rather than a
Wallet-, Order-, or Match-only lock.

[Rejected seed 20260815 R2](results/2026-08-14-canonical-mixed-staircase-seed-20260815-rejected-r2.json)

The sample remains published because rejected experiments explain why a raw
stage failure must not be averaged into valid capacity evidence.

## Interpretation

- `600 orders/s` passed all three valid short-window staircases and remains
  consistent with the existing release-pinned sustained lower-bound class.
- `624 orders/s` passed two of three comparable valid seeds and failed one. It
  is near a same-host variability knee, not yet a repeatable sustained claim.
- `648 orders/s` has one valid short-window pass only. Its latency and transient
  backlog are warning signals, so it is not promoted.
- No isolated service boundary tested on this revision explains the full-chain
  rate by itself. Under mixed flow, HTTP admission, reservation, confirmation,
  matching, durable writes, relays, settlement, the broker, three databases,
  JVMs, monitoring, and the load generator compete on the same machine.
- R4 sampled Order's command pool at `35 active / 37 pending`; Wallet and Match
  had zero pending connections. This identifies Order admission as the first
  visible pressure point in that repeat, but it does not prove that increasing
  the pool would raise end-to-end capacity. System CPU peaked at `100%` and
  averaged roughly `73-78%` across the service views.

## Decision And Next Test

No application setting or code is changed from this recheck. The current
release-pinned 15-minute `600 orders/s` sustained lower bound remains the public
capacity statement.

The next useful local test is a longer fixed-rate `624` candidate run with a new
seed and light diagnostics, followed by `648` only if `624` remains bounded.
Production-style attribution still requires the load generator on a separate
CPU domain or host; otherwise host scheduling pauses and observer load remain
part of the measured system.
