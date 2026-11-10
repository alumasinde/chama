package loans

import (
	"errors"
	"math/big"
	"time"
)

// ErrBadSchedule is returned when the loan terms cannot produce a schedule.
var ErrBadSchedule = errors.New("invalid loan terms")

// ScheduleRequest is the exact input the amortization engine needs.
type ScheduleRequest struct {
	PrincipalCents     int64
	MonthlyRatePercent string
	Method             string
	TermMonths         int
	FirstDue           time.Time
}

type Installment struct {
	Number         int16
	DueDate        time.Time
	PrincipalCents int64
	InterestCents  int64
}

type Schedule struct {
	Installments       []Installment
	TotalInterestCents int64
	TotalPayableCents  int64
}

// BuildSchedule is pure: flat interest spreads a rounded total, reducing balance
// recomputes interest on the opening balance each month. The final installment
// absorbs every rounding remainder so the sums always equal the loan totals.
func BuildSchedule(req ScheduleRequest) (Schedule, error) {
	if req.PrincipalCents <= 0 || req.TermMonths < 1 || req.TermMonths > 60 || req.FirstDue.IsZero() {
		return Schedule{}, ErrBadSchedule
	}
	rate, ok := new(big.Rat).SetString(req.MonthlyRatePercent)
	if !ok || rate.Sign() < 0 {
		return Schedule{}, ErrBadSchedule
	}
	rate.Quo(rate, big.NewRat(100, 1))

	switch req.Method {
	case "flat":
		return flatSchedule(req, rate)
	case "reducing_balance":
		return reducingSchedule(req, rate)
	default:
		return Schedule{}, ErrBadSchedule
	}
}

func flatSchedule(req ScheduleRequest, rate *big.Rat) (Schedule, error) {
	n := int64(req.TermMonths)
	principal := big.NewRat(req.PrincipalCents, 1)
	total := new(big.Rat).Mul(principal, rate)
	total.Mul(total, new(big.Rat).SetInt64(n))
	totalInterest := ratCents(total)

	basePrincipal := req.PrincipalCents / n
	baseInterest := totalInterest / n
	out := Schedule{Installments: make([]Installment, 0, req.TermMonths)}
	var principalSum, interestSum int64
	for i := int64(0); i < n; i++ {
		p, interest := basePrincipal, baseInterest
		if i == n-1 {
			p = req.PrincipalCents - principalSum
			interest = totalInterest - interestSum
		}
		principalSum += p
		interestSum += interest
		out.Installments = append(out.Installments, Installment{
			Number: int16(i + 1), DueDate: req.FirstDue.AddDate(0, int(i), 0),
			PrincipalCents: p, InterestCents: interest,
		})
	}
	out.TotalInterestCents = interestSum
	out.TotalPayableCents = principalSum + interestSum
	return out, nil
}

func reducingSchedule(req ScheduleRequest, rate *big.Rat) (Schedule, error) {
	n := int64(req.TermMonths)
	var emi int64
	if rate.Sign() == 0 {
		emi = req.PrincipalCents / n
	} else {
		// EMI = P·i·(1+i)^n / ((1+i)^n − 1)
		one := big.NewRat(1, 1)
		pow := new(big.Rat).SetInt64(1)
		factor := new(big.Rat).Add(one, rate)
		for i := int64(0); i < n; i++ {
			pow.Mul(pow, factor)
		}
		emiRat := new(big.Rat).SetInt64(req.PrincipalCents)
		emiRat.Mul(emiRat, rate)
		emiRat.Mul(emiRat, pow)
		den := new(big.Rat).Sub(pow, one)
		emiRat.Quo(emiRat, den)
		emi = ratCents(emiRat)
	}

	out := Schedule{Installments: make([]Installment, 0, req.TermMonths)}
	opening := req.PrincipalCents
	var interestSum int64
	for i := int64(0); i < n; i++ {
		interest := ratCents(new(big.Rat).Mul(new(big.Rat).SetInt64(opening), rate))
		var principal int64
		if i == n-1 {
			principal = opening
		} else {
			principal = emi - interest
			if principal < 0 {
				principal = 0
			}
			if principal > opening {
				principal = opening
			}
		}
		opening -= principal
		interestSum += interest
		out.Installments = append(out.Installments, Installment{
			Number: int16(i + 1), DueDate: req.FirstDue.AddDate(0, int(i), 0),
			PrincipalCents: principal, InterestCents: interest,
		})
	}
	out.TotalInterestCents = interestSum
	out.TotalPayableCents = req.PrincipalCents + interestSum
	return out, nil
}

// ratCents rounds a non-negative rational to whole cents, half away from zero.
func ratCents(r *big.Rat) int64 {
	num := new(big.Int).Mul(r.Num(), big.NewInt(2))
	num.Add(num, r.Denom())
	den := new(big.Int).Mul(r.Denom(), big.NewInt(2))
	return new(big.Int).Quo(num, den).Int64()
}
