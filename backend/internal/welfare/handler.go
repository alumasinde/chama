package welfare

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

func (h *Handler) fund(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	view, err := h.svc.Fund(r.Context(), scope.Group.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) saveFund(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in FundInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.SaveFund(r.Context(), scope.Group.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) contributions(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermWelfareManage)
	rows, err := h.svc.Contributions(r.Context(), scope.Group.ID, user.ID, manager, limit(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) contribute(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in ContributionInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Contribute(r.Context(), scope.Group.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) claims(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermWelfareManage)
	rows, err := h.svc.Claims(r.Context(), scope.Group.ID, user.ID, manager,
		r.URL.Query().Get("status"), limit(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) createClaim(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in ClaimInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.CreateClaim(r.Context(), scope.Group.ID, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) claim(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "claimID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Welfare claim not found."))
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermWelfareManage)
	view, err := h.svc.GetClaim(r.Context(), scope.Group.ID, id, user.ID, manager)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) decide(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "claimID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Welfare claim not found."))
		return
	}
	var in ClaimDecisionInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.DecideClaim(r.Context(), scope.Group.ID, id, user.ID, in)
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
	id, err := uuid.Parse(chi.URLParam(r, "claimID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Welfare claim not found."))
		return
	}
	var in ClaimPayoutInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.PayoutClaim(r.Context(), scope.Group.ID, id, user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, result)
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
