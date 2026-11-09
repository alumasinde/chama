package users

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
)

var emailPattern = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]{2,}$`)

type Service struct {
	repo   *Repository
	cipher *crypto.Cipher
}

func NewService(repo *Repository, cipher *crypto.Cipher) *Service {
	return &Service{repo: repo, cipher: cipher}
}

func (s *Service) Get(ctx context.Context, publicID string) (User, error) {
	user, err := s.repo.GetByPublicID(ctx, publicID)
	if err != nil {
		return User{}, err
	}
	pin, err := s.repo.PINSet(ctx, user.ID)
	if err != nil {
		return User{}, err
	}
	user.PINSet = pin
	return user, nil
}

// PINSet reports whether the user has configured a 4-digit PIN.
func (s *Service) PINSet(ctx context.Context, id int64) (bool, error) {
	return s.repo.PINSet(ctx, id)
}

func (s *Service) GetByID(ctx context.Context, id int64) (User, error) {
	user, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return User{}, err
	}
	pin, err := s.repo.PINSet(ctx, user.ID)
	if err != nil {
		return User{}, err
	}
	user.PINSet = pin
	return user, nil
}

// UpdateProfile validates names and email, then stores the encrypted national ID.
func (s *Service) UpdateProfile(ctx context.Context, user User, in UpdateProfileInput) (User, error) {
	fields := map[string]string{}
	firstName := strings.TrimSpace(in.FirstName)
	lastName := strings.TrimSpace(in.LastName)
	if len(firstName) == 0 || len(firstName) > 80 {
		fields["first_name"] = "Enter a first name up to 80 characters."
	}
	if len(lastName) == 0 || len(lastName) > 80 {
		fields["last_name"] = "Enter a last name up to 80 characters."
	}
	email := normalizeEmail(in.Email)
	if in.Email != nil && *in.Email != "" && email == nil {
		fields["email"] = "Enter a valid email address."
	}
	if len(fields) > 0 {
		return User{}, httpx.Validation(fields)
	}

	updated, err := s.repo.UpdateProfile(ctx, user.ID, firstName, lastName, email)
	if err != nil {
		return User{}, err
	}
	if in.NationalID != nil && strings.TrimSpace(*in.NationalID) != "" {
		enc, err := EncryptNationalID(s.cipher, user.PhoneNumber, strings.TrimSpace(*in.NationalID))
		if err != nil {
			return User{}, httpx.Validation(map[string]string{"national_id": err.Error()})
		}
		if err := s.repo.SetNationalID(ctx, user.ID, enc); err != nil {
			return User{}, err
		}
		updated.NationalIDSet = true
	}
	updated.PINSet = user.PINSet
	return updated, nil
}

// EncryptNationalID binds ciphertext to the owner phone so rows cannot be swapped.
func EncryptNationalID(cipher *crypto.Cipher, phoneNumber, nationalID string) ([]byte, error) {
	if !regexp.MustCompile(`^\d{7,8}$`).MatchString(nationalID) {
		return nil, errors.New("national ID must be 7 or 8 digits")
	}
	return cipher.Seal([]byte(nationalID), []byte("users.national_id:"+phoneNumber))
}

// NormalizeEmail lowercases and validates; ok is false only for a malformed value.
func NormalizeEmail(email *string) (*string, bool) {
	if email == nil {
		return nil, true
	}
	clean := strings.ToLower(strings.TrimSpace(*email))
	if clean == "" {
		return nil, true
	}
	if !emailPattern.MatchString(clean) {
		return nil, false
	}
	return &clean, true
}

func normalizeEmail(email *string) *string {
	if email == nil {
		return nil
	}
	clean := strings.ToLower(strings.TrimSpace(*email))
	if clean == "" {
		return nil
	}
	if !emailPattern.MatchString(clean) {
		return nil
	}
	return &clean
}

// WithUser stores the authenticated user on the request context.
func WithUser(ctx context.Context, user User) context.Context {
	return context.WithValue(ctx, userKey{}, user)
}

type userKey struct{}

func FromContext(ctx context.Context) (User, bool) {
	user, ok := ctx.Value(userKey{}).(User)
	return user, ok
}

func MustUser(ctx context.Context) (User, error) {
	user, ok := FromContext(ctx)
	if !ok {
		return User{}, httpx.Unauthorized("Sign in to continue.")
	}
	return user, nil
}

func parseUUID(raw string) (uuid.UUID, error) { return uuid.Parse(raw) }
