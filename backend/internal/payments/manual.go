package payments

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/users"
)

// ManualInput records a contribution the treasurer already received outside the app.
type ManualInput struct {
	MemberID  string `json:"member_id"`
	Amount    string `json:"amount"`
	Reference string `json:"reference"`
	Narration string `json:"narration"`
}

type ManualResult struct {
	TransactionID string    `json:"transaction_id"`
	MemberID      string    `json:"member_id"`
	Amount        string    `json:"amount"`
	Reference     string    `json:"reference"`
	RecordedAt    time.Time `json:"recorded_at"`
}

// RecordManualContribution writes one completed contribution row, with the M-Pesa code as its
// reference, for chamas whose members pay a paybill or hand cash to the treasurer.
func (s *Service) RecordManualContribution(ctx context.Context, actor users.User, group groups.Group, in ManualInput) (ManualResult, error) {
	memberID, err := uuid.Parse(strings.TrimSpace(in.MemberID))
	if err != nil {
		return ManualResult{}, httpx.Validation(map[string]string{"member_id": "Choose the member who paid."})
	}
	cents, err := money.ParseAmount(in.Amount)
	if err != nil || cents < 100 {
		return ManualResult{}, httpx.Validation(map[string]string{"amount": "Enter an amount of at least KES 1.00."})
	}
	if int64(cents)%100 != 0 {
		return ManualResult{}, httpx.Unprocessable("amount_not_whole_shillings", "M-Pesa accepts whole shillings only.")
	}
	reference := strings.ToUpper(strings.TrimSpace(in.Reference))
	if !validMpesaCode(reference) {
		return ManualResult{}, httpx.Validation(map[string]string{
			"reference": "Enter the M-Pesa code from the SMS, for example SLK7XQ2P9D.",
		})
	}
	narration := strings.TrimSpace(in.Narration)
	if narration == "" {
		narration = "Contribution recorded by the treasurer"
	}
	if len(narration) > 120 {
		return ManualResult{}, httpx.Validation(map[string]string{"narration": "Keep the note under 120 characters."})
	}

	row, err := s.repo.RecordManualContribution(ctx, ManualParams{
		GroupID:        group.ID,
		MemberPublicID: memberID,
		AmountCents:    int64(cents),
		ReferenceCode:  reference,
		Narration:      narration,
		RecordedBy:     actor.ID,
	})
	switch {
	case errors.Is(err, ErrMemberNotActive):
		return ManualResult{}, httpx.Validation(map[string]string{"member_id": "Choose an active member of this chama."})
	case errors.Is(err, ErrReferenceRecorded):
		return ManualResult{}, httpx.Conflict("reference_already_recorded",
			"That M-Pesa code is already in this chama's ledger.")
	case err != nil:
		return ManualResult{}, err
	}

	if s.onSettled != nil {
		s.onSettled(ctx, SettledEvent{
			GroupID: group.ID, GroupPublicID: group.PublicID, UserID: row.UserID,
			AmountCents: int64(cents), Purpose: "contribution", Status: "completed",
			Receipt: reference, TransactionID: row.ID, TransactionPublicID: row.TransactionID,
		})
	}
	return ManualResult{
		TransactionID: row.TransactionID.String(),
		MemberID:      memberID.String(),
		Amount:        cents.String(),
		Reference:     reference,
		RecordedAt:    row.CreatedAt,
	}, nil
}

// validMpesaCode accepts the receipt codes Safaricom sends, ignoring case and spaces.
func validMpesaCode(value string) bool {
	if len(value) < 6 || len(value) > 24 {
		return false
	}
	for _, r := range value {
		if (r < 'A' || r > 'Z') && (r < '0' || r > '9') {
			return false
		}
	}
	return true
}
