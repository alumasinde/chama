package loans

import (
	"testing"
	"time"
)

type scheduleFixture struct {
	name      string
	principal int64
	rate      string
	method    string
	term      int
}

func TestScheduleSumsAreExact(t *testing.T) {
	fixtures := []scheduleFixture{
		{"flat 10000 at 10% for 12", 1_000_000, "10.000", "flat", 12},
		{"flat 10000 at 10% for 7", 1_000_000, "10.000", "flat", 7},
		{"flat 100000 at 5% for 6", 10_000_000, "5.000", "flat", 6},
		{"flat 33333 at 7.5% for 5", 3_333_300, "7.500", "flat", 5},
		{"flat 1200 at 10% for 12 rounding edge", 120_000, "10.000", "flat", 12},
		{"flat 999 at 0% for 7", 99_900, "0", "flat", 7},
		{"reducing 10000 at 10% for 12", 1_000_000, "10.000", "reducing_balance", 12},
		{"reducing 10000 at 10% for 7", 1_000_000, "10.000", "reducing_balance", 7},
		{"reducing 100000 at 5% for 6", 10_000_000, "5.000", "reducing_balance", 6},
		{"reducing 50000 at 12.5% for 24", 5_000_000, "12.500", "reducing_balance", 24},
		{"reducing 12345 at 3% for 9", 1_234_500, "3.000", "reducing_balance", 9},
		{"reducing 1000000 at 1% for 60", 100_000_000, "1.000", "reducing_balance", 60},
		{"reducing 250000 at 8.75% for 18", 25_000_000, "8.750", "reducing_balance", 18},
	}
	firstDue := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)
	for _, f := range fixtures {
		t.Run(f.name, func(t *testing.T) {
			s, err := BuildSchedule(ScheduleRequest{
				PrincipalCents: f.principal, MonthlyRatePercent: f.rate,
				Method: f.method, TermMonths: f.term, FirstDue: firstDue,
			})
			if err != nil {
				t.Fatalf("BuildSchedule: %v", err)
			}
			if len(s.Installments) != f.term {
				t.Fatalf("installments = %d, want %d", len(s.Installments), f.term)
			}
			var principalSum, interestSum int64
			for i, inst := range s.Installments {
				if inst.Number != int16(i+1) {
					t.Fatalf("installment %d numbered %d", i, inst.Number)
				}
				if inst.PrincipalCents <= 0 {
					t.Fatalf("installment %d principal = %d", i+1, inst.PrincipalCents)
				}
				if inst.InterestCents < 0 {
					t.Fatalf("installment %d interest = %d", i+1, inst.InterestCents)
				}
				if inst.DueDate != firstDue.AddDate(0, i, 0) {
					t.Fatalf("installment %d due %s", i+1, inst.DueDate)
				}
				principalSum += inst.PrincipalCents
				interestSum += inst.InterestCents
			}
			if principalSum != f.principal {
				t.Fatalf("principal sum = %d, want %d", principalSum, f.principal)
			}
			if interestSum != s.TotalInterestCents {
				t.Fatalf("interest sum = %d, total = %d", interestSum, s.TotalInterestCents)
			}
			if s.TotalPayableCents != f.principal+s.TotalInterestCents {
				t.Fatalf("payable = %d, want %d", s.TotalPayableCents, f.principal+s.TotalInterestCents)
			}
		})
	}
}

func TestScheduleRejectsBadTerms(t *testing.T) {
	firstDue := time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC)
	bad := []ScheduleRequest{
		{PrincipalCents: 0, MonthlyRatePercent: "10", Method: "flat", TermMonths: 3, FirstDue: firstDue},
		{PrincipalCents: 100, MonthlyRatePercent: "10", Method: "flat", TermMonths: 0, FirstDue: firstDue},
		{PrincipalCents: 100, MonthlyRatePercent: "10", Method: "flat", TermMonths: 61, FirstDue: firstDue},
		{PrincipalCents: 100, MonthlyRatePercent: "10", Method: "balloon", TermMonths: 3, FirstDue: firstDue},
		{PrincipalCents: 100, MonthlyRatePercent: "-1", Method: "flat", TermMonths: 3, FirstDue: firstDue},
		{PrincipalCents: 100, MonthlyRatePercent: "10", Method: "flat", TermMonths: 3},
	}
	for _, req := range bad {
		if _, err := BuildSchedule(req); err == nil {
			t.Fatalf("expected rejection for %+v", req)
		}
	}
}
