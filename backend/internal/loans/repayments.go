package loans

import (
	"context"
	"errors"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var ErrOverpayment = errors.New("repayment exceeds outstanding balance")

type RepaymentRequest struct {
	GroupID       int64
	LoanID        int64
	UserID        int64
	ActorID       int64
	AmountCents   int64
	Channel       string
	Reference     string
	CurrentStatus string
}

type RepaymentOutcome struct {
	FullyPaid        bool
	OutstandingCents int64
	Touched          int
	TransactionID    uuid.UUID
}

// Repay allocates oldest-first across unpaid installments inside one transaction.
func (r *Repository) Repay(ctx context.Context, in RepaymentRequest) (RepaymentOutcome, error) {
	var out RepaymentOutcome
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		rows, err := q.ListScheduleForUpdate(ctx, store.ListScheduleForUpdateParams{
			GroupID: in.GroupID, LoanID: in.LoanID,
		})
		if err != nil {
			return err
		}
		remaining := in.AmountCents
		var dueTotal, paidTotal int64
		for _, inst := range rows {
			due := inst.PrincipalCents + inst.InterestCents
			dueTotal += due
			paidTotal += inst.PaidCents
			if remaining == 0 || inst.PaidCents >= due {
				continue
			}
			need := due - inst.PaidCents
			alloc := need
			if alloc > remaining {
				alloc = remaining
			}
			if alloc == 0 {
				continue
			}
			newPaid := inst.PaidCents + alloc
			if err := q.SetInstallmentPaid(ctx, store.SetInstallmentPaidParams{
				PaidCents: newPaid, FullyPaid: newPaid == due,
				InstallmentID: inst.ID, GroupID: in.GroupID,
			}); err != nil {
				return err
			}
			remaining -= alloc
			paidTotal += alloc
			out.Touched++
		}
		if remaining > 0 {
			return ErrOverpayment
		}
		tx, err := createCompleted(ctx, q, in.GroupID, in.UserID, in.ActorID, in.AmountCents,
			"loan_repayment", in.Channel, in.Reference, "Manual loan repayment")
		if err != nil {
			return err
		}
		out.TransactionID = tx.PublicID
		out.FullyPaid = paidTotal >= dueTotal && dueTotal > 0
		out.OutstandingCents = dueTotal - paidTotal
		if out.FullyPaid {
			status := "fully_paid"
			rowsAffected, err := q.UpdateLoanStatus(ctx, store.UpdateLoanStatusParams{
				Status: status, LoanID: in.LoanID, GroupID: in.GroupID, ExpectedStatus: in.CurrentStatus,
			})
			if err != nil {
				return err
			}
			if rowsAffected == 0 {
				return ErrStateChange
			}
		}
		return nil
	})
	return out, err
}

// Disburse creates the payout ledger row and activates the loan atomically.
func (r *Repository) Disburse(ctx context.Context, groupID, loanID, userID, actorID, amountCents int64,
	channel, reference string) error {
	return db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		tx, err := createCompleted(ctx, q, groupID, userID, actorID, amountCents,
			"loan_disbursement", channel, reference, "Manual loan disbursement")
		if err != nil {
			return err
		}
		rows, err := q.UpdateLoanStatus(ctx, store.UpdateLoanStatusParams{
			Status: "active", DisbursementTransactionID: &tx.ID,
			LoanID: loanID, GroupID: groupID, ExpectedStatus: "approved",
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrStateChange
		}
		return nil
	})
}

func (r *Repository) MarkDefaults(ctx context.Context, groupID int64, days int32) (int64, error) {
	return r.q.MarkDefaultedLoans(ctx, store.MarkDefaultedLoansParams{GroupID: groupID, OverdueDays: days})
}
