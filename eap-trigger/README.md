# EAP Trigger Service

`eap-trigger` is a Go-based conditional-order trigger service.

It subscribes to match events, keeps pending conditional orders in PostgreSQL, and injects real buy/sell orders into `eap-order` once the trigger condition is satisfied.

## Responsibilities

- Store and recover pending conditional orders
- Subscribe to `order.matched` events from RabbitMQ
- Evaluate trigger rules on incoming deal prices
- Submit real orders to `eap-order` when the rule fires
- Prevent duplicate trigger execution with a database claim step

## Trigger types

- `STOP_LOSS`
- `TAKE_PROFIT`
- `BUY_DIP`
- `BREAKOUT`

## Lifecycle

```text
PENDING -> TRIGGERING -> TRIGGERED
                    \-> FAILED
PENDING -> CANCELLED
```

`TRIGGERING` is a claim state. Before the service injects a real order into `eap-order`, it updates the row from `PENDING` to `TRIGGERING`. Only one worker can win that update, so duplicate match events or concurrent consumers do not submit the same conditional order twice.

On startup and every 30 seconds, the service recovers expired `TRIGGERING` rows back to `PENDING`. This handles both claims that were already stale at startup and claims that expire after the service has restarted. `TRIGGER_CLAIM_TIMEOUT` and `TRIGGER_RECOVERY_INTERVAL` control the lease and scan interval.

## Price Matching

Pending orders are kept in memory and backed by PostgreSQL. The in-memory structure separates trigger rules into two sorted indexes:

- `STOP_LOSS` / `BUY_DIP`: trigger when `dealPrice <= triggerPrice`
- `TAKE_PROFIT` / `BREAKOUT`: trigger when `dealPrice >= triggerPrice`

This avoids scanning unrelated trigger directions on every price update while keeping the implementation simple enough for a learning module.

## Idempotency Boundary

When a conditional order fires, `eap-trigger` generates a deterministic `orderId` from the conditional order id. If the submission is retried after a crash or duplicate event, the same real order id is reused.

Downstream, `eap-wallet` records processed `OrderSubmittedEvent` ids in `order_submission_idempotency`, so repeated submissions do not lock funds twice.

## Why Go

This module was intentionally written in Go as a learning project. It gave me a chance to practice:

- lightweight service structure without Spring
- interfaces and small fakes for unit testing
- mutex-protected in-memory state
- RabbitMQ consumers
- PostgreSQL persistence
- a small event-driven service lifecycle

Java 21 virtual threads could also implement this service. The choice of Go is not because Java cannot handle it; it is because this module is a bounded, event-driven problem that is suitable for practicing Go's simpler concurrency and service style.

## Run

```bash
make run-trigger
```

## Build and Test

```bash
make build-trigger
make test-trigger
```

## Positioning

This is a side module, not the core trading path. Its business meaning is straightforward: trigger a conditional order when the market price reaches the configured threshold.
