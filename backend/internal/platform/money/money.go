// Package money keeps amounts as integer cents; floats never enter the ledger.
package money

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

type Cents int64

const maxCents = int64(999_999_999_999_99)

var ErrInvalidAmount = errors.New("amount must be a positive number with at most 2 decimals")

// ParseAmount reads "1500", "1500.5" or "1500.50" without floating point.
func ParseAmount(raw string) (Cents, error) {
	s := strings.TrimSpace(raw)
	if s == "" || strings.HasPrefix(s, "-") || strings.HasPrefix(s, "+") {
		return 0, ErrInvalidAmount
	}
	whole, frac, hasFrac := strings.Cut(s, ".")
	if whole == "" {
		whole = "0"
	}
	if len(frac) > 2 || (hasFrac && frac == "") {
		return 0, ErrInvalidAmount
	}
	if !digitsOnly(whole) || (hasFrac && !digitsOnly(frac)) {
		return 0, ErrInvalidAmount
	}
	for len(frac) < 2 {
		frac += "0"
	}
	units, err := strconv.ParseInt(whole, 10, 64)
	if err != nil || units > maxCents/100 {
		return 0, ErrInvalidAmount
	}
	cents, err := strconv.ParseInt(frac, 10, 64)
	if err != nil {
		return 0, ErrInvalidAmount
	}
	total := units*100 + cents
	if total <= 0 || total > maxCents {
		return 0, ErrInvalidAmount
	}
	return Cents(total), nil
}

func digitsOnly(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// String renders cents with exactly two decimals, e.g. 150050 -> "1500.50".
func (c Cents) String() string {
	sign := ""
	value := int64(c)
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.Sprintf("%s%d.%02d", sign, value/100, value%100)
}

func (c Cents) IsPositive() bool { return c > 0 }
