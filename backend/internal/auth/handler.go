package auth

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

type Handler struct {
	svc        *Service
	trustProxy bool
}

func NewHandler(svc *Service, trustProxy bool) *Handler {
	return &Handler{svc: svc, trustProxy: trustProxy}
}

// PublicRoutes registers unauthenticated auth endpoints.
func (h *Handler) PublicRoutes(r chi.Router) {
	r.Post("/auth/otp/request", h.requestOTP)
	r.Post("/auth/otp/verify", h.verifyOTP)
	r.Post("/auth/register", h.register)
	r.Post("/auth/login", h.login)
	r.Post("/auth/pin/reset", h.resetPIN)
	r.Post("/auth/token/refresh", h.refresh)
}

// ProtectedRoutes must be mounted behind Service.Middleware.
func (h *Handler) ProtectedRoutes(r chi.Router) {
	r.Post("/auth/logout", h.logout)
	r.Post("/auth/pin/verify", h.verifyPIN)
	r.Post("/me/pin", h.changePIN)
	r.Post("/me/password", h.setPassword)
	r.Get("/me/devices", h.listDevices)
	r.Post("/me/devices", h.createDevice)
	r.Delete("/me/devices/{deviceID}", h.deleteDevice)
}

func (h *Handler) meta(r *http.Request) clientMeta {
	return clientMeta{
		userAgent: r.UserAgent(),
		ip:        httpx.ClientIP(r, h.trustProxy),
	}
}

func (h *Handler) requestOTP(w http.ResponseWriter, r *http.Request) {
	var in RequestOTPInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.RequestOTP(r.Context(), in, httpx.ClientIP(r, h.trustProxy))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, result)
}

func (h *Handler) verifyOTP(w http.ResponseWriter, r *http.Request) {
	var in VerifyOTPInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.VerifyOTP(r.Context(), in, h.meta(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, result)
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var in RegisterInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	session, err := h.svc.Register(r.Context(), bearerToken(r), in, h.meta(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, session)
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var in LoginInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	session, err := h.svc.Login(r.Context(), in, h.meta(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, session)
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	var in RefreshInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	session, err := h.svc.Refresh(r.Context(), in.RefreshToken, h.meta(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, session)
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	sessionID, err := MustSession(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.Logout(r.Context(), sessionID); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) verifyPIN(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	sessionID, err := MustSession(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in PINVerifyInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	result, err := h.svc.VerifyPIN(r.Context(), user, sessionID, in.PIN)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, result)
}

func (h *Handler) changePIN(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in ChangePINInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.ChangePIN(r.Context(), user, in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) resetPIN(w http.ResponseWriter, r *http.Request) {
	var in ResetPINInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.ResetPIN(r.Context(), in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) setPassword(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in SetPasswordInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.SetPassword(r.Context(), user, in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) listDevices(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	devices, err := h.svc.ListDevices(r.Context(), user)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusOK, map[string]any{"data": devices})
}

func (h *Handler) createDevice(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in DeviceInput
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	device, err := h.svc.RegisterDevice(r.Context(), user, in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Respond(w, http.StatusCreated, device)
}

func (h *Handler) deleteDevice(w http.ResponseWriter, r *http.Request) {
	user, err := users.MustUser(r.Context())
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.RevokeDevice(r.Context(), user, chi.URLParam(r, "deviceID")); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}
