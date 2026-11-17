package m15

import "testing"

func TestF_disjoint_m15(t *testing.T) {
	if F_disjoint_m15() != 1 {
		t.Fatal("bad")
	}
}
