package service

import (
	"crypto/sha1"
	"eap-trigger/internal/model"
	"encoding/hex"
	"fmt"
	"log"
	"sort"
	"sync"
	"time"
)

type orderStore interface {
	CancelByID(id int64) (bool, error)
	ClaimForTrigger(id int64) (bool, error)
	FindAllPending() ([]model.ConditionalOrder, error)
	FindByID(id int64) (*model.ConditionalOrder, error)
	FindByUserID(userID string) ([]model.ConditionalOrder, error)
	Insert(o *model.ConditionalOrder) (int64, error)
	RecoverStaleTriggering(before time.Time) (int64, error)
	UpdateStatus(id int64, status model.Status) error
}

type orderExecutor interface {
	PlaceBuyOrder(orderID string, userID string, price float64, amount int) error
	PlaceSellOrder(orderID string, userID string, price float64, amount int) error
}

// TriggerService is the core business logic.
// It holds all pending orders in memory for fast price matching,
// backed by PostgreSQL for persistence and recovery.
type TriggerService struct {
	store       orderStore
	orderClient orderExecutor

	mu      sync.RWMutex
	pending *pendingIndex // in-memory cache of pending orders
}

func NewTriggerService(store orderStore, orderClient orderExecutor) *TriggerService {
	return &TriggerService{
		store:       store,
		orderClient: orderClient,
		pending:     newPendingIndex(),
	}
}

type pendingIndex struct {
	byID       map[int64]*model.ConditionalOrder
	ltePriceID []int64 // STOP_LOSS / BUY_DIP: trigger when dealPrice <= triggerPrice
	gtePriceID []int64 // TAKE_PROFIT / BREAKOUT: trigger when dealPrice >= triggerPrice
}

func newPendingIndex() *pendingIndex {
	return &pendingIndex{
		byID: make(map[int64]*model.ConditionalOrder),
	}
}

func (idx *pendingIndex) add(order *model.ConditionalOrder) {
	if _, exists := idx.byID[order.ID]; exists {
		idx.remove(order.ID)
	}
	idx.byID[order.ID] = order
	switch triggerDirection(order.TriggerType) {
	case triggerWhenPriceLTE:
		idx.ltePriceID = insertByTriggerPrice(idx.ltePriceID, idx.byID, order.ID)
	case triggerWhenPriceGTE:
		idx.gtePriceID = insertByTriggerPrice(idx.gtePriceID, idx.byID, order.ID)
	}
}

func (idx *pendingIndex) remove(id int64) {
	if order, ok := idx.byID[id]; ok {
		switch triggerDirection(order.TriggerType) {
		case triggerWhenPriceLTE:
			idx.ltePriceID = removeID(idx.ltePriceID, id)
		case triggerWhenPriceGTE:
			idx.gtePriceID = removeID(idx.gtePriceID, id)
		}
	}
	delete(idx.byID, id)
}

func (idx *pendingIndex) count() int {
	return len(idx.byID)
}

func (idx *pendingIndex) matching(dealPrice float64) []*model.ConditionalOrder {
	var matched []*model.ConditionalOrder

	firstLTE := sort.Search(len(idx.ltePriceID), func(i int) bool {
		return idx.byID[idx.ltePriceID[i]].TriggerPrice >= dealPrice
	})
	for _, id := range idx.ltePriceID[firstLTE:] {
		matched = append(matched, idx.byID[id])
	}

	firstGT := sort.Search(len(idx.gtePriceID), func(i int) bool {
		return idx.byID[idx.gtePriceID[i]].TriggerPrice > dealPrice
	})
	for _, id := range idx.gtePriceID[:firstGT] {
		matched = append(matched, idx.byID[id])
	}

	return matched
}

type triggerDirectionType int

const (
	triggerNever triggerDirectionType = iota
	triggerWhenPriceLTE
	triggerWhenPriceGTE
)

func triggerDirection(triggerType model.TriggerType) triggerDirectionType {
	switch triggerType {
	case model.TriggerStopLoss, model.TriggerBuyDip:
		return triggerWhenPriceLTE
	case model.TriggerTakeProfit, model.TriggerBreakout:
		return triggerWhenPriceGTE
	default:
		return triggerNever
	}
}

func insertByTriggerPrice(ids []int64, orders map[int64]*model.ConditionalOrder, id int64) []int64 {
	insertAt := sort.Search(len(ids), func(i int) bool {
		return orders[ids[i]].TriggerPrice > orders[id].TriggerPrice
	})
	ids = append(ids, 0)
	copy(ids[insertAt+1:], ids[insertAt:])
	ids[insertAt] = id
	return ids
}

func removeID(ids []int64, id int64) []int64 {
	for i, existing := range ids {
		if existing == id {
			return append(ids[:i], ids[i+1:]...)
		}
	}
	return ids
}

// LoadPendingOrders restores pending orders from DB into memory.
// Called once at startup to survive restarts.
func (s *TriggerService) LoadPendingOrders(claimTimeout time.Duration) error {
	if claimTimeout <= 0 {
		return fmt.Errorf("trigger claim timeout must be positive")
	}
	recovered, err := s.store.RecoverStaleTriggering(time.Now().Add(-claimTimeout))
	if err != nil {
		return err
	}
	if recovered > 0 {
		log.Printf("[trigger] recovered %d stale triggering orders", recovered)
	}

	orders, err := s.mergePendingOrders()
	if err != nil {
		return err
	}
	log.Printf("[trigger] loaded %d pending conditional orders from DB", orders)
	return nil
}

