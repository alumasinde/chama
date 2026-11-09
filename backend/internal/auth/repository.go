package auth

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

// Repository is the sqlc boundary for auth tables; no SQL lives above this file.
type Repository struct {
	pool *pgxpool.Pool
	q    *store.Queries
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool, q: store.New(pool)}
}

func (r *Repository) WithTx(ctx context.Context, fn func(q *store.Queries) error) error {
	return db.WithTx(ctx, r.pool, fn)
}

// SetPassword stores an argon2id hash; the service has already verified the PIN.
func (r *Repository) SetPassword(ctx context.Context, userID int64, hash string) error {
	return r.q.SetUserPassword(ctx, store.SetUserPasswordParams{ID: userID, PasswordHash: &hash})
}
