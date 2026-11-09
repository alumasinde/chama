package groups

import (
	"strings"
	"testing"
)

func TestNormalizeInviteCode(t *testing.T) {
	if got := NormalizeInviteCode(" abcd-efgh "); got != "ABCDEFGH" {
		t.Fatalf("got %q", got)
	}
	if got := NormalizeInviteCode("OIL0"); got != "0110" {
		t.Fatalf("ambiguous characters must fold, got %q", got)
	}
}

func TestInviteCodeShape(t *testing.T) {
	code, err := newInviteCode()
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != inviteLength {
		t.Fatalf("length %d", len(code))
	}
	for _, r := range code {
		if !strings.ContainsRune(inviteAlphabet, r) {
			t.Fatalf("unexpected character %q", r)
		}
	}
}

func TestNormalizeGroupInput(t *testing.T) {
	params, err := normalizeGroupInput(CreateInput{
		Name:               "  Umoja Women  ",
		ContributionAmount: "1500.50",
		Frequency:          "monthly",
	})
	if err != nil {
		t.Fatalf("valid input rejected: %v", err)
	}
	if params.Name != "Umoja Women" || params.ContributionAmountCents != 150050 {
		t.Fatalf("unexpected params %+v", params)
	}
	if params.ContributionDay != 1 || params.LateGraceDays != 3 {
		t.Fatalf("defaults not applied: %+v", params)
	}

	bad := []CreateInput{
		{Name: "A", ContributionAmount: "100", Frequency: "monthly"},
		{Name: "Umoja", ContributionAmount: "0", Frequency: "monthly"},
		{Name: "Umoja", ContributionAmount: "100", Frequency: "yearly"},
		{Name: "Umoja", ContributionAmount: "100", Frequency: "monthly", ContributionDay: int16Ptr(31)},
		{Name: "Umoja", ContributionAmount: "100", Frequency: "monthly", LateGraceDays: int32Ptr(31)},
	}
	for _, in := range bad {
		if _, err := normalizeGroupInput(in); err == nil {
			t.Fatalf("expected validation error for %+v", in)
		}
	}
}

func TestMaskSecret(t *testing.T) {
	if got := maskSecret("very-secret-key"); got != "••••-key" {
		t.Fatalf("got %q", got)
	}
	if got := maskSecret("abc"); got != "••••" {
		t.Fatalf("short secret leaked: %q", got)
	}
}

func int16Ptr(v int16) *int16 { return &v }

func int32Ptr(v int32) *int32 { return &v }
