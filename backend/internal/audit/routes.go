package audit

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts the audit viewer; callers must already require authentication.
func (h *Handler) Register(r chi.Router, scope, active func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.Route("/groups/{groupID}/audit-logs", func(r chi.Router) {
		r.Use(scope, active, perm(rbac.PermAuditRead))
		r.Get("/", h.list)
		r.Get("/{auditID}", h.get)
	})
}
