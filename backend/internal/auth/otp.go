package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"fmt"

	"github.com/chama/chama/backend/internal/platform/crypto"
)

// GenerateOTP returns a six-digit code with leading zeros preserved.
func GenerateOTP() (string, error) {
	return crypto.Digits(6)
}

// HashOTP binds the code to the phone and purpose so it cannot be replayed elsewhere.
func HashOTP(key []byte, phoneNumber, purpose, code string) []byte {
	mac := hmac.New(sha256.New, key)
	_, _ = fmt.Fprintf(mac, "%s|%s|%s", phoneNumber, purpose, code)
	return mac.Sum(nil)
}

func constantTimeEqual(a, b []byte) bool { return hmac.Equal(a, b) }

func validPurpose(purpose string) bool {
	switch purpose {
	case PurposeLogin, PurposeRegistration, PurposePINReset:
		return true
	default:
		return false
	}
}
