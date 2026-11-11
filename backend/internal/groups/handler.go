package groups

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in CreateInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Create(r.Context(), user, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	views, err := h.svc.List(r.Context(), user)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": views})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	view, err := h.svc.Get(r.Context(), scope)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	var in UpdateInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Update(r.Context(), scope, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) join(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in JoinInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.Join(r.Context(), user, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, result)
}

func (h *Handler) InvitePreview(w http.ResponseWriter, r *http.Request) {
	preview, err := h.svc.InvitePreview(r.Context(), chi.URLParam(r, "code"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, preview)
}

func (h *Handler) members(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	members, err := h.svc.Members(r.Context(), scope)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": members})
}

func (h *Handler) updateMember(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	actor, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in MemberUpdateInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	member, err := h.svc.UpdateMember(r.Context(), actor.ID, scope, chi.URLParam(r, "userID"), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, member)
}

func (h *Handler) rotateInvite(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	result, err := h.svc.RotateInvite(r.Context(), scope)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, result)
}

func (h *Handler) getPaymentSettings(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	view, err := h.svc.PaymentSettings(r.Context(), scope)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) putPaymentSettings(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	actor, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in PaymentSettingsInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.PutPaymentSettings(r.Context(), scope, actor.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) verifyPaymentSettings(w http.ResponseWriter, r *http.Request) {
	scope, ok := ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	actor, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.VerifyPaymentSettings(r.Context(), scope, actor.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}
