package model

import "time"

// TriggerType defines when a conditional order should fire.
type TriggerType string

const (
	TriggerStopLoss   TriggerType = "STOP_LOSS"   // trigger when price <= triggerPrice (sell to cut loss)
	TriggerTakeProfit TriggerType = "TAKE_PROFIT" // trigger when price >= triggerPrice (sell to lock profit)
	TriggerBuyDip     TriggerType = "BUY_DIP"     // trigger when price <= triggerPrice (buy low)
	TriggerBreakout   TriggerType = "BREAKOUT"    // trigger when price >= triggerPrice (buy on breakout)
)

// OrderSide maps to eap-order's BUY/SELL.
type OrderSide string

const (
	SideBuy  OrderSide = "BUY"
	SideSell OrderSide = "SELL"
)

// Status tracks the lifecycle of a conditional order.
type Status string

const (
	StatusPending    Status = "PENDING"    // waiting for price condition
	StatusTriggering Status = "TRIGGERING" // claimed and being injected into eap-order
	StatusTriggered  Status = "TRIGGERED"  // price hit, order injected
	StatusFailed     Status = "FAILED"     // injection failed
	StatusCancelled  Status = "CANCELLED"  // user cancelled
)

// ConditionalOrder is the core domain model.
type ConditionalOrder struct {
	ID           int64       `json:"id"`
	UserID       string      `json:"userId"`
	TriggerType  TriggerType `json:"triggerType"`
	TriggerPrice float64     `json:"triggerPrice"`
	OrderSide    OrderSide   `json:"orderSide"`
	Amount       int         `json:"amount"`
	Status       Status      `json:"status"`
	TriggeredAt  *time.Time  `json:"triggeredAt,omitempty"`
	CreatedAt    time.Time   `json:"createdAt"`
}

// ShouldTrigger checks if the current deal price satisfies the trigger condition.
func (o *ConditionalOrder) ShouldTrigger(dealPrice float64) bool {
	switch o.TriggerType {
	case TriggerStopLoss, TriggerBuyDip:
		return dealPrice <= o.TriggerPrice
	case TriggerTakeProfit, TriggerBreakout:
		return dealPrice >= o.TriggerPrice
	default:
		return false
	}
}
