// Package notifications stores in-app events and pushes them through a provider interface.
package notifications

import (
	"context"
	"time"
)

// Event is one domain fact that should create exactly one notification per user.
type Event struct {
	UserID    int64
	GroupID   *int64
	Type      string
	Title     string
	Body      string
	Data      map[string]any
	DedupeKey string
}

// Notifier is the small surface other modules depend on, which keeps tests simple.
type Notifier interface {
	Notify(ctx context.Context, event Event) error
}

type View struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	Title     string         `json:"title"`
	Body      string         `json:"body"`
	Data      map[string]any `json:"data"`
	ReadAt    *time.Time     `json:"read_at"`
	CreatedAt time.Time      `json:"created_at"`
}

type ListResult struct {
	Data        []View `json:"data"`
	UnreadCount int64  `json:"unread_count"`
}

type ReadInput struct {
	IDs []string `json:"ids"`
	All bool     `json:"all"`
}
