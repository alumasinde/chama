package loans

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

// Decide records the committee decision; approving freezes the schedule.
func (s *Service) Decide(ctx context.Context, scope groups.Scope, user users.User,
	publicID uuid.UUID, in DecisionInput) (LoanView, error) {
	decision := strings.TrimSpace(in.Decision)
	if decision != "approved" && decision != "rejected" {
		return LoanView{}, httpx.Validation(map[string]string{"decision": "Choose approved or rejected."})
	}
	row, err := s.repo.Loan(ctx, scope.Group.ID, publicID)
	if errors.Is(err, ErrNotFound) {
		return LoanView{}, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return LoanView{}, err
	}
	if row.Status != "pending_approval" {
		return LoanView{}, httpx.Conflict("loan_not_pending_approval",
			"This loan is not waiting for a committee decision.")
	}
	counts, err := s.repo.GuarantorCounts(ctx, row.ID)
	if err != nil {
		return LoanView{}, err
	}
	if counts.Pending > 0 {
		return LoanView{}, httpx.Unprocessable("guarantors_pending",
			"Wait for every invited guarantor to respond.")
	}
	r, err := s.rules(ctx, scope.Group.ID)
	if err != nil {
		return LoanView{}, err
	}
	if counts.Accepted < int64(r.guarantors) {
		return LoanView{}, httpx.Unprocessable("guarantors_missing",
			"This loan does not have the required accepted guarantors.")
	}

	record := ApprovalRecord{
		GroupID: scope.Group.ID, LoanID: row.ID, ApproverID: user.ID,
		Decision: decision, Comment: in.Comment, NextStatus: decision,
	}
	if decision == "approved" {
		schedule, err := BuildSchedule(ScheduleRequest{
			PrincipalCents: row.PrincipalCents, MonthlyRatePercent: row.InterestRate,
			Method: row.InterestMethod, TermMonths: int(row.TermMonths),
			FirstDue: time.Now().UTC().AddDate(0, 1, 0),
		})
		if err != nil {
			return LoanView{}, httpx.Unprocessable("loan_terms_invalid", "Those loan terms cannot be scheduled.")
		}
		if schedule.TotalPayableCents != row.TotalPayableCents ||
			schedule.TotalInterestCents != row.TotalInterestCents {
			s.log.WarnContext(ctx, "schedule totals changed at approval",
				"loan_id", row.ID, "stored", row.TotalPayableCents, "recomputed", schedule.TotalPayableCents)
		}
		record.Schedule = schedule.Installments
	}
	if err := s.repo.Approve(ctx, record); errors.Is(err, ErrStateChange) {
		return LoanView{}, httpx.Conflict("loan_state_changed", "This loan changed while you were deciding.")
	} else if err != nil {
		return LoanView{}, err
	}
	s.notifyLoanUpdate(ctx, scope.Group.ID, row.UserID, row.PublicID,
		"Loan "+decision, "The committee "+decision+" your loan request.", "decision:"+decision)
	return s.Detail(ctx, scope.Group.ID, publicID, user.ID, true)
}

// Disburse marks the manual payout and activates the loan.
func (s *Service) Disburse(ctx context.Context, scope groups.Scope, user users.User,
	publicID uuid.UUID, in DisburseInput) (LoanView, error) {
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return LoanView{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	row, err := s.repo.Loan(ctx, scope.Group.ID, publicID)
	if errors.Is(err, ErrNotFound) {
		return LoanView{}, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return LoanView{}, err
	}
	if row.Status != "approved" {
		return LoanView{}, httpx.Conflict("loan_not_approved", "Only an approved loan can be disbursed.")
	}
	reference := manualReference("DSB")
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	if err := s.repo.Disburse(ctx, scope.Group.ID, row.ID, row.UserID, user.ID,
		row.PrincipalCents, channel, reference); errors.Is(err, ErrStateChange) {
		return LoanView{}, httpx.Conflict("loan_state_changed", "This loan changed while you were disbursing.")
	} else if err != nil {
		return LoanView{}, err
	}
	s.notifyLoanUpdate(ctx, scope.Group.ID, row.UserID, row.PublicID,
		"Loan disbursed", "Your loan of "+centsString(row.PrincipalCents)+" has been disbursed.", "disbursed")
	return s.Detail(ctx, scope.Group.ID, publicID, user.ID, true)
}

// Repay records a manual repayment built from the borrower's own loan context.
func (s *Service) Repay(ctx context.Context, scope groups.Scope, user users.User,
	publicID uuid.UUID, in RepaymentInput) (RepaymentView, error) {
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return RepaymentView{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	amount, err := money.ParseAmount(in.Amount)
	if err != nil {
		return RepaymentView{}, httpx.Validation(map[string]string{"amount": "Enter a positive amount."})
	}
	row, err := s.repo.Loan(ctx, scope.Group.ID, publicID)
	if errors.Is(err, ErrNotFound) {
		return RepaymentView{}, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return RepaymentView{}, err
	}
	if row.Status != "active" && row.Status != "defaulted" {
		return RepaymentView{}, httpx.Conflict("loan_not_active", "Only an active loan can receive repayments.")
	}
	reference := manualReference("LRP")
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	outcome, err := s.repo.Repay(ctx, RepaymentRequest{
		GroupID: scope.Group.ID, LoanID: row.ID, UserID: row.UserID, ActorID: user.ID,
		AmountCents: int64(amount), Channel: channel, Reference: reference, CurrentStatus: row.Status,
	})
	if errors.Is(err, ErrOverpayment) {
		return RepaymentView{}, httpx.Unprocessable("repayment_exceeds_balance",
			"That is more than the outstanding loan balance.")
	}
	if errors.Is(err, ErrStateChange) {
		return RepaymentView{}, httpx.Conflict("loan_state_changed", "This loan changed while you were recording.")
	}
	if err != nil {
		return RepaymentView{}, err
	}
	status := row.Status
	if outcome.FullyPaid {
		status = "fully_paid"
	}
	s.notifyLoanUpdate(ctx, scope.Group.ID, row.UserID, row.PublicID,
		"Loan repayment recorded", centsString(int64(amount))+" was added to your loan.",
		"repayment:"+outcome.TransactionID.String())
	return RepaymentView{
		LoanID: publicID.String(), Amount: centsString(int64(amount)),
		PaidToDate:  centsString(row.PaidCents + int64(amount)),
		Outstanding: centsString(outcome.OutstandingCents), Status: status,
		TransactionID: outcome.TransactionID.String(), InstallmentsPA: outcome.Touched,
	}, nil
}

// Defaults scans one chama for installments overdue beyond 30 days.
func (s *Service) Defaults(ctx context.Context, groupID int64) (int64, error) {
	return s.repo.MarkDefaults(ctx, groupID, 30)
}

// DefaultsAll is the nightly entry point across every chama.
func (s *Service) DefaultsAll(ctx context.Context) (int64, error) {
	groupsList, err := s.repo.Groups(ctx)
	if err != nil {
		return 0, err
	}
	var total int64
	for _, g := range groupsList {
		n, err := s.repo.MarkDefaults(ctx, g.ID, 30)
		if err != nil {
			return total, err
		}
		total += n
	}
	return total, nil
}
