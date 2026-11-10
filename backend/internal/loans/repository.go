package loans

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var (
	ErrNotFound    = errors.New("loan not found")
	ErrStateChange = errors.New("loan state changed")
	ErrDuplicate   = errors.New("guarantor already invited")
)

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) Settings(ctx context.Context, groupID int64) (store.GetLoanSettingsRow, error) {
	row, err := r.q.GetLoanSettings(ctx, groupID)
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetLoanSettingsRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) UpsertSettings(ctx context.Context, p store.UpsertLoanSettingsParams) error {
	return r.q.UpsertLoanSettings(ctx, p)
}

func (r *Repository) Loan(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetLoanByPublicIDRow, error) {
	row, err := r.q.GetLoanByPublicID(ctx, store.GetLoanByPublicIDParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetLoanByPublicIDRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) ListLoans(ctx context.Context, p store.ListLoansParams) ([]store.ListLoansRow, error) {
	return r.q.ListLoans(ctx, p)
}

func (r *Repository) Schedule(ctx context.Context, groupID, loanID int64) ([]store.ListScheduleRow, error) {
	return r.q.ListSchedule(ctx, store.ListScheduleParams{GroupID: groupID, LoanID: loanID})
}

func (r *Repository) Guarantors(ctx context.Context, groupID, loanID int64) ([]store.ListLoanGuarantorsRow, error) {
	return r.q.ListLoanGuarantors(ctx, store.ListLoanGuarantorsParams{GroupID: groupID, LoanID: loanID})
}

func (r *Repository) Approvals(ctx context.Context, groupID, loanID int64) ([]store.ListLoanApprovalsRow, error) {
	return r.q.ListLoanApprovals(ctx, store.ListLoanApprovalsParams{GroupID: groupID, LoanID: loanID})
}

func (r *Repository) MemberByPublicID(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetActiveMemberByPublicIDRow, error) {
	row, err := r.q.GetActiveMemberByPublicID(ctx, store.GetActiveMemberByPublicIDParams{PublicID: publicID, GroupID: groupID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetActiveMemberByPublicIDRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) Savings(ctx context.Context, groupID, userID int64) (int64, error) {
	return r.q.MemberSavings(ctx, store.MemberSavingsParams{GroupID: groupID, UserID: userID})
}

func (r *Repository) Exposure(ctx context.Context, groupID, userID int64) (int64, error) {
	return r.q.GuaranteeExposure(ctx, store.GuaranteeExposureParams{GroupID: groupID, GuarantorUserID: userID})
}

func (r *Repository) GuarantorCounts(ctx context.Context, loanID int64) (store.CountLoanGuarantorsRow, error) {
	return r.q.CountLoanGuarantors(ctx, loanID)
}

func (r *Repository) Groups(ctx context.Context) ([]store.ListGroupIDsRow, error) {
	return r.q.ListGroupIDs(ctx)
}

type NewGuarantor struct {
	UserID      int64
	AmountCents int64
}

type NewLoan struct {
	GroupID            int64
	UserID             int64
	CreatedBy          int64
	PrincipalCents     int64
	TotalInterestCents int64
	TotalPayableCents  int64
	InterestRate       string
	InterestMethod     string
	TermMonths         int16
	Purpose            string
	Status             string
	Guarantors         []NewGuarantor
}

type LoanRef struct {
	ID       int64
	PublicID uuid.UUID
}

// CreateLoan writes the application and its guarantor invitations atomically.
func (r *Repository) CreateLoan(ctx context.Context, in NewLoan) (LoanRef, error) {
	var out LoanRef
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		row, err := q.CreateLoan(ctx, store.CreateLoanParams{
			GroupID: in.GroupID, UserID: in.UserID, PrincipalCents: in.PrincipalCents,
			InterestRate: in.InterestRate, InterestMethod: in.InterestMethod,
			TermMonths: in.TermMonths, Status: in.Status,
			TotalInterestCents: in.TotalInterestCents, TotalPayableCents: in.TotalPayableCents,
			Purpose: in.Purpose, CreatedBy: in.CreatedBy,
		})
		if err != nil {
			return err
		}
		for _, g := range in.Guarantors {
			if _, err := q.AddLoanGuarantor(ctx, store.AddLoanGuarantorParams{
				GroupID: in.GroupID, LoanID: row.ID, GuarantorUserID: g.UserID, AmountCents: g.AmountCents,
			}); err != nil {
				return mapGuarantorError(err)
			}
		}
		out = LoanRef{ID: row.ID, PublicID: row.PublicID}
		return nil
	})
	return out, err
}

// Respond records a guarantor decision and returns the fresh tally.
func (r *Repository) Respond(ctx context.Context, groupID, loanID, userID int64, decision string) (store.CountLoanGuarantorsRow, error) {
	var counts store.CountLoanGuarantorsRow
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		rows, err := q.RespondToGuarantor(ctx, store.RespondToGuarantorParams{
			Decision: decision, LoanID: loanID, GroupID: groupID, GuarantorUserID: userID,
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrStateChange
		}
		counts, err = q.CountLoanGuarantors(ctx, loanID)
		return err
	})
	return counts, err
}

