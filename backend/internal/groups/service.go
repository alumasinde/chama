package groups

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/crypto"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/rbac"
	store "github.com/chama/chama/backend/internal/store"
	"github.com/chama/chama/backend/internal/users"
)

type Options struct {
	PublicBaseURL string
}

type Service struct {
	repo   *Repository
	cipher *crypto.Cipher
	log    *slog.Logger
	opts   Options
}

func NewService(repo *Repository, cipher *crypto.Cipher, log *slog.Logger, opts Options) *Service {
	return &Service{repo: repo, cipher: cipher, log: log, opts: opts}
}

var validFrequencies = map[string]bool{
	"weekly": true, "biweekly": true, "monthly": true, "quarterly": true,
}

func (s *Service) Create(ctx context.Context, user users.User, in CreateInput) (View, error) {
	p, err := normalizeGroupInput(in)
	if err != nil {
		return View{}, err
	}
	p.CreatedBy = user.ID
	for attempt := 0; attempt < 5; attempt++ {
		code, codeErr := newInviteCode()
		if codeErr != nil {
			return View{}, codeErr
		}
		p.InviteCode = code
		row, createErr := s.repo.Create(ctx, p, user.ID)
		if errors.Is(createErr, ErrDuplicateInvite) {
			continue
		}
		if createErr != nil {
			return View{}, createErr
		}
		return Summary{
			Group:         groupFromRow(row.ID, row.PublicID, row.Name, row.InviteCode, row.Description, row.ContributionAmountCents, row.Frequency, row.ContributionDay, row.LateGraceDays, row.CreatedAt),
			Role:          "admin",
			Status:        "active",
			ActiveMembers: 1,
		}.View(), nil
	}
	return View{}, httpx.Internal(errors.New("could not allocate a unique invite code"))
}

func (s *Service) List(ctx context.Context, user users.User) ([]View, error) {
	summaries, err := s.repo.ListForUser(ctx, user.ID)
	if err != nil {
		return nil, err
	}
	out := make([]View, 0, len(summaries))
	for _, summary := range summaries {
		out = append(out, summary.View())
	}
	return out, nil
}

func (s *Service) Get(ctx context.Context, scope Scope) (View, error) {
	active, err := s.repo.CountActiveMembers(ctx, scope.Group.ID)
	if err != nil {
		return View{}, err
	}
	return Summary{
		Group:         scope.Group,
		Role:          scope.Membership.Role,
		Status:        scope.Membership.Status,
		ActiveMembers: active,
	}.View(), nil
}

func (s *Service) Update(ctx context.Context, scope Scope, in UpdateInput) (View, error) {
	p, err := normalizeGroupInput(CreateInput(in))
	if err != nil {
		return View{}, err
	}
	group, err := s.repo.Update(ctx, store.UpdateGroupParams{
		Name:                    p.Name,
		Description:             p.Description,
		ContributionAmountCents: p.ContributionAmountCents,
		Frequency:               p.Frequency,
		ContributionDay:         p.ContributionDay,
		LateGraceDays:           p.LateGraceDays,
		ID:                      scope.Group.ID,
	})
	if err != nil {
		return View{}, err
	}
	active, err := s.repo.CountActiveMembers(ctx, group.ID)
	if err != nil {
		return View{}, err
	}
	return Summary{
		Group:         group,
		Role:          scope.Membership.Role,
		Status:        scope.Membership.Status,
		ActiveMembers: active,
	}.View(), nil
}

// Join creates a pending membership; admins approve it later.
func (s *Service) Join(ctx context.Context, user users.User, in JoinInput) (JoinResult, error) {
	code := NormalizeInviteCode(in.InviteCode)
	if len(code) != inviteLength {
		return JoinResult{}, httpx.Validation(map[string]string{
			"invite_code": "Enter the 8-character code your admin shared.",
		})
	}
	group, err := s.repo.GetByInviteCode(ctx, code)
	if errors.Is(err, ErrNotFound) {
		return JoinResult{}, httpx.NotFound("That invite code is not valid.")
	}
	if err != nil {
		return JoinResult{}, err
	}
	existing, err := s.repo.Membership(ctx, group.ID, user.ID)
	if err == nil {
		if existing.Status == "active" {
			return JoinResult{}, httpx.Conflict("already_member", "You are already a member of this chama.")
		}
		if existing.Status != "pending" {
			if err := s.repo.UpdateMembershipState(ctx, store.UpdateMembershipStateParams{
				Role: "member", Status: "pending", GroupID: group.ID, UserID: user.ID,
			}); err != nil {
				return JoinResult{}, err
			}
		}
		return pendingJoin(group), nil
	}
	if !errors.Is(err, ErrNotFound) {
		return JoinResult{}, err
	}
	if err := s.repo.CreateMembership(ctx, group.ID, user.ID, "member", "pending"); err != nil && !errors.Is(err, ErrAlreadyMember) {
		return JoinResult{}, err
	}
	return pendingJoin(group), nil
}

