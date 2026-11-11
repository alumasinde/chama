package payments

import (
	"context"
	"errors"
	"fmt"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
	"github.com/chama/chama/backend/internal/platform/money"
	"github.com/chama/chama/backend/internal/platform/phone"
	"github.com/chama/chama/backend/internal/users"
)

// TestResult is what a setup test prompt returned. No ledger row is written.
type TestResult struct {
	CheckoutRequestID string `json:"checkout_request_id"`
	Amount            string `json:"amount"`
	Message           string `json:"message"`
}

// SendTestCollection prompts the manager for KES 1 to prove the shortcode, passkey and
// environment work together before members are asked to pay. Safaricom rejects a mismatched
// passkey on this request, so an accepted prompt is the proof. The KES 1 lands in the chama's
// own account and is deliberately kept out of the ledger.
func (s *Service) SendTestCollection(ctx context.Context, user users.User, group groups.Group) (TestResult, error) {
	if s.provider == nil {
		return TestResult{}, httpx.NewError(503, "provider_unavailable", "Payments are not configured.")
	}
	credentials, err := s.groups.Credentials(ctx, group.ID)
	if errors.Is(err, groups.ErrNotFound) {
		return TestResult{}, httpx.Unprocessable("payment_settings_missing",
			"Save the chama's M-Pesa details first.")
	}
	if err != nil {
		return TestResult{}, err
	}
	phoneNumber, err := phone.Normalize(user.PhoneNumber)
	if err != nil {
		return TestResult{}, httpx.Validation(map[string]string{"phone_number": phone.ErrInvalid.Error()})
	}
	amount := money.Cents(100)
	callbackURL := fmt.Sprintf("%s/api/v1/payments/mpesa/callback/%s/%s",
		s.baseURL, group.PublicID, credentials.CallbackSecret)
	response, err := s.provider.RequestSTK(ctx, STKRequest{
		ShortcodeType:    credentials.ShortcodeType,
		Shortcode:        credentials.Shortcode,
		Passkey:          credentials.Passkey,
		ConsumerKey:      credentials.ConsumerKey,
		ConsumerSecret:   credentials.ConsumerSecret,
		Environment:      credentials.Environment,
		Amount:           amount,
		PhoneNumber:      phoneNumber,
		CallbackURL:      callbackURL,
		AccountReference: "SETUP-TEST",
		Description:      "Chama setup test",
	})
	if err != nil {
		s.log.ErrorContext(ctx, "setup stk failed", "provider", s.provider.Name(), "error", err)
		return TestResult{}, httpx.NewError(502, "provider_error",
			"M-Pesa did not accept the test prompt. Check the shortcode, passkey and environment.")
	}
	return TestResult{
		CheckoutRequestID: response.CheckoutRequestID,
		Amount:            amount.String(),
		Message:           "M-Pesa prompt sent. Enter your PIN to confirm.",
	}, nil
}
