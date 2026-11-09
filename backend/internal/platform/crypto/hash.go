// Package crypto holds AES-GCM, argon2id and random helpers.
package crypto

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argonTime        uint32 = 3
	argonMemory      uint32 = 64 * 1024
	argonThreads     uint8  = 2
	argonKeyLenBytes        = 32
	argonSaltLen            = 16
)

// HashSecret returns an argon2id PHC string suitable for passwords and PINs.
func HashSecret(secret string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("generate salt: %w", err)
	}
	key := argon2.IDKey([]byte(secret), salt, argonTime, argonMemory, argonThreads, uint32(argonKeyLenBytes))
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key)), nil
}

// VerifySecret compares a secret with an encoded argon2id hash in constant time.
func VerifySecret(encoded, secret string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var memory, timeCost uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &timeCost, &threads); err != nil {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}
	if len(want) != argonKeyLenBytes {
		return false
	}
	got := argon2.IDKey([]byte(secret), salt, timeCost, memory, threads, uint32(argonKeyLenBytes))
	return subtle.ConstantTimeCompare(got, want) == 1
}

var ErrEmptySecret = errors.New("secret must not be empty")
