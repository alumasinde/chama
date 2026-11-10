package fines

import (
	"time"
)

type RuleView struct {
	FineType          string    `json:"fine_type"`
	CalculationMethod string    `json:"calculation_method"`
	AmountOrRate      string    `json:"amount_or_rate"`
	GraceDays         int16     `json:"grace_days"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type RuleInput struct {
	CalculationMethod string `json:"calculation_method"`
	AmountOrRate      string `json:"amount_or_rate"`
	GraceDays         int16  `json:"grace_days"`
}

type CreateInput struct {
	UserID string `json:"user_id"`
	Amount string `json:"amount"`
	Reason string `json:"reason"`
}

type WaiveInput struct {
	Reason string `json:"reason"`
}

type PayInput struct {
	Amount    string  `json:"amount"`
	Channel   string  `json:"channel"`
	Reference *string `json:"reference"`
}

type FineView struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	Member      string    `json:"member"`
	FineType    string    `json:"fine_type"`
	Amount      string    `json:"amount"`
	Reason      string    `json:"reason"`
	Status      string    `json:"status"`
	PeriodLabel *string   `json:"period_label"`
	AssessedOn  string    `json:"assessed_on"`
	WaiveReason *string   `json:"waive_reason"`
	Paid        bool      `json:"paid"`
	CreatedAt   time.Time `json:"created_at"`
}

type PaymentResult struct {
	Fine          FineView `json:"fine"`
	TransactionID string   `json:"transaction_id"`
}

type Period struct {
	Start time.Time
	End   time.Time
	Label string
}

type EvaluationResult struct {
	Groups  int   `json:"groups"`
	Created int64 `json:"fines_created"`
}

var fineTypes = map[string]bool{
	"late_contribution": true, "late_loan_repayment": true, "absence": true, "custom": true,
}

var fineStatuses = map[string]bool{"unpaid": true, "paid": true, "waived": true}

var manualChannels = map[string]bool{
	"mpesa_manual": true, "cash": true, "bank_transfer": true, "other": true,
}
