package model

import "time"

// OrderMatchedEvent mirrors eap-common's OrderMatchedEvent.
// Published by eap-matchEngine on routing key "order.matched".
type OrderMatchedEvent struct {
	BuyerID         string    `json:"buyerId"`
	SellerID        string    `json:"sellerId"`
	BuyerOrderID    string    `json:"buyerOrderId"`
	SellerOrderID   string    `json:"sellerOrderId"`
	OriginBuyPrice  float64   `json:"originBuyerPrice"`
	OriginSellPrice float64   `json:"originSellerPrice"`
	DealPrice       float64   `json:"dealPrice"`
	Amount          int       `json:"amount"`
	MatchID         int64     `json:"matchId"`
	MatchedAt       time.Time `json:"matchedAt"`
	OrderType       string    `json:"orderType"`
}
