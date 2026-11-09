package users

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	store "github.com/chama/chama/backend/internal/store"
)

var ErrNotFound = errors.New("user not found")

type Repository struct {
	q *store.Queries
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool)}
}

func FromRow(u store.User) User {
	return User{
		ID:              u.ID,
		PublicID:        u.PublicID,
		PhoneNumber:     u.PhoneNumber,
		FirstName:       u.FirstName,
		LastName:        u.LastName,
		Email:           u.Email,
		PasswordHash:    u.PasswordHash,
		IsActive:        u.IsActive,
		NationalIDSet:   len(u.NationalIDEnc) > 0,
		PhoneVerifiedAt: u.PhoneVerifiedAt,
		CreatedAt:       u.CreatedAt,
		UpdatedAt:       u.UpdatedAt,
	}
}

func (r *Repository) GetByPublicID(ctx context.Context, id string) (User, error) {
	publicID, err := parseUUID(id)
	if err != nil {
		return User{}, ErrNotFound
	}
	row, err := r.q.GetUserByPublicID(ctx, publicID)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	return FromRow(row), nil
}

func (r *Repository) GetByID(ctx context.Context, id int64) (User, error) {
	row, err := r.q.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	return FromRow(row), nil
}

func (r *Repository) PINSet(ctx context.Context, id int64) (bool, error) {
	_, err := r.q.GetPIN(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

func (r *Repository) UpdateProfile(ctx context.Context, id int64, firstName, lastName string, email *string) (User, error) {
	row, err := r.q.UpdateUserProfile(ctx, store.UpdateUserProfileParams{
		FirstName: firstName,
		LastName:  lastName,
		Email:     email,
		ID:        id,
	})
	if err != nil {
		return User{}, err
	}
	return FromRow(row), nil
}

func (r *Repository) SetNationalID(ctx context.Context, id int64, enc []byte) error {
	return r.q.SetUserNationalID(ctx, store.SetUserNationalIDParams{ID: id, NationalIDEnc: enc})
}

// UpsertPIN is used by registration and PIN reset paths.
func (r *Repository) UpsertPIN(ctx context.Context, id int64, hash string) error {
	return r.q.UpsertPIN(ctx, store.UpsertPINParams{UserID: id, PinHash: hash})
}
