package loans

import (
	"context"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/notifications"
	"github.com/chama/chama/backend/internal/platform/money"
)

func (s *Service) notifyApplication(ctx context.Context, groupID, borrowerID int64,
	publicID uuid.UUID, purpose string, invites []NewGuarantor) {
	if s.notifier == nil {
		return
	}
	for _, invite := range invites {
		_ = s.notifier.Notify(ctx, notifications.Event{
			UserID: invite.UserID, GroupID: &groupID, Type: "guarantor_request",
			Title:     "Guarantee request",
			Body:      "You were asked to guarantee " + money.Cents(invite.AmountCents).String() + " for " + purpose + ".",
			Data:      map[string]any{"loan_id": publicID.String()},
			DedupeKey: "guarantor:" + publicID.String() + ":" + itoa(int(invite.UserID)),
		})
	}
	_ = s.notifier.Notify(ctx, notifications.Event{
		UserID: borrowerID, GroupID: &groupID, Type: "loan_update",
		Title:     "Loan application received",
		Body:      "Your loan request is being reviewed.",
		Data:      map[string]any{"loan_id": publicID.String()},
		DedupeKey: "loan:" + publicID.String() + ":applied",
	})
}

func (s *Service) notifyLoanUpdate(ctx context.Context, groupID, userID int64,
	publicID uuid.UUID, title, body, suffix string) {
	if s.notifier == nil {
		return
	}
	_ = s.notifier.Notify(ctx, notifications.Event{
		UserID: userID, GroupID: &groupID, Type: "loan_update",
		Title: title, Body: body,
		Data:      map[string]any{"loan_id": publicID.String()},
		DedupeKey: "loan:" + publicID.String() + ":" + suffix,
	})
}
