# Wallet Durable Inbox 全鏈效能回歸 - 2026-09-01

> Historical checkpoint：此報告只包含 Wallet inbox 階段。Match／Order inbox 與雙狀態加入後的目前版本，請改看 [2026-09-03 最新全鏈報告](2026-09-03-current-version-full-chain.md)；本頁的 400 pass 不代表目前 worktree 容量。

## Decision

這次 current dirty-worktree campaign 證明 Wallet durable inbox、原子驗資與非負數約束在 CDA 全鏈下維持正確，但也確認相對於既有版本有重大效能回歸。

- `400 orders/s` 通過一輪 `60s warm-up + 900s measurement` canonical shuffled mixed HTTP soak。
- `500 orders/s` 與 `648 orders/s` 的 k6 短窗都因 measurement-window completion rate 不足被拒絕。
- `450 orders/s` 輪次受到主機／driver 中斷，原定 90 秒流量拖成 654 秒並出現 109 個 EOF，因此不能用來判定服務邊界。
- 這些都是 dirty-worktree diagnostic evidence，不是 release-pinned capacity claim。舊的 release-pinned `648 orders/s` 只代表其 artifacts 記錄的舊 commits，不能套用到目前 Wallet Inbox 版本。

## Workload Matrix

| Run | Driver | Warm-up／measurement | Accepted orders/s | Steady trades/s | Full convergence trades/s | Decision |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `WALLET_ATOMIC_K6_648_20260901_R1` | k6 | 10s／30s | 648.00 | 150.49 | 189.16 | Reject：completion gate |
| `WALLET_INBOX_K6_500_20260901_R1` | k6 | 30s／60s | 500.12 | 175.01 | 198.18 | Reject：completion gate |
| `WALLET_INBOX_K6_300_20260901_R1` | k6 | 30s／60s | 300.01 | 150.57 | 144.50 | Pass |
| `WALLET_INBOX_K6_400_20260901_R1` | k6 | 30s／60s | 399.99 | 210.00 | 192.80 | Pass |
| `WALLET_INBOX_K6_450_20260901_R1` | k6 | 30s／60s | invalid | invalid | invalid | Inconclusive：host／driver interruption |
| `WALLET_INBOX_CANONICAL_400_15M_20260901_R1` | canonical Java | 60s／900s | 400.00 | 199.96 | 199.45 | Pass |

## Long-window Correctness Evidence

The accepted 400 orders/s soak produced:

- `384,000 / 384,000` accepted HTTP orders with zero 429, 503, other failure, or unscheduled order;
- `192,000` identical MatchEngine, Order, and Wallet durable trade IDs;
- exact buyer／seller assets with zero locked remainder and zero negative Wallet rows;
- zero remaining BUY／SELL order, active Match reservation, Rabbit queue backlog, unacked message, and DLQ debt;
- steady backlog maximum `177`, end `5`, and regression slope `-0.0026 messages/s`;
- all `384,000` Wallet `ORDER_SUBMITTED` inbox rows in `APPLIED`, with p95 receive-to-apply `0.1543s`, p99 `0.2754s`, and maximum `1.1948s`;
- all `384,000` Wallet result outbox rows in `SENT` and no Wallet retry／permanent inbox debt.

## Regression Size

The prior same-host 648 short-window comparison completed about `323.28–323.79 trades/s`. The current 648 k6 recheck completed `150.49 trades/s` in the measurement window, approximately `53.5%` lower. Although all delivered traffic eventually converged correctly, 648 no longer satisfies the sustained completion contract on this worktree.

The current evidence supports only one current-worktree sustained diagnostic point at `400 accepted orders/s` and `199.96 completed trades/s`. It does not prove 400 is the exact maximum: 450 was environmentally invalid, 500 failed, and the 400 long window has only one seed.

## Bottleneck Evidence and Hypothesis

At 648 orders/s, Wallet Inbox applied all `25,920` rows but averaged about `508.18 messages/s`; p95 receive-to-apply rose to `11.438s`. The current reconciler claims batches and processes their entries sequentially on one scheduled execution path, so it is a credible high-load bottleneck.

At 500 orders/s, however, Inbox processing kept pace at about `500.71 messages/s`, p95 apply latency was `0.903s`, and Wallet confirmation outbox publication also kept pace at about `501.88 events/s`. The complete chain still reached only `175.01 trades/s`. Therefore the 500 regression cannot yet be attributed only to the conditional reservation SQL or Inbox poller; additional DB write amplification, scheduler/CPU contention, and downstream pacing require stage-attributed diagnostics.

## Next Measurement

Do not tune away durable intake or the atomic balance guard. First add Wallet Inbox pending/oldest-age samples to the full-chain result, then compare:

1. claim batch SQL time;
2. per-message reservation transaction time;
3. Inbox APPLIED rate and confirmation outbox SENT rate;
4. Match admission and trade persistence rate;
5. Order/Wallet trade-consumer lag;
6. JVM CPU, GC, scheduler delay, PostgreSQL pool wait, WAL, and transaction time.

Any candidate concurrency or batching change must rerun the distinct-order oversubscription test and the exact full-chain correctness gates before performance adoption.
