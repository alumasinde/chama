package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

// Middleware authenticates a Bearer access token and loads the caller.
func (s *Service) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw := bearerToken(r)
		if raw == "" {
			httpx.Fail(w, r, httpx.Unauthorized("Sign in to continue."))
			return
		}
		claims, err := s.tokens.Parse(raw, AudienceAPI)
		if err != nil {
			httpx.Fail(w, r, httpx.Unauthorized("Session expired. Sign in again."))
			return
		}
		user, err := s.users.Get(r.Context(), claims.Subject)
		if errors.Is(err, users.ErrNotFound) {
			httpx.Fail(w, r, httpx.Unauthorized("Sign in to continue."))
			return
		}
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		if !user.IsActive {
			httpx.Fail(w, r, httpx.Forbidden("This account is disabled."))
			return
		}
		sessionID, _ := uuid.Parse(claims.SessionID)
		ctx := users.WithUser(r.Context(), user)
		ctx = withSession(ctx, sessionID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	prefix, value, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(prefix, "Bearer") {
		return ""
	}
	return strings.TrimSpace(value)
}

// MustSession returns the session from context for logout and step-up signing.
func MustSession(ctx context.Context) (uuid.UUID, error) {
	id := SessionFrom(ctx)
	if id == uuid.Nil {
		return uuid.Nil, httpx.Unauthorized("Sign in to continue.")
	}
	return id, nil
}
