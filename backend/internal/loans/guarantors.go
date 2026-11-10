package loans

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/users"
)

// GuaranteeDecision lets an invited guarantor accept or decline.
func (s *Service) GuaranteeDecision(ctx context.Context, scope groups.Scope, user users.User,
	publicID uuid.UUID, in GuaranteeDecisionInput) (LoanView, error) {
	decision := strings.TrimSpace(in.Decision)
	if decision != "accepted" && decision != "declined" {
		return LoanView{}, httpx.Validation(map[string]string{"decision": "Choose accepted or declined."})
	}
	row, err := s.repo.Loan(ctx, scope.Group.ID, publicID)
	if errors.Is(err, ErrNotFound) {
		return LoanView{}, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return LoanView{}, err
	}
	if row.Status != "pending_guarantors" {
		return LoanView{}, httpx.Conflict("loan_not_awaiting_guarantors",
			"This loan is no longer waiting for guarantors.")
	}
	counts, err := s.repo.Respond(ctx, scope.Group.ID, row.ID, user.ID, decision)
	if errors.Is(err, ErrStateChange) {
		return LoanView{}, httpx.Conflict("guarantor_decision_recorded",
			"You have already responded to this request.")
	}
	if err != nil {
		return LoanView{}, err
	}
	if counts.Pending == 0 {
		r, err := s.rules(ctx, scope.Group.ID)
		if err != nil {
			return LoanView{}, err
		}
		next := "rejected"
		if counts.Accepted >= int64(r.guarantors) {
			next = "pending_approval"
		}
		if err := s.repo.SetStatus(ctx, scope.Group.ID, row.ID, next, "pending_guarantors"); err != nil &&
			!errors.Is(err, ErrStateChange) {
			return LoanView{}, err
		}
	}
	return s.Detail(ctx, scope.Group.ID, publicID, user.ID, true)
}
