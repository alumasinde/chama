// Package routes mounts every module and the embedded web app.
package routes

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/audit"
	"github.com/chama/chama/backend/internal/auth"
	"github.com/chama/chama/backend/internal/config"
	"github.com/chama/chama/backend/internal/fines"
	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/loans"
	"github.com/chama/chama/backend/internal/notifications"
	"github.com/chama/chama/backend/internal/payments"
	"github.com/chama/chama/backend/internal/platform/brand"
	"github.com/chama/chama/backend/internal/platform/db"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/reports"
	"github.com/chama/chama/backend/internal/rotation"
	"github.com/chama/chama/backend/internal/users"
	"github.com/chama/chama/backend/internal/web"
	"github.com/chama/chama/backend/internal/welfare"
)

type Deps struct {
	Config               *config.Config
	Log                  *slog.Logger
	Pool                 *pgxpool.Pool
	Auth                 *auth.Service
	AuthHandler          *auth.Handler
	UsersHandler         *users.Handler
	Groups               *groups.Service
	GroupsHandler        *groups.Handler
	PaymentsHandler      *payments.Handler
	FinesHandler         *fines.Handler
	LoansHandler         *loans.Handler
	WelfareHandler       *welfare.Handler
	RotationHandler      *rotation.Handler
	NotificationsHandler *notifications.Handler
	ReportsHandler       *reports.Handler
	AuditHandler         *audit.Handler
}

func New(d Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(httpx.WithRequestID)
	r.Use(httpx.AccessLog(d.Log, d.Config.TrustProxy))
	r.Use(httpx.Recoverer)
	r.Use(httpx.SecureHeaders)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.Respond(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	r.Get("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if err := db.Ping(ctx, d.Pool); err != nil {
			httpx.Fail(w, r, httpx.NewError(http.StatusServiceUnavailable, "not_ready", "Database is not ready."))
			return
		}
		httpx.Respond(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/meta", metaHandler)
		r.Get("/invites/{code}", d.GroupsHandler.InvitePreview)
		r.Post("/payments/mpesa/callback/{groupID}/{secret}", d.PaymentsHandler.Callback)
		d.AuthHandler.PublicRoutes(r)
		r.Group(func(r chi.Router) {
			r.Use(d.Auth.Middleware)
			d.AuthHandler.ProtectedRoutes(r)
			d.UsersHandler.Register(r)
			d.GroupsHandler.Register(r)
			d.PaymentsHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Auth.RequireStepUp, d.Groups.RequirePermission)
			d.FinesHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Auth.RequireStepUp, d.Groups.RequirePermission)
			d.LoansHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Auth.RequireStepUp, d.Groups.RequirePermission)
			d.WelfareHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Auth.RequireStepUp, d.Groups.RequirePermission)
			d.RotationHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Auth.RequireStepUp, d.Groups.RequirePermission)
			d.RotationHandler.RegisterMe(r)
			d.NotificationsHandler.Register(r)
			d.ReportsHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Groups.RequirePermission)
			d.AuditHandler.Register(r, d.Groups.GroupScope, d.Groups.RequireActive, d.Groups.RequirePermission)
		})
	})

	spa := web.New()
	r.NotFound(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			httpx.Fail(w, r, httpx.NotFound("Endpoint not found."))
			return
		}
		spa.ServeHTTP(w, r)
	})
	return r
}

// metaHandler lets both clients read branding at runtime, so a rename needs no release.
func metaHandler(w http.ResponseWriter, r *http.Request) {
	httpx.Respond(w, http.StatusOK, map[string]any{
		"app_name":      brand.AppName,
		"short_name":    brand.ShortName,
		"currency":      brand.Currency,
		"locale":        brand.Locale,
		"primary_color": brand.PrimaryColor,
		"accent_color":  brand.AccentColor,
		"support_email": brand.SupportEmail,
		"features":      []string{},
		"api_version":   "v1",
		"server_time":   time.Now().UTC(),
	})
}
