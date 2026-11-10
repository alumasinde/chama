package welfare

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts welfare routes; callers must already require authentication.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.Route("/groups/{groupID}/welfare", func(r chi.Router) {
		r.Use(scope, active)

		r.Get("/", h.fund)
		r.With(perm(rbac.PermWelfareManage)).Put("/", h.saveFund)

		r.Get("/contributions", h.contributions)
		r.With(perm(rbac.PermWelfareContribute), stepUp).Post("/contributions", h.contribute)

		r.Get("/claims", h.claims)
		r.Post("/claims", h.createClaim)
		r.Get("/claims/{claimID}", h.claim)
		r.With(perm(rbac.PermWelfareManage)).Post("/claims/{claimID}/decision", h.decide)
		r.With(perm(rbac.PermWelfareManage), stepUp).Post("/claims/{claimID}/payout", h.payout)
	})
}
