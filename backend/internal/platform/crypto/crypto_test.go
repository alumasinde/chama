package crypto

import (
	"bytes"
	"testing"
)

func TestHashSecretRoundTrip(t *testing.T) {
	encoded, err := HashSecret("4826")
	if err != nil {
		t.Fatalf("HashSecret: %v", err)
	}
	if !VerifySecret(encoded, "4826") {
		t.Fatal("correct secret rejected")
	}
	if VerifySecret(encoded, "4827") {
		t.Fatal("wrong secret accepted")
	}
	if VerifySecret("not-a-hash", "4826") {
		t.Fatal("malformed hash accepted")
	}
}

func TestCipherBindsAAD(t *testing.T) {
	cipher, err := NewCipher(bytes.Repeat([]byte{7}, 32))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}
	aad := []byte("group-1:passkey")
	sealed, err := cipher.Seal([]byte("secret-value"), aad)
	if err != nil {
		t.Fatalf("Seal: %v", err)
	}
	opened, err := cipher.Open(sealed, aad)
	if err != nil || string(opened) != "secret-value" {
		t.Fatalf("Open = %q, %v", opened, err)
	}
	if _, err := cipher.Open(sealed, []byte("group-2:passkey")); err == nil {
		t.Fatal("ciphertext opened under a different tenant")
	}
}

func TestCipherRejectsShortKey(t *testing.T) {
	if _, err := NewCipher([]byte("short")); err == nil {
		t.Fatal("expected a key length error")
	}
}

func TestDigitsKeepsLeadingZeros(t *testing.T) {
	for i := 0; i < 50; i++ {
		code, err := Digits(6)
		if err != nil {
			t.Fatalf("Digits: %v", err)
		}
		if len(code) != 6 {
			t.Fatalf("Digits length = %d (%q)", len(code), code)
		}
	}
}