// RecoverStaleClaims periodically returns expired trigger claims to the in-memory
// pending index. Startup recovery alone cannot see a claim that has not expired yet.
func (s *TriggerService) RecoverStaleClaims(claimTimeout time.Duration) (int64, error) {
	if claimTimeout <= 0 {
		return 0, fmt.Errorf("trigger claim timeout must be positive")
	}
	recovered, err := s.store.RecoverStaleTriggering(time.Now().Add(-claimTimeout))
	if err != nil {
		return 0, err
	}
	if recovered == 0 {
		return 0, nil
	}
	loaded, err := s.mergePendingOrders()
	if err != nil {
		return 0, err
	}
	log.Printf("[trigger] recovered %d stale triggering orders; pending rows merged=%d", recovered, loaded)
	return recovered, nil
}

func (s *TriggerService) mergePendingOrders() (int, error) {
	orders, err := s.store.FindAllPending()
	if err != nil {
		return 0, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range orders {
		s.pending.add(&orders[i])
	}
	return len(orders), nil
}

// Create validates and persists a new conditional order.
func (s *TriggerService) Create(req *model.CreateConditionalOrderRequest) (*model.ConditionalOrder, error) {
	order := &model.ConditionalOrder{
		UserID:       req.UserID,
		TriggerType:  req.TriggerType,
		TriggerPrice: req.TriggerPrice,
		OrderSide:    req.OrderSide,
		Amount:       req.Amount,
		Status:       model.StatusPending,
		CreatedAt:    time.Now(),
	}

	id, err := s.store.Insert(order)
	if err != nil {
		return nil, err
	}
	order.ID = id

	s.mu.Lock()
	s.pending.add(order)
	s.mu.Unlock()

	log.Printf("[trigger] created conditional order #%d: %s when price %s %.2f",
		id, req.OrderSide, req.TriggerType, req.TriggerPrice)
	return order, nil
}

func (s *TriggerService) deterministicOrderID(orderID int64) string {
	sum := sha1.Sum([]byte(fmt.Sprintf("eap-trigger:%d", orderID)))
	hexStr := hex.EncodeToString(sum[:16])
	return fmt.Sprintf("%s-%s-%s-%s-%s",
		hexStr[0:8], hexStr[8:12], hexStr[12:16], hexStr[16:20], hexStr[20:32])
}

// GetByID returns a single conditional order.
func (s *TriggerService) GetByID(id int64) (*model.ConditionalOrder, error) {
	return s.store.FindByID(id)
}

// GetByUserID returns all conditional orders for a user.
func (s *TriggerService) GetByUserID(userID string) ([]model.ConditionalOrder, error) {
	return s.store.FindByUserID(userID)
}

// Cancel marks a pending order as cancelled.
func (s *TriggerService) Cancel(id int64) (bool, error) {
	ok, err := s.store.CancelByID(id)
	if err != nil {
		return false, err
	}
	if ok {
		s.mu.Lock()
		s.pending.remove(id)
		s.mu.Unlock()
		log.Printf("[trigger] cancelled conditional order #%d", id)
	}
	return ok, nil
}

// OnPriceUpdate is called whenever an OrderMatchedEvent arrives.
// It checks all pending orders against the new deal price
// and triggers any that match.
func (s *TriggerService) OnPriceUpdate(event *model.OrderMatchedEvent) {
	dealPrice := event.DealPrice

	s.mu.RLock()
	toTrigger := s.pending.matching(dealPrice)
	s.mu.RUnlock()

	for _, order := range toTrigger {
		s.triggerOrder(order, dealPrice)
	}
}

// triggerOrder injects the real order into eap-order and updates status.
func (s *TriggerService) triggerOrder(order *model.ConditionalOrder, dealPrice float64) {
	log.Printf("[trigger] FIRING #%d: %s %s @ dealPrice=%.2f (trigger=%.2f)",
		order.ID, order.OrderSide, order.TriggerType, dealPrice, order.TriggerPrice)

	claimed, claimErr := s.store.ClaimForTrigger(order.ID)
	if claimErr != nil {
		log.Printf("[trigger] CLAIM FAILED #%d: %v", order.ID, claimErr)
		return
	}
	if !claimed {
		log.Printf("[trigger] SKIP #%d: order already handled or no longer pending", order.ID)
		s.mu.Lock()
		s.pending.remove(order.ID)
		s.mu.Unlock()
		return
	}

	order.Status = model.StatusTriggering
	clientOrderID := s.deterministicOrderID(order.ID)

	var execErr error
	switch order.OrderSide {
	case model.SideBuy:
		execErr = s.orderClient.PlaceBuyOrder(clientOrderID, order.UserID, order.TriggerPrice, order.Amount)
	case model.SideSell:
		execErr = s.orderClient.PlaceSellOrder(clientOrderID, order.UserID, order.TriggerPrice, order.Amount)
	default:
		execErr = fmt.Errorf("unsupported order side %q", order.OrderSide)
	}

	if execErr != nil {
		log.Printf("[trigger] FAILED #%d: %v", order.ID, execErr)
		_ = s.store.UpdateStatus(order.ID, model.StatusFailed)
		s.mu.Lock()
		s.pending.remove(order.ID)
		s.mu.Unlock()
		return
	}

	log.Printf("[trigger] SUCCESS #%d: order injected into eap-order", order.ID)
	_ = s.store.UpdateStatus(order.ID, model.StatusTriggered)
	s.mu.Lock()
	s.pending.remove(order.ID)
	s.mu.Unlock()
}

// PendingCount returns the number of active pending orders (for health check).
func (s *TriggerService) PendingCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.pending.count()
}
