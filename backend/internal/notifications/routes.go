package notifications

import "github.com/go-chi/chi/v5"

// Register mounts user-scoped notification routes; authentication is already required.
func (h *Handler) Register(r chi.Router) {
	r.Get("/notifications", h.list)
	r.Post("/notifications/read", h.read)
}
