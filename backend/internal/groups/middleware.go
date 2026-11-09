package groups

import (
	"context"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/rbac"
	"github.com/chama/chama/backend/internal/users"
)

type ctxKey int

const scopeKey ctxKey = iota

type Scope struct {
	Group      Group
	Membership Membership
}

func ScopeFrom(ctx context.Context) (Scope, bool) {
	s, ok := ctx.Value(scopeKey).(Scope)
	return s, ok
}

// GroupScope resolves the chama from its public id and hides it from non-members.
func (s *Service) GroupScope(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		publicID, err := uuid.Parse(chi.URLParam(r, "groupID"))
		if err != nil {
			httpx.Fail(w, r, httpx.NotFound("Chama not found."))
			return
		}
		group, err := s.repo.GetByPublicID(r.Context(), publicID)
		if errors.Is(err, ErrNotFound) {
			httpx.Fail(w, r, httpx.NotFound("Chama not found."))
			return
		}
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		user, err := users.MustUser(r.Context())
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		membership, err := s.repo.Membership(r.Context(), group.ID, user.ID)
		if errors.Is(err, ErrNotFound) {
			httpx.Fail(w, r, httpx.NotFound("Chama not found."))
			return
		}
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		ctx := context.WithValue(r.Context(), scopeKey, Scope{Group: group, Membership: membership})
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequireActive blocks pending, suspended and exited members from acting.
func (s *Service) RequireActive(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		scope, ok := ScopeFrom(r.Context())
		if !ok {
			httpx.Fail(w, r, httpx.NotFound("Chama not found."))
			return
		}
		switch scope.Membership.Status {
		case "active":
			next.ServeHTTP(w, r)
		case "pending":
			httpx.Fail(w, r, httpx.NewError(http.StatusForbidden, "membership_pending",
				"Your request to join is waiting for an admin."))
		default:
			httpx.Fail(w, r, httpx.Forbidden("This membership is no longer active."))
		}
	})
}

func (s *Service) RequirePermission(permission string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			scope, ok := ScopeFrom(r.Context())
			if !ok {
				httpx.Fail(w, r, httpx.NotFound("Chama not found."))
				return
			}
			if !rbac.Allows(scope.Membership.Role, permission) {
				httpx.Fail(w, r, httpx.Forbidden("You do not have permission to do that."))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
