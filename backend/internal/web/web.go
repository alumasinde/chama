// Package web serves the embedded Svelte build with SPA fallback.
package web

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"

	"github.com/chama/chama/backend/internal/platform/httpx"
)

//go:embed all:dist
var embedded embed.FS

type Handler struct {
	fsys     fs.FS
	files    http.Handler
	index    []byte
	hasIndex bool
}

func New() *Handler {
	h := &Handler{}
	sub, err := fs.Sub(embedded, "dist")
	if err != nil {
		return h
	}
	h.fsys = sub
	h.files = http.FileServer(http.FS(sub))
	if index, err := fs.ReadFile(sub, "index.html"); err == nil {
		h.index, h.hasIndex = index, true
	}
	return h
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(r.URL.Path, "/api/") {
		httpx.Fail(w, r, httpx.NotFound("Endpoint not found."))
		return
	}
	clean := path.Clean(r.URL.Path)
	if h.fsys != nil && clean != "/" {
		if info, err := fs.Stat(h.fsys, strings.TrimPrefix(clean, "/")); err == nil && !info.IsDir() {
			if strings.HasPrefix(clean, "/assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			}
			h.files.ServeHTTP(w, r)
			return
		}
	}
	if !h.hasIndex {
		httpx.Fail(w, r, httpx.NewError(http.StatusServiceUnavailable, "web_not_built",
			"The web dashboard has not been built yet. Run make build."))
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Content-Security-Policy",
		"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self'")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(h.index)
}
