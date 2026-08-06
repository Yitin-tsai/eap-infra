package orderclient

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Client calls eap-order's REST API to inject triggered orders.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

func New(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

type buyRequest struct {
	OrderID  string  `json:"orderId"`
	Bidder   string  `json:"bidder"`
	BidPrice float64 `json:"bidPrice"`
	Amount   int     `json:"amount"`
}

type sellRequest struct {
	OrderID   string  `json:"orderId"`
	Seller    string  `json:"seller"`
	SellPrice float64 `json:"sellPrice"`
	Amount    int     `json:"amount"`
}

// PlaceBuyOrder calls POST /eap-order/bid/buy.
func (c *Client) PlaceBuyOrder(orderID string, userID string, price float64, amount int) error {
	body, _ := json.Marshal(buyRequest{
		OrderID:  orderID,
		Bidder:   userID,
		BidPrice: price,
		Amount:   amount,
	})
	return c.post("/bid/buy", body)
}

// PlaceSellOrder calls POST /eap-order/bid/sell.
func (c *Client) PlaceSellOrder(orderID string, userID string, price float64, amount int) error {
	body, _ := json.Marshal(sellRequest{
		OrderID:   orderID,
		Seller:    userID,
		SellPrice: price,
		Amount:    amount,
	})
	return c.post("/bid/sell", body)
}

func (c *Client) post(path string, body []byte) error {
	url := c.baseURL + path
	resp, err := c.httpClient.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("POST %s: %w", path, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("POST %s returned %d", path, resp.StatusCode)
	}
	return nil
}