func pendingJoin(group Group) JoinResult {
	return JoinResult{
		GroupID:   group.PublicID.String(),
		GroupName: group.Name,
		Status:    "pending",
		Message:   "Request sent. An admin will approve you shortly.",
	}
}

func (s *Service) Members(ctx context.Context, scope Scope) ([]MemberView, error) {
	return s.repo.Members(ctx, scope.Group.ID)
}

func (s *Service) UpdateMember(ctx context.Context, actorID int64, scope Scope, targetPublicID string, in MemberUpdateInput) (MemberView, error) {
	publicID, err := uuid.Parse(targetPublicID)
	if err != nil {
		return MemberView{}, httpx.NotFound("Member not found.")
	}
	targetUserID, err := s.repo.UserIDByPublicID(ctx, publicID)
	if errors.Is(err, ErrNotFound) {
		return MemberView{}, httpx.NotFound("Member not found.")
	}
	if err != nil {
		return MemberView{}, err
	}
	target, err := s.repo.Membership(ctx, scope.Group.ID, targetUserID)
	if errors.Is(err, ErrNotFound) {
		return MemberView{}, httpx.NotFound("Member not found.")
	}
	if err != nil {
		return MemberView{}, err
	}

	role, status := target.Role, target.Status
	if in.Role != nil {
		role = strings.TrimSpace(*in.Role)
	}
	if in.Status != nil {
		status = strings.TrimSpace(*in.Status)
	}
	fields := map[string]string{}
	if !rbac.ValidRole(role) {
		fields["role"] = "Choose admin, treasurer, secretary or member."
	}
	if !rbac.ValidStatus(status) {
		fields["status"] = "Choose pending, active, suspended or exited."
	}
	if len(fields) > 0 {
		return MemberView{}, httpx.Validation(fields)
	}
	if rbac.Rank(target.Role) > rbac.Rank(scope.Membership.Role) || rbac.Rank(role) > rbac.Rank(scope.Membership.Role) {
		return MemberView{}, httpx.Forbidden("You cannot change a member above your own role.")
	}
	if target.Role == "admin" && target.Status == "active" && (role != "admin" || status != "active") {
		admins, countErr := s.repo.CountActiveAdmins(ctx, scope.Group.ID)
		if countErr != nil {
			return MemberView{}, countErr
		}
		if admins <= 1 {
			return MemberView{}, httpx.Conflict("last_admin", "A chama needs at least one active admin.")
		}
	}

	params := store.UpdateMembershipStateParams{
		Role:    role,
		Status:  status,
		Joined:  status == "active",
		Exited:  status == "exited",
		GroupID: scope.Group.ID,
		UserID:  targetUserID,
	}
	if status == "active" && target.Status != "active" {
		params.ApprovedBy = &actorID
	}
	if err := s.repo.UpdateMembershipState(ctx, params); err != nil {
		return MemberView{}, err
	}
	return s.repo.Member(ctx, scope.Group.ID, targetUserID)
}

func (s *Service) RotateInvite(ctx context.Context, scope Scope) (map[string]string, error) {
	for attempt := 0; attempt < 5; attempt++ {
		code, err := newInviteCode()
		if err != nil {
			return nil, err
		}
		err = s.repo.RotateInvite(ctx, scope.Group.ID, code)
		if errors.Is(err, ErrDuplicateInvite) {
			continue
		}
		if err != nil {
			return nil, err
		}
		return map[string]string{"invite_code": code}, nil
	}
	return nil, httpx.Internal(errors.New("could not allocate a unique invite code"))
}

func normalizeGroupInput(in CreateInput) (store.CreateGroupParams, error) {
	fields := map[string]string{}
	name := strings.TrimSpace(in.Name)
	if n := utf8.RuneCountInString(name); n < 2 || n > 80 {
		fields["name"] = "Use between 2 and 80 characters."
	}
	description := trimOptional(in.Description)
	if description != nil && utf8.RuneCountInString(*description) > 280 {
		fields["description"] = "Keep the description under 280 characters."
	}
	cents, err := money.ParseAmount(in.ContributionAmount)
	if err != nil {
		fields["contribution_amount"] = "Enter an amount above zero, for example 1500.00."
	}
	frequency := strings.TrimSpace(in.Frequency)
	if !validFrequencies[frequency] {
		fields["contribution_frequency"] = "Choose weekly, biweekly, monthly or quarterly."
	}
	day := int16(1)
	if in.ContributionDay != nil {
		day = *in.ContributionDay
	}
	if day < 0 || day > 28 {
		fields["contribution_day"] = "Use a day between 0 and 28."
	}
	grace := int32(3)
	if in.LateGraceDays != nil {
		grace = *in.LateGraceDays
	}
	if grace < 0 || grace > 30 {
		fields["late_grace_days"] = "Grace must be between 0 and 30 days."
	}
	if len(fields) > 0 {
		return store.CreateGroupParams{}, httpx.Validation(fields)
	}
	return store.CreateGroupParams{
		Name:                    name,
		Description:             description,
		ContributionAmountCents: int64(cents),
		Frequency:               frequency,
		ContributionDay:         day,
		LateGraceDays:           grace,
	}, nil
}

func trimOptional(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}
