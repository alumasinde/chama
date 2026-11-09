package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/chama/chama/backend/internal/platform/brand"
	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/phone"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

type Options struct {
	JWTSecret       string
	AccessTTL       time.Duration
	StepUpTTL       time.Duration
	RegistrationTTL time.Duration
	RefreshTTL      time.Duration
	OTPTTL          time.Duration
	OTPMaxAttempts  int32
	PINMaxAttempts  int32
	PINLock         time.Duration
	OTPHashKey      []byte
	DevMode         bool
}

type Service struct {
	repo      *Repository
	users     *users.Service
	tokens    *TokenManager
	sms       SMS
	cipher    *crypto.Cipher
	log       *slog.Logger
	opts      Options
	dummyHash string
}

func NewService(opts Options, repo *Repository, usersSvc *users.Service, cipher *crypto.Cipher, sms SMS, log *slog.Logger) (*Service, error) {
	dummy, err := crypto.HashSecret("timing-equaliser-not-a-password")
	if err != nil {
		return nil, err
	}
	return &Service{
		repo:      repo,
		users:     usersSvc,
		tokens:    NewTokenManager(opts.JWTSecret, opts.AccessTTL, opts.StepUpTTL, opts.RegistrationTTL),
		sms:       sms,
		cipher:    cipher,
		log:       log,
		opts:      opts,
		dummyHash: dummy,
	}, nil
}

