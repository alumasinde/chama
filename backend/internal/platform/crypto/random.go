package crypto

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"math/big"
)

var randomRead = rand.Read

// Token returns a URL-safe random string with n bytes of entropy.
func Token(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("random bytes: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// Digits returns a fixed-length numeric string with leading zeros preserved.
func Digits(n int) (string, error) {
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil)
	v, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", fmt.Errorf("random digits: %w", err)
	}
	return fmt.Sprintf("%0*s", n, v.String()), nil
}

// Hash is used for refresh tokens and OTPs so the raw value is never stored.
func Hash(raw string) []byte {
	sum := sha256.Sum256([]byte(raw))
	return sum[:]
}
