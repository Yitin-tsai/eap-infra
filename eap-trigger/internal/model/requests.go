package model

// CreateConditionalOrderRequest is the JSON body for POST /api/conditional-orders.
type CreateConditionalOrderRequest struct {
	UserID       string      `json:"userId"`
	TriggerType  TriggerType `json:"triggerType"`
	TriggerPrice float64     `json:"triggerPrice"`
	OrderSide    OrderSide   `json:"orderSide"`
	Amount       int         `json:"amount"`
}

// Validate returns an error message if the request is invalid, or empty string if ok.
func (r *CreateConditionalOrderRequest) Validate() string {
	if r.UserID == "" {
		return "userId is required"
	}
	if r.TriggerPrice <= 0 {
		return "triggerPrice must be positive"
	}
	if r.Amount <= 0 {
		return "amount must be positive"
	}
	if r.OrderSide != SideBuy && r.OrderSide != SideSell {
		return "orderSide must be BUY or SELL"
	}
	switch r.TriggerType {
	case TriggerStopLoss, TriggerTakeProfit, TriggerBuyDip, TriggerBreakout:
		// ok
	default:
		return "triggerType must be STOP_LOSS, TAKE_PROFIT, BUY_DIP, or BREAKOUT"
	}
	return ""
}
