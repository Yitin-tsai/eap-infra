package service

import (
	"eap-trigger/internal/model"
	"errors"
	"reflect"
	"testing"
	"time"
)

type fakeStore struct {
	nextID       int64
	orders       map[int64]*model.ConditionalOrder
	claims       map[int64]bool
	statuses     map[int64]model.Status
	recoveredCut time.Time
	recovered    int64
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		nextID:   1,
		orders:   make(map[int64]*model.ConditionalOrder),
		claims:   make(map[int64]bool),
		statuses: make(map[int64]model.Status),
	}
}

func (s *fakeStore) CancelByID(id int64) (bool, error) {
	order, ok := s.orders[id]
	if !ok || order.Status != model.StatusPending {
		return false, nil
	}
	order.Status = model.StatusCancelled
	s.statuses[id] = model.StatusCancelled
	return true, nil
}

func (s *fakeStore) ClaimForTrigger(id int64) (bool, error) {
	order, ok := s.orders[id]
	if !ok || order.Status != model.StatusPending || s.claims[id] {
		return false, nil
	}
	s.claims[id] = true
	order.Status = model.StatusTriggering
	s.statuses[id] = model.StatusTriggering
	return true, nil
}

func (s *fakeStore) FindAllPending() ([]model.ConditionalOrder, error) {
	var orders []model.ConditionalOrder
	for _, order := range s.orders {
		if order.Status == model.StatusPending {
			orders = append(orders, *order)
		}
	}
	return orders, nil
}

func (s *fakeStore) FindByID(id int64) (*model.ConditionalOrder, error) {
	order, ok := s.orders[id]
	if !ok {
		return nil, errors.New("no rows")
	}
	copy := *order
	return &copy, nil
}

func (s *fakeStore) FindByUserID(userID string) ([]model.ConditionalOrder, error) {
	var orders []model.ConditionalOrder
	for _, order := range s.orders {
		if order.UserID == userID {
			orders = append(orders, *order)
		}
	}
	return orders, nil
}

func (s *fakeStore) Insert(o *model.ConditionalOrder) (int64, error) {
	id := s.nextID
	s.nextID++
	copy := *o
	copy.ID = id
	s.orders[id] = &copy
	return id, nil
}

func (s *fakeStore) RecoverStaleTriggering(before time.Time) (int64, error) {
	s.recoveredCut = before
	return s.recovered, nil
}

func (s *fakeStore) UpdateStatus(id int64, status model.Status) error {
	order, ok := s.orders[id]
	if !ok {
		return errors.New("no rows")
	}
	order.Status = status
	s.statuses[id] = status
	return nil
}

type placedOrder struct {
	orderID string
	userID  string
	side    model.OrderSide
	price   float64
	amount  int
}

type fakeOrderClient struct {
	err    error
	placed []placedOrder
}

func (c *fakeOrderClient) PlaceBuyOrder(orderID string, userID string, price float64, amount int) error {
	if c.err != nil {
		return c.err
	}
	c.placed = append(c.placed, placedOrder{orderID: orderID, userID: userID, side: model.SideBuy, price: price, amount: amount})
	return nil
}

func (c *fakeOrderClient) PlaceSellOrder(orderID string, userID string, price float64, amount int) error {
	if c.err != nil {
		return c.err
	}
	c.placed = append(c.placed, placedOrder{orderID: orderID, userID: userID, side: model.SideSell, price: price, amount: amount})
	return nil
}

func TestDeterministicOrderID(t *testing.T) {
	store := newFakeStore()
	client := &fakeOrderClient{}
	svc := NewTriggerService(store, client)

	first := svc.deterministicOrderID(42)
	second := svc.deterministicOrderID(42)
	other := svc.deterministicOrderID(43)

	if first != second {
		t.Fatalf("same conditional order id produced different order ids: %q != %q", first, second)
	}
	if first == other {
		t.Fatalf("different conditional order ids produced same order id: %q", first)
	}
	if len(first) != 36 {
		t.Fatalf("order id length = %d, want UUID-like 36", len(first))
	}
}

func TestOnPriceUpdateTriggersOnlyMatchingOrders(t *testing.T) {
	store := newFakeStore()
	client := &fakeOrderClient{}
	svc := NewTriggerService(store, client)

	create := func(triggerType model.TriggerType, triggerPrice float64, side model.OrderSide) {
		_, err := svc.Create(&model.CreateConditionalOrderRequest{
			UserID:       "user-1",
			TriggerType:  triggerType,
			TriggerPrice: triggerPrice,
			OrderSide:    side,
			Amount:       10,
		})
		if err != nil {
			t.Fatalf("Create() error = %v", err)
		}
	}

	create(model.TriggerStopLoss, 90, model.SideSell)    // match when deal <= 90
	create(model.TriggerBuyDip, 75, model.SideBuy)       // no match at 100
	create(model.TriggerTakeProfit, 110, model.SideSell) // no match at 100
	create(model.TriggerBreakout, 100, model.SideBuy)    // match when deal >= 100

	svc.OnPriceUpdate(&model.OrderMatchedEvent{DealPrice: 100})

	if got := len(client.placed); got != 1 {
		t.Fatalf("placed orders = %d, want 1", got)
	}
	if client.placed[0].side != model.SideBuy || client.placed[0].price != 100 {
		t.Fatalf("placed order = %+v, want breakout buy at 100", client.placed[0])
	}
	if got := svc.PendingCount(); got != 3 {
		t.Fatalf("PendingCount() = %d, want 3", got)
	}
}

