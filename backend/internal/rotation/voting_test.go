package rotation

import "testing"

func TestEvaluateVote(t *testing.T) {
	tests := []struct {
		name                       string
		eligible, quorum           int16
		forVotes, against, abstain int32
		passed, quorumMet          bool
	}{
		{"simple majority", 10, 60, 7, 2, 1, true, true},
		{"tie fails", 10, 60, 4, 4, 2, false, true},
		{"quorum short", 10, 60, 4, 0, 1, false, false},
		{"abstain counts for quorum only", 10, 50, 3, 2, 0, true, true},
		{"unanimous", 4, 100, 4, 0, 0, true, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, passed, quorumMet := EvaluateVote(tt.eligible, tt.quorum, tt.forVotes, tt.against, tt.abstain)
			if passed != tt.passed || quorumMet != tt.quorumMet {
				t.Fatalf("passed=%v quorum=%v, want %v/%v", passed, quorumMet, tt.passed, tt.quorumMet)
			}
		})
	}
}
