package users

import (
	"github.com/go-chi/chi/v5"
)

// Routes registers the profile endpoints; the caller applies auth middleware.
func (h *Handler) Register(r chi.Router) {
	r.Get("/me", h.getMe)
	r.Patch("/me", h.updateMe)
}
