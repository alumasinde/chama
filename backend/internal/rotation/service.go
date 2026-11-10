package rotation

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/notifications"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

type Service struct {
	repo     *Repository
	log      *slog.Logger
	notifier notifications.Notifier
}

func NewService(repo *Repository, log *slog.Logger) *Service {
	return &Service{repo: repo, log: log}
}

// SetNotifier is optional so tests and deployments without push still work.
func (s *Service) SetNotifier(n notifications.Notifier) { s.notifier = n }

func (s *Service) Cycles(ctx context.Context, groupID int64, limit int32) ([]CycleView, error) {
	rows, err := s.repo.Cycles(ctx, groupID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]CycleView, 0, len(rows))
	for _, row := range rows {
		out = append(out, listCycleView(row))
	}
	return out, nil
}

func (s *Service) Cycle(ctx context.Context, groupID int64, publicID uuid.UUID) (CycleView, error) {
	row, err := s.repo.Cycle(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return CycleView{}, httpx.NotFound("Rotation cycle not found.")
	}
	if err != nil {
		return CycleView{}, err
	}
	view := cycleView(row)
	slots, err := s.repo.Slots(ctx, groupID, row.ID)
	if err != nil {
		return CycleView{}, err
	}
	view.Slots = make([]SlotView, 0, len(slots))
	for _, slot := range slots {
		view.Slots = append(view.Slots, listSlotView(slot))
	}
	return view, nil
}

func (s *Service) Proposals(ctx context.Context, groupID int64, cyclePublicID uuid.UUID, limit int32) ([]ProposalSummaryView, error) {
	rows, err := s.repo.Proposals(ctx, groupID, cyclePublicID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]ProposalSummaryView, 0, len(rows))
	for _, row := range rows {
		needed := (int32(row.EligibleMembers)*int32(row.QuorumPercent) + 99) / 100
		out = append(out, ProposalSummaryView{
			ID: row.PublicID.String(), Status: row.Status, QuorumPct: row.QuorumPercent,
			Eligible: row.EligibleMembers, For: row.ForCount, Against: row.AgainstCount,
			Abstain: row.AbstainCount, Total: row.TotalCount, Needed: needed,
			OpensAt: row.OpensAt, ClosesAt: row.ClosesAt, ClosedAt: row.ClosedAt,
			CreatedAt: row.CreatedAt,
		})
	}
	return out, nil
}

func (s *Service) Create(ctx context.Context, groupID, actorID int64, in CreateInput) (CycleView, error) {
	name := strings.TrimSpace(in.Name)
	if len(name) < 1 || len(name) > 80 {
		return CycleView{}, httpx.Validation(map[string]string{"name": "Give the cycle a name of 1 to 80 characters."})
	}
	mode := strings.TrimSpace(in.OrderingMode)
	if !orderingModes[mode] {
		return CycleView{}, httpx.Validation(map[string]string{"ordering_mode": "Choose random, manual or vote."})
	}
	amount, err := money.ParseAmount(in.Contribution)
	if err != nil {
		return CycleView{}, httpx.Validation(map[string]string{"contribution_amount": "Enter a positive amount."})
	}
	startsOn, err := time.Parse("2006-01-02", strings.TrimSpace(in.StartsOn))
	if err != nil {
		return CycleView{}, httpx.Validation(map[string]string{"starts_on": "Use a date like 2026-11-15."})
	}
	members, byPublic, err := s.activeMembers(ctx, groupID)
	if err != nil {
		return CycleView{}, err
	}
	if len(members) < 2 {
		return CycleView{}, httpx.Unprocessable("rotation_members_short", "A rotation needs at least two active members.")
	}
	order := make([]int64, 0, len(members))
	if mode == "manual" {
		order, err = resolveOrder(in.Slots, byPublic, len(members))
		if err != nil {
			return CycleView{}, err
		}
	} else if len(in.Slots) > 0 {
		return CycleView{}, httpx.Validation(map[string]string{
			"slots": "Only a manual cycle takes its order now.",
		})
	}
	publicID, err := s.repo.Create(ctx, store.CreateRotationCycleParams{
		GroupID: groupID, Name: name, OrderingMode: mode,
		ContributionCents: int64(amount), StartsOn: startsOn.Format("2006-01-02"), CreatedBy: actorID,
	}, s.slotSpecs(ctx, order, startsOn, groupID))
	if err != nil {
		return CycleView{}, err
	}
	return s.Cycle(ctx, groupID, publicID)
}

