package m07

import "testing"

func TestF_disjoint_m07(t *testing.T) {
	if F_disjoint_m07() != 1 {
		t.Fatal("bad")
	}
}
