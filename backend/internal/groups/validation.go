package groups

import (
	"strings"
	"unicode/utf8"

	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

var validFrequencies = map[string]bool{
	"weekly": true, "biweekly": true, "monthly": true, "quarterly": true,
}

// normalizeGroupInput turns API input into store params or field-level errors.
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
