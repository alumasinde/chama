package audit

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("audit entry not found")

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

func (r *Repository) Insert(ctx context.Context, entry Entry) error {
	before, err := marshalState(entry.Before)
	if err != nil {
		return err
	}
	after, err := marshalState(entry.After)
	if err != nil {
		return err
	}
	_, err = r.pool.Exec(ctx, `
		INSERT INTO audit_logs (
			group_id, actor_user_id, action_code, entity_type, entity_id,
			entity_public_id, before_state, after_state, ip_address, request_id
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF($9, ''), NULLIF($10, ''))`,
		entry.GroupID, entry.ActorID, entry.Action, entry.EntityType, entry.EntityID,
		entry.EntityPublicID, before, after, entry.IPAddress, entry.RequestID)
	return err
}

func marshalState(value any) ([]byte, error) {
	if value == nil {
		return nil, nil
	}
	return json.Marshal(value)
}

func (r *Repository) List(ctx context.Context, groupID int64, filter Filter) ([]View, error) {
	limit := filter.Limit
	if limit < 1 || limit > 200 {
		limit = 100
	}
	rows, err := r.pool.Query(ctx, `
		SELECT a.public_id,
		       COALESCE(NULLIF(trim(u.first_name || ' ' || u.last_name), ''), 'System'),
		       a.action_code, a.entity_type, a.entity_public_id,
		       a.before_state, a.after_state, a.created_at
		FROM audit_logs a
		LEFT JOIN users u ON u.id = a.actor_user_id
		WHERE a.group_id = $1
		  AND ($2 = '' OR a.action_code = $2)
		  AND ($3 = '' OR a.entity_type = $3)
		  AND ($4::timestamptz IS NULL OR a.created_at >= $4)
		  AND ($5::timestamptz IS NULL OR a.created_at < $5)
		ORDER BY a.created_at DESC, a.id DESC
		LIMIT $6`,
		groupID, filter.Action, filter.EntityType, filter.From, filter.To, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]View, 0)
	for rows.Next() {
		var (
			view           View
			publicID       uuid.UUID
			entityPublicID *uuid.UUID
			before, after  []byte
		)
		if err := rows.Scan(&publicID, &view.Actor, &view.Action, &view.EntityType,
			&entityPublicID, &before, &after, &view.CreatedAt); err != nil {
			return nil, err
		}
		view.ID = publicID.String()
		if entityPublicID != nil {
			value := entityPublicID.String()
			view.EntityPublicID = &value
		}
		view.Before = decodeState(before)
		view.After = decodeState(after)
		out = append(out, view)
	}
	return out, rows.Err()
}

func (r *Repository) Get(ctx context.Context, groupID int64, publicID uuid.UUID) (View, error) {
	var (
		view           View
		entityPublicID *uuid.UUID
		before, after  []byte
	)
	err := r.pool.QueryRow(ctx, `
		SELECT a.public_id,
		       COALESCE(NULLIF(trim(u.first_name || ' ' || u.last_name), ''), 'System'),
		       a.action_code, a.entity_type, a.entity_public_id,
		       a.before_state, a.after_state, a.created_at
		FROM audit_logs a
		LEFT JOIN users u ON u.id = a.actor_user_id
		WHERE a.group_id = $1 AND a.public_id = $2`,
		groupID, publicID).Scan(&view.ID, &view.Actor, &view.Action, &view.EntityType,
		&entityPublicID, &before, &after, &view.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return View{}, ErrNotFound
	}
	if err != nil {
		return View{}, err
	}
	if entityPublicID != nil {
		value := entityPublicID.String()
		view.EntityPublicID = &value
	}
	view.Before = decodeState(before)
	view.After = decodeState(after)
	return view, nil
}

func decodeState(raw []byte) any {
	if len(raw) == 0 {
		return nil
	}
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return string(raw)
	}
	return value
}
