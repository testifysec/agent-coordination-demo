package m11

import "testing"

func TestF_disjoint_m11(t *testing.T) {
	if F_disjoint_m11() != 1 {
		t.Fatal("bad")
	}
}
