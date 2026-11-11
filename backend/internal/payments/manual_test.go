//go:build integration

package payments

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/testdb"
	"github.com/chama/chama/backend/internal/users"
)

type manualFixture struct {
	pool    *pgxpool.Pool
	repo    *Repository
	group   groups.Group
	admin   users.User
	active  users.User
	pending users.User
}

func newManualFixture(t *testing.T) manualFixture {
	t.Helper()
	ctx := context.Background()
	pool := testdb.New(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	cipher, err := crypto.NewCipher(bytes.Repeat([]byte{7}, 32))
	if err != nil {
		t.Fatalf("cipher: %v", err)
	}
	groupsSvc := groups.NewService(groups.NewRepository(pool), cipher, log,
		groups.Options{PublicBaseURL: "https://example.test"})

	admin := seedUser(t, pool, "0700000001", "Amina")
	active := seedUser(t, pool, "0700000002", "Brian")
	pending := seedUser(t, pool, "0700000003", "Caro")

	created, err := groupsSvc.Create(ctx, admin, groups.CreateInput{
		Name: "Umoja", ContributionAmount: "1000", Frequency: "monthly",
	})
	if err != nil {
		t.Fatalf("create group: %v", err)
	}
	publicID, err := uuid.Parse(created.ID)
	if err != nil {
		t.Fatalf("group id: %v", err)
	}
	group, err := groupsSvc.Find(ctx, publicID)
	if err != nil {
		t.Fatalf("find group: %v", err)
	}
	seedMember(t, pool, group.ID, active.ID, "member", "active")
	seedMember(t, pool, group.ID, pending.ID, "member", "pending")

	return manualFixture{
		pool:    pool,
		repo:    NewRepository(pool),
		group:   group,
		admin:   admin,
		active:  active,
		pending: pending,
	}
}

func seedUser(t *testing.T, pool *pgxpool.Pool, phone, first string) users.User {
	t.Helper()
	var u users.User
	err := pool.QueryRow(context.Background(), `
		INSERT INTO users (phone_number, first_name, last_name, is_active, phone_verified_at)
		VALUES ($1, $2, 'Mwangazi', TRUE, now())
		RETURNING id, public_id, phone_number, first_name, last_name, is_active, created_at, updated_at`,
		phone, first).Scan(
		&u.ID, &u.PublicID, &u.PhoneNumber, &u.FirstName, &u.LastName,
		&u.IsActive, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		t.Fatalf("seed user %s: %v", phone, err)
	}
	return u
}

func seedMember(t *testing.T, pool *pgxpool.Pool, groupID, userID int64, role, status string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO group_members (group_id, user_id, role_id, status_id, joined_at)
		VALUES ($1, $2,
		        (SELECT id FROM member_roles WHERE code = $3),
		        (SELECT id FROM member_statuses WHERE code = $4),
		        now())`,
		groupID, userID, role, status)
	if err != nil {
		t.Fatalf("seed member %d (%s/%s): %v", userID, role, status, err)
	}
}

func TestRecordManualContributionOnPostgres(t *testing.T) {
	f := newManualFixture(t)
	ctx := context.Background()

	row, err := f.repo.RecordManualContribution(ctx, ManualParams{
		GroupID:        f.group.ID,
		MemberPublicID: f.active.PublicID,
		AmountCents:    150000,
		ReferenceCode:  "SLK7XQ2P9D",
		Narration:      "Contribution recorded by the treasurer",
		RecordedBy:     f.admin.ID,
	})
	if err != nil {
		t.Fatalf("record manual contribution: %v", err)
	}
	if row.UserID != f.active.ID {
		t.Fatalf("credited user = %d, want %d", row.UserID, f.active.ID)
	}

	var status, channel, reference, txType string
	var recordedBy int64
	err = f.pool.QueryRow(ctx, `
		SELECT s.code, c.code, t.reference_code, tt.code, t.recorded_by
		FROM transactions t
		JOIN transaction_statuses s ON s.id = t.status_id
		JOIN payment_channels c ON c.id = t.channel_id
		JOIN transaction_types tt ON tt.id = t.transaction_type_id
		WHERE t.public_id = $1`, row.TransactionID).
		Scan(&status, &channel, &reference, &txType, &recordedBy)
	if err != nil {
		t.Fatalf("load ledger row: %v", err)
	}
	if status != "completed" || txType != "contribution" || channel != "mpesa_manual" {
		t.Fatalf("unexpected row: status=%s type=%s channel=%s", status, txType, channel)
	}
	if reference != "SLK7XQ2P9D" {
		t.Fatalf("reference = %q", reference)
	}
	if recordedBy != f.admin.ID {
		t.Fatalf("recorded_by = %d, want %d", recordedBy, f.admin.ID)
	}

	// The same M-Pesa code can only be recorded once for a chama.
	_, err = f.repo.RecordManualContribution(ctx, ManualParams{
		GroupID:        f.group.ID,
		MemberPublicID: f.active.PublicID,
		AmountCents:    150000,
		ReferenceCode:  "SLK7XQ2P9D",
		Narration:      "Duplicate",
		RecordedBy:     f.admin.ID,
	})
	if !errors.Is(err, ErrReferenceRecorded) {
		t.Fatalf("duplicate code error = %v, want ErrReferenceRecorded", err)
	}

	// A pending member cannot be credited.
	_, err = f.repo.RecordManualContribution(ctx, ManualParams{
		GroupID:        f.group.ID,
		MemberPublicID: f.pending.PublicID,
		AmountCents:    50000,
		ReferenceCode:  "QWERTY1234",
		Narration:      "Pending member",
		RecordedBy:     f.admin.ID,
	})
	if !errors.Is(err, ErrMemberNotActive) {
		t.Fatalf("pending member error = %v, want ErrMemberNotActive", err)
	}
}
