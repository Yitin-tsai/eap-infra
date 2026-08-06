# Correctness Snapshot

- Run: `GLT_20260805_ORDER_ASYNC4_WALLET_BATCHCONFIRM_900_15M_R1`
- Expected orders / trades: `864000 / 432000`
- HTTP accepted: `864000`
- Match / Order / Wallet trade facts: `432190 / 431783 / 432190`
- Final measured Rabbit backlog: `0`
- Result: invalid for capacity and reliability claims

The workload uses quantity-one orders, so one order ID appearing in more than one
trade is always invalid. The post-run Match query was:

```sql
WITH order_uses AS (
    SELECT buyer_order_id AS order_id, trade_id
    FROM match_engine.trade_executions
    UNION ALL
    SELECT seller_order_id AS order_id, trade_id
    FROM match_engine.trade_executions
), duplicates AS (
    SELECT order_id, count(*) AS uses, count(DISTINCT trade_id) AS trades
    FROM order_uses
    GROUP BY order_id
    HAVING count(*) > 1
)
SELECT count(*) AS orders_reused,
       coalesce(sum(uses - 1), 0) AS extra_uses,
       coalesce(max(uses), 0) AS max_uses
FROM duplicates;
```

Result:

| orders_reused | extra_uses | max_uses |
|---:|---:|---:|
| 431 | 431 | 2 |

Order's trade inbox contained `451 FAILED_PERMANENT` rows at attempt one and
`385 APPLIED` redelivery rows. The permanent rows were larger than the number of
reused orders because the listener classified the entire consumer batch using the
first `TradeApplicationRejectedException`.
