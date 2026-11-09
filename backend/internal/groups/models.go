package groups

import (
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/money"
)

type Group struct {
	ID              int64
	PublicID        uuid.UUID
	Name            string
	InviteCode      string
	Description     *string
	Contribution    money.Cents
	Frequency       string
	ContributionDay int16
	LateGraceDays   int32
	CreatedAt       time.Time
}

type Membership struct {
	GroupID  int64
	UserID   int64
	Role     string
	Status   string
	JoinedAt *time.Time
}

type Summary struct {
	Group         Group
	Role          string
	Status        string
	ActiveMembers int64
}

// View is what every endpoint returns for a chama.
type View struct {
	ID                    string    `json:"id"`
	Name                  string    `json:"name"`
	Description           *string   `json:"description"`
	InviteCode            string    `json:"invite_code"`
	Currency              string    `json:"currency"`
	ContributionAmount    string    `json:"contribution_amount"`
	ContributionFrequency string    `json:"contribution_frequency"`
	ContributionDay       int16     `json:"contribution_day"`
	LateGraceDays         int32     `json:"late_grace_days"`
	Role                  string    `json:"role,omitempty"`
	Status                string    `json:"status,omitempty"`
	ActiveMembers         int64     `json:"active_members"`
	CreatedAt             time.Time `json:"created_at"`
}

func (s Summary) View() View {
	return View{
		ID:                    s.Group.PublicID.String(),
		Name:                  s.Group.Name,
		Description:           s.Group.Description,
		InviteCode:            s.Group.InviteCode,
		Currency:              "KES",
		ContributionAmount:    s.Group.Contribution.String(),
		ContributionFrequency: s.Group.Frequency,
		ContributionDay:       s.Group.ContributionDay,
		LateGraceDays:         s.Group.LateGraceDays,
		Role:                  s.Role,
		Status:                s.Status,
		ActiveMembers:         s.ActiveMembers,
		CreatedAt:             s.Group.CreatedAt,
	}
}

type MemberView struct {
	UserID      string     `json:"user_id"`
	FirstName   string     `json:"first_name"`
	LastName    string     `json:"last_name"`
	DisplayName string     `json:"display_name"`
	Role        string     `json:"role"`
	Status      string     `json:"status"`
	JoinedAt    *time.Time `json:"joined_at"`
}

type CreateInput struct {
	Name               string  `json:"name"`
	Description        *string `json:"description"`
	ContributionAmount string  `json:"contribution_amount"`
	Frequency          string  `json:"contribution_frequency"`
	ContributionDay    *int16  `json:"contribution_day"`
	LateGraceDays      *int32  `json:"late_grace_days"`
}

type UpdateInput struct {
	Name               string  `json:"name"`
	Description        *string `json:"description"`
	ContributionAmount string  `json:"contribution_amount"`
	Frequency          string  `json:"contribution_frequency"`
	ContributionDay    *int16  `json:"contribution_day"`
	LateGraceDays      *int32  `json:"late_grace_days"`
}

type JoinInput struct {
	InviteCode string `json:"invite_code"`
}

type JoinResult struct {
	GroupID   string `json:"group_id"`
	GroupName string `json:"group_name"`
	Status    string `json:"status"`
	Message   string `json:"message"`
}

type MemberUpdateInput struct {
	Role   *string `json:"role"`
	Status *string `json:"status"`
}

type PaymentSettingsInput struct {
	ShortcodeType            string  `json:"shortcode_type"`
	Shortcode                string  `json:"shortcode"`
	AccountReferenceTemplate *string `json:"account_reference_template"`
	DarajaEnvironment        string  `json:"daraja_environment"`
	ConsumerKey              *string `json:"consumer_key"`
	ConsumerSecret           *string `json:"consumer_secret"`
	Passkey                  *string `json:"passkey"`
}

// PaymentSettingsView only ever carries masked secrets.
type PaymentSettingsView struct {
	Configured               bool       `json:"configured"`
	ShortcodeType            string     `json:"shortcode_type"`
	Shortcode                string     `json:"shortcode"`
	AccountReferenceTemplate string     `json:"account_reference_template"`
	DarajaEnvironment        string     `json:"daraja_environment"`
	ConsumerKeyMasked        string     `json:"consumer_key_masked"`
	ConsumerSecretMasked     string     `json:"consumer_secret_masked"`
	PasskeyMasked            string     `json:"passkey_masked"`
	IsVerified               bool       `json:"is_verified"`
	VerifiedAt               *time.Time `json:"verified_at"`
	UpdatedAt                *time.Time `json:"updated_at"`
	CallbackURL              string     `json:"callback_url,omitempty"`
}