// RequestOTP issues a hashed, throttled verification code.
func (s *Service) RequestOTP(ctx context.Context, in RequestOTPInput, ip string) (RequestOTPResult, error) {
	purpose := strings.TrimSpace(in.Purpose)
	if !validPurpose(purpose) {
		return RequestOTPResult{}, httpx.Validation(map[string]string{
			"purpose": "Choose login, registration or pin_reset.",
		})
	}
	phoneNumber, err := phone.Normalize(in.PhoneNumber)
	if err != nil {
		return RequestOTPResult{}, httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	if err := s.bump(ctx, "otp:ip:"+ip, time.Hour, 10, time.Hour); err != nil {
		return RequestOTPResult{}, err
	}
	if err := s.bump(ctx, "otp:send:"+phoneNumber, 10*time.Minute, 3, 10*time.Minute); err != nil {
		return RequestOTPResult{}, err
	}

	code, err := GenerateOTP()
	if err != nil {
		return RequestOTPResult{}, err
	}
	row, err := s.repo.q.CreateOTP(ctx, store.CreateOTPParams{
		PhoneNumber: phoneNumber,
		CodeHash:    HashOTP(s.opts.OTPHashKey, phoneNumber, purpose, code),
		Purpose:     purpose,
		TtlSeconds:  int32(s.opts.OTPTTL.Seconds()),
		RequestIp:   &ip,
	})
	if err != nil {
		return RequestOTPResult{}, err
	}

	message := fmt.Sprintf("Your %s code is %s. It expires in %d minutes.",
		brand.AppName, code, int(s.opts.OTPTTL.Minutes()))
	if s.sms != nil {
		if err := s.sms.Send(ctx, phoneNumber, message); err != nil {
			s.log.ErrorContext(ctx, "sms send failed", "error", err)
			return RequestOTPResult{}, httpx.Internal(err)
		}
	}

	result := RequestOTPResult{ExpiresIn: int(time.Until(row.ExpiresAt).Seconds()), ResendAfter: 60}
	if s.opts.DevMode {
		result.DevCode = code
	}
	return result, nil
}

// VerifyOTP signs in a known member or returns a registration token for a new phone.
func (s *Service) VerifyOTP(ctx context.Context, in VerifyOTPInput, meta clientMeta) (VerifyOTPResult, error) {
	purpose := strings.TrimSpace(in.Purpose)
	if !validPurpose(purpose) {
		return VerifyOTPResult{}, httpx.Validation(map[string]string{
			"purpose": "Choose login, registration or pin_reset.",
		})
	}
	if purpose == PurposePINReset {
		return VerifyOTPResult{}, httpx.Unprocessable("use_pin_reset", "Use the PIN reset endpoint instead.")
	}
	phoneNumber, err := phone.Normalize(in.PhoneNumber)
	if err != nil {
		return VerifyOTPResult{}, httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	if err := s.consumeOTP(ctx, phoneNumber, purpose, in.Code); err != nil {
		return VerifyOTPResult{}, err
	}

	row, err := s.repo.q.GetUserByPhone(ctx, phoneNumber)
	if errors.Is(err, pgx.ErrNoRows) {
		token, expires, err := s.tokens.IssueRegistration(phoneNumber)
		if err != nil {
			return VerifyOTPResult{}, err
		}
		return VerifyOTPResult{
			NewUser:           true,
			RegistrationToken: token,
			ExpiresIn:         int(time.Until(expires).Seconds()),
		}, nil
	}
	if err != nil {
		return VerifyOTPResult{}, err
	}
	user := users.FromRow(row)
	if !user.IsActive {
		return VerifyOTPResult{}, httpx.Forbidden("This account is disabled.")
	}
	pinSet, err := s.users.PINSet(ctx, user.ID)
	if err != nil {
		return VerifyOTPResult{}, err
	}
	user.PINSet = pinSet
	session, err := s.issueSession(ctx, user, meta)
	if err != nil {
		return VerifyOTPResult{}, err
	}
	return VerifyOTPResult{Session: &session}, nil
}

// consumeOTP validates a code once and burns it, never revealing which check failed.
func (s *Service) consumeOTP(ctx context.Context, phoneNumber, purpose, code string) error {
	if err := s.bump(ctx, "otp:verify:"+phoneNumber, time.Hour, 10, time.Hour); err != nil {
		return err
	}
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	row, err := s.repo.q.LatestOTP(ctx, store.LatestOTPParams{PhoneNumber: phoneNumber, Purpose: purpose})
	if errors.Is(err, pgx.ErrNoRows) {
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	if err != nil {
		return err
	}
	now := time.Now()
	if row.ConsumedAt != nil || now.After(row.ExpiresAt) || int(row.Attempts) >= int(s.opts.OTPMaxAttempts) {
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	if !constantTimeEqual(HashOTP(s.opts.OTPHashKey, phoneNumber, purpose, code), row.CodeHash) {
		_, _ = s.repo.q.IncrementOTPAttempts(ctx, row.ID)
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	burned, err := s.repo.q.ConsumeOTP(ctx, row.ID)
	if err != nil {
		return err
	}
	if burned == 0 {
		return httpx.Unprocessable("otp_invalid", "That code is not correct or has expired.")
	}
	return nil
}

// bump counts an attempt in a rolling window and locks the key when the limit is passed.
func (s *Service) bump(ctx context.Context, key string, window time.Duration, limit int, lock time.Duration) error {
	row, err := s.repo.q.BumpThrottle(ctx, store.BumpThrottleParams{
		Key: key, WindowSeconds: int32(window.Seconds()),
	})
	if err != nil {
		return err
	}
	if row.LockedUntil != nil && row.LockedUntil.After(time.Now()) {
		return httpx.TooMany("Too many attempts. Try again in a few minutes.")
	}
	if int(row.Attempts) > limit {
		if err := s.repo.q.LockThrottle(ctx, store.LockThrottleParams{
			Key: key, LockSeconds: int32(lock.Seconds()),
		}); err != nil {
			return err
		}
		return httpx.TooMany("Too many attempts. Try again in a few minutes.")
	}
	return nil
}

// issueSession mints the access token and a hashed, rotating refresh token.
func (s *Service) issueSession(ctx context.Context, user users.User, meta clientMeta) (Session, error) {
	sessionID := uuid.New()
	raw, err := crypto.Token(32)
	if err != nil {
		return Session{}, err
	}
	row, err := s.repo.q.CreateRefreshToken(ctx, store.CreateRefreshTokenParams{
		UserID:     user.ID,
		TokenHash:  crypto.Hash(raw),
		SessionID:  sessionID,
		TtlSeconds: int32(s.opts.RefreshTTL.Seconds()),
		UserAgent:  nullable(meta.userAgent),
		Ip:         nullable(meta.ip),
	})
	if err != nil {
		return Session{}, err
	}
	access, _, err := s.tokens.IssueAccess(user.PublicID, sessionID)
	if err != nil {
		return Session{}, err
	}
	return Session{
		AccessToken:      access,
		RefreshToken:     raw,
		TokenType:        "Bearer",
		ExpiresIn:        int(s.opts.AccessTTL.Seconds()),
		RefreshExpiresIn: int(time.Until(row.ExpiresAt).Seconds()),
		User:             user.View(),
	}, nil
}

func nullable(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
