package payments

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) initiateSTK(w http.ResponseWriter, r *http.Request) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	var in STKInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.InitiateSTK(r.Context(), user, scope.Group, in, key)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusAccepted, result)
}

func (h *Handler) listTransactions(w http.ResponseWriter, r *http.Request) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	limit := int32(25)
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 32)
		if err != nil || parsed < 1 || parsed > 100 {
			httpx.Fail(w, r, httpx.BadRequest("limit must be between 1 and 100."))
			return
		}
		limit = int32(parsed)
	}
	rows, next, err := h.svc.ListTransactions(r.Context(), scope.Group.ID, limit, r.URL.Query().Get("cursor"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{
		"data": rows,
		"page": map[string]any{"next_cursor": next, "has_more": next != ""},
	})
}

func (h *Handler) getTransaction(w http.ResponseWriter, r *http.Request) {
	scope, ok := groups.ScopeFrom(r.Context())
	if !ok {
		httpx.Fail(w, r, httpx.NotFound("Chama not found."))
		return
	}
	publicID, err := uuid.Parse(chi.URLParam(r, "txID"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Transaction not found."))
		return
	}
	view, err := h.svc.GetTransaction(r.Context(), scope.Group.ID, publicID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, view)
}

// Callback is public but authenticated by the per-group secret in the path.
func (h *Handler) Callback(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	err = h.svc.HandleCallback(r.Context(), chi.URLParam(r, "groupID"), chi.URLParam(r, "secret"), raw)
	if err != nil {
		var apiErr *httpx.Error
		if errors.As(err, &apiErr) && apiErr.Status == http.StatusForbidden {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		httpx.LoggerFrom(r.Context()).ErrorContext(r.Context(), "callback failed", "error", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"ResultCode": 0, "ResultDesc": "Accepted"})
}
