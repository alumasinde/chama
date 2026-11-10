package notifications

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	store "github.com/chama/chama/backend/internal/store"
)

var ErrNotFound = errors.New("notification not found")

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) Insert(ctx context.Context, e Event) (uuid.UUID, bool, error) {
	var groupID *int64
	if e.GroupID != nil {
		groupID = e.GroupID
	}
	key := e.DedupeKey
	var dedupe *string
	if key != "" {
		dedupe = &key
	}
	raw, _ := json.Marshal(e.Data)
	if len(raw) == 0 || string(raw) == "null" {
		raw = []byte("{}")
	}
	row, err := r.q.InsertNotification(ctx, store.InsertNotificationParams{
		UserID: e.UserID, GroupID: groupID, NotificationType: e.Type,
		Title: e.Title, Body: e.Body, Data: string(raw), DedupeKey: dedupe,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, false, nil
	}
	if err != nil {
		return uuid.Nil, false, err
	}
	return row.PublicID, true, nil
}

func (r *Repository) List(ctx context.Context, userID int64, unread bool, limit int32) ([]store.ListNotificationsRow, error) {
	return r.q.ListNotifications(ctx, store.ListNotificationsParams{
		UserID: userID, UnreadOnly: unread, RowLimit: limit,
	})
}

func (r *Repository) Unread(ctx context.Context, userID int64) (int64, error) {
	return r.q.CountUnreadNotifications(ctx, userID)
}

func (r *Repository) MarkRead(ctx context.Context, userID int64, publicID uuid.UUID) (int64, error) {
	return r.q.MarkNotificationRead(ctx, store.MarkNotificationReadParams{
		UserID: userID, PublicID: publicID,
	})
}

func (r *Repository) MarkAllRead(ctx context.Context, userID int64) (int64, error) {
	return r.q.MarkAllNotificationsRead(ctx, userID)
}

func (r *Repository) Tokens(ctx context.Context, userID int64) ([]string, error) {
	rows, err := r.q.ListNotificationDeviceTokens(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(rows))
	for _, token := range rows {
		if token != nil && *token != "" {
			out = append(out, *token)
		}
	}
	return out, nil
}

func (r *Repository) MarkPushed(ctx context.Context, userID int64, publicID uuid.UUID) error {
	return r.q.MarkNotificationPushed(ctx, store.MarkNotificationPushedParams{
		UserID: userID, PublicID: publicID,
	})
}

func (r *Repository) Cadences(ctx context.Context) ([]store.ListGroupCadencesRow, error) {
	return r.q.ListGroupCadences(ctx)
}

func (r *Repository) MembersWithoutContribution(ctx context.Context, groupID int64, startUnix, endUnix int64) ([]store.ListMembersWithoutContributionRow, error) {
	return r.q.ListMembersWithoutContribution(ctx, store.ListMembersWithoutContributionParams{
		GroupID:     groupID,
		PeriodStart: timeFromUnix(startUnix),
		PeriodEnd:   timeFromUnix(endUnix),
	})
}
