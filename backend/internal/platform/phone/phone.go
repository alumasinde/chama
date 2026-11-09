// Package phone normalises Kenyan MSISDNs and masks them for logs.
package phone

import (
	"errors"
	"regexp"
	"strings"
)

var (
	ErrInvalid = errors.New("phone number must be a Kenyan mobile number, e.g. 0712345678")

	kenyan = regexp.MustCompile(`^\+254[17]\d{8}$`)
	anyKE  = regexp.MustCompile(`\+254[17]\d{8}`)
)

// Normalize accepts 0712..., 254712..., +254712... and returns E.164.
func Normalize(raw string) (string, error) {
	s := strings.NewReplacer(" ", "", "-", "", "(", "", ")", "", ".", "").Replace(strings.TrimSpace(raw))
	switch {
	case strings.HasPrefix(s, "+254"):
	case strings.HasPrefix(s, "254"):
		s = "+" + s
	case strings.HasPrefix(s, "0"):
		s = "+254" + s[1:]
	default:
		return "", ErrInvalid
	}
	if !kenyan.MatchString(s) {
		return "", ErrInvalid
	}
	return s, nil
}

// Mask hides the middle digits: +254712345678 -> +2547****5678.
func Mask(p string) string {
	if len(p) < 9 {
		return "****"
	}
	return p[:5] + "****" + p[len(p)-4:]
}

// MaskAll masks every E.164 Kenyan number inside a free-text string.
func MaskAll(s string) string {
	return anyKE.ReplaceAllStringFunc(s, Mask)
}
