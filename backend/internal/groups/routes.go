package groups

import (
	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/rbac"
)

// Register mounts group routes; callers must already require authentication.
func (h *Handler) Register(r chi.Router) {
	r.Route("/groups", func(r chi.Router) {
		r.Post("/", h.create)
		r.Get("/", h.list)
		r.Post("/join", h.join)

		r.Route("/{groupID}", func(r chi.Router) {
			r.Use(h.svc.GroupScope)
			r.Get("/", h.get)

			r.Group(func(r chi.Router) {
				r.Use(h.svc.RequireActive)
				r.Get("/members", h.members)

				r.Group(func(r chi.Router) {
					r.Use(h.svc.RequirePermission(rbac.PermPaymentSettingsRead))
					r.Get("/payment-settings", h.getPaymentSettings)
				})

				r.Group(func(r chi.Router) {
					r.Use(h.svc.RequirePermission(rbac.PermPaymentSettingsWrite))
					r.Put("/payment-settings", h.putPaymentSettings)
					r.Post("/payment-settings/verify", h.verifyPaymentSettings)
				})

				r.Group(func(r chi.Router) {
					r.Use(h.svc.RequirePermission(rbac.PermMemberManage))
					r.Patch("/", h.update)
					r.Patch("/members/{userID}", h.updateMember)
					r.Post("/invites/rotate", h.rotateInvite)
				})
			})
		})
	})
}