func (r *Repository) SetStatus(ctx context.Context, groupID, loanID int64, status, expected string) error {
	rows, err := r.q.UpdateLoanStatus(ctx, store.UpdateLoanStatusParams{
		Status: status, LoanID: loanID, GroupID: groupID, ExpectedStatus: expected,
	})
	if err != nil {
		return err
	}
	if rows == 0 {
		return ErrStateChange
	}
	return nil
}

type ApprovalRecord struct {
	GroupID    int64
	LoanID     int64
	ApproverID int64
	Decision   string
	Comment    *string
	Schedule   []Installment
	NextStatus string
}

// Approve persists the decision and, when approved, the immutable schedule.
func (r *Repository) Approve(ctx context.Context, a ApprovalRecord) error {
	return db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		if err := q.UpsertLoanApproval(ctx, store.UpsertLoanApprovalParams{
			GroupID: a.GroupID, LoanID: a.LoanID, ApproverID: a.ApproverID,
			Decision: a.Decision, Comment: a.Comment,
		}); err != nil {
			return err
		}
		if a.NextStatus == "approved" {
			for _, inst := range a.Schedule {
				if err := q.AddScheduleItem(ctx, store.AddScheduleItemParams{
					GroupID: a.GroupID, LoanID: a.LoanID, InstallmentNo: inst.Number,
					DueDate:        inst.DueDate.Format("2006-01-02"),
					PrincipalCents: inst.PrincipalCents, InterestCents: inst.InterestCents,
				}); err != nil {
					return err
				}
			}
		}
		rows, err := q.UpdateLoanStatus(ctx, store.UpdateLoanStatusParams{
			Status: a.NextStatus, LoanID: a.LoanID, GroupID: a.GroupID, ExpectedStatus: "pending_approval",
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

type completedTx struct {
	ID       int64
	PublicID uuid.UUID
}

func createCompleted(ctx context.Context, q *store.Queries, groupID, userID, actorID, amountCents int64,
	purpose, channel, reference, narration string) (completedTx, error) {
	tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
		GroupID: groupID, UserID: userID, TransactionType: purpose, Channel: channel,
		AmountCents: amountCents, Narration: narration,
	})
	if err != nil {
		return completedTx{}, err
	}
	settled, err := q.SettleTransaction(ctx, store.SettleTransactionParams{
		Status: "completed", ReferenceCode: &reference, ID: tx.ID,
	})
	if err != nil {
		return completedTx{}, err
	}
	return completedTx{ID: settled.ID, PublicID: settled.PublicID}, nil
}

func manualReference(prefix string) string {
	return fmt.Sprintf("%s-%s", prefix, time.Now().UTC().Format("060102150405"))
}

func mapGuarantorError(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrDuplicate
	}
	return err
}
