package rotation

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/chama/chama/backend/internal/platform/db"
	store "github.com/chama/chama/backend/internal/store"
)

var (
	ErrNotFound        = errors.New("rotation cycle not found")
	ErrAlreadyStarted  = errors.New("rotation cycle already started")
	ErrRequiresVote    = errors.New("rotation order must be voted on")
	ErrProposalClosed  = errors.New("rotation proposal is closed")
	ErrProposalOpen    = errors.New("a proposal is already open")
	ErrCycleNotActive  = errors.New("rotation cycle is not active")
	ErrSlotPaid        = errors.New("rotation slot already paid")
	ErrPayoutOutOfTurn = errors.New("earlier rotation slots are unpaid")
	ErrStateChanged    = errors.New("rotation state changed")
)

type Repository struct {
	q    *store.Queries
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{q: store.New(pool), pool: pool}
}

func (r *Repository) Cycles(ctx context.Context, groupID int64, limit int32) ([]store.ListRotationCyclesRow, error) {
	return r.q.ListRotationCycles(ctx, store.ListRotationCyclesParams{GroupID: groupID, RowLimit: limit})
}

func (r *Repository) Cycle(ctx context.Context, groupID int64, publicID uuid.UUID) (store.GetRotationCycleRow, error) {
	row, err := r.q.GetRotationCycle(ctx, store.GetRotationCycleParams{GroupID: groupID, PublicID: publicID})
	if errors.Is(err, pgx.ErrNoRows) {
		return store.GetRotationCycleRow{}, ErrNotFound
	}
	return row, err
}

type SlotSpec struct {
	MemberID   int64
	Position   int16
	PayoutDate string
}

func (r *Repository) Create(ctx context.Context, p store.CreateRotationCycleParams, slots []SlotSpec) (uuid.UUID, error) {
	var publicID uuid.UUID
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		row, err := q.CreateRotationCycle(ctx, p)
		if err != nil {
			return err
		}
		for _, s := range slots {
			if _, err := q.AddRotationSlot(ctx, store.AddRotationSlotParams{
				GroupID: p.GroupID, CycleID: row.ID, MemberID: s.MemberID,
				Position: s.Position, PayoutDate: s.PayoutDate,
			}); err != nil {
				return err
			}
		}
		publicID = row.PublicID
		return nil
	})
	return publicID, err
}

