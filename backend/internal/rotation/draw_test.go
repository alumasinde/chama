package rotation

import (
	"reflect"
	"sort"
	"testing"
)

func TestDrawOrderIsDeterministicAndComplete(t *testing.T) {
	members := []int64{11, 22, 33, 44, 55, 66}
	first := DrawOrder(members, "seed-alpha")
	second := DrawOrder(members, "seed-alpha")
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same seed produced different orders: %v vs %v", first, second)
	}
	got := append([]int64(nil), first...)
	sort.Slice(got, func(i, j int) bool { return got[i] < got[j] })
	want := append([]int64(nil), members...)
	sort.Slice(want, func(i, j int) bool { return want[i] < want[j] })
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("draw is not a permutation: %v", first)
	}
	other := DrawOrder(members, "seed-beta")
	if reflect.DeepEqual(first, other) {
		t.Fatal("different seeds produced the same order")
	}
}
