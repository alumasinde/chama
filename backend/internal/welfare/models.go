package welfare

import "time"

type FundView struct {
	Configured    bool       `json:"configured"`
	Name          string     `json:"name"`
	MonthlyAmount string     `json:"monthly_amount"`
	IsActive      bool       `json:"is_active"`
	Balance       string     `json:"balance"`
	Contributed   string     `json:"contributed_total"`
	PaidOut       string     `json:"paid_out_total"`
	UpdatedAt     *time.Time `json:"updated_at"`
}

type FundInput struct {
	Name          string `json:"name"`
	MonthlyAmount string `json:"monthly_amount"`
	IsActive      *bool  `json:"is_active"`
}

type ContributionInput struct {
	UserID      string  `json:"user_id"`
	Amount      string  `json:"amount"`
	PeriodLabel *string `json:"period_label"`
	Channel     string  `json:"channel"`
	Reference   *string `json:"reference"`
}

type ContributionView struct {
	ID            string    `json:"id"`
	UserID        string    `json:"user_id"`
	Member        string    `json:"member"`
	Amount        string    `json:"amount"`
	PeriodLabel   string    `json:"period_label"`
	TransactionID *string   `json:"transaction_id"`
	CreatedAt     time.Time `json:"created_at"`
}

type ClaimInput struct {
	Amount string `json:"amount"`
	Reason string `json:"reason"`
}

type ClaimDecisionInput struct {
	Decision string  `json:"decision"`
	Comment  *string `json:"comment"`
}

type ClaimPayoutInput struct {
	Channel   string  `json:"channel"`
	Reference *string `json:"reference"`
}

type ClaimView struct {
	ID                  string     `json:"id"`
	UserID              string     `json:"user_id"`
	Member              string     `json:"member"`
	Amount              string     `json:"amount"`
	Reason              string     `json:"reason"`
	Status              string     `json:"status"`
	RequestedAt         time.Time  `json:"requested_at"`
	DecidedAt           *time.Time `json:"decided_at"`
	DecidedBy           *string    `json:"decided_by"`
	Comment             *string    `json:"comment"`
	PayoutTransactionID *string    `json:"payout_transaction_id"`
}

type PayoutResult struct {
	Claim         ClaimView `json:"claim"`
	TransactionID string    `json:"transaction_id"`
}

var manualChannels = map[string]bool{
	"mpesa_manual": true, "cash": true, "bank_transfer": true, "other": true,
}

var claimStatuses = map[string]bool{"pending": true, "approved": true, "rejected": true, "paid": true}
