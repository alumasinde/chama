package fines

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

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

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

func (h *Handler) rules(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	rows, err := h.svc.Rules(r.Context(), scope.Group.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) putRule(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in RuleInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	rows, err := h.svc.PutRule(r.Context(), scope.Group.ID, chi.URLParam(r, "fineType"), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	limit := int32(50)
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || parsed < 1 || parsed > 100 {
			httpx.Fail(w, r, httpx.BadRequest("limit must be between 1 and 100."))
			return
		}
		limit = int32(parsed)
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermFineManage)
	rows, err := h.svc.List(r.Context(), scope.Group.ID, user.ID, manager,
		r.URL.Query().Get("status"), limit)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in CreateInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Create(r.Context(), scope.Group.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "fineID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Fine not found."))
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermFineManage)
	view, err := h.svc.Get(r.Context(), scope.Group.ID, publicID, user.ID, manager)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) waive(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "fineID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Fine not found."))
		return
	}
	var in WaiveInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Waive(r.Context(), scope.Group.ID, publicID, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) pay(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "fineID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Fine not found."))
		return
	}
	var in PayInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.Pay(r.Context(), scope.Group.ID, publicID, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, result)
}

func (h *Handler) evaluate(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	created, err := h.svc.EvaluateGroup(r.Context(), scope.Group.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"fines_created": created})
}
