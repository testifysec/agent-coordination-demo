package m19

import "testing"

func TestF_disjoint_m19(t *testing.T) {
	if F_disjoint_m19() != 1 {
		t.Fatal("bad")
	}
}
