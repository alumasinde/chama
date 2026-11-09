package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/phone"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

// VerifyPIN mints a five-minute step-up token required by money endpoints.
func (s *Service) VerifyPIN(ctx context.Context, user users.User, sessionID uuid.UUID, pin string) (PINVerifyResult, error) {
	if err := s.checkPIN(ctx, user.ID, pin); err != nil {
		return PINVerifyResult{}, err
	}
	token, expires, err := s.tokens.IssueStepUp(user.PublicID, sessionID)
	if err != nil {
		return PINVerifyResult{}, err
	}
	return PINVerifyResult{StepUpToken: token, ExpiresIn: int(time.Until(expires).Seconds())}, nil
}

// checkPIN applies lockout, verifies, and resets counters on success.
func (s *Service) checkPIN(ctx context.Context, userID int64, pin string) error {
	row, err := s.repo.q.GetPIN(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return httpx.Unprocessable("pin_not_set", "Set a 4-digit PIN first.")
	}
	if err != nil {
		return err
	}
	if row.LockedUntil != nil && row.LockedUntil.After(time.Now()) {
		return pinLockedError(*row.LockedUntil)
	}
	if !crypto.VerifySecret(row.PinHash, pin) {
		failure, err := s.repo.q.RecordPINFailure(ctx, store.RecordPINFailureParams{
			UserID: userID, MaxAttempts: s.opts.PINMaxAttempts,
			LockSeconds: int32(s.opts.PINLock.Seconds()),
		})
		if err != nil {
			return err
		}
		if failure.LockedUntil != nil && failure.LockedUntil.After(time.Now()) {
			return pinLockedError(*failure.LockedUntil)
		}
		return httpx.Unprocessable("pin_incorrect", "That PIN is not correct.")
	}
	return s.repo.q.ResetPINFailures(ctx, userID)
}

func pinLockedError(until time.Time) error {
	minutes := int(time.Until(until).Minutes()) + 1
	return httpx.Unprocessable("pin_locked", fmt.Sprintf("Too many wrong PINs. Try again in %d minutes.", minutes))
}

// ResetPIN proves the phone with an OTP, then revokes every session.
func (s *Service) ResetPIN(ctx context.Context, in ResetPINInput) error {
	phoneNumber, err := phone.Normalize(in.PhoneNumber)
	if err != nil {
		return httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	if err := ValidatePIN(in.NewPIN); err != nil {
		return httpx.Validation(map[string]string{"new_pin": err.Error()})
	}
	if err := s.consumeOTP(ctx, phoneNumber, PurposePINReset, in.Code); err != nil {
		return err
	}
	row, err := s.repo.q.GetUserByPhone(ctx, phoneNumber)
	if errors.Is(err, pgx.ErrNoRows) {
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	if err != nil {
		return err
	}
	hash, err := crypto.HashSecret(in.NewPIN)
	if err != nil {
		return err
	}
	return s.repo.WithTx(ctx, func(q *store.Queries) error {
		if err := q.UpsertPIN(ctx, store.UpsertPINParams{UserID: row.ID, PinHash: hash}); err != nil {
			return err
		}
		return q.RevokeAllUserTokens(ctx, row.ID)
	})
}

func (s *Service) ChangePIN(ctx context.Context, user users.User, in ChangePINInput) error {
	if err := ValidatePIN(in.NewPIN); err != nil {
		return httpx.Validation(map[string]string{"new_pin": err.Error()})
	}
	if err := s.checkPIN(ctx, user.ID, in.CurrentPIN); err != nil {
		return err
	}
	hash, err := crypto.HashSecret(in.NewPIN)
	if err != nil {
		return err
	}
	return s.repo.q.UpsertPIN(ctx, store.UpsertPINParams{UserID: user.ID, PinHash: hash})
}

func (s *Service) SetPassword(ctx context.Context, user users.User, in SetPasswordInput) error {
	if err := ValidatePassword(in.Password); err != nil {
		return httpx.Validation(map[string]string{"password": err.Error()})
	}
	if err := s.checkPIN(ctx, user.ID, in.PIN); err != nil {
		return err
	}
	hash, err := crypto.HashSecret(in.Password)
	if err != nil {
		return err
	}
	return s.repo.SetPassword(ctx, user.ID, hash)
}
