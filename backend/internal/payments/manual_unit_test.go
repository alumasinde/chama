package payments

import "testing"

func TestValidMpesaCode(t *testing.T) {
	good := []string{"SLK7XQ2P9D", "QWE123", "123456789012345678901234"}
	for _, code := range good {
		if !validMpesaCode(code) {
			t.Fatalf("validMpesaCode(%q) = false, want true", code)
		}
	}
	bad := []string{"", "ABC", "SLK-7XQ", "SLK 7XQ2", "slk7xq2p9d", "1234567890123456789012345"}
	for _, code := range bad {
		if validMpesaCode(code) {
			t.Fatalf("validMpesaCode(%q) = true, want false", code)
		}
	}
}
