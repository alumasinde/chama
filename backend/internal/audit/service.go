package audit

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Record(ctx context.Context, entry Entry) error {
	entry.Action = strings.TrimSpace(entry.Action)
	entry.EntityType = strings.TrimSpace(entry.EntityType)
	if entry.GroupID <= 0 || entry.Action == "" || entry.EntityType == "" {
		return errors.New("audit entry is missing group, action or entity")
	}
	return s.repo.Insert(ctx, entry)
}

func (s *Service) List(ctx context.Context, groupID int64, filter Filter) ([]View, error) {
	return s.repo.List(ctx, groupID, filter)
}

func (s *Service) Get(ctx context.Context, groupID int64, publicID uuid.UUID) (View, error) {
	view, err := s.repo.Get(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return View{}, httpx.NotFound("Audit entry not found.")
	}
	return view, err
}
