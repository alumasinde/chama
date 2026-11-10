package loans

import (
	"context"
	"errors"
	"log/slog"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

type Service struct {
	repo *Repository
	log  *slog.Logger
}

func NewService(repo *Repository, log *slog.Logger) *Service {
	return &Service{repo: repo, log: log}
}

func (s *Service) Apply(ctx context.Context, scope groups.Scope, user users.User, in ApplyInput) (LoanView, error) {
	r, err := s.rules(ctx, scope.Group.ID)
	if err != nil {
		return LoanView{}, err
	}
	if !r.allow {
		return LoanView{}, httpx.Unprocessable("loans_disabled", "This chama is not accepting loan applications.")
	}
	principal, err := money.ParseAmount(in.Amount)
	if err != nil || principal < 100 {
		return LoanView{}, httpx.Validation(map[string]string{"amount": "Enter at least KES 1.00."})
	}
	if in.TermMonths < 1 || in.TermMonths > r.maxTerm {
		return LoanView{}, httpx.Validation(map[string]string{
			"term_months": "Choose a term within this chama's maximum.",
		})
	}
	purpose := strings.TrimSpace(in.Purpose)
	if len(purpose) < 1 || len(purpose) > 200 {
		return LoanView{}, httpx.Validation(map[string]string{"purpose": "Describe the purpose in 1 to 200 characters."})
	}

	savings, err := s.repo.Savings(ctx, scope.Group.ID, user.ID)
	if err != nil {
		return LoanView{}, err
	}
	maxBorrow := ratCents(new(big.Rat).Mul(new(big.Rat).SetInt64(savings), r.multiple))
	if int64(principal) > maxBorrow {
		return LoanView{}, httpx.Unprocessable("loan_limit_exceeded",
			"You can borrow up to "+money.Cents(maxBorrow).String()+" based on your savings.")
	}
	if len(in.Guarantors) != int(r.guarantors) {
		return LoanView{}, httpx.Validation(map[string]string{
			"guarantors": "This chama requires exactly " + itoa(int(r.guarantors)) + " guarantor(s).",
		})
	}

	schedule, err := BuildSchedule(ScheduleRequest{
		PrincipalCents: int64(principal), MonthlyRatePercent: r.rate, Method: r.method,
		TermMonths: int(in.TermMonths), FirstDue: time.Now().UTC().AddDate(0, 1, 0),
	})
	if err != nil {
		return LoanView{}, httpx.Unprocessable("loan_terms_invalid", "Those loan terms cannot be scheduled.")
	}

	invites := make([]NewGuarantor, 0, len(in.Guarantors))
	seen := map[int64]bool{}
	for _, g := range in.Guarantors {
		publicID, err := uuid.Parse(strings.TrimSpace(g.UserID))
		if err != nil {
			return LoanView{}, httpx.Validation(map[string]string{"guarantors": "One guarantor id is not valid."})
		}
		member, err := s.repo.MemberByPublicID(ctx, scope.Group.ID, publicID)
		if err != nil {
			return LoanView{}, httpx.Validation(map[string]string{"guarantors": "A guarantor must be an active member."})
		}
		if member.ID == user.ID || seen[member.ID] {
			return LoanView{}, httpx.Validation(map[string]string{"guarantors": "Choose other members, once each."})
		}
		seen[member.ID] = true
		amount, err := money.ParseAmount(g.Amount)
		if err != nil {
			return LoanView{}, httpx.Validation(map[string]string{"guarantors": "Each guarantee must be a positive amount."})
		}
		savings, err := s.repo.Savings(ctx, scope.Group.ID, member.ID)
		if err != nil {
			return LoanView{}, err
		}
		exposure, err := s.repo.Exposure(ctx, scope.Group.ID, member.ID)
		if err != nil {
			return LoanView{}, err
		}
		if int64(amount) > savings-exposure {
			return LoanView{}, httpx.Unprocessable("guarantor_cover_exceeded",
				member.FirstName+" "+member.LastName+" can only guarantee "+money.Cents(savings-exposure).String()+".")
		}
		invites = append(invites, NewGuarantor{UserID: member.ID, AmountCents: int64(amount)})
	}

	status := "pending_guarantors"
	if r.guarantors == 0 {
		status = "pending_approval"
	}
	ref, err := s.repo.CreateLoan(ctx, NewLoan{
		GroupID: scope.Group.ID, UserID: user.ID, CreatedBy: user.ID,
		PrincipalCents: int64(principal), TotalInterestCents: schedule.TotalInterestCents,
		TotalPayableCents: schedule.TotalPayableCents, InterestRate: r.rate, InterestMethod: r.method,
		TermMonths: in.TermMonths, Purpose: purpose, Status: status, Guarantors: invites,
	})
	if err != nil {
		return LoanView{}, err
	}
	return s.Detail(ctx, scope.Group.ID, ref.PublicID, user.ID, true)
}

func (s *Service) List(ctx context.Context, groupID, requesterID int64, manager bool, status string, limit int32) ([]LoanView, error) {
	params := store.ListLoansParams{GroupID: groupID, RowLimit: limit}
	if !manager {
		params.UserID = &requesterID
	}
	if status != "" {
		if !validLoanStatus(status) {
			return nil, httpx.Validation(map[string]string{"status": "Unknown loan status."})
		}
		params.Status = &status
	}
	rows, err := s.repo.ListLoans(ctx, params)
	if err != nil {
		return nil, err
	}
	out := make([]LoanView, 0, len(rows))
	for _, row := range rows {
		out = append(out, listView(row))
	}
	return out, nil
}

func (s *Service) Detail(ctx context.Context, groupID int64, publicID uuid.UUID, requesterID int64, manager bool) (LoanView, error) {
	row, err := s.repo.Loan(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return LoanView{}, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return LoanView{}, err
	}
	if !manager && row.UserID != requesterID {
		return LoanView{}, httpx.NotFound("Loan not found.")
	}
	guarantors, err := s.repo.Guarantors(ctx, groupID, row.ID)
	if err != nil {
		return LoanView{}, err
	}
	approvals, err := s.repo.Approvals(ctx, groupID, row.ID)
	if err != nil {
		return LoanView{}, err
	}
	view := detailView(row)
	view.Guarantors = make([]GuarantorView, 0, len(guarantors))
	for _, g := range guarantors {
		view.Guarantors = append(view.Guarantors, GuarantorView{
			UserID: g.UserPublicID.String(), DisplayName: g.FirstName + " " + g.LastName,
			Amount: centsString(g.AmountCents), Status: g.Status, RespondedAt: g.RespondedAt,
		})
	}
	view.Approvals = make([]ApprovalView, 0, len(approvals))
	for _, a := range approvals {
		view.Approvals = append(view.Approvals, ApprovalView{
			ApproverID: a.ApproverPublicID.String(), DisplayName: a.FirstName + " " + a.LastName,
			Decision: a.Decision, Comment: a.Comment, CreatedAt: a.CreatedAt,
		})
	}
	return view, nil
}

func (s *Service) Schedule(ctx context.Context, groupID int64, publicID uuid.UUID, requesterID int64, manager bool) ([]InstallmentView, error) {
	row, err := s.repo.Loan(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return nil, httpx.NotFound("Loan not found.")
	}
	if err != nil {
		return nil, err
	}
	if !manager && row.UserID != requesterID {
		return nil, httpx.NotFound("Loan not found.")
	}
	rows, err := s.repo.Schedule(ctx, groupID, row.ID)
	if err != nil {
		return nil, err
	}
	out := make([]InstallmentView, 0, len(rows))
	for _, inst := range rows {
		var paidAt *string
		if inst.PaidAt != nil {
			formatted := inst.PaidAt.Format(time.RFC3339)
			paidAt = &formatted
		}
		out = append(out, InstallmentView{
			Number: inst.InstallmentNo, DueDate: inst.DueDate,
			Principal: centsString(inst.PrincipalCents), Interest: centsString(inst.InterestCents),
			Paid: centsString(inst.PaidCents), Total: centsString(inst.PrincipalCents + inst.InterestCents),
			PaidAt: paidAt,
		})
	}
	return out, nil
}

func detailView(row store.GetLoanByPublicIDRow) LoanView {
	return LoanView{
		ID: row.PublicID.String(), BorrowerID: row.UserPublicID.String(),
		Borrower: row.FirstName + " " + row.LastName, Principal: centsString(row.PrincipalCents),
		InterestRate: row.InterestRate, InterestMethod: row.InterestMethod, TermMonths: row.TermMonths,
		Status: row.Status, TotalInterest: centsString(row.TotalInterestCents),
		TotalPayable: centsString(row.TotalPayableCents), PaidToDate: centsString(row.PaidCents),
		Outstanding: centsString(row.TotalPayableCents - row.PaidCents), Purpose: row.Purpose,
		RequestedAt: row.RequestedAt, ApprovedAt: row.ApprovedAt, DisbursedAt: row.DisbursedAt,
		Guarantors: []GuarantorView{}, Approvals: []ApprovalView{},
	}
}

func listView(row store.ListLoansRow) LoanView {
	return LoanView{
		ID: row.PublicID.String(), BorrowerID: row.UserPublicID.String(),
		Borrower: row.FirstName + " " + row.LastName, Principal: centsString(row.PrincipalCents),
		InterestRate: row.InterestRate, InterestMethod: row.InterestMethod, TermMonths: row.TermMonths,
		Status: row.Status, TotalInterest: centsString(row.TotalInterestCents),
		TotalPayable: centsString(row.TotalPayableCents), PaidToDate: centsString(row.PaidCents),
		Outstanding: centsString(row.TotalPayableCents - row.PaidCents), Purpose: row.Purpose,
		RequestedAt: row.RequestedAt, ApprovedAt: row.ApprovedAt, DisbursedAt: row.DisbursedAt,
		Guarantors: []GuarantorView{}, Approvals: []ApprovalView{},
	}
}

func validLoanStatus(status string) bool {
	switch status {
	case "pending_guarantors", "pending_approval", "approved", "rejected",
		"active", "fully_paid", "defaulted", "written_off":
		return true
	default:
		return false
	}
}
