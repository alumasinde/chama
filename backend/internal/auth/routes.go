package auth

import (
	"github.com/go-chi/chi/v5"
)

// Routes registers every auth endpoint; protected ones still need the middleware group.
func (h *Handler) Routes(r chi.Router) {
	h.PublicRoutes(r)
	r.Group(func(r chi.Router) {
		h.ProtectedRoutes(r)
	})
}