func (s *Service) Start(ctx context.Context, groupID int64, publicID uuid.UUID) (CycleView, error) {
	seed := ""
	var err error
	if seed, err = randomSeed(); err != nil {
		return CycleView{}, err
	}
	if err := s.repo.Start(ctx, groupID, publicID, seed); err != nil {
		switch {
		case errors.Is(err, ErrAlreadyStarted):
			return CycleView{}, httpx.Conflict("cycle_already_started", "This cycle has already started.")
		case errors.Is(err, ErrRequiresVote):
			return CycleView{}, httpx.Conflict("cycle_requires_vote", "Members must approve the order before this cycle can start.")
		case errors.Is(err, ErrNotFound):
			return CycleView{}, httpx.NotFound("Rotation cycle not found.")
		case errors.Is(err, ErrStateChanged):
			return CycleView{}, httpx.Conflict("cycle_state_changed", "The member list changed. Create the cycle again.")
		default:
			return CycleView{}, err
		}
	}
	view, err := s.Cycle(ctx, groupID, publicID)
	if err != nil {
		return CycleView{}, err
	}
	s.notifyStarted(ctx, groupID, view)
	return view, nil
}

func (s *Service) MyRotation(ctx context.Context, userID int64, limit int32) ([]MyRotationView, error) {
	rows, err := s.repo.My(ctx, userID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]MyRotationView, 0, len(rows))
	for _, row := range rows {
		out = append(out, MyRotationView{
			GroupID: row.GroupPublicID.String(), GroupName: row.GroupName,
			CycleID: row.CyclePublicID.String(), CycleName: row.CycleName,
			Position: row.Position, PayoutDate: row.PayoutDate, Paid: row.Paid,
		})
	}
	return out, nil
}

func (s *Service) activeMembers(ctx context.Context, groupID int64) ([]int64, map[string]int64, error) {
	rows, err := s.repo.Members(ctx, groupID)
	if err != nil {
		return nil, nil, err
	}
	ids := make([]int64, 0, len(rows))
	byPublic := make(map[string]int64, len(rows))
	for _, row := range rows {
		ids = append(ids, row.UserID)
		byPublic[row.UserPublicID.String()] = row.UserID
	}
	return ids, byPublic, nil
}

func (s *Service) slotSpecs(ctx context.Context, order []int64, startsOn time.Time, groupID int64) []SlotSpec {
	frequency, err := s.repo.Frequency(ctx, groupID)
	if err != nil {
		frequency = "monthly"
	}
	specs := make([]SlotSpec, 0, len(order))
	for i, memberID := range order {
		specs = append(specs, SlotSpec{MemberID: memberID, Position: int16(i + 1),
			PayoutDate: PayoutDate(startsOn, i, frequency)})
	}
	return specs
}

// notifyCycleStarted reloads the materialised cycle so both endpoint and job starts share one payload.
func (s *Service) notifyCycleStarted(ctx context.Context, groupID int64, cycleID uuid.UUID) {
	view, err := s.Cycle(ctx, groupID, cycleID)
	if err != nil {
		s.log.Error("rotation notification lookup failed", "error", err, "group_id", groupID, "cycle_id", cycleID)
		return
	}
	s.notifyStarted(ctx, groupID, view)
}

func (s *Service) notifyStarted(ctx context.Context, groupID int64, view CycleView) {
	if s.notifier == nil {
		return
	}
	for _, slot := range view.Slots {
		uid, err := uuid.Parse(slot.UserID)
		if err != nil {
			continue
		}
		memberID, err := s.repo.MemberID(ctx, groupID, uid)
		if err != nil {
			continue
		}
		_ = s.notifier.Notify(ctx, notifications.Event{
			UserID: memberID, GroupID: &groupID, Type: "rotation_turn",
			Title:     "Rotation order set",
			Body:      "You are number " + itoa(int(slot.Position)) + " in " + view.Name + ", paid on " + slot.PayoutDate + ".",
			Data:      map[string]any{"cycle_id": view.ID, "position": slot.Position},
			DedupeKey: "rotation:" + view.ID + ":start:" + slot.UserID,
		})
	}
}

func resolveOrder(raw []string, active map[string]int64, want int) ([]int64, error) {
	if len(raw) != want {
		return nil, httpx.Validation(map[string]string{
			"slots": "List every active member exactly once, in payout order.",
		})
	}
	order := make([]int64, 0, len(raw))
	seen := map[int64]bool{}
	for _, value := range raw {
		id, ok := active[strings.TrimSpace(value)]
		if !ok || seen[id] {
			return nil, httpx.Validation(map[string]string{
				"slots": "List every active member exactly once, in payout order.",
			})
		}
		seen[id] = true
		order = append(order, id)
	}
	return order, nil
}

func randomSeed() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var digits [20]byte
	i := len(digits)
	for n > 0 {
		i--
		digits[i] = byte('0' + n%10)
		n /= 10
	}
	return string(digits[i:])
}
