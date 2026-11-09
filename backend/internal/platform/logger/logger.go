// Package logger builds the JSON logger and strips secrets and phone numbers.
package logger

import (
	"log/slog"
	"os"
	"strings"

	"github.com/chama/chama/backend/internal/platform/phone"
)

var sensitiveKeys = map[string]bool{
	"password": true, "password_hash": true, "pin": true, "pin_hash": true,
	"token": true, "access_token": true, "refresh_token": true, "authorization": true,
	"secret": true, "otp": true, "code": true, "code_hash": true,
	"consumer_key": true, "consumer_secret": true, "passkey": true, "encryption_key": true,
	"jwt_secret": true, "national_id": true, "national_id_enc": true, "callback_secret": true,
}

func New(level, env string) *slog.Logger {
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level:       parseLevel(level),
		ReplaceAttr: redact,
		AddSource:   env == "development",
	})
	return slog.New(handler)
}

func parseLevel(level string) slog.Level {
	switch strings.ToLower(level) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// redact drops credential fields and masks phone numbers anywhere in a log record.
func redact(groups []string, a slog.Attr) slog.Attr {
	key := strings.ToLower(a.Key)
	if sensitiveKeys[key] {
		return slog.String(a.Key, "[redacted]")
	}
	if key == "phone" || key == "phone_number" {
		if s, ok := a.Value.Any().(string); ok {
			return slog.String(a.Key, phone.Mask(s))
		}
	}
	if a.Value.Kind() == slog.KindString {
		if masked := phone.MaskAll(a.Value.String()); masked != a.Value.String() {
			return slog.String(a.Key, masked)
		}
	}
	return a
}
