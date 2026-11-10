package rotation

import (
	"crypto/sha256"
	"sort"
	"strconv"
)

// DrawOrder sorts members by SHA-256(seed:memberID). The stored seed makes the
// result reproducible, so the committee can verify the published draw later.
func DrawOrder(memberIDs []int64, seed string) []int64 {
	type entry struct {
		id   int64
		hash [32]byte
	}
	entries := make([]entry, 0, len(memberIDs))
	for _, id := range memberIDs {
		entries = append(entries, entry{
			id:   id,
			hash: sha256.Sum256([]byte(seed + ":" + strconv.FormatInt(id, 10))),
		})
	}
	sort.SliceStable(entries, func(i, j int) bool {
		for k := range entries[i].hash {
			if entries[i].hash[k] != entries[j].hash[k] {
				return entries[i].hash[k] < entries[j].hash[k]
			}
		}
		return entries[i].id < entries[j].id
	})
	out := make([]int64, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.id)
	}
	return out
}
