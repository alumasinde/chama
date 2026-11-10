package rotation

import "time"

type CycleView struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	Status       string     `json:"status"`
	OrderingMode string     `json:"ordering_mode"`
	Contribution string     `json:"contribution_amount"`
	StartsOn     string     `json:"starts_on"`
	MemberCount  int16      `json:"member_count"`
	DrawSeed     *string    `json:"draw_seed"`
	SlotCount    int32      `json:"slot_count"`
	PaidCount    int32      `json:"paid_count"`
	CreatedAt    time.Time  `json:"created_at"`
	CompletedAt  *time.Time `json:"completed_at"`
	Slots        []SlotView `json:"slots"`
}

type SlotView struct {
	ID         string  `json:"id"`
	UserID     string  `json:"user_id"`
	Member     string  `json:"member"`
	Position   int16   `json:"position"`
	PayoutDate string  `json:"payout_date"`
	PayoutTxID *string `json:"payout_transaction_id"`
	Paid       bool    `json:"paid"`
}

type CreateInput struct {
	Name         string   `json:"name"`
	OrderingMode string   `json:"ordering_mode"`
	Contribution string   `json:"contribution_amount"`
	StartsOn     string   `json:"starts_on"`
	Slots        []string `json:"slots"`
}

type ProposalInput struct {
	Slots         []string  `json:"slots"`
	ClosesAt      time.Time `json:"closes_at"`
	QuorumPercent *int16    `json:"quorum_percent"`
}

type VoteInput struct {
	Choice string `json:"choice"`
}

type VoteView struct {
	Choice string    `json:"choice"`
	CastAt time.Time `json:"cast_at"`
}

type TallyView struct {
	For      int32 `json:"for"`
	Against  int32 `json:"against"`
	Abstain  int32 `json:"abstain"`
	Total    int32 `json:"total"`
	Eligible int16 `json:"eligible"`
	Needed   int32 `json:"needed"`
}

type ProposalView struct {
	ID         string     `json:"id"`
	CycleID    string     `json:"cycle_id"`
	Status     string     `json:"status"`
	ProposedBy string     `json:"proposed_by"`
	QuorumPct  int16      `json:"quorum_percent"`
	OpensAt    time.Time  `json:"opens_at"`
	ClosesAt   time.Time  `json:"closes_at"`
	ClosedAt   *time.Time `json:"closed_at"`
	Result     *TallyView `json:"result"`
	Tally      TallyView  `json:"tally"`
	MyVote     *VoteView  `json:"my_vote"`
	Slots      []SlotView `json:"slots"`
}

type ProposalSummaryView struct {
	ID        string     `json:"id"`
	Status    string     `json:"status"`
	QuorumPct int16      `json:"quorum_percent"`
	Eligible  int16      `json:"eligible_members"`
	For       int32      `json:"for"`
	Against   int32      `json:"against"`
	Abstain   int32      `json:"abstain"`
	Total     int32      `json:"total"`
	Needed    int32      `json:"needed"`
	OpensAt   time.Time  `json:"opens_at"`
	ClosesAt  time.Time  `json:"closes_at"`
	ClosedAt  *time.Time `json:"closed_at"`
	CreatedAt time.Time  `json:"created_at"`
}

type PayoutInput struct {
	SlotID    string  `json:"slot_id"`
	Channel   string  `json:"channel"`
	Reference *string `json:"reference"`
}

type PayoutResult struct {
	CycleID       string `json:"cycle_id"`
	SlotID        string `json:"slot_id"`
	TransactionID string `json:"transaction_id"`
	NextSlotID    string `json:"next_slot_id,omitempty"`
	MemberID      int64  `json:"-"`
	NextMemberID  int64  `json:"-"`
}

type MyRotationView struct {
	GroupID    string `json:"group_id"`
	GroupName  string `json:"group_name"`
	CycleID    string `json:"cycle_id"`
	CycleName  string `json:"cycle_name"`
	Position   int16  `json:"position"`
	PayoutDate string `json:"payout_date"`
	Paid       bool   `json:"paid"`
}

var manualChannels = map[string]bool{
	"mpesa_manual": true, "cash": true, "bank_transfer": true, "other": true,
}

var orderingModes = map[string]bool{"random": true, "manual": true, "vote": true}
var voteChoices = map[string]bool{"for": true, "against": true, "abstain": true}
