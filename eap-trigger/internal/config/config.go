package config

import (
	"log"
	"os"
	"time"
)

type Config struct {
	ServerPort              string
	RabbitMQURL             string
	OrderServiceURL         string
	PostgresURL             string
	TriggerClaimTimeout     time.Duration
	TriggerRecoveryInterval time.Duration
}

func Load() *Config {
	return &Config{
		ServerPort:              getEnv("SERVER_PORT", "8085"),
		RabbitMQURL:             getEnv("RABBITMQ_URL", "amqp://admin:admin123@localhost:5672/"),
		OrderServiceURL:         getEnv("ORDER_SERVICE_URL", "http://localhost:8080/eap-order"),
		PostgresURL:             getEnv("POSTGRES_URL", "postgres://admin:admin123@localhost:5432/eapdb?sslmode=disable&search_path=trigger_service"),
		TriggerClaimTimeout:     getDurationEnv("TRIGGER_CLAIM_TIMEOUT", 5*time.Minute),
		TriggerRecoveryInterval: getDurationEnv("TRIGGER_RECOVERY_INTERVAL", 30*time.Second),
	}
}

func getDurationEnv(key string, fallback time.Duration) time.Duration {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		log.Printf("[config] invalid %s=%q; using %s", key, raw, fallback)
		return fallback
	}
	return value
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
