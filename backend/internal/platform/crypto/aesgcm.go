package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"fmt"
)

// Cipher seals small secrets (M-Pesa credentials, national IDs) with a 32-byte key.
type Cipher struct {
	aead cipher.AEAD
}

func NewCipher(key []byte) (*Cipher, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("encryption key must be 32 bytes, got %d", len(key))
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("new aes cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("new gcm: %w", err)
	}
	return &Cipher{aead: aead}, nil
}

// Seal returns nonce||ciphertext; aad binds the value to its tenant and column.
func (c *Cipher) Seal(plaintext, aad []byte) ([]byte, error) {
	nonce := make([]byte, c.aead.NonceSize())
	if _, err := randomRead(nonce); err != nil {
		return nil, err
	}
	return c.aead.Seal(nonce, nonce, plaintext, aad), nil
}

// Open reverses Seal and fails if the aad does not match.
func (c *Cipher) Open(data, aad []byte) ([]byte, error) {
	if len(data) < c.aead.NonceSize() {
		return nil, errors.New("ciphertext too short")
	}
	nonce, ct := data[:c.aead.NonceSize()], data[c.aead.NonceSize():]
	out, err := c.aead.Open(nil, nonce, ct, aad)
	if err != nil {
		return nil, errors.New("decrypt failed")
	}
	return out, nil
}
