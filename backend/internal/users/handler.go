package users

import (
	"net/http"

	"github.com/chama/chama/backend/internal/platform/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) getMe(w http.ResponseWriter, r *http.Request) {
	user, err := MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"user": user.View()})
}

func (h *Handler) updateMe(w http.ResponseWriter, r *http.Request) {
	user, err := MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in UpdateProfileInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	updated, err := h.svc.UpdateProfile(r.Context(), user, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"user": updated.View()})
}
