package groups

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

var (
	ErrNotFound        = errors.New("group not found")
	ErrDuplicateInvite = errors.New("invite code already used")
	ErrAlreadyMember   = errors.New("already a member")
)

// PaymentSettings carries decrypted-at-the-edge ciphertext only.
type PaymentSettings struct {
	ShortcodeType            string
	Shortcode                string
	AccountReferenceTemplate string
	DarajaEnvironment        string
	ConsumerKeyEnc           []byte
	ConsumerSecretEnc        []byte
	PasskeyEnc               []byte
	CallbackSecretEnc        []byte
	IsVerified               bool
	VerifiedAt               *time.Time
	UpdatedAt                time.Time
}

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

// Create makes the chama and its first admin in one transaction.
func (r *Repository) Create(ctx context.Context, p store.CreateGroupParams, adminUserID int64) (store.CreateGroupRow, error) {
	var row store.CreateGroupRow
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		created, err := q.CreateGroup(ctx, p)
		if err != nil {
			return err
		}
		if _, err := q.CreateMembership(ctx, store.CreateMembershipParams{
			GroupID: created.ID, UserID: adminUserID, Role: "admin", Status: "active",
		}); err != nil {
			return err
		}
		row = created
		return nil
	})
	if err != nil {
		return store.CreateGroupRow{}, mapWriteError(err)
	}
	return row, nil
}

