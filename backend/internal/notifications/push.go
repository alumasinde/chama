package notifications

import (
	"context"
	"log/slog"
)

// Message is provider-neutral; notification data is stringified for FCM compatibility.
type Message struct {
	Title string
	Body  string
	Data  map[string]string
}

// Pusher is the boundary that tests mock, so no network call is needed in unit tests.
type Pusher interface {
	Name() string
	Push(ctx context.Context, tokens []string, message Message) error
}

type consolePusher struct {
	log *slog.Logger
}

func (p *consolePusher) Name() string { return "console" }

func (p *consolePusher) Push(ctx context.Context, tokens []string, message Message) error {
	p.log.InfoContext(ctx, "push notification", "provider", "console",
		"devices", len(tokens), "title", message.Title)
	return nil
}

// NewPusher selects the configured provider; console is the safe development default.
func NewPusher(provider, key string, log *slog.Logger) Pusher {
	if provider == "fcm" && key != "" {
		return &fcmPusher{key: key, client: defaultHTTPClient()}
	}
	return &consolePusher{log: log}
}
