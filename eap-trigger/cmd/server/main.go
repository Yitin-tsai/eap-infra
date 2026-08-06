package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"eap-trigger/internal/config"
	"eap-trigger/internal/handler"
	"eap-trigger/internal/mq"
	"eap-trigger/internal/orderclient"
	"eap-trigger/internal/service"

	_ "github.com/lib/pq" // PostgreSQL driver
)

func main() {
	cfg := config.Load()

	// 1. Connect to PostgreSQL
	db, err := sql.Open("postgres", cfg.PostgresURL)
	if err != nil {
		log.Fatalf("failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping PostgreSQL: %v", err)
	}
	log.Println("[main] connected to PostgreSQL")

	// 2. Initialize schema (auto-create table)
	store := service.NewStore(db)
	if err := store.InitSchema(); err != nil {
		log.Fatalf("failed to initialize schema: %v", err)
	}
	log.Println("[main] schema initialized")

	// 3. Build service layer
	orderClient := orderclient.New(cfg.OrderServiceURL)
	triggerSvc := service.NewTriggerService(store, orderClient)

	// 4. Restore pending orders from DB (survive restarts)
	if err := triggerSvc.LoadPendingOrders(cfg.TriggerClaimTimeout); err != nil {
		log.Fatalf("failed to load pending orders: %v", err)
	}
	recoveryContext, stopRecovery := context.WithCancel(context.Background())
	defer stopRecovery()
	go runTriggerClaimRecovery(
		recoveryContext,
		triggerSvc,
		cfg.TriggerRecoveryInterval,
		cfg.TriggerClaimTimeout)

	// 5. Start RabbitMQ consumer (in a goroutine)
	consumer, err := mq.NewConsumer(cfg.RabbitMQURL, triggerSvc.OnPriceUpdate)
	if err != nil {
		log.Fatalf("failed to create MQ consumer: %v", err)
	}
	defer consumer.Close()

	go func() {
		if err := consumer.Start(); err != nil {
			log.Printf("[main] MQ consumer stopped: %v", err)
		}
	}()

	// 6. Start HTTP server
	mux := http.NewServeMux()
	h := handler.New(triggerSvc)
	h.RegisterRoutes(mux)

	server := &http.Server{
		Addr:    ":" + cfg.ServerPort,
		Handler: mux,
	}

	// 7. Graceful shutdown
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("[main] shutting down...")
		stopRecovery()
		consumer.Close()
		server.Close()
	}()

	log.Printf("[main] eap-trigger starting on :%s", cfg.ServerPort)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
	log.Println("[main] stopped")
}

func runTriggerClaimRecovery(
	ctx context.Context,
	triggerSvc *service.TriggerService,
	interval time.Duration,
	claimTimeout time.Duration,
) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := triggerSvc.RecoverStaleClaims(claimTimeout); err != nil {
				log.Printf("[main] trigger claim recovery failed: %v", err)
			}
		}
	}
}
