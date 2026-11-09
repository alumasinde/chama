package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	store "github.com/chama/chama/backend/internal/store"
)

// WithTx runs fn inside a transaction; any error rolls every statement back.
func WithTx(ctx context.Context, pool *pgxpool.Pool, fn func(q *store.Queries) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(store.New(tx)); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}
