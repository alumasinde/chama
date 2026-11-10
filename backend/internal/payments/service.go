package payments

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/platform/phone"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

type Service struct {
	repo      *Repository
	groups    *groups.Service
	provider  Provider
	baseURL   string
	log       *slog.Logger
	onSettled func(context.Context, SettledEvent)
}

func NewService(repo *Repository, groupsSvc *groups.Service, provider Provider, baseURL string, log *slog.Logger) *Service {
	return &Service{repo: repo, groups: groupsSvc, provider: provider, baseURL: strings.TrimRight(baseURL, "/"), log: log}
}

// OnSettled installs the post-callback hook used for welfare records and notifications.
func (s *Service) OnSettled(fn func(context.Context, SettledEvent)) { s.onSettled = fn }

type STKInput struct {
	Amount      string  `json:"amount"`
	Purpose     string  `json:"purpose"`
	PhoneNumber *string `json:"phone_number"`
}

type STKResult struct {
	PaymentRequestID  string `json:"payment_request_id"`
	CheckoutRequestID string `json:"checkout_request_id"`
	Status            string `json:"status"`
	Amount            string `json:"amount"`
	Purpose           string `json:"purpose"`
}

var purposeTypes = map[string]bool{
	"contribution": true, "fine": true, "loan_repayment": true, "welfare_contribution": true,
}

// InitiateSTK prompts the member's phone and records a pending ledger row.
func (s *Service) InitiateSTK(ctx context.Context, user users.User, group groups.Group, in STKInput, idempotencyKey string) (STKResult, error) {
	if len(idempotencyKey) < 8 || len(idempotencyKey) > 128 {
		return STKResult{}, httpx.Validation(map[string]string{
			"idempotency_key": "Send an Idempotency-Key header of 8 to 128 characters.",
		})
	}
	cents, err := money.ParseAmount(in.Amount)
	if err != nil || cents < 100 {
		return STKResult{}, httpx.Validation(map[string]string{"amount": "Enter an amount of at least KES 1.00."})
	}
	if int64(cents)%100 != 0 {
		return STKResult{}, httpx.Unprocessable("amount_not_whole_shillings", "M-Pesa accepts whole shillings only.")
	}
	purpose := strings.TrimSpace(in.Purpose)
	if !purposeTypes[purpose] {
		return STKResult{}, httpx.Validation(map[string]string{
			"purpose": "Choose contribution, fine, loan_repayment or welfare_contribution.",
		})
	}
	if s.provider == nil {
		return STKResult{}, httpx.NewError(503, "provider_unavailable", "Payments are not configured.")
	}

	hash := requestHash(in)
	inserted, err := s.repo.BeginIdempotency(ctx, store.BeginIdempotencyParams{
		UserID: user.ID, Key: idempotencyKey, Route: "payments/stk", RequestHash: hash,
	})
	if err != nil {
		return STKResult{}, err
	}
	if inserted == 0 {
		return s.replay(ctx, user.ID, idempotencyKey, hash)
	}

	result, err := s.initiate(ctx, user, group, in, purpose, cents, idempotencyKey)
	if err != nil {
		_ = s.repo.DeleteIdempotency(ctx, user.ID, idempotencyKey)
		return STKResult{}, err
	}
	body, _ := json.Marshal(result)
	status := int32(202)
	if err := s.repo.CompleteIdempotency(ctx, store.CompleteIdempotencyParams{
		StatusCode: &status, ResponseBody: body, UserID: user.ID, Key: idempotencyKey,
	}); err != nil {
		s.log.ErrorContext(ctx, "store idempotent response", "error", err)
	}
	return result, nil
}

func (s *Service) replay(ctx context.Context, userID int64, key string, hash []byte) (STKResult, error) {
	row, err := s.repo.Idempotency(ctx, userID, key)
	if err != nil {
		return STKResult{}, err
	}
	if string(row.RequestHash) != string(hash) {
		return STKResult{}, httpx.Conflict("idempotency_conflict", "That key was already used for a different request.")
	}
	if row.State != "completed" || len(row.ResponseBody) == 0 {
		return STKResult{}, httpx.Conflict("request_in_progress", "That request is still being processed.")
	}
	var result STKResult
	if err := json.Unmarshal(row.ResponseBody, &result); err != nil {
		return STKResult{}, err
	}
	return result, nil
}

