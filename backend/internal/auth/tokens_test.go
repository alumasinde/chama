package auth

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

const testSecret = "test-secret-that-is-long-enough-for-hs256"

func newTestTokens() *TokenManager {
	return NewTokenManager(testSecret, 15*time.Minute, 5*time.Minute, 15*time.Minute)
}

func TestAccessTokenCarriesUserAndSession(t *testing.T) {
	m := newTestTokens()
	userID, sessionID := uuid.New(), uuid.New()

	token, expires, err := m.IssueAccess(userID, sessionID)
	if err != nil {
		t.Fatalf("IssueAccess: %v", err)
	}
	if time.Until(expires) < 14*time.Minute {
		t.Fatalf("access ttl too short: %v", time.Until(expires))
	}

	claims, err := m.Parse(token, AudienceAPI)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if claims.Subject != userID.String() {
		t.Fatalf("subject = %q, want %q", claims.Subject, userID)
	}
	if claims.SessionID != sessionID.String() {
		t.Fatalf("session = %q, want %q", claims.SessionID, sessionID)
	}
	if claims.Scope != ScopeAccess {
		t.Fatalf("scope = %q", claims.Scope)
	}
}

func TestAccessTokenCannotSatisfyStepUp(t *testing.T) {
	m := newTestTokens()
	token, _, err := m.IssueAccess(uuid.New(), uuid.New())
	if err != nil {
		t.Fatalf("IssueAccess: %v", err)
	}
	if _, err := m.Parse(token, AudienceStepUp); err == nil {
		t.Fatal("access token must not validate against the step-up audience")
	}
}

func TestStepUpTokenIsShortLived(t *testing.T) {
	m := newTestTokens()
	token, _, err := m.IssueStepUp(uuid.New(), uuid.New())
	if err != nil {
		t.Fatalf("IssueStepUp: %v", err)
	}
	claims, err := m.Parse(token, AudienceStepUp)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	lifetime := claims.ExpiresAt.Sub(claims.IssuedAt.Time)
	if lifetime != 5*time.Minute {
		t.Fatalf("step-up lifetime = %v, want 5m", lifetime)
	}
}

func TestRegistrationTokenCarriesPhoneOnly(t *testing.T) {
	m := newTestTokens()
	token, _, err := m.IssueRegistration("+254712345678")
	if err != nil {
		t.Fatalf("IssueRegistration: %v", err)
	}
	claims, err := m.Parse(token, AudienceRegistration)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if claims.Phone != "+254712345678" {
		t.Fatalf("phone = %q", claims.Phone)
	}
	if claims.Scope != ScopeRegistration {
		t.Fatalf("scope = %q", claims.Scope)
	}
}

func TestParseRejectsTamperedToken(t *testing.T) {
	m := newTestTokens()
	token, _, err := m.IssueAccess(uuid.New(), uuid.New())
	if err != nil {
		t.Fatalf("IssueAccess: %v", err)
	}
	if _, err := m.Parse(token+"x", AudienceAPI); err == nil {
		t.Fatal("expected a tampered token to fail")
	}
}
