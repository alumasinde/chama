// Package scheduler runs in-process daily jobs without an external queue.
package scheduler

import (
	"context"
	"log/slog"
	"time"
)

// Daily runs fn at hour:minute in loc every day until ctx is cancelled.
// A failed run is logged and the next day still runs.
func Daily(ctx context.Context, log *slog.Logger, name string, hour, minute int, loc *time.Location,
	fn func(context.Context) error) {
	go func() {
		for {
			now := time.Now().In(loc)
			next := time.Date(now.Year(), now.Month(), now.Day(), hour, minute, 0, 0, loc)
			if !next.After(now) {
				next = next.AddDate(0, 0, 1)
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Until(next)):
			}
			if err := fn(ctx); err != nil {
				log.ErrorContext(ctx, "scheduled job failed", "job", name, "error", err)
			}
		}
	}()
}
