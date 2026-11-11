package payments

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"

	"github.com/chama/chama/backend/internal/platform/money"
)

// Mock settles nothing by itself; the dev callback endpoint drives settlement.
type Mock struct{}

func (m *Mock) Name() string { return "mock" }

// VerifyCredentials accepts anything: mock is development-only and never moves money.
func (m *Mock) VerifyCredentials(ctx context.Context, environment, consumerKey, consumerSecret string) error {
	return nil
}

func (m *Mock) RequestSTK(ctx context.Context, req STKRequest) (STKResponse, error) {
	if req.Amount <= 0 {
		return STKResponse{}, fmt.Errorf("%w: amount must be positive", ErrProviderUnavailable)
	}
	id, err := randomID()
	if err != nil {
		return STKResponse{}, err
	}
	return STKResponse{
		MerchantRequestID: "mock-merchant-" + id,
		CheckoutRequestID: "ws_CO_MOCK_" + id,
		CustomerMessage:   "Success. Request accepted for processing",
	}, nil
}

func randomID() (string, error) {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

var _ = money.Cents(0)
