package mq

import (
	"encoding/json"
	"fmt"
	"log"

	"eap-trigger/internal/model"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	exchangeName = "order.exchange"
	queueName    = "trigger.orderMatched.queue"
	routingKey   = "order.matched"
)

// PriceHandler is called when a new match event arrives.
type PriceHandler func(event *model.OrderMatchedEvent)

// Consumer listens to order.matched events from RabbitMQ.
type Consumer struct {
	conn    *amqp.Connection
	channel *amqp.Channel
	handler PriceHandler
}

// NewConsumer connects to RabbitMQ, declares the queue, and binds it.
func NewConsumer(amqpURL string, handler PriceHandler) (*Consumer, error) {
	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		return nil, fmt.Errorf("rabbitmq dial: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("rabbitmq channel: %w", err)
	}

	// Declare our queue (idempotent - safe to call even if it exists)
	_, err = ch.QueueDeclare(
		queueName,
		true,  // durable
		false, // auto-delete
		false, // exclusive
		false, // no-wait
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("queue declare: %w", err)
	}

	// Bind to the existing order.exchange with routing key "order.matched"
	err = ch.QueueBind(
		queueName,
		routingKey,
		exchangeName,
		false,
		nil,
	)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("queue bind: %w", err)
	}

	// Prefetch 1: process one message at a time (same pattern as your Java services)
	err = ch.Qos(1, 0, false)
	if err != nil {
		ch.Close()
		conn.Close()
		return nil, fmt.Errorf("qos: %w", err)
	}

	log.Printf("[mq] connected to RabbitMQ, queue=%s bound to %s/%s", queueName, exchangeName, routingKey)

	return &Consumer{
		conn:    conn,
		channel: ch,
		handler: handler,
	}, nil
}

// Start begins consuming messages. Blocks until the channel is closed.
func (c *Consumer) Start() error {
	msgs, err := c.channel.Consume(
		queueName,
		"eap-trigger", // consumer tag
		false,         // auto-ack: false = manual ack
		false,         // exclusive
		false,         // no-local
		false,         // no-wait
		nil,
	)
	if err != nil {
		return fmt.Errorf("consume: %w", err)
	}

	log.Printf("[mq] consumer started, waiting for order.matched events...")

	for msg := range msgs {
		var event model.OrderMatchedEvent
		if err := json.Unmarshal(msg.Body, &event); err != nil {
			log.Printf("[mq] failed to parse message: %v", err)
			msg.Nack(false, false) // discard bad message
			continue
		}

		log.Printf("[mq] received match: dealPrice=%.2f matchId=%d", event.DealPrice, event.MatchID)
		c.handler(&event)
		msg.Ack(false) // manual ack after processing
	}

	return nil
}

// Close shuts down the consumer.
func (c *Consumer) Close() {
	if c.channel != nil {
		c.channel.Close()
	}
	if c.conn != nil {
		c.conn.Close()
	}
}
