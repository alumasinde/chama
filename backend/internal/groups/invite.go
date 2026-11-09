package groups

import (
	"crypto/rand"
	"strings"
)

// Crockford-style alphabet: 32 symbols, so byte modulo is unbiased.
const inviteAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const inviteLength = 8

func newInviteCode() (string, error) {
	buf := make([]byte, inviteLength)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	out := make([]byte, inviteLength)
	for i, b := range buf {
		out[i] = inviteAlphabet[int(b)%len(inviteAlphabet)]
	}
	return string(out), nil
}

// NormalizeInviteCode accepts what people actually type: spaces, dashes, lowercase, O for 0.
func NormalizeInviteCode(raw string) string {
	replacer := strings.NewReplacer(" ", "", "-", "", "O", "0", "I", "1", "L", "1")
	return replacer.Replace(strings.ToUpper(strings.TrimSpace(raw)))
}
