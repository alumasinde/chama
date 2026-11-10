package rotation

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/chama/chama/backend/internal/platform/httpx"
	store "github.com/chama/chama/backend/internal/store"
)

func (s *Service) Propose(ctx context.Context, groupID int64, cyclePublicID uuid.UUID,
	actorID int64, in ProposalInput) (ProposalView, error) {
	cycle, err := s.repo.Cycle(ctx, groupID, cyclePublicID)
	if errors.Is(err, ErrNotFound) {
		return ProposalView{}, httpx.NotFound("Rotation cycle not found.")
	}
	if err != nil {
		return ProposalView{}, err
	}
	if cycle.Status != "draft" || cycle.OrderingMode != "vote" {
		return ProposalView{}, httpx.Conflict("cycle_not_votable",
			"Only a draft cycle using vote ordering can take a proposal.")
	}
	closes := in.ClosesAt.UTC()
	now := time.Now().UTC()
	if closes.IsZero() || !closes.After(now) || closes.After(now.AddDate(0, 0, 30)) {
		return ProposalView{}, httpx.Validation(map[string]string{
			"closes_at": "Choose a time in the next 30 days.",
		})
	}
	quorum := int16(60)
	if in.QuorumPercent != nil {
		quorum = *in.QuorumPercent
	}
	if quorum < 1 || quorum > 100 {
		return ProposalView{}, httpx.Validation(map[string]string{"quorum_percent": "Use 1 to 100."})
	}
	_, byPublic, err := s.activeMembers(ctx, groupID)
	if err != nil {
		return ProposalView{}, err
	}
	order, err := resolveOrder(in.Slots, byPublic, len(byPublic))
	if err != nil {
		return ProposalView{}, err
	}
	publicID, err := s.repo.CreateProposal(ctx, groupID, cycle.ID, actorID, quorum, closes, order)
	if errors.Is(err, ErrProposalOpen) {
		return ProposalView{}, httpx.Conflict("proposal_already_open", "A proposal is already open for this cycle.")
	}
	if err != nil {
		return ProposalView{}, err
	}
	return s.Proposal(ctx, groupID, publicID, actorID)
}

func (s *Service) Proposal(ctx context.Context, groupID int64, publicID uuid.UUID, requesterID int64) (ProposalView, error) {
	row, err := s.repo.Proposal(ctx, groupID, publicID)
	if errors.Is(err, ErrNotFound) {
		return ProposalView{}, httpx.NotFound("Rotation proposal not found.")
	}
	if err != nil {
		return ProposalView{}, err
	}
	tallyRow, err := s.repo.Tally(ctx, row.ID)
	if err != nil {
		return ProposalView{}, err
	}
	needed := (int32(row.EligibleMembers)*int32(row.QuorumPercent) + 99) / 100
	tally := TallyView{For: tallyRow.ForCount, Against: tallyRow.AgainstCount,
		Abstain: tallyRow.AbstainCount, Total: tallyRow.TotalCount,
		Eligible: row.EligibleMembers, Needed: needed}
	view := ProposalView{
		ID: row.PublicID.String(), CycleID: row.CyclePublicID.String(), Status: row.Status,
		ProposedBy: row.ProposedByFirstName + " " + row.ProposedByLastName,
		QuorumPct:  row.QuorumPercent, OpensAt: row.OpensAt, ClosesAt: row.ClosesAt,
		ClosedAt: row.ClosedAt, Tally: tally,
	}
	if len(row.Result) > 0 {
		var result TallyView
		if json.Unmarshal(row.Result, &result) == nil {
			result.Eligible = row.EligibleMembers
			result.Needed = needed
			view.Result = &result
		}
	}
	if vote, err := s.repo.VoteByMember(ctx, row.ID, requesterID); err == nil {
		view.MyVote = &VoteView{Choice: vote.Choice, CastAt: vote.CastAt}
	}
	slots, err := s.repo.ProposalSlots(ctx, groupID, row.ID)
	if err != nil {
		return ProposalView{}, err
	}
	view.Slots = make([]SlotView, 0, len(slots))
	for _, slot := range slots {
		view.Slots = append(view.Slots, SlotView{
			UserID: slot.UserPublicID.String(), Member: slot.FirstName + " " + slot.LastName,
			Position: slot.Position,
		})
	}
	return view, nil
}

func (s *Service) Vote(ctx context.Context, groupID int64, publicID uuid.UUID, memberID int64, in VoteInput) (ProposalView, error) {
	choice := strings.TrimSpace(in.Choice)
	if !voteChoices[choice] {
		return ProposalView{}, httpx.Validation(map[string]string{"choice": "Choose for, against or abstain."})
	}
	if err := s.repo.Vote(ctx, groupID, publicID, memberID, choice); err != nil {
		switch {
		case errors.Is(err, ErrProposalClosed):
			return ProposalView{}, httpx.Conflict("proposal_closed", "Voting for this proposal has closed.")
		case errors.Is(err, ErrNotFound):
			return ProposalView{}, httpx.NotFound("Rotation proposal not found.")
		default:
			return ProposalView{}, err
		}
	}
	return s.Proposal(ctx, groupID, publicID, memberID)
}

func (s *Service) Close(ctx context.Context, groupID int64, publicID uuid.UUID, actorID int64) (ProposalView, error) {
	outcome, err := s.repo.Close(ctx, groupID, publicID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return ProposalView{}, httpx.NotFound("Rotation proposal not found.")
		}
		return ProposalView{}, err
	}
	if outcome.Passed {
		s.notifyCycleStarted(ctx, groupID, outcome.CycleID)
	}
	return s.Proposal(ctx, groupID, publicID, actorID)
}

// CloseExpired is the nightly job entry point; closing is idempotent per proposal.
func (s *Service) CloseExpired(ctx context.Context) (int, error) {
	rows, err := s.repo.Expired(ctx, 200)
	if err != nil {
		return 0, err
	}
	closed := 0
	for _, row := range rows {
		outcome, err := s.repo.Close(ctx, row.GroupID, row.PublicID)
		if err != nil && !errors.Is(err, ErrStateChanged) {
			return closed, err
		}
		if outcome.Passed {
			s.notifyCycleStarted(ctx, row.GroupID, outcome.CycleID)
		}
		closed++
	}
	return closed, nil
}

// EvaluateVote applies the quorum and majority rules in one testable place.
func EvaluateVote(eligible, quorumPercent int16, forVotes, against, abstain int32) (TallyView, bool, bool) {
	needed := (int32(eligible)*int32(quorumPercent) + 99) / 100
	total := forVotes + against + abstain
	quorumMet := total >= needed
	passed := quorumMet && forVotes > against
	return TallyView{For: forVotes, Against: against, Abstain: abstain,
		Total: total, Eligible: eligible, Needed: needed}, passed, quorumMet
}

var _ = store.TallyRotationVotesRow{}
