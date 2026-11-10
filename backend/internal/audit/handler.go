package audit

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	filter := Filter{
		Action:     r.URL.Query().Get("action"),
		EntityType: r.URL.Query().Get("entity_type"),
		Limit:      limit(r),
	}
	var err error
	if filter.From, err = parseTime(r.URL.Query().Get("from")); err != nil {
		httpx.Fail(w, r, httpx.Validation(map[string]string{"from": "Use an RFC3339 timestamp."}))
		return
	}
	if filter.To, err = parseTime(r.URL.Query().Get("to")); err != nil {
		httpx.Fail(w, r, httpx.Validation(map[string]string{"to": "Use an RFC3339 timestamp."}))
		return
	}
	rows, err := h.svc.List(r.Context(), scope.Group.ID, filter)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": rows})
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	id, err := uuid.Parse(chi.URLParam(r, "auditID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Audit entry not found."))
		return
	}
	view, err := h.svc.Get(r.Context(), scope.Group.ID, id)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

func parseTime(raw string) (*time.Time, error) {
	if raw == "" {
		return nil, nil
	}
	value, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func limit(r *http.Request) int32 {
	raw := r.URL.Query().Get("limit")
	if raw == "" {
		return 100
	}
	value, err := strconv.ParseInt(raw, 10, 32)
	if err != nil || value < 1 || value > 200 {
		return 100
	}
	return int32(value)
}
