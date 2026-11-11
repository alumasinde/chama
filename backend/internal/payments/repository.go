package payments

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var ErrNotFound = errors.New("payment not found")

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) PaymentSettings(ctx context.Context, groupID int64) (store.GetPaymentSettingsRow, error) {
	row, err := r.q.GetPaymentSettings(ctx, groupID)
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetPaymentSettingsRow{}, ErrNotFound
	}
	return row, err
}

// ErrMemberNotActive means the chosen member is missing, exited or suspended.
var ErrMemberNotActive = errors.New("member is not active")

// ErrReferenceRecorded means the M-Pesa code already exists in this chama's ledger.
var ErrReferenceRecorded = errors.New("reference already recorded")

type ManualParams struct {
	GroupID        int64
	MemberPublicID uuid.UUID
	AmountCents    int64
	ReferenceCode  string
	Narration      string
	RecordedBy     int64
}

// ManualContribution is the ledger row a treasurer's manual entry produced.
type ManualContribution struct {
	ID            int64
	TransactionID uuid.UUID
	UserID        int64
	CreatedAt     time.Time
}

// RecordManualContribution settles a contribution the chama already received.
func (r *Repository) RecordManualContribution(ctx context.Context, p ManualParams) (ManualContribution, error) {
	row, err := r.q.RecordManualContribution(ctx, store.RecordManualContributionParams{
		GroupID:        p.GroupID,
		Channel:        "mpesa_manual",
		AmountCents:    p.AmountCents,
		ReferenceCode:  p.ReferenceCode,
		Narration:      p.Narration,
		RecordedBy:     &p.RecordedBy,
		MemberPublicID: p.MemberPublicID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return ManualContribution{}, ErrMemberNotActive
	}
	if isDuplicateReference(err) {
		return ManualContribution{}, ErrReferenceRecorded
	}
	if err != nil {
		return ManualContribution{}, err
	}
	return ManualContribution{
		ID:            row.ID,
		TransactionID: row.PublicID,
		UserID:        row.UserID,
		CreatedAt:     row.CreatedAt,
	}, nil
}

type PendingRequest struct {
	TransactionID int64
	PublicID      uuid.UUID
	CheckoutID    string
	MerchantID    string
	PhoneNumber   string
	AmountCents   int64
}

// CreatePending writes the pending ledger row and its STK request together.
func (r *Repository) CreatePending(ctx context.Context, p CreatePendingParams) (PendingRequest, error) {
	var out PendingRequest
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
			GroupID:         p.GroupID,
			UserID:          p.UserID,
			TransactionType: p.Purpose,
			Channel:         "mpesa_stk",
			AmountCents:     p.AmountCents,
			IdempotencyKey:  nullable(p.IdempotencyKey),
			Narration:       p.Narration,
		})
		if err != nil {
			return err
		}
		request, err := q.CreatePaymentRequest(ctx, store.CreatePaymentRequestParams{
			GroupID:           p.GroupID,
			UserID:            p.UserID,
			PhoneNumber:       p.PhoneNumber,
			AmountCents:       p.AmountCents,
			Purpose:           p.Purpose,
			CheckoutRequestID: p.CheckoutID,
			MerchantRequestID: nullable(p.MerchantID),
			TransactionID:     &tx.ID,
			IdempotencyKey:    nullable(p.IdempotencyKey),
		})
		if err != nil {
			return err
		}
		out = PendingRequest{
			TransactionID: tx.ID,
			PublicID:      request.PublicID,
			CheckoutID:    request.CheckoutRequestID,
			MerchantID:    p.MerchantID,
			PhoneNumber:   p.PhoneNumber,
			AmountCents:   p.AmountCents,
		}
		return nil
	})
	return out, err
}

type CreatePendingParams struct {
	GroupID        int64
	UserID         int64
	Purpose        string
	AmountCents    int64
	PhoneNumber    string
	Narration      string
	CheckoutID     string
	MerchantID     string
	IdempotencyKey string
}

type SettleInput struct {
	GroupID     int64
	CheckoutID  string
	Status      string
	ResultCode  string
	ResultDesc  string
	Receipt     string
	RawCallback []byte
}

// SettledEvent describes the one transition a callback made, for downstream hooks.
type SettledEvent struct {
	GroupID             int64
	GroupPublicID       uuid.UUID
	UserID              int64
	AmountCents         int64
	Purpose             string
	Status              string
	Receipt             string
	TransactionID       int64
	TransactionPublicID uuid.UUID
}

// Settle is idempotent: a second callback for the same checkout changes nothing.
func (r *Repository) Settle(ctx context.Context, in SettleInput) (*SettledEvent, error) {
	var event *SettledEvent
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		request, err := q.GetPaymentRequestByCheckout(ctx, store.GetPaymentRequestByCheckoutParams{
			GroupID: in.GroupID, CheckoutRequestID: in.CheckoutID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if request.TransactionID == nil {
			return nil
		}
		settled, err := q.SettleTransaction(ctx, store.SettleTransactionParams{
			Status:        in.Status,
			ReferenceCode: nullable(in.Receipt),
			RawCallback:   in.RawCallback,
			ID:            *request.TransactionID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := q.SettlePaymentRequest(ctx, store.SettlePaymentRequestParams{
			Status:        in.Status,
			ResultCode:    nullable(in.ResultCode),
			ResultDesc:    nullable(in.ResultDesc),
			TransactionID: &settled.ID,
			ID:            request.ID,
		}); err != nil {
			return err
		}
		event = &SettledEvent{
			GroupID: in.GroupID, UserID: settled.UserID, AmountCents: settled.AmountCents,
			Purpose: settled.TransactionType, Status: settled.Status, Receipt: in.Receipt,
			TransactionID: settled.ID, TransactionPublicID: settled.PublicID,
		}
		return nil
	})
	if isDuplicateReference(err) {
		return nil, nil
	}
	return event, err
}

func (r *Repository) ListTransactions(ctx context.Context, p store.ListTransactionsParams) ([]store.ListTransactionsRow, error) {
	return r.q.ListTransactions(ctx, p)
}

func (r *Repository) GetTransaction(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetTransactionRow, error) {
	row, err := r.q.GetTransaction(ctx, store.GetTransactionParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetTransactionRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) BeginIdempotency(ctx context.Context, p store.BeginIdempotencyParams) (int64, error) {
	return r.q.BeginIdempotency(ctx, p)
}

func (r *Repository) Idempotency(ctx context.Context, userID int64, key string) (store.GetIdempotencyRow, error) {
	row, err := r.q.GetIdempotency(ctx, store.GetIdempotencyParams{UserID: userID, Key: key})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetIdempotencyRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) CompleteIdempotency(ctx context.Context, p store.CompleteIdempotencyParams) error {
	return r.q.CompleteIdempotency(ctx, p)
}

func (r *Repository) DeleteIdempotency(ctx context.Context, userID int64, key string) error {
	return r.q.DeleteIdempotency(ctx, store.DeleteIdempotencyParams{UserID: userID, Key: key})
}

func isDuplicateReference(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "transactions_group_reference_key"
}

func nullable(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

var _ = time.Time{}
