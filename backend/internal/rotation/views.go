package rotation

import (
	"strconv"
	"time"

	"github.com/chama/chama/backend/internal/platform/money"
	store "github.com/chama/chama/backend/internal/store"
)

func cycleView(row store.GetRotationCycleRow) CycleView {
	return CycleView{
		ID: row.PublicID.String(), Name: row.Name, Status: row.Status, OrderingMode: row.OrderingMode,
		Contribution: money.Cents(row.ContributionCents).String(), StartsOn: row.StartsOn,
		MemberCount: row.MemberCount, DrawSeed: row.DrawSeed, SlotCount: row.SlotCount,
		PaidCount: row.PaidCount, CreatedAt: row.CreatedAt, CompletedAt: row.CompletedAt,
		Slots: []SlotView{},
	}
}

func listCycleView(row store.ListRotationCyclesRow) CycleView {
	return CycleView{
		ID: row.PublicID.String(), Name: row.Name, Status: row.Status, OrderingMode: row.OrderingMode,
		Contribution: money.Cents(row.ContributionCents).String(), StartsOn: row.StartsOn,
		MemberCount: row.MemberCount, DrawSeed: row.DrawSeed, SlotCount: row.SlotCount,
		PaidCount: row.PaidCount, CreatedAt: row.CreatedAt, CompletedAt: row.CompletedAt,
		Slots: []SlotView{},
	}
}

func listSlotView(row store.ListRotationSlotsRow) SlotView {
	view := SlotView{
		ID: row.PublicID.String(), UserID: row.UserPublicID.String(),
		Member: row.FirstName + " " + row.LastName, Position: row.Position,
		PayoutDate: row.PayoutDate, Paid: row.PayoutTransactionPublicID.Valid,
	}
	if row.PayoutTransactionPublicID.Valid {
		value := uuidString(row.PayoutTransactionPublicID.Bytes)
		view.PayoutTxID = &value
	}
	return view
}

func uuidString(b [16]byte) string {
	raw := make([]byte, 16)
	copy(raw, b[:])
	return formatUUID(raw)
}

func formatUUID(b []byte) string {
	const hex = "0123456789abcdef"
	out := make([]byte, 36)
	pos := 0
	for i, v := range b {
		if i == 4 || i == 6 || i == 8 || i == 10 {
			out[pos] = '-'
			pos++
		}
		out[pos] = hex[v>>4]
		out[pos+1] = hex[v&15]
		pos += 2
	}
	return string(out)
}

func timeReference() string { return strconv.FormatInt(time.Now().UTC().UnixNano(), 10) }