func (r *Repository) Start(ctx context.Context, groupID int64, publicID uuid.UUID, seed string) error {
	return db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		cycle, err := q.GetRotationCycleForUpdate(ctx, store.GetRotationCycleForUpdateParams{
			GroupID: groupID, PublicID: publicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if cycle.Status != "draft" {
			return ErrAlreadyStarted
		}
		if cycle.OrderingMode == "vote" {
			return ErrRequiresVote
		}
		members, err := q.GetRotationMembers(ctx, groupID)
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
		if cycle.OrderingMode == "random" {
			ids := make([]int64, 0, len(members))
			for _, m := range members {
				ids = append(ids, m.UserID)
			}
			if len(ids) != int(cycle.MemberCount) {
				return ErrStateChanged
			}
			for i, memberID := range DrawOrder(ids, seed) {
				if _, err := q.AddRotationSlot(ctx, store.AddRotationSlotParams{
					GroupID: groupID, CycleID: cycle.ID, MemberID: memberID,
					Position: int16(i + 1), PayoutDate: PayoutDate(startsOn, i, frequency),
				}); err != nil {
					return err
				}
			}
			if err := q.SetRotationDrawSeed(ctx, store.SetRotationDrawSeedParams{
				DrawSeed: &seed, CycleID: cycle.ID, GroupID: groupID,
			}); err != nil {
				return err
			}
		} else {
			existing, err := q.ListRotationSlotsForUpdate(ctx, store.ListRotationSlotsForUpdateParams{
				GroupID: groupID, CycleID: cycle.ID,
			})
			if err != nil {
				return err
			}
			if len(existing) != len(members) {
				return ErrStateChanged
			}
		}
		rows, err := q.UpdateRotationCycleStatus(ctx, store.UpdateRotationCycleStatusParams{
			Status: "active", CycleID: cycle.ID, GroupID: groupID, ExpectedStatus: "draft",
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrAlreadyStarted
		}
		return nil
	})
}

func (r *Repository) Members(ctx context.Context, groupID int64) ([]store.GetRotationMembersRow, error) {
	return r.q.GetRotationMembers(ctx, groupID)
}

func (r *Repository) Frequency(ctx context.Context, groupID int64) (string, error) {
	return r.q.GetGroupFrequency(ctx, groupID)
}

func (r *Repository) MemberID(ctx context.Context, groupID int64, publicID uuid.UUID) (int64, error) {
	row, err := r.q.GetActiveMemberByPublicID(ctx, store.GetActiveMemberByPublicIDParams{
		GroupID: groupID, PublicID: publicID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	return row.ID, err
}

func (r *Repository) Proposals(ctx context.Context, groupID int64, cyclePublicID uuid.UUID, limit int32) ([]store.ListRotationProposalsRow, error) {
	return r.q.ListRotationProposals(ctx, store.ListRotationProposalsParams{
		GroupID: groupID, CyclePublicID: cyclePublicID, RowLimit: limit,
	})
}

func (r *Repository) Slots(ctx context.Context, groupID, cycleID int64) ([]store.ListRotationSlotsRow, error) {
	return r.q.ListRotationSlots(ctx, store.ListRotationSlotsParams{GroupID: groupID, CycleID: cycleID})
}

func (r *Repository) My(ctx context.Context, userID int64, limit int32) ([]store.ListMyRotationRow, error) {
	return r.q.ListMyRotation(ctx, store.ListMyRotationParams{UserID: userID, RowLimit: limit})
}

func (r *Repository) Payout(ctx context.Context, groupID int64, cyclePublicID uuid.UUID,
	slotPublicID uuid.UUID, actorID int64, channel, reference string) (PayoutResult, error) {
	var out PayoutResult
	err := db.WithTx(ctx, r.pool, func(q *store.Queries) error {
		cycle, err := q.GetRotationCycleForUpdate(ctx, store.GetRotationCycleForUpdateParams{
			GroupID: groupID, PublicID: cyclePublicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if cycle.Status != "active" {
			return ErrCycleNotActive
		}
		slot, err := q.GetRotationSlot(ctx, store.GetRotationSlotParams{
			GroupID: groupID, PublicID: slotPublicID,
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if slot.CyclePublicID != cycle.PublicID {
			return ErrNotFound
		}
		if slot.PayoutTransactionID != nil {
			return ErrSlotPaid
		}
		slots, err := q.ListRotationSlotsForUpdate(ctx, store.ListRotationSlotsForUpdateParams{
			GroupID: groupID, CycleID: cycle.ID,
		})
		if err != nil {
			return err
		}
		for _, s := range slots {
			if s.Position >= slot.Position {
				break
			}
			if s.PayoutTransactionID == nil {
				return ErrPayoutOutOfTurn
			}
		}
		tx, err := q.CreateTransaction(ctx, store.CreateTransactionParams{
			GroupID: groupID, UserID: slot.MemberID, TransactionType: "rotation_payout",
			Channel: channel, AmountCents: cycle.ContributionCents,
			Narration: "Rotation payout: " + cycle.Name,
		})
		if err != nil {
			return err
		}
		settled, err := q.SettleTransaction(ctx, store.SettleTransactionParams{
			Status: "completed", ReferenceCode: &reference, ID: tx.ID,
		})
		if err != nil {
			return err
		}
		rows, err := q.MarkRotationSlotPaid(ctx, store.MarkRotationSlotPaidParams{
			PayoutTransactionID: &settled.ID, SlotID: slot.ID, GroupID: groupID,
		})
		if err != nil {
			return err
		}
		if rows == 0 {
			return ErrSlotPaid
		}
		counts, err := q.CountRotationSlots(ctx, store.CountRotationSlotsParams{
			GroupID: groupID, CycleID: cycle.ID,
		})
		if err != nil {
			return err
		}
		if counts.Total > 0 && counts.Paid == counts.Total {
			if _, err := q.UpdateRotationCycleStatus(ctx, store.UpdateRotationCycleStatusParams{
				Status: "completed", CycleID: cycle.ID, GroupID: groupID, ExpectedStatus: "active",
			}); err != nil {
				return err
			}
		}
		out = PayoutResult{CycleID: cycle.PublicID.String(), SlotID: slot.PublicID.String(),
			TransactionID: settled.PublicID.String(), MemberID: slot.MemberID}
		for _, s := range slots {
			if s.Position > slot.Position && s.PayoutTransactionID == nil {
				out.NextSlotID = s.PublicID.String()
				out.NextMemberID = s.MemberID
				break
			}
		}
		return nil
	})
	return out, err
}

// PayoutDate spaces turns by the chama's own contribution cadence.
func PayoutDate(startsOn time.Time, index int, frequency string) string {
	date := startsOn
	switch frequency {
	case "weekly":
		date = date.AddDate(0, 0, 7*index)
	case "biweekly":
		date = date.AddDate(0, 0, 14*index)
	case "quarterly":
		date = date.AddDate(0, 3*index, 0)
	default:
		date = date.AddDate(0, index, 0)
	}
	return date.Format("2006-01-02")
}
