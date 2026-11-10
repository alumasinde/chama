package fines

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var (
	ErrNotFound      = errors.New("fine not found")
	ErrNotPayable    = errors.New("fine is not unpaid")
	ErrDuplicateRule = errors.New("an active rule already exists")
)

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) Rules(ctx context.Context, groupID int64) ([]store.ListFineRulesRow, error) {
	return r.q.ListFineRules(ctx, groupID)
}

func (r *Repository) RuleByType(ctx context.Context, groupID int64, fineType string) (store.GetFineRuleByTypeRow, error) {
	row, err := r.q.GetFineRuleByType(ctx, store.GetFineRuleByTypeParams{GroupID: groupID, FineType: fineType})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetFineRuleByTypeRow{}, ErrNotFound
	}
	return row, err
}

// PutRule updates the active rule for a type or creates the first one.
func (r *Repository) PutRule(ctx context.Context, groupID int64, fineType string,
	method, amount string, grace int16) error {
	existing, err := r.RuleByType(ctx, groupID, fineType)
	switch {
	case errors.Is(err, ErrNotFound):
		_, err = r.q.InsertFineRule(ctx, store.InsertFineRuleParams{
			GroupID: groupID, FineType: fineType, CalculationMethod: method,
			AmountOrRate: amount, GraceDays: grace,
		})
		return err
	case err != nil:
		return err
	default:
		return r.q.UpdateFineRule(ctx, store.UpdateFineRuleParams{
			CalculationMethod: method, AmountOrRate: amount, GraceDays: grace,
			FineRuleID: existing.ID, GroupID: groupID,
		})
	}
}

func (r *Repository) Create(ctx context.Context, p store.CreateFineParams) (store.CreateFineRow, error) {
	return r.q.CreateFine(ctx, p)
}

func (r *Repository) Fine(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetFineByPublicIDRow, error) {
	row, err := r.q.GetFineByPublicID(ctx, store.GetFineByPublicIDParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetFineByPublicIDRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) List(ctx context.Context, p store.ListFinesParams) ([]store.ListFinesRow, error) {
	return r.q.ListFines(ctx, p)
}

func (r *Repository) MemberByPublicID(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetActiveMemberByPublicIDRow, error) {
	row, err := r.q.GetActiveMemberByPublicID(ctx, store.GetActiveMemberByPublicIDParams{PublicID: publicID, GroupID: groupID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetActiveMemberByPublicIDRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) Waive(ctx context.Context, p store.WaiveFineParams) error {
	rows, err := r.q.WaiveFine(ctx, p)
	if err != nil {
		return err
	}
	if rows == 0 {
		return ErrNotPayable
	}
	return nil
}

type Payment struct {
	GroupID     int64
	PublicID    uuid.UUID
	UserID      int64
	ActorID     int64
	AmountCents int64
	Channel     string
	Reference   string
	Reason      string
}

// Pay writes the completed ledger row and closes the fine in one transaction.
func (r *Repository) Pay(ctx context.Context, p Payment) (uuid.UUID, error) {
	var txPublicID uuid.UUID
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		fine, err := q.GetFineByPublicID(ctx, store.GetFineByPublicIDParams{GroupID: p.GroupID, PublicID: p.PublicID})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if fine.Status != "unpaid" {
			return ErrNotPayable
		}
		tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
			GroupID: p.GroupID, UserID: p.UserID, TransactionType: "fine", Channel: p.Channel,
			AmountCents: p.AmountCents, Narration: "Fine payment: " + p.Reason,
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
		rows, err := q.MarkFinePaid(ctx, store.MarkFinePaidParams{
			PaymentTransactionID: &settled.ID, GroupID: p.GroupID, PublicID: p.PublicID,
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrNotPayable
		}
		txPublicID = settled.PublicID
		return nil
	})
	return txPublicID, err
}

func (r *Repository) Group(ctx context.Context, groupID int64) (store.GetFineGroupRow, error) {
	row, err := r.q.GetFineGroup(ctx, groupID)
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetFineGroupRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) Groups(ctx context.Context) ([]store.ListFineGroupsRow, error) {
	return r.q.ListFineGroups(ctx)
}

func (r *Repository) Evaluate(ctx context.Context, groupID int64, p Period) ([]store.CreateEvaluatedFinesRow, error) {
	label := p.Label
	return r.q.CreateEvaluatedFines(ctx, store.CreateEvaluatedFinesParams{
		PeriodLabel: &label, GroupID: groupID, PeriodEnd: p.End, PeriodStart: p.Start,
	})
}
