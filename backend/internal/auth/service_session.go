package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

var errRefreshReuse = errors.New("refresh token reuse")

// Refresh rotates a token; reuse of an old token revokes the whole session family.
func (s *Service) Refresh(ctx context.Context, raw string, meta clientMeta) (Session, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return Session{}, httpx.Unauthorized("Sign in again.")
	}
	row, err := s.repo.q.GetRefreshToken(ctx, crypto.Hash(raw))
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, httpx.Unauthorized("Sign in again.")
	}
	if err != nil {
		return Session{}, err
	}
	if row.RevokedAt != nil {
		_ = s.repo.q.RevokeSession(ctx, row.SessionID)
		s.log.WarnContext(ctx, "refresh token reuse detected", "user_id", row.UserID)
		return Session{}, httpx.Unauthorized("Session ended. Sign in again.")
	}
	if time.Now().After(row.ExpiresAt) {
		return Session{}, httpx.Unauthorized("Session expired. Sign in again.")
	}
	userRow, err := s.repo.q.GetUserByID(ctx, row.UserID)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, httpx.Unauthorized("Sign in again.")
	}
	if err != nil {
		return Session{}, err
	}
	if !userRow.IsActive {
		return Session{}, httpx.Forbidden("This account is disabled.")
	}

	var newRaw string
	var newExpiry time.Time
	err = s.repo.WithTx(ctx, func(q *store.Queries) error {
		generated, err := crypto.Token(32)
		if err != nil {
			return err
		}
		createdRow, err := q.CreateRefreshToken(ctx, store.CreateRefreshTokenParams{
			UserID:     row.UserID,
			TokenHash:  crypto.Hash(generated),
			SessionID:  row.SessionID,
			TtlSeconds: int32(s.opts.RefreshTTL.Seconds()),
			UserAgent:  nullable(meta.userAgent),
			Ip:         nullable(meta.ip),
		})
		if err != nil {
			return err
		}
		rotated, err := q.RotateRefreshToken(ctx, store.RotateRefreshTokenParams{
			ID: row.ID, ReplacedBy: &createdRow.ID,
		})
		if err != nil {
			return err
		}
		if rotated == 0 {
			return errRefreshReuse
		}
		newRaw = generated
		newExpiry = createdRow.ExpiresAt
		return nil
	})
	if errors.Is(err, errRefreshReuse) {
		_ = s.repo.q.RevokeSession(ctx, row.SessionID)
		s.log.WarnContext(ctx, "concurrent refresh reuse detected", "user_id", row.UserID)
		return Session{}, httpx.Unauthorized("Session ended. Sign in again.")
	}
	if err != nil {
		return Session{}, err
	}

	user := users.FromRow(userRow)
	pinSet, err := s.users.PINSet(ctx, user.ID)
	if err != nil {
		return Session{}, err
	}
	user.PINSet = pinSet
	access, _, err := s.tokens.IssueAccess(user.PublicID, row.SessionID)
	if err != nil {
		return Session{}, err
	}
	return Session{
		AccessToken:      access,
		RefreshToken:     newRaw,
		TokenType:        "Bearer",
		ExpiresIn:        int(s.opts.AccessTTL.Seconds()),
		RefreshExpiresIn: int(time.Until(newExpiry).Seconds()),
		User:             user.View(),
	}, nil
}

func (s *Service) Logout(ctx context.Context, sessionID uuid.UUID) error {
	if sessionID == uuid.Nil {
		return httpx.Unauthorized("Sign in to continue.")
	}
	return s.repo.q.RevokeSession(ctx, sessionID)
}
