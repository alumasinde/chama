package auth

import "testing"

func TestValidatePIN(t *testing.T) {
	tests := []struct {
		name    string
		pin     string
		wantErr bool
	}{
		{"unremarkable pin", "4826", false},
		{"too short", "123", true},
		{"too long", "12345", true},
		{"letters", "12a4", true},
		{"repeated digits", "7777", true},
		{"ascending run", "3456", true},
		{"descending run", "8765", true},
		{"common pin", "1234", true},
		{"blocklist pin", "2580", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePIN(tt.pin)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ValidatePIN(%q) error = %v, wantErr %v", tt.pin, err, tt.wantErr)
			}
		})
	}
}

func TestValidatePassword(t *testing.T) {
	tests := []struct {
		name     string
		password string
		wantErr  bool
	}{
		{"ok", "correct horse battery", false},
		{"short", "short", true},
		{"leading space", " leading", true},
		{"too long", string(make([]byte, 129)), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePassword(tt.password)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ValidatePassword error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
