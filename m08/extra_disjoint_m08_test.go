package m08

import "testing"

func TestF_disjoint_m08(t *testing.T) {
	if F_disjoint_m08() != 1 {
		t.Fatal("bad")
	}
}
