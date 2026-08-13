# Release-Pinned 700 Sustained Recheck and Recovery Ownership

## Scope

This report records two same-host shuffled mixed-HTTP CDA runs executed with the
same workload contract and seed. It separates two decisions:

1. whether the reservation recovery ownership change is correct and should be adopted;
2. whether the current release-pinned system sustains `700 orders/s` for a 15-minute measurement window.

The first decision passed its direct tests. The second did not pass the sustained capacity gate.

Repository versions:

| Repository | Baseline | Ownership candidate |
| --- | --- | --- |
| `eap-infra` | `dbc1942` | `dbc1942` |
| `eap-common` | `628893a` | `628893a` |
| `eap-order` | `51165d3` | `51165d3` |
| `eap-wallet` | `3811169` | `3811169` |
| `eap-matchEngine` | `853ac9b` | change later committed as `ed55214` |

## Benchmark Contract

- public HTTP path for shuffled BUY and SELL orders;
- `60s` warmup and `900s` measurement window;
- target `700 total orders/s`;
- workload seed `20260811`, `500` users per side;
- services, databases, RabbitMQ, Redis, monitoring, and load generator on one host;
- light diagnostics;
- at least `95%` offered-load and completion ratios;
- backlog slope at most `+7 messages/s` and maximum backlog at most `21000`;
- exact MatchEngine, Order, and Wallet trade-ID equality, asset reconciliation, empty final queues and DLQ, and no remaining orders or active reservations.

## Full-Lifecycle Results

| Signal | Release-pinned baseline | Recovery ownership candidate |
| --- | ---: | ---: |
| HTTP accepted | `672000 / 672000` | `672000 / 672000` |
| HTTP `429 / 503 / other` | `0 / 0 / 0` | `0 / 0 / 0` |
| steady accepted orders/s | `699.69` | `691.28` |
| steady completed trades/s | `330.90` | `303.22` |
| completion target ratio | `94.54%` | `86.63%` |
| backlog slope | `+27.5602/s` | `+31.5123/s` |
| maximum backlog | `33751` | `28004` |
| full-convergence trades/s | `311.78` | `278.13` |
| Match / Order / Wallet trades | `336000 / 336000 / 336000` | `336000 / 336000 / 336000` |
| final queue / DLQ / reservation debt | `0` | `0` |
| correctness gate | pass | pass |
| sustained-capacity gate | fail | fail |

Both runs failed the same three sustained gates: completion ratio, positive backlog growth, and maximum backlog. They remain strong full-convergence reliability evidence but cannot support a sustained `700 orders/s` claim.

Published result artifacts:

- [release-pinned baseline JSON](results/2026-08-11-http-matched-releasepin-700-seed-20260811-r1.json)
- [recovery ownership candidate JSON](results/2026-08-11-http-matched-recovery-ownership-700-seed-20260811-r1.json)

## Bottleneck Evidence

The largest sampled queue remained `matchEngine.orderConfirmed.queue`: `32571` messages in the baseline and `26838` in the candidate. Downstream `order.tradeExecuted.queue` and `wallet.tradeExecuted.queue` peaked at only `236 / 187` in the baseline and `282 / 212` in the candidate. The first durable backlog therefore remains MatchEngine admission rather than Order trade application or Wallet settlement.

All services shared a host that averaged roughly `86-90%` system CPU and reached `100%` in both runs. Order command-pool pending requests peaked at `86` and `91`; Wallet pending requests peaked at `24` and `26`. These data show material same-host contention and prevent treating either run as a production capacity measurement.

## Recovery Ownership Decision

Before the change, the reservation reconciler completed `22521` reservations that already had an active cleanup task. The cleanup worker then reached the same reservations and emitted `22521` redundant no-matching-reservation warnings.

The candidate makes an active `PENDING` or `PROCESSING` cleanup task the owner of normal reservation cleanup. The reconciler defers those entries and remains responsible for missing, failed, or abnormal cleanup-task recovery. Direct evidence after the change was:

- `44397` reconciler deferrals to active cleanup tasks;
- `0` reconciler completions for worker-owned cleanup;
- `0` redundant no-matching-reservation warnings;
- passing reservation reconciler, cleanup worker, Redis order-book, crash-window, and complete MatchEngine tests.

This is adopted as a correctness and ownership fix. It removes duplicate work and ambiguous warning noise without disabling crash recovery.

## Capacity Interpretation

The candidate run also encountered `477` Wallet RabbitMQ publisher-confirm batch timeouts during the late hot window. Scheduled retries preserved correctness, but the stall materially changed timing while the shared host was saturated. The candidate is therefore inconclusive as a throughput A/B: its lower completed TPS must not be attributed to the ownership change, and its lower maximum backlog must not be promoted as a capacity improvement.

The historical current-worktree 15-minute 700 pass remains a valid result for its own revision. This release-pinned repeat shows that sustained 700 is not currently repeatable. The public short-window mixed-HTTP lower-bound class remains about `700 accepted orders/s`; there is no current release-pinned sustained 700 claim.

## Follow-Up

1. Establish a clean release-pinned sustained point at `600 orders/s`.
2. Repeat the passing point with a second workload seed.
3. Test `650` and then `700` only after the lower point repeats.
4. Treat RabbitMQ publisher-confirm stalls and same-host saturation as explicit invalidation or diagnostic signals.
5. Repeat the contract from an external load-generator host when available.
