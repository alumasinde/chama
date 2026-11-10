package loans

import (
	"context"
	"errors"
	"math/big"
	"strings"
	"time"

	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
)

type rules struct {
	allow      bool
	rate       string
	method     string
	multiple   *big.Rat
	maxTerm    int16
	guarantors int16
	updatedAt  *time.Time
}

var defaultRules = rules{
	allow: true, rate: "10.000", method: "flat",
	multiple: big.NewRat(3, 1), maxTerm: 12, guarantors: 1,
}

func (s *Service) rules(ctx context.Context, groupID int64) (rules, error) {
	row, err := s.repo.Settings(ctx, groupID)
	if errors.Is(err, ErrNotFound) {
		return defaultRules, nil
	}
	if err != nil {
		return rules{}, err
	}
	multiple, ok := new(big.Rat).SetString(row.MaxMultiple)
	if !ok || multiple.Sign() <= 0 {
		multiple = defaultRules.multiple
	}
	updated := row.UpdatedAt
	return rules{
		allow: row.AllowLoans, rate: row.InterestRate, method: row.InterestMethod,
		multiple: multiple, maxTerm: row.MaxTermMonths, guarantors: row.GuarantorsRequired,
		updatedAt: &updated,
	}, nil
}

func (s *Service) Settings(ctx context.Context, groupID int64) (SettingsView, error) {
	r, err := s.rules(ctx, groupID)
	if err != nil {
		return SettingsView{}, err
	}
	return SettingsView{
		AllowLoans: r.allow, InterestRate: r.rate, InterestMethod: r.method,
		MaxMultiple: r.multiple.FloatString(2), MaxTermMonths: r.maxTerm,
		GuarantorsRequired: r.guarantors, UpdatedAt: r.updatedAt,
	}, nil
}

func (s *Service) PutSettings(ctx context.Context, groupID int64, in SettingsInput) (SettingsView, error) {
	fields := map[string]string{}
	rate, ok := parseDecimal(in.InterestRate)
	if !ok || rate.Cmp(big.NewRat(100, 1)) > 0 {
		fields["interest_rate"] = "Enter a monthly rate between 0 and 100."
	}
	if in.InterestMethod != "flat" && in.InterestMethod != "reducing_balance" {
		fields["interest_method"] = "Choose flat or reducing_balance."
	}
	multiple, ok := parseDecimal(in.MaxMultiple)
	if !ok || multiple.Sign() == 0 || multiple.Cmp(big.NewRat(100, 1)) > 0 {
		fields["max_multiple_of_savings"] = "Enter a multiple between 0 and 100."
	}
	if in.MaxTermMonths < 1 || in.MaxTermMonths > 60 {
		fields["max_term_months"] = "Term must be between 1 and 60 months."
	}
	if in.GuarantorsRequired < 0 || in.GuarantorsRequired > 10 {
		fields["guarantors_required"] = "Guarantors must be between 0 and 10."
	}
	if len(fields) > 0 {
		return SettingsView{}, httpx.Validation(fields)
	}
	allow := true
	if in.AllowLoans != nil {
		allow = *in.AllowLoans
	}
	if err := s.repo.UpsertSettings(ctx, store.UpsertLoanSettingsParams{
		GroupID: groupID, InterestRate: strings.TrimSpace(in.InterestRate),
		InterestMethod: in.InterestMethod, MaxMultiple: strings.TrimSpace(in.MaxMultiple),
		MaxTermMonths: in.MaxTermMonths, GuarantorsRequired: in.GuarantorsRequired, AllowLoans: allow,
	}); err != nil {
		return SettingsView{}, err
	}
	return s.Settings(ctx, groupID)
}

func parseDecimal(raw string) (*big.Rat, bool) {
	value, ok := new(big.Rat).SetString(strings.TrimSpace(raw))
	if !ok || value.Sign() < 0 {
		return nil, false
	}
	return value, true
}

func itoa(n int) string {
	return big.NewInt(int64(n)).String()
}
