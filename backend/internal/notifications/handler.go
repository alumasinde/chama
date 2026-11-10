package notifications

import (
	"net/http"
	"strconv"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
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
	out, err := h.svc.List(r.Context(), user.ID, r.URL.Query().Get("unread") == "true", limit)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, out)
}

func (h *Handler) read(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in ReadInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	changed, err := h.svc.MarkRead(r.Context(), user.ID, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"marked_read": changed})
}
