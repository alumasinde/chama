package auth

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
)

// SMS is the provider seam; a real gateway replaces the console in production.
type SMS interface {
	Send(ctx context.Context, phoneNumber, message string) error
}

type consoleSMS struct {
	log *slog.Logger
}

// Send logs in development only; the logger masks phone numbers.
func (c *consoleSMS) Send(ctx context.Context, phoneNumber, message string) error {
	c.log.InfoContext(ctx, "sms outbox", "to", phoneNumber, "message", message)
	return nil
}

type MockSMS struct {
	mu      sync.Mutex
	LastTo  string
	LastMsg string
}

func (m *MockSMS) Send(ctx context.Context, phoneNumber, message string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.LastTo, m.LastMsg = phoneNumber, message
	return nil
}

func NewSMS(provider string, log *slog.Logger) (SMS, error) {
	switch provider {
	case "console":
		return &consoleSMS{log: log}, nil
	case "mock":
		return &MockSMS{}, nil
	default:
		return nil, fmt.Errorf("SMS provider %q is not supported", provider)
	}
}