func TestTriggerOrderClaimPreventsDuplicateInjection(t *testing.T) {
	store := newFakeStore()
	client := &fakeOrderClient{}
	svc := NewTriggerService(store, client)

	order := &model.ConditionalOrder{
		ID:           1,
		UserID:       "user-1",
		TriggerType:  model.TriggerBreakout,
		TriggerPrice: 100,
		OrderSide:    model.SideBuy,
		Amount:       1,
		Status:       model.StatusTriggered,
		CreatedAt:    time.Now(),
	}
	store.orders[1] = order
	svc.pending.add(order)

	svc.OnPriceUpdate(&model.OrderMatchedEvent{DealPrice: 120})

	if got := len(client.placed); got != 0 {
		t.Fatalf("placed orders = %d, want 0 when claim fails", got)
	}
	if got := svc.PendingCount(); got != 0 {
		t.Fatalf("PendingCount() = %d, want stale in-memory order removed", got)
	}
}

func TestTriggerOrderFailureMarksFailedAndRemovesPending(t *testing.T) {
	store := newFakeStore()
	client := &fakeOrderClient{err: errors.New("eap-order unavailable")}
	svc := NewTriggerService(store, client)

	order, err := svc.Create(&model.CreateConditionalOrderRequest{
		UserID:       "user-1",
		TriggerType:  model.TriggerTakeProfit,
		TriggerPrice: 100,
		OrderSide:    model.SideSell,
		Amount:       5,
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	svc.OnPriceUpdate(&model.OrderMatchedEvent{DealPrice: 101})

	if got := store.statuses[order.ID]; got != model.StatusFailed {
		t.Fatalf("status = %s, want FAILED", got)
	}
	if got := svc.PendingCount(); got != 0 {
		t.Fatalf("PendingCount() = %d, want 0", got)
	}
}

func TestLoadPendingOrdersRecoversStaleClaimsAndIndexesPending(t *testing.T) {
	store := newFakeStore()
	store.recovered = 2
	store.orders[1] = &model.ConditionalOrder{ID: 1, UserID: "user-1", TriggerType: model.TriggerBuyDip, TriggerPrice: 80, OrderSide: model.SideBuy, Amount: 1, Status: model.StatusPending}
	store.orders[2] = &model.ConditionalOrder{ID: 2, UserID: "user-1", TriggerType: model.TriggerBreakout, TriggerPrice: 120, OrderSide: model.SideBuy, Amount: 1, Status: model.StatusPending}
	store.orders[3] = &model.ConditionalOrder{ID: 3, UserID: "user-1", TriggerType: model.TriggerBreakout, TriggerPrice: 150, OrderSide: model.SideBuy, Amount: 1, Status: model.StatusTriggered}

	client := &fakeOrderClient{}
	svc := NewTriggerService(store, client)

	if err := svc.LoadPendingOrders(5 * time.Minute); err != nil {
		t.Fatalf("LoadPendingOrders() error = %v", err)
	}
	if store.recoveredCut.IsZero() {
		t.Fatal("RecoverStaleTriggering was not called")
	}
	if got := svc.PendingCount(); got != 2 {
		t.Fatalf("PendingCount() = %d, want 2", got)
	}

	svc.OnPriceUpdate(&model.OrderMatchedEvent{DealPrice: 120})
	gotSides := []model.OrderSide{}
	for _, placed := range client.placed {
		gotSides = append(gotSides, placed.side)
	}
	if !reflect.DeepEqual(gotSides, []model.OrderSide{model.SideBuy}) {
		t.Fatalf("placed sides = %v, want one BUY", gotSides)
	}
}

func TestRecoverStaleClaimsMergesRecoveredOrderWithoutDuplicatingIndex(t *testing.T) {
	store := newFakeStore()
	store.recovered = 1
	store.orders[1] = &model.ConditionalOrder{
		ID:           1,
		UserID:       "user-1",
		TriggerType:  model.TriggerBreakout,
		TriggerPrice: 120,
		OrderSide:    model.SideBuy,
		Amount:       1,
		Status:       model.StatusPending,
	}
	svc := NewTriggerService(store, &fakeOrderClient{})

	for i := 0; i < 2; i++ {
		recovered, err := svc.RecoverStaleClaims(time.Minute)
		if err != nil {
			t.Fatalf("RecoverStaleClaims() error = %v", err)
		}
		if recovered != 1 {
			t.Fatalf("recovered = %d, want 1", recovered)
		}
	}

	if got := svc.PendingCount(); got != 1 {
		t.Fatalf("PendingCount() = %d, want one idempotently indexed order", got)
	}
	if got := len(svc.pending.gtePriceID); got != 1 {
		t.Fatalf("gte index entries = %d, want 1", got)
	}
}

func TestRecoverStaleClaimsRejectsNonPositiveTimeout(t *testing.T) {
	svc := NewTriggerService(newFakeStore(), &fakeOrderClient{})

	if _, err := svc.RecoverStaleClaims(0); err == nil {
		t.Fatal("RecoverStaleClaims() error = nil, want invalid timeout error")
	}
}
