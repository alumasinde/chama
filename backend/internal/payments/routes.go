package payments

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// Register mounts the authenticated ledger and STK routes.
func (h *Handler) Register(r chi.Router, scope, active, stepUp func(http.Handler) http.Handler) {
	r.With(scope, active, stepUp).Post("/groups/{groupID}/payments/stk", h.initiateSTK)
	r.With(scope, active).Get("/groups/{groupID}/transactions", h.listTransactions)
	r.With(scope, active).Get("/groups/{groupID}/transactions/{txID}", h.getTransaction)
}
