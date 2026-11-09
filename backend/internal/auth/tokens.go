package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	AudienceAPI          = "api"
	AudienceStepUp       = "step_up"
	AudienceRegistration = "registration"

	ScopeAccess       = "access"
	ScopeStepUp       = "step_up"
	ScopeRegistration = "registration"

	issuer = "chama-ledger"
)

var ErrInvalidToken = errors.New("invalid token")

// Claims carries only opaque identifiers; roles are resolved per group per request.
type Claims struct {
	jwt.RegisteredClaims
	Scope     string `json:"scope"`
	Phone     string `json:"phone,omitempty"`
	SessionID string `json:"sid,omitempty"`
}

type TokenManager struct {
	secret      []byte
	accessTTL   time.Duration
	stepUpTTL   time.Duration
	registerTTL time.Duration
}

func NewTokenManager(secret string, accessTTL, stepUpTTL, registerTTL time.Duration) *TokenManager {
	return &TokenManager{
		secret:      []byte(secret),
		accessTTL:   accessTTL,
		stepUpTTL:   stepUpTTL,
		registerTTL: registerTTL,
	}
}

func (m *TokenManager) IssueAccess(userID, sessionID uuid.UUID) (string, time.Time, error) {
	return m.issue(userID.String(), AudienceAPI, ScopeAccess, sessionID.String(), "", m.accessTTL)
}

func (m *TokenManager) IssueStepUp(userID, sessionID uuid.UUID) (string, time.Time, error) {
	return m.issue(userID.String(), AudienceStepUp, ScopeStepUp, sessionID.String(), "", m.stepUpTTL)
}

func (m *TokenManager) IssueRegistration(phoneNumber string) (string, time.Time, error) {
	return m.issue(uuid.Nil.String(), AudienceRegistration, ScopeRegistration, "", phoneNumber, m.registerTTL)
}

func (m *TokenManager) issue(subject, audience, scope, sessionID, phone string, ttl time.Duration) (string, time.Time, error) {
	now := time.Now().UTC()
	expires := now.Add(ttl)
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			Audience:  jwt.ClaimStrings{audience},
			Issuer:    issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(expires),
			ID:        uuid.NewString(),
		},
		Scope:     scope,
		SessionID: sessionID,
		Phone:     phone,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(m.secret)
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, expires, nil
}

func (m *TokenManager) Parse(raw, audience string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		return m.secret, nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithAudience(audience),
		jwt.WithIssuer(issuer),
		jwt.WithExpirationRequired(),
	)
	if err != nil || !token.Valid {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
