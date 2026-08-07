# EAP Trigger Service

`eap-trigger` is a Go learning module for conditional orders. It is not part of the current EAP core transaction path or capacity claim.

## Integration Status

The implementation still declares `trigger.orderMatched.queue` on `order.exchange` and listens to the retired `order.matched` routing key. The current MatchEngine publishes `TradeExecutedEvent` on `trade.exchange / trade.executed`, so this module does not receive current trade prices without a migration.

This is documented as an explicit compatibility gap, not as a working production integration. A future migration must:

1. consume `TradeExecutedEvent` from a Trigger-owned queue bound to `trade.exchange`;
2. map `dealPrice`, `marketId`, and `tradeId` from the current contract;
3. add duplicate-delivery and restart tests before enabling real order submission;
4. keep Trigger outside MatchEngine, Order, and Wallet state ownership.

## Intended Responsibility

- Persist conditional-order definitions and claim state.
- Evaluate `STOP_LOSS`, `TAKE_PROFIT`, `BUY_DIP`, and `BREAKOUT` rules from trade prices.
- Submit a deterministic real order ID to `eap-order` after a trigger wins its database claim.
- Recover expired `TRIGGERING` leases without submitting the same conditional order twice.

## Lifecycle

```text
PENDING -> TRIGGERING -> TRIGGERED
                    \-> FAILED
PENDING -> CANCELLED
```

The database claim prevents concurrent workers from firing one conditional order twice. The deterministic downstream order ID is intended to make retries idempotent, but the current event-contract migration and full integration test are still pending.

## Run and Test

```bash
make run-trigger
make test-trigger
```

## Positioning

The Go implementation is a bounded language-learning experiment. It must not be presented as part of the verified shuffled mixed HTTP lifecycle until the `TradeExecutedEvent` migration and end-to-end tests are complete.
