package rotation

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

func (r *Repository) VoteByMember(ctx context.Context, proposalID, memberID int64) (store.GetRotationVoteRow, error) {
	row, err := r.q.GetRotationVote(ctx, store.GetRotationVoteParams{
		ProposalID: proposalID, MemberID: memberID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetRotationVoteRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) Tally(ctx context.Context, proposalID int64) (store.TallyRotationVotesRow, error) {
	return r.q.TallyRotationVotes(ctx, proposalID)
}

// CreateProposal validates and writes the proposed order in one transaction.
func (r *Repository) CreateProposal(ctx context.Context, groupID, cycleID, proposerID int64,
	quorum int16, closes time.Time, order []int64) (uuid.UUID, error) {
	var publicID uuid.UUID
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		cycle, err := q.GetRotationCycleByIDForUpdate(ctx, store.GetRotationCycleByIDForUpdateParams{
			GroupID: groupID, CycleID: cycleID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if cycle.Status != "draft" || cycle.OrderingMode != "vote" {
			return ErrStateChanged
		}
		row, err := q.CreateRotationProposal(ctx, store.CreateRotationProposalParams{
			GroupID: groupID, CycleID: cycle.ID, ProposedBy: proposerID,
			QuorumPercent: quorum, ClosesAt: closes,
		})
		if err != nil {
			return err
		}
		for i, memberID := range order {
			if err := q.AddRotationProposalSlot(ctx, store.AddRotationProposalSlotParams{
				ProposalID: row.ID, GroupID: groupID, Position: int16(i + 1), MemberID: memberID,
			}); err != nil {
				return err
			}
		}
		publicID = row.PublicID
		return nil
	})
	return publicID, err
}

func (r *Repository) Proposal(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetRotationProposalRow, error) {
	row, err := r.q.GetRotationProposal(ctx, store.GetRotationProposalParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetRotationProposalRow{}, ErrNotFound
	}
	return row, err
}

func (r *Repository) ProposalSlots(ctx context.Context, groupID, proposalID int64) ([]store.ListRotationProposalSlotsRow, error) {
	return r.q.ListRotationProposalSlots(ctx, store.ListRotationProposalSlotsParams{
		GroupID: groupID, ProposalID: proposalID,
	})
}

func (r *Repository) Vote(ctx context.Context, groupID int64, publicID uuid.UUID, memberID int64, choice string) error {
	return db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		proposal, err := q.GetRotationProposalForUpdate(ctx, store.GetRotationProposalForUpdateParams{
			GroupID: groupID, PublicID: publicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if proposal.Status != "open" || !time.Now().UTC().Before(proposal.ClosesAt) {
			return ErrProposalClosed
		}
		return q.UpsertRotationVote(ctx, store.UpsertRotationVoteParams{
			GroupID: groupID, ProposalID: proposal.ID, MemberID: memberID, Choice: choice,
		})
	})
}

type CloseOutcome struct {
	ProposalID int64
	CycleID    uuid.UUID
	Status     string
	Passed     bool
	Tally      TallyView
}

// Close tallies once; a passing vote starts the draft cycle with the proposed order.
func (r *Repository) Close(ctx context.Context, groupID int64, publicID uuid.UUID) (CloseOutcome, error) {
	var out CloseOutcome
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		proposal, err := q.GetRotationProposalForUpdate(ctx, store.GetRotationProposalForUpdateParams{
			GroupID: groupID, PublicID: publicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		out.ProposalID = proposal.ID
		if proposal.ClosedAt != nil {
			out.Status = proposal.Status
			return nil
		}
		tally, err := q.TallyRotationVotes(ctx, proposal.ID)
		if err != nil {
			return err
		}
		tallyView, passed, quorumMet := EvaluateVote(proposal.EligibleMembers, proposal.QuorumPercent,
			tally.ForCount, tally.AgainstCount, tally.AbstainCount)
		status := "rejected"
		if passed {
			status = "passed"
		}
		result, _ := json.Marshal(map[string]any{
			"for": tally.ForCount, "against": tally.AgainstCount, "abstain": tally.AbstainCount,
			"eligible": proposal.EligibleMembers, "quorum_met": quorumMet,
		})
		rows, err := q.CloseRotationProposal(ctx, store.CloseRotationProposalParams{
			Status: status, Result: result, ProposalID: proposal.ID, GroupID: groupID,
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrStateChanged
		}
		out.Status, out.Passed = status, passed
		out.Tally = tallyView
		if !passed {
			return nil
		}
		cycle, err := q.GetRotationCycleByIDForUpdate(ctx, store.GetRotationCycleByIDForUpdateParams{
			GroupID: groupID, CycleID: proposal.CycleID,
		})
		if err != nil {
			return err
		}
		if cycle.Status != "draft" {
			return ErrStateChanged
		}
		out.CycleID = cycle.PublicID
		slots, err := q.ListRotationProposalMemberIDs(ctx, store.ListRotationProposalMemberIDsParams{
			GroupID: groupID, ProposalID: proposal.ID,
		})
		if err != nil {
			return err
		}
		frequency, err := q.GetGroupFrequency(ctx, groupID)
		if err != nil {
			return err
		}
		startsOn, err := time.Parse("2006-01-02", cycle.StartsOn)
		if err != nil {
			return err
		}
		for i, slot := range slots {
			if _, err := q.AddRotationSlot(ctx, store.AddRotationSlotParams{
				GroupID: groupID, CycleID: cycle.ID, MemberID: slot.MemberID,
				Position: slot.Position, PayoutDate: PayoutDate(startsOn, i, frequency),
			}); err != nil {
				return err
			}
		}
		rows, err = q.UpdateRotationCycleStatus(ctx, store.UpdateRotationCycleStatusParams{
			Status: "active", CycleID: cycle.ID, GroupID: groupID, ExpectedStatus: "draft",
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrStateChanged
		}
		return nil
	})
	return out, err
}

func (r *Repository) Expired(ctx context.Context, limit int32) ([]store.ListExpiredRotationProposalsRow, error) {
	return r.q.ListExpiredRotationProposals(ctx, limit)
}
