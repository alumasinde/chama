package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
)

// repository is the storage surface the service needs; tests supply a fake around it.
type repository interface {
	Insert(ctx context.Context, e Event) (uuid.UUID, bool, error)
	Tokens(ctx context.Context, userID int64) ([]string, error)
	MarkPushed(ctx context.Context, userID int64, publicID uuid.UUID) error
	List(ctx context.Context, userID int64, unread bool, limit int32) ([]store.ListNotificationsRow, error)
	Unread(ctx context.Context, userID int64) (int64, error)
	MarkRead(ctx context.Context, userID int64, publicID uuid.UUID) (int64, error)
	MarkAllRead(ctx context.Context, userID int64) (int64, error)
	Cadences(ctx context.Context) ([]store.ListGroupCadencesRow, error)
	MembersWithoutContribution(ctx context.Context, groupID int64, startUnix, endUnix int64) ([]store.ListMembersWithoutContributionRow, error)
}

type Service struct {
	repo repository
	push Pusher
	log  *slog.Logger
}

func NewService(repo repository, push Pusher, log *slog.Logger) *Service {
	return &Service{repo: repo, push: push, log: log}
}

// Notify inserts once per dedupe key, then pushes best-effort to registered devices.
func (s *Service) Notify(ctx context.Context, e Event) error {
	if e.UserID == 0 || strings.TrimSpace(e.Title) == "" || strings.TrimSpace(e.Body) == "" {
		return nil
	}
	if e.Type == "" {
		e.Type = "general"
	}
	id, created, err := s.repo.Insert(ctx, e)
	if err != nil {
		return err
	}
	if !created {
		return nil
	}
	tokens, err := s.repo.Tokens(ctx, e.UserID)
	if err != nil {
		s.log.WarnContext(ctx, "load notification devices", "error", err)
		return nil
	}
	if len(tokens) > 0 {
		data := map[string]string{}
		for k, v := range e.Data {
			data[k] = fmt.Sprint(v)
		}
		if err := s.push.Push(ctx, tokens, Message{Title: e.Title, Body: e.Body, Data: data}); err != nil {
			s.log.WarnContext(ctx, "push notification failed", "provider", s.push.Name(), "error", err)
			return nil
		}
	}
	if err := s.repo.MarkPushed(ctx, e.UserID, id); err != nil {
		s.log.WarnContext(ctx, "mark notification pushed", "error", err)
	}
	return nil
}

func (s *Service) List(ctx context.Context, userID int64, unread bool, limit int32) (ListResult, error) {
	rows, err := s.repo.List(ctx, userID, unread, limit)
	if err != nil {
		return ListResult{}, err
	}
	out := make([]View, 0, len(rows))
	for _, row := range rows {
		data := map[string]any{}
		if len(row.Data) > 0 {
			_ = json.Unmarshal(row.Data, &data)
		}
		out = append(out, View{
			ID: row.PublicID.String(), Type: row.NotificationType, Title: row.Title,
			Body: row.Body, Data: data, ReadAt: row.ReadAt, CreatedAt: row.CreatedAt,
		})
	}
	unreadCount, err := s.repo.Unread(ctx, userID)
	if err != nil {
		return ListResult{}, err
	}
	return ListResult{Data: out, UnreadCount: unreadCount}, nil
}

func (s *Service) MarkRead(ctx context.Context, userID int64, in ReadInput) (int64, error) {
	if in.All {
		return s.repo.MarkAllRead(ctx, userID)
	}
	if len(in.IDs) == 0 {
		return 0, httpx.Validation(map[string]string{"ids": "Choose at least one notification."})
	}
	var changed int64
	for _, raw := range in.IDs {
		id, err := uuid.Parse(strings.TrimSpace(raw))
		if err != nil {
			return changed, httpx.Validation(map[string]string{"ids": "One notification id is not valid."})
		}
		n, err := s.repo.MarkRead(ctx, userID, id)
		if err != nil {
			return changed, err
		}
		changed += n
	}
	return changed, nil
}

// DueReminders creates one reminder per active member still missing the current period.
func (s *Service) DueReminders(ctx context.Context) (int, error) {
	groups, err := s.repo.Cadences(ctx)
	if err != nil {
		return 0, err
	}
	now := time.Now().UTC()
	created := 0
	for _, group := range groups {
		start, end, label := CurrentPeriod(now, group.Frequency)
		members, err := s.repo.MembersWithoutContribution(ctx, group.GroupID, start.Unix(), end.Unix())
		if err != nil {
			return created, err
		}
		for _, member := range members {
			err := s.Notify(ctx, Event{
				UserID: member.UserID, GroupID: &group.GroupID, Type: "contribution_due",
				Title: "Contribution due", Body: group.Name + " is expecting your " + label + " contribution.",
				Data:      map[string]any{"group_id": group.PublicID.String(), "period": label},
				DedupeKey: "due:" + strconv.FormatInt(group.GroupID, 10) + ":" + strconv.FormatInt(member.UserID, 10) + ":" + label,
			})
			if err != nil {
				return created, err
			}
			created++
		}
	}
	return created, nil
}

// CurrentPeriod returns the period a reminder belongs to, labelled for humans.
func CurrentPeriod(now time.Time, frequency string) (time.Time, time.Time, string) {
	now = now.UTC()
	switch frequency {
	case "weekly", "biweekly":
		start := startOfISOWeek(now)
		end := start.AddDate(0, 0, 7)
		if frequency == "biweekly" {
			end = start.AddDate(0, 0, 14)
		}
		return start, end, "week of " + start.Format("2 Jan 2006")
	case "quarterly":
		month := time.Month(((int(now.Month())-1)/3)*3 + 1)
		start := time.Date(now.Year(), month, 1, 0, 0, 0, 0, time.UTC)
		return start, start.AddDate(0, 3, 0), fmt.Sprintf("%d-Q%d", start.Year(), (int(start.Month())-1)/3+1)
	default:
		start := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
		return start, start.AddDate(0, 1, 0), start.Format("January 2006")
	}
}

func startOfISOWeek(t time.Time) time.Time {
	day := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
	offset := (int(day.Weekday()) + 6) % 7
	return day.AddDate(0, 0, -offset)
}

func timeFromUnix(value int64) time.Time { return time.Unix(value, 0).UTC() }
