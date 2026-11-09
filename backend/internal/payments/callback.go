package payments

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/groups"
	"github.com/chama/chama/backend/internal/platform/httpx"
)

type callbackPayload struct {
	Body struct {
		STKCallback struct {
			MerchantRequestID string `json:"MerchantRequestID"`
			CheckoutRequestID string `json:"CheckoutRequestID"`
			ResultCode        int    `json:"ResultCode"`
			ResultDesc        string `json:"ResultDesc"`
			CallbackMetadata  struct {
				Item []struct {
					Name  string `json:"Name"`
					Value any    `json:"Value"`
				} `json:"Item"`
			} `json:"CallbackMetadata"`
		} `json:"stkCallback"`
	} `json:"Body"`
}

// HandleCallback authenticates the per-group secret and settles once.
func (s *Service) HandleCallback(ctx context.Context, groupPublicID, secret string, raw []byte) error {
	publicID, err := uuid.Parse(groupPublicID)
	if err != nil {
		return httpx.Forbidden("")
	}
	group, err := s.groups.Find(ctx, publicID)
	if errors.Is(err, groups.ErrNotFound) {
		return httpx.Forbidden("")
	}
	if err != nil {
		return err
	}
	expected, err := s.groups.CallbackSecret(ctx, group.ID)
	if err != nil {
		return err
	}
	if subtle.ConstantTimeCompare([]byte(expected), []byte(secret)) != 1 {
		return httpx.Forbidden("")
	}

	var payload callbackPayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil
	}
	stk := payload.Body.STKCallback
	if strings.TrimSpace(stk.CheckoutRequestID) == "" {
		return nil
	}
	status := "failed"
	if stk.ResultCode == 0 {
		status = "completed"
	}
	receipt := ""
	for _, item := range stk.CallbackMetadata.Item {
		if item.Name == "MpesaReceiptNumber" {
			receipt = strings.TrimSpace(fmt.Sprint(item.Value))
		}
	}
	if status == "completed" && receipt == "" {
		s.log.ErrorContext(ctx, "callback missing receipt", "checkout", stk.CheckoutRequestID)
		return nil
	}

	if err := s.repo.Settle(ctx, SettleInput{
		GroupID:     group.ID,
		CheckoutID:  stk.CheckoutRequestID,
		Status:      status,
		ResultCode:  fmt.Sprintf("%d", stk.ResultCode),
		ResultDesc:  stk.ResultDesc,
		Receipt:     receipt,
		RawCallback: raw,
	}); err != nil {
		s.log.ErrorContext(ctx, "settle callback", "checkout", stk.CheckoutRequestID, "error", err)
		return err
	}
	return nil
}
