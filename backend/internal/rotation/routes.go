package rotation

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts rotation routes; callers must already require authentication.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.Route("/groups/{groupID}/rotation", func(r chi.Router) {
		r.Use(scope, active)

		r.Get("/cycles", h.cycles)
		r.With(perm(rbac.PermRotationManage)).Post("/cycles", h.create)
		r.Get("/cycles/{cycleID}", h.cycle)
		r.With(perm(rbac.PermRotationManage)).Post("/cycles/{cycleID}/start", h.start)
		r.Get("/cycles/{cycleID}/proposals", h.proposals)
		r.With(perm(rbac.PermRotationManage)).Post("/cycles/{cycleID}/proposals", h.propose)
		r.With(perm(rbac.PermRotationManage), stepUp).Post("/cycles/{cycleID}/payouts", h.payout)

		r.Get("/proposals/{proposalID}", h.proposal)
		r.Post("/proposals/{proposalID}/vote", h.vote)
		r.With(perm(rbac.PermRotationManage)).Post("/proposals/{proposalID}/close", h.close)
	})
}

// RegisterMe mounts the cross-group member view.
func (h *Handler) RegisterMe(r chi.Router) {
	r.Get("/me/rotation", h.myRotation)
}
