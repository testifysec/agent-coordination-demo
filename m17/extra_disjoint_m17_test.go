package m17

import "testing"

func TestF_disjoint_m17(t *testing.T) {
	if F_disjoint_m17() != 1 {
		t.Fatal("bad")
	}
}
