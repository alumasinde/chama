package phone

import "testing"

func TestNormalize(t *testing.T) {
	tests := []struct {
		raw  string
		want string
		ok   bool
	}{
		{"0712 345 678", "+254712345678", true},
		{"+254712345678", "+254712345678", true},
		{"254712345678", "+254712345678", true},
		{"0712-345-678", "+254712345678", true},
		{"0112345678", "+254112345678", true},
		{"0812345678", "", false},
		{"071234567", "", false},
		{"+255712345678", "", false},
		{"", "", false},
	}
	for _, tt := range tests {
		got, err := Normalize(tt.raw)
		if tt.ok != (err == nil) {
			t.Fatalf("Normalize(%q) err = %v, want ok=%v", tt.raw, err, tt.ok)
		}
		if got != tt.want {
			t.Fatalf("Normalize(%q) = %q, want %q", tt.raw, got, tt.want)
		}
	}
}

func TestMask(t *testing.T) {
	if got := Mask("+254712345678"); got != "+2547****5678" {
		t.Fatalf("Mask = %q", got)
	}
	if got := MaskAll("text +254712345678 and +254798765432"); got != "text +2547****5678 and +2547****5432" {
		t.Fatalf("MaskAll = %q", got)
	}
}
