package loans

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

func (h *Handler) settings(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	view, err := h.svc.Settings(r.Context(), scope.Group.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) putSettings(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in SettingsInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.PutSettings(r.Context(), scope.Group.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) apply(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	var in ApplyInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Apply(r.Context(), scope, user, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
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
	manager := rbac.Allows(scope.Membership.Role, rbac.PermLoanManage)
	rows, err := h.svc.List(r.Context(), scope.Group.ID, user.ID, manager, r.URL.Query().Get("status"), limit)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) detail(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermLoanManage)
	view, err := h.svc.Detail(r.Context(), scope.Group.ID, publicID, user.ID, manager)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) schedule(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	manager := rbac.Allows(scope.Membership.Role, rbac.PermLoanManage)
	rows, err := h.svc.Schedule(r.Context(), scope.Group.ID, publicID, user.ID, manager)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) guarantee(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	var in GuaranteeDecisionInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.GuaranteeDecision(r.Context(), scope, user, publicID, in)
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
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	var in DecisionInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Decide(r.Context(), scope, user, publicID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) disburse(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	var in DisburseInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Disburse(r.Context(), scope, user, publicID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func (h *Handler) repay(w http.ResponseWriter, r *http.Request) {
	scope, user, ok := h.caller(w, r)
	if !ok {
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "loanID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Loan not found."))
		return
	}
	var in RepaymentInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	view, err := h.svc.Repay(r.Context(), scope, user, publicID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, view)
}

func (h *Handler) defaults(w http.ResponseWriter, r *http.Request) {
	scope, _, ok := h.caller(w, r)
	if !ok {
		return
	}
	marked, err := h.svc.Defaults(r.Context(), scope.Group.ID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"marked_defaulted": marked})
}
