package welfare

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

func (s *Service) CreateClaim(ctx context.Context, groupID, userID int64, in ClaimInput) (ClaimView, error) {
	fund, err := s.repo.Fund(ctx, groupID)
	if errors.Is(err, ErrNotFound) {
		return ClaimView{}, httpx.Unprocessable("welfare_fund_missing", "Set up the welfare fund first.")
	}
	if err != nil {
		return ClaimView{}, err
	}
	if !fund.IsActive {
		return ClaimView{}, httpx.Unprocessable("welfare_inactive", "The welfare fund is not active.")
	}
	amount, err := money.ParseAmount(in.Amount)
	if err != nil {
		return ClaimView{}, httpx.Validation(map[string]string{"amount": "Enter a positive amount."})
	}
	reason := strings.TrimSpace(in.Reason)
	if len(reason) < 1 || len(reason) > 300 {
		return ClaimView{}, httpx.Validation(map[string]string{"reason": "Give a reason of 1 to 300 characters."})
	}
	row, err := s.repo.CreateClaim(ctx, store.InsertWelfareClaimParams{
		GroupID: groupID, FundID: fund.ID, UserID: userID, AmountCents: int64(amount), Reason: reason,
	})
	if err != nil {
		return ClaimView{}, err
	}
	return s.GetClaim(ctx, groupID, row.PublicID, userID, true)
}

func (s *Service) Claims(ctx context.Context, groupID, requesterID int64, manager bool, status string, limit int32) ([]ClaimView, error) {
	params := store.ListWelfareClaimsParams{GroupID: groupID, RowLimit: limit}
	if !manager {
		params.UserID = &requesterID
	}
	if status != "" {
		if !claimStatuses[status] {
			return nil, httpx.Validation(map[string]string{"status": "Unknown claim status."})
		}
		params.Status = &status
	}
	rows, err := s.repo.Claims(ctx, params)
	if err != nil {
		return nil, err
	}
	out := make([]ClaimView, 0, len(rows))
	for _, row := range rows {
		out = append(out, ClaimView{
			ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
			Member: row.FirstName + " " + row.LastName, Amount: money.Cents(row.AmountCents).String(),
			Reason: row.Reason, Status: row.Status, RequestedAt: row.RequestedAt,
			DecidedAt: row.DecidedAt, DecidedBy: person(row.DecidedByFirstName, row.DecidedByLastName),
			Comment: row.Comment, PayoutTransactionID: publicIDString(row.PayoutTransactionPublicID),
		})
	}
	return out, nil
}

func (s *Service) GetClaim(ctx context.Context, groupID int64, publicID uuid.UUID, requesterID int64, manager bool) (ClaimView, error) {
	row, err := s.repo.Claim(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return ClaimView{}, httpx.NotFound("Welfare claim not found.")
	}
	if err != nil {
		return ClaimView{}, err
	}
	if !manager && row.UserID != requesterID {
		return ClaimView{}, httpx.NotFound("Welfare claim not found.")
	}
	return ClaimView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName, Amount: money.Cents(row.AmountCents).String(),
		Reason: row.Reason, Status: row.Status, RequestedAt: row.RequestedAt,
		DecidedAt: row.DecidedAt, DecidedBy: person(row.DecidedByFirstName, row.DecidedByLastName),
		Comment: row.Comment, PayoutTransactionID: publicIDString(row.PayoutTransactionPublicID),
	}, nil
}

func (s *Service) DecideClaim(ctx context.Context, groupID int64, publicID uuid.UUID, actorID int64, in ClaimDecisionInput) (ClaimView, error) {
	decision := strings.TrimSpace(in.Decision)
	if decision != "approved" && decision != "rejected" {
		return ClaimView{}, httpx.Validation(map[string]string{"decision": "Choose approved or rejected."})
	}
	var comment *string
	if in.Comment != nil {
		clean := strings.TrimSpace(*in.Comment)
		if len(clean) > 300 {
			return ClaimView{}, httpx.Validation(map[string]string{"comment": "Use at most 300 characters."})
		}
		if clean != "" {
			comment = &clean
		}
	}
	err := s.repo.Decide(ctx, store.DecideWelfareClaimParams{
		Status: decision, DecidedBy: &actorID, Comment: comment,
		GroupID: groupID, PublicID: publicID,
	})
	if errors.Is(err, ErrNotPending) {
		return ClaimView{}, httpx.Conflict("claim_not_pending", "Only a pending claim can be decided.")
	}
	if err != nil {
		return ClaimView{}, err
	}
	return s.GetClaim(ctx, groupID, publicID, actorID, true)
}

func (s *Service) PayoutClaim(ctx context.Context, groupID int64, publicID uuid.UUID, actorID int64, in ClaimPayoutInput) (PayoutResult, error) {
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return PayoutResult{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	reference := manualReference()
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	txID, err := s.repo.Payout(ctx, Payout{
		GroupID: groupID, PublicID: publicID, ActorID: actorID, Channel: channel, Reference: reference,
	})
	switch {
	case errors.Is(err, ErrNotApproved):
		return PayoutResult{}, httpx.Conflict("claim_not_approved", "Only an approved claim can be paid.")
	case errors.Is(err, ErrFundsShortfall):
		return PayoutResult{}, httpx.Unprocessable("welfare_insufficient_funds",
			"The welfare fund does not have enough balance for this claim.")
	case errors.Is(err, ErrNotFound):
		return PayoutResult{}, httpx.NotFound("Welfare claim not found.")
	case err != nil:
		return PayoutResult{}, err
	}
	view, err := s.GetClaim(ctx, groupID, publicID, actorID, true)
	if err != nil {
		return PayoutResult{}, err
	}
	return PayoutResult{Claim: view, TransactionID: txID.String()}, nil
}

func person(first, last *string) *string {
	if first == nil || last == nil {
		return nil
	}
	name := *first + " " + *last
	return &name
}
