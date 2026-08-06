package model

import "testing"

func TestConditionalOrderShouldTrigger(t *testing.T) {
	tests := []struct {
		name         string
		triggerType  TriggerType
		triggerPrice float64
		dealPrice    float64
		want         bool
	}{
		{"stop loss below threshold", TriggerStopLoss, 90, 89, true},
		{"stop loss above threshold", TriggerStopLoss, 90, 91, false},
		{"buy dip equal threshold", TriggerBuyDip, 80, 80, true},
		{"take profit above threshold", TriggerTakeProfit, 120, 121, true},
		{"take profit below threshold", TriggerTakeProfit, 120, 119, false},
		{"breakout equal threshold", TriggerBreakout, 130, 130, true},
		{"unknown trigger type", TriggerType("UNKNOWN"), 100, 100, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			order := &ConditionalOrder{
				TriggerType:  tt.triggerType,
				TriggerPrice: tt.triggerPrice,
			}
			if got := order.ShouldTrigger(tt.dealPrice); got != tt.want {
				t.Fatalf("ShouldTrigger() = %v, want %v", got, tt.want)
			}
		})
	}
}
