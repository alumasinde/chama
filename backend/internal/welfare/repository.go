package welfare

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var (
	ErrNotFound       = errors.New("welfare fund not found")
	ErrDuplicate      = errors.New("welfare contribution already recorded")
	ErrNotPending     = errors.New("welfare claim is not pending")
	ErrNotApproved    = errors.New("welfare claim is not approved")
	ErrFundsShortfall = errors.New("welfare fund balance is too low")
)

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) Fund(ctx context.Context, groupID int64) (store.GetWelfareFundRow, error) {
	row, err := r.q.GetWelfareFund(ctx, groupID)
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetWelfareFundRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) SaveFund(ctx context.Context, p store.UpsertWelfareFundParams) error {
	_, err := r.q.UpsertWelfareFund(ctx, p)
	return err
}

func (r *Repository) Contributions(ctx context.Context, p store.ListWelfareContributionsParams) ([]store.ListWelfareContributionsRow, error) {
	return r.q.ListWelfareContributions(ctx, p)
}

func (r *Repository) Member(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetActiveMemberByPublicIDRow, error) {
	row, err := r.q.GetActiveMemberByPublicID(ctx, store.GetActiveMemberByPublicIDParams{
		PublicID: publicID, GroupID: groupID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetActiveMemberByPublicIDRow{}, ErrNotFound
	}
	return row, err
}

type Contribution struct {
	GroupID     int64
	FundID      int64
	UserID      int64
	AmountCents int64
	Period      string
	Channel     string
	Reference   string
}

// ManualContribution writes the completed ledger row and the contribution together.
func (r *Repository) ManualContribution(ctx context.Context, p Contribution) (uuid.UUID, error) {
	var publicID uuid.UUID
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
			GroupID: p.GroupID, UserID: p.UserID, TransactionType: "welfare_contribution",
			Channel: p.Channel, AmountCents: p.AmountCents,
			Narration: "Welfare contribution " + p.Period,
		})
		if err != nil {
			return err
		}
		settled, err := q.SettleTransaction(ctx, store.SettleTransactionParams{
			Status: "completed", ReferenceCode: &p.Reference, ID: tx.ID,
		})
		if err != nil {
			return err
		}
		row, err := q.InsertWelfareContribution(ctx, store.InsertWelfareContributionParams{
			GroupID: p.GroupID, FundID: p.FundID, UserID: p.UserID,
			AmountCents: p.AmountCents, PeriodLabel: p.Period, TransactionID: &settled.ID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrDuplicate
		}
		if err != nil {
			return err
		}
		publicID = row.PublicID
		return nil
	})
	return publicID, err
}

// RecordContribution links an already-settled welfare payment; duplicates are ignored.
func (r *Repository) RecordContribution(ctx context.Context, p Contribution, transactionID int64) error {
	_, err := r.q.InsertWelfareContribution(ctx, store.InsertWelfareContributionParams{
		GroupID: p.GroupID, FundID: p.FundID, UserID: p.UserID,
		AmountCents: p.AmountCents, PeriodLabel: p.Period, TransactionID: &transactionID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	return err
}

func (r *Repository) CreateClaim(ctx context.Context, p store.InsertWelfareClaimParams) (store.InsertWelfareClaimRow, error) {
	return r.q.InsertWelfareClaim(ctx, p)
}

func (r *Repository) Claim(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetWelfareClaimRow, error) {
	row, err := r.q.GetWelfareClaim(ctx, store.GetWelfareClaimParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetWelfareClaimRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) Claims(ctx context.Context, p store.ListWelfareClaimsParams) ([]store.ListWelfareClaimsRow, error) {
	return r.q.ListWelfareClaims(ctx, p)
}

func (r *Repository) Decide(ctx context.Context, p store.DecideWelfareClaimParams) error {
	rows, err := r.q.DecideWelfareClaim(ctx, p)
	if err != nil {
		return err
	}
	if rows == 0 {
		return ErrNotPending
	}
	return nil
}

type Payout struct {
	GroupID   int64
	PublicID  uuid.UUID
	ActorID   int64
	Channel   string
	Reference string
}

// Payout locks the claim and fund, checks the balance, then writes one completed payout row.
func (r *Repository) Payout(ctx context.Context, p Payout) (uuid.UUID, error) {
	var txPublicID uuid.UUID
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		claim, err := q.LockWelfareClaim(ctx, store.LockWelfareClaimParams{
			GroupID: p.GroupID, PublicID: p.PublicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if claim.Status != "approved" {
			return ErrNotApproved
		}
		fund, err := q.LockWelfareFundBalance(ctx, p.GroupID)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if fund.BalanceCents < claim.AmountCents {
			return ErrFundsShortfall
		}
		tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
			GroupID: p.GroupID, UserID: claim.UserID, TransactionType: "welfare_payout",
			Channel: p.Channel, AmountCents: claim.AmountCents,
			Narration: "Welfare claim payout",
		})
		if err != nil {
			return err
		}
		settled, err := q.SettleTransaction(ctx, store.SettleTransactionParams{
			Status: "completed", ReferenceCode: &p.Reference, ID: tx.ID,
		})
		if err != nil {
			return err
		}
		rows, err := q.MarkWelfareClaimPaid(ctx, store.MarkWelfareClaimPaidParams{
			PayoutTransactionID: &settled.ID, DecidedBy: &p.ActorID,
			GroupID: p.GroupID, PublicID: p.PublicID,
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrNotApproved
		}
		txPublicID = settled.PublicID
		return nil
	})
	return txPublicID, err
}

func manualReference() string {
	return fmt.Sprintf("WLF-%s-%s", time.Now().UTC().Format("060102150405"), uuid.NewString()[:8])
}
