package rotation

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/rbac"
	"github.com/chama/chama/backend/internal/users"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) caller(w http.ResponseWriter, r *http.Request) (groups.Scope, users.User, bool) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return groups.Scope{}, users.User{}, false
	}
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return groups.Scope{}, users.User{}, false
	}
	return scope, user, true
}

func (h *Handler) cycles(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	rows, err := h.svc.Cycles(r.Context(), scope.Group.ID, limit(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in CreateInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Create(r.Context(), scope.Group.ID, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) cycle(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "cycleID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation cycle not found."))
		return
	}
	view, err := h.svc.Cycle(r.Context(), scope.Group.ID, id)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) proposals(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "cycleID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation cycle not found."))
		return
	}
	rows, err := h.svc.Proposals(r.Context(), scope.Group.ID, id, limit(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) start(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "cycleID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation cycle not found."))
		return
	}
	view, err := h.svc.Start(r.Context(), scope.Group.ID, id)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) propose(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "cycleID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation cycle not found."))
		return
	}
	var in ProposalInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Propose(r.Context(), scope.Group.ID, id, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) proposal(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "proposalID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation proposal not found."))
		return
	}
	view, err := h.svc.Proposal(r.Context(), scope.Group.ID, id, user.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) vote(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "proposalID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation proposal not found."))
		return
	}
	var in VoteInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Vote(r.Context(), scope.Group.ID, id, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) close(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "proposalID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation proposal not found."))
		return
	}
	view, err := h.svc.Close(r.Context(), scope.Group.ID, id, user.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) payout(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "cycleID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Rotation cycle not found."))
		return
	}
	var in PayoutInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.Payout(r.Context(), scope.Group.ID, id, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, result)
}

func (h *Handler) myRotation(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	rows, err := h.svc.MyRotation(r.Context(), user.ID, limit(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func limit(r *http.Request) int32 {
	raw := r.URL.Query().Get("limit")
	if raw == "" {
		return 50
	}
	value, err := strconv.ParseInt(raw, 10, 32)
	if err != nil || value < 1 || value > 100 {
		return 50
	}
	return int32(value)
}

var _ = rbac.Allows
