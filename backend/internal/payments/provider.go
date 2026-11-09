// Package payments triggers STK Push, settles callbacks, and writes the ledger.
package payments

import (
	"context"
	"errors"

	"github.com/chama/chama/backend/internal/platform/money"
)

var ErrProviderUnavailable = errors.New("payment provider unavailable")

type STKRequest struct {
	ShortcodeType    string
	Shortcode        string
	Passkey          string
	ConsumerKey      string
	ConsumerSecret   string
	Environment      string
	Amount           money.Cents
	PhoneNumber      string
	CallbackURL      string
	AccountReference string
	Description      string
}

type STKResponse struct {
	MerchantRequestID string
	CheckoutRequestID string
	CustomerMessage   string
}

// Provider is the seam between our ledger and M-Pesa.
type Provider interface {
	RequestSTK(ctx context.Context, req STKRequest) (STKResponse, error)
	Name() string
}
