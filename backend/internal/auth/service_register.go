package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/phone"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

// Register creates the account, PIN, optional password and encrypted national ID in one transaction.
func (s *Service) Register(ctx context.Context, registrationToken string, in RegisterInput, meta clientMeta) (Session, error) {
	claims, err := s.tokens.Parse(registrationToken, AudienceRegistration)
	if err != nil || claims.Phone == "" {
		return Session{}, httpx.Unauthorized("Your verification expired. Request a new code.")
	}
	phoneNumber, err := phone.Normalize(claims.Phone)
	if err != nil {
		return Session{}, httpx.Unauthorized("Your verification expired. Request a new code.")
	}

	if _, err := s.repo.q.GetUserByPhone(ctx, phoneNumber); err == nil {
		return Session{}, httpx.Conflict("phone_already_registered", "This phone already has an account. Sign in instead.")
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return Session{}, err
	}

	fields := map[string]string{}
	firstName := strings.TrimSpace(in.FirstName)
	lastName := strings.TrimSpace(in.LastName)
	if len(firstName) == 0 || len(firstName) > 80 {
		fields["first_name"] = "Enter a first name up to 80 characters."
	}
	if len(lastName) == 0 || len(lastName) > 80 {
		fields["last_name"] = "Enter a last name up to 80 characters."
	}
	if err := ValidatePIN(in.PIN); err != nil {
		fields["pin"] = err.Error()
	}
	email, emailOK := users.NormalizeEmail(in.Email)
	if !emailOK {
		fields["email"] = "Enter a valid email address."
	}
	var nationalIDEnc []byte
	if in.NationalID != nil && strings.TrimSpace(*in.NationalID) != "" {
		enc, err := users.EncryptNationalID(s.cipher, phoneNumber, strings.TrimSpace(*in.NationalID))
		if err != nil {
			fields["national_id"] = err.Error()
		}
		nationalIDEnc = enc
	}
	var passwordHash *string
	if in.Password != nil && *in.Password != "" {
		if err := ValidatePassword(*in.Password); err != nil {
			fields["password"] = err.Error()
		}
		hash, err := crypto.HashSecret(*in.Password)
		if err != nil {
			return Session{}, err
		}
		passwordHash = &hash
	}
	if len(fields) > 0 {
		return Session{}, httpx.Validation(fields)
	}

	pinHash, err := crypto.HashSecret(in.PIN)
	if err != nil {
		return Session{}, err
	}

	var created users.User
	err = s.repo.WithTx(ctx, func(q *store.Queries) error {
		row, err := q.CreateUser(ctx, store.CreateUserParams{
			PhoneNumber:   phoneNumber,
			FirstName:     firstName,
			LastName:      lastName,
			Email:         email,
			NationalIDEnc: nationalIDEnc,
			PasswordHash:  passwordHash,
		})
		if err != nil {
			return err
		}
		if err := q.TouchPhoneVerified(ctx, row.ID); err != nil {
			return err
		}
		if err := q.UpsertPIN(ctx, store.UpsertPINParams{UserID: row.ID, PinHash: pinHash}); err != nil {
			return err
		}
		if passwordHash != nil {
			if err := q.SetUserPassword(ctx, store.SetUserPasswordParams{ID: row.ID, PasswordHash: passwordHash}); err != nil {
				return err
			}
		}
		if len(nationalIDEnc) > 0 {
			if err := q.SetUserNationalID(ctx, store.SetUserNationalIDParams{ID: row.ID, NationalIDEnc: nationalIDEnc}); err != nil {
				return err
			}
		}
		created = users.FromRow(row)
		created.PINSet = true
		return nil
	})
	if err != nil {
		return Session{}, err
	}
	return s.issueSession(ctx, created, meta)
}

// Login verifies a password; the dummy hash keeps timing flat for unknown phones.
func (s *Service) Login(ctx context.Context, in LoginInput, meta clientMeta) (Session, error) {
	phoneNumber, err := phone.Normalize(in.PhoneNumber)
	if err != nil {
		return Session{}, httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	if err := s.bump(ctx, "login:"+phoneNumber, 15*time.Minute, 10, 15*time.Minute); err != nil {
		return Session{}, err
	}
	row, err := s.repo.q.GetUserByPhone(ctx, phoneNumber)
	if errors.Is(err, pgx.ErrNoRows) {
		crypto.VerifySecret(s.dummyHash, in.Password)
		return Session{}, httpx.Unauthorized("Phone number or password is incorrect.")
	}
	if err != nil {
		return Session{}, err
	}
	if row.PasswordHash == nil || !crypto.VerifySecret(*row.PasswordHash, in.Password) {
		return Session{}, httpx.Unauthorized("Phone number or password is incorrect.")
	}
	if !row.IsActive {
		return Session{}, httpx.Forbidden("This account is disabled.")
	}
	_ = s.repo.q.ClearThrottle(ctx, "login:"+phoneNumber)
	user := users.FromRow(row)
	pinSet, err := s.users.PINSet(ctx, user.ID)
	if err != nil {
		return Session{}, err
	}
	user.PINSet = pinSet
	return s.issueSession(ctx, user, meta)
}
