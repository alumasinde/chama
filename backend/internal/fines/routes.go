package fines

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts fine routes; callers must already require authentication.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.Route("/groups/{groupID}/fines", func(r chi.Router) {
		r.Use(scope, active)

		r.Get("/rules", h.rules)
		r.With(perm(rbac.PermFineRulesWrite)).Put("/rules/{fineType}", h.putRule)
		r.With(perm(rbac.PermFineEvaluate)).Post("/evaluate", h.evaluate)

		r.Get("/", h.list)
		r.With(perm(rbac.PermFineManage)).Post("/", h.create)
		r.Get("/{fineID}", h.get)
		r.With(perm(rbac.PermFineWaive)).Post("/{fineID}/waive", h.waive)
		r.With(perm(rbac.PermFinePay), stepUp).Post("/{fineID}/pay", h.pay)
	})
}
