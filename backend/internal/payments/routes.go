package payments

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts the authenticated ledger, STK, setup test and manual payment routes.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler,
	perm func(string) func(http.Handler) http.Handler) {
	r.With(scope, active, stepUp).Post("/groups/{groupID}/payments/stk", h.initiateSTK)
	r.With(scope, active, stepUp, perm(rbac.PermPaymentSettingsWrite)).
		Post("/groups/{groupID}/payments/test", h.sendTest)
	r.With(scope, active, stepUp, perm(rbac.PermPaymentRecord)).
		Post("/groups/{groupID}/payments/manual", h.recordManual)
	r.With(scope, active).Get("/groups/{groupID}/transactions", h.listTransactions)
	r.With(scope, active).Get("/groups/{groupID}/transactions/{txID}", h.getTransaction)
}
