package httpx

import (
	"encoding/json"
	"errors"
	"net/http"
)

type errorBody struct {
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields,omitempty"`
}

type envelope struct {
	Error errorBody `json:"error"`
}

// Respond writes a JSON body with no-store caching for personalised data.
func Respond(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	_ = json.NewEncoder(w).Encode(v)
}

func NoContent(w http.ResponseWriter) {
	w.WriteHeader(http.StatusNoContent)
}

// Fail renders any error as the shared envelope and logs 5xx with the request id.
func Fail(w http.ResponseWriter, r *http.Request, err error) {
	var e *Error
	if !errors.As(err, &e) {
		e = Internal(err)
	}
	if e.Status >= http.StatusInternalServerError {
		LoggerFrom(r.Context()).ErrorContext(r.Context(), "request failed",
			"code", e.Code, "error", err, "path", r.URL.Path)
	}
	Respond(w, e.Status, envelope{Error: errorBody{Code: e.Code, Message: e.Message, Fields: e.Fields}})
}