func (s *Service) initiate(ctx context.Context, user users.User, group groups.Group, in STKInput, purpose string, cents money.Cents, idempotencyKey string) (STKResult, error) {
	credentials, err := s.groups.Credentials(ctx, group.ID)
	if errors.Is(err, groups.ErrNotFound) {
		return STKResult{}, httpx.Unprocessable("payment_settings_missing", "Add your chama's M-Pesa settings first.")
	}
	if err != nil {
		return STKResult{}, err
	}
	rawPhone := user.PhoneNumber
	if in.PhoneNumber != nil && strings.TrimSpace(*in.PhoneNumber) != "" {
		rawPhone = *in.PhoneNumber
	}
	phoneNumber, err := phone.Normalize(rawPhone)
	if err != nil {
		return STKResult{}, httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	reference := accountReference(credentials.AccountReferenceTemplate, user, time.Now())
	callbackURL := fmt.Sprintf("%s/api/v1/payments/mpesa/callback/%s/%s", s.baseURL, group.PublicID, credentials.CallbackSecret)

	providerResp, err := s.provider.RequestSTK(ctx, STKRequest{
		ShortcodeType:    credentials.ShortcodeType,
		Shortcode:        credentials.Shortcode,
		Passkey:          credentials.Passkey,
		ConsumerKey:      credentials.ConsumerKey,
		ConsumerSecret:   credentials.ConsumerSecret,
		Environment:      credentials.Environment,
		Amount:           cents,
		PhoneNumber:      phoneNumber,
		CallbackURL:      callbackURL,
		AccountReference: reference,
		Description:      "Chama " + purpose,
	})
	if err != nil {
		s.log.ErrorContext(ctx, "stk request failed", "provider", s.provider.Name(), "error", err)
		return STKResult{}, httpx.NewError(502, "provider_error", "M-Pesa did not accept the request. Try again.")
	}

	pending, err := s.repo.CreatePending(ctx, CreatePendingParams{
		GroupID:        group.ID,
		UserID:         user.ID,
		Purpose:        purpose,
		AmountCents:    int64(cents),
		PhoneNumber:    phoneNumber,
		Narration:      "M-Pesa " + purpose,
		CheckoutID:     providerResp.CheckoutRequestID,
		MerchantID:     providerResp.MerchantRequestID,
		IdempotencyKey: idempotencyKey,
	})
	if err != nil {
		return STKResult{}, err
	}
	return STKResult{
		PaymentRequestID:  pending.PublicID.String(),
		CheckoutRequestID: pending.CheckoutID,
		Status:            "pending",
		Amount:            cents.String(),
		Purpose:           purpose,
	}, nil
}

type TransactionView struct {
	ID            string     `json:"id"`
	UserID        string     `json:"user_id"`
	Member        string     `json:"member"`
	Type          string     `json:"type"`
	Status        string     `json:"status"`
	Channel       *string    `json:"channel"`
	Amount        string     `json:"amount"`
	ReferenceCode *string    `json:"reference_code"`
	Narration     string     `json:"narration"`
	PeriodLabel   *string    `json:"period_label"`
	CreatedAt     time.Time  `json:"created_at"`
	CompletedAt   *time.Time `json:"completed_at"`
}

func (s *Service) ListTransactions(ctx context.Context, groupID int64, limit int32, cursor string) ([]TransactionView, string, error) {
	params := store.ListTransactionsParams{GroupID: groupID, RowLimit: limit + 1}
	if cursor != "" {
		at, id, err := decodeCursor(cursor)
		if err != nil {
			return nil, "", httpx.Validation(map[string]string{"cursor": "That cursor is not valid."})
		}
		params.BeforeAt, params.BeforeID = &at, &id
	}
	rows, err := s.repo.ListTransactions(ctx, params)
	if err != nil {
		return nil, "", err
	}
	var next string
	if len(rows) > int(limit) {
		rows = rows[:limit]
		last := rows[len(rows)-1]
		next = encodeCursor(last.CreatedAt, last.ID)
	}
	views := make([]TransactionView, 0, len(rows))
	for _, row := range rows {
		views = append(views, transactionView(row))
	}
	return views, next, nil
}

func (s *Service) GetTransaction(ctx context.Context, groupID int64, publicID uuid.UUID) (TransactionView, error) {
	row, err := s.repo.GetTransaction(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return TransactionView{}, httpx.NotFound("Transaction not found.")
	}
	if err != nil {
		return TransactionView{}, err
	}
	return TransactionView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName,
		Type:   row.TransactionType, Status: row.Status, Channel: row.Channel,
		Amount: money.Cents(row.AmountCents).String(), ReferenceCode: row.ReferenceCode,
		Narration: row.Narration, PeriodLabel: row.PeriodLabel,
		CreatedAt: row.CreatedAt, CompletedAt: row.CompletedAt,
	}, nil
}

func transactionView(row store.ListTransactionsRow) TransactionView {
	return TransactionView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName,
		Type:   row.TransactionType, Status: row.Status, Channel: row.Channel,
		Amount: money.Cents(row.AmountCents).String(), ReferenceCode: row.ReferenceCode,
		Narration: row.Narration, PeriodLabel: row.PeriodLabel,
		CreatedAt: row.CreatedAt, CompletedAt: row.CompletedAt,
	}
}

type txCursor struct {
	At time.Time `json:"at"`
	ID int64     `json:"id"`
}

func encodeCursor(at time.Time, id int64) string {
	raw, _ := json.Marshal(txCursor{At: at, ID: id})
	return base64.RawURLEncoding.EncodeToString(raw)
}

func decodeCursor(value string) (time.Time, int64, error) {
	raw, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return time.Time{}, 0, err
	}
	var cursor txCursor
	if err := json.Unmarshal(raw, &cursor); err != nil {
		return time.Time{}, 0, err
	}
	return cursor.At, cursor.ID, nil
}

func requestHash(in STKInput) []byte {
	raw, _ := json.Marshal(in)
	sum := sha256.Sum256(raw)
	return sum[:]
}

func accountReference(template string, user users.User, now time.Time) string {
	short := user.PhoneNumber
	if len(short) > 4 {
		short = short[len(short)-4:]
	}
	period := now.Format("200601")
	ref := strings.ReplaceAll(template, "{member_short}", short)
	ref = strings.ReplaceAll(ref, "{period}", period)
	if ref == "" {
		ref = "CHAMA-" + period
	}
	if len(ref) > 12 {
		ref = ref[:12]
	}
	return ref
}