func (r *Repository) GetByPublicID(ctx context.Context, publicID uuid.UUID) (Group, error) {
	row, err := r.q.GetGroupByPublicID(ctx, publicID)
	if errors.Is(err, pgx.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	return groupFromRow(row.ID, row.PublicID, row.Name, row.InviteCode, row.Description,
		row.ContributionAmountCents, row.Frequency, row.ContributionDay, row.LateGraceDays, row.CreatedAt), nil
}

func (r *Repository) GetByInviteCode(ctx context.Context, code string) (Group, error) {
	row, err := r.q.GetGroupByInviteCode(ctx, code)
	if errors.Is(err, pgx.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	return groupFromRow(row.ID, row.PublicID, row.Name, row.InviteCode, row.Description,
		row.ContributionAmountCents, row.Frequency, row.ContributionDay, row.LateGraceDays, row.CreatedAt), nil
}

func (r *Repository) Update(ctx context.Context, p store.UpdateGroupParams) (Group, error) {
	row, err := r.q.UpdateGroup(ctx, p)
	if errors.Is(err, pgx.ErrNoRows) {
		return Group{}, ErrNotFound
	}
	if err != nil {
		return Group{}, err
	}
	return groupFromRow(row.ID, row.PublicID, row.Name, row.InviteCode, row.Description,
		row.ContributionAmountCents, row.Frequency, row.ContributionDay, row.LateGraceDays, row.CreatedAt), nil
}

func (r *Repository) RotateInvite(ctx context.Context, groupID int64, code string) error {
	return r.q.RotateInviteCode(ctx, store.RotateInviteCodeParams{InviteCode: code, ID: groupID})
}

func (r *Repository) ListForUser(ctx context.Context, userID int64) ([]Summary, error) {
	rows, err := r.q.ListGroupsForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Summary, 0, len(rows))
	for _, row := range rows {
		out = append(out, Summary{
			Group: groupFromRow(row.ID, row.PublicID, row.Name, row.InviteCode, row.Description,
				row.ContributionAmountCents, row.Frequency, row.ContributionDay, row.LateGraceDays, row.CreatedAt),
			Role:          row.Role,
			Status:        row.Status,
			ActiveMembers: row.ActiveMembers,
		})
	}
	return out, nil
}

func (r *Repository) Membership(ctx context.Context, groupID, userID int64) (Membership, error) {
	row, err := r.q.GetMembership(ctx, store.GetMembershipParams{GroupID: groupID, UserID: userID})
	if errors.Is(err, pgx.ErrNoRows) {
		return Membership{}, ErrNotFound
	}
	if err != nil {
		return Membership{}, err
	}
	return Membership{GroupID: row.GroupID, UserID: row.UserID, Role: row.Role, Status: row.Status, JoinedAt: row.JoinedAt}, nil
}

func (r *Repository) CreateMembership(ctx context.Context, groupID, userID int64, role, status string) error {
	_, err := r.q.CreateMembership(ctx, store.CreateMembershipParams{
		GroupID: groupID, UserID: userID, Role: role, Status: status,
	})
	return mapWriteError(err)
}

func (r *Repository) UpdateMembershipState(ctx context.Context, p store.UpdateMembershipStateParams) error {
	rows, err := r.q.UpdateMembershipState(ctx, p)
	if err != nil {
		return err
	}
	if rows == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) Members(ctx context.Context, groupID int64) ([]MemberView, error) {
	rows, err := r.q.ListGroupMembers(ctx, groupID)
	if err != nil {
		return nil, err
	}
	out := make([]MemberView, 0, len(rows))
	for _, row := range rows {
		out = append(out, MemberView{
			UserID:      row.UserPublicID.String(),
			FirstName:   row.FirstName,
			LastName:    row.LastName,
			DisplayName: row.FirstName + " " + row.LastName,
			Role:        row.Role,
			Status:      row.Status,
			JoinedAt:    row.JoinedAt,
		})
	}
	return out, nil
}

func (r *Repository) Member(ctx context.Context, groupID, userID int64) (MemberView, error) {
	row, err := r.q.GetGroupMember(ctx, store.GetGroupMemberParams{GroupID: groupID, UserID: userID})
	if errors.Is(err, pgx.ErrNoRows) {
		return MemberView{}, ErrNotFound
	}
	if err != nil {
		return MemberView{}, err
	}
	return MemberView{
		UserID:      row.UserPublicID.String(),
		FirstName:   row.FirstName,
		LastName:    row.LastName,
		DisplayName: row.FirstName + " " + row.LastName,
		Role:        row.Role,
		Status:      row.Status,
		JoinedAt:    row.JoinedAt,
	}, nil
}

func (r *Repository) CountActiveAdmins(ctx context.Context, groupID int64) (int64, error) {
	return r.q.CountActiveAdmins(ctx, groupID)
}

func (r *Repository) CountActiveMembers(ctx context.Context, groupID int64) (int64, error) {
	return r.q.CountActiveMembers(ctx, groupID)
}

func (r *Repository) UserIDByPublicID(ctx context.Context, publicID uuid.UUID) (int64, error) {
	id, err := r.q.GetUserIDByPublicID(ctx, publicID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	return id, err
}

func (r *Repository) PaymentSettings(ctx context.Context, groupID int64) (PaymentSettings, error) {
	row, err := r.q.GetPaymentSettings(ctx, groupID)
	if errors.Is(err, pgx.ErrNoRows) {
		return PaymentSettings{}, ErrNotFound
	}
	if err != nil {
		return PaymentSettings{}, err
	}
	return PaymentSettings{
		ShortcodeType:            row.ShortcodeType,
		Shortcode:                row.Shortcode,
		AccountReferenceTemplate: row.AccountReferenceTemplate,
		DarajaEnvironment:        row.DarajaEnvironment,
		ConsumerKeyEnc:           row.DarajaConsumerKeyEnc,
		ConsumerSecretEnc:        row.DarajaConsumerSecretEnc,
		PasskeyEnc:               row.DarajaPasskeyEnc,
		CallbackSecretEnc:        row.CallbackSecretEnc,
		IsVerified:               row.IsVerified,
		VerifiedAt:               row.VerifiedAt,
		UpdatedAt:                row.UpdatedAt,
	}, nil
}

func (r *Repository) UpsertPaymentSettings(ctx context.Context, p store.UpsertPaymentSettingsParams) error {
	return r.q.UpsertPaymentSettings(ctx, p)
}

func (r *Repository) MarkPaymentSettingsVerified(ctx context.Context, groupID, actorID int64) error {
	return r.q.MarkPaymentSettingsVerified(ctx, store.MarkPaymentSettingsVerifiedParams{
		GroupID:   groupID,
		UpdatedBy: &actorID,
	})
}

func groupFromRow(id int64, publicID uuid.UUID, name, inviteCode string, description *string,
	cents int64, frequency string, day int16, grace int32, createdAt time.Time) Group {
	return Group{
		ID:              id,
		PublicID:        publicID,
		Name:            name,
		InviteCode:      inviteCode,
		Description:     description,
		Contribution:    money.Cents(cents),
		Frequency:       frequency,
		ContributionDay: day,
		LateGraceDays:   grace,
		CreatedAt:       createdAt,
	}
}

func mapWriteError(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		switch pgErr.ConstraintName {
		case "groups_invite_code_key":
			return ErrDuplicateInvite
		case "group_members_group_id_user_id_key":
			return ErrAlreadyMember
		}
	}
	return err
}
