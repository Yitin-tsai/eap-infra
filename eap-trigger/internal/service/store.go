package service

import (
	"database/sql"
	"eap-trigger/internal/model"
	"fmt"
	"time"
)

// Store handles all database operations for conditional orders.
type Store struct {
	db *sql.DB
}

func NewStore(db *sql.DB) *Store {
	return &Store{db: db}
}

type migration struct {
	id         string
	statements []string
}

var migrations = []migration{
	{
		id: "001_create_conditional_orders",
		statements: []string{
			`CREATE TABLE IF NOT EXISTS trigger_service.conditional_orders (
				id            BIGSERIAL PRIMARY KEY,
				user_id       VARCHAR(36)  NOT NULL,
				trigger_type  VARCHAR(20)  NOT NULL,
				trigger_price DOUBLE PRECISION NOT NULL,
				order_side    VARCHAR(4)   NOT NULL,
				amount        INT          NOT NULL,
				status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
				claimed_at    TIMESTAMP,
				triggered_at  TIMESTAMP,
				created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
			)`,
			`ALTER TABLE trigger_service.conditional_orders
			 ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMP`,
		},
	},
	{
		id: "002_create_conditional_order_indexes",
		statements: []string{
			`CREATE INDEX IF NOT EXISTS idx_co_status
			 ON trigger_service.conditional_orders (status)`,
			`CREATE INDEX IF NOT EXISTS idx_co_status_type_price
			 ON trigger_service.conditional_orders (status, trigger_type, trigger_price)`,
		},
	},
}

// InitSchema applies lightweight versioned migrations for the trigger service.
func (s *Store) InitSchema() error {
	if _, err := s.db.Exec(`CREATE SCHEMA IF NOT EXISTS trigger_service`); err != nil {
		return fmt.Errorf("init schema: %w", err)
	}
	if _, err := s.db.Exec(`CREATE TABLE IF NOT EXISTS trigger_service.schema_migrations (
		id         VARCHAR(100) PRIMARY KEY,
		applied_at TIMESTAMP NOT NULL DEFAULT NOW()
	)`); err != nil {
		return fmt.Errorf("init migration table: %w", err)
	}
	for _, m := range migrations {
		if err := s.applyMigration(m); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) applyMigration(m migration) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin migration %s: %w", m.id, err)
	}
	defer tx.Rollback()

	var exists bool
	if err := tx.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM trigger_service.schema_migrations WHERE id = $1)`,
		m.id,
	).Scan(&exists); err != nil {
		return fmt.Errorf("check migration %s: %w", m.id, err)
	}
	if exists {
		return nil
	}

	for _, statement := range m.statements {
		if _, err := tx.Exec(statement); err != nil {
			return fmt.Errorf("apply migration %s: %w", m.id, err)
		}
	}
	if _, err := tx.Exec(
		`INSERT INTO trigger_service.schema_migrations (id) VALUES ($1)`,
		m.id,
	); err != nil {
		return fmt.Errorf("record migration %s: %w", m.id, err)
	}
	return tx.Commit()
}

// Insert creates a new conditional order and returns its ID.
func (s *Store) Insert(o *model.ConditionalOrder) (int64, error) {
	var id int64
	err := s.db.QueryRow(
		`INSERT INTO trigger_service.conditional_orders
			(user_id, trigger_type, trigger_price, order_side, amount, status, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id`,
		o.UserID, o.TriggerType, o.TriggerPrice, o.OrderSide, o.Amount, o.Status, o.CreatedAt,
	).Scan(&id)
	return id, err
}

// FindAllPending returns all orders with status PENDING.
func (s *Store) FindAllPending() ([]model.ConditionalOrder, error) {
	rows, err := s.db.Query(
		`SELECT id, user_id, trigger_type, trigger_price, order_side, amount, status, triggered_at, created_at
		 FROM trigger_service.conditional_orders
		 WHERE status = 'PENDING'
		 ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orders []model.ConditionalOrder
	for rows.Next() {
		var o model.ConditionalOrder
		if err := rows.Scan(&o.ID, &o.UserID, &o.TriggerType, &o.TriggerPrice,
			&o.OrderSide, &o.Amount, &o.Status, &o.TriggeredAt, &o.CreatedAt); err != nil {
			return nil, err
		}
		orders = append(orders, o)
	}
	return orders, rows.Err()
}

// FindByID returns a single conditional order.
func (s *Store) FindByID(id int64) (*model.ConditionalOrder, error) {
	o := &model.ConditionalOrder{}
	err := s.db.QueryRow(
		`SELECT id, user_id, trigger_type, trigger_price, order_side, amount, status, triggered_at, created_at
		 FROM trigger_service.conditional_orders
		 WHERE id = $1`, id,
	).Scan(&o.ID, &o.UserID, &o.TriggerType, &o.TriggerPrice,
		&o.OrderSide, &o.Amount, &o.Status, &o.TriggeredAt, &o.CreatedAt)
	if err != nil {
		return nil, err
	}
	return o, nil
}

// FindByUserID returns all orders for a user.
func (s *Store) FindByUserID(userID string) ([]model.ConditionalOrder, error) {
	rows, err := s.db.Query(
		`SELECT id, user_id, trigger_type, trigger_price, order_side, amount, status, triggered_at, created_at
		 FROM trigger_service.conditional_orders
		 WHERE user_id = $1
		 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orders []model.ConditionalOrder
	for rows.Next() {
		var o model.ConditionalOrder
		if err := rows.Scan(&o.ID, &o.UserID, &o.TriggerType, &o.TriggerPrice,
			&o.OrderSide, &o.Amount, &o.Status, &o.TriggeredAt, &o.CreatedAt); err != nil {
			return nil, err
		}
		orders = append(orders, o)
	}
	return orders, rows.Err()
}

// UpdateStatus sets the status (and triggered_at if triggered).
func (s *Store) UpdateStatus(id int64, status model.Status) error {
	var triggeredAt *time.Time
	if status == model.StatusTriggered {
		now := time.Now()
		triggeredAt = &now
	}
	_, err := s.db.Exec(
		`UPDATE trigger_service.conditional_orders
		 SET status = $1,
		     triggered_at = $2,
		     claimed_at = CASE WHEN $1 = 'TRIGGERING' THEN claimed_at ELSE NULL END
		 WHERE id = $3`,
		status, triggeredAt, id)
	return err
}

// CancelByID cancels a pending order. Returns false if not found or not pending.
func (s *Store) CancelByID(id int64) (bool, error) {
	res, err := s.db.Exec(
		`UPDATE trigger_service.conditional_orders
		 SET status = 'CANCELLED'
		 WHERE id = $1 AND status = 'PENDING'`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ClaimForTrigger moves a PENDING order into TRIGGERING so only one worker can inject it.
func (s *Store) ClaimForTrigger(id int64) (bool, error) {
	res, err := s.db.Exec(
		`UPDATE trigger_service.conditional_orders
		 SET status = 'TRIGGERING', claimed_at = NOW()
		 WHERE id = $1 AND status = 'PENDING'`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// RecoverStaleTriggering resets trigger claims that have been stuck too long.
func (s *Store) RecoverStaleTriggering(before time.Time) (int64, error) {
	res, err := s.db.Exec(
		`UPDATE trigger_service.conditional_orders
		 SET status = 'PENDING', claimed_at = NULL
		 WHERE status = 'TRIGGERING' AND claimed_at IS NOT NULL AND claimed_at < $1`,
		before)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return n, nil
}
