package welfare

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

type Service struct {
	repo *Repository
	log  *slog.Logger
}

func NewService(repo *Repository, log *slog.Logger) *Service {
	return &Service{repo: repo, log: log}
}

func (s *Service) Fund(ctx context.Context, groupID int64) (FundView, error) {
	row, err := s.repo.Fund(ctx, groupID)
	if errors.Is(err, ErrNotFound) {
		return FundView{Configured: false, IsActive: false}, nil
	}
	if err != nil {
		return FundView{}, err
	}
	return fundView(row), nil
}

func (s *Service) SaveFund(ctx context.Context, groupID int64, in FundInput) (FundView, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" {
		name = "Welfare fund"
	}
	if len(name) > 80 {
		return FundView{}, httpx.Validation(map[string]string{"name": "Use a name of at most 80 characters."})
	}
	amount, err := money.ParseAmount(in.MonthlyAmount)
	if err != nil {
		return FundView{}, httpx.Validation(map[string]string{"monthly_amount": "Enter a positive amount or zero."})
	}
	active := true
	if in.IsActive != nil {
		active = *in.IsActive
	}
	if err := s.repo.SaveFund(ctx, store.UpsertWelfareFundParams{
		GroupID: groupID, Name: name, MonthlyCents: int64(amount), IsActive: active,
	}); err != nil {
		return FundView{}, err
	}
	return s.Fund(ctx, groupID)
}

func (s *Service) Contributions(ctx context.Context, groupID, requesterID int64, manager bool, limit int32) ([]ContributionView, error) {
	params := store.ListWelfareContributionsParams{GroupID: groupID, RowLimit: limit}
	if !manager {
		params.UserID = &requesterID
	}
	rows, err := s.repo.Contributions(ctx, params)
	if err != nil {
		return nil, err
	}
	out := make([]ContributionView, 0, len(rows))
	for _, row := range rows {
		out = append(out, ContributionView{
			ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
			Member: row.FirstName + " " + row.LastName, Amount: money.Cents(row.AmountCents).String(),
			PeriodLabel: row.PeriodLabel, TransactionID: publicIDString(row.TransactionPublicID),
			CreatedAt: row.CreatedAt,
		})
	}
	return out, nil
}

func (s *Service) Contribute(ctx context.Context, groupID int64, in ContributionInput) (ContributionView, error) {
	member, err := s.member(ctx, groupID, in.UserID)
	if err != nil {
		return ContributionView{}, err
	}
	fund, err := s.repo.Fund(ctx, groupID)
	if errors.Is(err, ErrNotFound) {
		return ContributionView{}, httpx.Unprocessable("welfare_fund_missing", "Set up the welfare fund first.")
	}
	if err != nil {
		return ContributionView{}, err
	}
	amount, err := money.ParseAmount(in.Amount)
	if err != nil {
		return ContributionView{}, httpx.Validation(map[string]string{"amount": "Enter a positive amount."})
	}
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return ContributionView{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	period := time.Now().UTC().Format("2006-01")
	if in.PeriodLabel != nil && strings.TrimSpace(*in.PeriodLabel) != "" {
		period = strings.TrimSpace(*in.PeriodLabel)
	}
	if len(period) > 20 {
		return ContributionView{}, httpx.Validation(map[string]string{"period_label": "Use at most 20 characters."})
	}
	reference := manualReference()
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	id, err := s.repo.ManualContribution(ctx, Contribution{
		GroupID: groupID, FundID: fund.ID, UserID: member.ID, AmountCents: int64(amount),
		Period: period, Channel: channel, Reference: reference,
	})
	if errors.Is(err, ErrDuplicate) {
		return ContributionView{}, httpx.Conflict("welfare_contribution_exists",
			"That member already has a contribution for this period.")
	}
	if err != nil {
		return ContributionView{}, err
	}
	return ContributionView{
		ID: id.String(), UserID: member.PublicID.String(),
		Member: member.FirstName + " " + member.LastName, Amount: amount.String(),
		PeriodLabel: period, CreatedAt: time.Now().UTC(),
	}, nil
}

// RecordSettledPayment links a completed M-Pesa welfare payment to the fund, once per period.
func (s *Service) RecordSettledPayment(ctx context.Context, groupID, userID, amountCents, transactionID int64) error {
	fund, err := s.repo.Fund(ctx, groupID)
	if errors.Is(err, ErrNotFound) || err != nil || !fund.IsActive {
		return nil
	}
	return s.repo.RecordContribution(ctx, Contribution{
		GroupID: groupID, FundID: fund.ID, UserID: userID, AmountCents: amountCents,
		Period: time.Now().UTC().Format("2006-01"),
	}, transactionID)
}

func (s *Service) member(ctx context.Context, groupID int64, raw string) (store.GetActiveMemberByPublicIDRow, error) {
	publicID, err := uuid.Parse(strings.TrimSpace(raw))
	if err != nil {
		return store.GetActiveMemberByPublicIDRow{}, httpx.Validation(map[string]string{"user_id": "Choose an active member."})
	}
	member, err := s.repo.Member(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return store.GetActiveMemberByPublicIDRow{}, httpx.Validation(map[string]string{"user_id": "Choose an active member."})
	}
	return member, err
}

func fundView(row store.GetWelfareFundRow) FundView {
	updated := row.UpdatedAt
	balance := row.ContributedCents - row.PaidOutCents
	return FundView{
		Configured: true, Name: row.Name, MonthlyAmount: money.Cents(row.MonthlyCents).String(),
		IsActive: row.IsActive, Balance: money.Cents(balance).String(),
		Contributed: money.Cents(row.ContributedCents).String(),
		PaidOut:     money.Cents(row.PaidOutCents).String(), UpdatedAt: &updated,
	}
}

func publicIDString(id pgtype.UUID) *string {
	if !id.Valid {
		return nil
	}
	value := uuid.UUID(id.Bytes).String()
	return &value
}
