package loans

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts loan routes; callers must already require authentication.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.Route("/groups/{groupID}/loans", func(r chi.Router) {
		r.Use(scope, active)

		r.Get("/settings", h.settings)
		r.With(perm(rbac.PermLoanSettingsWrite)).Put("/settings", h.putSettings)

		r.Get("/", h.list)
		r.With(stepUp).Post("/", h.apply)
		r.With(perm(rbac.PermLoanManage)).Post("/defaults/run", h.defaults)

		r.Route("/{loanID}", func(r chi.Router) {
			r.Get("/", h.detail)
			r.Get("/schedule", h.schedule)
			r.Post("/guarantors/respond", h.guarantee)
			r.With(perm(rbac.PermLoanManage)).Post("/decision", h.decide)
			r.With(perm(rbac.PermLoanDisburse), stepUp).Post("/disburse", h.disburse)
			r.With(perm(rbac.PermLoanRepay), stepUp).Post("/repayments", h.repay)
		})
	})
}
