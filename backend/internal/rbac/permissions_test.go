package rbac

import "testing"

func TestCapabilities(t *testing.T) {
	tests := []struct {
		role string
		perm string
		want bool
	}{
		{"admin", PermMemberManage, true},
		{"admin", PermPaymentSettingsWrite, true},
		{"admin", PermPaymentRecord, true},
		{"treasurer", PermPaymentSettingsWrite, true},
		{"treasurer", PermPaymentRecord, true},
		{"treasurer", PermMemberManage, false},
		{"secretary", PermPaymentRecord, false},
		{"secretary", PermPaymentSettingsWrite, false},
		{"member", PermPaymentRecord, false},
		{"secretary", PermMemberRead, true},
		{"secretary", PermGroupUpdate, false},
		{"member", PermMemberRead, true},
		{"member", PermPaymentSettingsRead, false},
		{"unknown", PermGroupRead, false},
	}
	for _, tt := range tests {
		if got := Allows(tt.role, tt.perm); got != tt.want {
			t.Fatalf("Allows(%q, %q) = %v, want %v", tt.role, tt.perm, got, tt.want)
		}
	}
}

func TestRanksAndValidation(t *testing.T) {
	if Rank("admin") <= Rank("treasurer") {
		t.Fatal("admin must rank above treasurer")
	}
	if !ValidRole("treasurer") || ValidRole("owner") {
		t.Fatal("role validation is wrong")
	}
	if !ValidStatus("pending") || ValidStatus("deleted") {
		t.Fatal("status validation is wrong")
	}
}
