package rotation

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/notifications"
	"github.com/chama/chama/backend/internal/platform/httpx"
)

func (s *Service) Payout(ctx context.Context, groupID int64, cyclePublicID uuid.UUID,
	actorID int64, in PayoutInput) (PayoutResult, error) {
	slotID, err := uuid.Parse(strings.TrimSpace(in.SlotID))
	if err != nil {
		return PayoutResult{}, httpx.Validation(map[string]string{"slot_id": "Choose a rotation slot."})
	}
	channel := strings.TrimSpace(in.Channel)
	if !manualChannels[channel] {
		return PayoutResult{}, httpx.Validation(map[string]string{
			"channel": "Choose mpesa_manual, cash, bank_transfer or other.",
		})
	}
	reference := "ROT-" + timeReference()
	if in.Reference != nil && strings.TrimSpace(*in.Reference) != "" {
		reference = strings.TrimSpace(*in.Reference)
	}
	result, err := s.repo.Payout(ctx, groupID, cyclePublicID, slotID, actorID, channel, reference)
	switch {
	case errors.Is(err, ErrCycleNotActive):
		return PayoutResult{}, httpx.Conflict("cycle_not_active", "Only an active cycle can pay out.")
	case errors.Is(err, ErrSlotPaid):
		return PayoutResult{}, httpx.Conflict("slot_already_paid", "That turn has already been paid.")
	case errors.Is(err, ErrPayoutOutOfTurn):
		return PayoutResult{}, httpx.Unprocessable("payout_out_of_order",
			"Pay every earlier turn before this one.")
	case errors.Is(err, ErrNotFound):
		return PayoutResult{}, httpx.NotFound("Rotation slot not found.")
	case err != nil:
		return PayoutResult{}, err
	}
	s.notifyPayout(ctx, groupID, result)
	return result, nil
}

func (s *Service) notifyPayout(ctx context.Context, groupID int64, result PayoutResult) {
	if s.notifier == nil {
		return
	}
	_ = s.notifier.Notify(ctx, notifications.Event{
		UserID: result.MemberID, GroupID: &groupID, Type: "payment_received",
		Title:     "Rotation payout recorded",
		Body:      "Your rotation payout has been recorded in the group ledger.",
		Data:      map[string]any{"cycle_id": result.CycleID, "transaction_id": result.TransactionID},
		DedupeKey: "rotation-payout:" + result.TransactionID,
	})
	if result.NextMemberID != 0 {
		_ = s.notifier.Notify(ctx, notifications.Event{
			UserID: result.NextMemberID, GroupID: &groupID, Type: "rotation_turn",
			Title:     "Your rotation turn is next",
			Body:      "The previous member has been paid. Your payout is next.",
			Data:      map[string]any{"cycle_id": result.CycleID, "slot_id": result.NextSlotID},
			DedupeKey: "rotation-next:" + result.CycleID + ":" + result.NextSlotID,
		})
	}
}
