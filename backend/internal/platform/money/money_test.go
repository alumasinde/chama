package money

import "testing"

func TestParseAmount(t *testing.T) {
	tests := []struct {
		raw  string
		want Cents
		ok   bool
	}{
		{"1500", 150000, true},
		{"1500.5", 150050, true},
		{"1500.50", 150050, true},
		{"0.01", 1, true},
		{" 2000 ", 200000, true},
		{"1500.555", 0, false},
		{"0", 0, false},
		{"-10", 0, false},
		{"+10", 0, false},
		{"1,500", 0, false},
		{"abc", 0, false},
		{"1500.", 0, false},
		{"", 0, false},
	}
	for _, tt := range tests {
		got, err := ParseAmount(tt.raw)
		if (err == nil) != tt.ok {
			t.Fatalf("ParseAmount(%q) err = %v, want ok=%v", tt.raw, err, tt.ok)
		}
		if got != tt.want {
			t.Fatalf("ParseAmount(%q) = %d, want %d", tt.raw, got, tt.want)
		}
	}
}

func TestCentsString(t *testing.T) {
	if got := Cents(150050).String(); got != "1500.50" {
		t.Fatalf("String = %q", got)
	}
	if got := Cents(5).String(); got != "0.05" {
		t.Fatalf("String = %q", got)
	}
}
