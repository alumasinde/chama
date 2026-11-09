//go:build integration

package auth

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/testdb"
	"github.com/chama/chama/backend/internal/users"
)

func newTestService(t *testing.T) *Service {
	t.Helper()
	pool := testdb.New(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	cipher, err := crypto.NewCipher(bytes.Repeat([]byte{7}, 32))
	if err != nil {
		t.Fatal(err)
	}
	usersSvc := users.NewService(users.NewRepository(pool), cipher)
	svc, err := NewService(Options{
		JWTSecret:       strings.Repeat("k", 48),
		AccessTTL:       15 * time.Minute,
		StepUpTTL:       5 * time.Minute,
		RegistrationTTL: 15 * time.Minute,
		RefreshTTL:      24 * time.Hour,
		OTPTTL:          10 * time.Minute,
		OTPMaxAttempts:  5,
		PINMaxAttempts:  5,
		PINLock:         15 * time.Minute,
		OTPHashKey:      []byte("integration-otp-key"),
		DevMode:         true,
	}, NewRepository(pool), usersSvc, cipher, &MockSMS{}, log)
	if err != nil {
		t.Fatal(err)
	}
	return svc
}

func TestAuthLifecycleOnPostgres(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	meta := clientMeta{userAgent: "integration-test", ip: "127.0.0.1"}
	const localPhone = "0712345678"
	const e164 = "+254712345678"

	otp, err := svc.RequestOTP(ctx, RequestOTPInput{PhoneNumber: localPhone, Purpose: PurposeRegistration}, "127.0.0.1")
	if err != nil {
		t.Fatalf("request otp: %v", err)
	}
	if len(otp.DevCode) != 6 {
		t.Fatalf("development mode must return a code, got %q", otp.DevCode)
	}

	verified, err := svc.VerifyOTP(ctx, VerifyOTPInput{PhoneNumber: localPhone, Code: otp.DevCode, Purpose: PurposeRegistration}, meta)
	if err != nil {
		t.Fatalf("verify otp: %v", err)
	}
	if !verified.NewUser || verified.RegistrationToken == "" {
		t.Fatalf("expected a new user with a registration token: %+v", verified)
	}

	session, err := svc.Register(ctx, verified.RegistrationToken, RegisterInput{
		FirstName: "Wanjiku", LastName: "Kamau", PIN: "4826",
		Password: strPtr("ChamaStrong2026"),
	}, meta)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	if session.User.PhoneNumber != e164 || !session.User.PINSet || !session.User.HasPassword {
		t.Fatalf("unexpected registered user: %+v", session.User)
	}

	user, err := svc.users.Get(ctx, session.User.ID)
	if err != nil {
		t.Fatalf("load user: %v", err)
	}
	claims, err := svc.tokens.Parse(session.AccessToken, AudienceAPI)
	if err != nil {
		t.Fatalf("parse access token: %v", err)
	}
	sessionID, err := uuid.Parse(claims.SessionID)
	if err != nil {
		t.Fatalf("session id claim: %v", err)
	}

	for attempt := 1; attempt <= 4; attempt++ {
		_, err := svc.VerifyPIN(ctx, user, sessionID, "9999")
		requireCode(t, err, "pin_incorrect")
	}
	_, err = svc.VerifyPIN(ctx, user, sessionID, "9999")
	requireCode(t, err, "pin_locked")
	_, err = svc.VerifyPIN(ctx, user, sessionID, "4826")
	requireCode(t, err, "pin_locked")

	rotated, err := svc.Refresh(ctx, session.RefreshToken, meta)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if rotated.RefreshToken == session.RefreshToken {
		t.Fatal("refresh token must rotate")
	}
	_, err = svc.Refresh(ctx, session.RefreshToken, meta)
	requireStatus(t, err, http.StatusUnauthorized)
	_, err = svc.Refresh(ctx, rotated.RefreshToken, meta)
	requireStatus(t, err, http.StatusUnauthorized)

	login, err := svc.Login(ctx, LoginInput{PhoneNumber: localPhone, Password: "ChamaStrong2026"}, meta)
	if err != nil {
		t.Fatalf("password login: %v", err)
	}
	if login.User.ID != session.User.ID {
		t.Fatalf("login returned a different user")
	}

	again, err := svc.RequestOTP(ctx, RequestOTPInput{PhoneNumber: e164, Purpose: PurposeRegistration}, "127.0.0.1")
	if err != nil {
		t.Fatalf("second otp: %v", err)
	}
	existing, err := svc.VerifyOTP(ctx, VerifyOTPInput{PhoneNumber: e164, Code: again.DevCode, Purpose: PurposeRegistration}, meta)
	if err != nil {
		t.Fatalf("verify existing phone: %v", err)
	}
	if existing.NewUser || existing.Session == nil {
		t.Fatalf("known phone must sign in instead of registering")
	}
}

func requireCode(t *testing.T, err error, want string) {
	t.Helper()
	var apiErr *httpx.Error
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected API error %q, got %v", want, err)
	}
	if apiErr.Code != want {
		t.Fatalf("expected code %q, got %q (%v)", want, apiErr.Code, err)
	}
}

func requireStatus(t *testing.T, err error, want int) {
	t.Helper()
	var apiErr *httpx.Error
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected API error with status %d, got %v", want, err)
	}
	if apiErr.Status != want {
		t.Fatalf("status = %d, want %d (%v)", apiErr.Status, want, err)
	}
}

func strPtr(v string) *string { return &v }
