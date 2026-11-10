package loans

import (
	"time"

	"github.com/chama/chama/backend/internal/platform/money"
)

type SettingsView struct {
	AllowLoans         bool       `json:"allow_loans"`
	InterestRate       string     `json:"interest_rate"`
	InterestMethod     string     `json:"interest_method"`
	MaxMultiple        string     `json:"max_multiple_of_savings"`
	MaxTermMonths      int16      `json:"max_term_months"`
	GuarantorsRequired int16      `json:"guarantors_required"`
	UpdatedAt          *time.Time `json:"updated_at,omitempty"`
}

type SettingsInput struct {
	InterestRate       string `json:"interest_rate"`
	InterestMethod     string `json:"interest_method"`
	MaxMultiple        string `json:"max_multiple_of_savings"`
	MaxTermMonths      int16  `json:"max_term_months"`
	GuarantorsRequired int16  `json:"guarantors_required"`
	AllowLoans         *bool  `json:"allow_loans"`
}

type GuarantorInput struct {
	UserID string `json:"user_id"`
	Amount string `json:"amount"`
}

type ApplyInput struct {
	Amount     string           `json:"amount"`
	TermMonths int16            `json:"term_months"`
	Purpose    string           `json:"purpose"`
	Guarantors []GuarantorInput `json:"guarantors"`
}

type GuarantorView struct {
	UserID      string     `json:"user_id"`
	DisplayName string     `json:"display_name"`
	Amount      string     `json:"amount"`
	Status      string     `json:"status"`
	RespondedAt *time.Time `json:"responded_at"`
}

type ApprovalView struct {
	ApproverID  string    `json:"approver_id"`
	DisplayName string    `json:"display_name"`
	Decision    string    `json:"decision"`
	Comment     *string   `json:"comment"`
	CreatedAt   time.Time `json:"created_at"`
}

type InstallmentView struct {
	Number    int16   `json:"installment_no"`
	DueDate   string  `json:"due_date"`
	Principal string  `json:"principal_due"`
	Interest  string  `json:"interest_due"`
	Paid      string  `json:"paid_amount"`
	Total     string  `json:"total_due"`
	PaidAt    *string `json:"paid_at"`
}

type LoanView struct {
	ID             string          `json:"id"`
	BorrowerID     string          `json:"user_id"`
	Borrower       string          `json:"borrower"`
	Principal      string          `json:"principal"`
	InterestRate   string          `json:"interest_rate"`
	InterestMethod string          `json:"interest_method"`
	TermMonths     int16           `json:"term_months"`
	Status         string          `json:"status"`
	TotalInterest  string          `json:"total_interest"`
	TotalPayable   string          `json:"total_payable"`
	PaidToDate     string          `json:"paid_to_date"`
	Outstanding    string          `json:"outstanding"`
	Purpose        string          `json:"purpose"`
	RequestedAt    time.Time       `json:"requested_at"`
	ApprovedAt     *time.Time      `json:"approved_at"`
	DisbursedAt    *time.Time      `json:"disbursed_at"`
	Guarantors     []GuarantorView `json:"guarantors"`
	Approvals      []ApprovalView  `json:"approvals"`
}

type DecisionInput struct {
	Decision string  `json:"decision"`
	Comment  *string `json:"comment"`
}

type GuaranteeDecisionInput struct {
	Decision string `json:"decision"`
}

type DisburseInput struct {
	Channel   string  `json:"channel"`
	Reference *string `json:"reference"`
}

type RepaymentInput struct {
	Amount    string  `json:"amount"`
	Channel   string  `json:"channel"`
	Reference *string `json:"reference"`
}

type RepaymentView struct {
	LoanID         string `json:"loan_id"`
	Amount         string `json:"amount"`
	PaidToDate     string `json:"paid_to_date"`
	Outstanding    string `json:"outstanding"`
	Status         string `json:"status"`
	TransactionID  string `json:"transaction_id,omitempty"`
	InstallmentsPA int    `json:"installments_touched"`
}

var manualChannels = map[string]bool{
	"mpesa_manual": true, "cash": true, "bank_transfer": true, "other": true,
}

func centsString(c int64) string { return money.Cents(c).String() }
