package fines

import (
	"context"
	"errors"
	"fmt"
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

func (s *Service) SetNotifier(n notifications.Notifier) { s.notifier = n }

func (s *Service) Rules(ctx context.Context, groupID int64) ([]RuleView, error) {
	rows, err := s.repo.Rules(ctx, groupID)
	if err != nil {
		return nil, err
	}
	out := make([]RuleView, 0, len(rows))
	for _, row := range rows {
		out = append(out, RuleView{
			FineType: row.FineType, CalculationMethod: row.CalculationMethod,
			AmountOrRate: row.AmountOrRate, GraceDays: row.GraceDays, UpdatedAt: row.UpdatedAt,
		})
	}
	return out, nil
}

func (s *Service) PutRule(ctx context.Context, groupID int64, fineType string, in RuleInput) ([]RuleView, error) {
	if !fineTypes[fineType] {
		return nil, httpx.NotFound("Fine type not found.")
	}
	fields := map[string]string{}
	if in.CalculationMethod != "flat" && in.CalculationMethod != "percentage" {
		fields["calculation_method"] = "Choose flat or percentage."
	}
	amount, err := money.ParseAmount(in.AmountOrRate)
	if err != nil {
		fields["amount_or_rate"] = "Enter a positive amount or percentage."
	} else if in.CalculationMethod == "percentage" && int64(amount) > 10000 {
		fields["amount_or_rate"] = "A percentage cannot exceed 100."
	}
	if in.GraceDays < 0 || in.GraceDays > 60 {
		fields["grace_days"] = "Grace days must be between 0 and 60."
	}
	if len(fields) > 0 {
		return nil, httpx.Validation(fields)
	}
	if err := s.repo.PutRule(ctx, groupID, fineType, in.CalculationMethod,
		amount.String(), in.GraceDays); err != nil {
		return nil, err
	}
	return s.Rules(ctx, groupID)
}

func (s *Service) Create(ctx context.Context, groupID int64, in CreateInput) (FineView, error) {
	publicID, err := uuid.Parse(strings.TrimSpace(in.UserID))
	if err != nil {
		return FineView{}, httpx.Validation(map[string]string{"user_id": "Choose an active member."})
	}
	member, err := s.repo.MemberByPublicID(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return FineView{}, httpx.Validation(map[string]string{"user_id": "Choose an active member."})
	}
	if err != nil {
		return FineView{}, err
	}
	amount, err := money.ParseAmount(in.Amount)
	if err != nil {
		return FineView{}, httpx.Validation(map[string]string{"amount": "Enter a positive amount."})
	}
	reason := strings.TrimSpace(in.Reason)
	if len(reason) < 1 || len(reason) > 200 {
		return FineView{}, httpx.Validation(map[string]string{"reason": "Give a reason of 1 to 200 characters."})
	}
	row, err := s.repo.Create(ctx, store.CreateFineParams{
		GroupID: groupID, UserID: member.ID, FineType: "custom",
		AmountCents: int64(amount), Reason: reason,
	})
	if err != nil {
		return FineView{}, err
	}
	s.notifyFine(ctx, groupID, member.ID, row.PublicID, int64(amount), reason)
	return s.Get(ctx, groupID, row.PublicID, member.ID, true)
}

func (s *Service) List(ctx context.Context, groupID, requesterID int64, manager bool, status string, limit int32) ([]FineView, error) {
	params := store.ListFinesParams{GroupID: groupID, RowLimit: limit}
	if !manager {
		params.UserID = &requesterID
	}
	if status != "" {
		if !fineStatuses[status] {
			return nil, httpx.Validation(map[string]string{"status": "Unknown fine status."})
		}
		params.Status = &status
	}
	rows, err := s.repo.List(ctx, params)
	if err != nil {
		return nil, err
	}
	out := make([]FineView, 0, len(rows))
	for _, row := range rows {
		out = append(out, listView(row))
	}
	return out, nil
}

func (s *Service) Get(ctx context.Context, groupID int64, publicID uuid.UUID, requesterID int64, manager bool) (FineView, error) {
	row, err := s.repo.Fine(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return FineView{}, httpx.NotFound("Fine not found.")
	}
	if err != nil {
		return FineView{}, err
	}
	if !manager && row.UserID != requesterID {
		return FineView{}, httpx.NotFound("Fine not found.")
	}
	return detailView(row), nil
}

func (s *Service) Waive(ctx context.Context, groupID int64, publicID uuid.UUID, actorID int64, in WaiveInput) (FineView, error) {
	reason := strings.TrimSpace(in.Reason)
	if len(reason) < 1 || len(reason) > 200 {
		return FineView{}, httpx.Validation(map[string]string{"reason": "Give a reason of 1 to 200 characters."})
	}
	if err := s.repo.Waive(ctx, store.WaiveFineParams{
		WaivedBy: &actorID, WaiveReason: &reason, GroupID: groupID, PublicID: publicID,
	}); errors.Is(err, ErrNotPayable) {
		return FineView{}, httpx.Conflict("fine_not_unpaid", "Only an unpaid fine can be waived.")
	} else if err != nil {
		return FineView{}, err
	}
	return s.Get(ctx, groupID, publicID, actorID, true)
}

func (s *Service) Pay(ctx context.Context, groupID int64, publicID uuid.UUID, actorID int64, in PayInput) (PaymentResult, error) {
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return PaymentResult{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	amount, err := money.ParseAmount(in.Amount)
	if err != nil {
		return PaymentResult{}, httpx.Validation(map[string]string{"amount": "Enter a positive amount."})
	}
	fine, err := s.repo.Fine(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return PaymentResult{}, httpx.NotFound("Fine not found.")
	}
	if err != nil {
		return PaymentResult{}, err
	}
	if fine.Status != "unpaid" {
		return PaymentResult{}, httpx.Conflict("fine_not_unpaid", "Only an unpaid fine can be paid.")
	}
	if int64(amount) != fine.AmountCents {
		return PaymentResult{}, httpx.Unprocessable("fine_payment_amount_mismatch",
			"Record the full fine amount of "+money.Cents(fine.AmountCents).String()+".")
	}
	reference := fmt.Sprintf("FNE-%d", time.Now().UTC().UnixNano())
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	txID, err := s.repo.Pay(ctx, Payment{
		GroupID: groupID, PublicID: publicID, UserID: fine.UserID, ActorID: actorID,
		AmountCents: int64(amount), Channel: channel, Reference: reference, Reason: fine.Reason,
	})
	if errors.Is(err, ErrNotPayable) {
		return PaymentResult{}, httpx.Conflict("fine_not_unpaid", "Only an unpaid fine can be paid.")
	}
	if err != nil {
		return PaymentResult{}, err
	}
	view, err := s.Get(ctx, groupID, publicID, actorID, true)
	if err != nil {
		return PaymentResult{}, err
	}
	return PaymentResult{Fine: view, TransactionID: txID.String()}, nil
}

// EvaluateGroup marks the most recently completed period for one chama.
func (s *Service) EvaluateGroup(ctx context.Context, groupID int64) (int64, error) {
	group, err := s.repo.Group(ctx, groupID)
	if err != nil {
		return 0, err
	}
	period := PreviousPeriod(time.Now(), group.Frequency)
	return s.evaluate(ctx, groupID, period)
}

func (s *Service) evaluate(ctx context.Context, groupID int64, period Period) (int64, error) {
	rows, err := s.repo.Evaluate(ctx, groupID, period)
	if err != nil {
		return 0, err
	}
	for _, row := range rows {
		s.notifyFine(ctx, groupID, row.UserID, row.PublicID, row.AmountCents,
			"Contribution not recorded for "+period.Label)
	}
	return int64(len(rows)), nil
}

// EvaluateAll is the nightly entry point; the unique fine key makes reruns safe.
func (s *Service) EvaluateAll(ctx context.Context) (EvaluationResult, error) {
	groups, err := s.repo.Groups(ctx)
	if err != nil {
		return EvaluationResult{}, err
	}
	out := EvaluationResult{Groups: len(groups)}
	for _, group := range groups {
		period := PreviousPeriod(time.Now(), group.Frequency)
		created, err := s.evaluate(ctx, group.ID, period)
		if err != nil {
			return out, err
		}
		out.Created += created
	}
	return out, nil
}

func (s *Service) notifyFine(ctx context.Context, groupID, userID int64, publicID uuid.UUID, amountCents int64, reason string) {
	if s.notifier == nil {
		return
	}
	_ = s.notifier.Notify(ctx, notifications.Event{
		UserID: userID, GroupID: &groupID, Type: "fine_applied",
		Title: "Fine applied", Body: money.Cents(amountCents).String() + " - " + reason,
		Data:      map[string]any{"fine_id": publicID.String()},
		DedupeKey: "fine:" + publicID.String(),
	})
}

func detailView(row store.GetFineByPublicIDRow) FineView {
	return FineView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName, FineType: row.FineType,
		Amount: money.Cents(row.AmountCents).String(), Reason: row.Reason,
		Status: row.Status, PeriodLabel: row.PeriodLabel, AssessedOn: row.AssessedOn,
		WaiveReason: row.WaiveReason, Paid: row.Paid, CreatedAt: row.CreatedAt,
	}
}

func listView(row store.ListFinesRow) FineView {
	return FineView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName, FineType: row.FineType,
		Amount: money.Cents(row.AmountCents).String(), Reason: row.Reason,
		Status: row.Status, PeriodLabel: row.PeriodLabel, AssessedOn: row.AssessedOn,
		WaiveReason: row.WaiveReason, Paid: row.Paid, CreatedAt: row.CreatedAt,
	}
}
